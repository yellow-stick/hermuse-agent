import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'activity.dart';
import 'agents.dart';
import 'automations.dart';
import 'onboarding.dart' show restClientProvider, setupChatTitle;
import 'product.dart';
import 'saved_sign_in.dart';

part 'providers.g.dart';

/// Opens a transport to an instance; overridden in tests.
typedef TransportFactory = Future<HermesTransport> Function(HermesInstance);

/// How long an unused connection stays open.
const connectionLinger = Duration(minutes: 5);

/// Connection failures are shown to the user, who retries explicitly; the
/// transport already reconnects on its own once established.
Duration? _noRetry(int retryCount, Object error) => null;

/// The app's database. Must be overridden (`openNativeDatabase` on Flutter,
/// `openWebDatabase` on the web).
@Riverpod(keepAlive: true)
HermuseDatabase hermuseDatabase(Ref ref) =>
    throw UnimplementedError('override hermuseDatabaseProvider');

/// Platform secret storage. Must be overridden (keystore on Flutter,
/// `MemorySecretStore` on the web).
@Riverpod(keepAlive: true)
SecretStore secretStore(Ref ref) =>
    throw UnimplementedError('override secretStoreProvider');

@Riverpod(keepAlive: true)
http.Client httpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
TransportFactory transportFactory(Ref ref) =>
    (instance) => DashboardTransport.connect(
      instance: instance,
      secrets: ref.read(secretStoreProvider),
      httpClient: ref.read(httpClientProvider),
    );

/// The instance registry, loaded from the database.
@Riverpod(keepAlive: true)
Future<HermesRegistry> registry(Ref ref) async {
  final registry = HermesRegistry(
    DriftInstanceStore(ref.watch(hermuseDatabaseProvider)),
    ref.watch(secretStoreProvider),
  );
  await registry.load();
  return registry;
}

/// Proves candidate credentials by opening (and closing) a throwaway
/// connection; throws the connection's [HermesException] when refused.
typedef TrialConnect = Future<void> Function(
  HermesInstance instance,
  SecretStore secrets,
);

/// Overridden in widget tests, where no real socket can open.
@Riverpod(keepAlive: true)
TrialConnect trialConnect(Ref ref) => (instance, secrets) async {
  final transport = await DashboardTransport.connect(
    instance: instance,
    secrets: secrets,
    httpClient: ref.read(httpClientProvider),
  );
  await transport.close();
};

/// Credential maintenance for registered instances.
@Riverpod(keepAlive: true)
InstanceAuth instanceAuth(Ref ref) => InstanceAuth._(ref);

final class InstanceAuth {
  InstanceAuth._(this._ref);
  final Ref _ref;

  /// Signs a password instance in again (rotated password, expired web
  /// session): proves [username]/[password] on a throwaway connection first,
  /// then stores them and reopens the shared connection. Throws the
  /// connection's [HermesException] (e.g. [HermesAuthFailed]) and stores
  /// nothing when they are rejected.
  Future<void> signIn(
    String instanceId, {
    required String username,
    required String password,
  }) async {
    final registry = await _ref.read(registryProvider.future);
    final instance = registry.byId(instanceId);
    if (instance == null) throw StateError('unknown instance $instanceId');
    if (instance.auth != AuthMethod.password) {
      throw StateError('${instance.label} does not use a password');
    }
    final trial = MemorySecretStore();
    await trial.write(instanceId, SecretKeys.username, username);
    await trial.write(instanceId, SecretKeys.password, password);
    await _ref.read(trialConnectProvider)(instance, trial);
    final secrets = _ref.read(secretStoreProvider);
    await secrets.write(instanceId, SecretKeys.username, username);
    await secrets.write(instanceId, SecretKeys.password, password);
    _ref
      ..invalidate(savedSignInProvider(instanceId))
      ..invalidate(connectionProvider(instanceId));
  }

