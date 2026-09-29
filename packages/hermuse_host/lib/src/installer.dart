import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

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

/// SHA-256 of `scripts/install.sh` at [hermesReleaseCommit]: the only bytes
/// the app runs as the POSIX installer, whichever source served them.
const hermesInstallShSha256 =
    '2017ddf0cc7bc6cfb70d40dc9fba1d916f47dbcccf5fe73bdee2cf93a11262af';

/// SHA-256 of `scripts/install.ps1` at [hermesReleaseCommit].
const hermesInstallPs1Sha256 =
    '0a80dfeb7434229933bac32e73140d10086dff81bd84b156e71be9abc87cddf2';

/// One download attempt of the installer script that returned no usable
/// bytes. [transient] failures (rate limits, server errors) may succeed
/// later from the same source, after at least [retryAfter] when the server
/// said so (`Retry-After`, or the reset of an exhausted API rate limit).
final class ScriptDownloadError implements Exception {
  const ScriptDownloadError(
    this.message, {
    required this.transient,
    this.retryAfter,
  });

  final String message;
  final bool transient;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// Where [HermesInstaller] gets the staged installer at [commit]:
/// [localScript] (development override) as is; otherwise the bytes whose
/// SHA-256 is [sha256], from the cache under `HERMES_HOME/bootstrap-cache`,
/// the pinned checkout of a previous install, or a download from
/// [downloadUris].
final class InstallerSource {
  const InstallerSource({
    required this.isWindows,
    this.commit = hermesReleaseCommit,
    this._sha256,
    this.localScript,
    this.cacheBuster = '',
  });

  final bool isWindows;
  final String commit;
  final String? localScript;
  final String? _sha256;

  /// Appended to the cache filename so Hermuse never shares a cache slot
  /// with the Desktop runner.
  final String cacheBuster;

  String get scriptName => isWindows ? 'install.ps1' : 'install.sh';

  /// Lowercase hex SHA-256 the script must have: the committed digest of
  /// [hermesReleaseCommit], or the one given for another [commit]. Null
  /// (another commit without a digest) refuses every source but
  /// [localScript].
  String? get sha256 =>
      _sha256 ??
      (commit == hermesReleaseCommit
          ? (isWindows ? hermesInstallPs1Sha256 : hermesInstallShSha256)
          : null);

  /// The download sources of the script at [commit], in order: GitHub's raw
  /// file host, then the contents endpoint of its REST API (raw media type).
  /// Same bytes, separately rate-limited hosts.
  List<Uri> get downloadUris => [
    Uri.https(
      'raw.githubusercontent.com',
      '/NousResearch/hermes-agent/$commit/scripts/$scriptName',
    ),
    Uri.https(
      'api.github.com',
      '/repos/NousResearch/hermes-agent/contents/scripts/$scriptName',
      {'ref': commit},
    ),
  ];

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
  const PrerequisiteCheck({
    required this.missing,
    this.fixCommand,
    this.installable = false,
  });

  /// What is missing: tools absent from PATH (`git`, `curl`, `tar` on
  /// POSIX) or, on macOS, [HermesInstaller.commandLineTools].
  final List<String> missing;

  /// Exact command the user must run when the fix is known
  /// (macOS without the Command Line Tools → `xcode-select --install`).
  final String? fixCommand;

  /// Whether [HermesInstaller.installPrerequisites] can start that fix:
  /// Apple's Command Line Tools installer on macOS.
  final bool installable;

