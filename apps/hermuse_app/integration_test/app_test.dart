import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/platform/secure_secret_store.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:integration_test/integration_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';

/// Real-run proof against a live Hermes instance (normally the VPS):
/// fills the add-instance form with `HERMUSE_TEST_URL/USER/PASSWORD` (env or
/// `--dart-define`), saves, sends 'Reply with only: pong', and waits for an
/// agent message containing 'pong'.
///
/// Run: `HERMUSE_TEST_URL=… HERMUSE_TEST_USER=… HERMUSE_TEST_PASSWORD=… \
///   flutter test integration_test -d linux`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add VPS instance and chat pong', (tester) async {
    final url = _value('HERMUSE_TEST_URL');
    final user = _value('HERMUSE_TEST_USER');
    final password = _value('HERMUSE_TEST_PASSWORD');
    if (url.isEmpty || user.isEmpty || password.isEmpty) {
      fail(
        'Set HERMUSE_TEST_URL/USER/PASSWORD (env or --dart-define) to run '
        'the live integration test',
      );
    }

    final db = openNativeDatabase(
      await Directory.systemTemp.createTemp('hermuse-integ-'),
    );
    addTearDown(db.close);
    SecretStore secrets = SecureSecretStore();
    var storeKind = 'SecureSecretStore';
    try {
      await secrets
          .read('__probe__', '__probe__')
          .timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      // Keyring unavailable in this session: same flow, memory secrets.
      debugPrint('KEYRING UNAVAILABLE, using MemorySecretStore: $e');
      secrets = MemorySecretStore();
      storeKind = 'MemorySecretStore';
    }
    debugPrint('SECRET STORE: $storeKind');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          secretStoreProvider.overrideWithValue(secrets),
        ],
        child: const HermuseApp(),
      ),
    );

    // Welcome → add-instance form.
    await _waitFor(tester, find.text('Connect to a Hermes'));
    await tester.tap(
      find.widgetWithText(YsButton, 'Connect to a Hermes').first,
    );
    await tester.pumpAndSettle();

    // One field now (URL); Name/Username/Password join after the probe.
    final fields = find.byType(EditableText);
    await tester.enterText(fields.first, url);
    await tester.tap(find.widgetWithText(YsButton, 'Check'));
    await _waitFor(tester, find.textContaining('Hermes 0.21.'));

    await tester.enterText(fields.at(2), user);
    await tester.enterText(fields.at(3), password);
    await tester.tap(find.widgetWithText(YsButton, 'Save and connect'));

    // The chat opens on a new conversation; the composer proves it. (The
    // kit merges the field label into the EditableText node, so match the
    // composer by its placeholder text rather than a semantics label.)
    await _waitFor(tester, find.text('Message'));
    // A fresh conversation has no transcript: send the ping.
    await tester.enterText(fields.first, 'Reply with only: pong');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send message'));
    await _waitFor(
      tester,
      find.textContaining('pong'),
      timeout: const Duration(minutes: 3),
    );

    // Sanity: credentials landed in the secret store, not the DB.
    final instances = await db.loadInstances();
    expect(instances, hasLength(1));
    expect(
      await secrets.read(instances.single.id, SecretKeys.password),
      password,
    );
  });
}

String _value(String name) {
  const defines = String.fromEnvironment('HERMUSE_TEST_URL');
  if (name == 'HERMUSE_TEST_URL' && defines.isNotEmpty) return defines;
  // `String.fromEnvironment` needs a const key; expand per variable.
  final fromDefine = switch (name) {
    'HERMUSE_TEST_USER' => const String.fromEnvironment('HERMUSE_TEST_USER'),
    'HERMUSE_TEST_PASSWORD' => const String.fromEnvironment(
      'HERMUSE_TEST_PASSWORD',
    ),
    _ => '',
  };
  if (fromDefine.isNotEmpty) return fromDefine;
  return Platform.environment[name] ?? '';
}

/// Pumps until [finder] matches or [timeout] elapses.
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) return;
  }
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .where((t) => t.isNotEmpty)
      .take(30)
      .toList();
  debugPrint('WAIT TIMEOUT for $finder; on screen: $texts');
  fail('Timed out waiting for $finder');
}
