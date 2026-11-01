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

/// Native catalogue captured from the real loopback Hermes
/// (`GET /api/model/options`, trimmed to the rows this suite needs).
Map<String, Object?> realOptionsFixture() => {
  'providers': [
    {
      'slug': 'anthropic',
      'name': 'Anthropic',
      'is_current': false,
      'is_user_defined': false,
      'models': [
        'claude-fable-5.1',
        'claude-fable-5',
        'claude-opus-5',
        'claude-sonnet-5',
        'claude-opus-4-8',
        'claude-opus-4-7',
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-opus-4-5-20251101',
        'claude-sonnet-4-5-20250929',
        'claude-opus-4-20250514',
        'claude-sonnet-4-20250514',
        'claude-haiku-4-5-20251001',
        'claude-opus-5-5',
        'claude-fable-5-1',
      ],
      'total_models': 15,
      'source': 'hermes',
      'authenticated': true,
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      // Static Hermes catalogue for the GLM coding plan
      // (`models_catalog_static.py` "zai" row).
      'slug': 'zai',
      'name': 'Z.AI / GLM',
      'is_current': false,
      'is_user_defined': false,
      'models': [
        'glm-5.3',
        'glm-5.3-flash',
        'glm-5.2',
        'glm-5.1',
        'glm-5',
        'glm-5v-turbo',
        'glm-5-turbo',
        'glm-4.7',
        'glm-4.5',
        'glm-4.5-flash',
      ],
      'total_models': 10,
      'source': 'hermes',
      'authenticated': true,
      'auth_type': 'api_key',
      'key_env': 'GLM_API_KEY',
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      // Static Hermes catalogue, "kimi-coding" row.
      'slug': 'kimi-coding',
      'name': 'Kimi / Kimi Coding Plan',
      'is_current': false,
      'is_user_defined': false,
      'models': [
        'kimi-k3',
        'kimi-k2.7-code',
        'kimi-k2.6',
        'kimi-k2.5',
        'kimi-for-coding',
        'kimi-for-coding-highspeed',
        'kimi-k2-thinking',
        'kimi-k2-thinking-turbo',
        'kimi-k2-turbo-preview',
        'kimi-k2-0905-preview',
      ],
      'total_models': 10,
      'source': 'hermes',
      'authenticated': true,
      'auth_type': 'api_key',
      'key_env': 'KIMI_API_KEY',
      'capabilities': <String, Object?>{},
      'featured_models': <Object?>[],
    },
    {
      // Static Hermes catalogue, "minimax" row.
      'slug': 'minimax',
      'name': 'MiniMax',
      'is_current': false,
      'is_user_defined': false,
      'models': [
        'MiniMax-M3',
        'MiniMax-M2.7',
        'MiniMax-M2.5',
        'MiniMax-M2.1',
        'MiniMax-M2',
      ],
      'total_models': 5,
      'source': 'hermes',
      'authenticated': true,
      'auth_type': 'api_key',
      'key_env': 'MINIMAX_API_KEY',
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
  ],
  'model': '',
  'provider': '',
};

/// Sidecar catalogue slice shaped like the real `OpenAIModels`
/// `{object: list, data: [{id, object, owned_by}]}` response, with ids from
/// the embedded `models.json` (`meta` + `codex-pro` sections).
Map<String, Object?> sidecarCatalogueFixture() => {
  'object': 'list',
  'data': [
    {'id': 'gpt-5.5', 'object': 'model', 'owned_by': 'openai'},
    {'id': 'gpt-6-astra', 'object': 'model', 'owned_by': 'openai'},
    {'id': 'gpt-6-sol', 'object': 'model', 'owned_by': 'openai'},
    {'id': 'gpt-6-luna', 'object': 'model', 'owned_by': 'openai'},
    {'id': 'spark-1.3', 'object': 'model', 'owned_by': 'meta'},
    {'id': 'spark-1.3-contributor', 'object': 'model', 'owned_by': 'meta'},
    {'id': 'spark-1.2', 'object': 'model', 'owned_by': 'meta'},
    {'id': 'spark-1.1', 'object': 'model', 'owned_by': 'meta'},
  ],
};

void main() {
  group('tiers', () {
    test('classifies the real families', () {
      // Claude: opus/fable = large, sonnet/haiku = small.
      expect(classifyModel('claude-opus-4-6'), ModelTier.large);
      expect(classifyModel('claude-opus-5-5'), ModelTier.large);
      // GPT: base/astra = large, mini/nano/sol = small (user's pair: astra + sol).
      expect(classifyModel('gpt-6-sol'), ModelTier.small);
      expect(classifyModel('gpt-6-astra'), ModelTier.large);
      expect(classifyModel('gpt-5.4'), ModelTier.large);
      expect(classifyModel('gpt-5.4-mini'), ModelTier.small);
      expect(classifyModel('gpt-5.4-nano'), ModelTier.small);
      // GLM: base = large, flash/turbo = small.
      expect(classifyModel('glm-5.3'), ModelTier.large);
      expect(classifyModel('glm-5.3-flash'), ModelTier.small);
      expect(classifyModel('glm-5-turbo'), ModelTier.small);
      // Kimi: base = large, thinking/turbo/preview/aliases/256k = small.
      expect(classifyModel('kimi-k3'), ModelTier.large);
      expect(classifyModel('kimi-k3-256k'), ModelTier.small);
      expect(classifyModel('kimi-k2.6'), ModelTier.large);
      expect(classifyModel('kimi-k2-thinking'), ModelTier.small);
      expect(classifyModel('kimi-for-coding'), ModelTier.small);
      // MiniMax: M-numbered = large.
      expect(classifyModel('MiniMax-M3'), ModelTier.large);
      expect(classifyModel('MiniMax-M2.5'), ModelTier.large);
      // Meta: base = large, contributor = small.
      expect(classifyModel('spark-1.3'), ModelTier.large);
      expect(classifyModel('spark-1.3-contributor'), ModelTier.small);
      // Grok: base = large, mini/fast = small.
      expect(classifyModel('grok-4.6'), ModelTier.large);
      expect(classifyModel('grok-3-mini'), ModelTier.small);
      expect(classifyModel('grok-4.7-build-fast'), ModelTier.small);
      // Unknown family / harness aliases: no auto pick.
      expect(classifyModel('frobnicator-9000'), ModelTier.unknown);
      expect(classifyModel('codex-auto-review'), ModelTier.unknown);
      expect(classifyModel('auto'), ModelTier.unknown);
    });

    test('ranks recency by version, snapshots by date', () {
      // Newest large Claude = opus 5.5; newest small = sonnet 5.
      final claude = pickLargeAndSmall([
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-opus-5',
        'claude-sonnet-5',
        'claude-opus-5-5',
        'claude-haiku-4-5-20251001',
      ]);
      expect(claude.large, 'claude-opus-5-5');
      expect(claude.small, 'claude-sonnet-5');

      // Dated snapshots: later date wins within the same version.
      final dated = pickLargeAndSmall([
        'claude-opus-4-5-20251101',
        'claude-opus-4-20250514',
      ]);
      expect(dated.large, 'claude-opus-4-5-20251101');

      // GLM 5.3 + GLM 5.3 flash (the user's example).
      final glm = pickLargeAndSmall([
        'glm-5.3',
        'glm-5.3-flash',
        'glm-5.2',
        'glm-4.5-flash',
      ]);
      expect(glm.large, 'glm-5.3');
      expect(glm.small, 'glm-5.3-flash');

      // GPT astra + sol (the user's pair): astra large, sol small.
      final gpt = pickLargeAndSmall(['gpt-6-astra', 'gpt-6-sol']);
      expect(gpt.large, 'gpt-6-astra');
      expect(gpt.small, 'gpt-6-sol');

      // Meta spark 1.3 + contributor (the user's example).
      final meta = pickLargeAndSmall([
        'spark-1.3',
        'spark-1.3-contributor',
        'spark-1.2',
      ]);
      expect(meta.large, 'spark-1.3');
      expect(meta.small, 'spark-1.3-contributor');

      // Kimi k3 has no small sibling in the base list.
      final kimi = pickLargeAndSmall(['kimi-k3', 'kimi-k2.6']);
      expect(kimi.large, 'kimi-k3');
      expect(kimi.small, isNull);

      // Unknown-only lists pick nothing.
      expect(pickLargeAndSmall(['frobnicator-1', 'auto']), (
        large: null,
        small: null,
      ));
    });
  });

  group('modelSelectionProvider', () {
    late HermuseDatabase db;
    late FakeHermesTransport fake;
    late ProviderContainer container;
    late Map<String, http.Response Function(http.Request)> routes;
    late List<({String method, String path, Object? body})> calls;
    late MockClient mock;

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
        'GET /api/providers/oauth': (_) => json({
          'providers': [
            {
              'id': 'anthropic',
              'name': 'Anthropic API Key',
              'flow': 'external',
              'cli_command': 'hermes auth add anthropic',
              'docs_url': '',
              'disconnect_hint': null,
              'disconnect_command': null,
              'disconnectable': true,
              'status': {
                'logged_in': true,
                'source_label': 'ANTHROPIC_API_KEY',
              },
            },
          ],
        }),
        'GET /api/credentials/pool': (_) => json({'providers': []}),
        'GET /api/providers/custom-endpoints': (_) => json({'endpoints': []}),
        'GET /api/env': (_) => json({
          'GLM_API_KEY': {'is_set': true},
          'KIMI_API_KEY': {'is_set': true},
          'MINIMAX_API_KEY': {'is_set': true},
        }),
      };
      calls = [];
      mock = MockClient((request) async {
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
            (ref) => HermesRestClient(
              mock,
              baseUrl: Uri.parse('https://vps.example'),
            ),
          ),
          for (final profile in ['aya', 'noah'])
            restClientProvider('vps', profile: profile).overrideWith(
              (ref) => HermesRestClient(
                mock,
                baseUrl: Uri.parse('https://vps.example'),
                profile: profile,
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
      fake.on('model.options', (_) => realOptionsFixture());
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('defaults to newest large + newest small', () async {
      final anthropic = await container.read(
        modelSelectionProvider('vps', 'anthropic').future,
      );
      expect(anthropic.large, 'claude-opus-5-5');
      expect(anthropic.small, 'claude-sonnet-5');
      expect(anthropic.selected, ['claude-opus-5-5', 'claude-sonnet-5']);

      final glm = await container.read(
        modelSelectionProvider('vps', 'zai').future,
      );
      expect(glm.large, 'glm-5.3');
      expect(glm.small, 'glm-5.3-flash');
    });

    test('override, clear, same-id collapse, persistence', () async {
      final notifier = container.read(
        modelSelectionProvider('vps', 'zai').notifier,
      );
      await container.read(modelSelectionProvider('vps', 'zai').future);

      await notifier.select(ModelTier.small, 'glm-4.5-flash');
      expect(
        container.read(modelSelectionProvider('vps', 'zai')).value?.small,
        'glm-4.5-flash',
      );
      // Persisted in the settings table.
      expect(
        await db.readSetting('model_selection:vps:zai'),
        contains('glm-4.5-flash'),
      );

      // Unknown id rejected.
      await expectLater(
        notifier.select(ModelTier.small, 'glm-9'),
        throwsA(isA<ArgumentError>()),
      );

      // Setting small to the large id clears large (max 2, no dupes).
      await notifier.select(ModelTier.small, 'glm-5.3');
      final state = container.read(modelSelectionProvider('vps', 'zai')).value!;
      expect(state.small, 'glm-5.3');
      expect(state.large, isNull);

      // Clear reverts to the newest discovered on next load.
      await notifier.clear(ModelTier.small);
      container.invalidate(modelSelectionProvider('vps', 'zai'));
      final reloaded = await container.read(
        modelSelectionProvider('vps', 'zai').future,
      );
      expect(reloaded.large, 'glm-5.3');
      expect(reloaded.small, 'glm-5.3-flash');
    });

    test(
      'selections and default writes are independent for two profiles',
      () async {
        final aya = modelSelectionProvider('vps', 'zai', profile: 'aya');
        final noah = modelSelectionProvider('vps', 'zai', profile: 'noah');
        final ayaSub = container.listen(aya, (_, _) {});
        final noahSub = container.listen(noah, (_, _) {});
        addTearDown(ayaSub.close);
        addTearDown(noahSub.close);
        await Future.wait([
          container.read(aya.future),
          container.read(noah.future),
        ]);
        await container.read(aya.notifier).select(ModelTier.large, 'glm-5.1');
        await container.read(noah.notifier).select(ModelTier.large, 'glm-5.2');
        expect(container.read(aya).requireValue.large, 'glm-5.1');
        expect(container.read(noah).requireValue.large, 'glm-5.2');
        expect(
          await db.readSetting('model_selection:vps:profile:aya:zai'),
          contains('glm-5.1'),
        );
        expect(
          await db.readSetting('model_selection:vps:profile:noah:zai'),
          contains('glm-5.2'),
        );
        expect(await db.readSetting('model_selection:vps:zai'), isNull);
        container.invalidate(aya);
        expect((await container.read(aya.future)).large, 'glm-5.1');
        routes['POST /api/model/set'] = (request) {
          expect(request.url.queryParameters['profile'], 'aya');
          return json({'ok': true});
        };
        await container.read(aya.notifier).makeDefault();
        final writes = [
          for (final call in calls)
            if (call.method == 'POST' && call.path == '/api/model/set')
              call.body as Map<String, Object?>,
        ];
        expect(writes, hasLength(2));
        expect(writes.map((body) => body['profile']), everyElement('aya'));
        expect(writes.first['model'], 'glm-5.1');
        expect(container.read(noah).requireValue.large, 'glm-5.2');
      },
    );

    test('makeDefault assigns main + every auxiliary slot', () async {
      routes['POST /api/model/set'] = (_) => json({'ok': true});
      await container.read(modelSelectionProvider('vps', 'zai').future);
      await container
          .read(modelSelectionProvider('vps', 'zai').notifier)
          .makeDefault();
      final sets = [
        for (final c in calls)
          if (c.method == 'POST' && c.path == '/api/model/set') c.body,
      ];
      expect(sets, [
        {'scope': 'main', 'provider': 'zai', 'model': 'glm-5.3'},
        {'scope': 'auxiliary', 'provider': 'zai', 'model': 'glm-5.3-flash'},
      ]);
    });

    test('availableModels unions ≤2 per connected provider', () async {
      final models = await container.read(
        availableModelsProvider('vps').future,
      );
      // anthropic (2) + zai (2) + kimi-coding (2: k3 + newest small) +
      // minimax (1: M3, no small tier in the catalogue).
      expect(models.map((m) => m.modelId), [
        'claude-opus-5-5',
        'claude-sonnet-5',
        'glm-5.3',
        'glm-5.3-flash',
        'kimi-k3',
        // Newest small Kimi: the dated preview (`0905`) outranks `thinking`
        // (unversioned) and `turbo-preview` (same stamp, shorter version).
        'kimi-k2-0905-preview',
        'MiniMax-M3',
      ]);
    });

    test('a bridge on a server serves discovery and makeDefault', () async {
      const label = 'Claude Pro/Max (bridge)';
      const endpoint = 'http://127.0.0.1:41000/v1';
      Map<String, Object?> model(String id, String owner) => {
        'id': id,
        'object': 'model',
        'owned_by': owner,
      };
      routes['GET /api/providers/custom-endpoints'] = (_) => json({
        'endpoints': [
          {'id': 'claude-bridge', 'name': label, 'base_url': endpoint},
        ],
      });
      routes['GET $hermuseBridgeRoute/status'] = (_) => json({
        'supported': true,
        'running': true,
        'base_url': 'http://127.0.0.1:41000',
        'accounts': [
          {
            'name': 'claude-dev@shop.com.json',
            'provider': 'claude',
            'email': 'dev@shop.com',
            'usable': true,
          },
        ],
      });
      routes['POST $hermuseBridgeRoute/ensure'] = (_) =>
          json({'base_url': 'http://127.0.0.1:41000', 'api_key': 'server-key'});
      routes['GET $hermuseBridgeRoute/models'] = (_) => json({
        'object': 'list',
        'data': [
          model('claude-opus-4-6', 'anthropic'),
          model('claude-sonnet-4-6', 'anthropic'),
          model('gpt-5.5', 'openai'),
        ],
      });
      // Hermes keys the entry `providers.claude-bridge`: the slots name it so.
      routes['POST /api/providers/custom-endpoints'] = (_) =>
          json({'ok': true, 'id': 'claude-bridge'});
      routes['POST /api/model/set'] = (_) => json({'ok': true});
      final desktop = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(MemorySecretStore()),
          transportFactoryProvider.overrideWithValue((_) async => fake),
          restClientProvider('vps').overrideWith(
            (ref) => HermesRestClient(
              mock,
              baseUrl: Uri.parse('https://vps.example'),
            ),
          ),
          // This desktop's sidecar: an instance on a server never uses it.
          bridgeHostProvider.overrideWithValue(const _UnusedBridgeHost()),
        ],
      );
      addTearDown(desktop.dispose);
      final claude = modelSelectionProvider('vps', 'bridge:anthropic');

      final selection = await desktop.read(claude.future);
      await desktop.read(claude.notifier).makeDefault();

      expect(selection.allModels, ['claude-opus-4-6', 'claude-sonnet-4-6']);
      expect(
        [
          for (final c in calls)
            if (c.method == 'POST' &&
                (c.path == '/api/providers/custom-endpoints' ||
                    c.path == '/api/model/set'))
              c.body,
        ],
        [
          {
            'name': label,
            'base_url': endpoint,
            'model': 'claude-opus-4-6',
            'api_key': 'server-key',
            'models': ['claude-opus-4-6', 'claude-sonnet-4-6'],
            'api_mode': 'chat_completions',
            'discover_models': true,
          },
          {
            'scope': 'main',
            'provider': 'claude-bridge',
            'model': 'claude-opus-4-6',
            'base_url': endpoint,
            'api_key': 'server-key',
          },
          {
            'scope': 'auxiliary',
            'provider': 'claude-bridge',
            'model': 'claude-sonnet-4-6',
            'base_url': endpoint,
          },
        ],
      );
    });

    group('custom endpoint', () {
      const card = 'custom:spideros-llm';
      setUp(() {
        routes['GET /api/providers/custom-endpoints'] = (_) => json({
          'endpoints': [
            {
              'id': 'spideros-llm',
              'name': 'SpiderOS LLM',
              'base_url': 'https://llm.example/v1',
              'model': 'muse-spark-1.3-contributor',
              'api_mode': 'chat_completions',
              'models': [
                'claude-opus-5',
                'claude-haiku-4-5-20251001',
                'glm-5.3',
                'muse-spark-1.3-contributor',
              ],
            },
          ],
        });
        // Hermes lists the endpoint as a user-defined row under its slug.
        fake.on('model.options', (_) {
          final options = realOptionsFixture();
          return {
            ...options,
            'providers': [
              ...options['providers']! as List<Object?>,
              {
                'slug': 'spideros-llm',
                'name': 'SpiderOS LLM',
                'is_current': false,
                'is_user_defined': true,
                'models': [
                  'claude-opus-5',
                  'claude-haiku-4-5-20251001',
                  'glm-5.3',
                  'muse-spark-1.3-contributor',
                ],
                'total_models': 4,
                'source': 'user-config',
                'authenticated': true,
                'capabilities': <String, Object?>{},
                'featured_models': <Object?>[],
              },
            ],
          };
        });
      });

      test('defaults large to the configured model', () async {
        final selection = await container.read(
          modelSelectionProvider('vps', card).future,
        );
        expect(selection.allModels, contains('glm-5.3'));
        expect(selection.large, 'muse-spark-1.3-contributor');
        expect(selection.small, isNot('muse-spark-1.3-contributor'));
      });

      test('reaches the chat picker under its Hermes slug', () async {
        final models = await container.read(
          availableModelsProvider('vps').future,
        );
        final custom = [
          for (final m in models)
            if (m.providerName == 'SpiderOS LLM') (m.providerId, m.modelId),
        ];
        expect(custom.first, ('spideros-llm', 'muse-spark-1.3-contributor'));
        expect(custom.map((m) => m.$1).toSet(), {'spideros-llm'});
      });

      test('makeDefault sends the slug and confirms on request', () async {
        routes['POST /api/model/set'] = (request) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          if (body['confirm_expensive_model'] != true) {
            return json({
              'ok': false,
              'confirm_required': true,
              'confirm_message': 'CONTRIBUTOR TIER — TRAINS ON YOUR DATA',
              'scope': body['scope'],
              'provider': body['provider'],
              'model': body['model'],
            });
          }
          return json({'ok': true});
        };
        final selection = await container.read(
          modelSelectionProvider('vps', card).future,
        );
        final notifier = container.read(
          modelSelectionProvider('vps', card).notifier,
        );
        await expectLater(
          notifier.makeDefault(),
          throwsA(
            isA<ExpensiveModelConfirmation>().having(
              (e) => e.message,
              'message',
              'CONTRIBUTOR TIER — TRAINS ON YOUR DATA',
            ),
          ),
        );
        List<Object?> sets() => [
          for (final c in calls)
            if (c.method == 'POST' && c.path == '/api/model/set') c.body,
        ];
        // Refused main slot: nothing else is assigned.
        expect(sets(), [
          {
            'scope': 'main',
            'provider': 'spideros-llm',
            'model': 'muse-spark-1.3-contributor',
          },
        ]);
        calls.clear();
        await notifier.makeDefault(confirmExpensiveModel: true);
        expect(sets(), [
          {
            'scope': 'main',
            'provider': 'spideros-llm',
            'model': 'muse-spark-1.3-contributor',
            'confirm_expensive_model': true,
          },
          {
            'scope': 'auxiliary',
            'provider': 'spideros-llm',
            'model': selection.small,
            'confirm_expensive_model': true,
          },
        ]);
      });
    });
  });
}

/// This desktop's sidecar, which must not serve an instance on a server.
final class _UnusedBridgeHost implements BridgeHost {
  const _UnusedBridgeHost();

  @override
  Future<BridgeConnection> ensureStarted() =>
      throw StateError('the sidecar served an instance on a server');
}