  bool get ok => missing.isEmpty;
}

/// The user's XDG base directories. POSIX installer stages run without
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
/// [InstallerSource] (cache, pinned checkout, then download; every copy is
/// checked against [InstallerSource.sha256]) and spawn it via `bash` /
/// PowerShell exactly like `bootstrap-runner.ts`, with an environment built
/// from [hostEnvironment] only. Stages flagged `needs_user_input` are still
/// invoked — the script's own non-interactive handler emits the
/// `skipped: true` frame, which is the single source of truth. Never runs
/// with sudo.
///
/// POSIX stages (Linux, macOS) pin the checkout with `--commit`
/// ([InstallerSource.commit]), get `--dir`, `--skip-browser` and
/// `--skip-computer-use` (the agent's browser is the Hermuse computer
/// container, not a host Chromium or computer-use driver) and run in the
/// [ManagedRuntime]: `HOME` is the private `<hermesHome>/runtime`, created
/// first, the XDG base directories are unset so they default under it, and
/// `PATH` starts with its tool directories. No launcher, Node or Python
/// lands in the user's `~/.local` and no shell rc file of theirs is edited.
///
/// Windows stages (`install.ps1`) get the same pin and skips in its own
/// syntax: `-Commit`, `-HermesHome`, `-InstallDir` and `-SkipComputerUse`
/// (the script has no browser skip). They run in the host environment:
/// `install.ps1` keeps everything under `HERMES_HOME` (uv, PortableGit, Node,
/// the `bin\hermes.exe` launcher) and records its PATH additions in the
/// user's environment itself.
///
/// With a [journalPath] the install is the app's own: an [InstallJournal]
/// is written before the first stage, a fresh install refuses an existing
/// [installDir] the app does not own, stages also get `--force-commit` /
/// `-ForceCommit` (a re-run `repository` stage re-pins the app's own
/// checkout), [run] skips the stages that already succeeded and re-runs the
/// interrupted one, and the journal only closes once the result validates:
/// the checkout's `HEAD` and `<installDir>/.hermes-bootstrap-complete` name
/// the pinned commit and the installed launcher answers `--version`.
final class HermesInstaller {
  HermesInstaller({
    required this.hermesHome,
    required this.installDir,
    this.journalPath,
    InstallerSource? source,
    Map<String, String>? environment,
    Future<List<int>> Function(Uri uri)? download,
    Future<void> Function(Duration delay)? sleep,
    Future<ProcessResult> Function(
      String executable,
      List<String> args, {
      Map<String, String>? environment,
      void Function(String stream, String line)? onLine,
    })?
    runScript,
    Future<bool> Function(String path)? fileExists,
    this._which,
    bool? isWindows,
    bool? isMacOS,
  }) : source =
           source ??
           InstallerSource(isWindows: isWindows ?? Platform.isWindows),
       _environment = environment ?? hostEnvironment(),
       _download = download ?? _downloadDefault,
       _sleep = sleep ?? Future<void>.delayed,
       _runScript = runScript ?? _runScriptDefault,
       _fileExists = fileExists ?? ((path) => File(path).exists()),
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS;

  final String hermesHome;
  final String installDir;

  /// Where the [InstallJournal] of this install lives, under the app
  /// support directory; null runs the installer unjournaled.
  final String? journalPath;
  final InstallerSource source;

  /// The [hostEnvironment] every spawn starts from.
  final Map<String, String> _environment;
  final Future<List<int>> Function(Uri) _download;
  final Future<void> Function(Duration) _sleep;
  final Future<ProcessResult> Function(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  })
  _runScript;
  final Future<bool> Function(String path) _fileExists;
  final Future<String?> Function(String name)? _which;
  final bool _isWindows;
  final bool _isMacOS;

  ManagedRuntime get _runtime => ManagedRuntime(hermesHome);
  String get _shell => _isWindows ? 'powershell.exe' : 'bash';

  /// Tools the POSIX installer shells out to and cannot self-provision.
  static const posixRequiredTools = ['git', 'curl', 'tar'];

  /// What macOS reports missing without Apple's developer tools: they
  /// provide `git` and the compiler the stages build native modules with.
  static const commandLineTools = 'Xcode Command Line Tools';

  static const _xcodeSelect = '/usr/bin/xcode-select';

