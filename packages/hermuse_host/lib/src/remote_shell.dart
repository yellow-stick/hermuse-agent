import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'errors.dart';
import 'remote_ssh_auth.dart';

/// The server identity presented before SSH authentication.
final class RemoteHostKey {
  const RemoteHostKey({
    required this.host,
    required this.port,
    required this.type,
    required this.fingerprint,
  });

  final String host;
  final int port;
  final String type;

  /// OpenSSH's SHA256 fingerprint, including its `SHA256:` prefix.
  final String fingerprint;
}

/// In-memory TOFU trust, retained across fresh logins and retries.
final class RemoteHostKeyTrust {
  final _accepted = <(String, int), RemoteHostKey>{};

  Future<bool> verify(
    RemoteHostKey key,
    Future<bool> Function(RemoteHostKey) confirm,
  ) async {
    final address = (key.host, key.port);
    final known = _accepted[address];
    if (known != null) {
      if (known.type != key.type || known.fingerprint != key.fingerprint) {
        throw RemoteHostKeyChanged(
          'SSH host key changed for ${key.host}:${key.port}. '
          'Expected ${known.fingerprint}, received ${key.fingerprint}. '
          'Verify the server identity outside Hermuse before trying again.',
        );
      }
      return true;
    }
    if (!await confirm(key)) throw const RemoteHostKeyRejected();
    _accepted[address] = key;
    return true;
  }
}

/// Cancels a single attempt, including pending host-key confirmation.
final class RemoteCancellation {
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>[];

  bool get isCancelled => _cancelled.isCompleted;

  void check() {
    if (isCancelled) throw const RemoteInstallCancelled();
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  Future<T> bind<T>(Future<T> operation) {
    check();
    return Future.any([
      operation,
      _cancelled.future.then<T>((_) => throw const RemoteInstallCancelled()),
    ]);
  }
}

/// One completed remote command; a missing SSH exit status is never success.
final class RemoteResult {
  const RemoteResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
}

/// Transport boundary shared by SSH and the trusted root-side local helper.
abstract interface class RemoteShell {
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  });

  /// Writes a file whose parent already exists, without local disk staging.
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384});

  void close();
}

/// Separates the long-lived admission holder from serialized local commands.
///
/// Only the provisioner supplies this command, within the trusted helper.
/// Desktop IPC must never expose it. Closing the shell stops the holder only
/// after active provisioning commands finish, without killing package managers.
abstract interface class RemoteOperationHolderShell implements RemoteShell {
  Future<RemoteResult> holdOperation(
    String command, {
    required Duration timeout,
    required void Function(String line) onLine,
  });
}

typedef RemoteConnector = Future<RemoteShell> Function({
  required String host,
  required int port,
  required String username,
  required String password,
  required Future<bool> Function(RemoteHostKey) verifyHostKey,
  required RemoteCancellation cancellation,
});

/// Password or existing-key dartssh2 transport, with mandatory host verification.
final class SshRemoteShell implements RemoteShell {
  SshRemoteShell._(this._client, this._cancellation) {
    _cancellation.addListener(close);
  }

  final SSHClient _client;
  final RemoteCancellation _cancellation;
  final _sessions = <SSHSession>{};
  SftpClient? _sftp;
  bool _closed = false;

