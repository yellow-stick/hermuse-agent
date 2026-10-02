import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_host/src/remote_ssh_auth.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// RFC 8032's first Ed25519 test vector: a public, deterministic test identity.
final _publicKey = _hex(
  'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
);
final _seed = _hex(
  '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
);
final _key = OpenSSHEd25519KeyPair(
  _publicKey,
  Uint8List.fromList([..._seed, ..._publicKey]),
  'disposable-test-identity',
);
final _emptyMessageSignature = _signature(
  'ssh-ed25519',
  _hex(
    'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
    '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
  ),
);

void main() {
  group('RemoteSshAuthentication', () {
    late Directory home;
    late RemoteCancellation cancellation;
    late bool trusted;
    final authentications = <RemoteSshAuthentication>[];
    _AgentFixture? agent;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('hermuse-ssh-auth-');
      await Directory(p.join(home.path, '.ssh')).create();
      cancellation = RemoteCancellation();
      trusted = false;
    });
    tearDown(() async {
      for (final authentication in authentications) {
        authentication.close();
      }
      authentications.clear();
      await agent?.close();
      agent = null;
      await home.delete(recursive: true);
    });

    Future<void> keyFile(String name, String pem) =>
        File(p.join(home.path, '.ssh', name)).writeAsString(pem);

    Future<RemoteSshAuthentication> load({String password = ''}) async {
      final authentication = await RemoteSshAuthentication.load(
        password: password,
        cancellation: cancellation,
        checkTrusted: () {
          if (!trusted) throw const RemoteHostKeyRejected();
        },
        environment: {
          'HOME': home.path,
          'USERPROFILE': home.path,
          if (agent != null) 'SSH_AUTH_SOCK': agent!.path,
        },
      );
      authentications.add(authentication);
      return authentication;
    }

    test('should use only an entered password after host acceptance without trimming it', () async {
      await keyFile('id_ed25519', _key.toPem());
      final authentication = await load(password: ' p@ss word ');
      expect(authentication.identities, isEmpty);
      expect(
        authentication.onPasswordRequest!,
        throwsA(isA<RemoteHostKeyRejected>()),
      );
      trusted = true;
      expect(await authentication.onPasswordRequest!(), ' p@ss word ');
    });

    test('should sign with a default local key only after host acceptance and never request an empty password', () async {
      await keyFile('id_ed25519', _key.toPem());
      final authentication = await load();
      expect(authentication.onPasswordRequest, isNull);
      final identity = authentication.identities.single;
      expect(
        () => identity.sign(Uint8List(0)),
        throwsA(isA<RemoteHostKeyRejected>()),
      );
      trusted = true;
      expect(
        (await identity.sign(Uint8List(0))).encode(),
        _emptyMessageSignature,
      );
    });

    test('should skip encrypted and malformed keys and use a later usable default file', () async {
      await keyFile(
        'id_ed25519',
        _key.toPem(passphrase: 'test-passphrase', rounds: 1),
      );
      await keyFile('id_ecdsa', 'not a private key');
      await keyFile('id_rsa', _key.toPem());
      final authentication = await load();
      trusted = true;
      expect(
        (await authentication.identities.single.sign(Uint8List(0))).encode(),
        _emptyMessageSignature,
      );
    });

    test('should report that an encrypted local key needs an unlocked agent instead of trying an empty password', () async {
      await keyFile(
        'id_ed25519',
        _key.toPem(passphrase: 'test-passphrase', rounds: 1),
      );
      final authentication = await load();
      expect(authentication.onPasswordRequest, isNull);
      expect(
        authentication.checkUsable,
        throwsA(isA<RemoteSshKeyUnavailable>()),
      );
    });

    group(
      'Unix SSH agent',
      () {
        test('should obtain a real signature through the standard agent protocol only after host acceptance', () async {
          agent = await _AgentFixture.start(p.join(home.path, 'agent.sock'));
          final authentication = await load();
          expect(authentication.onPasswordRequest, isNull);
          final identity = authentication.identities.single;
          await expectLater(
            Future.sync(() => identity.sign(Uint8List(0))),
            throwsA(isA<RemoteHostKeyRejected>()),
          );
          expect(agent!.signRequests, 0);
          trusted = true;
          expect(
            (await identity.sign(Uint8List(0))).encode(),
            _emptyMessageSignature,
          );
          expect(agent!.signRequests, 1);
        });

        test(
          'should surface an agent refusal as a key authentication error',
          () async {
            agent = await _AgentFixture.start(p.join(home.path, 'agent.sock'));
            agent!.rejectSigning = true;
            final authentication = await load();
            trusted = true;
            await expectLater(
              Future.sync(
                () => authentication.identities.single.sign(Uint8List(0)),
              ),
              throwsA(isA<RemoteAuthFailed>()),
            );
          },
        );

        test('should return a key failure without uncaught socket errors when the agent disconnects before signing', () async {
          final uncaught = <Object>[];
          Object? failure;
          await runZonedGuarded(() async {
            agent = await _AgentFixture.start(p.join(home.path, 'agent.sock'));
            final authentication = await load();
            trusted = true;
            await agent!.disconnectClients();
            try {
              await authentication.identities.single.sign(Uint8List(0));
            } on Object catch (error) {
              failure = error;
            } finally {
              authentication.close();
            }
            await pumpEventQueue(times: 5);
          }, (error, stack) => uncaught.add(error));
          expect(failure, isA<RemoteAuthFailed>());
          expect(uncaught, isEmpty);
        });

        test(
          'should cancel a pending agent signature and release the socket',
          () async {
            agent = await _AgentFixture.start(p.join(home.path, 'agent.sock'));
            agent!.signRelease = Completer<void>();
            final authentication = await load();
            trusted = true;
            final signing = Future.sync(
              () => authentication.identities.single.sign(Uint8List(0)),
            );
            final cancelled = expectLater(
              signing,
              throwsA(isA<RemoteInstallCancelled>()),
            );
            await agent!.signRequested.future;
            cancellation.cancel();
            await cancelled;
            agent!.signRelease!.complete();
            await agent!.connectionClosed.future;
          },
        );

        test('should fall back to an unencrypted local key when the agent cannot provide identities', () async {
          agent = await _AgentFixture.start(p.join(home.path, 'agent.sock'));
          agent!.rejectIdentities = true;
          await keyFile('id_ed25519', _key.toPem());
          final authentication = await load();
          trusted = true;
          expect(
            (await authentication.identities.single.sign(Uint8List(0)))
                .encode(),
            _emptyMessageSignature,
          );
          expect(agent!.signRequests, 0);
        });
      },
      skip: Platform.isWindows
          ? 'Unix-domain SSH agents are not supported on Windows.'
          : false,
    );
  });
}

