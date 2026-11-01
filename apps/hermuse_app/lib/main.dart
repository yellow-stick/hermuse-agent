import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:path_provider/path_provider.dart';

import 'host/linux_setup.dart';
import 'platform/local_host.dart';
import 'platform/secure_secret_store.dart';
import 'shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final db = openNativeDatabase(support);
  final secrets = SecureSecretStore();
  // Linux verifies (and can repair) the keyring in its setup assistant,
  // before anything connects; elsewhere a keystore that fails here blocks
  // the app. Never a silent plaintext fallback.
  final keystoreError = Platform.isLinux ? null : await _probeKeystore(secrets);
  final journalPath =
      '${support.path}${Platform.pathSeparator}'
      'hermes-install.json';
  final host = isDesktop
      ? LocalHermesHost.system(secrets, installJournalPath: journalPath)
      : null;
  final container = ProviderContainer(
    overrides: [
      hermuseDatabaseProvider.overrideWithValue(db),
      secretStoreProvider.overrideWithValue(secrets),
      if (host != null) ...localHostOverrides(host),
      if (host != null && Platform.isLinux)
        linuxSetupServicesProvider.overrideWithValue(
          await LinuxSetupServices.forHost(host),
        ),
    ],
  );
  if (host != null) {
    // Finish or safely stop setup on quit. Linux's canonical system service
    // remains running; other desktops stop only their owned subprocesses.
    AppLifecycleListener(
      onExitRequested: () async {
        if (Platform.isLinux) {
          await container.read(linuxSetupProvider.notifier).stopAndWait();
        }
        await host.shutdown();
        return AppExitResponse.exit;
      },
    );
  }
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: HermuseApp(keystoreError: keystoreError),
    ),
  );
}

/// A real write, read and delete of a probe secret: a locked, missing or
/// refused keystore surfaces as a blocking error screen.
Future<Object?> _probeKeystore(SecureSecretStore secrets) async {
  try {
    await verifySecretStore(secrets);
    return null;
  } on Object catch (e) {
    return e;
  }
}

/// True on the desktop targets (install flow target); phones get only Connect.
bool get isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;