  /// Registers [candidate] once [secrets] (keyed by [SecretKeys]: the
  /// session token of a [AuthMethod.loopbackToken] instance, or username and
  /// password) open a throwaway connection. Nothing is stored when the
  /// connection refuses them (its [HermesException], e.g.
  /// [HermesAuthFailed]) or the registry rejects the instance
  /// ([DuplicateInstance]); the secrets go to the [SecretStore] only.
  /// [replaceExisting] updates an existing registration only after the same
  /// connection proof, preserving its identity when changing its login method.
  Future<void> add(
    HermesInstance candidate, {
    required Map<String, String> secrets,
    bool replaceExisting = false,
  }) async {
    final trial = MemorySecretStore();
    for (final MapEntry(:key, :value) in secrets.entries) {
      await trial.write(candidate.id, key, value);
    }
    if (candidate.auth == AuthMethod.loopbackToken) {
      // A wrong token only fails the `/api/ws` upgrade (403), which reads as
      // an unreachable host: prove it on an authenticated route first so a
      // refusal is a [HermesAuthFailed].
      await HermesRestClient(
        _ref.read(httpClientProvider),
        baseUrl: candidate.baseUrl,
        sessionToken: secrets[SecretKeys.sessionToken],
      ).getJson('/api/config');
    }
    await _ref.read(trialConnectProvider)(candidate, trial);
    // Registry first: secrets written before a failed add would be orphaned
    // under the new id.
    final registry = await _ref.read(registryProvider.future);
    if (replaceExisting) {
      await registry.update(candidate);
    } else {
      await registry.add(candidate);
    }
    final store = _ref.read(secretStoreProvider);
    for (final MapEntry(:key, :value) in secrets.entries) {
      await store.write(candidate.id, key, value);
    }
    if (replaceExisting) {
      _ref
        ..invalidate(savedSignInProvider(candidate.id))
        ..invalidate(connectionProvider(candidate.id));
    }
  }
}

/// Registered instances, in user order.
@riverpod
Stream<List<HermesInstance>> instances(Ref ref) =>
    ref.watch(hermuseDatabaseProvider).watchInstances();

/// A profile's separate connection, opened lazily and closed
/// [connectionLinger] after its last listener goes away. Credentials remain
/// keyed by the real registered instance id.
@Riverpod(retry: _noRetry)
Future<HermesConnection> connection(
  Ref ref,
  String instanceId, {
  String profile = 'default',
}) async {
  final link = ref.keepAlive();
  Timer? linger;
  ref.onCancel(() => linger = Timer(connectionLinger, link.close));
  ref.onResume(() => linger?.cancel());
  HermesTransport? transport;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    linger?.cancel();
    unawaited(transport?.close());
  });
  final registry = await ref.watch(registryProvider.future);
  final instance = registry.byId(instanceId);
  if (instance == null) throw StateError('unknown instance $instanceId');
  transport = await ref.read(transportFactoryProvider)(
    instance.copyWith(profile: () => profile),
  );
  if (disposed) {
    unawaited(transport.close());
    throw StateError('connection to $instanceId disposed while opening');
  }
  return HermesConnection(instanceId, transport);
}

/// Live [ConnectionState] of an instance (drives status badges).
@riverpod
Stream<ConnectionState> connectionState(
  Ref ref,
  String instanceId, {
  String profile = 'default',
}) async* {
  final transport = (await ref.watch(
    connectionProvider(instanceId, profile: profile).future,
  )).transport;
  yield transport.currentState;
  yield* transport.state;
}

String _profileKey(String prefix, String instanceId, String profile) =>
    profile == 'default'
    ? '$prefix:$instanceId'
    : '$prefix:$instanceId:profile:${Uri.encodeComponent(profile)}';

String _mainKey(String instanceId, String profile) =>
    _profileKey('main_session', instanceId, profile);

String _openKey(String instanceId, String profile) =>
    _profileKey('open_thread', instanceId, profile);

String _selectedProfileKey(String instanceId) => 'agent_profile:$instanceId';

/// Named legacy instance keys are moved once by the database migration.
Future<String?> _profileSetting(
  HermuseDatabase db,
  String prefix,
  String instanceId,
  String profile,
) => db.readSetting(_profileKey(prefix, instanceId, profile));