  /// Checks the installer prerequisites before any stage runs. POSIX only:
  /// `git`, `curl`, `tar` on PATH. On macOS `/usr/bin/git` is a stub until
  /// the [commandLineTools] are installed (running it opens Apple's
  /// installer), so git counts as present only when `xcode-select -p` names
  /// a developer directory holding it; the app can start that install
  /// ([PrerequisiteCheck.installable]). The Windows script self-provisions
  /// via winget, so it always passes there.
  Future<PrerequisiteCheck> checkPrerequisites() async {
    if (_isWindows) return const PrerequisiteCheck(missing: []);
    final which = _which ?? _whichOnPath;
    final missing = <String>[];
    if (_isMacOS && !await _hasCommandLineTools()) {
      missing.add(commandLineTools);
    }
    for (final tool in posixRequiredTools) {
      if (_isMacOS && tool == 'git') continue;
      if (await which(tool) == null) missing.add(tool);
    }
    if (missing.isEmpty) return const PrerequisiteCheck(missing: []);
    final tools = missing.contains(commandLineTools);
    return PrerequisiteCheck(
      missing: missing,
      fixCommand: tools ? 'xcode-select --install' : null,
      installable: tools,
    );
  }

  /// Starts the fix of an [PrerequisiteCheck.installable] check: on macOS,
  /// Apple's installer for the [commandLineTools] (`xcode-select
  /// --install`). Returns once its dialog is requested; the user completes
  /// the install there and [checkPrerequisites] tells when it is done.
  /// Throws [ProcessFailed] when the request is refused, for instance when
  /// the tools are already installed.
  Future<void> installPrerequisites() async {
    if (!_isMacOS) {
      throw UnsupportedError('only macOS prerequisites can be installed');
    }
    final result = await _runScript(_xcodeSelect, const [
      '--install',
    ], environment: _environment);
    if (result.exitCode != 0) {
      throw ProcessFailed(
        'xcode-select --install failed (exit ${result.exitCode})',
        exitCode: result.exitCode,
        outputTail: '${result.stdout}${result.stderr}'.trim(),
      );
    }
  }

