import 'dart:async';
import 'dart:convert';

import 'errors.dart';
import 'installer.dart';
import 'remote_scripts.dart';
import 'remote_shell.dart';
import 'remote_uninstall_scripts.dart';

/// Ordered remote removal steps, including the final read-back inventory.
enum RemoteUninstallStep {
  connect,
  inspect,
  services,
  runtime,
  network,
  purge,
  verify,
}

sealed class RemoteUninstallProgress {
  const RemoteUninstallProgress();
}

final class RemoteUninstallStepStarted extends RemoteUninstallProgress {
  const RemoteUninstallStepStarted(this.step);
  final RemoteUninstallStep step;
}

final class RemoteUninstallStepFinished extends RemoteUninstallProgress {
  const RemoteUninstallStepFinished(this.step);
  final RemoteUninstallStep step;
}

final class RemoteUninstallLog extends RemoteUninstallProgress {
  const RemoteUninstallLog(this.line);
  final String line;
}

final class RemoteUninstallCompleted extends RemoteUninstallProgress {
  const RemoteUninstallCompleted(this.outcome);
  final RemoteUninstallOutcome outcome;
}

/// One resource discovered without loading or executing installed plugin code.
final class RemoteUninstallResource {
  const RemoteUninstallResource({
    required this.id,
    required this.label,
    required this.kind,
    required this.removable,
    required this.purgeOnly,
    required this.reason,
    this.managed = true,
  });

  final String id;
  final String label;

  /// A human-readable category: service, runtime, jobs, network, data, account,
  /// cache, container, volume, image, package or ownership.
  final String kind;
  final bool removable;
  final bool purgeOnly;
  final String reason;

  /// False for shared dependencies and foreign resources that are never removed.
  final bool managed;

  bool removedBy({required bool purge}) => removable && (purge || !purgeOnly);

  factory RemoteUninstallResource.fromJson(Map<String, Object?> value) =>
      RemoteUninstallResource(
        id: value['id'] as String,
        label: value['label'] as String,
        kind: value['kind'] as String,
        removable: value['removable'] as bool,
        purgeOnly: value['purgeOnly'] as bool,
        reason: value['reason'] as String,
        managed: value['managed'] as bool,
      );
}

/// A connection-bound preview that must be explicitly confirmed before removal.
final class RemoteUninstallInventory {
  const RemoteUninstallInventory({
    required this.resources,
    required this.revision,
    this.transactionActive = false,
    this.host = '',
    this.port = 22,
    this.username = 'root',
  });

  final List<RemoteUninstallResource> resources;
  final String revision;
  final bool transactionActive;
  final String host;
  final int port;
  final String username;
}

/// The observed removal result; preservation is never reported as removal.
final class RemoteUninstallOutcome {
  const RemoteUninstallOutcome({
    required this.purged,
    required this.removed,
    required this.preserved,
    required this.warnings,
    required this.complete,
  });

  final bool purged;
  final List<String> removed;
  final List<RemoteUninstallResource> preserved;
  final List<String> warnings;

  /// False when a managed runtime/network resource cannot safely be reverted.
  /// Intentional keep-data retention and preserved shared packages are complete.
  final bool complete;
}

/// Inspects and removes only verifiably installer-owned server resources.
///
/// SSH operations use host-key verification and reconnect after inspection.
/// Local operations use a root shell inside the trusted helper. Both execute
/// identical ownership recipes and refuse changed inventory or active setup.
/// Credentials never enter the ownership journal or a remote command.
class RemoteUninstaller {
  RemoteUninstaller({RemoteConnector? connect})
    : _connect = connect ?? SshRemoteShell.connect;

  final RemoteConnector _connect;
  final _trust = RemoteHostKeyTrust();
  RemoteCancellation? _active;
  Completer<void>? _stopped;

  RemoteCancellation _begin() {
    if (_active != null) {
      throw StateError('A remote inspection or uninstall is already running.');
    }
    _stopped = Completer<void>();
    return _active = RemoteCancellation();
  }

  void _finish() {
    _active = null;
    _stopped?.complete();
  }

  /// Returns removable and preserved resources without changing remote files.
  Future<RemoteUninstallInventory> inspect({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required Future<bool> Function(RemoteHostKey) onHostKey,
  }) => _inspect(
    host: host,
    port: port,
    username: username,
    password: password,
    onHostKey: onHostKey,
  );

  /// Inspects through a root shell owned by the trusted local helper.
  Future<RemoteUninstallInventory> inspectLocal({required RemoteShell shell}) =>
      _inspect(
        host: 'localhost',
        port: 22,
        username: 'root',
        password: '',
        onHostKey: (_) async => false,
        localShell: shell,
      );

