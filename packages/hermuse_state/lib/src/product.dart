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
/// created_at, reactions: {love?: ts, discuss?: ts}, why, image_url}`.
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
    this.why = '',
    this.imageUrl,
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
    why: json['why'] as String? ?? '',
    imageUrl: switch (json['image_url']) {
      final String url when url.trim().isNotEmpty => url.trim(),
      _ => null,
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

  /// "Why I created this": what in the user's context led to the post;
  /// '' for posts written before the agent gave reasons.
  final String why;

  /// The post's image (an absolute URL, or a path on the instance), if any.
  final String? imageUrl;

  bool reacted(FeedReaction reaction) => reactions.containsKey(reaction.name);
}

/// A feed edition started on demand (`POST /feed/generate`).
final class FeedGeneration {
  const FeedGeneration({required this.jobId, required this.started});

  /// The Hermes cron job running it.
  final String jobId;
  final bool started;
}

/// An idea. Shape: `{id, title, pitch, group, first_step, file,
/// created_at, feedback: [{at, text}], seeded, icon}`. Starter-catalog
/// ideas ([seeded], ids `seed-…`) carry no file nor creation time.
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
    this.seeded = false,
    this.icon = '',
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
    seeded: json['seeded'] == true,
    icon: json['icon'] as String? ?? '',
  );

  final String id;
  final String title;
  final String pitch;
  final String group;
  final String firstStep;
  final String file;
  final String createdAt;
  final List<IdeaFeedback> feedback;

  /// Part of the starter catalog shipped with the plugin, not the agent's.
  final bool seeded;

  /// Icon key: `workout`, `shopping`, `people`, `city`, `documents`,
  /// `returns`, `inbox`, `money`, `health`, `travel`; '' when none.
  final String icon;
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

/// Who set a goal: the user, or the agent tracking a commitment of its own
/// (a trip, a scheduled briefing).
enum GoalSource { user, agent }

/// A goal. Shape: `{id, title, category, why, target_date, status, file,
/// created_at, timeline: [{at, note, progress}], source, status_line, done,
/// parent_id, cron_job_id}`.
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
    this.source = GoalSource.user,
    this.statusLine = '',
    this.done = false,
    this.parentId,
    this.cronJobId,
  });

  factory Goal.fromJson(Map<String, Object?> json) {
    final status = json['status'] == 'done'
        ? GoalStatus.done
        : GoalStatus.tracking;
    return Goal(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? '',
      why: json['why'] as String? ?? '',
      targetDate: json['target_date'] as String? ?? '',
      status: status,
      file: json['file'] as String? ?? '',
      createdAt: json['created_at'] as String? ?? '',
      timeline: [
        for (final e in ((json['timeline'] as List?) ?? const []))
          GoalEvent.fromJson(e as Map<String, Object?>),
      ],
      source: json['source'] == 'agent' ? GoalSource.agent : GoalSource.user,
      statusLine: json['status_line'] as String? ?? '',
      done: json['done'] as bool? ?? status == GoalStatus.done,
      parentId: _id(json['parent_id']),
      cronJobId: _id(json['cron_job_id']),
    );
  }

  final String id;
  final String title;
  final String category;
  final String why;
  final String targetDate;
  final GoalStatus status;
  final String file;
  final String createdAt;
  final List<GoalEvent> timeline;
  final GoalSource source;

  /// Latest progress, shown under the title; '' when none was written.
  final String statusLine;
  final bool done;

  /// The goal this one is a subgoal of.
  final String? parentId;

  /// The scheduled job working towards it (a briefing the agent set up).
  final String? cronJobId;
}

