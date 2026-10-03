import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show ToolKind;
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

/// Fixtures below mirror the real plugin responses captured from
/// `hermes-plugin/hermuse` on a throwaway HERMES_HOME (see
/// `/tmp/hermcap/plugin.json`): same keys, same nesting, truncated bodies.

Map<String, Object?> feedFixture() => {
  'posts': [
    {
      'id': '6372ea12f016',
      'title': 'Second',
      'topic': '',
      'body': 'More news.',
      'sources': <Object?>[],
      'file': '2026-09-26-second-6372ea12f016.md',
      'created_at': '2026-09-26T20:37:22.593946+00:00',
      'reactions': <String, Object?>{},
    },
    {
      'id': 'a1b2c3d4e5f6',
      'title': 'Launch day',
      'topic': 'intro',
      'body': 'We shipped.',
      'sources': ['https://example.com'],
      'file': '2026-09-26-launch-day-a1b2c3d4e5f6.md',
      'created_at': '2026-09-26T20:37:20.000000+00:00',
      'reactions': {'love': '2026-09-26T20:40:00+00:00'},
    },
  ],
};

Map<String, Object?> ideasFixture() => {
  'ideas': [
    {
      'id': '9432126be5b7',
      'title': 'Triage',
      'pitch': 'Let me triage.',
      'group': 'Productivity',
      'first_step': 'Open inbox',
      'file': '9432126be5b7.md',
      'created_at': '2026-09-26T20:37:22.611939+00:00',
      'feedback': <Object?>[],
    },
  ],
};

Map<String, Object?> goalsFixture() => {
  'goals': [
    {
      'id': '1d70799620e5',
      'title': 'Run',
      'category': 'health',
      'why': 'Stay fit.',
      'target_date': '2026-12-31',
      'status': 'tracking',
      'file': '1d70799620e5.md',
      'created_at': '2026-09-26T20:37:22.629770+00:00',
      'timeline': [
        {
          'at': '2026-09-26T20:37:22.629770+00:00',
          'note': 'tracking started.',
          'progress': '',
        },
      ],
    },
  ],
};

Map<String, Object?> artifactsFixture() => {
  'artifacts': [
    {
      'id': '0cc169cccb46',
      'title': 'Plan',
      'kind': 'document',
      'file': 'files/0cc169cccb46/plan-0cc169cccb46.md',
      'size': 6,
      'tags': <Object?>[],
      'created_at': '2026-09-26T20:37:22.647657+00:00',
    },
  ],
};

Map<String, Object?> reflectionsFixture() => {
  'reflections': [
    {
      'date': '2026-09-25',
      'file': '2026-09-25.md',
      'written_at': '2026-09-26T20:37:22.656786+00:00',
      'body': 'I reflected on plugins.',
    },
  ],
};

