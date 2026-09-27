import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart' show setupChatTitle;

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
    _ref.invalidate(connectionProvider(instanceId));
  }
}

/// Registered instances, in user order.
@riverpod
Stream<List<HermesInstance>> instances(Ref ref) =>
    ref.watch(hermuseDatabaseProvider).watchInstances();

/// The shared connection of one instance, opened lazily and closed
/// [connectionLinger] after its last listener goes away.
@Riverpod(retry: _noRetry)
Future<HermesConnection> connection(Ref ref, String instanceId) async {
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
  transport = await ref.read(transportFactoryProvider)(instance);
  if (disposed) {
    unawaited(transport.close());
    throw StateError('connection to $instanceId disposed while opening');
  }
  return HermesConnection(instanceId, transport);
}

/// Live [ConnectionState] of an instance (drives status badges).
@riverpod
Stream<ConnectionState> connectionState(Ref ref, String instanceId) async* {
  final transport = (await ref.watch(connectionProvider(instanceId).future))
      .transport;
  yield transport.currentState;
  yield* transport.state;
}

/// Settings key of the main chat of [instanceId] (its stored session id).
String _mainKey(String instanceId) => 'main_session:$instanceId';

/// Settings key of the thread on screen for [instanceId] (main or side).
String _openKey(String instanceId) => 'open_thread:$instanceId';

/// The main chat of [instanceId]: its stored session id, or '' when it has
/// not been created yet (created on the first message).
///
/// Before main chats existed the conversation on screen was persisted as
/// `active_thread`; that conversation is adopted as the main chat.
Future<String> _mainSessionOf(HermuseDatabase db, String instanceId) async {
  final saved = await db.readSetting(_mainKey(instanceId));
  if (saved != null) return saved;
  final legacy = await db.readSetting(ActiveThread._key);
  if (legacy == null) return '';
  final json = jsonDecode(legacy) as Map<String, Object?>;
  final sessionId = json['session_id'] as String? ?? '';
  if (json['instance_id'] != instanceId || sessionId.isEmpty) return '';
  await db.writeSetting(_mainKey(instanceId), sessionId);
  return sessionId;
}

/// The main chat on screen: `ThreadRef(instance, mainSessionId)`, one main
/// chat per instance (every other thread is a side chat of it). Persisted across launches (settings table).
///
/// A main chat not created yet is `ThreadRef(instanceId, '')`; once its
/// session exists the stored id is persisted for the next launch while the
/// open chat keeps its provider key.
@Riverpod(keepAlive: true)
class ActiveThread extends _$ActiveThread {
  static const _key = 'active_thread';

  @override
  Future<ThreadRef?> build() async {
    final db = ref.watch(hermuseDatabaseProvider);
    final registry = await ref.watch(registryProvider.future);
    final raw = await db.readSetting(_key);
    String? instanceId;
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final saved = json['instance_id'] as String;
      if (registry.byId(saved) != null) instanceId = saved;
    }
    instanceId ??= registry.primary?.id;
    if (instanceId == null) return null;
    return ThreadRef(
      instanceId: instanceId,
      sessionId: await _mainSessionOf(db, instanceId),
    );
  }

  /// Opens the main chat of [instanceId].
  Future<void> openInstance(String instanceId) async {
    final db = ref.read(hermuseDatabaseProvider);
    final thread = ThreadRef(
      instanceId: instanceId,
      sessionId: await _mainSessionOf(db, instanceId),
    );
    state = AsyncData(thread);
    await _persist(thread);
  }

  /// Opens the onboarding conversation [setup]: it becomes the instance's
  /// main chat when there is none yet, otherwise a side chat of it that
  /// opens on screen.
  Future<void> openSetup(ThreadRef setup) async {
    if (setup.isNew) return openInstance(setup.instanceId);
    final db = ref.read(hermuseDatabaseProvider);
    final main = await _mainSessionOf(db, setup.instanceId);
    if (main.isEmpty || main == setup.sessionId) {
      await db.writeSetting(_mainKey(setup.instanceId), setup.sessionId);
    } else {
      await db.upsertSession(
        SessionRow(
          instanceId: setup.instanceId,
          sessionId: setup.sessionId,
          title: setupChatTitle,
          parentId: main,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          archived: false,
        ),
      );
      await db.writeSetting(_openKey(setup.instanceId), setup.sessionId);
      ref.invalidate(chatSessionProvider);
    }
    await openInstance(setup.instanceId);
  }

  /// Records the stored id of a main chat created from a draft.
  Future<void> mainCreated(ThreadRef created) async {
    final db = ref.read(hermuseDatabaseProvider);
    await db.writeSetting(_mainKey(created.instanceId), created.sessionId);
    await _persist(created);
  }

  Future<void> _persist(ThreadRef thread) => ref
      .read(hermuseDatabaseProvider)
      .writeSetting(_key, jsonEncode({'instance_id': thread.instanceId}));
}

