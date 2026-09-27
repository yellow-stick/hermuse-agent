import 'package:test/test.dart';

import 'package:cliproxy_client/cliproxy_client.dart';

void main() {
  group('CliproxyProvider', () {
    test('routes match the v7.3.18 management server', () {
      expect(CliproxyProvider.anthropic.route, 'anthropic-auth-url');
      expect(CliproxyProvider.codex.route, 'codex-auth-url');
      expect(CliproxyProvider.meta.route, 'meta-auth-url');
      expect(CliproxyProvider.antigravity.route, 'antigravity-auth-url');
      expect(CliproxyProvider.xai.route, 'xai-auth-url');
      expect(CliproxyProvider.kimi.route, 'kimi-auth-url');
      expect(CliproxyProvider.kimiAi.route, 'kimi-ai-auth-url');
      expect(CliproxyProvider.devin.route, 'devin-auth-url');
    });
  });

  group('AuthStart', () {
    test('parses a browser flow', () {
      final start = AuthStart.fromJson({
        'status': 'ok',
        'url': 'https://claude.ai/oauth?...',
        'state': 'abc',
      });
      expect(start.url, contains('claude.ai'));
      expect(start.state, 'abc');
      expect(start.flow, AuthFlow.browser);
      expect(start.userCode, isNull);
    });

    test('parses a device flow (meta shape)', () {
      final start = AuthStart.fromJson({
        'status': 'ok',
        'url': 'https://meta.ai/device',
        'state': 'meta-123',
        'flow': 'device',
        'user_code': 'ABCD-1234',
        'expires_in': 600,
      });
      expect(start.flow, AuthFlow.device);
      expect(start.userCode, 'ABCD-1234');
      expect(start.expiresIn, 600);
    });

    test('rejects a response without url/state', () {
      expect(
        () => AuthStart.fromJson({'status': 'ok'}),
        throwsA(isA<CliproxyProtocolError>()),
      );
    });
  });

  group('AuthStatus', () {
    test('maps wait/ok/error', () {
      expect(AuthStatus.fromJson({'status': 'wait'}).isPending, isTrue);
      expect(AuthStatus.fromJson({'status': 'ok'}).isOk, isTrue);
      final failed = AuthStatus.fromJson({
        'status': 'error',
        'error': 'Timeout waiting for OAuth callback',
      });
      expect(failed.state, AuthState.error);
      expect(failed.error, contains('Timeout'));
    });

    test('rejects unknown statuses', () {
      expect(
        () => AuthStatus.fromJson({'status': 'bogus'}),
        throwsA(isA<CliproxyProtocolError>()),
      );
    });
  });

  group('AuthFile', () {
    test('reads buildAuthFileEntryLocked fields', () {
      final file = AuthFile.fromJson({
        'id': 'claude-1.json',
        'name': 'claude-1.json',
        'type': 'claude',
        'provider': 'claude',
        'label': 'user@example.com',
        'status': 'active',
        'status_message': '',
        'disabled': false,
        'unavailable': false,
        'runtime_only': false,
        'email': 'user@example.com',
      });
      expect(file.provider, 'claude');
      expect(file.email, 'user@example.com');
      expect(file.usable, isTrue);
    });

    test('unusable when disabled or unavailable', () {
      expect(AuthFile.fromJson({'disabled': true}).usable, isFalse);
      expect(AuthFile.fromJson({'unavailable': true}).usable, isFalse);
    });
  });

  group('hermesCustomEndpoint', () {
    test('builds the CustomEndpointUpdate body', () {
      final body = hermesCustomEndpoint(
        cliproxyBaseUrl: Uri.parse('http://127.0.0.1:8317'),
        apiKey: 'k',
        name: 'Meta (bridge)',
        model: 'spark-1.3',
      );
      expect(body, {
        'name': 'Meta (bridge)',
        'base_url': 'http://127.0.0.1:8317/v1',
        'model': 'spark-1.3',
        'api_key': 'k',
        'discover_models': true,
      });
    });

    test('persists the discovered catalogue', () {
      final body = hermesCustomEndpoint(
        cliproxyBaseUrl: Uri.parse('http://127.0.0.1:8317'),
        apiKey: 'k',
        name: 'Meta (bridge)',
        model: 'spark-1.3',
        models: ['spark-1.3', 'spark-1.2'],
      );
      expect(body['models'], ['spark-1.3', 'spark-1.2']);
    });

    test('omits models when undiscovered', () {
      final body = hermesCustomEndpoint(
        cliproxyBaseUrl: Uri.parse('http://127.0.0.1:8317'),
        apiKey: 'k',
        name: 'n',
        model: 'm',
      );
      expect(body.containsKey('models'), isFalse);
    });

    test('pins api_mode only when asked', () {
      final pinned = hermesCustomEndpoint(
        cliproxyBaseUrl: Uri.parse('http://127.0.0.1:8317/'),
        apiKey: 'k',
        name: 'n',
        model: 'm',
        chatCompletionsPath: true,
      );
      expect(pinned['api_mode'], 'chat_completions');
      // A trailing slash on the sidecar origin must not fork a `//v1` twin.
      expect(pinned['base_url'], 'http://127.0.0.1:8317/v1');
    });
  });
}
