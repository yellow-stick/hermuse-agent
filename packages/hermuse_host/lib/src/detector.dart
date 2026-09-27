// Private fields with public constructor params need explicit initializers.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

/// An existing Hermes install found on this machine.
final class DetectedHermes {
  const DetectedHermes({
    required this.executable,
    required this.version,
    required this.home,
  });

  /// Absolute path of the `hermes` launcher that answered `--version`.
  final String executable;

  /// The `--version` first line, e.g.
  /// `Hermes Agent v0.21.5 (2026.9.24) · upstream 130b8f2c`.
  final String version;

  /// The `HERMES_HOME` the install uses (env or platform default).
  final String home;
}

/// Finds an existing Hermes install; an existing install is reused, never
/// duplicated.
///
/// Lookup order: explicit [hermesHome]/PATH environment, then
/// `~/.local/bin/hermes` (POSIX), `%LOCALAPPDATA%\hermes\bin\hermes.exe`
/// with the `.cmd` relocatable-venv fallback (Windows, matching the
/// `Install-HermesCommandLaunchers` staging in `install.ps1`), then a `hermes`
/// lookup on PATH. A candidate only counts when `hermes --version` exits 0.
///
/// All platform access goes through injectable callbacks so tests can fake a
/// filesystem; production call sites use [HermesDetector.system].
final class HermesDetector {
  HermesDetector({
    required bool isWindows,
    required Map<String, String> environment,
    required String homeDirectory,
    required Future<bool> Function(String path) fileExists,
    required Future<ProcessResult> Function(
      String executable,
      List<String> args,
    )
    runVersion,
    required Future<String?> Function(String name) which,
  }) : _isWindows = isWindows,
       _environment = environment,
       _homeDirectory = homeDirectory,
       _fileExists = fileExists,
       _runVersion = runVersion,
       _which = which;

  /// Production detector on the current platform.
  factory HermesDetector.system() => HermesDetector(
    isWindows: Platform.isWindows,
    environment: Platform.environment,
    homeDirectory:
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '',
    fileExists: (path) => File(path).exists(),
    runVersion: (executable, args) => Process.run(executable, args),
    which: _whichOnPath,
  );

  final bool _isWindows;
  final Map<String, String> _environment;
  final String _homeDirectory;
  final Future<bool> Function(String path) _fileExists;
  final Future<ProcessResult> Function(String, List<String>) _runVersion;
  final Future<String?> Function(String) _which;

  /// Home directory Hermes uses: `$HERMES_HOME`, else `~/.hermes` (POSIX) or
  /// `%LOCALAPPDATA%\hermes` (Windows, per the `install.ps1` defaults).
  String get hermesHome {
    final fromEnv = _environment['HERMES_HOME'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv;
    if (_isWindows) {
      final localAppData = _environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return '$localAppData\\hermes';
      }
    }
    final sep = _isWindows ? '\\' : '/';
    return '$_homeDirectory$sep.hermes';
  }

  String _join(String a, String b) => _isWindows ? '$a\\$b' : '$a/$b';

  /// Candidate launcher paths before PATH lookup.
  Future<List<String>> _candidates() async {
    final candidates = <String>[];
    if (_isWindows) {
      final bin = _join(hermesHome, 'bin');
      candidates.add(_join(bin, 'hermes.exe'));
      candidates.add(_join(bin, 'hermes.cmd'));
    } else {
      candidates.add(_join(_join(_homeDirectory, '.local'), 'bin/hermes'));
    }
    final onPath = await _which('hermes');
    if (onPath != null && !candidates.contains(onPath)) {
      candidates.add(onPath);
    }
    return candidates;
  }

  /// Returns the first candidate whose `hermes --version` exits 0, else null.
  Future<DetectedHermes?> detect() async {
    for (final candidate in await _candidates()) {
      if (!await _fileExists(candidate)) continue;
      final version = await _readVersion(candidate);
      if (version != null) {
        return DetectedHermes(
          executable: candidate,
          version: version,
          home: hermesHome,
        );
      }
    }
    return null;
  }

  /// Runs `<candidate> --version`; returns the trimmed first stdout line, or
  /// null when the spawn fails, times out, or exits non-zero.
  Future<String?> _readVersion(String candidate) async {
    try {
      final result = await _runVersion(candidate, const [
        '--version',
      ]).timeout(const Duration(seconds: 10));
      if (result.exitCode != 0) return null;
      final firstLine = '${result.stdout}'.split('\n').first.trim();
      return firstLine.isEmpty ? null : firstLine;
    } on TimeoutException {
      return null;
    } on ProcessException {
      return null;
    }
  }

  static Future<String?> _whichOnPath(String name) async {
    final pathEnv =
        Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
    final extensions = Platform.isWindows
        ? (Platform.environment['PATHEXT'] ?? '.EXE;.CMD;.BAT')
              .split(';')
              .where((e) => e.isNotEmpty)
              .toList()
        : const [''];
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      for (final ext in extensions) {
        final candidate = Platform.isWindows
            ? '$dir\\$name$ext'
            : '$dir/$name$ext';
        if (await File(candidate).exists()) return candidate;
      }
    }
    return null;
  }
}