/// The chat of the main session [thread] (main chat + its side chats),
/// opened on the thread that was on screen last time.
@riverpod
Future<ChatController> chatSession(Ref ref, ThreadRef thread) async {
  final db = ref.watch(hermuseDatabaseProvider);
  // Keep the connection open while the chat lives, without rebuilding it.
  ref.listen(connectionProvider(thread.instanceId), (_, _) {});
  final registry = await ref.watch(registryProvider.future);
  final sides = thread.isNew
      ? const <SessionRow>[]
      : await db.loadSideChats(thread.instanceId, thread.sessionId);
  final controller = ChatController(
    connections: _ProviderConnections(ref),
    ref: thread,
    observer: _DatabaseObserver(db, (created) {
      if (ref.mounted) {
        unawaited(ref.read(activeThreadProvider.notifier).mainCreated(created));
      }
    }),
    agentName: registry.byId(thread.instanceId)?.label ?? 'Hermes',
    sideThreads: [
      for (final s in sides)
        Thread(id: s.sessionId, title: s.title, startedAt: '', messages: []),
    ],
    initialThreadId: await db.readSetting(_openKey(thread.instanceId)),
  );
  ref.onDispose(controller.dispose);
  return controller;
}

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
          .watchSideChats(main.instanceId, main.sessionId, archived: archived);

/// Last activity of the main chat [main] (null until it exists).
@riverpod
Stream<DateTime?> mainChatUpdatedAt(Ref ref, ThreadRef main) => main.isNew
    ? Stream.value(null)
    : ref
          .watch(hermuseDatabaseProvider)
          .watchSession(main.instanceId, main.sessionId)
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
      : await db.loadSideChats(chat.instanceId, main.id);
  final mainRow = main.id.startsWith('draft-')
      ? null
      : await db.loadSession(chat.instanceId, main.id);
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
  Future<HermesConnection> connectionFor(String instanceId) {
    final provider = connectionProvider(instanceId);
    if (_ref.read(provider).hasError) _ref.invalidate(provider);
    return _ref.read(provider.future);
  }
}

/// Mirrors chats into the local cache (side chat index + FTS transcript).
final class _DatabaseObserver implements ChatObserver {
  _DatabaseObserver(this._db, this._mainCreated);
  final HermuseDatabase _db;

  /// Called when the main (non side) session gets its stored id.
  final void Function(ThreadRef) _mainCreated;

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
    unawaited(_db.renameSession(ref.instanceId, ref.sessionId, title));
  }

  @override
  void turnEnded(ThreadRef ref) {
    unawaited(_db.touchSession(ref.instanceId, ref.sessionId, _now()));
  }

  @override
  void threadOpened(ThreadRef ref) {
    unawaited(_db.writeSetting(_openKey(ref.instanceId), ref.sessionId));
  }

  @override
  void sessionArchived(ThreadRef ref, {required bool archived}) {
    unawaited(
      _db.setSessionArchived(ref.instanceId, ref.sessionId, archived: archived),
    );
  }

  @override
  void sessionDeleted(ThreadRef ref) {
    unawaited(_db.deleteSession(ref.instanceId, ref.sessionId));
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
            sessionId: ref.sessionId,
            messageId: m.id,
            author: m.author.name,
            bodyText: m.plainText,
            createdAt: int.parse(m.id.substring(4)),
          ),
    ];
    if (rows.isNotEmpty) {
      unawaited(_db.cacheTranscript(ref.instanceId, ref.sessionId, rows));
    }
  }
}
