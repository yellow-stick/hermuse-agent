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
  if (!host.canonicalService)
    bridgeHostProvider.overrideWithValue(host.bridgeHost),
  // A service is never spawned or stopped by the desktop connection.
  transportFactoryProvider.overrideWith(
    (ref) => (instance) async {
      var target = instance;
      if (instance.id == localInstanceId) {
        final booted =
            await host.boot(await ref.read(registryProvider.future)) ??
            (throw const HermesUnreachable(
              'Hermes is no longer installed on this computer',
            ));
        // Boot returns the registered instance; keep the agent profile this
        // connection was opened for.
        target = booted.copyWith(profile: () => instance.profile);
      }
      return DashboardTransport.connect(
        instance: target,
        secrets: ref.read(secretStoreProvider),
        httpClient: ref.read(httpClientProvider),
      );
    },
  ),
];

/// Connects to the canonical Linux service without supervising its lifetime.
///
/// On macOS and Windows, detects and supervises the desktop-owned backend
/// and model bridge. Those subprocesses alone are stopped on app exit.
final class LocalHermesHost {
  LocalHermesHost._({
    required this.detector,
    required this.secrets,
    this.installJournalPath,
    this.canonicalService = false,
    HermesSupervisor? injected,
  }) : _supervisor = injected {
    bridgeHost = SupervisorBridgeHost(
      secrets: secrets,
      hermesHome: detector.hermesHome,
    );
  }

  /// Uses the canonical service on Linux and desktop supervision elsewhere.
  /// [installJournalPath] journals the non-Linux desktop installation.
  factory LocalHermesHost.system(
    SecretStore secrets, {
    String? installJournalPath,
  }) => LocalHermesHost._(
    detector: HermesDetector.system(installJournalPath: installJournalPath),
    secrets: secrets,
    installJournalPath: installJournalPath,
    canonicalService: Platform.isLinux,
  );

  @visibleForTesting
  factory LocalHermesHost.test({
    required HermesDetector detector,
    required SecretStore secrets,
    HermesSupervisor? supervisor,
    bool canonicalService = false,
  }) => LocalHermesHost._(
    detector: detector,
    secrets: secrets,
    injected: supervisor,
    canonicalService: canonicalService,
  );

  final HermesDetector detector;
  final SecretStore secrets;
  final bool canonicalService;

  /// The [InstallJournal] of the install Hermuse makes on this computer, or
  /// null when installs are not journaled here.
  final String? installJournalPath;

  /// Subscription bridge (CLIProxyAPI sidecar), started lazily on first use.
  late final SupervisorBridgeHost bridgeHost;

  HermesSupervisor? _supervisor;
  DetectedHermes? _detected;
  Future<void>? _mutation;
  bool _uninstalling = false;

  /// The supervised backend (null until [boot] finds an install).
  HermesSupervisor? get supervisor => _supervisor;

  /// Hermes home of this computer's install.
  String get hermesHome =>
      canonicalService ? '/home/hermes/.hermes' : detector.hermesHome;

  /// Detects an install, starts the owned backend and registers the
  /// `hermuse-local` instance. Null when no Hermes is installed (the
  /// install flow then runs the official installer).
  ///
  /// Idempotent: later calls return the registered instance without
  /// restarting the backend.
  Future<HermesInstance?> boot(HermesRegistry registry) async {
    if (_uninstalling) {
      throw const HermesUnreachable('The local installation is being removed.');
    }
    if (canonicalService) {
      final instance = registry.byId(localInstanceId);
      if (instance?.kind != InstanceKind.system) return null;
      if (await _serviceCredential(instance!) == null) {
        throw const HermesUnreachable(
          'Reconnect this computer through setup to authorize service access.',
        );
      }
      return instance;
    }
    if (_detected != null && _supervisor != null) {
      return registry.byId(localInstanceId);
    }
    final found = await detector.detect();
    if (found == null) return null;
    return adopt(registry, found);
  }

  /// Whether the registered system service has lost its desktop credential
  /// (keyring reset, item deleted): setup must sign in or authorize again
  /// before [boot] can connect.
  Future<bool> serviceAccessMissing(HermesRegistry registry) async {
    final instance = registry.byId(localInstanceId);
    if (!canonicalService || instance?.kind != InstanceKind.system) {
      return false;
    }
    if (instance!.auth == AuthMethod.nativeOAuth) return true;
    return await _serviceCredential(instance) == null;
  }

