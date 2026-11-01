// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_theme.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Device-local appearance, shared by the native and web settings surfaces.

@ProviderFor(AppTheme)
final appThemeProvider = AppThemeProvider._();

/// Device-local appearance, shared by the native and web settings surfaces.
final class AppThemeProvider
    extends $AsyncNotifierProvider<AppTheme, YsThemeMode> {
  /// Device-local appearance, shared by the native and web settings surfaces.
  AppThemeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appThemeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appThemeHash();

  @$internal
  @override
  AppTheme create() => AppTheme();
}

String _$appThemeHash() => r'd7c80ee88e4a93ac8d896ef19b1a53f07e7d70bb';

/// Device-local appearance, shared by the native and web settings surfaces.

abstract class _$AppTheme extends $AsyncNotifier<YsThemeMode> {
  FutureOr<YsThemeMode> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<YsThemeMode>, YsThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<YsThemeMode>, YsThemeMode>,
              AsyncValue<YsThemeMode>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
