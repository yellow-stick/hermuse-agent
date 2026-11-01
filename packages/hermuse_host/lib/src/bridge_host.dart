import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';

import 'cliproxy_supervisor.dart';

/// [BridgeHost] backed by a [CliproxySupervisor]: the desktop app's
/// implementation, overriding `bridgeHostProvider` at startup.
///
/// Constructed with the app's [SecretStore] + Hermes home; [ensureStarted]
/// starts the sidecar lazily and returns whatever keys the supervisor minted
/// (it throws [StateError] only if the supervisor reports success without
/// keys, which cannot happen — [CliproxySupervisor.ensureStarted] resolves
/// both before spawning).
final class SupervisorBridgeHost implements BridgeHost {
  SupervisorBridgeHost({
    required SecretStore secrets,
    required String hermesHome,
    CliproxySupervisor? supervisor,
  }) : _supervisor =
           supervisor ??
           CliproxySupervisor(secrets: secrets, hermesHome: hermesHome);

  final CliproxySupervisor _supervisor;
  Future<BridgeConnection>? _starting;
  bool _suspended = false;

  /// The supervised sidecar (for stop/dispose/log wiring in the app shell).
  CliproxySupervisor get supervisor => _supervisor;

  @override
  Future<BridgeConnection> ensureStarted() {
    if (_suspended) {
      return Future.error(
        StateError('The local installation is being removed.'),
      );
    }
    if (_starting case final starting?) return starting;
    late final Future<BridgeConnection> operation;
    operation = _connect().whenComplete(() {
      if (identical(_starting, operation)) _starting = null;
    });
    _starting = operation;
    return operation;
  }

  /// Prevents new starts and waits for a pending one before stopping it.
  Future<void> suspend() async {
    _suspended = true;
    try {
      await _starting;
    } on Object {
      // The original caller receives the startup failure; this is a barrier.
    }
    await _supervisor.stop();
  }

  /// Allows starts again after the installation removal flow has closed.
  void resume() => _suspended = false;

  Future<BridgeConnection> _connect() async {
    final baseUrl = await _supervisor.ensureStarted();
    final apiKey = _supervisor.apiKey;
    final managementKey = _supervisor.managementKey;
    if (apiKey == null || managementKey == null) {
      throw StateError('sidecar started without keys');
    }
    return BridgeConnection(
      baseUrl: baseUrl,
      apiKey: apiKey,
      managementKey: managementKey,
    );
  }
}
