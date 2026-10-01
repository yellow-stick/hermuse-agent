import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'computer.dart';
import 'onboarding.dart';

part 'product.g.dart';

/// Base route of the Hermuse plugin dashboard backend.
const hermusePluginRoute = '/api/plugins/hermuse';

/// Allow-listed system files (mirrors `store.MANAGED_FILES`).
const hermuseManagedFiles = [
  'FEED_PROMPT.md',
  'PREFERENCES.md',
  'IDENTITY.md',
  'HEARTBEAT.md',
];

/// Goal categories (mirrors `store.GOAL_CATEGORIES`).
const hermuseGoalCategories = [
  'health',
  'relationships',
  'finance',
  'career',
  'interests',
  'productivity',
  'something_else',
];

/// Feed reactions (mirrors `store.REACTIONS`).
enum FeedReaction { love, discuss }

/// A feed post. Shape: `{id, title, topic, body, sources[], file,
/// created_at, reactions: {love?: ts, discuss?: ts}}`.
final class FeedPost {
  const FeedPost({
    required this.id,
    required this.title,
    required this.topic,
    required this.body,
    required this.sources,
    required this.file,
    required this.createdAt,
    required this.reactions,
  });

  factory FeedPost.fromJson(Map<String, Object?> json) => FeedPost(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    body: json['body'] as String? ?? '',
    sources: ((json['sources'] as List?) ?? const []).cast<String>(),
    file: json['file'] as String? ?? '',
    createdAt: json['created_at'] as String? ?? '',
    reactions: {
      for (final e in ((json['reactions'] as Map?) ?? const {}).entries)
        e.key as String: e.value as String? ?? '',
    },
  );

  final String id;
  final String title;
  final String topic;
  final String body;
  final List<String> sources;
  final String file;
  final String createdAt;
  final Map<String, String> reactions;

  bool reacted(FeedReaction reaction) => reactions.containsKey(reaction.name);
}

/// An idea. Shape: `{id, title, pitch, group, first_step, file,
/// created_at, feedback: [{at, text}]}`.
final class Idea {
  const Idea({
    required this.id,
    required this.title,
    required this.pitch,
    required this.group,
    required this.firstStep,
    required this.file,
    required this.createdAt,
    required this.feedback,
  });

  factory Idea.fromJson(Map<String, Object?> json) => Idea(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    pitch: json['pitch'] as String? ?? '',
    group: json['group'] as String? ?? '',
    firstStep: json['first_step'] as String? ?? '',
    file: json['file'] as String? ?? '',
    createdAt: json['created_at'] as String? ?? '',
    feedback: [
      for (final e in ((json['feedback'] as List?) ?? const []))
        IdeaFeedback.fromJson(e as Map<String, Object?>),
    ],
  );

  final String id;
  final String title;
  final String pitch;
  final String group;
  final String firstStep;
  final String file;
  final String createdAt;
  final List<IdeaFeedback> feedback;
}

/// One "idea feedback" entry: `{at, text}`.
final class IdeaFeedback {
  const IdeaFeedback({required this.at, required this.text});

  factory IdeaFeedback.fromJson(Map<String, Object?> json) => IdeaFeedback(
    at: json['at'] as String? ?? '',
    text: json['text'] as String? ?? '',
  );

  final String at;
  final String text;
}

/// Goal status (`tracking` or `done`).
enum GoalStatus { tracking, done }

/// A goal. Shape: `{id, title, category, why, target_date, status, file,
/// created_at, timeline: [{at, note, progress}]}`.
final class Goal {
  const Goal({
    required this.id,
    required this.title,
    required this.category,
    required this.why,
    required this.targetDate,
    required this.status,
    required this.file,
    required this.createdAt,
    required this.timeline,
  });

  factory Goal.fromJson(Map<String, Object?> json) => Goal(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    category: json['category'] as String? ?? '',
    why: json['why'] as String? ?? '',
    targetDate: json['target_date'] as String? ?? '',
    status: json['status'] == 'done' ? GoalStatus.done : GoalStatus.tracking,
    file: json['file'] as String? ?? '',
    createdAt: json['created_at'] as String? ?? '',
    timeline: [
      for (final e in ((json['timeline'] as List?) ?? const []))
        GoalEvent.fromJson(e as Map<String, Object?>),
    ],
  );

  final String id;
  final String title;
  final String category;
  final String why;
  final String targetDate;
  final GoalStatus status;
  final String file;
  final String createdAt;
  final List<GoalEvent> timeline;
}