Future<String> _mainSessionOf(
  HermuseDatabase db,
  String instanceId,
  String profile,
) async {
  final saved = await _profileSetting(db, 'main_session', instanceId, profile);
  if (saved != null) return saved;
  final legacy = await db.readSetting(ActiveThread._key);
  if (legacy == null) return '';
  final json = jsonDecode(legacy) as Map<String, Object?>;
  final sessionId = json['session_id'] as String? ?? '';
  final registered = (await db.loadInstances())
      .where((i) => i.id == instanceId)
      .firstOrNull;
  final legacyProfile =
      json['profile'] as String? ?? registered?.profile ?? 'default';
  if (json['instance_id'] != instanceId ||
      legacyProfile != profile ||
      sessionId.isEmpty) {
    return '';
  }
  await db.writeSetting(_mainKey(instanceId, profile), sessionId);
  return sessionId;
}

/// The selected agent's main chat, persisted across launches. An uncreated
/// main chat keeps its draft provider key while its stored id is saved.
@Riverpod(keepAlive: true)
class ActiveThread extends _$ActiveThread {
  static const _key = 'active_thread';
  final _opened = <(String, String), ThreadRef>{};
  int _selection = 0;

  @override
  Future<ThreadRef?> build() async {
    final db = ref.watch(hermuseDatabaseProvider);
    final registry = await ref.watch(registryProvider.future);
    final raw = await db.readSetting(_key);
    String? instanceId;
    String? profile;
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final saved = json['instance_id'] as String;
      if (registry.byId(saved) != null) {
        instanceId = saved;
        profile = json['profile'] as String?;
      }
    }
    instanceId ??= registry.primary?.id;
    if (instanceId == null) return null;
    profile ??=
        await db.readSetting(_selectedProfileKey(instanceId)) ??
        registry.byId(instanceId)?.profile ??
        'default';
    return _restore(db, instanceId, profile);
  }

  Future<ThreadRef> _restore(
    HermuseDatabase db,
    String instanceId,
    String profile,
  ) async {
    final key = (instanceId, profile);
    if (_opened[key] case final opened?) return opened;
    final thread = ThreadRef(
      instanceId: instanceId,
      profile: profile,
      sessionId: await _mainSessionOf(db, instanceId, profile),
    );
    return _opened.putIfAbsent(key, () => thread);
  }

  /// Restores the last selected agent of this registered instance.
  Future<void> openInstance(String instanceId) async {
    final selection = ++_selection;
    final db = ref.read(hermuseDatabaseProvider);
    final registry = await ref.read(registryProvider.future);
    final profile =
        await db.readSetting(_selectedProfileKey(instanceId)) ??
        registry.byId(instanceId)?.profile ??
        'default';
    if (!ref.mounted || selection != _selection) return;
    await _openAgent(instanceId, profile, selection);
  }

  /// Opens or restores one agent without changing the registered instance.
  Future<void> openAgent(String instanceId, String profile) =>
      _openAgent(instanceId, profile, ++_selection);

  Future<void> _openAgent(
    String instanceId,
    String profile,
    int selection,
  ) async {
    final db = ref.read(hermuseDatabaseProvider);
    final thread = await _restore(db, instanceId, profile);
    if (!ref.mounted || selection != _selection) return;
    await db.writeSettings({
      _key: jsonEncode({'instance_id': instanceId, 'profile': profile}),
      _selectedProfileKey(instanceId): profile,
    });
    if (!ref.mounted || selection != _selection) return;
    state = AsyncData(thread);
  }

  /// Opens onboarding as this profile's main chat, or as a side chat.
  Future<void> openSetup(ThreadRef setup) async {
    if (setup.isNew) return openAgent(setup.instanceId, setup.profile);
    final db = ref.read(hermuseDatabaseProvider);
    final main = await _mainSessionOf(db, setup.instanceId, setup.profile);
    if (main.isEmpty || main == setup.sessionId) {
      await db.writeSetting(
        _mainKey(setup.instanceId, setup.profile),
        setup.sessionId,
      );
      _opened.remove((setup.instanceId, setup.profile));
    } else {
      await db.upsertSession(
        SessionRow(
          instanceId: setup.instanceId,
          profile: setup.profile,
          sessionId: setup.sessionId,
          title: setupChatTitle,
          parentId: main,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          archived: false,
        ),
      );
      await db.writeSetting(
        _openKey(setup.instanceId, setup.profile),
        setup.sessionId,
      );
      final thread =
          _opened[(setup.instanceId, setup.profile)] ??
          ThreadRef(
            instanceId: setup.instanceId,
            profile: setup.profile,
            sessionId: main,
          );
      ref.invalidate(chatSessionProvider(thread));
    }
    await openAgent(setup.instanceId, setup.profile);
  }

  /// Persists a newly created main session without changing selection.
  /// A late callback from a background agent must never steal the screen.
  Future<void> mainCreated(ThreadRef created) => ref
      .read(hermuseDatabaseProvider)
      .writeSetting(
        _mainKey(created.instanceId, created.profile),
        created.sessionId,
      );
}

