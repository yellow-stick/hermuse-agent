import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_host/hermuse_host.dart';

void main() {
  group('LocalHermesHost removal lifecycle', () {
    test(
      'blocks reconnects and bridge starts until removal is released',
      () async {
        final secrets = MemorySecretStore();
        final registry = HermesRegistry(MemoryInstanceStore(), secrets);
        var detections = 0;
        final host = LocalHermesHost.test(
          secrets: secrets,
          detector: HermesDetector(
            isWindows: false,
            environment: const {'HERMES_HOME': '/unused/.hermes'},
            homeDirectory: '/unused',
            fileExists: (_) async => false,
            runVersion: (_, _) async => ProcessResult(0, 1, '', ''),
            which: (_) async {
              detections++;
              return null;
            },
          ),
        );
        addTearDown(host.shutdown);
        await host.prepareForUninstall();
        await expectLater(
          host.boot(registry),
          throwsA(isA<HermesUnreachable>()),
        );
        await expectLater(host.bridgeHost.ensureStarted(), throwsStateError);
        expect(detections, 0);
        host.finishUninstall();
        expect(await host.boot(registry), isNull);
        expect(detections, greaterThan(0));
      },
    );

    test(
      'should never adopt a legacy registration in canonical Linux mode',
      () async {
        final secrets = MemorySecretStore();
        final registry = HermesRegistry(MemoryInstanceStore(), secrets);
        await registry.add(
          HermesInstance(
            id: localInstanceId,
            label: 'This computer',
            kind: InstanceKind.local,
            baseUrl: Uri.parse('http://127.0.0.1:43210'),
            auth: AuthMethod.loopbackToken,
          ),
        );
        final host = LocalHermesHost.test(
          secrets: secrets,
          canonicalService: true,
          detector: HermesDetector(
            isWindows: false,
            environment: const {},
            homeDirectory: '/unused',
            fileExists: (_) async =>
                throw StateError('Must not inspect legacy'),
            runVersion: (_, _) async =>
                throw StateError('Must not execute legacy'),
            which: (_) async => throw StateError('Must not detect legacy'),
          ),
        );
        expect(await host.boot(registry), isNull);
        expect(host.hermesHome, '/home/hermes/.hermes');
        expect(host.supervisor, isNull);
        await host.shutdown();
        expect(registry.byId(localInstanceId)?.kind, InstanceKind.local);
      },
    );
    test('reopens a password-authenticated system service without a loopback token', () async {
      final secrets = MemorySecretStore();
      final registry = HermesRegistry(MemoryInstanceStore(), secrets);
      final instance = HermesInstance(
        id: localInstanceId,
        label: 'This computer',
        kind: InstanceKind.system,
        baseUrl: Uri.parse('http://127.0.0.1:9119'),
        auth: AuthMethod.password,
      );
      await registry.add(instance);
      await secrets.write(localInstanceId, SecretKeys.username, 'admin');
      await secrets.write(
        localInstanceId,
        SecretKeys.password,
        'saved-dashboard-password',
      );
      final host = LocalHermesHost.test(
        secrets: secrets,
        canonicalService: true,
        detector: HermesDetector(
          isWindows: false,
          environment: const {},
          homeDirectory: '/unused',
          fileExists: (_) async => throw StateError('Must not inspect legacy'),
          runVersion: (_, _) async =>
              throw StateError('Must not execute legacy'),
          which: (_) async => throw StateError('Must not detect legacy'),
        ),
      );
      addTearDown(host.shutdown);
      expect(await host.boot(registry), instance);
      expect(host.supervisor, isNull);
      await secrets.delete(localInstanceId);
      await expectLater(host.boot(registry), throwsA(isA<HermesUnreachable>()));
    });
  });
}