/// One goal timeline entry: `{at, note, progress}`.
final class GoalEvent {
  const GoalEvent({
    required this.at,
    required this.note,
    required this.progress,
  });

  factory GoalEvent.fromJson(Map<String, Object?> json) => GoalEvent(
    at: json['at'] as String? ?? '',
    note: json['note'] as String? ?? '',
    progress: json['progress'] as String? ?? '',
  );

  final String at;
  final String note;
  final String progress;
}

/// A library artifact. Shape: `{id, title, kind, file, size, tags[],
/// created_at}`.
final class Artifact {
  const Artifact({
    required this.id,
    required this.title,
    required this.kind,
    required this.file,
    required this.size,
    required this.tags,
    required this.createdAt,
  });

  factory Artifact.fromJson(Map<String, Object?> json) => Artifact(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    file: json['file'] as String? ?? '',
    size: (json['size'] as num?)?.toInt() ?? 0,
    tags: ((json['tags'] as List?) ?? const []).cast<String>(),
    createdAt: json['created_at'] as String? ?? '',
  );

  final String id;
  final String title;
  final String kind;
  final String file;
  final int size;
  final List<String> tags;
  final String createdAt;
}

/// A reflection journal entry. Shape: `{date, file, written_at, body}`.
final class Reflection {
  const Reflection({
    required this.date,
    required this.file,
    required this.writtenAt,
    required this.body,
  });

  factory Reflection.fromJson(Map<String, Object?> json) => Reflection(
    date: json['date'] as String? ?? '',
    file: json['file'] as String? ?? '',
    writtenAt: json['written_at'] as String? ?? '',
    body: json['body'] as String? ?? '',
  );

  final String date;
  final String file;
  final String writtenAt;
  final String body;
}

/// A managed system file or the preferences doc: `{name, content}`.
final class SystemFile {
  const SystemFile({required this.name, required this.content});

  factory SystemFile.fromJson(Map<String, Object?> json) => SystemFile(
    name: json['name'] as String? ?? '',
    content: json['content'] as String? ?? '',
  );

  final String name;
  final String content;
}

/// Plugin presence on an instance.
enum PluginPresence {
  /// The plugin routes answer.
  installed,

  /// The plugin routes 404 (not installed or not enabled).
  missing,
}

/// Whether the Hermuse plugin backend answers on [instanceId].
///
/// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
/// router is not mounted (not installed/enabled); anything else propagates.
@riverpod
Future<PluginPresence> pluginStatus(Ref ref, String instanceId) async {
  final rest = await ref.watch(restClientProvider(instanceId).future);
  try {
    await rest.getJson('$hermusePluginRoute/files');
    return PluginPresence.installed;
  } on HermesHttpError catch (error) {
    if (error.statusCode == 404) return PluginPresence.missing;
    rethrow;
  }
}

Future<void> _requirePlugin(Ref ref, String instanceId) async {
  if (await ref.read(pluginStatusProvider(instanceId).future) !=
      PluginPresence.installed) {
    throw StateError('the Hermuse plugin is not installed on this instance');
  }
}

/// Plugin source the dashboard installs from (public GitHub repo + subdir).
const hermusePluginIdentifier =
    'yellow-stick/hermuse-agent/hermes-plugin/hermuse';

/// Version of the Hermuse plugin these apps are built with: the desktop app
/// bundles it (`plugin.yaml`), and a remote Hermes running an older one is
/// offered the update.
const hermusePluginVersion = '0.3.0';

/// Hermes' agent-plugin management API.
const _pluginsApi = '/api/dashboard/agent-plugins';

/// One finding of the Hermes plugin security scan: `{pattern_id, severity,
/// category, file, line, description}`.
final class PluginScanFinding {
  const PluginScanFinding({
    required this.severity,
    required this.file,
    required this.description,
    this.line,
  });

  factory PluginScanFinding.fromJson(Map<String, Object?> json) =>
      PluginScanFinding(
        severity: '${json['severity'] ?? ''}',
        file: '${json['file'] ?? ''}',
        line: switch (json['line']) {
          final int line => line,
          _ => null,
        },
        description: '${json['description'] ?? ''}',
      );

  final String severity;
  final String file;
  final int? line;
  final String description;

  @override
  String toString() =>
      '$severity: $file${line == null ? '' : ':$line'} — $description';
}

/// Outcome of [installHermusePlugin] and [mountHermusePlugin].
sealed class PluginInstallResult {
  const PluginInstallResult();
}