  Future<RemoteUninstallInventory> _inspect({
    required String host,
    required int port,
    required String username,
    required String password,
    required Future<bool> Function(RemoteHostKey) onHostKey,
    RemoteShell? localShell,
  }) async {
    final cancellation = _begin();
    final attempt = _UninstallAttempt(
      uninstaller: this,
      host: host,
      port: port,
      username: username,
      password: password,
      onHostKey: onHostKey,
      localShell: localShell,
      cancellation: cancellation,
      emit: (_) {},
    );
    try {
      await attempt.connect();
      final result = await attempt.execute(remoteUninstallInventoryScript);
      return attempt.inventory(
        _frame(result.stdout, 'HERMUSE_UNINSTALL_INVENTORY_V1:'),
      );
    } finally {
      attempt.close();
      _finish();
    }
  }

  /// Removes confirmed resources, optionally purging owned data/config/caches.
  Stream<RemoteUninstallProgress> run({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required RemoteUninstallInventory inventory,
    bool purge = false,
    required Future<bool> Function(RemoteHostKey) onHostKey,
  }) => _run(
    host: host,
    port: port,
    username: username,
    password: password,
    inventory: inventory,
    purge: purge,
    onHostKey: onHostKey,
  );

  /// Removes a confirmed canonical inventory through the same owned recipes.
  Stream<RemoteUninstallProgress> runLocal({
    required RemoteShell shell,
    required RemoteUninstallInventory inventory,
    bool purge = false,
  }) => _run(
    host: 'localhost',
    port: 22,
    username: 'root',
    password: '',
    inventory: inventory,
    purge: purge,
    onHostKey: (_) async => false,
    localShell: shell,
  );

  Stream<RemoteUninstallProgress> _run({
    required String host,
    required int port,
    required String username,
    required String password,
    required RemoteUninstallInventory inventory,
    required bool purge,
    required Future<bool> Function(RemoteHostKey) onHostKey,
    RemoteShell? localShell,
  }) {
    final cancellation = _begin();
    late final StreamController<RemoteUninstallProgress> events;
    events = StreamController<RemoteUninstallProgress>(
      onListen: () async {
        final attempt = _UninstallAttempt(
          uninstaller: this,
          host: host,
          port: port,
          username: username,
          password: password,
          onHostKey: onHostKey,
          localShell: localShell,
          cancellation: cancellation,
          emit: (event) {
            if (!events.isClosed) events.add(event);
          },
        );
        try {
          if (username == 'hermes') {
            throw const RemoteInstallFailed(
              'connect',
              'Use another administrator account for removal so the current SSH login cannot be deleted.',
            );
          }
          if (inventory.host != host ||
              inventory.port != port ||
              inventory.username != username ||
              inventory.revision.isEmpty) {
            throw const RemoteInstallFailed(
              'inspect',
              'Inspect this SSH connection before confirming removal.',
            );
          }
          if (inventory.transactionActive) {
            throw const RemoteInstallFailed(
              'inspect',
              'A server setup, rollback or uninstall is still running.',
            );
          }
          await attempt.connect();
          final result = await attempt.execute(
            remoteUninstallScript(inventory.revision, purge: purge),
          );
          final value = _frame(result.stdout, 'HERMUSE_UNINSTALL_OUTCOME_V1:');
          final outcome = RemoteUninstallOutcome(
            purged: value['purged'] as bool,
            removed: List<String>.unmodifiable(
              (value['removed'] as List).cast<String>(),
            ),
            preserved: List<RemoteUninstallResource>.unmodifiable(
              (value['preserved'] as List).map(
                (resource) => RemoteUninstallResource.fromJson(
                  Map<String, Object?>.from(resource as Map),
                ),
              ),
            ),
            warnings: List<String>.unmodifiable(
              (value['warnings'] as List).cast<String>(),
            ),
            complete: value['complete'] as bool,
          );
          cancellation.check();
          events.add(RemoteUninstallCompleted(outcome));
        } catch (error, stack) {
          if (!events.isClosed) events.addError(error, stack);
        } finally {
          attempt.close();
          _finish();
          await events.close();
        }
      },
      onCancel: cancellation.cancel,
    );
    return events.stream;
  }

  /// Cancels the active transport and waits until its operation is closed.
  /// Completed deletions remain completed; inspect again before retrying.
  Future<void> cancel() {
    _active?.cancel();
    return _stopped?.future ?? Future<void>.value();
  }
}

final class _UninstallAttempt {
  _UninstallAttempt({
    required this.uninstaller,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.onHostKey,
    required this.cancellation,
    required this.emit,
    this.localShell,
  });