/// The chat of the main session [thread] (main chat + its side chats),
/// opened on the thread that was on screen last time.
@Riverpod(keepAlive: true)
Future<ChatController> chatSession(Ref ref, ThreadRef thread) async {
  final db = ref.watch(hermuseDatabaseProvider);
  // Keep the connection open while the chat lives, without rebuilding it.
  ref.listen(
    connectionProvider(thread.instanceId, profile: thread.profile),
    (_, _) {},
  );
  final registry = await ref.watch(registryProvider.future);
  final sides = thread.isNew
      ? const <SessionRow>[]
      : await db.loadSideChats(
          thread.instanceId,
          thread.sessionId,
          profile: thread.profile,
        );
  final controller = ChatController(
    connections: _ProviderConnections(ref),
    ref: thread,
    observer: _DatabaseObserver(
      db,
      (created) {
        if (ref.mounted) {
          unawaited(
            ref.read(activeThreadProvider.notifier).mainCreated(created),
          );
        }
      },
      (changed, tool) {
        if (!ref.mounted) return;
        if (tool == null) {
          // A finished turn is a new task row.
          final tasks = tasksProvider(
            changed.instanceId,
            profile: changed.profile,
          );
          if (ref.exists(tasks)) ref.read(tasks.notifier).turnEnded();
        }
        if (tool == null || tool == 'feed_post') {
          ref.invalidate(
            feedProvider(changed.instanceId, profile: changed.profile),
          );
        }
        if (tool == null || tool == 'cronjob_manage') {
          final provider = automationsProvider(
            changed.instanceId,
            profile: changed.profile,
          );
          // An unopened tab reads fresh data when it is first watched.
          if (ref.exists(provider)) {
            ref.read(provider.notifier).refreshFromChat();
          }
        }
      },
    ),
    agentName:
        ref
            .read(agentProfileProvider(thread.instanceId, thread.profile))
            ?.displayName ??
        (thread.profile == 'default'
            ? registry.byId(thread.instanceId)?.label ?? 'Hermes'
            : thread.profile),
    sideThreads: [
      for (final s in sides)
        Thread(id: s.sessionId, title: s.title, startedAt: '', messages: []),
    ],
    initialThreadId: await _profileSetting(
      db,
      'open_thread',
      thread.instanceId,
      thread.profile,
    ),
    clarifyResults: (sessionId) async {
      if (!ref.mounted) return const {};
      final rest = await ref.read(
        restClientProvider(thread.instanceId, profile: thread.profile).future,
      );
      return clarifyResultsOf(
        await rest.getJson(
          '/api/sessions/${Uri.encodeComponent(sessionId)}/messages',
          {'limit': '500', 'order': 'latest'},
        ),
      );
    },
  );
  ref.listen(agentProfileProvider(thread.instanceId, thread.profile), (
    _,
    next,
  ) {
    if (next != null) controller.setAgentName(next.displayName);
  });
  ref.onDispose(controller.dispose);
  return controller;
}

