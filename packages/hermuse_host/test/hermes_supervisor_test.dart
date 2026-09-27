import 'dart:io';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

/// A script printing the READY line then idling, standing in for
/// `hermes serve` (which tests must never spawn).
Future<Supervisor> _readyChild({
  required int port,
  required String token,
  required Directory dir,
}) async {
  final script = File('${dir.path}/ready_$port.dart');
  await script.writeAsString(
    "import 'dart:io';\n"
    'Future<void> main() async {\n'
    "  print('HERMES_BACKEND_READY port=$port');\n"
    '  await stdout.flush();\n'
    '  await Future<void>.delayed(Duration(seconds: 60));\n'
    '}\n',
  );
  final supervisor = Supervisor(
    executable: Platform.resolvedExecutable,
    arguments: [script.path],
    environment: {'HERMES_DASHBOARD_SESSION_TOKEN': token},
    readiness: parseBackendReadyPort,
    startTimeout: const Duration(seconds: 15),
  );
  await supervisor.ensureStarted();
  return supervisor;
}

void main() {
  group('HermesSupervisor', () {
    late Directory dir;
    final owned = <Supervisor>[];

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hermes_sup_test');
    });

    tearDown(() async {
      for (final s in owned) {
        await s.dispose();
      }
      owned.clear();
      await dir.delete(recursive: true);
    });

    test('default factory spawns the Desktop-equivalent command', () {
      // The factory itself spawns on ensureStarted; assert the contract via
      // a captured factory on a twin instance instead of exec'ing hermes.
      Supervisor? captured;
      final supervisor = HermesSupervisor(
        hermes: const DetectedHermes(
          executable: '/h/bin/hermes',
          version: 'Hermes Agent v0.21.5',
          home: '/h',
        ),
        supervisorFactory: () => Supervisor(
          executable: '/h/bin/hermes',
          arguments: const [
            'serve',
            '--host',
            '127.0.0.1',
            '--port',
            '0',
            '--skip-build',
          ],
          environment: const {
            'HERMES_DASHBOARD_SESSION_TOKEN': 't',
            'HERMES_DESKTOP': '1',
            'HERMES_PARENT_PID': '1',
          },
          readiness: parseBackendReadyPort,
        ),
      );
      expect(supervisor.executable, '/h/bin/hermes');
      expect(supervisor.baseUrl, isNull);
      expect(supervisor.sessionToken, isNull);
      expect(captured, isNull);
    });

    test('registerLocal creates then updates the stable local row', () async {
      final secrets = MemorySecretStore();
      final registry = HermesRegistry(MemoryInstanceStore(), secrets);
      await registry.load();

      Future<HermesInstance> register(int port, String token) async {
        final child = await _readyChild(port: port, token: token, dir: dir);
        owned.add(child);
        final supervisor = HermesSupervisor(
          hermes: const DetectedHermes(
            executable: 'hermes',
            version: 'v',
            home: '/h',
          ),
          supervisorFactory: () => child,
        );
        final url = await supervisor.ensureStarted();
        expect(url.port, port);
        final instance = await supervisor.registerLocal(registry, secrets);
        await supervisor.stop();
        return instance;
      }

      final created = await register(50101, 'token-1');
      expect(created.id, localInstanceId);
      expect(created.label, 'This computer');
      expect(created.kind, InstanceKind.local);
      expect(created.auth, AuthMethod.loopbackToken);
      expect(created.baseUrl, Uri.parse('http://127.0.0.1:50101'));
      expect(
        await secrets.read(localInstanceId, SecretKeys.sessionToken),
        'token-1',
      );
      expect(registry.instances, hasLength(1));

      // A restart on a new port updates the same row (no twin).
      final updated = await register(50102, 'token-2');
      expect(updated.id, localInstanceId);
      expect(updated.baseUrl, Uri.parse('http://127.0.0.1:50102'));
      expect(updated.label, 'This computer');
      expect(registry.instances, hasLength(1));
      expect(
        await secrets.read(localInstanceId, SecretKeys.sessionToken),
        'token-2',
      );
    });

    test('registerLocal refuses before start', () async {
      final supervisor = HermesSupervisor(
        hermes: const DetectedHermes(
          executable: 'hermes',
          version: 'v',
          home: '/h',
        ),
      );
      final secrets = MemorySecretStore();
      final registry = HermesRegistry(MemoryInstanceStore(), secrets);
      await registry.load();
      await expectLater(
        supervisor.registerLocal(registry, secrets),
        throwsStateError,
      );
    });
  });
}