String? _id(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// The Goals surface: "Tracking" (goals the agent set itself) above
/// "Goals" (set by the user), top-level goals in list order, each with its
/// subgoals.
final class GoalSections {
  const GoalSections({
    required this.tracking,
    required this.goals,
    required this.subgoals,
  });

  final List<Goal> tracking;
  final List<Goal> goals;

  /// Subgoals by parent goal id, in list order.
  final Map<String, List<Goal>> subgoals;

  List<Goal> subgoalsOf(Goal goal) => subgoals[goal.id] ?? const [];
}

/// [goals] split into [GoalSections]; a subgoal whose parent is not in the
/// list stands as a top-level goal.
GoalSections goalSections(List<Goal> goals) {
  final ids = {for (final g in goals) g.id};
  final subgoals = <String, List<Goal>>{};
  final tracking = <Goal>[];
  final own = <Goal>[];
  for (final goal in goals) {
    final parent = goal.parentId;
    if (parent != null && parent != goal.id && ids.contains(parent)) {
      subgoals.putIfAbsent(parent, () => []).add(goal);
    } else {
      (goal.source == GoalSource.agent ? tracking : own).add(goal);
    }
  }
  return GoalSections(tracking: tracking, goals: own, subgoals: subgoals);
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

/// The server guide's install of the plugin by hand, for both kinds of
/// servers (set up by Hermuse, or by hand).
const hermusePluginByHandGuide =
    'https://github.com/yellow-stick/hermuse-agent/blob/main/docs/guides/'
    'server.md#without-the-one-click-install';

/// Version of the Hermuse plugin these apps are built with: the desktop app
/// bundles it (`plugin.yaml`), and a remote Hermes running an older one is
/// offered the update.
const hermusePluginVersion = '0.5.0';

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
  Future<List<FeedPost>> build(
    String instanceId, {
    int limit = 50,
    String profile = 'default',
  }) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
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
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
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

  /// Deletes a post.
  Future<void> delete(String postId) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    await rest.delete(
      '$hermusePluginRoute/feed/${Uri.encodeComponent(postId)}',
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final p in current)
          if (p.id != postId) p,
      ]);
    }
  }

  /// Runs a feed edition now: the plugin marks its feed job due and the
  /// Hermes scheduler fires it; new posts arrive when the agent wrote them
  /// (reload then). Throws [HermesHttpError] 409 when the feed job is not
  /// registered (the plugin's schedule is off).
  Future<FeedGeneration> generate() async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    final body = await rest.postJson(
      '$hermusePluginRoute/feed/generate',
      const {},
    );
    return FeedGeneration(
      jobId: '${body['job_id'] ?? ''}',
      started: body['started'] == true,
    );
  }

  /// Publishes a post (used by tests/smoke; the agent usually writes).
  Future<FeedPost> publish({
    required String title,
    required String body,
    String topic = '',
    List<String> sources = const [],
  }) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
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
  Future<List<Idea>> build(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  }) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    final body = await rest.getJson('$hermusePluginRoute/ideas', {
      'limit': '$limit',
    });
    return [
      for (final e in ((body['ideas'] as List?) ?? const []))
        Idea.fromJson(e as Map<String, Object?>),
    ];
  }

  /// Hides an idea (a starter one or the agent's) from the list.
  Future<void> dismiss(String ideaId) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    await rest.postJson(
      '$hermusePluginRoute/ideas/${Uri.encodeComponent(ideaId)}/dismiss',
      const {},
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final i in current)
          if (i.id != ideaId) i,
      ]);
    }
  }

  /// Appends user feedback to an idea; returns the updated idea.
  Future<Idea> feedback(String ideaId, String text) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
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
  Future<List<Goal>> build(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  }) async {
    await _requirePlugin(ref, instanceId);
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    final body = await rest.getJson('$hermusePluginRoute/goals', {
      'limit': '$limit',
    });
    return [
      for (final e in ((body['goals'] as List?) ?? const []))
        Goal.fromJson(e as Map<String, Object?>),
    ];
  }

  /// Tracks a new goal; returns it. [category] must be a
  /// [hermuseGoalCategories] value (the server 422s otherwise); a
  /// [parentId] files it as a subgoal.
  Future<Goal> create({
    required String title,
    required String category,
    required String why,
    String targetDate = '',
    GoalSource source = GoalSource.user,
    String? parentId,
  }) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    final goal = Goal.fromJson(
      await rest.postJson('$hermusePluginRoute/goals', {
        'title': title,
        'category': category,
        'why': why,
        if (targetDate.isNotEmpty) 'target_date': targetDate,
        'source': source.name,
        'parent_id': ?parentId,
      }),
    );
    ref.invalidateSelf();
    return goal;
  }

  /// "Add subgoal": a goal under [parent], in its category; [why] defaults
  /// to naming the parent.
  Future<Goal> addSubgoal({
    required Goal parent,
    required String title,
    String why = '',
  }) => create(
    title: title,
    category: hermuseGoalCategories.contains(parent.category)
        ? parent.category
        : 'something_else',
    why: why.trim().isEmpty ? 'Part of "${parent.title}"' : why,
    parentId: parent.id,
  );

  /// "Rename": a new title (the server refuses a blank one).
  Future<Goal> rename(String goalId, String title) =>
      _patch(goalId, {'title': title.trim()});

  /// "Complete" (or reopen with [done] false).
  Future<Goal> complete(String goalId, {bool done = true}) =>
      _patch(goalId, {'done': done});

  /// "Delete": the goal and its subgoals.
  Future<void> delete(String goalId) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    await rest.delete(
      '$hermusePluginRoute/goals/${Uri.encodeComponent(goalId)}',
    );
    final current = state.value;
    if (current != null) {
      state = AsyncData([
        for (final g in current)
          if (g.id != goalId && g.parentId != goalId) g,
      ]);
    }
  }

  Future<Goal> _patch(String goalId, Map<String, Object?> changes) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    final goal = Goal.fromJson(
      await rest.patchJson(
        '$hermusePluginRoute/goals/${Uri.encodeComponent(goalId)}',
        changes,
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

  /// Appends a timeline entry (and optionally flips the status).
  Future<Goal> updateGoal({
    required String goalId,
    required String note,
    String progress = '',
    GoalStatus? status,
  }) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
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
  String profile = 'default',
}) async {
  await _requirePlugin(ref, instanceId);
  final rest = await ref.watch(
    restClientProvider(instanceId, profile: profile).future,
  );
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
  String profile = 'default',
}) async {
  await _requirePlugin(ref, instanceId);
  final rest = await ref.watch(
    restClientProvider(instanceId, profile: profile).future,
  );
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
  Future<SystemFile> build(
    String instanceId,
    String name, {
    String profile = 'default',
  }) async {
    await _requirePlugin(ref, instanceId);
    _checkName(name);
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    return SystemFile.fromJson(await rest.getJson(_route(name)));
  }

  /// Saves new Markdown content; returns the updated file.
  Future<SystemFile> save(String content) async {
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
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
