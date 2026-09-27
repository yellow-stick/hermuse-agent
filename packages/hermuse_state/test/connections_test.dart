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

    test('addCustomEndpoint persists the resolved base url', () async {
      rest.routes['POST /api/providers/custom-endpoints/validate'] =
          ScriptedRest.json({
            'ok': true,
            'reachable': true,
            'message': '',
            'models': ['llama-3.1-8b'],
            'resolved_base_url': 'http://127.0.0.1:8000/v1',
          });
      rest.routes['POST /api/providers/custom-endpoints'] = (request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['base_url'], 'http://127.0.0.1:8000/v1');
        expect(body['model'], 'llama-3.1-8b');
        return http.Response.bytes(
          utf8.encode(jsonEncode({'ok': true, 'id': 'local-llama'})),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      await cards();
      final id = await container
          .read(connectionCardsProvider('vps').notifier)
          .addCustomEndpoint(name: 'Local', baseUrl: 'http://127.0.0.1:8000');
      expect(id, 'local-llama');
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
          restClientProvider('vps').overrideWith(
            (ref) => HermesRestClient(
              rest.client,
              baseUrl: Uri.parse('https://vps.example'),
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
    });

    tearDown(() async {
      bridgeContainer.dispose();
    });

    Future<ConnectionsState> bridgeCards() =>
        bridgeContainer.read(connectionCardsProvider('vps').future);

    test('hidden without a bridge host, shown with one', () async {
      // The default container has no host: no bridge cards.
      expect(
        (await cards()).cards.any((c) => c.flow == ConnectionFlow.bridge),
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
          },
        ],
      });
      final state = await bridgeCards();
      final meta = state.cards.where((c) => c.id == 'bridge:meta').single;
      expect(meta.state, ConnectionCardState.connected);
      expect(meta.detail, contains('dev@shop.com'));
      // Credentials without registration: disconnected with a nudge.
      rest.routes['GET /api/providers/custom-endpoints'] = ScriptedRest.json({
        'endpoints': [],
      });
      bridgeContainer.invalidate(connectionCardsProvider('vps'));
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
        connectionCardsProvider('vps').notifier,
      );
      final result = await notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: Duration.zero,
      );
      expect(result.outcome, BridgePollOutcome.ok);
      expect(authStatusCalls, greaterThanOrEqualTo(2));
      expect(
        bridgeContainer
            .read(connectionCardsProvider('vps'))
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
        connectionCardsProvider('vps').notifier,
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
          .read(connectionCardsProvider('vps'))
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
        connectionCardsProvider('vps').notifier,
      );
      final result = await notifier.startBridgeLogin(
        'bridge:meta',
        pollInterval: Duration.zero,
      );
      expect(result.outcome, BridgePollOutcome.error);
      expect(result.message, contains('Timeout waiting'));
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
        connectionCardsProvider('vps').notifier,
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
          .read(connectionCardsProvider('vps').notifier)
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
}

/// Test [BridgeHost] returning a fixed sidecar connection.
final class _FakeBridgeHost implements BridgeHost {
  const _FakeBridgeHost(this.connection);

  final BridgeConnection connection;

  @override
  Future<BridgeConnection> ensureStarted() async => connection;
}
