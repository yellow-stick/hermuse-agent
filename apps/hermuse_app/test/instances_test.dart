import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/shell/instances.dart';
import 'package:hermuse_app/shell/screens.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

const _password = 'generated-dashboard-secret';

HermesInstance _instance(String id, AuthMethod auth) => HermesInstance(
  id: id,
  label: id,
  kind: InstanceKind.remote,
  baseUrl: Uri.parse('https://$id.example.com'),
  auth: auth,
);

Finder _button(String text) => find.widgetWithText(YsButton, text);

void main() {
  testWidgets(
    'should show a saved dashboard password masked, with reveal and copy',
    (tester) async {
      final db = openMemoryDatabase();
      final secrets = MemorySecretStore();
      final fake = FakeHermesTransport()
        ..on('session.list', (_) => const {'sessions': []});
      final container = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
          transportFactoryProvider.overrideWithValue((_) async => fake),
        ],
      );
      addTearDown(() async {
        await fake.close();
        await db.close();
      });
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.runAsync(() async {
        final registry = await container.read(registryProvider.future);
        await registry.add(_instance('vps', AuthMethod.password));
        // Signed in on another surface: this app holds no password for it.
        await registry.add(_instance('elsewhere', AuthMethod.password));
        await secrets.write('vps', SecretKeys.username, 'admin');
        await secrets.write('vps', SecretKeys.password, _password);
        await secrets.write('elsewhere', SecretKeys.username, 'admin');
      });

      tester.view
        ..physicalSize = const Size(900, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData.fromView(tester.view)
                .copyWith(disableAnimations: true),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: YsTheme(
                palette: YsPalette.dark,
                child: Overlay.wrap(
                  child: InstancesScreen(
                    onAdd: () {},
                    onClose: () {},
                    onOpen: (_) {},
                    onSetup: (_) {},
                    onComponents: (_) {},
                    onConnections: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      // The registry loaded outside the fake clock: let its future hand over.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('vps'), findsOneWidget);
      expect(find.text('elsewhere'), findsOneWidget);
      // Only the instance whose password this app holds shows its account.
      expect(find.byType(SignInBox), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.text(_password), findsNothing);

      await tester.tap(_button('Show'));
      await tester.pumpAndSettle();
      expect(find.text(_password), findsOneWidget);
      await tester.tap(_button('Hide'));
      await tester.pumpAndSettle();
      expect(find.text(_password), findsNothing);

      await tester.tap(_button('Copy'));
      await tester.pump();
      expect(copied, _password);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      // Closes the lingering connections before the fake clock checks timers.
      container.dispose();
    },
  );
}
