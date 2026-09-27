import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';

/// The desktop host, or null on phones (overridden in `main()`).
final localHostProvider = Provider<LocalHermesHost?>((_) => null);

/// Provider overrides wiring [host] into the app (desktop `main()` and the
/// desktop integration test).
List<Override> localHostOverrides(LocalHermesHost host) => [
  localHostProvider.overrideWithValue(host),
  bridgeHostProvider.overrideWithValue(host.bridgeHost),
  // The local backend listens on a fresh port each launch: boot (or reuse)
  // it before connecting, then connect to its current URL.
  transportFactoryProvider.overrideWith(
    (ref) => (instance) async {
      var target = instance;
      if (instance.id == localInstanceId) {
        target =
            await host.boot(await ref.read(registryProvider.future)) ??
            (throw const HermesUnreachable(
              'Hermes is no longer installed on this computer',
            ));
      }
      return DashboardTransport.connect(
        instance: target,
        secrets: ref.read(secretStoreProvider),
        httpClient: ref.read(httpClientProvider),
      );
    },
  ),
];

/// Owns the Hermuse-supervised local Hermes backend on desktop.
///
/// Created once in `main()` (desktop only) and shut down on app exit:
/// - [boot]: detect → supervise → `registerLocal`.
/// - [bridgeHost]: the CLIProxyAPI sidecar behind the subscription cards.
/// - [installPlugin]: installs the bundled Hermuse plugin on this Hermes.
///
/// It never stops a Hermes it did not spawn.
final class LocalHermesHost {
  LocalHermesHost._({
    required this.detector,
    required this.secrets,
    HermesSupervisor? injected,
  }) : _supervisor = injected,
       bridgeHost = SupervisorBridgeHost(
         secrets: secrets,
         hermesHome: detector.hermesHome,
       );

  /// Production host against the real platform (detect on PATH/filesystem).
  factory LocalHermesHost.system(SecretStore secrets) =>
      LocalHermesHost._(detector: HermesDetector.system(), secrets: secrets);

  @visibleForTesting
  factory LocalHermesHost.test({
    required HermesDetector detector,
    required SecretStore secrets,
    HermesSupervisor? supervisor,
  }) => LocalHermesHost._(
    detector: detector,
    secrets: secrets,
    injected: supervisor,
  );

  final HermesDetector detector;
  final SecretStore secrets;

  /// Subscription bridge (CLIProxyAPI sidecar), started lazily on first use.
  final SupervisorBridgeHost bridgeHost;

  HermesSupervisor? _supervisor;
  DetectedHermes? _detected;

  /// The supervised backend (null until [boot] finds an install).
  HermesSupervisor? get supervisor => _supervisor;

  /// Hermes home of this computer's install.
  String get hermesHome => detector.hermesHome;

  /// Detects an install, starts the owned backend and registers the
  /// `hermuse-local` instance. Null when no Hermes is installed (the
  /// install flow then runs the official installer).
  ///
  /// Idempotent: later calls return the registered instance without
  /// restarting the backend.
  Future<HermesInstance?> boot(HermesRegistry registry) async {
    if (_detected != null && _supervisor != null) {
      return registry.byId(localInstanceId);
    }
    final found = await detector.detect();
    if (found == null) return null;
    _detected = found;
    _supervisor ??= HermesSupervisor(hermes: found);
    await _supervisor!.ensureStarted();
    return _supervisor!.registerLocal(registry, secrets);
  }

  /// Copies the plugin bundled in the app assets into this Hermes, enables
  /// it, and restarts the owned backend so it mounts the plugin routes (the
  /// local instance is re-registered on its new port). Requires a booted
  /// host; callers reopen the local connection afterwards.
  Future<HermusePluginInstall> installPlugin(
    HermesRegistry registry, {
    AssetBundle? bundle,
  }) async {
    final detected = _detected;
    final supervisor = _supervisor;
    if (detected == null || supervisor == null) {
      throw StateError('the local Hermes is not running');
    }
    final assets = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(assets);
    final staging = await Directory.systemTemp.createTemp('hermuse-plugin');
    try {
      for (final key in manifest.listAssets()) {
        if (!key.startsWith(pluginAssetPrefix)) continue;
        final file = File(
          '${staging.path}/${key.substring(pluginAssetPrefix.length)}',
        );
        await file.parent.create(recursive: true);
        final data = await assets.load(key);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
      final result = await HermusePluginInstaller(pluginSourceDir: staging.path)
          .install(
            hermesHome: detected.home,
            hermesExecutable: detected.executable,
          );
      await supervisor.stop();
      await supervisor.ensureStarted();
      await supervisor.registerLocal(registry, secrets);
      return result;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  /// Stops the owned backend and the sidecar (if started). Never touches
  /// user-started processes.
  Future<void> shutdown() async {
    await bridgeHost.supervisor.stop();
    await _supervisor?.stop();
  }
}

/// Asset folder holding the bundled plugin (see `tool/sync_plugin_assets.dart`).
const pluginAssetPrefix = 'assets/hermes-plugin/hermuse/';

/// Builds the staged installer for [hermesHome] (desktop install flow), using
/// the official release script like Hermes Desktop.
HermesInstaller makeInstaller(String hermesHome) => HermesInstaller(
  hermesHome: hermesHome,
  installDir: '$hermesHome${Platform.pathSeparator}hermes-agent',
  source: InstallerSource(isWindows: Platform.isWindows),
);
