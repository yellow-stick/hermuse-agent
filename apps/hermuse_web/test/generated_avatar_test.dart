import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:hermuse_web/agents.dart';
import 'package:hermuse_web/scope.dart';
import 'package:hermuse_web/settings.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_test/jaspr_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

const _plugin = '/api/plugins/hermuse';
const _candidates = [
  '$_plugin/avatar/candidates/p1/0',
  '$_plugin/avatar/candidates/p1/1',
];

http.Response _json(Object? payload, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(payload)),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _bytes(List<int> body, String type) =>
    http.Response.bytes(body, 200, headers: {'content-type': type});

Map<String, Object?> _config({String endpoint = '', bool hasToken = false}) => {
  'provider': 'contentflow',
  'endpoint': endpoint,
  'has_token': hasToken,
  'image_model': '',
  'video_model': '',
  'feed_fallback': false,
  'from_env': false,
};

Map<String, Object?> _status({
  bool configured = true,
  bool reachable = true,
  int? credits,
  int? videoCost,
  String? error,
}) => {
  'configured': configured,
  'reachable': reachable,
  'credits': credits,
  'video_cost': videoCost,
  'error': error,
};

Map<String, Object?> _job(
  String id, {
  String kind = 'portrait',
  String status = 'running',
  List<String> candidates = const [],
  Map<String, String> states = const {},
}) => {
  'id': id,
  'kind': kind,
  'status': status,
  'candidates': candidates,
  'states': states,
  'error': null,
  'started_at': '2026-10-04T10:00:00+00:00',
  'finished_at': status == 'running' ? null : '2026-10-04T10:00:30+00:00',
};

Map<String, Object?> _avatar({
  bool portrait = false,
  Iterable<String> states = const [],
  Map<String, Object?>? job,
}) => {
  'portrait_url': portrait ? '$_plugin/avatar/portrait' : null,
  'states': {for (final s in states) s: '$_plugin/avatar/states/$s'},
  'job': job,
  'updated_at': portrait ? '2026-10-04T10:01:00+00:00' : null,
};

ChatState _chat({bool busy = false}) => ChatState(
  agentName: 'Aya',
  threads: const [
    Thread(id: 'main', title: 'Main', startedAt: '', messages: []),
  ],
  activeThreadId: 'main',
  connection: ChatConnection.ready,
  busyThreads: busy ? {'main'} : {},
);

/// Agent writes recorded instead of sent to Hermes.
final class _FakeProfiles extends AgentProfiles {
  static final saved = <String>[];

  @override
  Future<List<AgentProfile>> build(String instanceId) async => const [
    AgentProfile(profile: 'aya', displayName: 'Aya', avatarId: 'noah'),
  ];

  @override
  Future<void> saveAgent({
    required AgentProfile agent,
    required String name,
    required String avatarId,
    required String prompt,
  }) async {
    saved.add('${agent.profile}:$avatarId');
  }

  @override
  Future<AgentProfile> create({
    required String name,
    required String avatarId,
    required String prompt,
  }) async {
    saved.add('created:$name:$avatarId');
    return AgentProfile(profile: 'aya', displayName: name, avatarId: avatarId);
  }
}

