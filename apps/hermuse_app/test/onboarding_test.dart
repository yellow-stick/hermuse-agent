import 'dart:convert';

import 'package:cliproxy_client/cliproxy_client.dart'
    show BridgeConnection, BridgeHost, bridgeCardSpecs;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/onboarding/connections.dart';
import 'package:hermuse_app/onboarding/onboarding.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Widget tests for the onboarding + Connections flows (round a).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('onboarding', () {
    testWidgets('runtimeCheck shows problems, Check again re-probes', (
      tester,
    ) async {
      var checks = 0;
      final harness = _Harness(
        rpc: {
          'setup.status': (_) => {'provider_configured': true},
          'setup.runtime_check': (_) {
            checks++;
            return {
              'ok': false,
              'error': 'No provider configured yet.',
              'provider': 'anthropic',
              'model': 'claude-opus-4-5',
              'source': 'env',
            };
          },
          'free_tier.status': (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': '',
            'label': '',
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpOnboarding(tester, harness);

      expect(find.text('Checking this Hermes'), findsOneWidget);
      expect(find.text('No provider configured yet.'), findsOneWidget);
      expect(
        find.text('provider: anthropic · model: claude-opus-4-5 · source: env'),
        findsOneWidget,
      );
      final before = checks;
      await tester.tap(find.widgetWithText(YsButton, 'Check again'));
      await tester.pumpAndSettle();
      expect(checks, greaterThan(before));
    });

    testWidgets('defaultModel picks provider+model and saves', (tester) async {
      var saved = <String, Object?>{};
      final harness = _Harness(
        rpc: {
          'setup.status': (_) => {'provider_configured': true},
          'setup.runtime_check': (_) => {'ok': true},
          'free_tier.status': (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': '',
            'label': '',
          },
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'anthropic',
                'name': 'Anthropic',
                'models': ['claude-opus-4-5', 'claude-haiku-4-5'],
                'is_current': true,
              },
              {
                'slug': 'zai',
                'name': 'Z.AI',
                'models': ['glm-5'],
              },
            ],
          },
        },
        rest: {
          'POST /api/model/set': (request) async {
            saved = jsonDecode(request.body) as Map<String, Object?>;
            return _json({'ok': true});
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpOnboarding(tester, harness);

      // A configured instance opens at ready; re-open the model step.
      expect(find.text('All set'), findsOneWidget);
      await tester.tap(find.text('Change default model'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a default model'), findsOneWidget);
      await tester.tap(find.widgetWithText(YsButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(saved['provider'], 'anthropic');
      expect(saved['model'], 'claude-opus-4-5');
      expect(saved['scope'], 'main');
    });

    testWidgets('expensive model asks for confirmation first', (tester) async {
      var calls = 0;
      final harness = _Harness(
        rpc: {
          'setup.status': (_) => {'provider_configured': true},
          'setup.runtime_check': (_) => {'ok': true},
          'free_tier.status': (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': '',
            'label': '',
          },
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'anthropic',
                'name': 'Anthropic',
                'models': ['claude-opus-4-5'],
              },
            ],
          },
        },
        rest: {
          'POST /api/model/set': (request) async {
            calls++;
            final body = jsonDecode(request.body) as Map<String, Object?>;
            if (body['confirm_expensive_model'] != true) {
              return _json({
                'confirm_required': true,
                'confirm_message': 'Opus costs more.',
              });
            }
            return _json({'ok': true});
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpOnboarding(tester, harness);

      await tester.tap(find.text('Change default model'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(YsButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Expensive model'), findsOneWidget);
      expect(find.text('Opus costs more.'), findsOneWidget);
      await tester.tap(find.widgetWithText(YsButton, 'Use it anyway'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Expensive model'), findsNothing);
    });

    testWidgets('profile step starts the guided conversation', (tester) async {
      ThreadRef? done;
      final harness = _Harness(
        rpc: {
          'setup.status': (params) => params['profile'] == 'hermes-setup'
              ? {'provider_configured': true, 'ready': true}
              : {'provider_configured': true},
          'setup.runtime_check': (_) => {'ok': true},
          'free_tier.status': (_) => {
            'has_guest': false,
            'enabled': false,
            'available': false,
            'notice_pending': false,
            'model': '',
            'label': '',
          },
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'anthropic',
                'name': 'Anthropic',
                'models': ['claude-opus-4-5'],
              },
            ],
          },
          'onboarding.ensure_setup_profile': (_) => {
            'name': 'hermes-setup',
            'path': '/tmp/hermes-setup',
            'created': false,
          },
          'session.list': (_) => const {'sessions': []},
          'session.create': (_) => {
            'session_id': 'live-setup',
            'stored_session_id': 'stored-setup',
            'message_count': 0,
            'messages': const [],
            'info': const <String, Object?>{},
          },
          'session.title': (_) => const <String, Object?>{},
        },
        rest: {
          'POST /api/model/set': (_) async => _json({'ok': true}),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpOnboarding(tester, harness, onDone: (thread) => done = thread);

      // Ready instance: the tour is re-opened from the ready step.
      await tester.tap(find.text('Take the tour'));
      await tester.pumpAndSettle();
      expect(find.text('Meet your Hermes'), findsOneWidget);
      await tester.tap(find.widgetWithText(YsButton, 'Start the tour'));
      await tester.pumpAndSettle();
      expect(done, isNotNull);
      expect(done!.sessionId, 'stored-setup');
    });
  });

  group('connections', () {
    testWidgets('device-code flow shows code and polls to approval', (
      tester,
    ) async {
      var polls = 0;
      var loggedIn = false;
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'nous',
                'name': 'Nous',
                'models': ['nous/welcome'],
                'auth_type': 'oauth',
              },
            ],
          },
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({
            'providers': [
              {
                'id': 'nous',
                'name': 'Nous',
                'flow': 'device_code',
                'status': {'logged_in': loggedIn},
              },
            ],
          }),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
          'POST /api/providers/oauth/nous/start': (_) async => _json({
            'session_id': 'sess-1',
            'user_code': 'ABCD-1234',
            'verification_url': 'https://example.test/device',
            'expires_in': 900,
            'poll_interval': 1,
          }),
          'GET /api/providers/oauth/nous/poll/sess-1': (_) async {
            polls++;
            if (polls >= 2) {
              loggedIn = true;
              return _json({'status': 'approved'});
            }
            return _json({'status': 'pending'});
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      expect(find.text('Model accounts'), findsOneWidget);
      expect(find.text('Nous'), findsOneWidget);
      // Rows are compact: tapping one expands its flow.
      await tester.tap(find.text('Nous'));
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Connect'));
      await tester.pump();
      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(find.textContaining('example.test/device'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 30));
      expect(find.text('Connected'), findsOneWidget);
    });

    testWidgets('API key save posts validate then model.save_key', (
      tester,
    ) async {
      final calls = <String>[];
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'zai',
                'name': 'Z.AI',
                'models': ['glm-5'],
                'auth_type': 'api_key',
                'key_env': 'ZAI_API_KEY',
              },
            ],
          },
          'model.save_key': (params) {
            calls.add('save_key:${params['slug']}');
            return {
              'provider': {
                'slug': 'zai',
                'name': 'Z.AI',
                'models': ['glm-5'],
              },
            };
          },
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
          'POST /api/providers/validate': (_) async {
            calls.add('validate');
            return _json({'ok': true, 'reachable': true});
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      expect(find.text('Z.AI'), findsOneWidget);
      await tester.tap(find.text('Z.AI'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'sk-test-key');
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Save'));
      await tester.pumpAndSettle();
      expect(calls, ['validate', 'save_key:zai']);
    });

    testWidgets('rejected API key surfaces the server sentence', (
      tester,
    ) async {
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'zai',
                'name': 'Z.AI',
                'models': ['glm-5'],
                'auth_type': 'api_key',
                'key_env': 'ZAI_API_KEY',
              },
            ],
          },
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
          'POST /api/providers/validate': (_) async => _json({
            'ok': false,
            'reachable': true,
            'message': 'Invalid API key (401).',
          }),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      await tester.tap(find.text('Z.AI'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'bad');
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid API key (401).'), findsOneWidget);
    });

    testWidgets('subscription sign-ins lead, other providers fold away', (
      tester,
    ) async {
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {'providers': []},
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({
            'providers': [
              {
                'id': 'openai-codex',
                'name': 'ChatGPT or Codex Subscription',
                'flow': 'device_code',
                'status': {'logged_in': false},
              },
              {
                'id': 'anthropic',
                'name': 'Anthropic OAuth',
                'flow': 'external',
                'status': {'logged_in': false},
              },
              {
                'id': 'nous',
                'name': 'Nous Portal',
                'flow': 'device_code',
                'status': {'logged_in': true},
              },
            ],
          }),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      // An instance on this machine without a bridge host: Codex signs in
      // through Hermes, and Claude, which needs a terminal there, waits with
      // the others.
      expect(find.text('Use your subscription'), findsOneWidget);
      expect(find.text('Sign in with ChatGPT / Codex'), findsOneWidget);
      expect(
        find.text('Use your ChatGPT Plus/Pro subscription'),
        findsOneWidget,
      );
      expect(find.text('Sign in with Claude Code'), findsNothing);
      // A connected provider never folds away, nor does your own endpoint.
      expect(find.text('Nous Portal'), findsOneWidget);
      expect(find.text('Anthropic OAuth'), findsNothing);
      expect(find.text('Add a connection'), findsOneWidget);

      await tester.tap(find.text('Show other providers'));
      await tester.pump();
      expect(find.text('Anthropic OAuth'), findsOneWidget);
      await tester.tap(find.text('Hide other providers'));
      await tester.pump();
      expect(find.text('Anthropic OAuth'), findsNothing);

      // A search shows every match, folded or not, featured rows by what
      // they read.
      await tester.enterText(find.byType(EditableText).first, 'anthropic');
      await tester.pump();
      expect(find.text('Anthropic OAuth'), findsOneWidget);
      expect(find.text('Sign in with ChatGPT / Codex'), findsNothing);
      expect(find.text('Show other providers'), findsNothing);
      await tester.enterText(find.byType(EditableText).first, 'sign in');
      await tester.pump();
      expect(find.text('Sign in with ChatGPT / Codex'), findsOneWidget);
      expect(find.text('Anthropic OAuth'), findsNothing);
    });

    testWidgets('desktop features every subscription bridge', (tester) async {
      final harness = _Harness(
        bridgeHost: const _StoppedBridgeHost(),
        rpc: {
          'model.options': (_) => {'providers': []},
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({
            'providers': [
              {
                'id': 'openai-codex',
                'name': 'ChatGPT or Codex Subscription',
                'flow': 'device_code',
                'status': {'logged_in': false},
              },
              {
                'id': 'claude-code',
                'name': 'Claude Code',
                'flow': 'external',
                'status': {'logged_in': false},
              },
            ],
          }),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      expect(find.text('Sign in with Claude Code'), findsOneWidget);
      expect(find.text('Use your Claude Pro/Max subscription'), findsOneWidget);
      expect(find.text('Sign in with Codex'), findsOneWidget);
      expect(find.text('Sign in with Muse Code'), findsOneWidget);
      expect(find.text('Sign in with Grok'), findsOneWidget);
      expect(find.text('Sign in with ChatGPT / Codex'), findsNothing);
      // The Hermes cards the bridges replace wait under other providers.
      expect(find.text('Claude Code'), findsNothing);

      await tester.tap(find.text('Sign in with Claude Code'));
      await tester.pump();
      expect(find.textContaining('Personal use only'), findsOneWidget);
      await tester.tap(find.text('Sign in with Claude Code'));
      await tester.pump();

      // Eight sign-ins: the toggle and the rest sit below the fold.
      final page = find.byType(Scrollable).first;
      Future<void> reveal(String text) =>
          tester.scrollUntilVisible(find.text(text), 200, scrollable: page);
      await reveal('Show other providers');
      await tester.tap(find.text('Show other providers'));
      await tester.pump();
      await reveal('Claude Code');
      await reveal('ChatGPT or Codex Subscription');
    });

    testWidgets('a server without the bridge plugin leads to its update', (
      tester,
    ) async {
      final harness = _Harness(
        bridgeHost: const _StoppedBridgeHost(),
        baseUrl: 'https://vps.example',
        rpc: {
          'model.options': (_) => {'providers': []},
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
          // Plugin 0.2: no bridge routes, but the plugin answers.
          'GET $hermuseBridgeRoute/status': (_) async =>
              _json({'detail': 'Not Found'}, 404),
          'GET $hermusePluginRoute/files': (_) async => _json({'files': []}),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      var opened = 0;
      await _pumpConnections(tester, harness, onServerSetup: () => opened++);

      expect(find.text('Retry'), findsNothing);
      final bridges = bridgeCardSpecs.length;
      expect(find.text('Update plugin'), findsNWidgets(bridges));
      expect(find.text(serverBridgeUpdatePlugin), findsNWidgets(bridges));

      await tester.tap(find.text('Sign in with Claude Code'));
      await tester.pump();
      await tester.tap(find.text('Update the plugin'));
      expect(opened, 1);
    });

    testWidgets('a server sign-in finishes with the pasted address, '
        'with no sidecar on this device', (tester) async {
      var signedIn = false;
      String? pasted;
      final registered = <Map<String, Object?>>[];
      final harness = _Harness(
        baseUrl: 'https://vps.example',
        rpc: {
          'model.options': (_) => {'providers': []},
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async => _json({
            'endpoints': [
              for (final body in registered)
                {
                  'id': 'claude',
                  'name': body['name'],
                  'base_url': body['base_url'],
                },
            ],
          }),
          'POST /api/providers/custom-endpoints': (request) async {
            registered.add(jsonDecode(request.body) as Map<String, Object?>);
            return _json({'ok': true, 'id': 'claude'});
          },
          'GET /api/env': (_) async => _json({}),
          'GET $hermuseBridgeRoute/status': (_) async => _json({
            'supported': true,
            'running': true,
            'base_url': 'http://127.0.0.1:41000',
            'sign_in': true,
            'accounts': [
              if (signedIn)
                {
                  'name': 'claude-dev@shop.com.json',
                  'provider': 'claude',
                  'email': 'dev@shop.com',
                  'usable': true,
                },
            ],
          }),
          'POST $hermuseBridgeRoute/ensure': (_) async => _json({
            'base_url': 'http://127.0.0.1:41000',
            'api_key': 'server-key',
          }),
          'POST $hermuseBridgeRoute/login': (_) async => _json({
            'status': 'ok',
            'url': 'https://claude.ai/oauth/authorize?state=s-1',
            'state': 's-1',
          }),
          'GET $hermuseBridgeRoute/login/status': (_) async =>
              _json({'status': signedIn ? 'ok' : 'wait'}),
          'POST $hermuseBridgeRoute/login/callback': (request) async {
            pasted =
                (jsonDecode(request.body) as Map)['redirect_url'] as String;
            signedIn = true;
            return _json({'ok': true});
          },
          'GET $hermuseBridgeRoute/models': (_) async => _json({
            'data': [
              if (signedIn) {'id': 'claude-opus-4-6', 'owned_by': 'anthropic'},
            ],
          }),
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      await tester.tap(find.text('Sign in with Claude Code'));
      await tester.pump();
      await tester.tap(find.widgetWithText(YsButton, 'Connect'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('https://claude.ai/oauth/authorize?state=s-1'),
        findsOneWidget,
      );
      // The search field leads the page; the address field is the last.
      await tester.enterText(
        find.byType(EditableText).last,
        'http://localhost:54545/callback?code=c-1&state=s-1',
      );
      await tester.pump();
      await tester.tap(find.text('Finish'));
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(pasted, 'http://localhost:54545/callback?code=c-1&state=s-1');
      expect(registered.single['base_url'], 'http://127.0.0.1:41000/v1');
      expect(find.text('Finish'), findsNothing);
    });

    testWidgets('custom endpoint checks, then adds the picked model', (
      tester,
    ) async {
      final calls = <String>[];
      Map<String, Object?>? saved;
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {'providers': []},
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async =>
              _json({'endpoints': []}),
          'GET /api/env': (_) async => _json({}),
          'POST /api/providers/custom-endpoints/validate': (_) async {
            calls.add('validate');
            return _json({
              'ok': true,
              'resolved_base_url': 'http://localhost:1234/v1',
              'models': ['local-model'],
            });
          },
          'POST /api/providers/custom-endpoints': (request) async {
            calls.add('save');
            saved = jsonDecode(request.body) as Map<String, Object?>;
            return _json({'id': 'local'});
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      // The endpoint form sits above the provider list, never folded.
      expect(find.text('Your own endpoint'), findsOneWidget);
      await tester.tap(find.widgetWithText(YsButton, 'Add a connection'));
      await tester.pump();
      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(1), 'Local model');
      await tester.enterText(fields.at(2), 'http://localhost:1234');
      await tester.pump();
      final check = find.widgetWithText(YsButton, 'Check');
      await tester.ensureVisible(check);
      await tester.pump();
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(find.text('Found 1 model. Pick the default one.'), findsOneWidget);

      final add = find.widgetWithText(YsButton, 'Add');
      await tester.ensureVisible(add);
      await tester.pump();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(calls, ['validate', 'save']);
      expect(saved, {
        'name': 'Local model',
        'base_url': 'http://localhost:1234/v1',
        'model': 'local-model',
        'api_mode': 'chat_completions',
        'models': ['local-model'],
      });
    });

    testWidgets('a guarded default model asks before Hermes switches', (
      tester,
    ) async {
      final sets = <Map<String, Object?>>[];
      final harness = _Harness(
        rpc: {
          'model.options': (_) => {
            'providers': [
              {
                'slug': 'my-llm',
                'name': 'My LLM',
                'is_user_defined': true,
                'models': ['spark-1.3-contributor'],
                'authenticated': true,
              },
            ],
          },
        },
        rest: {
          'GET /api/providers/oauth': (_) async => _json({'providers': []}),
          'GET /api/credentials/pool': (_) async => _json({'providers': []}),
          'GET /api/providers/custom-endpoints': (_) async => _json({
            'endpoints': [
              {
                'id': 'my-llm',
                'name': 'My LLM',
                'base_url': 'https://llm.example/v1',
                'model': 'spark-1.3-contributor',
                'api_mode': 'anthropic_messages',
                'models': ['spark-1.3-contributor'],
              },
            ],
          }),
          'GET /api/env': (_) async => _json({}),
          'POST /api/model/set': (request) async {
            final body = jsonDecode(request.body) as Map<String, Object?>;
            sets.add(body);
            return _json(
              body['confirm_expensive_model'] == true
                  ? {'ok': true}
                  : {
                      'ok': false,
                      'confirm_required': true,
                      'confirm_message': 'Trains on your data.',
                    },
            );
          },
        },
      );
      await harness.open();
      addTearDown(harness.dispose);
      await _pumpConnections(tester, harness);

      expect(
        find.text('Anthropic-compatible · spark-1.3-contributor · 1 model'),
        findsOneWidget,
      );
      await tester.tap(find.text('My LLM'));
      await tester.pumpAndSettle();
      final use = find.widgetWithText(YsButton, 'Use as default');
      await tester.ensureVisible(use);
      await tester.pump();
      await tester.tap(use);
      await tester.pumpAndSettle();
      expect(find.text('Trains on your data.'), findsOneWidget);
      expect(sets.single['provider'], 'my-llm');

      await tester.tap(find.widgetWithText(YsButton, 'Use it anyway'));
      await tester.pumpAndSettle();
      expect(find.text('Trains on your data.'), findsNothing);
      expect(sets.last, {
        'scope': 'main',
        'provider': 'my-llm',
        'model': 'spark-1.3-contributor',
        'confirm_expensive_model': true,
      });
    });
  });
}

http.Response _json(Object? payload, [int status = 200]) =>
    http.Response(jsonEncode(payload), status);

/// Scripted harness: memory DB + fake transport + MockClient REST.
final class _Harness {
  _Harness({
    required this.rpc,
    this.rest = const {},
    this.bridgeHost,
    this.baseUrl = 'http://127.0.0.1:9119',
  });

  final Map<String, Object? Function(Map<String, Object?>)> rpc;
  final Map<String, Future<http.Response> Function(http.Request)> rest;

  /// The desktop subscription-bridge host; null like on the web.
  final BridgeHost? bridgeHost;

  /// Where the instance's Hermes listens.
  final String baseUrl;

  late final db = openMemoryDatabase();
  late final fake = FakeHermesTransport();
  late final HermesInstance instance = HermesInstance(
    id: 'vps',
    label: 'VPS',
    kind: InstanceKind.remote,
    baseUrl: Uri.parse(baseUrl),
    auth: AuthMethod.password,
  );

  Future<void> open() async {
    await db.saveInstances([instance], primaryId: 'vps');
    for (final entry in rpc.entries) {
      fake.on(entry.key, entry.value);
    }
  }

  Future<void> dispose() async {
    await fake.close();
    await db.close();
  }

  ProviderScope _scope({required Widget child}) => ProviderScope(
    overrides: [
      hermuseDatabaseProvider.overrideWithValue(db),
      secretStoreProvider.overrideWithValue(MemorySecretStore()),
      transportFactoryProvider.overrideWithValue((_) async => fake),
      restClientProvider('vps').overrideWith(
        (ref) => HermesRestClient(
          MockClient((request) async {
            final route = rest['${request.method} ${request.url.path}'];
            if (route != null) return route(request);
            return http.Response('no route ${request.url.path}', 500);
          }),
          baseUrl: Uri.parse('https://vps.example'),
        ),
      ),
      bridgeHostProvider.overrideWithValue(bridgeHost),
    ],
    child: child,
  );
}

/// A desktop bridge host whose sidecar is down: the bridge cards still
/// list, signed out.
final class _StoppedBridgeHost implements BridgeHost {
  const _StoppedBridgeHost();

  @override
  Future<BridgeConnection> ensureStarted() =>
      Future.error(StateError('test: sidecar down'));
}

Future<void> _pumpOnboarding(
  WidgetTester tester,
  _Harness harness, {
  ValueChanged<ThreadRef>? onDone,
}) async {
  await tester.pumpWidget(
    harness._scope(
      child: MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: YsTheme(
            palette: YsPalette.dark,
            child: Overlay.wrap(
              child: OnboardingScreen(
                instance: harness.instance,
                onDone: onDone ?? (_) {},
                onSkipToChat: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpConnections(
  WidgetTester tester,
  _Harness harness, {
  VoidCallback? onServerSetup,
}) async {
  await tester.pumpWidget(
    harness._scope(
      child: MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: YsTheme(
            palette: YsPalette.dark,
            child: Overlay.wrap(
              child: ConnectionsScreen(
                instance: harness.instance,
                onBack: () {},
                onServerSetup: onServerSetup,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
