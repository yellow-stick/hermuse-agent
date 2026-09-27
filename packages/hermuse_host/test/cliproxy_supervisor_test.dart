import 'dart:io';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('CliproxySupervisor', () {
    late Directory home;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('cliproxy_sup_test');
    });

    tearDown(() async {
      await home.delete(recursive: true);
    });

    test('writes config, spawns the binary, probes readiness', () async {
      final secrets = MemorySecretStore();
      String? spawnedExe;
      List<String>? spawnedArgs;
      final child = Supervisor(
        executable: Platform.resolvedExecutable,
        arguments: const ['--version'],
      );
      final supervisor = CliproxySupervisor(
        secrets: secrets,
        hermesHome: home.path,
        locateBinary: () async => _fakeBinary(),
        supervisorFactory: ({required executable, required args, environment}) {
          spawnedExe = executable;
          spawnedArgs = args;
          return child;
        },
        probe: (_, _) async => true,
      );

      final url = await supervisor.ensureStarted();
      expect(url.host, '127.0.0.1');
      expect(url.port, isNonZero);
      expect(spawnedExe, '/sidecar/cliproxy');
      expect(spawnedArgs!.first, '-config');

      final configPath = supervisor.configPath!;
      final config = await File(configPath).readAsString();
      expect(config, contains('host: "127.0.0.1"'));
      expect(config, contains('allow-remote: false'));
      expect(config, contains('port: ${url.port}'));

      // Keys were minted once and persisted in the SecretStore.
      final mgmt = await secrets.read(
        cliproxyInstanceId,
        CliproxySecretKeys.managementKey,
      );
      final api = await secrets.read(
        cliproxyInstanceId,
        CliproxySecretKeys.apiKey,
      );
      expect(mgmt, isNotNull);
      expect(api, isNotNull);
      expect(mgmt, isNot(api));
      expect(supervisor.managementKey, mgmt);
      expect(supervisor.apiKey, api);
      expect(config, contains('secret-key: "$mgmt"'));

      // auth-dir exists with mode 0700 (POSIX).
      if (!Platform.isWindows) {
        final stat = await Directory('${home.path}/cliproxy/auth').stat();
        expect(stat.mode & 0x1ff, 0x1c0);
        final cfgStat = await File(configPath).stat();
        expect(cfgStat.mode & 0x1ff, 0x180);
      }
      await supervisor.dispose();
    });

    test('reuses stored keys on the second start', () async {
      final secrets = MemorySecretStore();
      await secrets.write(
        cliproxyInstanceId,
        CliproxySecretKeys.managementKey,
        'mgmt-1',
      );
      await secrets.write(
        cliproxyInstanceId,
        CliproxySecretKeys.apiKey,
        'api-1',
      );
      final supervisor = CliproxySupervisor(
        secrets: secrets,
        hermesHome: home.path,
        locateBinary: () async => _fakeBinary(),
        supervisorFactory:
            ({required executable, required args, environment}) => Supervisor(
              executable: Platform.resolvedExecutable,
              arguments: const ['--version'],
            ),
        probe: (_, _) async => true,
      );
      await supervisor.ensureStarted();
      expect(supervisor.managementKey, 'mgmt-1');
      expect(supervisor.apiKey, 'api-1');
      await supervisor.dispose();
    });

    test('fails with the output tail when the probe never answers', () async {
      final secrets = MemorySecretStore();
      final supervisor = CliproxySupervisor(
        secrets: secrets,
        hermesHome: home.path,
        locateBinary: () async => _fakeBinary(),
        supervisorFactory:
            ({required executable, required args, environment}) => Supervisor(
              executable: Platform.resolvedExecutable,
              arguments: const ['--version'],
            ),
        probe: (_, _) async => false,
      );
      await expectLater(
        supervisor.ensureStarted(),
        throwsA(isA<ProcessFailed>()),
      );
      await supervisor.dispose();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

CliproxyBinary _fakeBinary() => const CliproxyBinary(
  path: '/sidecar/cliproxy',
  entry: CliproxyLockEntry(
    asset: 'asset',
    archiveSha256: 'a',
    binary: 'cliproxy',
    binarySha256: 'b',
  ),
);
