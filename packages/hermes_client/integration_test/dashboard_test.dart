// Live test against a real Hermes dashboard. Skipped unless configured:
//
//   HERMUSE_TEST_URL=https://host  HERMUSE_TEST_USER=…  HERMUSE_TEST_PASSWORD=…
//   or, for a loopback `hermes serve`: HERMUSE_TEST_URL=http://127.0.0.1:<port>
//   HERMUSE_TEST_TOKEN=<HERMES_DASHBOARD_SESSION_TOKEN>
//
//   dart test integration_test
//
// Sends one real prompt: the configured model is billed for a short turn.
import 'dart:async';
import 'dart:io';

import 'package:hermes_client/hermes_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  final env = Platform.environment;
  final url = env['HERMUSE_TEST_URL'];
  final token = env['HERMUSE_TEST_TOKEN'];
  final user = env['HERMUSE_TEST_USER'];
  final password = env['HERMUSE_TEST_PASSWORD'];
  final configured =
      url != null && (token != null || (user != null && password != null));

  test(
    'connects, lists sessions and streams a prompt turn',
    () async {
      final instance = HermesInstance(
        id: 'integration',
        label: 'Integration',
        kind: InstanceKind.remote,
        baseUrl: normalizeBaseUrl(url!),
        auth: token != null ? AuthMethod.loopbackToken : AuthMethod.password,
      );
      final secrets = MemorySecretStore();
      if (token != null) {
        await secrets.write(instance.id, SecretKeys.sessionToken, token);
      } else {
        await secrets.write(instance.id, SecretKeys.username, user!);
        await secrets.write(instance.id, SecretKeys.password, password!);
      }
      final client = http.Client();
      final transport = await DashboardTransport.connect(
        instance: instance,
        secrets: secrets,
        httpClient: client,
      );
      addTearDown(() async {
        await transport.close();
        client.close();
      });
      expect(transport.currentState, ConnectionState.ready);

      await transport.call(
        HermesMethods.sessionList,
        const SessionListParams(limit: 5),
      );

      final created = await transport.call(
        HermesMethods.sessionCreate,
        const SessionCreateParams(
          title: 'hermuse integration',
          closeOnDisconnect: true,
        ),
      );
      final sid = created.sessionId;
      final seen = <String>{};
      final done = Completer<MessageCompleteEvent>();
      final sub = transport.events.where((e) => e.sessionId == sid).listen((e) {
        seen.add(e.type);
        if (e is MessageCompleteEvent && !done.isCompleted) done.complete(e);
      });
      addTearDown(sub.cancel);
      transport.onServerRequest(
        (request) async => switch (request) {
          ApprovalServerRequest() => const ApprovalResult(
            choice: ApprovalChoice.once,
          ),
          _ => throw UnsupportedError(request.method),
        },
      );

      await transport.call(
        HermesMethods.promptSubmit,
        PromptSubmitParams(
          sessionId: sid,
          text:
              'Use your terminal tool to run `echo hermuse-ok`, then reply '
              'with only its output.',
        ),
      );
      final complete = await done.future.timeout(const Duration(minutes: 3));
      expect(seen, contains('message.delta'));
      expect(seen, contains('tool.start'));
      expect('${complete.payload.text}', contains('hermuse-ok'));
    },
    skip: configured ? false : 'HERMUSE_TEST_URL + credentials not set',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
