// Private fields with public constructor params need explicit initializers.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'host_environment.dart';
import 'install_journal.dart';
import 'managed_runtime.dart';

/// Hermes Agent releases this build works with, as a version specifier.
const supportedHermesVersions = '>=0.21.5 <0.22';

/// First `X.Y.Z` release in a `--version` line, plus what follows it
/// (`rc1`, `.post1`, `+local`, …).
final _releasePattern = RegExp(r'(\d+)\.(\d+)\.(\d+)([0-9A-Za-z.+-]*)');

/// A pre-release or development suffix: sorts before the release itself.
final _preReleasePattern = RegExp(
  r'^[-.]?(?:a|alpha|b|beta|c|rc|pre|preview|dev)\d*',
  caseSensitive: false,
);

/// An existing Hermes install found on this machine.
final class DetectedHermes {
  const DetectedHermes({
    required this.executable,
    required this.version,
    required this.home,
    this.managed = false,
  });

  /// Absolute path of the `hermes` launcher that answered `--version`.
  final String executable;

  /// The `--version` first line, e.g.
  /// `Hermes Agent v0.21.5 (2026.9.24) · upstream 130b8f2c`.
  final String version;

  /// The `HERMES_HOME` the install uses (env or platform default).
  final String home;

  /// Whether [executable] is the launcher of the runtime Hermuse installed
  /// ([ManagedRuntime.launcher]) rather than an install the user made.
  final bool managed;

  /// The release [version] names (`0.21.5`, `0.22.0rc1`, …), or null when
  /// the line carries none.
  String? get semver => _releasePattern.firstMatch(version)?.group(0);

  /// Whether [semver] is within [supportedHermesVersions]. A pre-release of
  /// 0.21.5 is below the floor and none of 0.22 is admitted (PEP 440). An
  /// incompatible install is reported to the user and never modified.
  bool get compatible {
    final match = _releasePattern.firstMatch(version);
    if (match == null) return false;
    final major = int.tryParse(match[1]!);
    final minor = int.tryParse(match[2]!);
    final patch = int.tryParse(match[3]!);
    if (major != 0 || minor != 21 || patch == null || patch < 5) return false;
    return patch > 5 || !_preReleasePattern.hasMatch(match[4]!);
  }

  /// Entries a child process of this install needs over [hostEnvironment]:
  /// a managed install reaches its launcher, Node and uv through
  /// [ManagedRuntime.binDirs] ahead of the host `PATH` (the real `HOME` is
  /// kept); an install the user made runs with the host environment as is.
  /// [host] defaults to [hostEnvironment].
  Map<String, String> runtimeEnvironment([Map<String, String>? host]) {
    if (!managed) return const {};
    final hostPath = (host ?? hostEnvironment())['PATH'];
    return {'PATH': ManagedRuntime(home).prefixPath(hostPath)};
  }
}

/// Finds an existing Hermes install; an existing install is reused, never
/// duplicated.
///
/// Lookup order: explicit [hermesHome]/PATH environment, then the runtime
/// Hermuse installed (`<HERMES_HOME>/runtime/.local/bin/hermes`, see
/// [ManagedRuntime]) and `~/.local/bin/hermes` (POSIX),
/// `%LOCALAPPDATA%\hermes\bin\hermes.exe` with the `.cmd` relocatable-venv
/// fallback (Windows, matching the `Install-HermesCommandLaunchers` staging
/// in `install.ps1`), then a `hermes` lookup on PATH. A candidate only
/// counts when `hermes --version` exits 0, and nothing counts while the
/// install journal reports an app-owned install of this home that is not
/// finished: its launcher may already answer, but the install is partial.
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
    Future<InstallJournal?> Function()? readInstallJournal,
  }) : _isWindows = isWindows,
       _environment = environment,
       _homeDirectory = homeDirectory,
       _fileExists = fileExists,
       _runVersion = runVersion,
       _which = which,
       _readInstallJournal = readInstallJournal;

  /// Production detector on the current platform, in the [hostEnvironment].
  /// [installJournalPath] is where the app keeps its [InstallJournal].
  factory HermesDetector.system({String? installJournalPath}) {
    final environment = hostEnvironment();
    return HermesDetector(
      isWindows: Platform.isWindows,
      environment: environment,
      homeDirectory: environment['HOME'] ?? environment['USERPROFILE'] ?? '',
      fileExists: (path) => File(path).exists(),
      runVersion: (executable, args) => Process.run(
        executable,
        args,
        includeParentEnvironment: false,
        environment: environment,
      ),
      which: (name) => _whichOnPath(name, environment),
      readInstallJournal: installJournalPath == null
          ? null
          : () => InstallJournal.read(installJournalPath),
    );
  }

  final bool _isWindows;
  final Map<String, String> _environment;
  final String _homeDirectory;
  final Future<bool> Function(String path) _fileExists;
  final Future<ProcessResult> Function(String, List<String>) _runVersion;
  final Future<String?> Function(String) _which;
  final Future<InstallJournal?> Function()? _readInstallJournal;

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
      candidates.add(ManagedRuntime(hermesHome).launcher);
      candidates.add(_join(_join(_homeDirectory, '.local'), 'bin/hermes'));
    }
    final onPath = await _which('hermes');
    if (onPath != null && !candidates.contains(onPath)) {
      candidates.add(onPath);
    }
    return candidates;
  }

  /// Returns the first candidate whose `hermes --version` exits 0, else
  /// null — also null while an app-owned install of [hermesHome] is
  /// unfinished (the install flow resumes it).
  Future<DetectedHermes?> detect() async {
    if (await _installUnfinished()) return null;
    final managedLauncher = _isWindows
        ? null
        : ManagedRuntime(hermesHome).launcher;
    for (final candidate in await _candidates()) {
      if (!await _fileExists(candidate)) continue;
      final version = await _readVersion(candidate);
      if (version != null) {
        return DetectedHermes(
          executable: candidate,
          version: version,
          home: hermesHome,
          managed: candidate == managedLauncher,
        );
      }
    }
    return null;
  }

  /// Whether the journal records an unfinished install of [hermesHome]. An
  /// unreadable journal counts as unfinished: the state of that install is
  /// unknown, so its launcher must not be adopted (the installer then
  /// reports the journal error).
  Future<bool> _installUnfinished() async {
    final read = _readInstallJournal;
    if (read == null) return false;
    try {
      final journal = await read();
      return journal != null &&
          !journal.finished &&
          journal.hermesHome == hermesHome;
    } on FormatException {
      return true;
    } on FileSystemException {
      return true;
    }
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

  static Future<String?> _whichOnPath(
    String name,
    Map<String, String> environment,
  ) async {
    final pathEnv = environment['PATH'] ?? environment['Path'] ?? '';
    final extensions = Platform.isWindows
        ? (environment['PATHEXT'] ?? '.EXE;.CMD;.BAT')
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
