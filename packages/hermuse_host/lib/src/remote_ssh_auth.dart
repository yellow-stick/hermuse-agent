import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;

import 'errors.dart';
import 'remote_shell.dart';

/// Authentication for one SSH connection, without forwarding the local agent.
final class RemoteSshAuthentication {
  RemoteSshAuthentication._(
    this.identities,
    this.onPasswordRequest,
    this._agent,
  );

  final List<SSHIdentity> identities;
  final SSHPasswordRequestHandler? onPasswordRequest;
  final _SshAgent? _agent;

  /// Uses an entered password exclusively, or the desktop's existing SSH keys.
  static Future<RemoteSshAuthentication> load({
    required String password,
    required RemoteCancellation cancellation,
    required void Function() checkTrusted,
    Map<String, String>? environment,
  }) async {
    void check() {
      cancellation.check();
      checkTrusted();
    }

    cancellation.check();
    if (password.isNotEmpty) {
      return RemoteSshAuthentication._([], () {
        check();
        return password;
      }, null);
    }

    final variables = environment ?? Platform.environment;
    final identities = <SSHIdentity>[];
    _SshAgent? agent;
    final socketPath = variables['SSH_AUTH_SOCK'];
    if (!Platform.isWindows && socketPath != null && socketPath.isNotEmpty) {
      try {
        agent = await _SshAgent.connect(socketPath, cancellation);
        identities.addAll(await agent.identities(check));
      } on Object {
        // An absent, locked or incompatible agent must not hide local keys.
        cancellation.check();
        agent?.close();
        agent = null;
      }
    }

    try {
      final home = Platform.isWindows
          ? variables['USERPROFILE'] ?? variables['HOME']
          : variables['HOME'];
      if (home != null && home.isNotEmpty) {
        for (final name in ['id_ed25519', 'id_ecdsa', 'id_rsa']) {
          cancellation.check();
          try {
            final pem = await cancellation.bind(
              File(p.join(home, '.ssh', name)).readAsString(),
            );
            // Passphrases belong to the user's existing agent, not this form.
            for (final key in SSHKeyPair.fromPem(pem)) {
              identities.add(
                SSHIdentity.custom(
                  type: key.type,
                  publicKey: key.toPublicKey(),
                  shouldProbe: true,
                  signer: (data) {
                    check();
                    return key.sign(data);
                  },
                ),
              );
            }
          } on FileSystemException {
            // Missing or unreadable default keys are not usable identities.
          } on FormatException {
            // Ignore files that are not supported SSH private keys.
          } on ArgumentError {
            // Malformed key data must not hide a later usable default key.
          } on SSHKeyDecodeError {
            // Includes encrypted keys; those must be unlocked in the SSH agent.
          } on UnsupportedError {
            // Certificates, security-key and other unsupported formats are skipped.
          }
        }
      }
      cancellation.check();
      return RemoteSshAuthentication._(identities, null, agent);
    } on Object {
      agent?.close();
      rethrow;
    }
  }

  /// Refuses a key-only login when no usable local identity was found.
  void checkUsable() {
    if (onPasswordRequest == null && identities.isEmpty) {
      throw const RemoteSshKeyUnavailable();
    }
  }

  void close() => _agent?.close();
}

/// The standard OpenSSH agent protocol over SSH_AUTH_SOCK (Unix sockets only).
final class _SshAgent {
  _SshAgent(this._socket, this._cancellation)
    : _input = StreamIterator(_socket) {
    unawaited(
      _socket.done.then<void>(
        (_) => _recordDisconnect(
          const SocketException('SSH agent connection closed'),
        ),
        onError: _recordDisconnect,
      ),
    );
    _cancellation.addListener(close);
  }

  static const _timeout = Duration(seconds: 5);
  static const _maxFrameSize = 256 * 1024;
  final Socket _socket;
  final RemoteCancellation _cancellation;
  final StreamIterator<Uint8List> _input;
  final _disconnected = Completer<void>();
  Object? _socketFailure;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  bool _closed = false;