/// The plugin answers; its schedule is on and the computer setup ran,
/// unless only the plugin was installed ([mountHermusePlugin]).
final class PluginInstalled extends PluginInstallResult {
  const PluginInstalled([this.computer]);

  /// Result of `POST /computer/setup` (Docker may still be missing); null
  /// when only the plugin was installed.
  final ComputerStatus? computer;
}

/// Hermes installed and enabled the plugin but its routes stay unmounted
/// until the dashboard restarts.
final class PluginNeedsDashboardRestart extends PluginInstallResult {
  const PluginNeedsDashboardRestart();
}

/// Hermes' plugin scan rated the plugin "caution" (it installs Docker with
/// sudo): the user must allow it, then [installHermusePlugin] runs again
/// with `force: true`. A "dangerous" verdict is a [PluginInstallFailed].
final class PluginNeedsConsent extends PluginInstallResult {
  const PluginNeedsConsent(this.detail);

  /// Hermes' scan report (reason and findings).
  final String detail;
}

/// A step failed; [message] says which and why.
final class PluginInstallFailed extends PluginInstallResult {
  const PluginInstallFailed(this.message, {this.findings = const []});

  final String message;

  /// Security scan findings when the scan blocked the install.
  final List<PluginScanFinding> findings;
}

/// Installs the Hermuse plugin on a remote Hermes through its dashboard
/// ([mountHermusePlugin]), then turns its schedule on and sets the computer
/// up.
Future<PluginInstallResult> installHermusePlugin(
  HermesRestClient rest, {
  bool force = false,
  Duration mountTimeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  final mounted = await mountHermusePlugin(
    rest,
    force: force,
    mountTimeout: mountTimeout,
    pollInterval: pollInterval,
  );
  return mounted is PluginInstalled ? _finish(rest) : mounted;
}

/// Installs or turns on the Hermuse plugin on a remote Hermes through its
/// dashboard and waits for its routes, nothing more:
///
/// 1. `GET /files` answers → the plugin already runs;
/// 2. else `enable` it (installed but disabled), then wait for its routes;
/// 3. Hermes does not know it → `install` it, then wait for its routes.
///
/// Routes that stay unmounted for [mountTimeout] need a dashboard restart.
/// Hermes rates the plugin "caution" (it installs Docker with sudo): the
/// first install returns [PluginNeedsConsent]; call again with [force] once
/// the user allowed it (steps 1–2 are skipped then).
Future<PluginInstallResult> mountHermusePlugin(
  HermesRestClient rest, {
  bool force = false,
  Duration mountTimeout = const Duration(seconds: 10),
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  if (!force) {
    switch (await _probe(rest)) {
      case true:
        return const PluginInstalled();
      case final PluginInstallFailed failed:
        return failed;
    }
    var known = true;
    try {
      final body = await rest.postJson('$_pluginsApi/hermuse/enable', const {});
      if (body['ok'] == false) {
        return PluginInstallFailed('${body['error'] ?? 'Enable failed.'}');
      }
    } on HermesHttpError catch (e) {
      // "Plugin 'hermuse' is not installed or bundled."
      if (e.statusCode != 400 || !e.message.contains('not installed')) {
        return PluginInstallFailed(hermesReason(e));
      }
      known = false;
    } on HermesException catch (e) {
      return PluginInstallFailed(hermesReason(e));
    }
    if (known) return _awaitRoutes(rest, mountTimeout, pollInterval);
  }

  return await _install(rest, force: force) ??
      await _awaitRoutes(rest, mountTimeout, pollInterval);
}

/// Replaces the Hermuse plugin of a remote Hermes with the published one:
/// Hermes installs it again from [hermusePluginIdentifier] (`force` replaces
/// the installed copy). The dashboard keeps serving the plugin it loaded
/// until it restarts, so success is [PluginNeedsDashboardRestart].
Future<PluginInstallResult> updateHermusePlugin(HermesRestClient rest) async =>
    await _install(rest, force: true) ?? const PluginNeedsDashboardRestart();

/// `POST /install`: null once Hermes installed the plugin, else why not.
///
/// Every failure returns its own result: dart2js once compiled a nullable
/// local assigned only in failure branches as set on success too.
Future<PluginInstallResult?> _install(
  HermesRestClient rest, {
  required bool force,
}) async {
  // Hermes answers a failed mutation with 400 `{detail}` (the scan findings
  // are dropped); a 200 `{ok: false, …}` carries them.
  try {
    final body = await rest.postJson('$_pluginsApi/install', {
      'identifier': hermusePluginIdentifier,
      'enable': true,
      'force': force,
    });
    if (body['ok'] != false) return null;
    return _refused(
      '${body['error'] ?? 'Install failed.'}',
      force: force,
      findings: [
        for (final f in body['scan_findings'] as List? ?? const [])
          if (f is Map<String, Object?>) PluginScanFinding.fromJson(f),
      ],
    );
  } on HermesException catch (e) {
    return _refused(hermesReason(e), force: force);
  }
}

/// An install Hermes refused: "Requires confirmation (caution verdict, N
/// findings)" asks for consent unless it was [force]d; a dangerous verdict
/// reads "dangerous verdict" and `force` cannot override it.
PluginInstallResult _refused(
  String error, {
  required bool force,
  List<PluginScanFinding> findings = const [],
}) => !force && error.contains('caution verdict')
    ? PluginNeedsConsent(error)
    : PluginInstallFailed(error, findings: findings);

/// `GET /files`: `true` when the plugin routes answer, `false` on 404.
Future<Object> _probe(HermesRestClient rest) async {
  try {
    await rest.getJson('$hermusePluginRoute/files');
    return true;
  } on HermesHttpError catch (e) {
    if (e.statusCode == 404) return false;
    return PluginInstallFailed(hermesReason(e));
  } on HermesException catch (e) {
    return PluginInstallFailed(hermesReason(e));
  }
}

/// Waits for the plugin routes to mount.
Future<PluginInstallResult> _awaitRoutes(
  HermesRestClient rest,
  Duration mountTimeout,
  Duration pollInterval,
) async {
  final deadline = DateTime.now().add(mountTimeout);
  while (true) {
    switch (await _probe(rest)) {
      case true:
        return const PluginInstalled();
      case final PluginInstallFailed failed:
        return failed;
    }
    if (!DateTime.now().isBefore(deadline)) {
      return const PluginNeedsDashboardRestart();
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// Turns the schedule on and sets the computer up.
Future<PluginInstallResult> _finish(HermesRestClient rest) async {
  try {
    await rest.postJson('$hermusePluginRoute/cron/enable', const {});
  } on HermesException catch (e) {
    return PluginInstallFailed(
      'Hermuse is installed but its schedule could not be enabled: '
      '${hermesReason(e)}',
    );
  }
  try {
    return PluginInstalled(await ComputerClient(rest).setup());
  } on HermesException catch (e) {
    // The plugin works; the computer viewer retries the setup.
    return PluginInstalled(
      ComputerStatus(state: ComputerState.error, detail: hermesReason(e)),
    );
  }
}

/// The server's words: [HermesHttpError] messages are
/// `METHOD path: detail`.
String hermesReason(HermesException e) => switch (e) {
  HermesHttpError(:final message) => switch (message.indexOf(': ')) {
    -1 => message,
    final i => message.substring(i + 2),
  },
  _ => e.message,
};

/// Feed posts, newest first.
@riverpod
class Feed extends _$Feed {
  @override
  Future<List<FeedPost>> build(String instanceId, {int limit = 50}) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(restClientProvider(instanceId).future);
    final body = await rest.getJson('$hermusePluginRoute/feed', {
      'limit': '$limit',
    });
    return [
      for (final e in ((body['posts'] as List?) ?? const []))
        FeedPost.fromJson(e as Map<String, Object?>),
    ];
  }

  /// Toggles a reaction; returns the updated post.
  Future<FeedPost> react(String postId, FeedReaction reaction) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final post = FeedPost.fromJson(
      await rest.postJson(
        '$hermusePluginRoute/feed/${Uri.encodeComponent(postId)}/react',
        {'reaction': reaction.name},
      ),
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final p in current)
          if (p.id == postId) post else p,
      ]);
    }
    return post;
  }

  /// Publishes a post (used by tests/smoke; the agent usually writes).
  Future<FeedPost> publish({
    required String title,
    required String body,
    String topic = '',
    List<String> sources = const [],
  }) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final post = FeedPost.fromJson(
      await rest.postJson('$hermusePluginRoute/feed', {
        'title': title,
        'body': body,
        if (topic.isNotEmpty) 'topic': topic,
        if (sources.isNotEmpty) 'sources': sources,
      }),
    );
    ref.invalidateSelf();
    return post;
  }
}