  final RemoteUninstaller uninstaller;
  final String host;
  final int port;
  final String username;
  final String password;
  final Future<bool> Function(RemoteHostKey) onHostKey;
  final RemoteCancellation cancellation;
  final void Function(RemoteUninstallProgress) emit;
  final RemoteShell? localShell;
  RemoteShell? _shell;
  bool _root = false;
  var _step = RemoteUninstallStep.connect;

  String _redact(String value) {
    final text = stripAnsi(value);
    return password.isEmpty ? text : text.replaceAll(password, '[redacted]');
  }

  Future<void> connect() async {
    if (host.isEmpty ||
        host.contains(RegExp(r'[\s/\x00]')) ||
        port < 1 ||
        port > 65535 ||
        username.isEmpty) {
      throw const RemoteInstallFailed(
        'connect',
        'Enter a host, valid SSH port and user name.',
      );
    }
    emit(const RemoteUninstallStepStarted(RemoteUninstallStep.connect));
    _shell =
        localShell ??
        await cancellation.bind(
          uninstaller._connect(
            host: host,
            port: port,
            username: username,
            password: password,
            verifyHostKey: (key) => uninstaller._trust.verify(
              key,
              (key) => cancellation.bind(onHostKey(key)),
            ),
            cancellation: cancellation,
          ),
        );
    final identity = await cancellation.bind(_shell!.run('id -u'));
    if (identity.exitCode != 0) {
      throw const RemoteInstallFailed(
        'connect',
        'Could not determine the SSH account identity.',
      );
    }
    _root = identity.stdout.trim() == '0';
    if (localShell != null && !_root) {
      throw const RemoteInstallFailed(
        'connect',
        'Local removal requires the trusted root helper.',
      );
    }
    if (!_root) {
      final sudo = await cancellation.bind(_shell!.run('sudo -n true'));
      if (sudo.exitCode != 0) {
        throw const RemoteInstallFailed(
          'connect',
          'Log in as root or an administrator with passwordless sudo. '
              'The SSH password is never reused for privilege elevation.',
        );
      }
    }
    cancellation.check();
    emit(const RemoteUninstallStepFinished(RemoteUninstallStep.connect));
  }

  Future<RemoteResult> execute(String script) async {
    cancellation.check();
    final result = await cancellation.bind(
      _shell!.run(
        '${_root ? '' : 'sudo -n '}bash -euo pipefail -c ${shellQuote(script)}',
        timeout: const Duration(minutes: 30, seconds: 15),
        onLine: (line) {
          const prefix = 'HERMUSE_UNINSTALL_STEP_V1:';
          if (line.startsWith(prefix)) {
            final parts = line.substring(prefix.length).split(':');
            if (parts.length == 2) {
              for (final step in RemoteUninstallStep.values) {
                if (step.name != parts[0]) continue;
                _step = step;
                if (parts[1] == 'started') {
                  emit(RemoteUninstallStepStarted(step));
                }
                if (parts[1] == 'finished') {
                  emit(RemoteUninstallStepFinished(step));
                }
              }
            }
          } else if (!line.startsWith('HERMUSE_UNINSTALL_')) {
            emit(RemoteUninstallLog(_redact(line)));
          }
        },
      ),
    );
    cancellation.check();
    if (result.exitCode != 0) {
      final message = _redact('${result.stderr}\n${result.stdout}').trim();
      throw RemoteInstallFailed(
        _step.name,
        'Remote removal stopped (exit ${result.exitCode}). '
        '${message.length > 4000 ? message.substring(message.length - 4000) : message}',
      );
    }
    return result;
  }

  RemoteUninstallInventory inventory(Map<String, Object?> value) =>
      RemoteUninstallInventory(
        resources: List<RemoteUninstallResource>.unmodifiable(
          (value['resources'] as List).map(
            (resource) => RemoteUninstallResource.fromJson(
              Map<String, Object?>.from(resource as Map),
            ),
          ),
        ),
        revision: value['revision'] as String,
        transactionActive: value['transactionActive'] as bool,
        host: host,
        port: port,
        username: username,
      );

  void close() => (_shell ?? localShell)?.close();
}

Map<String, Object?> _frame(String stdout, String prefix) {
  final frames = const LineSplitter()
      .convert(stdout)
      .where((line) => line.startsWith(prefix))
      .toList();
  if (frames.length != 1) {
    throw const RemoteInstallFailed(
      'inspect',
      'The server returned no unambiguous removal inventory/result.',
    );
  }
  try {
    return Map<String, Object?>.from(
      jsonDecode(frames.single.substring(prefix.length)) as Map,
    );
  } on FormatException {
    throw const RemoteInstallFailed(
      'inspect',
      'The server returned an invalid removal result.',
    );
  }
}
