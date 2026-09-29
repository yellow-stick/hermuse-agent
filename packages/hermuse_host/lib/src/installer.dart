import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'host_environment.dart';
import 'install_journal.dart';
import 'managed_runtime.dart';

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

/// A raw installer output line (stdout or stderr), ANSI-stripped, streamed
/// while its stage runs.
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
  const InstallStageFinished(
    this.stage,
    this.result, {
    this.previouslyCompleted = false,
  });
  final InstallStage stage;
  final StageResult result;

  /// Whether the stage succeeded in an earlier run recorded in the
  /// [InstallJournal] and was not run again ([result] is then synthetic).
  final bool previouslyCompleted;
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

/// The user's XDG base directories. Linux installer stages run without
/// them, so every tool defaults to the private runtime `HOME` instead.
const _userDirectoryVariables = {
  'XDG_BIN_HOME',
  'XDG_CACHE_HOME',
  'XDG_CONFIG_HOME',
  'XDG_DATA_HOME',
  'XDG_STATE_HOME',
};

/// PowerShell arguments ahead of the script path.
const _powerShellPrefix = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File'];

/// Drives the official staged installer protocol (`--manifest` / `--stage`
/// with `--non-interactive --json`; `-Manifest` / `-Stage` on Windows).
///
/// Construction is cheap; [manifest] and [run] resolve the script through
/// [InstallerSource] (download → cache → installed-agent fallback) and spawn
/// it via `bash` / PowerShell exactly like `bootstrap-runner.ts`, with an
/// environment built from [hostEnvironment] only. Stages flagged
/// `needs_user_input` are still invoked — the script's own non-interactive
/// handler emits the `skipped: true` frame, which is the single source of
/// truth. Never runs with sudo.
///
/// POSIX stages pin the checkout with `--commit` ([InstallerSource.commit]).
/// On Linux every stage also gets `--dir`, `--skip-browser` and
/// `--skip-computer-use` (the agent's browser is the Hermuse computer
/// container, not a host Chromium or computer-use driver) and runs in the
/// [ManagedRuntime]: `HOME` is the private `<hermesHome>/runtime`, created
/// first, the XDG base directories are unset so they default under it, and
/// `PATH` starts with its tool directories. No launcher, Node or Python
/// lands in the user's `~/.local` and no shell rc file of theirs is edited.
///
/// With a [journalPath] (Linux only) the install is the app's own: an
/// [InstallJournal] is written before the first stage, a fresh install
/// refuses an existing [installDir] the app does not own, stages also get
/// `--force-commit` (a re-run `repository` stage re-pins the app's own
/// checkout), [run] skips the stages that already succeeded and re-runs the
/// interrupted one, and the journal only closes once the result validates:
/// the checkout's `HEAD` and `<installDir>/.hermes-bootstrap-complete` name
/// the pinned commit and the managed launcher answers `--version`.
final class HermesInstaller {
  HermesInstaller({
    required this.hermesHome,
    required this.installDir,
    this.journalPath,
    InstallerSource? source,
    Map<String, String>? environment,
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
    this._which,
    bool? isWindows,
    bool? isMacOS,
  }) : source = source ?? InstallerSource(isWindows: isWindows ?? false),
       _environment = environment ?? hostEnvironment(),
       _download = download ?? _downloadDefault,
       _runScript = runScript ?? _runScriptDefault,
       _fileExists = fileExists ?? ((path) => File(path).exists()),
       _writeFile = writeFile ?? _writeFileDefault,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS {
    if (journalPath != null && !_isLinux) {
      throw ArgumentError.value(
        journalPath,
        'journalPath',
        'install journals are kept on Linux only',
      );
    }
  }

  final String hermesHome;
  final String installDir;

  /// Where the [InstallJournal] of this install lives, under the app
  /// support directory; null runs the installer unjournaled.
  final String? journalPath;
  final InstallerSource source;

  /// The [hostEnvironment] every spawn starts from.
  final Map<String, String> _environment;
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
  final Future<String?> Function(String name)? _which;
  final bool _isWindows;
  final bool _isMacOS;

  bool get _isLinux => !_isWindows && !_isMacOS;
  ManagedRuntime get _runtime => ManagedRuntime(hermesHome);
  String get _shell => _isWindows ? 'powershell.exe' : 'bash';

  /// Tools the POSIX installer shells out to and cannot self-provision.
  static const posixRequiredTools = ['git', 'curl', 'tar'];

