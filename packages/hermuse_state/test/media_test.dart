import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

const _plugin = '/api/plugins/hermuse';

Map<String, Object?> job(
  String id, {
  String kind = 'portrait',
  String status = 'running',
  List<String> candidates = const [],
  Map<String, String> states = const {},
  String? error,
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'candidates': candidates,
  'states': states,
  'error': error,
  'started_at': '2026-10-04T10:00:00+00:00',
  'finished_at': status == 'running' ? null : '2026-10-04T10:00:30+00:00',
};

Map<String, Object?> avatar({
  bool portrait = false,
  Map<String, String> states = const {},
  Map<String, Object?>? job,
  String? updatedAt,
}) => {
  'portrait_url': portrait ? '$_plugin/avatar/portrait' : null,
  'states': {
    for (final state in states.keys) state: '$_plugin/avatar/states/$state',
  },
  'job': job,
  'updated_at': updatedAt,
};

void main() {
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ProviderContainer container;
  late Map<String, http.Response Function(http.Request)> routes;
  late List<http.Request> calls;

  http.Response json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response bytes(List<int> body) =>
      http.Response.bytes(body, 200, headers: {'content-type': 'image/jpeg'});

  Map<String, Object?>? body(http.Request request) => request.body.isEmpty
      ? null
      : jsonDecode(request.body) as Map<String, Object?>;

  int count(String method, String path) => calls
      .where((c) => c.method == method && c.url.path == '$_plugin$path')
      .length;

  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('condition not reached');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    routes = {};
    calls = [];
    final mock = MockClient((request) async {
      calls.add(request);
      final route = routes['${request.method} ${request.url.path}'];
      if (route == null) return json({'detail': 'not found'}, 404);
      return route(request);
    });
    HermesRestClient rest(String? profile) => HermesRestClient(
      mock,
      baseUrl: Uri.parse('https://vps.example'),
      profile: profile,
    );
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider('vps').overrideWith((ref) => rest(null)),
        restClientProvider(
          'vps',
          profile: 'aya',
        ).overrideWith((ref) => rest('aya')),
        avatarJobPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 10),
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

  group('media provider', () {
    test(
      'config reads, saves with a write-only token, refreshes status',
      () async {
        var config = <String, Object?>{
          'provider': 'contentflow',
          'endpoint': '',
          'has_token': false,
          'image_model': 'Nano Banana',
          'video_model': 'Omni 1.1 Flash',
          'feed_fallback': false,
          'from_env': false,
        };
        var probes = 0;
        routes['GET $_plugin/media/config'] = (_) => json(config);
        routes['PUT $_plugin/media/config'] = (request) {
          final sent = body(request)!;
          config = {
            ...config,
            'endpoint': sent['endpoint'],
            'has_token': sent['token'] is String
                ? (sent['token']! as String).isNotEmpty
                : config['has_token'],
            if (sent['feed_fallback'] case final bool fallback)
              'feed_fallback': fallback,
          };
          return json(config);
        };
        routes['GET $_plugin/media/status'] = (_) {
          probes++;
          return json({
            'configured': (config['endpoint']! as String).isNotEmpty,
            'reachable': true,
            'credits': 120,
            'video_cost': 7,
            'error': null,
          });
        };

        final initial = await container.read(mediaConfigProvider('vps').future);
        expect(initial.configured, isFalse);
        expect(initial.imageModel, 'Nano Banana');
        expect(initial.videoModel, 'Omni 1.1 Flash');
        final before = await container.read(mediaStatusProvider('vps').future);
        expect(before.configured, isFalse);

        final saved = await container
            .read(mediaConfigProvider('vps').notifier)
            .save(
              endpoint: ' http://flow.lan:8000 ',
              token: 'secret',
              feedFallback: true,
            );
        final put = calls.lastWhere((c) => c.method == 'PUT');
        // Server-wide: never scoped to a profile.
        expect(put.url.queryParameters, isEmpty);
        expect(body(put), {
          'endpoint': 'http://flow.lan:8000',
          'token': 'secret',
          'feed_fallback': true,
        });
        expect(saved.configured, isTrue);
        expect(saved.hasToken, isTrue);
        expect(saved.feedFallback, isTrue);
        expect(
          container.read(mediaConfigProvider('vps')).value!.endpoint,
          'http://flow.lan:8000',
        );

        // Token omitted keeps it.
        await container
            .read(mediaConfigProvider('vps').notifier)
            .save(endpoint: 'http://flow.lan:8000');
        expect(body(calls.lastWhere((c) => c.method == 'PUT')), {
          'endpoint': 'http://flow.lan:8000',
        });

        final status = await container.read(mediaStatusProvider('vps').future);
        expect(status.configured, isTrue);
        expect(status.credits, 120);
        expect(status.videoCost, 7);
        expect(status.error, isNull);
        final refreshed = await container
            .read(mediaStatusProvider('vps').notifier)
            .refresh();
        expect(refreshed.reachable, isTrue);
        expect(probes, greaterThanOrEqualTo(3));
      },
    );

    test('status reports an unreachable service', () async {
      routes['GET $_plugin/media/status'] = (_) => json({
        'configured': true,
        'reachable': false,
        'credits': null,
        'video_cost': null,
        'error': 'connection refused',
      });
      final status = await container.read(mediaStatusProvider('vps').future);
      expect(status.reachable, isFalse);
      expect(status.error, 'connection refused');
      expect(animationCost(customAvatarStates, status), isNull);
      expect(animationCostLine(customAvatarStates, status), '4 animations');
    });

    test('animation cost is states times the clip price', () {
      const status = MediaStatus(
        configured: true,
        reachable: true,
        videoCost: 7,
      );
      expect(animationCost(customAvatarStates, status), 28);
      expect(
        animationCostLine(customAvatarStates, status),
        '4 animations · 28 credits',
      );
      expect(animationCostLine(['idle'], status), '1 animation · 7 credits');
      expect(animationCost(['idle'], null), isNull);
    });
  });

  group('agent avatar', () {
    test('generate, poll, select, animate, load images', () async {
      var current = avatar();
      var portraitPolls = 0;
      var animatePolls = 0;
      final candidates = [
        for (var i = 0; i < 4; i++) '$_plugin/avatar/candidates/p1/$i',
      ];
      routes.addAll({
        'GET $_plugin/avatar': (_) => json(current),
        'POST $_plugin/avatar/portrait': (_) => json(job('p1'), 202),
        'GET $_plugin/avatar/jobs/p1': (_) => json(
          ++portraitPolls < 2
              ? job('p1')
              : job('p1', status: 'done', candidates: candidates),
        ),
        'GET $_plugin/avatar/candidates/p1/1': (_) => bytes([1, 1]),
        'POST $_plugin/avatar/select': (_) {
          current = avatar(
            portrait: true,
            updatedAt: '2026-10-04T10:01:00+00:00',
          );
          return json(current);
        },
        'GET $_plugin/avatar/portrait': (_) => bytes([2, 2]),
        'POST $_plugin/avatar/animate': (_) => json(
          job(
            'a1',
            kind: 'animate',
            states: {for (final s in customAvatarStates) s: 'queued'},
          ),
          202,
        ),
        'GET $_plugin/avatar/jobs/a1': (_) {
          animatePolls++;
          if (animatePolls == 1) {
            current = avatar(
              portrait: true,
              states: {'idle': 'done'},
              updatedAt: '2026-10-04T10:02:00+00:00',
            );
            return json(
              job(
                'a1',
                kind: 'animate',
                states: {
                  'idle': 'done',
                  'thinking': 'running',
                  'replying': 'queued',
                  'working': 'queued',
                },
              ),
            );
          }
          current = avatar(
            portrait: true,
            states: {'idle': '', 'thinking': '', 'working': ''},
            updatedAt: '2026-10-04T10:03:00+00:00',
          );
          return json(
            job(
              'a1',
              kind: 'animate',
              status: 'done',
              states: {
                'idle': 'done',
                'thinking': 'done',
                'replying': 'failed',
                'working': 'done',
              },
            ),
          );
        },
        'GET $_plugin/avatar/states/idle': (_) => bytes([3, 3]),
      });

      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      final initial = await container.read(provider.future);
      expect(initial.hasPortrait, isFalse);
      expect(initial.states, isEmpty);
      final notifier = container.read(provider.notifier);

      final started = await notifier.generatePortraits(
        '  A calm librarian  ',
        count: 4,
      );
      expect(started.kind, AvatarJobKind.portrait);
      expect(started.running, isTrue);
      final post = calls.lastWhere((c) => c.method == 'POST');
      expect(post.url.queryParameters['profile'], 'aya');
      expect(body(post), {
        'profile': 'aya',
        'description': 'A calm librarian',
        'count': 4,
      });
      expect(container.read(provider).value!.job!.running, isTrue);

      await until(() => container.read(provider).value?.job?.running == false);
      final portraitJob = container.read(provider).value!.job!;
      expect(portraitJob.status, AvatarJobStatus.done);
      expect(portraitJob.candidates, candidates);

      expect(await notifier.candidateBytes(candidates[1]), [1, 1]);
      expect(await notifier.candidateBytes(candidates[1]), [1, 1]);
      expect(count('GET', '/avatar/candidates/p1/1'), 1);

      final selected = await notifier.select(1);
      expect(body(calls.lastWhere((c) => c.method == 'POST')), {
        'profile': 'aya',
        'candidate': 1,
      });
      expect(selected.hasPortrait, isTrue);
      expect(await notifier.portraitBytes(), [2, 2]);
      expect(await notifier.imageBytes(null), [2, 2]);
      expect(count('GET', '/avatar/portrait'), 1);
      expect(() => notifier.stateBytes('idle'), throwsA(isA<StateError>()));

      final animation = await notifier.animate();
      expect(animation.kind, AvatarJobKind.animate);
      expect(body(calls.lastWhere((c) => c.method == 'POST')), {
        'profile': 'aya',
      });

      // The first clip shows up while the others are still generating.
      await until(
        () =>
            container.read(provider).value?.states.containsKey('idle') ?? false,
      );
      expect(
        container.read(provider).value!.job!.states['thinking'],
        AvatarStateStatus.running,
      );
      expect(await notifier.stateBytes('idle'), [3, 3]);

      await until(() => container.read(provider).value?.job?.running == false);
      final done = container.read(provider).value!;
      expect(done.states.keys, ['idle', 'thinking', 'working']);
      expect(done.job!.states['replying'], AvatarStateStatus.failed);

      // A new updated_at drops the cached images.
      expect(await notifier.portraitBytes(), [2, 2]);
      expect(count('GET', '/avatar/portrait'), 2);

      final polls = animatePolls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(animatePolls, polls, reason: 'polling stops once done');
    });

    test('a running job found on load is followed', () async {
      var polls = 0;
      routes.addAll({
        'GET $_plugin/avatar': (_) =>
            json(avatar(job: polls == 0 ? job('p2') : null)),
        'GET $_plugin/avatar/jobs/p2': (_) {
          polls++;
          return json(
            job(
              'p2',
              status: 'failed',
              error: 'WafRejectionError: PUBLIC_ERROR_UNUSUAL_ACTIVITY',
            ),
          );
        },
      });
      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await container.read(provider.future);
      await until(() => container.read(provider).value?.job?.running == false);
      final failed = container.read(provider).value!.job!;
      expect(failed.status, AvatarJobStatus.failed);
      expect(failed.error, contains('WafRejectionError'));
    });

    test('polling stops when the provider is disposed', () async {
      var polls = 0;
      routes.addAll({
        'GET $_plugin/avatar': (_) => json(avatar()),
        'POST $_plugin/avatar/portrait': (_) => json(job('p3'), 202),
        'GET $_plugin/avatar/jobs/p3': (_) {
          polls++;
          return json(job('p3'));
        },
      });
      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      await container.read(provider.future);
      await container.read(provider.notifier).generatePortraits('An owl');
      await until(() => polls >= 2);
      sub.close();
      await container.pump();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final stopped = polls;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(polls, stopped);
      expect(container.exists(provider), isFalse);
    });

    test('a failed poll keeps the avatar and recovers', () async {
      var polls = 0;
      routes.addAll({
        'GET $_plugin/avatar': (_) => json(
          avatar(portrait: true, updatedAt: '2026-10-04T10:00:00+00:00'),
        ),
        'POST $_plugin/avatar/animate': (_) =>
            json(job('a2', kind: 'animate'), 202),
        'GET $_plugin/avatar/jobs/a2': (_) => ++polls == 1
            ? json({'detail': 'store unavailable'}, 500)
            : json(job('a2', kind: 'animate', status: 'done')),
      });
      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await container.read(provider.future);
      await container.read(provider.notifier).animate(states: ['idle']);
      expect(body(calls.lastWhere((c) => c.method == 'POST')), {
        'profile': 'aya',
        'states': ['idle'],
      });
      await until(() => container.read(provider).hasError);
      final errored = container.read(provider);
      expect(errored.value!.hasPortrait, isTrue);
      expect(
        hermesReason(errored.error! as HermesException),
        'store unavailable',
      );
      await until(() => container.read(provider).value?.job?.running == false);
      expect(container.read(provider).hasError, isFalse);
    });

    test("refusals carry the server's reason", () async {
      routes['GET $_plugin/avatar'] = (_) => json(avatar());
      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);

      Matcher refused(int status, String reason) => throwsA(
        isA<HermesHttpError>()
            .having((e) => e.statusCode, 'statusCode', status)
            .having(hermesReason, 'reason', reason),
      );

      routes['POST $_plugin/avatar/animate'] = (_) =>
          json({'detail': 'an avatar job is already running'}, 409);
      await expectLater(
        notifier.animate(),
        refused(409, 'an avatar job is already running'),
      );
      routes['POST $_plugin/avatar/animate'] = (_) =>
          json({'detail': 'select a portrait first'}, 422);
      await expectLater(
        notifier.animate(),
        refused(422, 'select a portrait first'),
      );
      routes['POST $_plugin/avatar/portrait'] = (_) => json({
        'detail':
            'ContentFlow: WafRejectionError (PUBLIC_ERROR_UNUSUAL_ACTIVITY)',
      }, 502);
      await expectLater(
        notifier.generatePortraits('A fox'),
        refused(
          502,
          'ContentFlow: WafRejectionError (PUBLIC_ERROR_UNUSUAL_ACTIVITY)',
        ),
      );
      // Nothing was started, nothing is polled.
      expect(container.read(provider).value!.job, isNull);
      expect(() => notifier.portraitBytes(), throwsA(isA<StateError>()));
    });

    test('clear drops the generated avatar', () async {
      routes.addAll({
        'GET $_plugin/avatar': (_) => json(
          avatar(
            portrait: true,
            states: {'idle': ''},
            updatedAt: '2026-10-04T10:00:00+00:00',
          ),
        ),
        'DELETE $_plugin/avatar': (_) => json({'ok': true}),
      });
      final provider = agentAvatarProvider('vps', profile: 'aya');
      final sub = container.listen(provider, (_, _) {});
      addTearDown(sub.close);
      expect((await container.read(provider.future)).states.keys, ['idle']);
      await container.read(provider.notifier).clear();
      expect(count('DELETE', '/avatar'), 1);
      final cleared = container.read(provider).value!;
      expect(cleared.hasPortrait, isFalse);
      expect(cleared.states, isEmpty);
    });
  });

  group('agent profiles', () {
    Map<String, Object?> row(String avatarId, {int revision = 3}) => {
      'name': 'aya',
      'path': '/home/hermes/.hermes/profiles/aya',
      'ui_meta': {
        'hermuse': {'display_name': 'Aya', 'avatar_id': avatarId},
      },
      'ui_meta_revisions': {'hermuse': revision},
    };

    test('a generated portrait is saved and read back as custom', () async {
      var stored = 'aya';
      Map<String, Object?>? sent;
      fake
        ..on(
          'profiles.list',
          (_) => {
            'profiles': [row(stored)],
          },
        )
        ..on('profiles.configure', (params) {
          sent = params;
          final meta = (params['ui_meta']! as Map)['hermuse'] as Map;
          stored = meta['avatar_id']! as String;
          return {
            'ok': true,
            'applied': {'soul': true, 'ui_meta': true},
          };
        });
      final agents = await container.read(agentProfilesProvider('vps').future);
      expect(agents.single.isCustom, isFalse);

      await container
          .read(agentProfilesProvider('vps').notifier)
          .saveAgent(
            agent: agents.single,
            name: 'Aya',
            avatarId: AgentAvatar.customId,
            prompt: 'You are Aya.',
          );
      expect(
        ((sent!['ui_meta']! as Map)['hermuse'] as Map)['avatar_id'],
        'custom',
      );
      expect(sent!['ui_meta_expected_revisions'], {'hermuse': 3});
      final saved = container.read(agentProfilesProvider('vps')).value!.single;
      expect(saved.avatarId, 'custom');
      expect(saved.isCustom, isTrue);
      expect(saved.avatar, same(AgentAvatar.custom));

      await expectLater(
        container
            .read(agentProfilesProvider('vps').notifier)
            .saveAgent(
              agent: saved,
              name: 'Aya',
              avatarId: 'generated',
              prompt: 'You are Aya.',
            ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
