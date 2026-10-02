import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';

import 'plugin_bundle.dart';

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
/// - [boot]: detect → [adopt] (supervise → `registerLocal`).
/// - [bridgeHost]: the CLIProxyAPI sidecar behind the subscription cards.
/// - [installPlugin]: installs the bundled Hermuse plugin on this Hermes.
///
/// It never stops a Hermes it did not spawn.
final class LocalHermesHost {
  LocalHermesHost._({
    required this.detector,
    required this.secrets,
    this.installJournalPath,
    this.setupAssistant = false,
    HermesSupervisor? injected,
  }) : _supervisor = injected,
       bridgeHost = SupervisorBridgeHost(
         secrets: secrets,
         hermesHome: detector.hermesHome,
       );

  /// Production host against the real platform (detect on PATH/filesystem).
  /// [installJournalPath] is where the install Hermuse makes is journaled
  /// (Linux, macOS; an unfinished install is never adopted); [setupAssistant]
  /// is true on Linux.
  factory LocalHermesHost.system(
    SecretStore secrets, {
    String? installJournalPath,
    bool setupAssistant = false,
  }) => LocalHermesHost._(
    detector: HermesDetector.system(installJournalPath: installJournalPath),
    secrets: secrets,
    installJournalPath: installJournalPath,
    setupAssistant: setupAssistant,
  );

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

  /// The [InstallJournal] of the install Hermuse makes on this computer, or
  /// null when installs are not journaled here.
  final String? installJournalPath;

  /// Whether the Linux setup assistant (`host/linux_setup.dart`) prepares
  /// this computer: the backend uses [dockerEndpoint], and the agent's
  /// computer is set up through the backend rather than by the plugin
  /// installer.
  final bool setupAssistant;

  /// The Docker engine the supervised backend uses, as the setup assistant
  /// planned it; null keeps the inherited Docker configuration. A change
  /// applies when [adopt] next runs.
  DockerEndpoint? dockerEndpoint;

  /// Subscription bridge (CLIProxyAPI sidecar), started lazily on first use.
  final SupervisorBridgeHost bridgeHost;

  HermesSupervisor? _supervisor;
  DetectedHermes? _detected;

  /// `DOCKER_HOST` the owned backend was started with (explicit endpoints
  /// only).
  String? _backendDockerHost;

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
    return adopt(registry, found);
  }

  /// Supervises [hermes] (as [detector] found it) and registers the
  /// `hermuse-local` instance on its backend.
  ///
  /// An incompatible install is refused ([HermesUnreachable]) and left as it
  /// is. A backend already running for [hermes] is kept, unless
  /// [dockerEndpoint] now names another engine: it then restarts with it.
  Future<HermesInstance> adopt(
    HermesRegistry registry,
    DetectedHermes hermes,
  ) async {
    if (!hermes.compatible) {
      throw HermesUnreachable(incompatibleHermesMessage(hermes));
    }
    final endpoint = dockerEndpoint;
    final dockerHost = endpoint != null && endpoint.explicit
        ? endpoint.host
        : null;
    final running = _supervisor;
    if (running != null &&
        _detected != null &&
        (_detected!.executable != hermes.executable ||
            _backendDockerHost != dockerHost)) {
      await running.dispose();
      _supervisor = null;
    }
    _detected = hermes;
    final supervisor = _supervisor ??= HermesSupervisor(
      hermes: hermes,
      dockerEndpoint: endpoint,
    );
    _backendDockerHost = dockerHost;
    await supervisor.ensureStarted();
    return supervisor.registerLocal(registry, secrets);
  }

  /// Copies the plugin bundled in the app assets into this Hermes, enables
  /// it, and restarts the owned backend so it mounts the plugin routes (the
  /// local instance is re-registered on its new port). Requires a booted
  /// host; callers reopen the local connection afterwards. With
  /// [setupAssistant] the agent's computer is left to the caller, which sets
  /// it up through the restarted backend.
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
          .installFor(detected, setupComputer: !setupAssistant);
      await supervisor.stop();
      await supervisor.ensureStarted();
      await supervisor.registerLocal(registry, secrets);
      return result;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  /// `hermes hermuse doctor` on the supervised install: the plugin's store
  /// and schedule diagnostics. Throws [ProcessFailed] with its output when
  /// it reports a problem.
  Future<void> pluginDoctor() async {
    final detected = _detected;
    if (detected == null) throw StateError('the local Hermes is not running');
    final result = await Process.run(
      detected.executable,
      const ['hermuse', 'doctor'],
      includeParentEnvironment: false,
      environment: {
        ...hostEnvironment(),
        ...detected.runtimeEnvironment(),
        'HERMES_HOME': detected.home,
      },
    ).timeout(const Duration(minutes: 1));
    if (result.exitCode != 0) {
      throw ProcessFailed(
        'hermes hermuse doctor reported a problem (exit ${result.exitCode})',
        exitCode: result.exitCode,
        outputTail: '${result.stdout}${result.stderr}'.trim(),
      );
    }
  }

  /// Stops the owned backend and the sidecar (if started). Never touches
  /// user-started processes.
  Future<void> shutdown() async {
    await bridgeHost.supervisor.stop();
    await _supervisor?.stop();
  }
}

/// Builds the staged installer for [hermesHome] (desktop install flow), using
/// the official release script like Hermes Desktop. With a [journalPath]
/// the install is the app's own, resumable one.
HermesInstaller makeInstaller(String hermesHome, {String? journalPath}) =>
    HermesInstaller(
      hermesHome: hermesHome,
      installDir: '$hermesHome${Platform.pathSeparator}hermes-agent',
      journalPath: journalPath,
      source: InstallerSource(isWindows: Platform.isWindows),
    );

/// Why [hermes] is not used: its version is outside
/// [supportedHermesVersions]. The install itself is left as it is.
String incompatibleHermesMessage(DetectedHermes hermes) =>
    'Hermes Agent ${hermes.semver ?? '"${hermes.version}"'} at '
    '${hermes.executable} is not supported: Hermuse Agent works with Hermes '
    'Agent $supportedHermesVersions. It is left as it is.';
