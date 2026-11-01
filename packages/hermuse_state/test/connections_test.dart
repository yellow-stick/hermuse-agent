import 'dart:async';
import 'dart:convert';

import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

/// `GET /api/providers/oauth` shape, captured from the real 0.21.5 dashboard.
Map<String, Object?> oauthFixture({
  bool nousLoggedIn = false,
  bool extraUnknown = false,
}) => {
  'providers': [
    {
      'id': 'nous',
      'name': 'Nous Portal',
      'flow': 'device_code',
      'cli_command': 'hermes auth add nous',
      'docs_url': 'https://portal.nousresearch.com',
      'disconnect_hint': null,
      'disconnect_command': null,
      'disconnectable': true,
      'status': {
        'logged_in': nousLoggedIn,
        'source': 'nous_portal',
        'source_label': 'Nous Portal',
        'token_preview': nousLoggedIn ? '…ABC123' : '',
        'expires_at': null,
        'has_refresh_token': nousLoggedIn,
        'free_tier': false,
        'account_tier': null,
      },
    },
    {
      'id': 'openai-codex',
      'name': 'ChatGPT or Codex Subscription',
      'flow': 'device_code',
      'cli_command': 'hermes auth add openai-codex',
      'docs_url': 'https://platform.openai.com/docs',
      'disconnect_hint': null,
      'disconnect_command': null,
      'disconnectable': true,
      'status': {
        'logged_in': false,
        'source': 'openai_codex',
        'source_label': 'OpenAI Codex',
        'token_preview': '',
        'expires_at': null,
        'has_refresh_token': false,
        'last_refresh': null,
      },
    },
    {
      // Hermes marks this `external`: its `/start` refuses it, so the card
      // delegates to the terminal (and later to the subscription bridge).
      'id': 'qwen-oauth',
      'name': 'Qwen (via Qwen CLI)',
      'flow': 'external',
      'cli_command': 'hermes auth add qwen-oauth',
      'docs_url': 'https://github.com/QwenLM/qwen-code',
      'disconnect_hint': "Managed by that provider's CLI; remove it there.",
      'disconnect_command': null,
      'disconnectable': false,
      'status': {
        'logged_in': false,
        'source': 'qwen_cli',
        'source_label': 'Qwen CLI',
        'token_preview': '',
        'expires_at': null,
        'has_refresh_token': false,
      },
    },
    {
      'id': 'anthropic',
      'name': 'Anthropic API Key',
      'flow': 'external',
      'cli_command': 'hermes auth add anthropic',
      'docs_url': 'https://docs.claude.com/en/api/getting-started',
      'disconnect_hint': null,
      'disconnect_command': null,
      'disconnectable': true,
      'status': {'logged_in': false, 'source': null},
    },
    if (extraUnknown)
      {
        'id': 'frobnicator-9000',
        'name': 'Frobnicator 9000',
        'flow': 'mystery_flow',
        'cli_command': 'frob auth',
        'docs_url': '',
        'disconnect_hint': null,
        'disconnect_command': null,
        'disconnectable': true,
        'status': {'logged_in': false, 'source_label': 'Frobnicator'},
      },
  ],
};

/// `GET /api/credentials/pool` shape, captured from the real dashboard.
Map<String, Object?> poolFixture() => {
  'providers': [
    {
      'provider': 'alibaba-token-plan',
      'entries': [
        {
          'index': 1,
          'id': '2cc16c',
          'label': 'ALIBABA_TOKEN_PLAN_API_KEY',
          'auth_type': 'api_key',
          'source': 'env:ALIBABA_TOKEN_PLAN_API_KEY',
          'priority': 0,
          'last_status': null,
          'request_count': 0,
          'token_preview': 'sk-s...5kcA',
          'has_refresh': false,
        },
      ],
    },
  ],
};

Map<String, Object?> endpointsFixture() => {
  'endpoints': <Object?>[],
  'current': {'provider': '', 'model': '', 'base_url': ''},
};

/// `GET /api/env` shape (flat map of var → row).
Map<String, Object?> envFixture({bool openaiSet = false}) => {
  'OPENAI_API_KEY': {
    'is_set': openaiSet,
    'redacted_value': openaiSet ? 'sk-...wxyz' : null,
    'description': 'OpenAI API key',
    'url': null,
    'category': 'provider',
    'is_password': true,
    'tools': <Object?>[],
    'advanced': false,
    'channel_managed': false,
    'provider': 'openai-api',
    'provider_label': 'OpenAI API',
    'custom': false,
  },
};

/// `model.options` rows, shaped like the real `include_unconfigured`
/// inventory: `auth_type`/`key_env` for unconfigured rows, bare for
/// configured ones.
Map<String, Object?> modelOptionsFixture() => {
  'providers': [
    {
      'slug': 'nous',
      'name': 'Nous Portal',
      'is_current': false,
      'is_user_defined': false,
      'models': <Object?>[],
      'total_models': 0,
      'source': 'canonical',
      'authenticated': false,
      'auth_type': 'oauth_device_code',
      'key_env': '',
      'warning': 'run `hermes model` to configure (oauth_device_code)',
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      'slug': 'openai-api',
      'name': 'OpenAI API',
      'is_current': false,
      'is_user_defined': false,
      'models': <Object?>[],
      'total_models': 0,
      'source': 'canonical',
      'authenticated': false,
      'auth_type': 'api_key',
      'key_env': 'OPENAI_API_KEY',
      'warning': 'paste OPENAI_API_KEY to activate',
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      'slug': 'anthropic',
      'name': 'Anthropic',
      'is_current': false,
      'is_user_defined': false,
      'models': ['claude-opus-4-5-20251101'],
      'total_models': 1,
      'source': 'hermes',
      'authenticated': true,
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      'slug': 'alibaba-token-plan',
      'name': 'Alibaba Cloud (Token Plan)',
      'is_current': false,
      'is_user_defined': false,
      'models': ['z-ai/glm-5.2'],
      'total_models': 1,
      'source': 'hermes',
      'authenticated': true,
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
  ],
  'model': '',
  'provider': '',
};

/// A REST double routing by method+path with a readable script.
final class ScriptedRest {
  ScriptedRest(this.routes);

  final Map<String, Future<http.Response> Function(http.Request)> routes;

  final List<({String method, String path, Object? body})> calls = [];

  MockClient get client => MockClient((request) async {
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
    if (route == null) {
      return http.Response.bytes(
        utf8.encode('no route ${request.method} ${request.url.path}'),
        500,
      );
    }
    return route(request);
  });

  static Future<http.Response> Function(http.Request) json(
    Object? payload, [
    int status = 200,
  ]) =>
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  /// Same, for closures that compute the payload per request.
  static Future<http.Response> Function(http.Request) dynamicJson(
    Object? Function() payload,
  ) =>
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode(payload())),
        200,
        headers: {'content-type': 'application/json'},
      );
}