void main() {
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ProviderContainer container;
  late Map<String, http.Response Function(http.Request)> routes;
  late List<({String method, String path, Object? body})> calls;

  http.Response json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    routes = {
      'GET /api/plugins/hermuse/files': (_) =>
          json({'files': hermuseManagedFiles}),
      'GET /api/plugins/hermuse/feed': (_) => json(feedFixture()),
      'GET /api/plugins/hermuse/ideas': (_) => json(ideasFixture()),
      'GET /api/plugins/hermuse/goals': (_) => json(goalsFixture()),
      'GET /api/plugins/hermuse/artifacts': (_) => json(artifactsFixture()),
      'GET /api/plugins/hermuse/reflections': (_) => json(reflectionsFixture()),
      'GET /api/plugins/hermuse/preferences': (_) =>
          json({'name': 'PREFERENCES.md', 'content': '# prefs\n'}),
      'GET /api/plugins/hermuse/files/HEARTBEAT.md': (_) =>
          json({'name': 'HEARTBEAT.md', 'content': '# Heartbeat\n'}),
    };
    calls = [];
    final mock = MockClient((request) async {
      Object? body;
      if (request.body.isNotEmpty) {
        try {
          body = jsonDecode(request.body);
        } on FormatException {
          body = request.body;
        }
      }
      calls.add((method: request.method, path: request.url.path, body: body));
      final route = routes['${request.method} ${request.url.path}'];
      if (route == null) return json({'detail': 'not found'}, 404);
      return route(request);
    });
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider('vps').overrideWith(
          (ref) =>
              HermesRestClient(mock, baseUrl: Uri.parse('https://vps.example')),
        ),
      ],
    );
    final registry = await container.read(registryProvider.future);
    await registry.add(
      HermesInstance(
        id: 'vps',
        label: 'VPS',
        kind: InstanceKind.remote,
        baseUrl: Uri.parse('https://vps.example'),
        auth: AuthMethod.password,
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('pluginStatus detects installed vs missing', () async {
    expect(
      await container.read(pluginStatusProvider('vps').future),
      PluginPresence.installed,
    );
    routes['GET /api/plugins/hermuse/files'] = (_) =>
        json({'detail': 'not found'}, 404);
    container.invalidate(pluginStatusProvider('vps'));
    expect(
      await container.read(pluginStatusProvider('vps').future),
      PluginPresence.missing,
    );
  });

  test('lists decode the real shapes', () async {
    final posts = await container.read(feedProvider('vps').future);
    expect(posts, hasLength(2));
    expect(posts.first.reactions, isEmpty);
    expect(posts.last.reacted(FeedReaction.love), isTrue);
    expect(posts.last.sources, ['https://example.com']);

    final ideas = await container.read(ideasProvider('vps').future);
    expect(ideas.single.group, 'Productivity');

    final goals = await container.read(goalsProvider('vps').future);
    expect(goals.single.status, GoalStatus.tracking);
    expect(goals.single.timeline.single.note, 'tracking started.');

    final artifacts = await container.read(artifactsProvider('vps').future);
    expect(artifacts.single.size, 6);

    final reflections = await container.read(reflectionsProvider('vps').future);
    expect(reflections.single.date, '2026-09-25');
  });

  test('react toggles and patches the cached post', () async {
    routes['POST /api/plugins/hermuse/feed/6372ea12f016/react'] = (_) => json({
      ...((feedFixture()['posts'] as List).first as Map<String, Object?>),
      'reactions': {'love': '2026-09-26T21:00:00+00:00'},
    });
    await container.read(feedProvider('vps').future);
    final post = await container
        .read(feedProvider('vps').notifier)
        .react('6372ea12f016', FeedReaction.love);
    expect(post.reacted(FeedReaction.love), isTrue);
    expect(calls.last.body, {'reaction': 'love'});
    final cached = container.read(feedProvider('vps')).value!;
    expect(
      cached.firstWhere((p) => p.id == '6372ea12f016').reactions,
      contains('love'),
    );
  });

  test('feedback appends and patches the cached idea', () async {
    routes['POST /api/plugins/hermuse/ideas/9432126be5b7/feedback'] = (_) =>
        json({
          ...((ideasFixture()['ideas'] as List).first as Map<String, Object?>),
          'feedback': [
            {'at': '2026-09-26T21:00:00+00:00', 'text': 'do it'},
          ],
        });
    await container.read(ideasProvider('vps').future);
    final idea = await container
        .read(ideasProvider('vps').notifier)
        .feedback('9432126be5b7', 'do it');
    expect(idea.feedback.single.text, 'do it');
    expect(calls.last.body, {'feedback': 'do it'});
  });

  test('create + updateGoal round-trip', () async {
    routes['POST /api/plugins/hermuse/goals'] = (request) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return json({
        ...((goalsFixture()['goals'] as List).first as Map<String, Object?>),
        'id': 'new-goal-id',
        'title': body['title'],
        'category': body['category'],
        'why': body['why'],
      }, 201);
    };
    routes['POST /api/plugins/hermuse/goals/1d70799620e5/update'] = (_) =>
        json({
          ...((goalsFixture()['goals'] as List).first as Map<String, Object?>),
          'status': 'done',
          'timeline': [
            {
              'at': '2026-09-26T20:37:22.629770+00:00',
              'note': 'tracking started.',
              'progress': '',
            },
            {
              'at': '2026-09-26T21:00:00+00:00',
              'note': 'Ran 5k',
              'progress': 'week 1',
            },
          ],
        });
    await container.read(goalsProvider('vps').future);
    final created = await container
        .read(goalsProvider('vps').notifier)
        .create(title: 'Swim', category: 'health', why: 'Cardio.');
    expect(created.id, 'new-goal-id');
    final updated = await container
        .read(goalsProvider('vps').notifier)
        .updateGoal(
          goalId: '1d70799620e5',
          note: 'Ran 5k',
          progress: 'week 1',
          status: GoalStatus.done,
        );
    expect(updated.status, GoalStatus.done);
    expect(updated.timeline, hasLength(2));
    final updateCall = calls.lastWhere(
      (c) => c.path == '/api/plugins/hermuse/goals/1d70799620e5/update',
    );
    expect(updateCall.body, {
      'note': 'Ran 5k',
      'progress': 'week 1',
      'status': 'done',
    });
  });

  test('system files read + save, unknown names rejected', () async {
    final file = await container.read(
      systemFileProvider('vps', 'HEARTBEAT.md').future,
    );
    expect(file.content, '# Heartbeat\n');

    final saved = <String, String>{};
    routes['PUT /api/plugins/hermuse/files/HEARTBEAT.md'] = (request) {
      saved['content'] =
          (jsonDecode(request.body) as Map<String, Object?>)['content']
              as String;
      return json({'ok': true, 'name': 'HEARTBEAT.md'});
    };
    final updated = await container
        .read(systemFileProvider('vps', 'HEARTBEAT.md').notifier)
        .save('# hb\n');
    expect(updated.content, '# hb\n');
    expect(saved['content'], '# hb\n');

    final prefs = await container.read(
      systemFileProvider('vps', 'PREFERENCES.md').future,
    );
    expect(prefs.content, '# prefs\n');
    expect(
      calls.any(
        (c) =>
            c.method == 'GET' && c.path == '/api/plugins/hermuse/preferences',
      ),
      isTrue,
    );

    await expectLater(
      container.read(systemFileProvider('vps', '../x').future),
      throwsA(isA<ArgumentError>()),
    );
  });

  Map<String, Object?> taskRow(
    String id,
    String finishedAt, {
    String? status,
  }) => {
    'id': id,
    'session_id': 's-$id',
    'turn_id': 't-$id',
    'title': 'Set daily 8am briefing',
    'summary': 'Scheduled daily 8:00 AM Nantes briefing',
    'status': ?status,
    'source': 'chat',
    'started_at': finishedAt,
    'finished_at': finishedAt,
    'tools': ['cronjob', 'web_search'],
  };

  group('Activity tasks', () {
    test('decode the plugin shape', () {
      final task = Task.fromJson({
        ...taskRow('a', '2026-10-02T08:00:05Z', status: 'interrupted'),
        'source': 'heartbeat',
        'started_at': '2026-10-02T08:00:00Z',
      });
      expect(task.title, 'Set daily 8am briefing');
      expect(task.summary, 'Scheduled daily 8:00 AM Nantes briefing');
      expect(task.status, TaskStatus.interrupted);
      expect(task.source, TaskSource.heartbeat);
      expect(task.sessionId, 's-a');
      expect(task.startedAt, DateTime.utc(2026, 10, 2, 8));
      expect(task.finishedAt, DateTime.utc(2026, 10, 2, 8, 0, 5));
      expect(task.kind, ToolKind.web);
      expect(Task.fromJson(const {'id': 'b'}).status, TaskStatus.completed);
      expect(
        Task.fromJson(const {'id': 'b', 'source': 'x'}).source,
        TaskSource.other,
      );
    });

    test('group by local day, newest first', () {
      final now = DateTime(2026, 10, 2, 9);
      Task at(DateTime when) =>
          Task.fromJson({...taskRow('x', when.toUtc().toIso8601String())});
      final days = activityDays([
        at(DateTime(2026, 10, 2, 8, 30)),
        at(DateTime(2026, 10, 2, 0, 5)),
        at(DateTime(2026, 10, 1, 23, 59)),
        at(DateTime(2026, 9, 28, 12)),
        at(DateTime(2026, 9, 20, 12)),
        at(DateTime(2025, 12, 31, 12)),
      ], now);
      expect(
        [for (final d in days) (d.label, d.items.length)],
        [
          ('Today', 2),
          ('Yesterday', 1),
          ('Monday', 1),
          ('Sep 20', 1),
          ('Dec 31, 2025', 1),
        ],
      );
    });

    test('load from the plugin and reload on sessions.changed', () async {
      var served = 0;
      routes['GET /api/plugins/hermuse/tasks'] = (request) {
        served++;
        expect(request.url.queryParameters['limit'], '100');
        return json({
          'tasks': [
            for (var i = served; i > 0; i--)
              taskRow('$i', '2026-10-02T08:0$i:00Z'),
          ],
        });
      };
      final sub = container.listen(tasksProvider('vps'), (_, _) {});
      addTearDown(sub.close);
      expect(
        (await container.read(tasksProvider('vps').future)).single.id,
        '1',
      );
      // The connection opens alongside; its writes reload the list.
      await container.read(connectionProvider('vps').future);
      fake.emitEvent('sessions.changed');
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      final tasks = await container.read(tasksProvider('vps').future);
      expect(tasks.map((t) => t.id), ['2', '1']);
    });
  });

  test('memory entries read and save per target', () async {
    routes['GET /api/plugins/hermuse/memory/user'] = (_) => json({
      'target': 'user',
      'entries': ['Lives in Nantes', 'Prefers trains'],
      'updated_at': '2026-10-01T10:00:00Z',
    });
    Object? saved;
    routes['PUT /api/plugins/hermuse/memory/user'] = (request) {
      saved = jsonDecode(request.body);
      return json({'ok': true});
    };
    final provider = agentMemoryProvider('vps', MemoryTarget.user);
    final memory = await container.read(provider.future);
    expect(memory.entries, ['Lives in Nantes', 'Prefers trains']);
    expect(memory.updatedAt, DateTime.utc(2026, 10, 1, 10));
    await container.read(provider.notifier).save([
      ' Lives in Nantes ',
      '',
      'Vegetarian',
    ]);
    expect(saved, {
      'entries': ['Lives in Nantes', 'Vegetarian'],
    });
    expect(container.read(provider).value!.entries, [
      'Lives in Nantes',
      'Vegetarian',
    ]);
    expect(MemoryTarget.memory.fileName, 'MEMORY.md');
  });

  test('approvals mode reads and writes approvals.mode', () async {
    var mode = 'manual';
    fake
      ..on('config.get', (params) {
        expect(params['key'], 'approvals.mode');
        return {'value': mode};
      })
      ..on('config.set', (params) {
        mode = params['value']! as String;
        return {'key': 'approvals.mode', 'value': mode};
      });
    final provider = approvalsModeProvider('vps');
    expect(await container.read(provider.future), ApprovalsMode.manual);
    await container.read(provider.notifier).set(ApprovalsMode.off);
    expect(mode, 'off');
    expect(container.read(provider).value, ApprovalsMode.off);
    expect(ApprovalsMode.fromValue(null), ApprovalsMode.smart);
    expect(ApprovalsMode.smart.label, 'Ask only when needed');
  });

  test('SOUL saves through profiles.configure', () async {
    fake.on('profiles.configure', (params) {
      expect(params['name'], 'aya');
      expect(params['soul'], 'You are Aya.');
      return {
        'ok': true,
        'applied': {'soul': true},
      };
    });
    fake.on('profiles.list', (_) => {'profiles': const []});
    await container
        .read(agentProfilesProvider('vps').notifier)
        .saveSoul('aya', 'You are Aya.');
    fake.on('profiles.configure', (_) => {'ok': true, 'applied': const {}});
    await expectLater(
      container
          .read(agentProfilesProvider('vps').notifier)
          .saveSoul('aya', 'x'),
      throwsA(isA<AgentWriteException>()),
    );
  });

  test('goals: sections, subgoal, rename, complete, delete', () async {
    Map<String, Object?> goal(
      String id, {
      String source = 'user',
      String? parent,
      bool done = false,
    }) => {
      ...((goalsFixture()['goals'] as List).first as Map<String, Object?>),
      'id': id,
      'title': id,
      'source': source,
      'status_line': 'on track',
      'done': done,
      'parent_id': parent,
      'cron_job_id': null,
    };
    routes['GET /api/plugins/hermuse/goals'] = (_) => json({
      'goals': [
        goal('trip', source: 'agent'),
        goal('run'),
        goal('book', parent: 'trip'),
        goal('orphan', parent: 'gone'),
      ],
    });
    routes['POST /api/plugins/hermuse/goals'] = (_) =>
        json(goal('hotel', parent: 'trip'), 201);
    routes['PATCH /api/plugins/hermuse/goals/run'] = (request) {
      final body = jsonDecode(request.body) as Map<String, Object?>;
      return json({
        ...goal('run', done: body['done'] == true),
        if (body['title'] case final String title) 'title': title,
      });
    };
    routes['DELETE /api/plugins/hermuse/goals/trip'] = (_) =>
        json({'ok': true});
    final notifier = container.read(goalsProvider('vps').notifier);
    final goals = await container.read(goalsProvider('vps').future);
    final sections = goalSections(goals);
    expect(sections.tracking.map((g) => g.id), ['trip']);
    expect(sections.goals.map((g) => g.id), ['run', 'orphan']);
    expect(sections.subgoalsOf(goals.first).map((g) => g.id), ['book']);
    expect(goals.first.statusLine, 'on track');
    expect(goals.first.source, GoalSource.agent);

    await notifier.addSubgoal(parent: goals.first, title: 'Book hotel');
    expect(calls.last.body, {
      'title': 'Book hotel',
      'category': 'health',
      'why': 'Part of "trip"',
      'source': 'user',
      'parent_id': 'trip',
    });
    await container.read(goalsProvider('vps').future);
    expect((await notifier.rename('run', ' Run 10k ')).title, 'Run 10k');
    expect(calls.last.body, {'title': 'Run 10k'});
    expect((await notifier.complete('run')).done, isTrue);
    expect(calls.last.body, {'done': true});
    await notifier.delete('trip');
    expect(calls.last.method, 'DELETE');
    expect(container.read(goalsProvider('vps')).value!.map((g) => g.id), [
      'run',
      'orphan',
    ]);
    // Records written before: user goals, done from the status.
    final legacy = Goal.fromJson({'id': 'old', 'status': 'done'});
    expect(
      (legacy.source, legacy.done, legacy.parentId),
      (GoalSource.user, true, null),
    );
  });

  test('feed: why, image, delete, generate', () async {
    routes['GET /api/plugins/hermuse/feed'] = (_) => json({
      'posts': [
        {
          ...((feedFixture()['posts'] as List).first as Map<String, Object?>),
          'why': 'You asked about Lisbon.',
          'image_url': 'https://img.example/1.jpg',
        },
        (feedFixture()['posts'] as List).last,
      ],
    });
    routes['DELETE /api/plugins/hermuse/feed/6372ea12f016'] = (_) =>
        json({'ok': true});
    routes['POST /api/plugins/hermuse/feed/generate'] = (_) =>
        json({'job_id': 'feedjob', 'started': true});
    final posts = await container.read(feedProvider('vps').future);
    expect(posts.first.why, 'You asked about Lisbon.');
    expect(posts.first.imageUrl, 'https://img.example/1.jpg');
    expect((posts.last.why, posts.last.imageUrl), ('', null));
    final notifier = container.read(feedProvider('vps').notifier);
    final run = await notifier.generate();
    expect((run.jobId, run.started), ('feedjob', true));
    await notifier.delete('6372ea12f016');
    expect(container.read(feedProvider('vps')).value!.map((p) => p.id), [
      'a1b2c3d4e5f6',
    ]);
  });

  test('ideas: starter catalog flags and dismiss', () async {
    routes['GET /api/plugins/hermuse/ideas'] = (_) => json({
      'ideas': [
        {
          'id': 'seed-workout',
          'title': 'Plan my workouts',
          'pitch': 'A weekly plan.',
          'group': 'Health',
          'first_step': 'Tell me your goal',
          'file': null,
          'created_at': null,
          'feedback': <Object?>[],
          'seeded': true,
          'icon': 'workout',
        },
        ...(ideasFixture()['ideas'] as List),
      ],
    });
    routes['POST /api/plugins/hermuse/ideas/seed-workout/dismiss'] = (_) =>
        json({'ok': true});
    final ideas = await container.read(ideasProvider('vps').future);
    expect(
      (ideas.first.seeded, ideas.first.icon, ideas.first.file),
      (true, 'workout', ''),
    );
    expect((ideas.last.seeded, ideas.last.icon), (false, ''));
    await container.read(ideasProvider('vps').notifier).dismiss('seed-workout');
    expect(container.read(ideasProvider('vps')).value!.map((i) => i.id), [
      '9432126be5b7',
    ]);
  });
}
