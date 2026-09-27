import 'dart:io';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('SupervisorBridgeHost', () {
    test('returns the supervisor connection', () async {
      final home = await Directory.systemTemp.createTemp('bridge_host');
      try {
        final supervisor = CliproxySupervisor(
          secrets: MemorySecretStore(),
          hermesHome: home.path,
          locateBinary: () async => const CliproxyBinary(
            path: '/sidecar/cliproxy',
            entry: CliproxyLockEntry(
              asset: 'asset',
              archiveSha256: 'a',
              binary: 'cliproxy',
              binarySha256: 'b',
            ),
          ),
          supervisorFactory:
              ({required executable, required args, environment}) => Supervisor(
                executable: Platform.resolvedExecutable,
                arguments: const ['--version'],
              ),
          probe: (_, _) async => true,
        );
        final host = SupervisorBridgeHost(
          secrets: MemorySecretStore(),
          hermesHome: home.path,
          supervisor: supervisor,
        );
        final connection = await host.ensureStarted();
        expect(connection.baseUrl.host, '127.0.0.1');
        expect(connection.apiKey, isNotEmpty);
        expect(connection.managementKey, isNotEmpty);
        expect(identical(host.supervisor, supervisor), isTrue);
        await supervisor.dispose();
      } finally {
        await home.delete(recursive: true);
      }
    });
  });

  group('HermusePluginInstaller', () {
    late Directory work;
    late Directory source;
    late Directory home;

    setUp(() async {
      work = await Directory.systemTemp.createTemp('hermuse_plugin');
      source = Directory('${work.path}/src')..createSync();
      home = Directory('${work.path}/home')..createSync();
      File('${source.path}/plugin.yaml')
          .writeAsStringSync('name: hermuse\nversion: 0.1.0\n');
      File('${source.path}/store.py').writeAsStringSync('# store\n');
      Directory('${source.path}/tests').createSync();
      File('${source.path}/tests/test_x.py').writeAsStringSync('# inert\n');
      Directory('${source.path}/dashboard').createSync();
      File('${source.path}/dashboard/plugin_api.py')
          .writeAsStringSync('# api\n');
    });

    tearDown(() async {
      await work.delete(recursive: true);
    });

    Future<ProcessResult> okRun(
      String exe,
      List<String> args, {
      Map<String, String>? environment,
    }) async {
      expect(exe, '/bin/hermes');
      expect(args, ['plugins', 'enable', 'hermuse']);
      expect(environment?['HERMES_HOME'], home.path);
      return ProcessResult(1, 0, 'enabled hermuse', '');
    }

    test('copies the tree minus tests and enables', () async {
      final installer = HermusePluginInstaller(
        pluginSourceDir: source.path,
        runProcess: okRun,
      );
      final result = await installer.install(
        hermesHome: home.path,
        hermesExecutable: '/bin/hermes',
      );
      expect(result.pluginDir, '${home.path}/plugins/hermuse');
      expect(result.overwrote, isFalse);
      expect(result.enableOutput, contains('enabled'));
      expect(File('${result.pluginDir}/store.py').existsSync(), isTrue);
      expect(
        File('${result.pluginDir}/dashboard/plugin_api.py').existsSync(),
        isTrue,
      );
      expect(Directory('${result.pluginDir}/tests').existsSync(), isFalse);
    });

    test('refreshes an identical install, refuses a foreign one', () async {
      final target = Directory('${home.path}/plugins/hermuse')
        ..createSync(recursive: true);
      File('${target.path}/plugin.yaml').writeAsStringSync('name: other\n');
      File('${target.path}/keep.txt').writeAsStringSync('x');
      final installer = HermusePluginInstaller(
        pluginSourceDir: source.path,
        runProcess: okRun,
      );
      await expectLater(
        installer.install(
          hermesHome: home.path,
          hermesExecutable: '/bin/hermes',
        ),
        throwsA(isA<InstallFailed>()),
      );
      expect(File('${target.path}/keep.txt').existsSync(), isTrue);

      File('${target.path}/plugin.yaml')
          .writeAsStringSync('name: hermuse\nversion: 0.0.1\n');
      final result = await installer.install(
        hermesHome: home.path,
        hermesExecutable: '/bin/hermes',
      );
      expect(result.overwrote, isTrue);
      expect(File('${target.path}/keep.txt').existsSync(), isFalse);

      File('${target.path}/plugin.yaml').writeAsStringSync('name: other\n');
      final forced = await installer.install(
        hermesHome: home.path,
        hermesExecutable: '/bin/hermes',
        overwrite: true,
      );
      expect(forced.overwrote, isFalse);
    });

    test('enable failure surfaces the command output', () async {
      final installer = HermusePluginInstaller(
        pluginSourceDir: source.path,
        runProcess: (exe, args, {environment}) async =>
            ProcessResult(1, 1, '', 'nope'),
      );
      await expectLater(
        installer.install(
          hermesHome: home.path,
          hermesExecutable: '/bin/hermes',
        ),
        throwsA(
          isA<InstallFailed>().having(
            (e) => e.message,
            'message',
            contains('plugins enable hermuse'),
          ),
        ),
      );
    });

    test('missing source tree is a prerequisite error', () async {
      final installer = HermusePluginInstaller(
        pluginSourceDir: '${work.path}/nope',
        runProcess: okRun,
      );
      await expectLater(
        installer.install(
          hermesHome: home.path,
          hermesExecutable: '/bin/hermes',
        ),
        throwsA(isA<PrerequisiteMissing>()),
      );
    });
  });
}
