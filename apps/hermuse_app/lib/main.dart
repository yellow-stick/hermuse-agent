import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:path_provider/path_provider.dart';

import 'platform/local_host.dart';
import 'platform/secure_secret_store.dart';
import 'shell/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = openNativeDatabase(await getApplicationSupportDirectory());
  final secrets = SecureSecretStore();
  Object? keystoreError;
  try {
    // Touch the keystore now: a locked/missing keyring must surface as a
    // blocking error screen, never as a silent plaintext fallback.
    await secrets.read('__probe__', '__probe__');
  } on Object catch (e) {
    keystoreError = e;
  }
  final host = isDesktop ? LocalHermesHost.system(secrets) : null;
  if (host != null) {
    // Stops the backend and sidecar Hermuse started when the app quits (the
    // binding keeps the listener alive).
    AppLifecycleListener(
      onExitRequested: () async {
        await host.shutdown();
        return AppExitResponse.exit;
      },
    );
  }
  runApp(
    ProviderScope(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets),
        if (host != null) ...localHostOverrides(host),
      ],
      child: HermuseApp(keystoreError: keystoreError),
    ),
  );
}

/// True on the desktop targets (install flow target); phones get only Connect.
bool get isDesktop =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;
