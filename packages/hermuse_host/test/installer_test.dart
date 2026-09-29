import 'dart:async';
import 'dart:convert';
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
    late Directory root;
    late FakeInstallerScript script;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('installer_test');
      script = FakeInstallerScript(root.path);
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    Future<List<InstallProgress>> drain(HermesInstaller installer) async {
      final events = <InstallProgress>[];
      await for (final event in installer.run()) {
        events.add(event);
      }
      return events;
    }

    test('manifest() reads stages without side effects', () async {
      final manifest = await script.installer().manifest();
      expect(manifest.stages, hasLength(10));
      expect(script.stagesRun, isEmpty);
    });

    test('run() skips setup/gateway and stops on failure', () async {
      script.frames['python-deps'] = '{"ok":false,"stage":"python-deps","skipped":false,"reason":"exit code 1"}';
      final events = <InstallProgress>[];
      await expectLater(
        () async {
          await for (final event in script.installer().run()) {
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
      final events = await drain(script.installer());
      final finished = {
        for (final f in events.whereType<InstallStageFinished>())
          f.stage.name: f.result,
      };
      expect(finished['setup']!.skipped, isTrue);
      expect(finished['gateway']!.skipped, isTrue);
      expect(finished['complete']!.ok, isTrue);
      expect(finished, hasLength(10));
      expect(script.stagesRun, isNot(contains('setup')));
      expect(script.stagesRun, isNot(contains('gateway')));
    });

    for (final macOS in [false, true]) {
      test('${macOS ? 'macOS' : 'Linux'} stages pin the commit, stay in the '
          'private runtime and close the journal', () async {
        await drain(
          script.installer(
            macOS: macOS,
            environment: {
              'PATH': '/usr/local/bin:/usr/bin',
              'HOME': '/home/u',
              'XDG_DATA_HOME': '/home/u/.local/share',
              'XDG_BIN_HOME': '/home/u/bin',
              'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
            },
          ),
        );
        final (args, environment) = script.stageCalls['python-deps']!;
        expect(
          args.sublist(1),
          containsAllInOrder([
            '--stage',
            'python-deps',
            '--commit',
            hermesReleaseCommit,
            '--dir',
            script.installDir,
            '--skip-browser',
            '--skip-computer-use',
            '--non-interactive',
            '--json',
          ]),
        );
        expect(args, isNot(contains('--ensure')));
        expect(environment['HOME'], '${script.hermesHome}/runtime');
        expect(Directory('${script.hermesHome}/runtime').existsSync(), isTrue);
        expect(environment['HERMES_HOME'], script.hermesHome);
        expect(
          environment['PATH'],
          '${script.hermesHome}/runtime/.local/bin:'
          '${script.hermesHome}/node/bin:${script.hermesHome}/bin:'
          '/usr/local/bin:/usr/bin',
        );
        expect(environment.keys, isNot(contains('XDG_DATA_HOME')));
        expect(environment.keys, isNot(contains('XDG_BIN_HOME')));
        expect(
          environment['DBUS_SESSION_BUS_ADDRESS'],
          'unix:path=/run/user/1000/bus',
        );
        expect(
          (await InstallJournal.read(script.journalPath))!.finished,
          isTrue,
        );
      });
    }

    test('logs arrive, ANSI-stripped, while their stage still runs', () async {
      const expected = 'log:→ working on repository';
      final release = Completer<void>();
      script.hold['repository'] = release.future;
      final seen = <String>[];
      final done = Completer<void>();
      final subscription = script.installer().run().listen(
        (event) {
          switch (event) {
            case InstallLog(:final line):
              seen.add('log:$line');
            case InstallStageFinished(:final stage):
              seen.add('finished:${stage.name}');
            case InstallStageStarted():
              break;
          }
        },
        onError: done.completeError,
        onDone: done.complete,
      );
      while (!seen.contains(expected)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(seen, isNot(contains('finished:repository')));
      release.complete();
      await done.future;
      await subscription.cancel();
      expect(
        seen.indexOf(expected),
        lessThan(seen.indexOf('finished:repository')),
      );
    });

    test('the journal exists before the first stage runs', () async {
      InstallJournal? atFirstStage;
      script.onStage = (name) async {
        atFirstStage ??= await InstallJournal.read(script.journalPath);
      };
      await drain(script.installer());
      expect(atFirstStage!.currentStage, 'prerequisites');
      expect(atFirstStage!.completedStages, isEmpty);
      expect(atFirstStage!.commit, hermesReleaseCommit);
      expect(atFirstStage!.runtimeHome, '${script.hermesHome}/runtime');
      expect(script.stageCalls['repository']!.$1, contains('--force-commit'));
      final closed = (await InstallJournal.read(script.journalPath))!;
      expect(closed.finished, isTrue);
    });

    test('resuming skips completed stages and re-runs the interrupted one, '
        'even though the partial install already answers', () async {
      await Directory('${script.installDir}/.git').create(recursive: true);
      await File('${script.installDir}/.git/HEAD')
          .writeAsString('$hermesReleaseCommit\n');
      await InstallJournal(
        hermesHome: script.hermesHome,
        installDir: script.installDir,
        runtimeHome: '${script.hermesHome}/runtime',
        commit: hermesReleaseCommit,
        startedAt: DateTime.utc(2026, 9, 29),
        completedStages: const ['prerequisites', 'repository', 'venv', 'path'],
        currentStage: 'python-deps',
      ).write(script.journalPath);

      final events = await drain(script.installer());

      expect(script.stagesRun, [
        'python-deps',
        'node-deps',
        'config',
        'complete',
      ]);
      final resumed = events
          .whereType<InstallStageFinished>()
          .where((f) => f.previouslyCompleted)
          .map((f) => f.stage.name);
      expect(resumed, ['prerequisites', 'repository', 'venv', 'path']);
      expect((await InstallJournal.read(script.journalPath))!.finished, isTrue);
    });

    test(
      'an unpinned checkout keeps the journal open on the stage to redo',
      () async {
        script.head = 'ffffffffffffffffffffffffffffffffffffffff';
        await expectLater(
          drain(script.installer()),
          throwsA(
            isA<InstallFailed>().having((e) => e.stage, 'stage', 'repository'),
          ),
        );
        final open = (await InstallJournal.read(script.journalPath))!;
        expect(open.finished, isFalse);
        expect(open.currentStage, 'repository');
        expect(open.hasCompleted('repository'), isFalse);
        expect(open.hasCompleted('complete'), isTrue);

        script.head = hermesReleaseCommit;
        script.stagesRun.clear();
        await drain(script.installer());
        expect(script.stagesRun, ['repository']);
        expect(
          (await InstallJournal.read(script.journalPath))!.finished,
          isTrue,
        );
      },
    );

    test(
      'a launcher that does not answer keeps the install unfinished',
      () async {
        script.launcherAnswers = false;
        await expectLater(
          drain(script.installer()),
          throwsA(isA<InstallFailed>().having((e) => e.stage, 'stage', 'path')),
        );
        expect(
          (await InstallJournal.read(script.journalPath))!.finished,
          isFalse,
        );
      },
    );

    test(
      'a fresh install leaves a checkout it does not own untouched',
      () async {
        final foreign = File('${script.installDir}/README.md');
        await foreign.create(recursive: true);
        await foreign.writeAsString('mine');
        await expectLater(
          drain(script.installer()),
          throwsA(isA<InstallBlocked>()),
        );
        expect(script.stagesRun, isEmpty);
        expect(await foreign.readAsString(), 'mine');
        expect(await InstallJournal.read(script.journalPath), isNull);
      },
    );

    test('runStage() surfaces a missing frame explicitly', () async {
      final installer = HermesInstaller(
        hermesHome: script.hermesHome,
        installDir: script.installDir,
        source: const InstallerSource(
          isWindows: false,
          localScript: '/fake/install.sh',
        ),
        environment: const {'PATH': '/usr/bin'},
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

    test('checkPrerequisites reports the tools missing from PATH', () async {
      HermesInstaller withTools(Set<String> present) => HermesInstaller(
        hermesHome: '/h',
        installDir: '/h/hermes-agent',
        isWindows: false,
        isMacOS: false,
        which: (name) async => present.contains(name) ? '/usr/bin/$name' : null,
      );
      expect(
        (await withTools({'git', 'curl', 'tar'}).checkPrerequisites()).ok,
        isTrue,
      );
      final missing = await withTools({'curl'}).checkPrerequisites();
      expect(missing.ok, isFalse);
      expect(missing.missing, ['git', 'tar']);
      expect(missing.fixCommand, isNull);
      expect(missing.installable, isFalse);
    });

    group('on macOS', () {
      const tools = '/Library/Developer/CommandLineTools';

      /// A Mac whose `/usr/bin/git` stub is always on PATH; [developerDir]
      /// is what `xcode-select -p` prints (null: exit 2, none selected) and
      /// [gitInstalled] whether that directory holds git.
      HermesInstaller mac({
        String? developerDir,
        bool gitInstalled = true,
        int installExit = 0,
      }) => HermesInstaller(
        hermesHome: '/h',
        installDir: '/h/hermes-agent',
        isWindows: false,
        isMacOS: true,
        which: (name) async => '/usr/bin/$name',
        fileExists: (path) async =>
            gitInstalled && path == '$developerDir/usr/bin/git',
        runScript: (executable, args, {environment, onLine}) async {
          if (args.contains('--install')) {
            return ProcessResult(0, installExit, '', 'already installed');
          }
          return developerDir == null
              ? ProcessResult(0, 2, '', 'unable to get active developer dir')
              : ProcessResult(0, 0, '$developerDir\n', '');
        },
      );

      test(
        'the git stub does not count without the Command Line Tools',
        () async {
          final check = await mac().checkPrerequisites();
          expect(check.missing, [HermesInstaller.commandLineTools]);
          expect(check.fixCommand, 'xcode-select --install');
          expect(check.installable, isTrue);

          final stale = await mac(
            developerDir: tools,
            gitInstalled: false,
          ).checkPrerequisites();
          expect(stale.missing, [HermesInstaller.commandLineTools]);
        },
      );

      test('the Command Line Tools or Xcode provide git', () async {
        expect(
          (await mac(developerDir: tools).checkPrerequisites()).ok,
          isTrue,
        );
        expect(
          (await mac(
            developerDir: '/Applications/Xcode.app/Contents/Developer',
          ).checkPrerequisites()).ok,
          isTrue,
        );
      });

      test('a refused installer request surfaces its output', () async {
        await expectLater(
          mac(installExit: 1).installPrerequisites(),
          throwsA(
            isA<ProcessFailed>().having(
              (e) => e.outputTail,
              'outputTail',
              'already installed',
            ),
          ),
        );
      });
    });

    test('InstallerSource mirrors the Desktop resolution order', () {
      const source = InstallerSource(isWindows: false);
      expect(source.scriptName, 'install.sh');
      expect(
        source.downloadUri().toString(),
        'https://raw.githubusercontent.com/NousResearch/hermes-agent/'
        '$hermesReleaseCommit/scripts/install.sh',
      );
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

/// Stands in for `install.sh`: answers `--manifest`, runs stages by
/// recording them and producing the side effects validation reads (the
/// checkout's `HEAD`, the bootstrap marker), and answers `--version` for
/// the managed launcher and `xcode-select -p` for a Mac with the Command
/// Line Tools. Paths live in a real temporary directory.
final class FakeInstallerScript {
  FakeInstallerScript(this.root);

  final String root;
  String get hermesHome => '$root/hermes-home';
  String get installDir => '$hermesHome/hermes-agent';
  String get journalPath => '$root/support/hermes-install.json';
  String get launcher => '$hermesHome/runtime/.local/bin/hermes';
  static const _developerDir = '/Library/Developer/CommandLineTools';

  final stagesRun = <String>[];
  final stageCalls = <String, (List<String>, Map<String, String>)>{};

  /// Result frame per stage; stages absent here succeed.
  final frames = <String, String>{};

  /// Stages that print a line and then wait for the future.
  final hold = <String, Future<void>>{};

  Future<void> Function(String stage)? onStage;

  /// Commit the `repository` stage checks out.
  String head = hermesReleaseCommit;
  bool launcherAnswers = true;

  HermesInstaller installer({
    Map<String, String> environment = const {'PATH': '/usr/bin'},
    bool journaled = true,
    bool macOS = false,
  }) => HermesInstaller(
    hermesHome: hermesHome,
    installDir: installDir,
    journalPath: journaled ? journalPath : null,
    source: const InstallerSource(
      isWindows: false,
      localScript: '/fake/install.sh',
    ),
    environment: environment,
    isWindows: false,
    isMacOS: macOS,
    fileExists: (path) async =>
        path == '/fake/install.sh' || path == '$_developerDir/usr/bin/git',
    which: (_) async => '/usr/bin/tool',
    runScript: _run,
  );

  Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  }) async {
    if (executable == '/usr/bin/xcode-select') {
      return ProcessResult(0, 0, '$_developerDir\n', '');
    }
    if (executable == launcher) {
      return launcherAnswers
          ? ProcessResult(0, 0, 'Hermes Agent v0.21.5 (2026.9.24)\n', '')
          : ProcessResult(0, 1, '', 'No such file or directory');
    }
    if (args.contains('--manifest')) {
      return ProcessResult(0, 0, posixManifest, '');
    }
    final name = args[args.indexOf('--stage') + 1];
    stagesRun.add(name);
    stageCalls[name] = (args, environment ?? const {});
    await onStage?.call(name);
    onLine?.call('stdout', '\x1B[36m→\x1B[0m working on $name');
    await hold[name];
    switch (name) {
      case 'repository':
        await Directory('$installDir/.git').create(recursive: true);
        await File('$installDir/.git/HEAD').writeAsString('$head\n');
      case 'complete':
        await File('$installDir/.hermes-bootstrap-complete').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'pinnedCommit': args[args.indexOf('--commit') + 1],
            'pinnedBranch': 'main',
            'completedAt': '2026-09-29T08:00:00.000Z',
          }),
        );
    }
    final frame = frames[name] ?? '{"ok":true,"stage":"$name","skipped":false}';
    return ProcessResult(0, 0, '…\n$frame\n', '');
  }
}
