import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

// Fixtures in the exact shapes the real scripts emit: install.sh
// `emit_manifest` / `emit_stage_json`, install.ps1 `Invoke-Stage` frames.
const posixManifest = '''
{"protocol_version":1,"stages":[{"name":"prerequisites","title":"System prerequisites","category":"runtime","needs_user_input":false},{"name":"repository","title":"Download Hermes Agent","category":"runtime","needs_user_input":false},{"name":"venv","title":"Create Python virtual environment","category":"runtime","needs_user_input":false},{"name":"python-deps","title":"Install Python dependencies","category":"runtime","needs_user_input":false},{"name":"node-deps","title":"Install browser-tool dependencies","category":"runtime","needs_user_input":false},{"name":"path","title":"Install hermes command","category":"runtime","needs_user_input":false},{"name":"config","title":"Prepare config and skills","category":"configuration","needs_user_input":false},{"name":"setup","title":"Configure API keys and settings","category":"configuration","needs_user_input":true},{"name":"gateway","title":"Configure gateway service","category":"configuration","needs_user_input":true},{"name":"complete","title":"Finish install","category":"runtime","needs_user_input":false}]}
''';

const psManifestWithBanner = '''
Hermes Agent Installer
{"protocol_version":1,"stages":[{"name":"uv","title":"Installing uv package manager","category":"prereqs","needs_user_input":false},{"name":"configure","title":"Configuring API keys and models","category":"post-install","needs_user_input":true}]}
''';

