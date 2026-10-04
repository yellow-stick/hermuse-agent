import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  late HermuseDatabase db;
  late ProviderContainer container;

  ProviderContainer openScope() => ProviderContainer(
    overrides: [hermuseDatabaseProvider.overrideWithValue(db)],
  );

  setUp(() {
    db = openMemoryDatabase();
    container = openScope();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test(
    'dark is the default but explicit light and system survive reopening',
    () async {
      expect(await container.read(appThemeProvider.future), YsThemeMode.dark);
      await container
          .read(appThemeProvider.notifier)
          .setMode(YsThemeMode.light);
      container.dispose();
      container = openScope();
      expect(await container.read(appThemeProvider.future), YsThemeMode.light);

      await container
          .read(appThemeProvider.notifier)
          .setMode(YsThemeMode.system);
      container.dispose();
      container = openScope();
      expect(await container.read(appThemeProvider.future), YsThemeMode.system);
    },
  );

  test('a failed save retains the last saved appearance', () async {
    await container.read(appThemeProvider.notifier).setMode(YsThemeMode.light);
    await db.customStatement('''
      CREATE TRIGGER reject_settings BEFORE INSERT ON settings
      BEGIN SELECT RAISE(ABORT, 'storage unavailable'); END;
    ''');

    await expectLater(
      container.read(appThemeProvider.notifier).setMode(YsThemeMode.dark),
      throwsA(isA<Exception>()),
    );
    expect(container.read(appThemeProvider).requireValue, YsThemeMode.light);
    container.dispose();
    container = openScope();
    expect(await container.read(appThemeProvider.future), YsThemeMode.light);
  });
}
