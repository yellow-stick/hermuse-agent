import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteUninstaller', () {
    test(
      'local inspection and removal use the same inventory without SSH',
      () async {
        final server = _Server();
        final uninstaller = RemoteUninstaller(connect: server.connect);
        final inspectionShell = _Shell(server, '');
        final inventory = await uninstaller.inspectLocal(
          shell: inspectionShell,
        );
        expect(inspectionShell.closed, isTrue);
        expect(inventory.host, 'localhost');
        expect(inventory.revision, 'fixture-confirmed-revision');
        final removalShell = _Shell(server, '');
        final events = await uninstaller
            .runLocal(shell: removalShell, inventory: inventory)
            .toList();
        expect(
          events.whereType<RemoteUninstallCompleted>().single.outcome.complete,
          isTrue,
        );
        expect(server.removals, 1);
        expect(server.connections, 0);
        expect(removalShell.closed, isTrue);
      },
    );

    test('local removal rejects a remote inventory before mutation', () async {
      final server = _Server();
      final uninstaller = RemoteUninstaller(connect: server.connect);
      final inventory = await uninstaller.inspect(
        host: 'remote.example',
        onHostKey: (_) async => true,
      );
      await expectLater(
        uninstaller
            .runLocal(shell: _Shell(server, ''), inventory: inventory)
            .toList(),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(server.removals, 0);
    });

    test('should pin inspected server identity before opening destructive reconnect', () async {
      final server = _Server();
      final uninstaller = RemoteUninstaller(connect: server.connect);
      var confirmations = 0;
      final inventory = await uninstaller.inspect(
        host: 'server.example',
        onHostKey: (_) async {
          confirmations++;
          return true;
        },
      );
      expect(server.shells.single.closed, isTrue);
      server.fingerprint = 'SHA256:changed';
      await expectLater(
        uninstaller
            .run(
              host: 'server.example',
              inventory: inventory,
              onHostKey: (_) async => true,
            )
            .toList(),
        throwsA(isA<RemoteHostKeyChanged>()),
      );
      expect(confirmations, 1);
      expect(server.removals, 0);
    });

    test(
      'should reject a preview bound to a different target before connecting',
      () async {
        final server = _Server();
        final uninstaller = RemoteUninstaller(connect: server.connect);
        final inventory = await uninstaller.inspect(
          host: 'first.example',
          onHostKey: (_) async => true,
        );
        await expectLater(
          uninstaller.run(
            host: 'other.example',
            inventory: inventory,
            onHostKey: (_) async => true,
          ),
          emitsError(isA<RemoteInstallFailed>()),
        );
        expect(server.connections, 1);
        expect(server.removals, 0);
      },
    );
    test('should preserve SSH access by requiring an independent administrator login', () async {
      final server = _Server();
      final uninstaller = RemoteUninstaller(connect: server.connect);
      final inventory = await uninstaller.inspect(
        host: 'server.example',
        username: 'hermes',
        onHostKey: (_) async => true,
      );
      for (final purge in [false, true]) {
        await expectLater(
          uninstaller
              .run(
                host: 'server.example',
                username: 'hermes',
                inventory: inventory,
                purge: purge,
                onHostKey: (_) async => true,
              )
              .toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
      }
      expect(server.connections, 1);
      expect(server.removals, 0);
    });

    test(
      'should return active transaction inventory but forbid confirmed removal',
      () async {
        final server = _Server()..transactionActive = true;
        final uninstaller = RemoteUninstaller(connect: server.connect);
        final inventory = await uninstaller.inspect(
          host: 'server.example',
          onHostKey: (_) async => true,
        );
        expect(inventory.transactionActive, isTrue);
        await expectLater(
          uninstaller.run(
            host: 'server.example',
            inventory: inventory,
            onHostKey: (_) async => true,
          ),
          emitsError(isA<RemoteInstallFailed>()),
        );
        expect(server.removals, 0);
      },
    );

    test('should cancel pending host confirmation and close operation without starting removal', () async {
      final server = _Server();
      final uninstaller = RemoteUninstaller(connect: server.connect);
      final entered = Completer<void>();
      final confirmation = Completer<bool>();
      final inspection = uninstaller.inspect(
        host: 'server.example',
        onHostKey: (_) {
          entered.complete();
          return confirmation.future;
        },
      );
      final failed = expectLater(
        inspection,
        throwsA(isA<RemoteInstallCancelled>()),
      );
      await entered.future;
      await uninstaller.cancel();
      await failed;
      expect(server.removals, 0);
      confirmation.complete(true);
      final retry = await uninstaller.inspect(
        host: 'server.example',
        onHostKey: (_) async => true,
      );
      expect(retry.host, 'server.example');
    });

    test(
      'should never emit completion for command failure or absent result frame',
      () async {
        for (final failedCommand in [true, false]) {
          final server = _Server()
            ..failedCommand = failedCommand
            ..omitOutcome = !failedCommand;
          final uninstaller = RemoteUninstaller(connect: server.connect);
          final inventory = await uninstaller.inspect(
            host: 'server.example',
            onHostKey: (_) async => true,
          );
          final events = <RemoteUninstallProgress>[];
          Object? failure;
          final stopped = Completer<void>();
          uninstaller
              .run(
                host: 'server.example',
                inventory: inventory,
                onHostKey: (_) async => true,
              )
              .listen(
                events.add,
                onError: (Object error) => failure = error,
                onDone: stopped.complete,
              );
          await stopped.future;
          expect(failure, isA<RemoteInstallFailed>());
          expect(events.whereType<RemoteUninstallCompleted>(), isEmpty);
          expect(server.shells.every((shell) => shell.closed), isTrue);
        }
      },
    );

    test(
      'should not expose the SSH password in failed command output',
      () async {
        final server = _Server()..failedCommand = true;
        final uninstaller = RemoteUninstaller(connect: server.connect);
        const password = 'secret-login-password';
        final inventory = await uninstaller.inspect(
          host: 'server.example',
          password: password,
          onHostKey: (_) async => true,
        );
        Object? failure;
        final stopped = Completer<void>();
        uninstaller
            .run(
              host: 'server.example',
              password: password,
              inventory: inventory,
              onHostKey: (_) async => true,
            )
            .listen(
              (_) {},
              onError: (Object error) => failure = error,
              onDone: stopped.complete,
            );
        await stopped.future;
        expect(failure.toString(), isNot(contains(password)));
        expect(failure.toString(), contains('[redacted]'));
      },
    );
  });
}

