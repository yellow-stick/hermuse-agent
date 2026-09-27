// Live desktop test: adopts the Hermes installed on this computer, supervises
// it, installs the bundled Hermuse plugin and opens Feed/Goals on it.
//
// Run it against a THROWAWAY home, never the user's ~/.hermes:
//   HERMES_HOME=$(mktemp -d) flutter test integration_test/desktop_test.dart -d linux
//
// Skipped unless HERMES_HOME points under the system temp directory.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final home = Platform.environment['HERMES_HOME'] ?? '';
  final throwaway =
      home.isNotEmpty && home.startsWith(Directory.systemTemp.path);

  testWidgets(
    'adopt local Hermes, install the plugin, open Feed and Goals',
    (tester) async {
      final db = openMemoryDatabase();
      final secrets = MemorySecretStore();
      final host = LocalHermesHost.system(secrets);
      addTearDown(() async {
        await host.shutdown();
        await db.close();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermuseDatabaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(secrets),
            ...localHostOverrides(host),
          ],
          child: const HermuseApp(),
        ),
      );

      Future<void> waitFor(Finder finder, {int seconds = 120}) async {
        for (var i = 0; i < seconds * 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pump();
          if (finder.evaluate().isNotEmpty) return;
        }
        fail('timed out waiting for $finder');
      }

      await waitFor(find.text('Install Hermes on this computer'));
      await tester.tap(find.text('Install Hermes on this computer'));
      // Detected install → supervised → registered → chat on it.
      await waitFor(find.bySemanticsLabel('Feed'));
      expect(host.supervisor?.baseUrl, isNotNull);

      await tester.tap(find.bySemanticsLabel('Feed').first);
      await waitFor(find.text('Install the plugin'));
      await tester.tap(find.text('Install the plugin'));
      await waitFor(find.text('YOUR FEED PROMPT'), seconds: 180);
      expect(
        File('$home/plugins/hermuse/plugin.yaml').existsSync(),
        isTrue,
        reason: 'plugin copied into the throwaway HERMES_HOME',
      );

      await tester.tap(find.bySemanticsLabel('Goals').first);
      await waitFor(find.text('Create a goal'));
      expect(find.text('Tracking'), findsOneWidget);
    },
    skip: !throwaway,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
