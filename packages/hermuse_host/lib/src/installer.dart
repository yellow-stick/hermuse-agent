import 'dart:convert';
import 'dart:io';

import 'errors.dart';

/// Matches the backend port announcement on a stdout line.
///
/// `hermes serve` writes `HERMES_BACKEND_READY port=<n>` to fd 1
/// (`web_server.py` via `_write_machine_sentinel_line`); the legacy
/// `hermes dashboard` writes `HERMES_DASHBOARD_READY port=<n>`. Accepts both,
/// like the Desktop's `_READY_RE` in `backend-ready.ts`.
int? parseBackendReadyPort(String line) {
  final match = RegExp(r'HERMES_(?:BACKEND|DASHBOARD)_READY port=(\d+)')
      .firstMatch(line);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}

/// One staged-installer step from `--manifest` / `-Manifest`
/// (`{"name","title","category","needs_user_input"}`, protocol version 1).
final class InstallStage {
  const InstallStage({
    required this.name,
    required this.title,
    required this.category,
    required this.needsUserInput,
  });

  factory InstallStage.fromJson(Map<String, Object?> json) {
    final name = json['name'] as String?;
    if (name == null || name.isEmpty) {
      throw const FormatException('install manifest stage misses name');
    }
    return InstallStage(
      name: name,
      title: json['title'] as String? ?? name,
      category: json['category'] as String? ?? '',
      needsUserInput: json['needs_user_input'] as bool? ?? false,
    );
  }

  final String name;
  final String title;
  final String category;
  final bool needsUserInput;
}

/// The parsed `--manifest` payload: protocol version plus ordered stages.
final class InstallManifest {
  const InstallManifest({required this.protocolVersion, required this.stages});

  /// Parses the manifest JSON object (not the raw process output; see
  /// [parseManifestOutput] for the stdout scan).
  factory InstallManifest.fromJson(Map<String, Object?> json) {
    final stages = json['stages'];
    if (stages is! List) {
      throw const FormatException('install manifest misses stages');
    }
    return InstallManifest(
      protocolVersion: (json['protocol_version'] as num?)?.toInt() ?? 0,
      stages: [
        for (final stage in stages)
          if (stage is Map<String, Object?>) InstallStage.fromJson(stage),
      ],
    );
  }

  final int protocolVersion;
  final List<InstallStage> stages;
}

/// The per-stage JSON result frame: `{ok, stage, skipped[, reason]}`
/// (`emit_stage_json` in `install.sh`; `Invoke-Stage` in `install.ps1`, which
/// also reports `duration_ms`).
final class StageResult {
  const StageResult({
    required this.stage,
    required this.ok,
    required this.skipped,
    this.reason,
    this.duration,
  });

  factory StageResult.fromJson(Map<String, Object?> json) {
    final ok = json['ok'];
    final stage = json['stage'];
    if (ok is! bool || stage is! String) {
      throw const FormatException('stage result misses ok/stage');
    }
    final durationMs = (json['duration_ms'] as num?)?.toInt();
    return StageResult(
      stage: stage,
      ok: ok,
      skipped: json['skipped'] as bool? ?? false,
      reason: json['reason'] as String?,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }

  final String stage;
  final bool ok;
  final bool skipped;
  final String? reason;
  final Duration? duration;

  bool get failed => !ok;
}

/// Finds the manifest payload in `--manifest` stdout: the LAST line that
/// parses as JSON with a `stages` array (the ps1 script may print banner
/// lines first — `bootstrap-runner.ts fetchManifest`).
InstallManifest parseManifestOutput(String stdout) {
  final lines = const LineSplitter().convert(stdout);
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i].trim();
    if (!line.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?> && decoded['stages'] is List) {
        return InstallManifest.fromJson(decoded);
      }
    } on FormatException {
      continue;
    }
  }
  throw const FormatException('manifest output has no JSON payload');
}