  /// Whether `xcode-select -p` names a developer directory (the Command
  /// Line Tools or Xcode) with its `git`.
  Future<bool> _hasCommandLineTools() async {
    final ProcessResult result;
    try {
      result = await _runScript(_xcodeSelect, const [
        '-p',
      ], environment: _environment).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return false;
    } on ProcessException {
      return false;
    }
    final directory = '${result.stdout}'.trim();
    return result.exitCode == 0 &&
        directory.isNotEmpty &&
        await _fileExists('$directory/usr/bin/git');
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
  /// Stages in [skip] are not invoked at all (default `setup` and
  /// `configure`, the POSIX and Windows setup wizards, and `gateway`, whose
  /// interactive concerns the app's own onboarding owns); they are
  /// reported as [InstallStageFinished] with a synthetic skipped frame, like
  /// the stages the journal records as done
  /// ([InstallStageFinished.previouslyCompleted]). Stages flagged
  /// `needs_user_input` outside [skip] ARE invoked so the script emits its
  /// own `skipped: true` frame. Stops after the first failing stage by
  /// throwing [InstallFailed], which a failed validation also throws with
  /// the stage to run again. A stage already running when the listener
  /// cancels still completes (and is journaled); no later stage starts.
  Stream<InstallProgress> run({
    Set<String> skip = const {'setup', 'configure', 'gateway'},
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
          '-Commit',
          source.commit,
          if (owned) '-ForceCommit',
          '-HermesHome',
          hermesHome,
          '-InstallDir',
          installDir,
          '-SkipComputerUse',
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
          '--dir',
          installDir,
          '--skip-browser',
          '--skip-computer-use',
          '--non-interactive',
          '--json',
        ];

  /// The complete environment of a stage; on POSIX the [ManagedRuntime]
  /// (whose `HOME` is created here).
  Future<Map<String, String>> _stageEnvironment() async {
    final environment = {..._environment, 'HERMES_HOME': hermesHome};
    if (_isWindows) return environment;
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
      runtimeHome: _isWindows ? null : _runtime.home,
      commit: source.commit,
      startedAt: DateTime.now().toUtc(),
    );
    await journal.write(path);
    return journal;
  }

  /// The launchers a validated install may answer `--version` with, in
  /// lookup order: the [ManagedRuntime] one on POSIX; on Windows the
  /// `path` stage's `<hermesHome>\bin\hermes.exe`, or `hermes.cmd` for a
  /// relocatable venv (`Install-HermesCommandLaunchers`).
  List<String> get _launchers => _isWindows
      ? ['$hermesHome\\bin\\hermes.exe', '$hermesHome\\bin\\hermes.cmd']
      : [_runtime.launcher];

  /// The stage writing `<installDir>/.hermes-bootstrap-complete`.
  String get _markerStage => _isWindows ? 'bootstrap-marker' : 'complete';

  /// Validates the finished install and closes [journal], or reopens the
  /// stage a defect traces back to and throws [InstallFailed] for it.
  Future<void> _close(InstallJournal journal) async {
    final path = journalPath!;
    final commit = source.commit;
    final head = await _readTrimmed('$installDir/.git/HEAD');
    final marker = await _markerCommit();
    final launcher = await _existingLauncher();
    final (String, String)? defect = head != commit
        ? (
            'repository',
            'the checkout $installDir is at ${head ?? 'no commit'}, not the '
                'pinned $commit',
          )
        : marker != commit
        ? (
            _markerStage,
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

  /// `pinnedCommit` of the bootstrap marker the marker stage writes
  /// (`write_bootstrap_marker` / `Write-BootstrapMarker`, schema 1), or null.
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

  /// The first of [_launchers] that exists, else the first one (whose
  /// `--version` then fails).
  Future<String> _existingLauncher() async {
    final launchers = _launchers;
    for (final launcher in launchers) {
      if (await _fileExists(launcher)) return launcher;
    }
    return launchers.first;
  }

  Future<bool> _answersVersion(String launcher) async {
    try {
      final result = await _runScript(
        launcher,
        const ['--version'],
        environment: {
          ..._environment,
          'HERMES_HOME': hermesHome,
          if (!_isWindows) 'PATH': _runtime.prefixPath(_environment['PATH']),
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

  /// Waits between the rounds of download attempts over every source: a
  /// rate limit or a network failure gets about a minute and a half to
  /// clear before the install reports the script unavailable.
  static const _scriptRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 20),
    Duration(seconds: 60),
  ];

  /// The longest wait a server may ask for before its source is tried
  /// again; a longer one (an exhausted hourly API quota) gives it up.
  static const _longestServerWait = Duration(minutes: 2);

  static const _downloadTimeout = Duration(seconds: 60);

  /// The installer scripts weigh about 250 KB: a larger body is not one.
  static const _maxScriptBytes = 4 << 20;

  /// Resolves the installer script path: [InstallerSource.localScript]
  /// (dev override) as is; otherwise a copy under
  /// `HERMES_HOME/bootstrap-cache` whose bytes have [InstallerSource.sha256].
  /// A missing or different cached copy is replaced with the script of the
  /// pinned checkout a previous install left, when its bytes match, else
  /// with a download ([_fetchScript]). The script never runs from the
  /// checkout its stages rewrite.
  Future<String> _resolveScript() async {
    final local = source.localScript;
    if (local != null) {
      if (!await _fileExists(local)) {
        throw InstallerUnavailable('local installer not found: $local');
      }
      return local;
    }
    final digest = source.sha256;
    if (digest == null) {
      throw InstallerUnavailable(
        'no SHA-256 is pinned for ${source.scriptName} at ${source.commit}',
      );
    }
    final cached = source.cachePath(hermesHome);
    if (await _digestOf(cached) == digest) return cached;
    final installed = source.installedAgentScript(hermesHome);
    final bytes = await _digestOf(installed) == digest
        ? await File(installed).readAsBytes()
        : await _fetchScript(digest);
    await _writeCache(cached, bytes);
    return cached;
  }

  /// Downloads the script from [InstallerSource.downloadUris] until a source
  /// serves the bytes with [digest]. A transient failure (rate limit, server
  /// error, network) is tried again after the next of [_scriptRetryDelays],
  /// or after the longer wait its server asked for; a source serving other
  /// bytes, refusing for good, or asking to wait beyond [_longestServerWait]
  /// is given up. Throws [InstallerUnavailable] with the last failure of
  /// every source.
  Future<List<int>> _fetchScript(String digest) async {
    final failures = <String, String>{};
    var sources = source.downloadUris;
    for (var round = 0; ; round++) {
      final retry = <Uri>[];
      var soonest = _longestServerWait;
      for (final uri in sources) {
        Duration? wait;
        try {
          final bytes = await _download(uri);
          final got = '${crypto.sha256.convert(bytes)}';
          if (got == digest) return bytes;
          failures[uri.host] = 'served SHA-256 $got, not the pinned $digest';
        } on ScriptDownloadError catch (e) {
          failures[uri.host] = e.message;
          if (e.transient) wait = e.retryAfter ?? Duration.zero;
        }
        if (wait == null || wait > _longestServerWait) continue;
        retry.add(uri);
        if (wait < soonest) soonest = wait;
      }
      if (retry.isEmpty || round == _scriptRetryDelays.length) {
        final reasons = [
          for (final MapEntry(:key, :value) in failures.entries) '$key: $value',
        ];
        throw InstallerUnavailable(
          'cannot download ${source.scriptName} at ${source.commit} '
          '(${reasons.join('; ')})',
        );
      }
      final delay = _scriptRetryDelays[round];
      await _sleep(soonest > delay ? soonest : delay);
      sources = retry;
    }
  }

  /// Lowercase hex SHA-256 of the file at [path]; null when unreadable.
  static Future<String?> _digestOf(String path) async {
    try {
      return '${await crypto.sha256.bind(File(path).openRead()).first}';
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [bytes] to [path] through a temporary file, so a crash never
  /// leaves a truncated script behind.
  static Future<void> _writeCache(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final partial = await File('$path.partial')
        .writeAsBytes(bytes, flush: true);
    if (await file.exists()) await file.delete();
    await partial.rename(path);
  }

  /// GETs [uri], in the raw media type for the GitHub REST API: the body of
  /// a 200, else a [ScriptDownloadError] saying whether and when the source
  /// may answer.
  static Future<List<int>> _downloadDefault(Uri uri) async {
    final client = HttpClient()..connectionTimeout = _downloadTimeout;
    try {
      final request = await client.getUrl(uri);
      if (uri.host == 'api.github.com') {
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/vnd.github.raw')
          ..set('x-github-api-version', '2022-11-28');
      }
      final response = await request.close().timeout(_downloadTimeout);
      final status = response.statusCode;
      if (status != HttpStatus.ok) {
        final wait = _serverWait(response.headers, DateTime.now().toUtc());
        throw ScriptDownloadError(
          'HTTP $status',
          transient:
              status == HttpStatus.requestTimeout ||
              status == HttpStatus.tooManyRequests ||
              status >= 500 ||
              (status == HttpStatus.forbidden && wait != null),
          retryAfter: wait,
        );
      }
      final body = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_downloadTimeout)) {
        body.add(chunk);
        if (body.length > _maxScriptBytes) {
          throw const ScriptDownloadError(
            'larger than an installer script',
            transient: false,
          );
        }
      }
      return body.takeBytes();
    } on TlsException catch (e) {
      throw ScriptDownloadError('TLS: ${e.message}', transient: false);
    } on IOException catch (e) {
      throw ScriptDownloadError('$e', transient: true);
    } on TimeoutException {
      throw ScriptDownloadError(
        'no answer within ${_downloadTimeout.inSeconds} s',
        transient: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// The wait a refusal asks for: `Retry-After` (seconds or an HTTP date),
  /// else the reset of an exhausted GitHub API rate limit; null when none.
  static Duration? _serverWait(HttpHeaders headers, DateTime now) {
    final DateTime at;
    final retryAfter = headers.value(HttpHeaders.retryAfterHeader);
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter.trim());
      if (seconds != null) return Duration(seconds: seconds < 0 ? 0 : seconds);
      try {
        at = HttpDate.parse(retryAfter);
      } on HttpException {
        return null;
      }
    } else if (headers.value('x-ratelimit-remaining') == '0') {
      final reset = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
      if (reset == null) return null;
      at = DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true);
    } else {
      return null;
    }
    return at.isAfter(now) ? at.difference(now) : Duration.zero;
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