void main() {
  group('manifest parsing', () {
    test('parses the real install.sh manifest', () {
      final manifest = parseManifestOutput(posixManifest);
      expect(manifest.protocolVersion, 1);
      expect(manifest.stages.map((s) => s.name), [
        'prerequisites',
        'repository',
        'venv',
        'python-deps',
        'node-deps',
        'path',
        'config',
        'setup',
        'gateway',
        'complete',
      ]);
      expect(
        manifest.stages.where((s) => s.needsUserInput).map((s) => s.name),
        ['setup', 'gateway'],
      );
    });

    test('takes the last JSON line past ps1 banner output', () {
      final manifest = parseManifestOutput(psManifestWithBanner);
      expect(manifest.stages.map((s) => s.name), ['uv', 'configure']);
    });

    test('throws when no JSON payload exists', () {
      expect(
        () => parseManifestOutput('nothing here\n'),
        throwsFormatException,
      );
    });
  });

  group('stage result parsing', () {
    test('parses the ok frame', () {
      final result = parseStageResultOutput(
        'Cloning into ...\n{"ok":true,"stage":"repository","skipped":false}\n',
      );
      expect(result, isNotNull);
      expect(result!.ok, isTrue);
      expect(result.stage, 'repository');
      expect(result.skipped, isFalse);
      expect(result.failed, isFalse);
    });

    test('parses the non-interactive skipped frame', () {
      final result = parseStageResultOutput(
        '{"ok":true,"stage":"setup","skipped":true}\n',
      );
      expect(result!.skipped, isTrue);
      expect(result.failed, isFalse);
    });

    test('parses the failure frame with reason', () {
      final result = parseStageResultOutput(
        'some noise\n{"ok":false,"stage":"python-deps","skipped":false,"reason":"exit code 1"}\n',
      );
      expect(result!.failed, isTrue);
      expect(result.reason, 'exit code 1');
    });

    test('parses the ps1 frame with duration_ms', () {
      final result = parseStageResultOutput(
        '{"stage":"uv","ok":true,"skipped":false,"reason":null,"duration_ms":1234}\n',
      );
      expect(result!.ok, isTrue);
      expect(result.duration, const Duration(milliseconds: 1234));
    });

    test('returns null when no frame was emitted', () {
      expect(parseStageResultOutput('traceback...\n'), isNull);
    });
  });

  group('HermesInstaller', () {
    HermesInstaller fakeInstaller({
      required String manifest,
      Map<String, String> frames = const {},
      Set<String> existingFiles = const {},
      Future<String> Function(Uri)? download,
    }) {
      final calls = <String>[];
      return HermesInstaller(
        hermesHome: '/home/test/.hermes',
        installDir: '/home/test/.hermes/hermes-agent',
        source: const InstallerSource(
          isWindows: false,
          localScript: '/fake/install.sh',
        ),
        isWindows: false,
        isMacOS: false,
        fileExists: (path) async =>
            path == '/fake/install.sh' || existingFiles.contains(path),
        writeFile: (_, _) async {},
        download:
            download ?? (_) async => throw const SocketException('offline'),
        which: (_) async => '/usr/bin/tool',
        runScript: (executable, args, {environment, onLine}) async {
          calls.add(args.join(' '));
          if (args.contains('--manifest')) {
            return ProcessResult(0, 0, manifest, '');
          }
          final name = args[args.indexOf('--stage') + 1];
          final frame =
              frames[name] ?? '{"ok":true,"stage":"$name","skipped":false}';
          return ProcessResult(0, 0, '…\n$frame\n', '');
        },
      );
    }

    test('manifest() reads stages without side effects', () async {
      final installer = fakeInstaller(manifest: posixManifest);
      final manifest = await installer.manifest();
      expect(manifest.stages, hasLength(10));
    });

    test('run() skips setup/gateway and stops on failure', () async {
      final installer = fakeInstaller(
        manifest: posixManifest,
        frames: {
          'python-deps': '{"ok":false,"stage":"python-deps","skipped":false,"reason":"exit code 1"}',
        },
      );
      final events = <InstallProgress>[];
      await expectLater(
        () async {
          await for (final event in installer.run()) {
            events.add(event);
          }
        }(),
        throwsA(
          isA<InstallFailed>().having((e) => e.stage, 'stage', 'python-deps'),
        ),
      );
      final finished = events.whereType<InstallStageFinished>().toList();
      // prerequisites, repository, venv ran; python-deps failed; the rest
      // (incl. the skipped setup/gateway) never started.
      expect(finished.map((f) => f.stage.name), [
        'prerequisites',
        'repository',
        'venv',
        'python-deps',
      ]);
      expect(finished.last.result.failed, isTrue);
    });

    test('run() reports skipped stages as synthetic frames', () async {
      final installer = fakeInstaller(manifest: posixManifest);
      final events = <InstallProgress>[];
      await for (final event in installer.run()) {
        events.add(event);
      }
      final finished = {
        for (final f in events.whereType<InstallStageFinished>())
          f.stage.name: f.result,
      };
      expect(finished['setup']!.skipped, isTrue);
      expect(finished['gateway']!.skipped, isTrue);
      expect(finished['complete']!.ok, isTrue);
      expect(finished, hasLength(10));
    });

    test('runStage() surfaces a missing frame explicitly', () async {
      final installer = HermesInstaller(
        hermesHome: '/home/test/.hermes',
        installDir: '/home/test/.hermes/hermes-agent',
        source: const InstallerSource(
          isWindows: false,
          localScript: '/fake/install.sh',
        ),
        isWindows: false,
        isMacOS: false,
        fileExists: (_) async => true,
        runScript: (_, _, {environment, onLine}) async =>
            ProcessResult(0, 1, 'traceback, no json\n', ''),
      );
      await expectLater(
        installer.runStage('venv'),
        throwsA(
          isA<InstallFailed>().having(
            (e) => e.message,
            'message',
            contains('no JSON result frame'),
          ),
        ),
      );
    });

    test(
      'checkPrerequisites reports missing tools and the macOS fix',
      () async {
        HermesInstaller withTools(Set<String> present, {bool macOS = false}) =>
            HermesInstaller(
              hermesHome: '/h',
              installDir: '/h/hermes-agent',
              isWindows: false,
              isMacOS: macOS,
              which: (name) async =>
                  present.contains(name) ? '/usr/bin/$name' : null,
            );
        expect(
          (await withTools({'git', 'curl', 'tar'}).checkPrerequisites()).ok,
          isTrue,
        );
        final missing = await withTools({'curl'}).checkPrerequisites();
        expect(missing.ok, isFalse);
        expect(missing.missing, ['git', 'tar']);
        expect(missing.fixCommand, isNull);
        final mac = await withTools({
          'curl',
          'tar',
        }, macOS: true).checkPrerequisites();
        expect(mac.fixCommand, 'xcode-select --install');
      },
    );

    test('InstallerSource mirrors the Desktop resolution order', () {
      const source = InstallerSource(isWindows: false);
      expect(source.scriptName, 'install.sh');
      expect(
        source.downloadUri().toString(),
        startsWith(
          'https://raw.githubusercontent.com/NousResearch/hermes-agent/',
        ),
      );
      expect(source.downloadUri().toString(), contains('/scripts/install.sh'));
      expect(
        source.cachePath('/h'),
        '/h/bootstrap-cache/install-$hermesReleaseCommit.sh',
      );
      expect(
        source.installedAgentScript('/h'),
        '/h/hermes-agent/scripts/install.sh',
      );
      expect(const InstallerSource(isWindows: true).scriptName, 'install.ps1');
    });
  });

  group('stripAnsi', () {
    test('strips colours and keeps the last \\r frame', () {
      expect(stripAnsi('\x1B[32mok\x1B[0m'), 'ok');
      expect(stripAnsi('10%\r100%\r'), '');
      expect(stripAnsi('10%\r100%'), '100%');
    });
  });
}