  static Future<_SshAgent> connect(
    String path,
    RemoteCancellation cancellation,
  ) async {
    final agent = await cancellation.bind(
      Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: _timeout,
      ).then((socket) => _SshAgent(socket, cancellation)),
    );
    cancellation.check();
    return agent;
  }

  Future<List<SSHIdentity>> identities(void Function() checkTrusted) async {
    final response = _AgentReader(
      await _request(Uint8List.fromList([SSHAgentProtocol.requestIdentities])),
    );
    if (response.byte() != SSHAgentProtocol.identitiesAnswer) {
      throw const FormatException('SSH agent did not return identities');
    }
    final count = response.uint32();
    final result = <SSHIdentity>[];
    for (var i = 0; i < count; i++) {
      final key = response.string();
      final comment = utf8.decode(response.string(), allowMalformed: true);
      final keyType = SSHHostKey.getType(key);
      final type = keyType == 'ssh-rsa' ? 'rsa-sha2-256' : keyType;
      if (keyType != 'ssh-rsa' &&
          keyType != 'ssh-ed25519' &&
          keyType != 'ecdsa-sha2-nistp256' &&
          keyType != 'ecdsa-sha2-nistp384' &&
          keyType != 'ecdsa-sha2-nistp521') {
        continue;
      }
      result.add(
        SSHIdentity.custom(
          type: type,
          publicKey: SSHRawHostKey(key),
          comment: comment,
          shouldProbe: true,
          signer: (data) async {
            checkTrusted();
            final request = BytesBuilder(copy: false)
              ..addByte(SSHAgentProtocol.signRequest)
              ..add(_uint32(key.length))
              ..add(key)
              ..add(_uint32(data.length))
              ..add(data)
              ..add(
                _uint32(
                  keyType == 'ssh-rsa' ? SSHAgentProtocol.rsaSha2_256 : 0,
                ),
              );
            try {
              final reply = _AgentReader(await _request(request.takeBytes()));
              if (reply.byte() != SSHAgentProtocol.signResponse) {
                throw const RemoteAuthFailed.key();
              }
              final signature = reply.string();
              if (SSHSignature.getType(signature) != type) {
                throw const RemoteAuthFailed.key();
              }
              return SSHRawSignature(signature);
            } on Object {
              _cancellation.check();
              // Never echo agent responses or local credential data to the UI.
              throw const RemoteAuthFailed.key();
            }
          },
        ),
      );
    }
    return result;
  }

  Future<Uint8List> _request(Uint8List request) async {
    _cancellation.check();
    if (_socketFailure case final failure?) throw failure;
    _socket
      ..add(_uint32(request.length))
      ..add(request);
    final header = await _receive(4);
    final length = ByteData.sublistView(header).getUint32(0);
    if (length == 0 || length > _maxFrameSize) {
      throw const FormatException('Invalid SSH agent response size');
    }
    return _receive(length);
  }

  void _recordDisconnect(Object failure) {
    if (_disconnected.isCompleted) return;
    _socketFailure = failure;
    // No error completes this signal outside an observed request race.
    _disconnected.complete();
  }

  Future<Uint8List> _receive(int length) => _cancellation.bind(
    Future.any([
      _read(length),
      _disconnected.future.then<Uint8List>((_) => throw _socketFailure!),
    ]).timeout(_timeout),
  );

  Future<Uint8List> _read(int length) async {
    final result = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext()) {
          throw const FormatException('SSH agent closed its socket');
        }
        _chunk = _input.current;
        _offset = 0;
      }
      final available = _chunk.length - _offset;
      final needed = length - written;
      final count = available < needed ? available : needed;
      result.setRange(written, written + count, _chunk, _offset);
      written += count;
      _offset += count;
    }
    return result;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _cancellation.removeListener(close);
    _socket.destroy();
    unawaited(_input.cancel().catchError(_recordDisconnect));
  }
}

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

final class _AgentReader {
  _AgentReader(this.bytes);
  final Uint8List bytes;
  int _offset = 0;

  int byte() {
    if (_offset >= bytes.length) {
      throw const FormatException('Truncated SSH agent response');
    }
    return bytes[_offset++];
  }

  int uint32() {
    if (_offset + 4 > bytes.length) {
      throw const FormatException('Truncated SSH agent response');
    }
    final value = ByteData.sublistView(
      bytes,
      _offset,
      _offset + 4,
    ).getUint32(0);
    _offset += 4;
    return value;
  }

  Uint8List string() {
    final length = uint32();
    if (length > bytes.length - _offset) {
      throw const FormatException('Truncated SSH agent response');
    }
    final result = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }
}