/// Results of the `clarify` calls in a page of stored session messages
/// (`GET /api/sessions/{id}/messages`), by tool call id: the chat
/// transcript omits them, so a reloaded chat reads the user's answers here.
Map<String, Object?> clarifyResultsOf(Map<String, Object?> page) => {
  for (final m in (page['messages'] as List?) ?? const [])
    if (m is Map && m['role'] == 'tool' && m['tool_name'] == 'clarify')
      if (m['tool_call_id'] case final String id) id: m['content'],
};

/// Side chats of the main chat [main] as stored locally (pin and activity
/// order); empty until the main chat exists. [archived] lists the archive.
@riverpod
Stream<List<SessionRow>> sideChats(
  Ref ref,
  ThreadRef main, {
  bool archived = false,
}) => main.isNew
    ? Stream.value(const [])
    : ref
          .watch(hermuseDatabaseProvider)
          .watchSideChats(
            main.instanceId,
            main.sessionId,
            archived: archived,
            profile: main.profile,
          );

/// Last activity of the main chat [main] (null until it exists).
@riverpod
Stream<DateTime?> mainChatUpdatedAt(Ref ref, ThreadRef main) => main.isNew
    ? Stream.value(null)
    : ref
          .watch(hermuseDatabaseProvider)
          .watchSession(main.instanceId, main.sessionId, profile: main.profile)
          .map(
            (row) => row == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
          );

/// One row of the side chat list.
final class SideChatEntry {
  const SideChatEntry({
    required this.threadId,
    required this.title,
    required this.pinned,
    this.updatedAt,
  });

  final String threadId;

  /// Empty until the agent titles the chat (show "New side chat").
  final String title;
  final bool pinned;

  /// Last activity, null for a side chat not saved yet (draft).
  final DateTime? updatedAt;
}

/// The side chat list shown for [state]: its side threads, pinned first then
/// by last activity ([rows] from [sideChatsProvider]); drafts not yet saved
/// come first, newest on top.
List<SideChatEntry> sideChatEntries(ChatState state, List<SessionRow> rows) {
  final byId = {for (final r in rows) r.sessionId: r};
  final order = {for (final (i, r) in rows.indexed) r.sessionId: i};
  final sides = state.sideThreads.toList();
  final drafts = [
    for (final t in sides.reversed)
      if (!byId.containsKey(t.id)) t,
  ];
  final saved = [
    for (final t in sides)
      if (byId.containsKey(t.id)) t,
  ]..sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  return [
    for (final t in drafts)
      SideChatEntry(threadId: t.id, title: t.title, pinned: false),
    for (final t in saved)
      SideChatEntry(
        threadId: t.id,
        title: t.title.isNotEmpty ? t.title : byId[t.id]!.title,
        pinned: byId[t.id]!.pinnedAt != null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(byId[t.id]!.updatedAt),
      ),
  ];
}

/// Pins (on top of the side chat list) or unpins a side chat. Local only.
Future<void> setSideChatPinned(
  HermuseDatabase db,
  ThreadRef sideChat, {
  required bool pinned,
}) => db.setSessionPinned(
  sideChat.instanceId,
  sideChat.sessionId,
  pinned ? DateTime.now().millisecondsSinceEpoch : null,
  profile: sideChat.profile,
);

/// A result of [chatSearch].
final class ChatSearchHit {
  const ChatSearchHit({
    required this.threadId,
    required this.threadTitle,
    required this.text,
    required this.isTitle,
    this.updatedAt,
  });

  /// Thread to open (the main chat or a side chat).
  final String threadId;

  /// "Main chat", the side chat title, or "" for an untitled side chat.
  final String threadTitle;

  /// The matching message, or the title for a title match.
  final String text;

  /// The side chat title matched (rather than a message).
  final bool isTitle;
  final DateTime? updatedAt;
}

