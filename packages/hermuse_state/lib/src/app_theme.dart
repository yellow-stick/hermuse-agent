import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'providers.dart';

part 'app_theme.g.dart';

/// Device-local appearance, shared by the native and web settings surfaces.
@Riverpod(keepAlive: true)
class AppTheme extends _$AppTheme {
  static const _key = 'app_theme';

  @override
  Future<YsThemeMode> build() async {
    final saved = await ref.watch(hermuseDatabaseProvider).readSetting(_key);
    return switch (saved) {
      'light' => YsThemeMode.light,
      'system' => YsThemeMode.system,
      _ => YsThemeMode.dark,
    };
  }

  /// Publishes the choice only once it is saved; a failed write leaves the
  /// current appearance intact and is reported by the settings surface.
  Future<void> setMode(YsThemeMode mode) async {
    await future;
    await ref.read(hermuseDatabaseProvider).writeSetting(_key, mode.name);
    if (ref.mounted) state = AsyncData(mode);
  }
}