  static Future<RemoteShell> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required Future<bool> Function(RemoteHostKey) verifyHostKey,
    required RemoteCancellation cancellation,
  }) async {
    const deadline = Duration(seconds: 20);
    Socket? socket;
    SSHClient? client;
    ConnectionTask<Socket>? task;
    Timer? handshakeTimer;
    RemoteSshAuthentication? authentication;
    Object? verificationFailure;
    var timedOut = false;
    var verified = false;
    var aborted = false;
    void abort() {
      aborted = true;
      task?.cancel();
      socket?.destroy();
      if (client case final value?) unawaited(value.close());
    }

    cancellation.addListener(abort);
    try {
      cancellation.check();
      authentication = await RemoteSshAuthentication.load(
        password: password,
        cancellation: cancellation,
        checkTrusted: () {
          if (!verified) throw const RemoteHostKeyRejected();
        },
      );
      // startConnect exposes cancellation of a still-pending TCP connect.
      final starting = Socket.startConnect(host, port).then((value) {
        task = value;
        if (aborted || cancellation.isCancelled) {
          unawaited(
            value.socket.then<void>(
              (socket) => socket.destroy(),
              onError: (Object _) {},
            ),
          );
          value.cancel();
        }
        return value;
      });
      await cancellation.bind(starting.timeout(deadline));
      socket = await cancellation.bind(
        task!.socket
            .then((value) {
              if (aborted || cancellation.isCancelled) value.destroy();
              return value;
            })
            .timeout(deadline),
      );
      cancellation.check();
      handshakeTimer = Timer(deadline, () {
        timedOut = true;
        abort();
      });
      client = SSHClient(
        _SshSocket(socket!),
        username: username,
        authTimeout: deadline,
        identities: authentication.identities,
        onPasswordRequest: authentication.onPasswordRequest,
        onVerifyHostKey: (type, fingerprint) async {
          // Human confirmation is not charged against a network timeout.
          handshakeTimer?.cancel();
          try {
            verified = await cancellation.bind(
              verifyHostKey(
                RemoteHostKey(
                  host: host,
                  port: port,
                  type: type,
                  fingerprint: utf8.decode(fingerprint),
                ),
              ),
            );
            if (!verified) verificationFailure = const RemoteHostKeyRejected();
            if (verified) {
              authentication!.checkUsable();
              handshakeTimer = Timer(deadline, () {
                timedOut = true;
                abort();
              });
            }
            return verified && !cancellation.isCancelled;
          } catch (error) {
            verificationFailure = error;
            return false;
          }
        },
      );
      await cancellation.bind(client.authenticated);
      handshakeTimer?.cancel();
      cancellation.check();
      return SshRemoteShell._(client, cancellation);
    } catch (error) {
      abort();
      cancellation.check();
      if (verificationFailure case final failure?) throw failure;
      if (error is SSHAuthFailError) {
        throw password.isEmpty
            ? const RemoteAuthFailed.key()
            : const RemoteAuthFailed();
      }
      if (error case SSHAuthAbortError(
        reason: SSHInternalError(error: final HostException failure),
      )) {
        throw failure;
      }
      if (timedOut || error is TimeoutException) {
        throw RemoteUnreachable(
          'SSH at $host:$port did not answer within 20 seconds.',
        );
      }
      if (error is HostException) rethrow;
      // Do not echo transport errors that may include authentication data.
      throw RemoteUnreachable(
        'Could not establish SSH at $host:$port. Check the address, port, '
        'network and SSH authentication settings.',
      );
    } finally {
      handshakeTimer?.cancel();
      authentication?.close();
      cancellation.removeListener(abort);
    }
  }

  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  }) async {
    _cancellation.check();
    final session = await _cancellation.bind(
      _client.execute(command).timeout(timeout),
    );
    _sessions.add(session);
    final stdout = _OutputTail();
    final stderr = _OutputTail();
    Future<void> collect(Stream<Uint8List> stream, _OutputTail buffer) => stream
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          buffer.add(line);
          onLine?.call(line);
        });
    try {
      final output = Future.wait([
        collect(session.stdout, stdout),
        collect(session.stderr, stderr),
      ]);
      if (stdin != null) {
        session.stdin.add(Uint8List.fromList(utf8.encode(stdin)));
      }
      unawaited(session.stdin.close());
      await _cancellation.bind(
        Future.wait([session.done, output]).timeout(timeout),
      );
      return RemoteResult(
        stdout: stdout.text,
        stderr: stderr.text,
        exitCode: session.exitCode ?? -1,
      );
    } on TimeoutException {
      session.kill(SSHSignal.TERM);
      rethrow;
    } finally {
      _sessions.remove(session);
      session.close();
    }
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) async {
    _cancellation.check();
    const timeout = Duration(minutes: 1);
    final SftpClient sftp =
        _sftp ??
        await _cancellation.bind<SftpClient>(_client.sftp().timeout(timeout));
    _sftp = sftp;
    final file = await _cancellation.bind(
      sftp
          .open(
            path,
            mode:
                SftpFileOpenMode.write |
                SftpFileOpenMode.create |
                SftpFileOpenMode.truncate,
          )
          .timeout(timeout),
    );
    try {
      await _cancellation.bind(
        file
            .setStat(SftpFileAttrs(mode: SftpFileMode.value(mode)))
            .timeout(timeout),
      );
      await _cancellation.bind(
        file.writeBytes(bytes).timeout(const Duration(minutes: 5)),
      );
    } finally {
      if (!_closed) await file.close().timeout(timeout);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _cancellation.removeListener(close);
    for (final session in _sessions) {
      session.kill(SSHSignal.TERM);
      session.close();
    }
    unawaited(_client.close());
    _client.socket.destroy();
  }
}

final class _OutputTail {
  static const _limit = 256 * 1024;
  final _lines = ListQueue<String>();
  int _length = 0;
  void add(String line) {
    final kept = line.length > _limit
        ? line.substring(line.length - _limit)
        : line;
    _lines.add(kept);
    _length += kept.length + 1;
    while (_length > _limit && _lines.length > 1) {
      _length -= _lines.removeFirst().length + 1;
    }
  }

  String get text => _lines.join('\n');
}

final class _SshSocket implements SSHSocket {
  _SshSocket(this.socket);
  final Socket socket;
  @override
  Stream<Uint8List> get stream => socket;
  @override
  StreamSink<List<int>> get sink => socket;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> close() async {
    await socket.close();
  }

  @override
  void destroy() => socket.destroy();
  @override
  Future<void> flush() => socket.flush();
}
