// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_update.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// App-update check state: one cached feed result plus its persistence.
///
/// Network through [httpClientProvider]; persistence in the settings table
/// (per-version skip, last-check timestamp), so both apps share it. The
/// running version and platform are injected for tests; production passes
/// the real ones from `app_update.dart` of each app.

@ProviderFor(AppUpdate)
final appUpdateProvider = AppUpdateFamily._();

/// App-update check state: one cached feed result plus its persistence.
///
/// Network through [httpClientProvider]; persistence in the settings table
/// (per-version skip, last-check timestamp), so both apps share it. The
/// running version and platform are injected for tests; production passes
/// the real ones from `app_update.dart` of each app.
final class AppUpdateProvider
    extends $AsyncNotifierProvider<AppUpdate, AppUpdateStatus?> {
  /// App-update check state: one cached feed result plus its persistence.
  ///
  /// Network through [httpClientProvider]; persistence in the settings table
  /// (per-version skip, last-check timestamp), so both apps share it. The
  /// running version and platform are injected for tests; production passes
  /// the real ones from `app_update.dart` of each app.
  AppUpdateProvider._({
    required AppUpdateFamily super.from,
    required ({String? currentVersion, AppPlatform? platform}) super.argument,
  }) : super(
         retry: null,
         name: r'appUpdateProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$appUpdateHash();

  @override
  String toString() {
    return r'appUpdateProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AppUpdate create() => AppUpdate();

  @override
  bool operator ==(Object other) {
    return other is AppUpdateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$appUpdateHash() => r'd1b0fa00a3ecad46f12fcf986cf383187f3f1b18';

/// App-update check state: one cached feed result plus its persistence.
///
/// Network through [httpClientProvider]; persistence in the settings table
/// (per-version skip, last-check timestamp), so both apps share it. The
/// running version and platform are injected for tests; production passes
/// the real ones from `app_update.dart` of each app.

final class AppUpdateFamily extends $Family
    with
        $ClassFamilyOverride<
          AppUpdate,
          AsyncValue<AppUpdateStatus?>,
          AppUpdateStatus?,
          FutureOr<AppUpdateStatus?>,
          ({String? currentVersion, AppPlatform? platform})
        > {
  AppUpdateFamily._()
    : super(
        retry: null,
        name: r'appUpdateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// App-update check state: one cached feed result plus its persistence.
  ///
  /// Network through [httpClientProvider]; persistence in the settings table
  /// (per-version skip, last-check timestamp), so both apps share it. The
  /// running version and platform are injected for tests; production passes
  /// the real ones from `app_update.dart` of each app.

  AppUpdateProvider call({String? currentVersion, AppPlatform? platform}) =>
      AppUpdateProvider._(
        argument: (currentVersion: currentVersion, platform: platform),
        from: this,
      );

  @override
  String toString() => r'appUpdateProvider';
}

/// App-update check state: one cached feed result plus its persistence.
///
/// Network through [httpClientProvider]; persistence in the settings table
/// (per-version skip, last-check timestamp), so both apps share it. The
/// running version and platform are injected for tests; production passes
/// the real ones from `app_update.dart` of each app.

abstract class _$AppUpdate extends $AsyncNotifier<AppUpdateStatus?> {
  late final _$args =
      ref.$arg as ({String? currentVersion, AppPlatform? platform});
  String? get currentVersion => _$args.currentVersion;
  AppPlatform? get platform => _$args.platform;

  FutureOr<AppUpdateStatus?> build({
    String? currentVersion,
    AppPlatform? platform,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AppUpdateStatus?>, AppUpdateStatus?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AppUpdateStatus?>, AppUpdateStatus?>,
              AsyncValue<AppUpdateStatus?>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(
        currentVersion: _$args.currentVersion,
        platform: _$args.platform,
      ),
    );
  }
}