/// Finds the stage result frame in `--stage` stdout: the LAST line that
/// parses as JSON with boolean `ok` and string `stage`
/// (`bootstrap-runner.ts parseStageResult`). Returns null when no frame was
/// emitted (a protocol violation the caller reports explicitly).
StageResult? parseStageResultOutput(String stdout) {
  final lines = const LineSplitter().convert(stdout);
  for (var i = lines.length - 1; i >= 0; i--) {
    final line = lines[i].trim();
    if (!line.startsWith('{')) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?> &&
          decoded['ok'] is bool &&
          decoded['stage'] is String) {
        return StageResult.fromJson(decoded);
      }
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// Progress events streamed by [HermesInstaller.run].
sealed class InstallProgress {
  const InstallProgress();
}

/// A raw installer output line (stdout or stderr), ANSI-stripped.
final class InstallLog extends InstallProgress {
  const InstallLog(this.stream, this.line);
  final String stream;
  final String line;
}

/// A stage started.
final class InstallStageStarted extends InstallProgress {
  const InstallStageStarted(this.stage);
  final InstallStage stage;
}

/// A stage finished (ok, skipped, or failed with [StageResult.reason]).
final class InstallStageFinished extends InstallProgress {
  const InstallStageFinished(this.stage, this.result);
  final InstallStage stage;
  final StageResult result;
}

/// The git commit of hermes-agent v0.21.5 that [HermesInstaller] pins:
/// the upstream `HEAD` the reference checkout reports for the release.
const hermesReleaseCommit = '130b8f2c5dbca93a81aa396dd2ba44420d78f6f0';

/// Where [HermesInstaller] fetches the staged installer from, mirroring the
/// Desktop `bootstrap-runner.ts` order: dev-checkout override, pinned GitHub
/// download cached under `HERMES_HOME/bootstrap-cache`, installed-agent
/// fallback.
final class InstallerSource {
  const InstallerSource({
    required this.isWindows,
    this.commit = hermesReleaseCommit,
    this.localScript,
    this.cacheBuster = '',
  });

  final bool isWindows;
  final String commit;
  final String? localScript;

  /// Appended to the cache filename so Hermuse never shares a cache slot
  /// with the Desktop runner.
  final String cacheBuster;

  String get scriptName => isWindows ? 'install.ps1' : 'install.sh';

  Uri downloadUri([String? ref]) => Uri.parse(
    'https://raw.githubusercontent.com/NousResearch/hermes-agent/${ref ?? commit}/scripts/$scriptName',
  );

  String cachePath(String hermesHome) {
    final sep = isWindows ? '\\' : '/';
    final ext = isWindows ? 'ps1' : 'sh';
    final key = cacheBuster.isEmpty ? commit : '$commit-$cacheBuster';
    return '$hermesHome${sep}bootstrap-cache${sep}install-$key.$ext';
  }

  String installedAgentScript(String hermesHome) {
    final sep = isWindows ? '\\' : '/';
    return '$hermesHome${sep}hermes-agent${sep}scripts$sep$scriptName';
  }
}

/// Outcome of [HermesInstaller.checkPrerequisites].
final class PrerequisiteCheck {
  const PrerequisiteCheck({required this.missing, this.fixCommand});

  /// Tools absent from PATH (`git`, `curl`, `tar` on POSIX).
  final List<String> missing;

  /// Exact command the user must run when the fix is known
  /// (macOS without git → `xcode-select --install`).
  final String? fixCommand;

  bool get ok => missing.isEmpty;
}

/// Drives the official staged installer protocol (`--manifest` / `--stage`
/// with `--non-interactive --json`; `-Manifest` / `-Stage` on Windows).
///
/// Construction is cheap; [manifest] and [run] resolve the script through
/// [InstallerSource] (download → cache → installed-agent fallback) and spawn
/// it via `bash` / PowerShell exactly like `bootstrap-runner.ts`. Stages
/// flagged `needs_user_input` are still invoked — the script's own
/// non-interactive handler emits the `skipped: true` frame, which is the
/// single source of truth. Never runs with sudo.
final class HermesInstaller {
  HermesInstaller({
    required this.hermesHome,
    required this.installDir,
    InstallerSource? source,
    Future<String> Function(Uri uri)? download,
    Future<ProcessResult> Function(
      String executable,
      List<String> args, {
      Map<String, String>? environment,
      void Function(String stream, String line)? onLine,
    })?
    runScript,
    Future<bool> Function(String path)? fileExists,
    Future<void> Function(String path, String content)? writeFile,
    Future<String?> Function(String name)? which,
    bool? isWindows,
    bool? isMacOS,
  }) : source = source ?? InstallerSource(isWindows: isWindows ?? false),
       _download = download ?? _downloadDefault,
       _runScript = runScript ?? _runScriptDefault,
       _fileExists = fileExists ?? ((path) => File(path).exists()),
       _writeFile = writeFile ?? _writeFileDefault,
       _which = which ?? _whichDefault,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final String hermesHome;
  final String installDir;
  final InstallerSource source;

  final Future<String> Function(Uri) _download;
  final Future<ProcessResult> Function(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  })
  _runScript;
  final Future<bool> Function(String path) _fileExists;
  final Future<void> Function(String path, String content) _writeFile;
  final Future<String?> Function(String name) _which;
  final bool _isWindows;
  final bool _isMacOS;

  /// Tools the POSIX installer shells out to and cannot self-provision.
  static const posixRequiredTools = ['git', 'curl', 'tar'];

  /// Checks the installer prerequisites before any stage runs. POSIX only:
  /// `git`, `curl`, `tar` on PATH. The Windows script self-provisions via
  /// winget, so it always passes there.
  Future<PrerequisiteCheck> checkPrerequisites() async {
    if (_isWindows) return const PrerequisiteCheck(missing: []);
    final missing = <String>[];
    for (final tool in posixRequiredTools) {
      if (await _which(tool) == null) missing.add(tool);
    }
    if (missing.isEmpty) return const PrerequisiteCheck(missing: []);
    final fix = _isMacOS && missing.contains('git')
        ? 'xcode-select --install'
        : null;
    return PrerequisiteCheck(missing: missing, fixCommand: fix);
  }

  /// Reads the stage manifest without side effects (`--manifest` /
  /// `-Manifest` only prints JSON).
  Future<InstallManifest> manifest() async {
    final script = await _resolveScript();
    final result = await _runScript(
      _isWindows ? 'powershell.exe' : 'bash',
      _isWindows
          ? [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              script,
              '-Manifest',
            ]
          : [script, '--manifest'],
      environment: {'HERMES_HOME': hermesHome},
    );
    if (result.exitCode != 0) {
      throw InstallFailed(
        '__manifest__',
        'installer --manifest failed (exit ${result.exitCode}): '
            '${result.stderr}${result.stdout}',
      );
    }
    return parseManifestOutput('${result.stdout}');
  }

  /// Runs one stage (`--stage <name> --non-interactive --json`) and returns
  /// its result frame. Used for "retry this stage" after a failed [run].
  Future<StageResult> runStage(
    String name, {
    void Function(String stream, String line)? onLine,
  }) async {
    final script = await _resolveScript();
    final result = await _runScript(
      _isWindows ? 'powershell.exe' : 'bash',
      _isWindows
          ? [
              '-NoProfile',
              '-ExecutionPolicy',
              'Bypass',
              '-File',
              script,
              '-Stage',
              name,
              '-NonInteractive',
              '-Json',
            ]
          : [script, '--stage', name, '--non-interactive', '--json'],
      environment: {'HERMES_HOME': hermesHome},
      onLine: onLine == null
          ? null
          : (stream, line) => onLine(stream, stripAnsi(line)),
    );
    final frame = parseStageResultOutput('${result.stdout}');
    if (frame == null) {
      throw InstallFailed(
        name,
        'installer stage $name produced no JSON result frame '
        '(exit=${result.exitCode})',
      );
    }
    return frame;
  }

  /// Runs every manifest stage in order, streaming [InstallProgress].
  ///
  /// Stages in [skip] are not invoked at all (default `{'setup','gateway'}`,
  /// whose interactive concerns the app's own onboarding owns); they are
  /// reported as [InstallStageFinished] with a synthetic skipped frame.
  /// Stages flagged `needs_user_input` outside [skip] ARE invoked so the
  /// script emits its own `skipped: true` frame. Stops after the first
  /// failing stage by throwing [InstallFailed].
  Stream<InstallProgress> run({
    Set<String> skip = const {'setup', 'gateway'},
  }) async* {
    final check = await checkPrerequisites();
    if (!check.ok) {
      final fix = check.fixCommand == null
          ? ''
          : ' Run `${check.fixCommand}` to install it.';
      throw PrerequisiteMissing(
        'missing required tools: ${check.missing.join(', ')}.$fix',
        fixCommand: check.fixCommand,
      );
    }
    final manifest = await this.manifest();
    for (final stage in manifest.stages) {
      if (skip.contains(stage.name)) {
        yield InstallStageStarted(stage);
        yield InstallStageFinished(
          stage,
          StageResult(stage: stage.name, ok: true, skipped: true),
        );
        continue;
      }
      yield InstallStageStarted(stage);
      final pending = <InstallLog>[];
      final result = await runStage(
        stage.name,
        onLine: (stream, line) =>
            pending.add(InstallLog(stream, stripAnsi(line))),
      );
      for (final log in pending) {
        yield log;
      }
      yield InstallStageFinished(stage, result);
      if (result.failed) {
        throw InstallFailed(
          stage.name,
          result.reason ?? 'stage ${stage.name} failed',
        );
      }
    }
  }

  /// Resolves the installer script path: explicit [InstallerSource.localScript]
  /// first (dev override), then the pinned GitHub download cached under
  /// `HERMES_HOME/bootstrap-cache`, then the installed-agent fallback.
  Future<String> _resolveScript() async {
    final local = source.localScript;
    if (local != null) {
      if (!await _fileExists(local)) {
        throw InstallerUnavailable('local installer not found: $local');
      }
      return local;
    }
    final cached = source.cachePath(hermesHome);
    if (await _fileExists(cached)) return cached;
    try {
      final content = await _download(source.downloadUri());
      await _writeFile(cached, content);
      return cached;
    } on Exception catch (e) {
      final fallback = source.installedAgentScript(hermesHome);
      if (await _fileExists(fallback)) return fallback;
      throw InstallerUnavailable(
        'cannot fetch ${source.scriptName} for ${source.commit}: $e',
      );
    }
  }

  static Future<String> _downloadDefault(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode} fetching $uri',
          uri: uri,
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  static Future<ProcessResult> _runScriptDefault(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment == null
          ? null
          : {...Platform.environment, ...environment},
      runInShell: false,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    void listen(Stream<List<int>> bytes, String stream, StringBuffer buffer) {
      bytes.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        buffer.writeln(line);
        onLine?.call(stream, line);
      });
    }

    listen(process.stdout, 'stdout', stdoutBuffer);
    listen(process.stderr, 'stderr', stderrBuffer);
    final code = await process.exitCode;
    return ProcessResult(
      process.pid,
      code,
      stdoutBuffer.toString(),
      stderrBuffer.toString(),
    );
  }

  static Future<void> _writeFileDefault(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  static Future<String?> _whichDefault(String name) async {
    final pathEnv =
        Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '';
    for (final dir in pathEnv.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = Platform.isWindows ? '$dir\\$name' : '$dir/$name';
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }
}

/// Strips SGR colours, cursor/erase sequences and carriage-return redraws
/// from installer output, keeping the last `\r` frame a terminal would show
/// (mirrors `bootstrap-runner.ts stripAnsi` for the overlay).
String stripAnsi(String line) {
  var text = line;
  final cr = text.lastIndexOf('\r');
  if (cr >= 0) text = text.substring(cr + 1);
  text = text.replaceAll(RegExp('\x1B\\][^\x07\x1B]*(?:\x07|\x1B\\\\)'), '');
  text = text.replaceAll(RegExp('\x1B\\[[0-9;?]*[A-Za-z]'), '');
  text = text.replaceAll(RegExp('\x1B[()][0-9A-B]'), '');
  return text;
}