void main() {
  late ProviderContainer container;
  late Map<String, http.Response Function(http.Request)> routes;
  late List<http.Request> calls;

  int count(String method, String path) => calls
      .where((c) => c.method == method && c.url.path == '$_plugin$path')
      .length;

  /// The JSON body of the last [method] [path] call, without the client's
  /// profile scope.
  Map<String, Object?>? lastBody(String method, String path) {
    final call = calls.lastWhere(
      (c) => c.method == method && c.url.path == '$_plugin$path',
    );
    if (call.body.isEmpty) return null;
    return (jsonDecode(call.body) as Map<String, Object?>)..remove('profile');
  }

  /// Pumps until [done] holds (polls run on real 10 ms timers).
  Future<void> until(ComponentTester tester, bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('condition not reached');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await tester.pump();
    }
  }

  bool shows(String text) => find.text(text).evaluate().isNotEmpty;

  Finder pressable(String label) => find.byComponentPredicate(
    (c) =>
        (c is YsPressable && c.label == label) ||
        (c is YsFilledButton && c.label == label),
    description: 'button "$label"',
  );

  bool enabled(String label) {
    final button = find
        .descendant(of: pressable(label), matching: find.tag('button'))
        .evaluate()
        .single;
    return (button.component as DomComponent).attributes?['disabled'] == null;
  }

  Future<void> type(ComponentTester tester, String label, String text) async {
    final element = find
        .byComponentPredicate(
          (c) =>
              (c is YsTextBox && c.label == label) ||
              (c is YsInputBox && c.label == label),
        )
        .evaluate()
        .single;
    switch (element.component) {
      case final YsTextBox box:
        box.onChanged(text);
      case final YsInputBox box:
        box.onChanged(text);
    }
    await tester.pump();
  }

  Map<String, String> attributesOf(String tag) =>
      (find.tag(tag).evaluate().single.component as DomComponent).attributes ??
      const {};

  setUp(() {
    routes = {};
    calls = [];
    _FakeProfiles.saved.clear();
    final mock = MockClient((request) async {
      calls.add(request);
      final route = routes['${request.method} ${request.url.path}'];
      if (route == null) return _json({'detail': 'Not Found'}, 404);
      return route(request);
    });
    HermesRestClient rest(String? profile) => HermesRestClient(
      mock,
      baseUrl: Uri.parse('https://vps.example'),
      profile: profile,
    );
    container = ProviderContainer(
      overrides: [
        restClientProvider('vps').overrideWith((ref) => rest(null)),
        restClientProvider(
          'vps',
          profile: 'aya',
        ).overrideWith((ref) => rest('aya')),
        avatarJobPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 10),
        ),
        agentProfilesProvider('vps').overrideWith(_FakeProfiles.new),
        agentDetailsProvider('vps', 'aya').overrideWith(
          (ref) async => const AgentDetails(prompt: 'You are Aya.'),
        ),
      ],
    );
    HermuseScope.debugContainer = container;
  });

  tearDown(() {
    HermuseScope.debugContainer = null;
    container.dispose();
  });

  const aya = AgentProfile(
    profile: 'aya',
    displayName: 'Aya',
    avatarId: 'noah',
  );

  group('agent editor Generate', () {
    testComponents('without an image service shows the setup line', (
      tester,
    ) async {
      routes['GET $_plugin/media/config'] = (_) => _json(_config());
      routes['GET $_plugin/media/status'] = (_) =>
          _json(_status(configured: false, reachable: false));
      routes['GET $_plugin/avatar'] = (_) => _json(_avatar());
      var settings = 0;
      tester.pumpComponent(
        HermuseAgentEditor(
          instanceId: 'vps',
          agent: aya,
          onClose: () {},
          onOpenSettings: () => settings++,
        ),
      );
      await until(tester, () => shows('Generate'));
      await tester.click(pressable('Generate a portrait'));
      await until(
        tester,
        () => shows(
          'Portrait generation needs an image service. Set it up in '
          'Settings → Image generation.',
        ),
      );
      expect(pressable('Generate portraits'), findsNothing);
      await tester.click(pressable('Open Settings'));
      expect(settings, 1);
    });

    testComponents('generate → pick → animate, retrying only the failed clip', (
      tester,
    ) async {
      var avatar = _avatar();
      var animateJob = _job(
        'a1',
        kind: 'animate',
        states: {
          'idle': 'running',
          'thinking': 'queued',
          'replying': 'queued',
          'working': 'queued',
        },
      );
      routes['GET $_plugin/media/config'] = (_) =>
          _json(_config(endpoint: 'https://cf.example'));
      routes['GET $_plugin/media/status'] = (_) =>
          _json(_status(credits: 120, videoCost: 7));
      routes['GET $_plugin/avatar'] = (_) => _json(avatar);
      routes['POST $_plugin/avatar/portrait'] = (_) => _json(_job('p1'), 202);
      routes['GET $_plugin/avatar/jobs/p1'] = (_) =>
          _json(_job('p1', status: 'done', candidates: _candidates));
      for (final url in _candidates) {
        routes['GET $url'] = (_) => _bytes([1, 2, 3], 'image/jpeg');
      }
      routes['POST $_plugin/avatar/select'] = (_) {
        avatar = _avatar(portrait: true);
        return _json(avatar);
      };
      routes['GET $_plugin/avatar/portrait'] = (_) =>
          _bytes([4, 5, 6], 'image/jpeg');
      routes['POST $_plugin/avatar/animate'] = (_) => _json(animateJob, 202);
      routes['GET $_plugin/avatar/jobs/a1'] = (_) => _json(animateJob);
      routes['GET $_plugin/avatar/jobs/a2'] = (_) => _json(
        _job(
          'a2',
          kind: 'animate',
          status: 'done',
          states: {'working': 'done'},
        ),
      );

      tester.pumpComponent(
        HermuseAgentEditor(
          instanceId: 'vps',
          agent: aya,
          onClose: () {},
          onOpenSettings: () {},
        ),
      );
      await until(tester, () => shows('Generate'));
      await tester.click(pressable('Generate a portrait'));
      await until(tester, () => shows('Generate portraits'));
      expect(enabled('Generate portraits'), isFalse);

      await type(
        tester,
        'Describe your agent',
        'A cheerful plush fox with round glasses',
      );
      expect(enabled('Generate portraits'), isTrue);
      await tester.click(pressable('Generate portraits'));
      await until(tester, () => count('POST', '/avatar/portrait') == 1);
      expect(lastBody('POST', '/avatar/portrait'), {
        'description': 'A cheerful plush fox with round glasses',
        'count': 4,
      });

      // The job is polled until its candidates are in.
      await until(tester, () => pressable('Portrait 2').evaluate().isNotEmpty);
      expect(pressable('Portrait 1'), findsOneComponent);
      await until(
        tester,
        () => find
            .tag('img')
            .evaluate()
            .any(
              (e) => ((e.component as DomComponent).attributes?['src'] ?? '')
                  .startsWith('data:image/jpeg'),
            ),
      );

      await tester.click(pressable('Portrait 2'));
      await until(tester, () => _FakeProfiles.saved.isNotEmpty);
      expect(lastBody('POST', '/avatar/select'), {'candidate': 1});
      expect(_FakeProfiles.saved, ['aya:custom']);

      // The preview and the tile show the picked portrait; Animate costs
      // the four clips.
      await until(tester, () => shows('4 animations · 28 credits'));
      expect(shows('Generated'), isTrue);
      await tester.click(pressable('Animate'));
      await until(tester, () => count('POST', '/avatar/animate') == 1);
      expect(lastBody('POST', '/avatar/animate'), isEmpty);
      await until(tester, () => shows('Generating…'));
      expect(
        shows(
          'You can save the agent now; the animations keep going on the '
          'server.',
        ),
        isTrue,
      );

      // The run ends with the working clip failed.
      avatar = _avatar(
        portrait: true,
        states: ['idle', 'thinking', 'replying'],
      );
      animateJob = _job(
        'a1',
        kind: 'animate',
        status: 'done',
        states: {
          'idle': 'done',
          'thinking': 'done',
          'replying': 'done',
          'working': 'failed',
        },
      );
      await until(tester, () => shows('Failed'));
      expect(find.text('Done'), findsNComponents(3));
      expect(shows('1 animation · 7 credits'), isTrue);

      routes['POST $_plugin/avatar/animate'] = (_) => _json(
        _job('a2', kind: 'animate', states: {'working': 'running'}),
        202,
      );
      await tester.click(pressable('Retry failed animations'));
      await until(tester, () => count('POST', '/avatar/animate') == 2);
      expect(lastBody('POST', '/avatar/animate'), {
        'states': ['working'],
      });
    });

    testComponents('a new agent is created before its first generation', (
      tester,
    ) async {
      routes['GET $_plugin/media/config'] = (_) =>
          _json(_config(endpoint: 'https://cf.example'));
      routes['GET $_plugin/media/status'] = (_) => _json(_status());
      routes['GET $_plugin/avatar'] = (_) => _json(_avatar());
      routes['POST $_plugin/avatar/portrait'] = (_) => _json(_job('p1'), 202);
      routes['GET $_plugin/avatar/jobs/p1'] = (_) => _json(_job('p1'));
      tester.pumpComponent(
        HermuseAgentEditor(instanceId: 'vps', onClose: () {}),
      );
      await tester.click(pressable('Generate a portrait'));
      await until(tester, () => shows('Generate portraits'));
      await type(tester, 'Describe your agent', 'A green owl');
      await tester.click(pressable('Generate portraits'));
      await until(tester, () => count('POST', '/avatar/portrait') == 1);
      expect(_FakeProfiles.saved, ['created:Noah:noah']);
      expect(calls.last.url.queryParameters['profile'], 'aya');
      await until(
        tester,
        () => shows('Generating portraits… about 15 seconds'),
      );
    });
  });

  group('custom avatar', () {
    void serveCustom() {
      routes['GET $_plugin/avatar'] = (_) =>
          _json(_avatar(portrait: true, states: customAvatarStates));
      routes['GET $_plugin/avatar/portrait'] = (_) =>
          _bytes([4, 5, 6], 'image/jpeg');
      for (final state in customAvatarStates) {
        routes['GET $_plugin/avatar/states/$state'] = (_) =>
            _bytes([7, 8, 9], 'image/webp');
      }
    }

    testComponents(
      'animates only for no-preference motion; the img is the portrait',
      (tester) async {
        serveCustom();
        tester.pumpComponent(
          HermuseAgentAvatar(
            instanceId: 'vps',
            profile: 'aya',
            avatarId: 'custom',
            chat: _chat(busy: true),
            size: 100,
          ),
        );
        await until(tester, () => find.tag('source').evaluate().isNotEmpty);
        final source = attributesOf('source');
        expect(source['media'], '(prefers-reduced-motion: no-preference)');
        expect(source['srcset'], startsWith('data:image/webp'));
        // Reduced motion keeps the static portrait (the <img>).
        await until(
          tester,
          () =>
              (attributesOf('img')['src'] ?? '').startsWith('data:image/jpeg'),
        );
        expect(count('GET', '/avatar/states/thinking'), 1);
        expect(count('GET', '/avatar/states/idle'), 0);
      },
    );

    testComponents('without a chat the portrait stays static', (tester) async {
      serveCustom();
      tester.pumpComponent(
        HermuseAgentAvatar(
          instanceId: 'vps',
          profile: 'aya',
          avatarId: 'custom',
          size: 36,
        ),
      );
      await until(
        tester,
        () => (attributesOf('img')['src'] ?? '').startsWith('data:image/jpeg'),
      );
      expect(find.tag('source'), findsNothing);
    });

    testComponents('a bundled avatar never asks the plugin', (tester) async {
      tester.pumpComponent(
        HermuseAgentAvatar(
          instanceId: 'vps',
          profile: 'aya',
          avatarId: 'noah',
          chat: _chat(busy: true),
        ),
      );
      await tester.pump();
      expect(attributesOf('img')['src'], '/images/agents/noah.webp');
      expect(calls, isEmpty);
    });
  });

  group('Settings → Image generation', () {
    testComponents('saves the endpoint and token, tests the service', (
      tester,
    ) async {
      var config = _config();
      var status = _status(configured: false, reachable: false);
      routes['GET $_plugin/media/config'] = (_) => _json(config);
      routes['GET $_plugin/media/status'] = (_) => _json(status);
      routes['PUT $_plugin/media/config'] = (request) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        config = _config(
          endpoint: body['endpoint']! as String,
          hasToken: body['token'] != null,
        );
        return _json(config);
      };
      tester.pumpComponent(
        const HermuseImageGenerationSection(instanceId: 'vps'),
      );
      await until(
        tester,
        () => shows(
          'Not set up: nothing is generated until you enter an endpoint.',
        ),
      );
      expect(
        shows(
          'Generates agent portraits, their animations and Feed '
          'illustrations with a ContentFlow service you run.',
        ),
        isTrue,
      );

      await type(tester, 'Endpoint', 'https://cf.example');
      await type(tester, 'Token', 'secret');
      // The models are advanced settings, collapsed at first.
      expect(shows('Image model'), isFalse);
      await tester.click(
        find.ancestor(of: find.text('Advanced'), matching: find.tag('button')),
      );
      expect(shows('Hide advanced'), isTrue);
      await type(tester, 'Video model', 'Omni 1.1 Flash');
      await tester.click(pressable('Illustrate Feed posts that have no image'));
      await tester.click(pressable('Save'));
      await until(tester, () => shows('Saved.'));
      expect(lastBody('PUT', '/media/config'), {
        'endpoint': 'https://cf.example',
        'token': 'secret',
        'image_model': '',
        'video_model': 'Omni 1.1 Flash',
        'feed_fallback': true,
      });
      expect(shows('Token saved'), isTrue);

      status = _status(credits: 120, videoCost: 7);
      await tester.click(pressable('Test'));
      await until(tester, () => shows('Reachable · 120 credits'));

      status = _status(reachable: false, error: 'WafRejectionError');
      await tester.click(pressable('Test'));
      await until(tester, () => shows('Not reachable: WafRejectionError'));
    });

    testComponents('a refused save shows the server detail', (tester) async {
      routes['GET $_plugin/media/config'] = (_) => _json(_config());
      routes['GET $_plugin/media/status'] = (_) =>
          _json(_status(configured: false, reachable: false));
      routes['PUT $_plugin/media/config'] = (_) =>
          _json({'detail': 'endpoint must be an http(s) URL'}, 422);
      tester.pumpComponent(
        const HermuseImageGenerationSection(instanceId: 'vps'),
      );
      await until(tester, () => pressable('Save').evaluate().isNotEmpty);
      await until(tester, () => enabled('Save'));
      await type(tester, 'Endpoint', 'ftp://nope');
      await tester.click(pressable('Save'));
      await until(
        tester,
        () => shows('Could not save: endpoint must be an http(s) URL'),
      );
    });
  });
}