/// Ideas, newest first.
@riverpod
class Ideas extends _$Ideas {
  @override
  Future<List<Idea>> build(String instanceId, {int limit = 200}) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(restClientProvider(instanceId).future);
    final body = await rest.getJson('$hermusePluginRoute/ideas', {
      'limit': '$limit',
    });
    return [
      for (final e in ((body['ideas'] as List?) ?? const []))
        Idea.fromJson(e as Map<String, Object?>),
    ];
  }

  /// Appends user feedback to an idea; returns the updated idea.
  Future<Idea> feedback(String ideaId, String text) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final idea = Idea.fromJson(
      await rest.postJson(
        '$hermusePluginRoute/ideas/${Uri.encodeComponent(ideaId)}/feedback',
        {'feedback': text},
      ),
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final i in current)
          if (i.id == ideaId) idea else i,
      ]);
    }
    return idea;
  }
}

/// Goals, newest first.
@riverpod
class Goals extends _$Goals {
  @override
  Future<List<Goal>> build(String instanceId, {int limit = 200}) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(restClientProvider(instanceId).future);
    final body = await rest.getJson('$hermusePluginRoute/goals', {
      'limit': '$limit',
    });
    return [
      for (final e in ((body['goals'] as List?) ?? const []))
        Goal.fromJson(e as Map<String, Object?>),
    ];
  }

  /// Tracks a new goal; returns it. [category] must be a
  /// [hermuseGoalCategories] value (the server 422s otherwise).
  Future<Goal> create({
    required String title,
    required String category,
    required String why,
    String targetDate = '',
  }) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final goal = Goal.fromJson(
      await rest.postJson('$hermusePluginRoute/goals', {
        'title': title,
        'category': category,
        'why': why,
        if (targetDate.isNotEmpty) 'target_date': targetDate,
      }),
    );
    ref.invalidateSelf();
    return goal;
  }

  /// Appends a timeline entry (and optionally flips the status).
  Future<Goal> updateGoal({
    required String goalId,
    required String note,
    String progress = '',
    GoalStatus? status,
  }) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final goal = Goal.fromJson(
      await rest.postJson(
        '$hermusePluginRoute/goals/${Uri.encodeComponent(goalId)}/update',
        {
          'note': note,
          if (progress.isNotEmpty) 'progress': progress,
          if (status != null) 'status': status.name,
        },
      ),
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final g in current)
          if (g.id == goalId) goal else g,
      ]);
    }
    return goal;
  }
}