  /// Checks the installer prerequisites before any stage runs. POSIX only:
  /// `git`, `curl`, `tar` on PATH. The Windows script self-provisions via
  /// winget, so it always passes there.
  Future<PrerequisiteCheck> checkPrerequisites() async {
    if (_isWindows) return const PrerequisiteCheck(missing: []);
    final which = _which ?? _whichOnPath;
    final missing = <String>[];
    for (final tool in posixRequiredTools) {
      if (await which(tool) == null) missing.add(tool);
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
      _shell,
      _isWindows
          ? [..._powerShellPrefix, script, '-Manifest']
          : [script, '--manifest'],
      environment: {..._environment, 'HERMES_HOME': hermesHome},
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

  /// Runs one stage and returns its result frame. Used for "retry this
  /// stage" after a failed [run]; journaled like the stages of [run].
  Future<StageResult> runStage(
    String name, {
    void Function(String stream, String line)? onLine,
  }) async {
    final (result, _) = await _runStage(
      name,
      await _openJournal(),
      onLine: onLine,
    );
    return result;
  }

  /// Runs every manifest stage in order, streaming [InstallProgress]; the
  /// [InstallLog] lines of a stage arrive while it runs.
  ///
  /// Stages in [skip] are not invoked at all (default `{'setup','gateway'}`,
  /// whose interactive concerns the app's own onboarding owns); they are
  /// reported as [InstallStageFinished] with a synthetic skipped frame, like
  /// the stages the journal records as done
  /// ([InstallStageFinished.previouslyCompleted]). Stages flagged
  /// `needs_user_input` outside [skip] ARE invoked so the script emits its
  /// own `skipped: true` frame. Stops after the first failing stage by
  /// throwing [InstallFailed], which a failed validation also throws with
  /// the stage to run again. A stage already running when the listener
  /// cancels still completes (and is journaled); no later stage starts.
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
    var journal = await _openJournal();
    for (final stage in manifest.stages) {
      if (skip.contains(stage.name)) {
        yield InstallStageStarted(stage);
        yield InstallStageFinished(
          stage,
          StageResult(stage: stage.name, ok: true, skipped: true),
        );
        continue;
      }
      if (journal != null && journal.hasCompleted(stage.name)) {
        yield InstallStageStarted(stage);
        yield InstallStageFinished(
          stage,
          StageResult(stage: stage.name, ok: true, skipped: false),
          previouslyCompleted: true,
        );
        continue;
      }
      yield InstallStageStarted(stage);
      final logs = StreamController<InstallProgress>();
      final outcome = _runStage(
        stage.name,
        journal,
        onLine: (stream, line) {
          if (!logs.isClosed) logs.add(InstallLog(stream, line));
        },
      );
      // The outcome is awaited below; this only ends the log stream, also
      // when the listener is gone.
      unawaited(
        outcome
            .then<void>((_) {}, onError: (Object _) {})
            .whenComplete(logs.close),
      );
      yield* logs.stream;
      final (result, updated) = await outcome;
      journal = updated;
      yield InstallStageFinished(stage, result);
      if (result.failed) {
        throw InstallFailed(
          stage.name,
          result.reason ?? 'stage ${stage.name} failed',
        );
      }
    }
    if (journal != null) await _close(journal);
  }

  /// Runs stage [name], recording it in [journal] (when journaled) before
  /// the spawn and again once it succeeded.
  Future<(StageResult, InstallJournal?)> _runStage(
    String name,
    InstallJournal? journal, {
    void Function(String stream, String line)? onLine,
  }) async {
    final script = await _resolveScript();
    final environment = await _stageEnvironment();
    var current = journal?.withStageStarted(name);
    await current?.write(journalPath!);
    final result = await _runScript(
      _shell,
      _stageArguments(script, name, owned: journal != null),
      environment: environment,
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
    if (current != null && frame.ok) {
      current = current.withStageCompleted(name);
      await current.write(journalPath!);
    }
    return (frame, current);
  }

  List<String> _stageArguments(
    String script,
    String name, {
    required bool owned,
  }) => _isWindows
      ? [
          ..._powerShellPrefix,
          script,
          '-Stage',
          name,
          '-NonInteractive',
          '-Json',
        ]
      : [
          script,
          '--stage',
          name,
          '--commit',
          source.commit,
          if (owned) '--force-commit',
          if (_isLinux) ...[
            '--dir',
            installDir,
            '--skip-browser',
            '--skip-computer-use',
          ],
          '--non-interactive',
          '--json',
        ];

  /// The complete environment of a stage; on Linux the [ManagedRuntime]
  /// (whose `HOME` is created here).
  Future<Map<String, String>> _stageEnvironment() async {
    final environment = {..._environment, 'HERMES_HOME': hermesHome};
    if (!_isLinux) return environment;
    final runtime = _runtime;
    await Directory(runtime.home).create(recursive: true);
    environment.removeWhere(
      (name, _) => _userDirectoryVariables.contains(name),
    );
    return {
      ...environment,
      'HOME': runtime.home,
      'PATH': runtime.prefixPath(environment['PATH']),
    };
  }

  /// The journal to continue, or a new one written before any stage runs;
  /// null when unjournaled.
  ///
  /// An unfinished journal of this install at the current pin resumes. A
  /// journal of this install that finished (or pins another commit) proves
  /// the checkout is the app's, so a new run may repair or re-pin it.
  /// Without one, [installDir] must not exist: a checkout Hermuse did not
  /// install is never modified ([InstallBlocked]).
  Future<InstallJournal?> _openJournal() async {
    final path = journalPath;
    if (path == null) return null;
    final InstallJournal? existing;
    try {
      existing = await InstallJournal.read(path);
    } on FormatException catch (e) {
      throw InstallBlocked(
        'the install journal $path cannot be read (${e.message}). The state '
        'of $installDir is unknown: remove both to install again.',
      );
    }
    final owned =
        existing != null &&
        existing.hermesHome == hermesHome &&
        existing.installDir == installDir;
    if (owned && !existing.finished && existing.commit == source.commit) {
      return existing;
    }
    if (!owned && await Directory(installDir).exists()) {
      throw InstallBlocked(
        '$installDir already exists and was not installed by Hermuse; it is '
        'left untouched. Remove it or repair it yourself to continue.',
      );
    }
    final journal = InstallJournal(
      hermesHome: hermesHome,
      installDir: installDir,
      runtimeHome: _runtime.home,
      commit: source.commit,
      startedAt: DateTime.now().toUtc(),
    );
    await journal.write(path);
    return journal;
  }

  /// Validates the finished install and closes [journal], or reopens the
  /// stage a defect traces back to and throws [InstallFailed] for it.
  Future<void> _close(InstallJournal journal) async {
    final path = journalPath!;
    final commit = source.commit;
    final head = await _readTrimmed('$installDir/.git/HEAD');
    final marker = await _markerCommit();
    final launcher = _runtime.launcher;
    final (String, String)? defect = head != commit
        ? (
            'repository',
            'the checkout $installDir is at ${head ?? 'no commit'}, not the '
                'pinned $commit',
          )
        : marker != commit
        ? (
            'complete',
            '$installDir/.hermes-bootstrap-complete '
                '${marker == null ? 'is missing or malformed' : 'pins $marker'}'
                ', not $commit',
          )
        : !await _answersVersion(launcher)
        ? ('path', 'the installed launcher $launcher does not answer --version')
        : null;
    if (defect case (final stage, final message)?) {
      await journal.withStageReopened(stage).write(path);
      throw InstallFailed(stage, message);
    }
    await journal.asFinished().write(path);
  }

  /// `pinnedCommit` of the bootstrap marker the `complete` stage writes
  /// (`write_bootstrap_marker`, schema 1), or null.
  Future<String?> _markerCommit() async {
    final content = await _readTrimmed(
      '$installDir/.hermes-bootstrap-complete',
    );
    if (content == null) return null;
    try {
      return switch (jsonDecode(content)) {
        {'schemaVersion': 1, 'pinnedCommit': final String commit} => commit,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }

  Future<bool> _answersVersion(String launcher) async {
    try {
      final result = await _runScript(
        launcher,
        const ['--version'],
        environment: {
          ..._environment,
          'HERMES_HOME': hermesHome,
          'PATH': _runtime.prefixPath(_environment['PATH']),
        },
      ).timeout(const Duration(seconds: 30));
      return result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty;
    } on TimeoutException {
      return false;
    } on ProcessException {
      return false;
    }
  }

  static Future<String?> _readTrimmed(String path) async {
    try {
      return (await File(path).readAsString()).trim();
    } on FileSystemException {
      return null;
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

  /// Spawns [executable] with exactly [environment] (the app's own is never
  /// inherited) and returns once both output streams ended, so the last
  /// line — the stage's JSON frame — is never lost.
  static Future<ProcessResult> _runScriptDefault(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  }) async {
    final process = await Process.start(
      executable,
      args,
      environment: environment ?? hostEnvironment(),
      includeParentEnvironment: false,
      runInShell: false,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    Future<void> collect(
      Stream<List<int>> bytes,
      String stream,
      StringBuffer buffer,
    ) => bytes
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          buffer.writeln(line);
          onLine?.call(stream, line);
        });

    final output = Future.wait([
      collect(process.stdout, 'stdout', stdoutBuffer),
      collect(process.stderr, 'stderr', stderrBuffer),
    ]);
    final code = await process.exitCode;
    // A daemon the script left behind may hold the pipes open: stop
    // waiting for them shortly after the exit.
    await output.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const [],
    );
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

  /// Looks [name] up on the `PATH` of the host environment.
  Future<String?> _whichOnPath(String name) async {
    final pathEnv = _environment['PATH'] ?? _environment['Path'] ?? '';
    for (final dir in pathEnv.split(_isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = _isWindows ? '$dir\\$name' : '$dir/$name';
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
