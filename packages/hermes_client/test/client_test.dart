import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('HermesRestClient cookie session', () {
    test(
      'keeps login cookies (Expires with commas) and drops Max-Age=0',
      () async {
        final seenCookies = <String?>[];
        final client = MockClient((request) async {
          seenCookies.add(request.headers['cookie']);
          return switch (request.url.path) {
            '/auth/password-login' => http.Response(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie':
                    'hermes_at=AAA; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT; HttpOnly,'
                    'hermes_rt=RRR; Path=/; HttpOnly,stale=; Max-Age=0',
              },
            ),
            '/auth/logout' => http.Response(
              '{}',
              200,
              headers: {'set-cookie': 'hermes_rt=; Max-Age=0; Path=/'},
            ),
            _ => http.Response('{"ticket":"T"}', 200),
          };
        });
        final rest = HermesRestClient(client, baseUrl: Uri.parse('https://h'));
        await rest.passwordLogin(username: 'u', password: 'p');
        await rest.mintWsTicket();
        await rest.postJson('/auth/logout', const {});
        await rest.mintWsTicket();
        expect(seenCookies, [
          null,
          'hermes_at=AAA; hermes_rt=RRR',
          'hermes_at=AAA; hermes_rt=RRR',
          'hermes_at=AAA',
        ]);
      },
    );

    test('401 and 429 surface as HermesAuthFailed with the detail', () async {
      for (final code in [401, 429]) {
        final rest = HermesRestClient(
          MockClient((_) async => http.Response('{"detail":"nope"}', code)),
          baseUrl: Uri.parse('https://h'),
        );
        await expectLater(
          rest.passwordLogin(username: 'u', password: 'p'),
          throwsA(
            isA<HermesAuthFailed>()
                .having((e) => e.statusCode, 'statusCode', code)
                .having((e) => e.message, 'message', 'nope'),
          ),
        );
      }
    });
  });

  test('checkSupportedVersion accepts only the 0.21 line', () {
    checkSupportedVersion('0.21.5');
    checkSupportedVersion('v0.21.0');
    for (final v in ['0.2.1', '0.210.0', '0.22.0', '']) {
      expect(
        () => checkSupportedVersion(v),
        throwsA(isA<UnsupportedServerVersion>()),
      );
    }
  });

  test('normalizeBaseUrl canonicalises what users paste', () {
    expect(
      normalizeBaseUrl(' HTTPS://Host.Example:8443/hermes// ').toString(),
      'https://host.example:8443/hermes',
    );
    expect(normalizeBaseUrl('vps.example').toString(), 'https://vps.example');
  });

  group('HermesRegistry', () {
    HermesInstance make(String id, String label, String url) => HermesInstance(
      id: id,
      label: label,
      kind: InstanceKind.remote,
      baseUrl: normalizeBaseUrl(url),
      auth: AuthMethod.password,
    );

    test('rejects duplicate URL or case-insensitive label', () async {
      final registry = HermesRegistry(
        MemoryInstanceStore(),
        MemorySecretStore(),
      );
      await registry.add(make('a', 'VPS', 'https://vps.example'));
      await expectLater(
        registry.add(make('b', 'Other', 'https://VPS.example/')),
        throwsA(isA<DuplicateInstance>()),
      );
      await expectLater(
        registry.add(make('c', ' vps ', 'https://other.example')),
        throwsA(isA<DuplicateInstance>()),
      );
      expect(registry.instances.map((i) => i.id), ['a']);
    });

    test(
      'first instance becomes primary; removing it wipes its secrets',
      () async {
        final secrets = MemorySecretStore();
        final registry = HermesRegistry(MemoryInstanceStore(), secrets);
        await registry.add(make('a', 'A', 'https://a.example'));
        await registry.add(make('b', 'B', 'https://b.example'));
        await secrets.write('a', SecretKeys.password, 'pw');
        expect(registry.primary?.id, 'a');
        await registry.remove('a');
        expect(registry.primary?.id, 'b');
        expect(await secrets.read('a', SecretKeys.password), isNull);
      },
    );
  });

  group('JSON-RPC framing', () {
    test(
      'server request is answered on its own id with the handler result',
      () async {
        final fake = FakeHermesTransport();
        fake.onServerRequest((request) async {
          final approval = request as ApprovalServerRequest;
          expect(approval.params.command, 'rm -rf build');
          return const ApprovalResult(choice: ApprovalChoice.session);
        });
        fake.emitRequest('srq-1', 'approval', {
          'session_id': 's1',
          'request_id': 'r1',
          'command': 'rm -rf build',
        });
        await pumpEventQueue();
        expect(fake.replies['srq-1'], {
          'jsonrpc': '2.0',
          'id': 'srq-1',
          'result': {'choice': 'session'},
        });
      },
    );

    test('unknown server request method gets -32601', () async {
      final fake = FakeHermesTransport();
      fake.emitRequest('srq-2', 'future.thing', {'session_id': 's'});
      await pumpEventQueue();
      expect((fake.replies['srq-2']!['error'] as Map)['code'], -32601);
    });

    test('JSON-RPC error rejects the call with HermesRpcError', () async {
      final fake = FakeHermesTransport()
        ..on('session.list', (_) => throw const FakeRpcError(4000, 'bad'));
      await expectLater(
        fake.call(HermesMethods.sessionList, const SessionListParams()),
        throwsA(
          isA<HermesRpcError>()
              .having((e) => e.code, 'code', 4000)
              .having((e) => e.method, 'method', 'session.list'),
        ),
      );
    });

    test('undecodable event payload degrades to UnknownHermesEvent', () async {
      final fake = FakeHermesTransport();
      final events = <HermesEvent>[];
      fake.events.listen(events.add);
      fake.emitEvent('message.delta', sessionId: 's', payload: {'text': 42});
      fake.emitEvent(
        'message.delta',
        sessionId: 's',
        seq: 3,
        payload: {'text': 'hi'},
      );
      expect(events.first, isA<UnknownHermesEvent>());
      final delta = events.last as MessageDeltaEvent;
      expect((delta.payload.text, delta.seq), ('hi', 3));
      expect(jsonEncode(delta.payload.toJson()), contains('"text":"hi"'));
    });
  });
}
