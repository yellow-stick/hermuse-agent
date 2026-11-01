import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:web_socket/testing.dart';
import 'package:web_socket/web_socket.dart';

void main() {
  group('Profile-bound transports', () {
    test('RPC injects the bound profile, preserves overrides and leaves handshake alone', () async {
      final secrets = MemorySecretStore();
      await secrets.write('server', SecretKeys.sessionToken, 'shared-token');
      final calls = <Map<String, Object?>>[];
      final client = MockClient((request) async {
        expect(request.url.queryParameters, isNot(contains('profile')));
        expect(request.headers['x-hermes-session-token'], 'shared-token');
        return http.Response(jsonEncode({'version': '0.21.5'}), 200);
      });
      final transports = <DashboardTransport>[];
      addTearDown(() async {
        for (final transport in transports) {
          await transport.close();
        }
        client.close();
      });
      for (final profile in ['aya', 'noah']) {
        final (socket, server) = fakes();
        server.events.listen((event) {
          if (event is! TextDataReceived) return;
          final frame = jsonDecode(event.text) as Map<String, Object?>;
          calls.add(frame);
          server.sendText(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': frame['id'],
              'result': frame['method'] == 'client.capabilities'
                  ? {'server_requests': <String>[]}
                  : {'sessions': []},
            }),
          );
        });
        final transport = await DashboardTransport.connect(
          instance: HermesInstance(
            id: 'server',
            label: 'Server',
            kind: InstanceKind.remote,
            baseUrl: Uri.parse('https://server.example'),
            auth: AuthMethod.loopbackToken,
            profile: profile,
          ),
          secrets: secrets,
          httpClient: client,
          connector: (uri) async {
            expect(uri.queryParameters, {'token': 'shared-token'});
            scheduleMicrotask(
              () => server.sendText(
                jsonEncode({
                  'jsonrpc': '2.0',
                  'method': 'event',
                  'params': {
                    'type': 'gateway.ready',
                    'payload': {
                      'skin': {},
                      'change_events': false,
                      'replay_epoch': 'test',
                    },
                  },
                }),
              ),
            );
            return socket;
          },
        );
        transports.add(transport);
        await transport.call(
          HermesMethods.sessionList,
          const SessionListParams(),
        );
        await transport.call(
          HermesMethods.sessionList,
          const SessionListParams(profile: 'explicit'),
        );
      }
      expect(
        calls
            .where((c) => c['method'] == 'client.capabilities')
            .map((c) => c['params']),
        everyElement({'server_requests': true}),
      );
      expect(
        calls
            .where((c) => c['method'] == 'session.list')
            .map((c) => (c['params'] as Map)['profile']),
        ['aya', 'explicit', 'noah', 'explicit'],
      );
    });

    test('REST scopes reads, writes and stream URLs without changing authentication', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final rest = HermesRestClient(
        client,
        baseUrl: Uri.parse('https://server.example/prefix'),
        sessionToken: 'shared-token',
        profile: 'aya',
      );
      await rest.getJson('/api/plugins/hermuse/feed');
      await rest.postJson('/api/model/set', {'model': 'one'});
      await rest.postJson('/api/model/set', {
        'model': 'two',
        'profile': 'noah',
      });
      await rest.getJson('/api/config', {'profile': 'noah'});
      await rest.getJson('/api/status');
      await rest.postJson('/api/auth/ws-ticket', {});
      expect(requests[0].url.queryParameters['profile'], 'aya');
      expect(jsonDecode(requests[1].body)['profile'], 'aya');
      expect(jsonDecode(requests[2].body)['profile'], 'noah');
      expect(requests[3].url.queryParameters['profile'], 'noah');
      expect(requests[4].url.queryParameters, isEmpty);
      expect(requests[5].url.queryParameters, isEmpty);
      expect(jsonDecode(requests[5].body), isEmpty);
      expect(
        requests.map((r) => r.headers['x-hermes-session-token']),
        everyElement('shared-token'),
      );
      expect(
        rest.resolve('/api/plugins/hermuse/computer/ws', {
          'ticket': 't',
        }).queryParameters,
        {'profile': 'aya', 'ticket': 't'},
      );
      expect(requests[2].url.queryParameters['profile'], 'noah');
    });

    test('PATCH sends a scoped JSON body', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{"id":"g1","done":true}', 200);
      });
      addTearDown(client.close);
      final rest = HermesRestClient(
        client,
        baseUrl: Uri.parse('https://server.example'),
        profile: 'aya',
      );
      final body = await rest.patchJson('/api/plugins/hermuse/goals/g1', {
        'done': true,
      });
      expect(body, {'id': 'g1', 'done': true});
      expect(requests.single.method, 'PATCH');
      expect(requests.single.url.queryParameters['profile'], 'aya');
      expect(jsonDecode(requests.single.body), {
        'profile': 'aya',
        'done': true,
      });
    });
  });
}
