import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
