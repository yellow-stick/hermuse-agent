// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automations.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.

@ProviderFor(Automations)
final automationsProvider = AutomationsFamily._();

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.
final class AutomationsProvider
    extends $AsyncNotifierProvider<Automations, AutomationBoard> {
  /// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
  /// with pause/resume, run now and delete.
  AutomationsProvider._({
    required AutomationsFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'automationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationsHash();

  @override
  String toString() {
    return r'automationsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Automations create() => Automations();

  @override
  bool operator ==(Object other) {
    return other is AutomationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationsHash() => r'961071f8c59e63af560c0538f978d613458ffa16';

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.

final class AutomationsFamily extends $Family
    with
        $ClassFamilyOverride<
          Automations,
          AsyncValue<AutomationBoard>,
          AutomationBoard,
          FutureOr<AutomationBoard>,
          (String, {String profile})
        > {
  AutomationsFamily._()
    : super(
        retry: null,
        name: r'automationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
  /// with pause/resume, run now and delete.

  AutomationsProvider call(String instanceId, {String profile = 'default'}) =>
      AutomationsProvider._(
        argument: (instanceId, profile: profile),
        from: this,
      );

  @override
  String toString() => r'automationsProvider';
}

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.

abstract class _$Automations extends $AsyncNotifier<AutomationBoard> {
  late final _$args = ref.$arg as (String, {String profile});
  String get instanceId => _$args.$1;
  String get profile => _$args.profile;

  FutureOr<AutomationBoard> build(
    String instanceId, {
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AutomationBoard>, AutomationBoard>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AutomationBoard>, AutomationBoard>,
              AsyncValue<AutomationBoard>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, profile: _$args.profile),
    );
  }
}