/// Searches the main chat of [state] and its side chats: side chat titles
/// first, then cached messages (best match first). Only transcripts opened
/// or written on this device are cached, so only those are searchable.
Future<List<ChatSearchHit>> chatSearch(
  HermuseDatabase db,
  ChatController chat,
  String query, {
  int limit = 50,
}) async {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final state = chat.state;
  final main = state.mainThread;
  final rows = main.id.startsWith('draft-')
      ? const <SessionRow>[]
      : await db.loadSideChats(chat.instanceId, main.id, profile: chat.profile);
  final mainRow = main.id.startsWith('draft-')
      ? null
      : await db.loadSession(chat.instanceId, main.id, profile: chat.profile);
  final updated = {
    for (final r in [...rows, ?mainRow])
      r.sessionId: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
  };
  String titleOf(String id) => id == main.id
      ? 'Main chat'
      : state.threads.where((t) => t.id == id).firstOrNull?.title ?? '';
  final saved = [
    for (final t in state.threads)
      if (!t.id.startsWith('draft-')) t.id,
  ];
  final messages = await db.search(
    query,
    instanceId: chat.instanceId,
    profile: chat.profile,
    sessionIds: saved,
    limit: limit,
  );
  return [
    for (final t in state.sideThreads)
      if (t.title.toLowerCase().contains(needle))
        ChatSearchHit(
          threadId: t.id,
          threadTitle: t.title,
          text: t.title,
          isTitle: true,
          updatedAt: updated[t.id],
        ),
    for (final m in messages)
      ChatSearchHit(
        threadId: m.sessionId,
        threadTitle: titleOf(m.sessionId),
        text: m.bodyText,
        isTitle: false,
        updatedAt: updated[m.sessionId],
      ),
  ];
}

/// Chats panel preferences ("Keep chat panel visible" and the
/// resizable width), persisted in the settings table.
final class ChatPanelPrefs {
  const ChatPanelPrefs({this.pinned = false, this.width = defaultWidth});

  static const defaultWidth = 240.0;
  static const minWidth = 200.0;
  static const maxWidth = 400.0;

  /// Stays open after picking a thread.
  final bool pinned;
  final double width;
}

@Riverpod(keepAlive: true)
class ChatPanel extends _$ChatPanel {
  static const _pinnedKey = 'chat_panel_pinned';
  static const _widthKey = 'chat_panel_width';

  @override
  Future<ChatPanelPrefs> build() async {
    final db = ref.watch(hermuseDatabaseProvider);
    final width = double.tryParse(await db.readSetting(_widthKey) ?? '');
    return ChatPanelPrefs(
      pinned: await db.readSetting(_pinnedKey) == 'true',
      width: (width ?? ChatPanelPrefs.defaultWidth).clamp(
        ChatPanelPrefs.minWidth,
        ChatPanelPrefs.maxWidth,
      ),
    );
  }

  Future<void> setPinned(bool pinned) async {
    final current = state.value ?? const ChatPanelPrefs();
    state = AsyncData(ChatPanelPrefs(pinned: pinned, width: current.width));
    await ref.read(hermuseDatabaseProvider).writeSetting(_pinnedKey, '$pinned');
  }

  /// Sets the width (clamped); call [saveWidth] when the drag ends.
  void setWidth(double width) {
    final current = state.value ?? const ChatPanelPrefs();
    state = AsyncData(
      ChatPanelPrefs(
        pinned: current.pinned,
        width: width.clamp(ChatPanelPrefs.minWidth, ChatPanelPrefs.maxWidth),
      ),
    );
  }

  Future<void> saveWidth() => ref
      .read(hermuseDatabaseProvider)
      .writeSetting(
        _widthKey,
        '${(state.value ?? const ChatPanelPrefs()).width}',
      );
}

final class _ProviderConnections implements HermesConnections {
  _ProviderConnections(this._ref);
  final Ref _ref;

  @override
  Future<HermesConnection> connectionFor(
    String instanceId, {
    String profile = 'default',
  }) {
    final provider = connectionProvider(instanceId, profile: profile);
    if (_ref.read(provider).hasError) _ref.invalidate(provider);
    return _ref.read(provider.future);
  }
}