void main() {
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ScriptedRest rest;
  late ProviderContainer container;

  Map<String, Object?> oauth = oauthFixture();
  var polls = <Map<String, Object?>>[];
  var pollCount = 0;

  Map<String, Future<http.Response> Function(http.Request)> baseRoutes() => {
    'GET /api/providers/oauth': ScriptedRest.dynamicJson(() => oauth),
    'GET /api/credentials/pool': ScriptedRest.json(poolFixture()),
    'GET /api/providers/custom-endpoints': ScriptedRest.json(
      endpointsFixture(),
    ),
    'GET /api/env': ScriptedRest.json(envFixture()),
  };

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    oauth = oauthFixture();
    polls = [];
    pollCount = 0;
    rest = ScriptedRest(baseRoutes());
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider('vps').overrideWith(
          (ref) => HermesRestClient(
            rest.client,
            baseUrl: Uri.parse('https://vps.example'),
          ),
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
    fake.on('model.options', (_) => modelOptionsFixture());
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ConnectionsState> cards() =>
      container.read(connectionCardsProvider('vps').future);

  group('card descriptors', () {
    test('merge oauth catalog, pool, options and env', () async {
      final state = await cards();
      final byId = {for (final c in state.cards) c.id: c};

      final nous = byId['nous']!;
      expect(nous.flow, ConnectionFlow.deviceCode);
      expect(nous.state, ConnectionCardState.disconnected);
      expect(nous.name, 'Nous Portal');
      expect(nous.cliCommand, 'hermes auth add nous');

      // Registry api_key provider behind an `external` oauth flow keeps an
      // in-app key form. (The real 0.21.5 inventory omits auth_type/key_env
      // for configured rows, so this fixture only asserts the oauth merge.)
      expect(byId['anthropic']!.flow, ConnectionFlow.external);
      expect(byId['anthropic']!.disconnectable, isTrue);

      // Inventory-only api_key row gets its own card with the env hint.
      final openai = byId['openai-api']!;
      expect(openai.flow, ConnectionFlow.apiKey);
      expect(openai.keyEnv, 'OPENAI_API_KEY');
      expect(openai.detail, 'paste OPENAI_API_KEY to activate');

      // Pooled-only provider renders as a generic connected card.
      final pool = byId['alibaba-token-plan']!;
      expect(pool.state, ConnectionCardState.connected);
      expect(pool.poolEntries, hasLength(1));
      expect(pool.poolEntries.single.tokenPreview, 'sk-s...5kcA');
    });

    test('unknown provider ids render a generic card', () async {
      oauth = oauthFixture(extraUnknown: true);
      final state = await cards();
      final card = state.cards.where((c) => c.id == 'frobnicator-9000').single;
      expect(card.name, 'Frobnicator 9000');
      expect(card.flow, ConnectionFlow.external);
      expect(card.logoKey, 'frobnicator-9000');
      expect(card.state, ConnectionCardState.disconnected);
    });

    test('Hermes-external providers route to the external flow', () async {
      final state = await cards();
      final qwen = state.cards.where((c) => c.id == 'qwen-oauth').single;
      expect(qwen.flow, ConnectionFlow.external);
      expect(qwen.cliCommand, 'hermes auth add qwen-oauth');
      expect(qwen.disconnectable, isFalse);
    });

    test('connected card reflects logged_in status', () async {
      oauth = oauthFixture(nousLoggedIn: true);
      final state = await cards();
      final nous = state.cards.where((c) => c.id == 'nous').single;
      expect(nous.state, ConnectionCardState.connected);
      expect(nous.detail, 'Nous Portal');
    });
  });

  group('device-code flow', () {
    setUp(() {
      rest.routes['POST /api/providers/oauth/nous/start'] = ScriptedRest.json({
        'session_id': 'sess-1',
        'flow': 'device_code',
        'user_code': 'ABCD-1234',
        'verification_url': 'https://portal.nousresearch.com/device',
        'expires_in': 900,
        'poll_interval': 0,
      });
      rest.routes['GET /api/providers/oauth/nous/poll/sess-1'] =
          ScriptedRest.dynamicJson(() {
            final i = pollCount < polls.length ? pollCount : polls.length - 1;
            pollCount++;
            return polls[i];
          });
      rest.routes['DELETE /api/providers/oauth/sessions/sess-1'] =
          ScriptedRest.json({'ok': true, 'session_id': 'sess-1'});
      fake
        ..on(
          'setup.status',
          (_) => {
            'provider_configured': false,
            'ready': true,
            'free_tier': false,
            'other_providers': false,
            'inference_provider': '',
          },
        )
        ..on(
          'setup.runtime_check',
          (_) => {'ok': false, 'error': 'No usable credentials found.'},
        )
        ..on(
          'free_tier.status',
          (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': 'nous/welcome',
            'label': 'Nous · free tier',
          },
        );
    });

    test('polls to success and clears the pending login', () async {
      polls = [
        {'session_id': 'sess-1', 'status': 'pending'},
        {'session_id': 'sess-1', 'status': 'pending'},
        {'session_id': 'sess-1', 'status': 'approved'},
      ];
      // The approved login flips the card to connected on refresh.
      oauth = oauthFixture(nousLoggedIn: true);
      final notifier = container.read(connectionCardsProvider('vps').notifier);
      await container.read(connectionCardsProvider('vps').future);
      final result = await notifier.startDeviceCode('nous');
      expect(result.outcome, DevicePollOutcome.approved);
      final state = container.read(connectionCardsProvider('vps')).value!;
      expect(state.pendingLogin, isNull);
      expect(
        state.cards.where((c) => c.id == 'nous').single.state,
        ConnectionCardState.connected,
      );
      expect(pollCount, 3);
    });

    test('surfaces the server error message on failure', () async {
      polls = [
        {
          'session_id': 'sess-1',
          'status': 'error',
          'error_message': 'portal exploded',
        },
      ];
      final notifier = container.read(connectionCardsProvider('vps').notifier);
      await container.read(connectionCardsProvider('vps').future);
      final result = await notifier.startDeviceCode('nous');
      expect(result.outcome, DevicePollOutcome.error);
      expect(result.message, 'portal exploded');
      final state = container.read(connectionCardsProvider('vps')).value!;
      final nous = state.cards.where((c) => c.id == 'nous').single;
      expect(nous.state, ConnectionCardState.error);
      expect(nous.detail, 'portal exploded');
    });

    test('timeout and cancel settle the poll loop', () async {
      polls = [
        {'session_id': 'sess-1', 'status': 'pending'},
      ];
      final notifier = container.read(connectionCardsProvider('vps').notifier);
      await container.read(connectionCardsProvider('vps').future);
      final result = await notifier.startDeviceCode(
        'nous',
        timeout: const Duration(milliseconds: 50),
      );
      expect(result.outcome, DevicePollOutcome.timeout);

      // A fresh login can be cancelled: the server session is deleted.
      polls = [
        {'session_id': 'sess-1', 'status': 'pending'},
      ];
      pollCount = 0;
      final pending = notifier.startDeviceCode(
        'nous',
        timeout: const Duration(seconds: 5),
      );
      // Let the first poll land before cancelling.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await notifier.cancelLogin();
      final cancelled = await pending.timeout(const Duration(seconds: 10));
      expect(cancelled.outcome, DevicePollOutcome.cancelled);
      expect(
        rest.calls.any(
          (c) =>
              c.method == 'DELETE' &&
              c.path == '/api/providers/oauth/sessions/sess-1',
        ),
        isTrue,
      );
      expect(
        container.read(connectionCardsProvider('vps')).value!.pendingLogin,
        isNull,
      );
    });
  });

  group('api-key flow', () {
    setUp(() {
      fake
        ..on(
          'setup.status',
          (_) => {
            'provider_configured': true,
            'ready': true,
            'free_tier': false,
            'other_providers': true,
            'inference_provider': 'openai-api',
          },
        )
        ..on(
          'setup.runtime_check',
          (_) => {
            'ok': true,
            'provider': 'openai-api',
            'model': 'gpt-5',
            'source': 'env:OPENAI_API_KEY',
            'free_tier': false,
          },
        )
        ..on(
          'free_tier.status',
          (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': 'nous/welcome',
            'label': 'Nous · free tier',
          },
        );
    });

    test('validation failure surfaces the server message', () async {
      rest.routes['POST /api/providers/validate'] = ScriptedRest.json({
        'ok': false,
        'reachable': true,
        'message': 'That API key was rejected. Double-check it and try again.',
      });
      await cards();
      await expectLater(
        container
            .read(connectionCardsProvider('vps').notifier)
            .saveApiKey('openai-api', 'sk-bad'),
        throwsA(
          isA<ConnectionRejected>().having(
            (e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
      // Nothing was persisted: no RPC save happened.
      expect(fake.calls.any((c) => c.method == 'model.save_key'), isFalse);
    });

    test('valid key is saved via model.save_key', () async {
      rest.routes['POST /api/providers/validate'] = ScriptedRest.json({
        'ok': true,
        'reachable': true,
        'message': '',
      });
      fake.on('model.save_key', (params) {
        expect(params['slug'], 'openai-api');
        expect(params['api_key'], 'sk-good');
        return {
          'provider': {
            'slug': 'openai-api',
            'name': 'OpenAI API',
            'is_current': false,
            'authenticated': true,
            'models': ['gpt-5'],
            'total_models': 1,
          },
        };
      });
      await cards();
      final provider = await container
          .read(connectionCardsProvider('vps').notifier)
          .saveApiKey('openai-api', 'sk-good');
      expect(provider.slug, 'openai-api');
      expect(provider.authenticated, isTrue);
      final validate = rest.calls
          .where(
            (c) => c.method == 'POST' && c.path == '/api/providers/validate',
          )
          .single;
      expect(validate.body, {'key': 'OPENAI_API_KEY', 'value': 'sk-good'});
    });
  });

  group('custom endpoints and disconnect', () {
    setUp(() {
      fake
        ..on(
          'setup.status',
          (_) => {
            'provider_configured': true,
            'ready': true,
            'free_tier': false,
            'other_providers': true,
            'inference_provider': 'openai-api',
          },
        )
        ..on(
          'setup.runtime_check',
          (_) => {
            'ok': true,
            'provider': 'openai-api',
            'model': 'gpt-5',
            'source': 'env:OPENAI_API_KEY',
            'free_tier': false,
          },
        )
        ..on(
          'free_tier.status',
          (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': 'nous/welcome',
            'label': 'Nous · free tier',
          },
        );
    });

    test('check probes with api_mode, add saves the chosen model', () async {
      rest.routes['POST /api/providers/custom-endpoints/validate'] =
          ScriptedRest.json({
            'ok': true,
            'reachable': true,
            'message': '',
            'models': ['claude-opus-5', 'glm-5.3', 'muse-spark-1.3'],
            'resolved_base_url': 'https://llm.example/v1',
          });
      rest.routes['POST /api/providers/custom-endpoints'] = ScriptedRest.json({
        'ok': true,
        'id': 'my-llm',
      });
      await cards();
      final notifier = container.read(connectionCardsProvider('vps').notifier);
      final probe = await notifier.checkCustomEndpoint(
        name: 'My LLM',
        baseUrl: 'https://llm.example',
        apiKey: 'sk-test',
        apiMode: 'anthropic_messages',
      );
      expect(probe.resolvedBaseUrl, 'https://llm.example/v1');
      expect(probe.models, ['claude-opus-5', 'glm-5.3', 'muse-spark-1.3']);
      final id = await notifier.addCustomEndpoint(
        name: 'My LLM',
        baseUrl: probe.resolvedBaseUrl,
        apiKey: 'sk-test',
        apiMode: 'anthropic_messages',
        model: 'muse-spark-1.3',
        models: probe.models,
      );
      expect(id, 'my-llm');
      final posts = [
        for (final c in rest.calls)
          if (c.method == 'POST') {'path': c.path, 'body': c.body},
      ];
      expect(posts, [
        {
          'path': '/api/providers/custom-endpoints/validate',
          'body': {
            'name': 'My LLM',
            'base_url': 'https://llm.example',
            'model': '',
            'api_mode': 'anthropic_messages',
            'api_key': 'sk-test',
          },
        },
        {
          'path': '/api/providers/custom-endpoints',
          'body': {
            'name': 'My LLM',
            'base_url': 'https://llm.example/v1',
            'model': 'muse-spark-1.3',
            'api_mode': 'anthropic_messages',
            'api_key': 'sk-test',
            'models': ['muse-spark-1.3', 'claude-opus-5', 'glm-5.3'],
          },
        },
      ]);
    });

    test('a refused check throws the server sentence', () async {
      rest.routes['POST /api/providers/custom-endpoints/validate'] =
          ScriptedRest.json({
            'ok': false,
            'reachable': true,
            'message': 'HTTP 401 from https://llm.example/v1/models',
            'models': <Object?>[],
          });
      await cards();
      await expectLater(
        container
            .read(connectionCardsProvider('vps').notifier)
            .checkCustomEndpoint(
              name: 'My LLM',
              baseUrl: 'https://llm.example',
            ),
        throwsA(
          isA<ConnectionRejected>().having(
            (e) => e.message,
            'message',
            'HTTP 401 from https://llm.example/v1/models',
          ),
        ),
      );
    });

    test('a saved endpoint card carries its api type and models', () async {
      rest.routes['GET /api/providers/custom-endpoints'] = ScriptedRest.json({
        'endpoints': [
          {
            'id': 'spideros-llm',
            'name': 'SpiderOS LLM',
            'base_url': 'https://llm.example/v1',
            'model': 'muse-spark-1.3-contributor',
            'api_mode': 'chat_completions',
            'models': ['claude-opus-5', 'muse-spark-1.3-contributor'],
          },
        ],
      });
      final card = (await cards()).cards.singleWhere(
        (c) => c.flow == ConnectionFlow.customEndpoint,
      );
      expect(card.id, 'custom:spideros-llm');
      expect(card.hermesProvider, 'spideros-llm');
      expect(card.apiMode, 'chat_completions');
      expect(card.defaultModel, 'muse-spark-1.3-contributor');
      expect(card.baseUrl, 'https://llm.example/v1');
      expect(
        card.detail,
        'OpenAI-compatible · muse-spark-1.3-contributor · 2 models',
      );
    });

    test('disconnect routes oauth, pool and env-var cards', () async {
      await cards();
      final notifier = container.read(connectionCardsProvider('vps').notifier);

      rest.routes['DELETE /api/providers/oauth/nous'] = ScriptedRest.json({
        'ok': true,
        'provider': 'nous',
      });
      await notifier.disconnect('nous');

      rest.routes['DELETE /api/credentials/pool/alibaba-token-plan/1'] =
          ScriptedRest.json({'ok': true, 'provider': 'alibaba-token-plan'});
      await notifier.disconnect('alibaba-token-plan');

      expect(
        rest.calls.where((c) => c.method == 'DELETE').map((c) => c.path),
        containsAll([
          '/api/providers/oauth/nous',
          '/api/credentials/pool/alibaba-token-plan/1',
        ]),
      );

      // Non-disconnectable external card without pool entries refuses.
      await expectLater(
        notifier.disconnect('qwen-oauth'),
        throwsA(isA<ConnectionRejected>()),
      );
    });
  });
  group('subscription bridge', () {
    late ProviderContainer bridgeContainer;
    late ScriptedRest sidecar;
    late int authStatusCalls;

    setUp(() async {
      sidecar = ScriptedRest({});
      authStatusCalls = 0;
      bridgeContainer = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          transportFactoryProvider.overrideWithValue((_) async => fake),
          restClientProvider('desk').overrideWith(
            (ref) => HermesRestClient(
              rest.client,
              baseUrl: Uri.parse('http://127.0.0.1:9119'),
            ),
          ),
          httpClientProvider.overrideWithValue(sidecar.client),
          bridgeHostProvider.overrideWithValue(
            _FakeBridgeHost(
              BridgeConnection(
                baseUrl: Uri.parse('http://127.0.0.1:8317'),
                apiKey: 'sidecar-api-key',
                managementKey: 'sidecar-mgmt-key',
              ),
            ),
          ),
        ],
      );
      // The sidecar serves the Hermes on this computer.
      final registry = await bridgeContainer.read(registryProvider.future);
      await registry.add(
        HermesInstance(
          id: 'desk',
          label: 'This computer',
          kind: InstanceKind.local,
          baseUrl: Uri.parse('http://127.0.0.1:9119'),
          auth: AuthMethod.loopbackToken,
        ),
      );
    });

    tearDown(() async {
      bridgeContainer.dispose();
    });

    Future<ConnectionsState> bridgeCards() =>
        bridgeContainer.read(connectionCardsProvider('desk').future);

    test('this computer\'s instance: hidden without a bridge host, shown '
        'with one', () async {
      final noHost = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          transportFactoryProvider.overrideWithValue((_) async => fake),
          restClientProvider('desk').overrideWith(
            (ref) => HermesRestClient(
              rest.client,
              baseUrl: Uri.parse('http://127.0.0.1:9119'),
            ),
          ),
        ],
      );
      addTearDown(noHost.dispose);
      expect(
        (await noHost.read(connectionCardsProvider('desk').future)).cards
            .any((c) => c.flow == ConnectionFlow.bridge),
        isFalse,
      );
      // With a host but no credentials: 8 advanced disconnected cards.
      sidecar.routes['GET /v0/management/auth-files'] = ScriptedRest.json({
        'observed_at': '2026-09-26T00:00:00Z',
        'files': [],
      });
      final state = await bridgeCards();
      final bridges = [
        for (final c in state.cards)
          if (c.flow == ConnectionFlow.bridge) c,
      ];
      expect(bridges, hasLength(8));
      expect(bridges.every((c) => c.advanced), isTrue);
      expect(
        bridges.map((c) => c.id),
        containsAll(['bridge:anthropic', 'bridge:meta', 'bridge:codex']),
      );
      expect(
        bridges.every((c) => c.state == ConnectionCardState.disconnected),
        isTrue,
      );
    });

    test('usable auth file + Hermes registration reads connected', () async {
      sidecar.routes['GET /v0/management/auth-files'] = ScriptedRest.json({
        'observed_at': '2026-09-26T00:00:00Z',
        'files': [
          {
            'id': 'meta-1',
            'name': 'meta-1.json',
            'type': 'meta',
            'provider': 'meta',
            'label': 'dev@shop.com',
            'email': 'dev@shop.com',
            'status': 'active',
            'status_message': '',
            'disabled': false,
            'unavailable': false,
          },
        ],
      });
      rest.routes['GET /api/providers/custom-endpoints'] = ScriptedRest.json({
        'endpoints': [
          {
            'id': 'meta-bridge',
            'name': 'Meta (bridge)',
            'base_url': 'http://127.0.0.1:8317/v1',
            'model': 'spark-1.3',
            'is_current': true,
          },
        ],
        'current': {'provider': 'meta-bridge', 'model': 'spark-1.3'},
      });
      final state = await bridgeCards();
      final meta = state.cards.where((c) => c.id == 'bridge:meta').single;
      expect(meta.state, ConnectionCardState.connected);
      expect(meta.detail, contains('dev@shop.com'));
      // Hermes names it by the key it saved it under, never by the card id
      // (`/model … --provider`, `/api/model/set`); it runs the main model.
      expect(meta.hermesProvider, 'meta-bridge');
      expect(meta.isDefault, isTrue);
      expect(state.cards.where((c) => c.isDefault).map((c) => c.id), [
        'bridge:meta',
      ]);
      // Credentials without registration: disconnected with a nudge.
      rest.routes['GET /api/providers/custom-endpoints'] = ScriptedRest.json({
        'endpoints': [],
      });
      bridgeContainer.invalidate(connectionCardsProvider('desk'));
      final again = await bridgeCards();
      final metaAgain = again.cards.where((c) => c.id == 'bridge:meta').single;
      expect(metaAgain.state, ConnectionCardState.disconnected);
      expect(metaAgain.detail, contains('register in Hermes'));
    });

    test('startBridgeLogin polls to ok and registers the endpoint', () async {
      Map<String, Object?> authFiles() => {
        'observed_at': '2026-09-26T00:00:00Z',
        'files': authStatusCalls >= 2
            ? [
                {
                  'id': 'meta-1',
                  'name': 'meta-1.json',
                  'provider': 'meta',
                  'label': '',
                  'status': 'active',
                  'status_message': '',
                  'disabled': false,
                  'unavailable': false,
                },
              ]
            : [],
      };
      sidecar.routes['GET /v0/management/auth-files'] = (_) async =>
          http.Response.bytes(
            utf8.encode(jsonEncode(authFiles())),
            200,
            headers: {'content-type': 'application/json'},
          );
      sidecar.routes['GET /v0/management/meta-auth-url'] = ScriptedRest.json({
        'status': 'ok',
        'url': 'https://meta.ai/device',
        'state': 'meta-1',
        'flow': 'device',
        'user_code': 'ABCD-1234',
        'expires_in': 600,
      });
      sidecar.routes['GET /v0/management/get-auth-status'] = (_) async {
        authStatusCalls++;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({'status': authStatusCalls >= 2 ? 'ok' : 'wait'}),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      // Sidecar catalogue: mixed owners, like the real `OpenAIModels`
      // `{object: list, data: [{id, object, owned_by}]}` shape.
      sidecar.routes['GET /v1/models'] = ScriptedRest.json({
        'object': 'list',
        'data': [
          {'id': 'claude-opus-4-6', 'object': 'model', 'owned_by': 'anthropic'},
          {'id': 'spark-1.3', 'object': 'model', 'owned_by': 'meta'},
          {
            'id': 'spark-1.3-contributor',
            'object': 'model',
            'owned_by': 'meta',
          },
          {'id': 'spark-1.2', 'object': 'model', 'owned_by': 'meta'},
        ],
      });
      final registered = <Map<String, Object?>>[];
      rest.routes['POST /api/providers/custom-endpoints'] = (request) async {
        registered.add(jsonDecode(request.body) as Map<String, Object?>);
        return http.Response.bytes(
          utf8.encode(jsonEncode({'ok': true, 'id': 'meta-bridge'})),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      await bridgeCards();
      final notifier = bridgeContainer.read(
        connectionCardsProvider('desk').notifier,
      );
      final result = await notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: Duration.zero,
      );
      expect(result.outcome, BridgePollOutcome.ok);
      expect(authStatusCalls, greaterThanOrEqualTo(2));
      expect(
        bridgeContainer
            .read(connectionCardsProvider('desk'))
            .value
            ?.pendingBridgeLogin,
        isNull,
      );
      final body = registered.single;
      expect(body['name'], 'Meta (bridge)');
      expect(body['base_url'], 'http://127.0.0.1:8317/v1');
      // Only the large+small pair is registered (≤2, never the catalogue).
      expect(body['model'], 'spark-1.3');
      expect(body['models'], ['spark-1.3', 'spark-1.3-contributor']);
      expect(body['api_key'], 'sidecar-api-key');
      expect(body['api_mode'], 'chat_completions');
    });

    test('empty discovery refuses to register a guessed model', () async {
      sidecar.routes['GET /v0/management/auth-files'] = ScriptedRest.json({
        'observed_at': '2026-09-26T00:00:00Z',
        'files': [
          {
            'id': 'meta-1',
            'name': 'meta-1.json',
            'provider': 'meta',
            'label': '',
            'status': 'active',
            'status_message': '',
            'disabled': false,
            'unavailable': false,
          },
        ],
      });
      // Signed-in credential exists (re-registration path) but the catalogue
      // carries no meta-owned models.
      sidecar.routes['GET /v1/models'] = ScriptedRest.json({
        'object': 'list',
        'data': [
          {'id': 'claude-opus-4-6', 'object': 'model', 'owned_by': 'anthropic'},
        ],
      });
      await bridgeCards();
      final notifier = bridgeContainer.read(
        connectionCardsProvider('desk').notifier,
      );
      final result = await notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: Duration.zero,
      );
      expect(result.outcome, BridgePollOutcome.error);
      expect(result.message, contains('no models'));
      expect(
        rest.calls.any(
          (c) =>
              c.method == 'POST' && c.path == '/api/providers/custom-endpoints',
        ),
        isFalse,
      );
      final card = bridgeContainer
          .read(connectionCardsProvider('desk'))
          .value!
          .cards
          .where((c) => c.id == 'bridge:meta')
          .single;
      expect(card.state, ConnectionCardState.error);
    });

    test('bridge login error surfaces the sidecar message', () async {
      sidecar.routes['GET /v0/management/auth-files'] = ScriptedRest.json({
        'observed_at': '2026-09-26T00:00:00Z',
        'files': [],
      });
      sidecar.routes['GET /v0/management/meta-auth-url'] = ScriptedRest.json({
        'status': 'ok',
        'url': 'https://meta.ai/device',
        'state': 'meta-2',
        'flow': 'device',
        'user_code': 'WXYZ-9999',
        'expires_in': 600,
      });
      sidecar.routes['GET /v0/management/get-auth-status'] = ScriptedRest.json({
        'status': 'error',
        'error': 'Timeout waiting for OAuth callback',
      });
      await bridgeCards();
      final notifier = bridgeContainer.read(
        connectionCardsProvider('desk').notifier,
      );
      final result = await notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: Duration.zero,
      );
      expect(result.outcome, BridgePollOutcome.error);
      // CLIProxyAPI's timeout reads as what happened and what to do.
      expect(
        result.message,
        'The sign-in expired before it finished (it waits 5 minutes). '
        'Start it again.',
      );
      // Nothing was registered in Hermes (only the GET list from refresh).
      expect(
        rest.calls.any(
          (c) =>
              c.method == 'POST' && c.path == '/api/providers/custom-endpoints',
        ),
        isFalse,
      );
    });

    test('cancelBridgeLogin stops the poll and deletes the session', () async {
      sidecar.routes['GET /v0/management/auth-files'] = ScriptedRest.json({
        'observed_at': '2026-09-26T00:00:00Z',
        'files': [],
      });
      sidecar.routes['GET /v0/management/meta-auth-url'] = ScriptedRest.json({
        'status': 'ok',
        'url': 'https://meta.ai/device',
        'state': 'meta-3',
        'flow': 'device',
        'user_code': 'QQQQ-1111',
        'expires_in': 600,
      });
      sidecar.routes['GET /v0/management/get-auth-status'] = ScriptedRest.json({
        'status': 'wait',
      });
      var cancelCalls = 0;
      sidecar.routes['DELETE /v0/management/oauth-session'] = (_) async {
        cancelCalls++;
        return http.Response.bytes(
          utf8.encode(jsonEncode({'status': 'ok', 'cancelled': true})),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      await bridgeCards();
      final notifier = bridgeContainer.read(
        connectionCardsProvider('desk').notifier,
      );
      final pending = notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: const Duration(milliseconds: 50),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await notifier.cancelBridgeLogin();
      final result = await pending.timeout(const Duration(seconds: 10));
      expect(result.outcome, BridgePollOutcome.cancelled);
      expect(cancelCalls, 1);
    });

    test('disconnectBridge deletes the Hermes registration', () async {
      rest.routes['GET /api/providers/custom-endpoints'] = ScriptedRest.json({
        'endpoints': [
          {
            'id': 'meta-bridge',
            'name': 'Meta (bridge)',
            'base_url': 'http://127.0.0.1:8317/v1',
            'model': 'spark-1.3',
          },
        ],
      });
      rest.routes['DELETE /api/providers/custom-endpoints/meta-bridge'] =
          ScriptedRest.json({'ok': true});
      await bridgeCards();
      await bridgeContainer
          .read(connectionCardsProvider('desk').notifier)
          .disconnect('bridge:meta');
      expect(
        rest.calls.any(
          (c) =>
              c.method == 'DELETE' &&
              c.path == '/api/providers/custom-endpoints/meta-bridge',
        ),
        isTrue,
      );
    });
  });

  group('subscription bridge on a server', () {
    const name = 'claude-dev@shop.com.json';
    const label = 'Claude Pro/Max (bridge)';
    const bridgeBase = 'http://127.0.0.1:41000';
    const authorize = 'https://claude.ai/oauth/authorize?state=claude-1';
    const redirect = 'http://localhost:54545/callback?code=c-1&state=claude-1';
    final serverAccount = {
      'name': name,
      'provider': 'claude',
      'email': 'dev@shop.com',
      'usable': true,
    };

    late ProviderContainer bridgeContainer;
    late _CountingBridgeHost host;
    late ScriptedRest sidecar;
    late List<Map<String, Object?>> serverAccounts;
    // Sign-ins started on the server bridge: state → "wait" | "ok".
    late Map<String, String> serverLogins;
    late List<String> cancelled;
    late List<Map<String, Object?>> endpoints;
    late List<Map<String, Object?>> registered;
    late bool modelsLag;

    http.Response reply(Object? payload, [int status = 200]) =>
        http.Response.bytes(
          utf8.encode(jsonEncode(payload)),
          status,
          headers: {'content-type': 'application/json'},
        );

    ProviderContainer containerWith({BridgeHost? bridgeHost}) =>
        ProviderContainer(
          overrides: [
            hermuseDatabaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(MemorySecretStore()),
            transportFactoryProvider.overrideWithValue((_) async => fake),
            restClientProvider('vps').overrideWith(
              (ref) => HermesRestClient(
                rest.client,
                baseUrl: Uri.parse('https://vps.example'),
              ),
            ),
            httpClientProvider.overrideWithValue(sidecar.client),
            if (bridgeHost != null)
              bridgeHostProvider.overrideWithValue(bridgeHost),
          ],
        );

    setUp(() async {
      serverAccounts = [];
      serverLogins = {};
      cancelled = [];
      endpoints = [];
      registered = [];
      modelsLag = false;
      // This desktop's sidecar: an instance on a server never uses it.
      sidecar = ScriptedRest({});
      rest.routes
        ..['GET /api/providers/custom-endpoints'] = ScriptedRest.dynamicJson(
          () => {'endpoints': endpoints},
        )
        ..['POST /api/providers/custom-endpoints'] = (request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          registered.add(body);
          endpoints = [
            {
              'id': 'claude-bridge',
              'name': body['name'],
              'base_url': body['base_url'],
            },
          ];
          return reply({'ok': true, 'id': 'claude-bridge'});
        }
        ..['DELETE /api/providers/custom-endpoints/claude-bridge'] = (_) async {
          endpoints = [];
          return reply({'ok': true});
        }
        ..['GET $hermuseBridgeRoute/status'] = ScriptedRest.dynamicJson(
          () => {
            'supported': true,
            'platform': 'linux-amd64',
            'version': 'v7.3.18',
            'installed': true,
            'running': true,
            'base_url': bridgeBase,
            'accounts': serverAccounts,
            'detail': '',
            'sign_in': true,
          },
        )
        ..['POST $hermuseBridgeRoute/ensure'] = ScriptedRest.json({
          'base_url': bridgeBase,
          'api_key': 'server-key',
          'version': 'v7.3.18',
        })
        ..['POST $hermuseBridgeRoute/login'] = (request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body, {'provider': 'anthropic'});
          serverLogins['claude-1'] = 'wait';
          return reply({'status': 'ok', 'url': authorize, 'state': 'claude-1'});
        }
        ..['GET $hermuseBridgeRoute/login/status'] = (request) async {
          final login = serverLogins[request.url.queryParameters['state']];
          return reply(
            login == null
                ? {'status': 'error', 'error': 'unknown or expired state'}
                : {'status': login},
          );
        }
        // CLIProxyAPI on the server reads the code from the pasted address
        // and saves the account there.
        ..['POST $hermuseBridgeRoute/login/callback'] = (request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final state = Uri.parse(body['redirect_url']! as String)
              .queryParameters['state'];
          if (serverLogins[state] != 'wait') {
            return reply({'detail': 'unknown or expired state'}, 400);
          }
          serverLogins[state!] = 'ok';
          serverAccounts.add(serverAccount);
          // CLIProxyAPI lists a new account's models a moment later.
          modelsLag = true;
          return reply({'ok': true});
        }
        ..['POST $hermuseBridgeRoute/login/cancel'] = (request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          cancelled.add(body['state']! as String);
          return reply({
            'cancelled': serverLogins.remove(body['state']) != null,
          });
        }
        ..['GET $hermuseBridgeRoute/models'] = (_) async {
          final lagging = modelsLag;
          modelsLag = false;
          return reply({
            'object': 'list',
            'data': [
              if (!lagging && serverAccounts.isNotEmpty) ...[
                {
                  'id': 'claude-opus-4-6',
                  'object': 'model',
                  'owned_by': 'anthropic',
                },
                {
                  'id': 'claude-sonnet-4-6',
                  'object': 'model',
                  'owned_by': 'anthropic',
                },
              ],
            ],
          });
        };
      // The server bridge's account route (the name is URL-encoded).
      final accountRoute =
          '$hermuseBridgeRoute/accounts/${Uri.encodeComponent(name)}';
      rest.routes['DELETE $accountRoute'] = (_) async {
        serverAccounts.removeWhere((a) => a['name'] == name);
        return reply({'ok': true, 'name': name});
      };
      host = _CountingBridgeHost(
        BridgeConnection(
          baseUrl: Uri.parse('http://127.0.0.1:8317'),
          apiKey: 'sidecar-api-key',
          managementKey: 'sidecar-mgmt-key',
        ),
      );
      bridgeContainer = containerWith(bridgeHost: host);
    });

    tearDown(() async {
      bridgeContainer.dispose();
    });

    Future<ConnectionsState> serverCards() =>
        bridgeContainer.read(connectionCardsProvider('vps').future);

    ConnectionCard card(ConnectionsState state, String id) =>
        state.cards.where((c) => c.id == id).single;

    Future<BridgePollResult> signIn() async {
      await serverCards();
      return bridgeContainer
          .read(connectionCardsProvider('vps').notifier)
          .startBridgeLogin('bridge:anthropic', pollInterval: Duration.zero);
    }

    /// The sign-in's pending login once the UI shows its link.
    Future<BridgeLogin> shownLogin() async {
      for (var i = 0; i < 200; i++) {
        final login = bridgeContainer
            .read(connectionCardsProvider('vps'))
            .value
            ?.pendingBridgeLogin;
        if (login != null) return login;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('the sign-in never showed its link');
    }

    test('cards come from the server accounts and endpoint', () async {
      serverAccounts.add(serverAccount);
      endpoints = [
        {'id': 'claude-bridge', 'name': label, 'base_url': '$bridgeBase/v1'},
      ];
      final state = await serverCards();
      final claude = card(state, 'bridge:anthropic');
      expect(claude.state, ConnectionCardState.connected);
      expect(claude.detail, 'on the server · dev@shop.com');
      expect(claude.onServer, isTrue);
      expect(
        card(state, 'bridge:codex').state,
        ConnectionCardState.disconnected,
      );
      // This desktop's sidecar holds none of the server's accounts.
      expect(sidecar.calls, isEmpty);
      expect(host.starts, 0);

      // An entry pointing at a desktop sidecar cannot work from the server:
      // it reads as not registered, so a tap re-registers it.
      endpoints = [
        {
          'id': 'claude-bridge',
          'name': label,
          'base_url': 'http://127.0.0.1:8317/v1',
        },
      ];
      bridgeContainer.invalidate(connectionCardsProvider('vps'));
      final stale = card(await serverCards(), 'bridge:anthropic');
      expect(stale.state, ConnectionCardState.disconnected);
      expect(stale.detail, contains('register in Hermes'));
    });

    test('an old plugin says what to do before any login', () async {
      rest.routes
        ..['GET $hermuseBridgeRoute/status'] = ScriptedRest.json({
          'detail': 'No such API endpoint: $hermuseBridgeRoute/status',
        }, 404)
        ..['GET $hermusePluginRoute/files'] = ScriptedRest.json({
          'files': ['FEED_PROMPT.md'],
        });
      final claude = card(await serverCards(), 'bridge:anthropic');
      expect(claude.needsPlugin, isTrue);
      expect(claude.state, ConnectionCardState.disconnected);
      expect(claude.detail, serverBridgeUpdatePlugin);

      final result = await signIn();

      expect(result.outcome, BridgePollOutcome.error);
      expect(result.message, serverBridgeUpdatePlugin);
      expect(sidecar.calls, isEmpty);
      expect(host.starts, 0);

      // No Hermuse plugin at all.
      rest.routes['GET $hermusePluginRoute/files'] = ScriptedRest.json({
        'detail': 'Not Found',
      }, 404);
      bridgeContainer.invalidate(connectionCardsProvider('vps'));
      expect(
        card(await serverCards(), 'bridge:anthropic').detail,
        serverBridgeInstallPlugin,
      );
    });

    test('a plugin that cannot sign in on the server asks for its update, '
        'and keeps serving its accounts', () async {
      rest.routes['GET $hermuseBridgeRoute/status'] = ScriptedRest.dynamicJson(
        () => {
          'supported': true,
          'running': true,
          'base_url': bridgeBase,
          'accounts': serverAccounts,
          'detail': '',
        },
      );
      final claude = card(await serverCards(), 'bridge:anthropic');
      expect(claude.needsPlugin, isTrue);
      expect(claude.detail, serverBridgeUpdatePlugin);

      final result = await signIn();

      expect(result.outcome, BridgePollOutcome.error);
      expect(result.message, serverBridgeUpdatePlugin);
      expect(serverLogins, isEmpty);

      // An account signed in earlier still works and still registers.
      serverAccounts.add(serverAccount);
      bridgeContainer.invalidate(connectionCardsProvider('vps'));
      expect(card(await serverCards(), 'bridge:anthropic').needsPlugin, false);
      expect((await signIn()).outcome, BridgePollOutcome.ok);
    });

    test('a browser sign-in on the server ends with the pasted address, '
        'never touching this device', () async {
      final pending = signIn();
      final login = await shownLogin();
      expect(login.url, authorize);
      expect(login.deviceFlow, isFalse);
      final notifier = bridgeContainer.read(
        connectionCardsProvider('vps').notifier,
      );

      // An address of another sign-in is refused with the bridge's reason;
      // the sign-in keeps waiting.
      await expectLater(
        notifier.submitBridgeCallback(
          'http://localhost:54545/callback?code=x&state=other',
        ),
        throwsA(
          isA<BridgeCallbackRejected>().having(
            (e) => e.message,
            'message',
            'This address is not from the sign-in in progress. Copy the '
                'address the browser shows after this sign-in.',
          ),
        ),
      );
      await notifier.submitBridgeCallback('  $redirect\n');
      final result = await pending;

      expect(result.outcome, BridgePollOutcome.ok);
      // Hermes points at the server's bridge, never at this desktop. The
      // catalogue read right after the sign-in was empty, then retried.
      final body = registered.single;
      expect(body['name'], label);
      expect(body['base_url'], '$bridgeBase/v1');
      expect(body['api_key'], 'server-key');
      expect(body['model'], 'claude-opus-4-6');
      expect(body['models'], ['claude-opus-4-6', 'claude-sonnet-4-6']);
      expect(body['api_mode'], 'chat_completions');
      final state = bridgeContainer.read(connectionCardsProvider('vps')).value!;
      expect(state.pendingBridgeLogin, isNull);
      final claude = card(state, 'bridge:anthropic');
      expect(claude.state, ConnectionCardState.connected);
      expect(claude.detail, 'on the server · dev@shop.com');
      expect(sidecar.calls, isEmpty);
      expect(host.starts, 0);
      await expectLater(
        notifier.submitBridgeCallback(redirect),
        throwsA(isA<BridgeCallbackRejected>()),
      );
    });

    test(
      'without any sidecar (web, mobile) the server cards sign in',
      () async {
        bridgeContainer.dispose();
        bridgeContainer = containerWith();

        final pending = signIn();
        await shownLogin();
        await bridgeContainer
            .read(connectionCardsProvider('vps').notifier)
            .submitBridgeCallback(redirect);

        expect((await pending).outcome, BridgePollOutcome.ok);
        expect(registered.single['base_url'], '$bridgeBase/v1');
      },
    );

    test('cancel ends the sign-in on the server', () async {
      final pending = signIn();
      await shownLogin();

      await bridgeContainer
          .read(connectionCardsProvider('vps').notifier)
          .cancelBridgeLogin();

      expect((await pending).outcome, BridgePollOutcome.cancelled);
      expect(cancelled, ['claude-1']);
      expect(serverAccounts, isEmpty);
      expect(registered, isEmpty);
    });

    test('a server account only needs the endpoint', () async {
      serverAccounts.add(serverAccount);

      expect((await signIn()).outcome, BridgePollOutcome.ok);

      expect(registered.single['base_url'], '$bridgeBase/v1');
      expect(serverLogins, isEmpty);
      expect(sidecar.calls, isEmpty);
      expect(host.starts, 0);
    });

    test('disconnect removes the server account and the endpoint', () async {
      serverAccounts.add(serverAccount);
      endpoints = [
        {'id': 'claude-bridge', 'name': label, 'base_url': '$bridgeBase/v1'},
      ];
      await serverCards();

      await bridgeContainer
          .read(connectionCardsProvider('vps').notifier)
          .disconnect('bridge:anthropic');

      expect(serverAccounts, isEmpty);
      expect(endpoints, isEmpty);
      final state = bridgeContainer.read(connectionCardsProvider('vps')).value!;
      expect(
        card(state, 'bridge:anthropic').state,
        ConnectionCardState.disconnected,
      );
    });
  });
}

/// Test [BridgeHost] returning a fixed sidecar connection.
final class _FakeBridgeHost implements BridgeHost {
  const _FakeBridgeHost(this.connection);

  final BridgeConnection connection;

  @override
  Future<BridgeConnection> ensureStarted() async => connection;
}

/// Test [BridgeHost] counting the sidecar starts.
final class _CountingBridgeHost implements BridgeHost {
  _CountingBridgeHost(this.connection);

  final BridgeConnection connection;
  var starts = 0;

  @override
  Future<BridgeConnection> ensureStarted() async {
    starts++;
    return connection;
  }
}
