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
