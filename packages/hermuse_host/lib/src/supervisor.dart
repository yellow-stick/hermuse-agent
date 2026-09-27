import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';

/// Lifecycle of a [Supervisor]-owned child process.
enum SupervisorState {
  /// Never started, or stopped cleanly via [Supervisor.stop].
  stopped,

  /// The child was spawned and has not announced readiness yet.
  starting,

  /// The readiness predicate matched (or none was configured and the child
  /// survived spawn).
  running,

  /// The child exited unexpectedly; a restart is scheduled.
  restarting,
}

final class SupervisorLog {
  const SupervisorLog(this.stream, this.line);

  /// Either `stdout` or `stderr`.
  final String stream;
  final String line;

  @override
  String toString() => '[$stream] $line';
}

/// Result of [Supervisor.start] / [Supervisor.ensureStarted].
final class SupervisorStarted {
  const SupervisorStarted({required this.pid, required this.alreadyRunning});

  /// The child pid (current supervisor-owned process).
  final int pid;

  /// True when the supervisor was already running and no spawn happened.
  final bool alreadyRunning;
}

/// Generic child-process supervisor: spawn with args/env, stream logs,
/// restart with exponential backoff on unexpected exit, and stop ONLY the
/// process it started.
///
/// The supervisor owns exactly one [Process] at a time. [stop] signals that
/// handle with SIGTERM (or `taskkill` semantics via [Process.kill] on
/// Windows) and escalates to SIGKILL after [killTimeout]; it never kills by
/// pid, port, or name, so a reused pid or a sibling process is never touched.
///
/// Restart policy: an unexpected exit (anything but [stop]) schedules a
/// restart after `min(1s * 2^attempt, 30s)`. There is no restart cap: a
/// supervised backend is expected to be available whenever the app runs; the
/// UI reads [state] and offers a manual stop. [stop] cancels any pending
/// restart.
final class Supervisor {
  Supervisor({
    required this.executable,
    required this.arguments,
    this.environment,
    this.workingDirectory,
    this.readiness,
    this.startTimeout = const Duration(seconds: 90),
    this.killTimeout = const Duration(seconds: 5),
    Future<Process> Function(
      String executable,
      List<String> args, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool runInShell,
    })?
    spawn,
  }) : _spawn = spawn ?? Process.start;

  /// Program to spawn (absolute path or resolved on PATH).
  final String executable;
  final List<String> arguments;

  /// Extra/dropped environment entries merged over [Platform.environment].
  final Map<String, String>? environment;
  final String? workingDirectory;

  /// Matches readiness on a stdout line and returns the parsed payload (e.g.
  /// the announced port), or null to keep waiting. When null, the child
  /// counts as running once spawned.
  final int? Function(String line)? readiness;

  /// How long to wait for [readiness] before failing the start. Mirrors the
  /// Desktop's 90 s port-announce default (`backend-ready.ts`).
  final Duration startTimeout;

  /// Delay between SIGTERM and the SIGKILL escalation in [stop].
  final Duration killTimeout;

  final Future<Process> Function(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell,
  })
  _spawn;

  final _stateController = StreamController<SupervisorState>.broadcast();
  final _logController = StreamController<SupervisorLog>.broadcast();
  final List<String> _tail = [];
  SupervisorState _state = SupervisorState.stopped;
  Process? _process;
  Completer<int?>? _readyCompleter;
  Timer? _restartTimer;
  Timer? _startTimer;
  int _restarts = 0;
  bool _stopping = false;
  bool _disposed = false;

  /// Broadcast lifecycle stream; the current value is [state].
  Stream<SupervisorState> get stateChanges => _stateController.stream;

  /// Current lifecycle state.
  SupervisorState get state => _state;

  /// Broadcast child-output stream (stdout and stderr lines).
  Stream<SupervisorLog> get logs => _logController.stream;

  /// Pid of the currently owned process, or null when none.
  int? get pid => _process?.pid;

  /// Payload parsed by [readiness] for the current process (if any).
  int? readyValue;

  /// How many unexpected restarts happened since the last clean start/stop.
  int get restartCount => _restarts;

  /// Last output lines (bounded to 200) for error reports.
  List<String> get outputTail => List.unmodifiable(_tail);

  /// Whether a supervisor-owned process is currently alive.
  bool get isRunning =>
      _process != null &&
      (_state == SupervisorState.starting || _state == SupervisorState.running);

  /// Starts the child; no-op (returning `alreadyRunning: true`) when one is
  /// alive. Fails with [ProcessFailed] when readiness times out.
  Future<SupervisorStarted> ensureStarted() async {
    if (isRunning) return SupervisorStarted(pid: pid!, alreadyRunning: true);
    return start();
  }

  /// Spawns the child and waits for [readiness] (or spawn survival when no
  /// predicate is set). Throws [ProcessFailed] on spawn failure, early exit,
  /// or [startTimeout].
  Future<SupervisorStarted> start() async {
    _throwIfDisposed();
    if (isRunning) return SupervisorStarted(pid: pid!, alreadyRunning: true);
    _restartTimer?.cancel();
    _restartTimer = null;

    final process = await _spawnChild();
    _process = process;
    _restarts = 0;
    _setState(SupervisorState.starting);

    if (readiness == null) {
      _watchExit(process);
      _setState(SupervisorState.running);
      return SupervisorStarted(pid: process.pid, alreadyRunning: false);
    }

    final completer = Completer<int?>();
    _readyCompleter = completer;
    _watchExit(process);
    _startTimer?.cancel();
    _startTimer = Timer(startTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          ProcessFailed(
            '$executable announced no readiness within ${startTimeout.inSeconds}s',
            outputTail: _tail.join('\n'),
          ),
        );
      }
    });
    try {
      readyValue = await completer.future;
    } catch (_) {
      _startTimer?.cancel();
      _readyCompleter = null;
      await stop();
      rethrow;
    }
    _startTimer?.cancel();
    _readyCompleter = null;
    _setState(SupervisorState.running);
    return SupervisorStarted(pid: process.pid, alreadyRunning: false);
  }

  /// Stops the owned process (SIGTERM, then SIGKILL after [killTimeout]) and
  /// cancels any pending restart. Idempotent; never touches processes this
  /// supervisor did not spawn.
  Future<void> stop() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    _startTimer?.cancel();
    _startTimer = null;
    final completer = _readyCompleter;
    _readyCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(
        const ProcessFailed('supervisor stopped while starting'),
      );
    }
    final process = _process;
    _process = null;
    if (process == null) {
      _setState(SupervisorState.stopped);
      return;
    }
    _stopping = true;
    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        killTimeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return process.exitCode;
        },
      );
    } finally {
      _stopping = false;
    }
    _setState(SupervisorState.stopped);
  }

  /// [stop] plus closing the streams. The supervisor is unusable afterwards.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _stateController.close();
    await _logController.close();
  }

  Future<Process> _spawnChild() async {
    try {
      final process = await _spawn(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment == null
            ? null
            : {...Platform.environment, ...environment!},
        runInShell: false,
      );
      _attachLogs(process);
      return process;
    } on ProcessException catch (e) {
      throw ProcessFailed('cannot spawn $executable: ${e.message}');
    }
  }

  void _attachLogs(Process process) {
    void listen(Stream<List<int>> bytes, String stream) {
      bytes
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _onLine(process, stream, line), onError: (_) {});
    }

    listen(process.stdout, 'stdout');
    listen(process.stderr, 'stderr');
  }

  void _onLine(Process process, String stream, String line) {
    if (identical(process, _process)) {
      _tail.add('[$stream] $line');
      if (_tail.length > 200) _tail.removeRange(0, _tail.length - 200);
      if (!_logController.isClosed) {
        _logController.add(SupervisorLog(stream, line));
      }
    }
    if (stream == 'stdout' && identical(process, _process)) {
      final value = readiness?.call(line);
      final completer = _readyCompleter;
      if (value != null && completer != null && !completer.isCompleted) {
        completer.complete(value);
      }
    }
  }

  void _watchExit(Process process) {
    process.exitCode.then((code) {
      if (!identical(process, _process)) return; // stale handle: ignore.
      _process = null;
      final completer = _readyCompleter;
      _readyCompleter = null;
      if (_stopping || _disposed) {
        if (completer != null && !completer.isCompleted) {
          completer.completeError(
            const ProcessFailed('supervisor stopped while starting'),
          );
        }
        _setState(SupervisorState.stopped);
        return;
      }
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          ProcessFailed(
            '$executable exited (code $code) before readiness',
            exitCode: code,
            outputTail: _tail.join('\n'),
          ),
        );
        _setState(SupervisorState.stopped);
        return;
      }
      // Unexpected exit of a running child: backoff restart.
      final delay = _backoffDelay(_restarts);
      _restarts += 1;
      _setState(SupervisorState.restarting);
      _restartTimer = Timer(delay, () {
        if (_stopping || _disposed) return;
        // `start` re-arms the exit watcher; a repeated early exit surfaces
        // through the next cycle instead of an unhandled future.
        start().then((_) {}, onError: (_) {});
      });
    });
  }

  void _setState(SupervisorState next) {
    if (_state == next || _stateController.isClosed) return;
    _state = next;
    _stateController.add(next);
  }

  void _throwIfDisposed() {
    if (_disposed) throw StateError('Supervisor is disposed');
  }
}

/// Restart delay for attempt [n] (0-based): 1s, 2s, 4s… capped at 30s.
Duration supervisorBackoff(int n) {
  var delay = Duration(seconds: 1) * (1 << n.clamp(0, 5));
  const cap = Duration(seconds: 30);
  if (delay > cap) delay = cap;
  return delay;
}

Duration _backoffDelay(int n) => supervisorBackoff(n);