/// A disposable standard-protocol agent, using dartssh2's cryptographic signer.
final class _AgentFixture {
  _AgentFixture(this.path, this._server) {
    _server.listen((socket) {
      // The fixture intentionally resets its peer; observe its own sink errors.
      unawaited(socket.done.then<void>((_) {}, onError: (Object error) {}));
      _sockets.add(socket);
      _serving.add(_serve(socket));
    });
  }

  final String path;
  final ServerSocket _server;
  final _signer = SSHKeyPairAgent([_key]);
  final _sockets = <Socket>[];
  final _serving = <Future<void>>[];
  final signRequested = Completer<void>();
  final connectionClosed = Completer<void>();
  Completer<void>? signRelease;
  int signRequests = 0;
  bool rejectSigning = false;
  bool rejectIdentities = false;

  static Future<_AgentFixture> start(String path) async => _AgentFixture(
    path,
    await ServerSocket.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    ),
  );

  Future<void> _serve(Socket socket) async {
    final bytes = StreamIterator(socket.expand((chunk) => chunk));
    Future<Uint8List> read(int count) async {
      final result = Uint8List(count);
      for (var i = 0; i < count; i++) {
        if (!await bytes.moveNext()) {
          throw const SocketException('Agent closed');
        }
        result[i] = bytes.current;
      }
      return result;
    }

    try {
      while (true) {
        final header = await read(4);
        final request = await read(ByteData.sublistView(header).getUint32(0));
        if (request.first == SSHAgentProtocol.signRequest) {
          signRequests++;
          if (!signRequested.isCompleted) signRequested.complete();
          await signRelease?.future;
        }
        final rejected = request.first == SSHAgentProtocol.requestIdentities
            ? rejectIdentities
            : rejectSigning;
        final response = rejected
            ? Uint8List.fromList([SSHAgentProtocol.failure])
            : await _signer.handleRequest(request);
        final frame = Uint8List.fromList([
          ..._uint32(response.length),
          ...response,
        ]);
        // Fragment both the frame header and body independently of requests.
        socket.add(Uint8List.sublistView(frame, 0, 2));
        await socket.flush();
        await Future<void>.delayed(Duration.zero);
        socket.add(Uint8List.sublistView(frame, 2, 5));
        await socket.flush();
        await Future<void>.delayed(Duration.zero);
        socket.add(Uint8List.sublistView(frame, 5));
        await socket.flush();
      }
    } on SocketException {
      // Closing either endpoint terminates this disposable agent connection.
    } on StateError {
      // A cancelled signature can finish after the client socket has closed.
    } finally {
      await bytes.cancel();
      socket.destroy();
      if (!connectionClosed.isCompleted) connectionClosed.complete();
    }
  }

  Future<void> disconnectClients() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await Future.wait(_serving);
  }

  Future<void> close() async {
    if (signRelease case final release? when !release.isCompleted) {
      release.complete();
    }
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
    await Future.wait(_serving);
  }
}

Uint8List _hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);

Uint8List _uint32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

Uint8List _signature(String type, Uint8List value) {
  final name = utf8.encode(type);
  return Uint8List.fromList([
    ..._uint32(name.length),
    ...name,
    ..._uint32(value.length),
    ...value,
  ]);
}