final class _Server {
  final shells = <_Shell>[];
  var fingerprint = 'SHA256:trusted';
  bool transactionActive = false;
  bool failedCommand = false;
  bool omitOutcome = false;
  int connections = 0;
  int removals = 0;

  Future<RemoteShell> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required Future<bool> Function(RemoteHostKey) verifyHostKey,
    required RemoteCancellation cancellation,
  }) async {
    connections++;
    await cancellation.bind(
      verifyHostKey(
        RemoteHostKey(
          host: host,
          port: port,
          type: 'ssh-ed25519',
          fingerprint: fingerprint,
        ),
      ),
    );
    cancellation.check();
    final shell = _Shell(this, password);
    shells.add(shell);
    cancellation.addListener(shell.close);
    return shell;
  }
}

final class _Shell implements RemoteShell {
  _Shell(this.server, this.password);
  final _Server server;
  final String password;
  bool closed = false;

  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String)? onLine,
  }) async {
    if (command == 'id -u') {
      return const RemoteResult(stdout: '0\n', stderr: '', exitCode: 0);
    }
    final removing = command.contains('"mode":"remove"');
    if (!removing) {
      return RemoteResult(
        stdout:
            'HERMUSE_UNINSTALL_INVENTORY_V1:${jsonEncode({'resources': [], 'revision': 'fixture-confirmed-revision', 'transactionActive': server.transactionActive})}\n',
        stderr: '',
        exitCode: 0,
      );
    }
    server.removals++;
    onLine?.call('HERMUSE_UNINSTALL_STEP_V1:services:started');
    if (server.failedCommand) {
      return RemoteResult(
        stdout: '',
        stderr: 'Failed with $password',
        exitCode: 1,
      );
    }
    if (server.omitOutcome) {
      return const RemoteResult(stdout: '', stderr: '', exitCode: 0);
    }
    return RemoteResult(
      stdout:
          'HERMUSE_UNINSTALL_OUTCOME_V1:${jsonEncode({
            'purged': false,
            'removed': ['dashboard'],
            'preserved': [],
            'warnings': [],
            'complete': true,
          })}\n',
      stderr: '',
      exitCode: 0,
    );
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) =>
      throw StateError(
        'Uninstall must never upload runtime or credential files.',
      );

  @override
  void close() => closed = true;
}
