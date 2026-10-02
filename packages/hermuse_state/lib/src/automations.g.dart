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
    required String super.argument,
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
        '($argument)';
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

String _$automationsHash() => r'794e78729870475f14a8dcde5e1315d5c7cd6720';

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.

final class AutomationsFamily extends $Family
    with
        $ClassFamilyOverride<
          Automations,
          AsyncValue<AutomationBoard>,
          AutomationBoard,
          FutureOr<AutomationBoard>,
          String
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

  AutomationsProvider call(String instanceId) =>
      AutomationsProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'automationsProvider';
}

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.

abstract class _$Automations extends $AsyncNotifier<AutomationBoard> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<AutomationBoard> build(String instanceId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}