/// Library artifacts, newest first.
@riverpod
Future<List<Artifact>> artifacts(
  Ref ref,
  String instanceId, {
  int limit = 200,
}) async {
  await _requirePlugin(ref, instanceId);
  final rest = await ref.watch(restClientProvider(instanceId).future);
  final body = await rest.getJson('$hermusePluginRoute/artifacts', {
    'limit': '$limit',
  });
  return [
    for (final e in ((body['artifacts'] as List?) ?? const []))
      Artifact.fromJson(e as Map<String, Object?>),
  ];
}

/// Reflection journal entries, newest first.
@riverpod
Future<List<Reflection>> reflections(
  Ref ref,
  String instanceId, {
  int limit = 90,
}) async {
  await _requirePlugin(ref, instanceId);
  final rest = await ref.watch(restClientProvider(instanceId).future);
  final body = await rest.getJson('$hermusePluginRoute/reflections', {
    'limit': '$limit',
  });
  return [
    for (final e in ((body['reflections'] as List?) ?? const []))
      Reflection.fromJson(e as Map<String, Object?>),
  ];
}

/// Name of the proactive-preferences doc (served by `/preferences`).
const preferencesFileName = 'PREFERENCES.md';

/// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
/// or [preferencesFileName].
@Riverpod(name: 'systemFileProvider')
class SystemFileState extends _$SystemFileState {
  @override
  Future<SystemFile> build(String instanceId, String name) async {
    await _requirePlugin(ref, instanceId);
    _checkName(name);
    final rest = await ref.watch(restClientProvider(instanceId).future);
    return SystemFile.fromJson(await rest.getJson(_route(name)));
  }

  /// Saves new Markdown content; returns the updated file.
  Future<SystemFile> save(String content) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    await rest.putJson(_route(name), {'content': content});
    final file = SystemFile(name: name, content: content);
    state = AsyncData(file);
    return file;
  }

  String _route(String file) => file == preferencesFileName
      ? '$hermusePluginRoute/preferences'
      : '$hermusePluginRoute/files/${Uri.encodeComponent(file)}';

  void _checkName(String file) {
    if (file != preferencesFileName && !hermuseManagedFiles.contains(file)) {
      throw ArgumentError.value(file, 'name', 'not a managed file');
    }
  }
}
