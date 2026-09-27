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

  /// The supervised sidecar (for stop/dispose/log wiring in the app shell).
  CliproxySupervisor get supervisor => _supervisor;

  @override
  Future<BridgeConnection> ensureStarted() async {
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
