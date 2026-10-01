import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'package:cliproxy_client/cliproxy_client.dart';

void main() {
  group('CliproxyManagement request shapes', () {
    test('startLogin hits the provider route with the Bearer key', () async {
      http.Request? seen;
      final client = CliproxyManagement(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'status': 'ok',
              'url': 'https://example.com/device',
              'state': 'meta-1',
              'flow': 'device',
              'user_code': 'CODE',
            }),
            200,
          );
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      final start = await client.startLogin(CliproxyProvider.meta);

      expect(seen?.method, 'GET');
      expect(seen?.url.path, '/v0/management/meta-auth-url');
      expect(seen?.headers['Authorization'], 'Bearer secret');
      expect(start.flow, AuthFlow.device);
      expect(start.userCode, 'CODE');
    });

    test('listModels hits /v1/models with the API key', () async {
      http.Request? seen;
      final client = CliproxyManagement(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'object': 'list',
              'data': [
                {'id': 'spark-1.3', 'object': 'model', 'owned_by': 'meta'},
                {
                  'id': 'claude-opus-4-6',
                  'object': 'model',
                  'owned_by': 'anthropic',
                },
              ],
            }),
            200,
          );
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'mgmt',
      );

      final models = await client.listModels(apiKey: 'api-key');

      expect(seen?.url.path, '/v1/models');
      expect(seen?.headers['Authorization'], 'Bearer api-key');
      expect(models.map((m) => m.id), ['spark-1.3', 'claude-opus-4-6']);
      expect(models.first.ownedBy, 'meta');
    });

    test('pollLogin passes state as a query parameter', () async {
      http.Request? seen;
      final client = CliproxyManagement(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'status': 'wait'}), 200);
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      final status = await client.pollLogin('meta-1');

      expect(seen?.url.path, '/v0/management/get-auth-status');
      expect(seen?.url.queryParameters, {'state': 'meta-1'});
      expect(status.isPending, isTrue);
    });

    test('listAuthFiles decodes files', () async {
      final client = CliproxyManagement(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'observed_at': '2026-09-26T00:00:00Z',
              'files': [
                {
                  'id': 'a.json',
                  'name': 'a.json',
                  'provider': 'claude',
                  'label': 'l',
                  'status': 'active',
                  'status_message': '',
                  'disabled': false,
                  'unavailable': false,
                },
              ],
            }),
            200,
          ),
        ),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      final files = await client.listAuthFiles();
      expect(files, hasLength(1));
      expect(files.single.provider, 'claude');
    });

    test('401 maps to CliproxyAuthFailed', () async {
      final client = CliproxyManagement(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'invalid management key'}),
            401,
          ),
        ),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'wrong',
      );

      await expectLater(
        client.listAuthFiles(),
        throwsA(
          isA<CliproxyAuthFailed>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('500 maps to CliproxyHttpError', () async {
      final client = CliproxyManagement(
        MockClient((_) async => http.Response('boom', 500)),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      await expectLater(
        client.startLogin(CliproxyProvider.codex),
        throwsA(isA<CliproxyHttpError>()),
      );
    });

    test('transport failure maps to CliproxyUnreachable', () async {
      final client = CliproxyManagement(
        MockClient((_) async => throw http.ClientException('refused')),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      await expectLater(client.ping(), completion(isFalse));
      await expectLater(
        client.pollLogin('s'),
        throwsA(isA<CliproxyUnreachable>()),
      );
    });

    test('cancelLogin returns the cancelled flag', () async {
      final client = CliproxyManagement(
        MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/v0/management/oauth-session');
          return http.Response(
            jsonEncode({'status': 'ok', 'cancelled': true}),
            200,
          );
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );

      expect(await client.cancelLogin('s'), isTrue);
    });

    test('auth files round-trip verbatim by name', () async {
      final dir = <String, String>{};
      final seen = <String>[];
      final client = CliproxyManagement(
        MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer secret');
          final name = request.url.queryParameters['name']!;
          seen.add('${request.method} ${request.url.path}');
          final missing = http.Response(
            jsonEncode({'error': 'file not found'}),
            404,
          );
          switch ((request.method, request.url.path)) {
            case ('POST', '/v0/management/auth-files'):
              expect(
                request.headers['content-type'],
                startsWith('application/json'),
              );
              dir[name] = request.body;
            case ('GET', '/v0/management/auth-files/download'):
              final content = dir[name];
              return content == null ? missing : http.Response(content, 200);
            case ('DELETE', '/v0/management/auth-files'):
              if (dir.remove(name) == null) return missing;
          }
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }),
        baseUrl: Uri.parse('http://127.0.0.1:8317'),
        managementKey: 'secret',
      );
      // Exact bytes matter: the file moves to another CLIProxyAPI as is.
      const content = '{"type":"claude","email":"dev@shop.com",\n "x": 1}';

      await client.uploadAuthFile('claude-dev@shop.com.json', content);
      expect(
        await client.downloadAuthFile('claude-dev@shop.com.json'),
        content,
      );
      await client.deleteAuthFile('claude-dev@shop.com.json');

      await expectLater(
        client.downloadAuthFile('claude-dev@shop.com.json'),
        throwsA(
          isA<CliproxyHttpError>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      await expectLater(
        client.deleteAuthFile('claude-dev@shop.com.json'),
        throwsA(isA<CliproxyHttpError>()),
      );
      expect(seen.first, 'POST /v0/management/auth-files');
    });
  });
}
