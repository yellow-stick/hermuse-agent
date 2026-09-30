import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

/// Fake `hermes --version` responder: [versions] maps executable → stdout.
HermesDetector fakeDetector({
  required Map<String, String> versions,
  bool isWindows = false,
  Map<String, String> environment = const {},
  String homeDirectory = '/home/test',
  String? onPath,
  Future<InstallJournal?> Function()? readInstallJournal,
}) => HermesDetector(
  isWindows: isWindows,
  environment: environment,
  homeDirectory: homeDirectory,
  fileExists: (path) async => versions.containsKey(path) || path == onPath,
  runVersion: (executable, args) async {
    final stdout = versions[executable];
    if (stdout == null) throw ProcessException(executable, args, 'missing');
    return ProcessResult(0, 0, '$stdout\n', '');
  },
  which: (_) async => onPath,
  readInstallJournal: readInstallJournal,
);

const managedLauncher = '/home/test/.hermes/runtime/.local/bin/hermes';

InstallJournal journal({required bool finished, String? home}) =>
    InstallJournal(
      hermesHome: home ?? '/home/test/.hermes',
      installDir: '${home ?? '/home/test/.hermes'}/hermes-agent',
      runtimeHome: '${home ?? '/home/test/.hermes'}/runtime',
      commit: hermesReleaseCommit,
      startedAt: DateTime.utc(2026, 9, 29),
      completedStages: const ['prerequisites', 'repository', 'venv', 'path'],
      currentStage: finished ? null : 'python-deps',
      finished: finished,
    );