  Future<String?> _serviceCredential(HermesInstance instance) async {
    final key = switch (instance.auth) {
      AuthMethod.loopbackToken => SecretKeys.sessionToken,
      AuthMethod.password => SecretKeys.password,
      AuthMethod.nativeOAuth => throw const HermesUnreachable(
        'Reconnect this computer with a supported dashboard login.',
      ),
    };
    final credential = await secrets.read(localInstanceId, key);
    return credential == null || credential.isEmpty ? null : credential;
  }

  /// Persists the helper's verified loopback handoff, never its token on disk.
  Future<HermesInstance> registerService(
    HermesRegistry registry,
    RemoteInstallOutcome outcome,
  ) async {
    final token = outcome.sessionToken;
    if (!canonicalService ||
        token == null ||
        token.isEmpty ||
        outcome.baseUrl.toString() != 'http://127.0.0.1:9119') {
      throw StateError('The service did not return a valid loopback handoff.');
    }
    final existing = registry.byId(localInstanceId);
    if (existing != null && existing.kind == InstanceKind.remote) {
      throw StateError('The local registration belongs to a remote instance.');
    }
    final instance = HermesInstance(
      id: localInstanceId,
      label: existing?.label ?? 'This computer',
      kind: InstanceKind.system,
      baseUrl: Uri.parse(outcome.baseUrl),
      auth: AuthMethod.loopbackToken,
      profile: existing?.profile,
    );
    await secrets.write(localInstanceId, SecretKeys.sessionToken, token);
    if (existing == null) {
      await registry.add(instance);
    } else {
      await registry.update(instance);
    }
    return instance;
  }

  /// Supervises [hermes] (as [detector] found it) and registers the
  /// `hermuse-local` instance on its backend.
  ///
  /// An incompatible install is refused and left untouched. Canonical Linux
  /// mode never adopts or starts a per-user backend.
  Future<HermesInstance> adopt(
    HermesRegistry registry,
    DetectedHermes hermes,
  ) => _tracked(() => _adopt(registry, hermes));

  Future<HermesInstance> _adopt(
    HermesRegistry registry,
    DetectedHermes hermes,
  ) async {
    if (canonicalService) {
      throw StateError(
        'Linux uses the canonical service; legacy adoption is disabled.',
      );
    }
    if (!hermes.compatible) {
      throw HermesUnreachable(incompatibleHermesMessage(hermes));
    }
    final running = _supervisor;
    if (running != null &&
        _detected != null &&
        _detected!.executable != hermes.executable) {
      await running.dispose();
      _supervisor = null;
    }
    _detected = hermes;
    final supervisor = _supervisor ??= HermesSupervisor(hermes: hermes);
    await supervisor.ensureStarted();
    return supervisor.registerLocal(registry, secrets);
  }

  /// Copies the plugin bundled in the app assets into this Hermes, enables
  /// it, and restarts the owned backend so it mounts the plugin routes (the
  /// local instance is re-registered on its new port). Requires a booted
  /// host; callers reopen the local connection afterwards. Linux service
  /// updates go through the canonical provisioning helper instead.
  Future<HermusePluginInstall> installPlugin(
    HermesRegistry registry, {
    AssetBundle? bundle,
  }) => _tracked(() => _installPlugin(registry, bundle: bundle));

  Future<HermusePluginInstall> _installPlugin(
    HermesRegistry registry, {
    AssetBundle? bundle,
  }) async {
    if (canonicalService) {
      throw StateError('Update the canonical service through computer setup.');
    }
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
          .installFor(detected);
      await supervisor.stop();
      await supervisor.ensureStarted();
      await supervisor.registerLocal(registry, secrets);
      return result;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  /// Serializes host mutations so removal waits for every in-flight write.
  Future<T> _tracked<T>(Future<T> Function() body) {
    if (_uninstalling) {
      return Future.error(
        StateError('The local installation is being removed.'),
      );
    }
    final preceding = _mutation;
    final finished = Completer<void>();
    _mutation = finished.future;
    return () async {
      try {
        await preceding;
        if (_uninstalling) {
          throw StateError('The local installation is being removed.');
        }
        return await body();
      } finally {
        finished.complete();
        if (identical(_mutation, finished.future)) _mutation = null;
      }
    }();
  }

  /// Quiesces only this host; reconnects cannot recreate files during removal.
  Future<void> prepareForUninstall() async {
    _uninstalling = true;
    await _mutation;
    await bridgeHost.suspend();
    await _supervisor?.dispose();
    _supervisor = null;
    _detected = null;
  }

  /// Allows this target to be installed or connected again after the page closes.
  void finishUninstall() {
    _uninstalling = false;
    bridgeHost.resume();
  }

  /// Stops the owned backend and the sidecar (if started). Never touches
  /// user-started processes.
  Future<void> shutdown() async {
    if (canonicalService) return;
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