/// Mirrors chats into the local cache and refreshes their product surfaces.
final class _DatabaseObserver implements ChatObserver {
  _DatabaseObserver(this._db, this._mainCreated, this._productsChanged);
  final HermuseDatabase _db;

  /// Called when the main (non side) session gets its stored id.
  final void Function(ThreadRef) _mainCreated;

  final void Function(ThreadRef, String? tool) _productsChanged;

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  void sessionCreated(
    ThreadRef ref, {
    required String title,
    String? parentId,
  }) {
    if (parentId == null) _mainCreated(ref);
    unawaited(
      _db.upsertSession(
        SessionRow(
          instanceId: ref.instanceId,
          profile: ref.profile,
          sessionId: ref.sessionId,
          title: title,
          parentId: parentId,
          updatedAt: _now(),
          archived: false,
        ),
      ),
    );
  }

  @override
  void sessionTitled(ThreadRef ref, String title) {
    unawaited(
      _db.renameSession(
        ref.instanceId,
        ref.sessionId,
        title,
        profile: ref.profile,
      ),
    );
  }

  @override
  void turnEnded(ThreadRef ref) {
    // Also covers product changes made through terminal or delegated tools.
    _productsChanged(ref, null);
    unawaited(
      _db.touchSession(
        ref.instanceId,
        ref.sessionId,
        _now(),
        profile: ref.profile,
      ),
    );
  }

  @override
  void threadOpened(ThreadRef ref) {
    unawaited(
      _db.writeSetting(_openKey(ref.instanceId, ref.profile), ref.sessionId),
    );
  }

  @override
  void sessionArchived(ThreadRef ref, {required bool archived}) {
    unawaited(
      _db.setSessionArchived(
        ref.instanceId,
        ref.sessionId,
        archived: archived,
        profile: ref.profile,
      ),
    );
  }

  @override
  void sessionDeleted(ThreadRef ref) {
    unawaited(
      _db.deleteSession(ref.instanceId, ref.sessionId, profile: ref.profile),
    );
  }

  @override
  void toolCompleted(ThreadRef ref, String tool) => _productsChanged(ref, tool);

  @override
  void mainSessionChanged(ThreadRef main, {String? previousId}) {
    _mainCreated(main);
    if (previousId != null) unawaited(_fileUnder(main, previousId));
  }

  /// The main chat [previousId] gave way to [main]: it and its side chats
  /// become side chats of [main].
  Future<void> _fileUnder(ThreadRef main, String previousId) async {
    final previous = await _db.loadSession(
      main.instanceId,
      previousId,
      profile: main.profile,
    );
    await _db.reparentSideChats(
      main.instanceId,
      from: previousId,
      to: main.sessionId,
      profile: main.profile,
    );
    await _db.upsertSession(
      SessionRow(
        instanceId: main.instanceId,
        profile: main.profile,
        sessionId: previousId,
        title: previous == null || previous.title == mainThreadTitle
            ? ''
            : previous.title,
        parentId: main.sessionId,
        updatedAt: previous?.updatedAt ?? _now(),
        archived: false,
        pinnedAt: previous?.pinnedAt,
      ),
    );
  }

  /// Caches messages that carry a transcript row id (`row-<n>`); local
  /// placeholders are cached once the turn reports its persisted rows.
  @override
  void messagesSettled(ThreadRef ref, List<Message> messages) {
    final rows = [
      for (final m in messages)
        if (m.id.startsWith('row-') && int.tryParse(m.id.substring(4)) != null)
          MessageRow(
            instanceId: ref.instanceId,
            profile: ref.profile,
            sessionId: ref.sessionId,
            messageId: m.id,
            author: m.author.name,
            bodyText: m.plainText,
            createdAt: int.parse(m.id.substring(4)),
          ),
    ];
    if (rows.isNotEmpty) {
      unawaited(
        _db.cacheTranscript(
          ref.instanceId,
          ref.sessionId,
          rows,
          profile: ref.profile,
        ),
      );
    }
  }
}