void main() {
  group('HermesDetector', () {
    test('finds ~/.local/bin/hermes on POSIX', () async {
      final detector = fakeDetector(
        versions: {
          '/home/test/.local/bin/hermes':
              'Hermes Agent v0.21.5 (2026.9.24) · upstream 130b8f2c',
        },
      );
      final found = await detector.detect();
      expect(found, isNotNull);
      expect(found!.executable, '/home/test/.local/bin/hermes');
      expect(found.version, contains('v0.21.5'));
      expect(found.home, '/home/test/.hermes');
    });

    test('HERMES_HOME wins over the default home', () async {
      final detector = fakeDetector(
        environment: {'HERMES_HOME': '/data/hermes'},
        versions: {'/home/test/.local/bin/hermes': 'Hermes Agent v0.21.5'},
      );
      final found = await detector.detect();
      expect(found!.home, '/data/hermes');
    });

    test('falls back to PATH when the well-known path is absent', () async {
      final detector = fakeDetector(
        versions: {'/opt/hermes/bin/hermes': 'Hermes Agent v0.21.5'},
        onPath: '/opt/hermes/bin/hermes',
      );
      final found = await detector.detect();
      expect(found!.executable, '/opt/hermes/bin/hermes');
    });

    test('returns null when nothing answers --version', () async {
      final detector = fakeDetector(versions: {});
      expect(await detector.detect(), isNull);
    });

    test('skips candidates whose --version fails', () async {
      final detector = HermesDetector(
        isWindows: false,
        environment: const {},
        homeDirectory: '/home/test',
        fileExists: (_) async => true,
        runVersion: (executable, _) async => ProcessResult(0, 1, '', 'boom'),
        which: (_) async => null,
      );
      expect(await detector.detect(), isNull);
    });

    test('Windows probes the hermes bin dir with .cmd fallback', () async {
      String? probed;
      final detector = HermesDetector(
        isWindows: true,
        environment: {'LOCALAPPDATA': r'C:\Users\t'},
        homeDirectory: r'C:\Users\t',
        fileExists: (path) async {
          probed ??= path;
          return path.endsWith('hermes.cmd');
        },
        runVersion: (executable, _) async =>
            ProcessResult(0, 0, 'Hermes Agent v0.21.5\n', ''),
        which: (_) async => null,
      );
      final found = await detector.detect();
      expect(probed, r'C:\Users\t\hermes\bin\hermes.exe');
      expect(found!.executable, r'C:\Users\t\hermes\bin\hermes.cmd');
      expect(found.home, r'C:\Users\t\hermes');
    });

    group('on Windows', () {
      const home = r'C:\Users\t\AppData\Local\hermes';
      HermesDetector windows({required bool portableGit}) => HermesDetector(
        isWindows: true,
        environment: const {'LOCALAPPDATA': r'C:\Users\t\AppData\Local'},
        homeDirectory: r'C:\Users\t',
        fileExists: (path) async =>
            path == '$home\\bin\\hermes.exe' ||
            (portableGit && path == '$home\\git\\bin\\bash.exe'),
        runVersion: (_, _) async =>
            ProcessResult(0, 0, 'Hermes Agent v0.21.5\n', ''),
        which: (_) async => null,
      );

      test(
        "children reach the tools install.ps1 added after the app's start",
        () async {
          final found = (await windows(portableGit: true).detect())!;
          expect(found.managed, isFalse);
          expect(found.gitBash, '$home\\git\\bin\\bash.exe');
          // A snapshot taken before the install: Path spelled as Windows
          // does, the hermes bin dir already listed once.
          final environment = found.runtimeEnvironment({
            'Path': '$home\\bin;C:\\Windows\\system32;',
            'SystemRoot': r'C:\Windows',
          });
          expect(environment, {
            'Path':
                '$home\\bin;$home\\node;C:\\Windows\\system32;'
                '$home\\git\\cmd',
            'HERMES_GIT_BASH_PATH': '$home\\git\\bin\\bash.exe',
            'PYTHONUTF8': '1',
          });
        },
      );

      test("keeps what the user's environment already sets", () async {
        final found = (await windows(portableGit: true).detect())!;
        final environment = found.runtimeEnvironment({
          'PATH': r'C:\Windows\system32',
          'HERMES_GIT_BASH_PATH': r'C:\Program Files\Git\bin\bash.exe',
          'PYTHONUTF8': '0',
        });
        expect(environment, {
          'PATH':
              '$home\\bin;$home\\node;C:\\Windows\\system32;$home\\git\\cmd',
        });
      });

      test('a system Git leaves Git Bash to Hermes', () async {
        final found = (await windows(portableGit: false).detect())!;
        expect(found.gitBash, isNull);
        expect(found.runtimeEnvironment({'Path': r'C:\Windows\system32'}), {
          'Path': '$home\\bin;$home\\node;C:\\Windows\\system32',
          'PYTHONUTF8': '1',
        });
      });
    });

    test('prefers the runtime Hermuse installed and marks it', () async {
      final detector = fakeDetector(
        versions: {
          managedLauncher: 'Hermes Agent v0.21.5 (2026.9.24)',
          '/home/test/.local/bin/hermes': 'Hermes Agent v0.21.5',
        },
        onPath: '/usr/local/bin/hermes',
      );
      final found = (await detector.detect())!;
      expect(found.executable, managedLauncher);
      expect(found.managed, isTrue);
      expect(
        found.runtimeEnvironment({'PATH': '/usr/bin:/bin'})['PATH'],
        '/home/test/.hermes/runtime/.local/bin:/home/test/.hermes/node/bin:'
        '/home/test/.hermes/bin:/usr/bin:/bin',
      );
    });

    test("leaves the environment of the user's own install alone", () async {
      final detector = fakeDetector(
        versions: {'/home/test/.local/bin/hermes': 'Hermes Agent v0.21.5'},
      );
      final found = (await detector.detect())!;
      expect(found.managed, isFalse);
      expect(found.runtimeEnvironment({'PATH': '/usr/bin'}), isEmpty);
    });

    test(
      'an unfinished install journal wins over a working launcher',
      () async {
        var current = journal(finished: false);
        final detector = fakeDetector(
          versions: {managedLauncher: 'Hermes Agent v0.21.5'},
          readInstallJournal: () async => current,
        );
        expect(await detector.detect(), isNull);

        current = journal(finished: true);
        expect((await detector.detect())!.executable, managedLauncher);
      },
    );

    test('a journal of another home does not hide this one', () async {
      final detector = fakeDetector(
        versions: {managedLauncher: 'Hermes Agent v0.21.5'},
        readInstallJournal: () async =>
            journal(finished: false, home: '/data/other-hermes'),
      );
      expect(await detector.detect(), isNotNull);
    });

    test('an unreadable journal adopts nothing', () async {
      final detector = fakeDetector(
        versions: {managedLauncher: 'Hermes Agent v0.21.5'},
        readInstallJournal: () async =>
            throw const FormatException('truncated'),
      );
      expect(await detector.detect(), isNull);
    });
  });

  group('DetectedHermes compatibility', () {
    DetectedHermes withVersion(String line) =>
        DetectedHermes(executable: '/h/hermes', version: line, home: '/h');

    test('accepts the 0.21 series from 0.21.5', () {
      for (final line in [
        'Hermes Agent v0.21.5 (2026.9.24) · upstream 130b8f2c',
        'Hermes Agent v0.21.9',
        'Hermes Agent v0.21.5.post1',
        'hermes 0.21.6rc1',
      ]) {
        expect(withVersion(line).compatible, isTrue, reason: line);
      }
      expect(withVersion('Hermes Agent v0.21.5 (2026.9.24)').semver, '0.21.5');
    });

    test('rejects older, newer and pre-release boundaries', () {
      for (final line in [
        'Hermes Agent v0.21.4',
        'Hermes Agent v0.21.5rc2',
        'Hermes Agent v0.21.5.dev0',
        'Hermes Agent v0.22.0',
        'Hermes Agent v0.22.0rc1',
        'Hermes Agent v1.21.5',
        'Hermes Agent v0.20.9',
      ]) {
        expect(withVersion(line).compatible, isFalse, reason: line);
      }
    });

    test('a line without a release is incompatible', () {
      final hermes = withVersion('Hermes Agent (development build)');
      expect(hermes.semver, isNull);
      expect(hermes.compatible, isFalse);
    });
  });

  group('parseBackendReadyPort', () {
    test('parses the serve announcement', () {
      expect(parseBackendReadyPort('HERMES_BACKEND_READY port=65238'), 65238);
    });

    test('accepts the legacy dashboard token', () {
      expect(parseBackendReadyPort('HERMES_DASHBOARD_READY port=9119'), 9119);
    });

    test('finds the sentinel spliced onto uvicorn noise', () {
      expect(
        parseBackendReadyPort(
          '...process [4711]HERMES_BACKEND_READY port=65238',
        ),
        65238,
      );
    });

    test('returns null for prose', () {
      expect(parseBackendReadyPort('  Hermes backend listening on'), isNull);
      expect(parseBackendReadyPort(''), isNull);
    });
  });
}
