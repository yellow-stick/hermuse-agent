import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hermes_client/hermes_client.dart';

import 'detector.dart';
import 'errors.dart';
import 'installer.dart' show parseBackendReadyPort;
import 'supervisor.dart';

/// Supervises the Hermuse-owned local backend:
/// `hermes serve --host 127.0.0.1 --port 0 --skip-build`.
///
/// The argv mirrors the Desktop pool spawn (`serveBackendArgs` in
/// `backend-command.ts`): headless, loopback-only, OS-assigned port. The
/// spawn environment carries a fresh `HERMES_DASHBOARD_SESSION_TOKEN`
/// (minted in memory, like the Desktop) plus `HERMES_DESKTOP=1` and
/// `HERMES_PARENT_PID` so the child opts out of the host rendezvous
/// multiplexing (`_attach_to_host_backend` requires the desktop-owned
/// proof: `HERMES_DESKTOP=1` + token env) and self-exits when Hermuse dies
/// uncleanly. Readiness is the `HERMES_BACKEND_READY port=<n>` fd-1
/// announcement. Hermuse stops only this owned child and never touches a
/// user-started `hermes serve`.
final class HermesSupervisor {
  HermesSupervisor({
    required DetectedHermes hermes,
    Supervisor Function()? supervisorFactory,
  }) : _hermes = hermes,
       _supervisorFactory =
           supervisorFactory ??
           (() => Supervisor(
             executable: hermes.executable,
             arguments: const [
               'serve',
               '--host',
               '127.0.0.1',
               '--port',
               '0',
               '--skip-build',
             ],
             environment: {
               'HERMES_DASHBOARD_SESSION_TOKEN': _mintToken(),
               'HERMES_DESKTOP': '1',
               'HERMES_PARENT_PID': '$pid',
             },
             readiness: parseBackendReadyPort,
           ));

  final DetectedHermes _hermes;
  final Supervisor Function() _supervisorFactory;
  Supervisor? _supervisor;

  /// The executable this supervisor spawns.
  String get executable => _hermes.executable;

  /// Detected install metadata.
  DetectedHermes get hermes => _hermes;

  /// Dashboard origin of the running backend; null until [ensureStarted].
  Uri? get baseUrl {
    final port = _supervisor?.readyValue;
    return port == null ? null : Uri.parse('http://127.0.0.1:$port');
  }

  /// The session token minted for the current backend process.
  String? get sessionToken =>
      _supervisor?.environment?['HERMES_DASHBOARD_SESSION_TOKEN'];

  /// Lifecycle of the owned backend.
  SupervisorState get state => _supervisor?.state ?? SupervisorState.stopped;

  Stream<SupervisorState> get stateChanges =>
      _supervisor?.stateChanges ?? const Stream.empty();

  /// Backend stdout/stderr lines.
  Stream<SupervisorLog> get logs => _supervisor?.logs ?? const Stream.empty();

  /// Starts the backend if it is not running; waits for the READY port.
  Future<Uri> ensureStarted() async {
    final supervisor = _supervisor ??= _supervisorFactory();
    await supervisor.ensureStarted();
    final url = baseUrl;
    if (url == null) {
      throw const ProcessFailed('backend started but announced no port');
    }
    return url;
  }

  /// Stops the owned backend. Never touches other processes.
  Future<void> stop() async {
    await _supervisor?.stop();
  }

  /// Releases the supervisor; the backend is stopped first.
  Future<void> dispose() async {
    await _supervisor?.dispose();
    _supervisor = null;
  }

  /// Creates or updates the single `InstanceKind.local` instance for this
  /// backend and stores its session token in [secrets].
  ///
  /// The instance keeps a stable id (`hermuse-local`) so restarts update the
  /// row instead of forking twins (the port changes every spawn). When the
  /// existing local row is unreachable-by-construction (a previous port),
  /// its URL is replaced. The label is `This computer`.
  Future<HermesInstance> registerLocal(
    HermesRegistry registry,
    SecretStore secrets,
  ) async {
    final url = baseUrl;
    final token = sessionToken;
    if (url == null || token == null) {
      throw StateError('backend is not started');
    }
    const id = localInstanceId;
    final existing = registry.byId(id);
    final instance = HermesInstance(
      id: id,
      label: existing?.label ?? 'This computer',
      kind: InstanceKind.local,
      baseUrl: url,
      auth: AuthMethod.loopbackToken,
    );
    if (existing == null) {
      await registry.add(instance);
    } else {
      await registry.update(instance);
    }
    await secrets.write(id, SecretKeys.sessionToken, token);
    return instance;
  }

  /// Runs `hermes update`, streaming output lines to [onLine].
  ///
  /// The backend keeps running: `hermes update` restarts supervised
  /// processes itself. Throws [ProcessFailed] on a non-zero exit.
  Future<void> update({
    void Function(String stream, String line)? onLine,
  }) async {
    final process = await Process.start(_hermes.executable, const ['update']);
    final tail = <String>[];
    void listen(Stream<List<int>> bytes, String stream) {
      bytes.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        tail.add('[$stream] $line');
        if (tail.length > 200) tail.removeRange(0, tail.length - 200);
        onLine?.call(stream, line);
      });
    }

    listen(process.stdout, 'stdout');
    listen(process.stderr, 'stderr');
    final code = await process.exitCode;
    if (code != 0) {
      throw ProcessFailed(
        'hermes update failed (exit $code)',
        exitCode: code,
        outputTail: tail.join('\n'),
      );
    }
  }

  /// 32 random bytes, base64url without padding (43 chars). Generated in
  /// memory per spawn; never logged or written to disk by this class.
  static String _mintToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// Stable registry id of the Hermuse-supervised local backend.
const localInstanceId = 'hermuse-local';
