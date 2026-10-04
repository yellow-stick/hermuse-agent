// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'automations.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
/// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
/// run now and delete.

@ProviderFor(Automations)
final automationsProvider = AutomationsFamily._();

/// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
/// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
/// run now and delete.
final class AutomationsProvider
    extends $AsyncNotifierProvider<Automations, AutomationBoard> {
  /// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
  /// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
  /// run now and delete.
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

String _$automationsHash() => r'c2e0bcc10a0a8aca6f1f8764c0d7560d18a2df5a';

/// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
/// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
/// run now and delete.

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

  /// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
  /// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
  /// run now and delete.

  AutomationsProvider call(String instanceId, {String profile = 'default'}) =>
      AutomationsProvider._(
        argument: (instanceId, profile: profile),
        from: this,
      );

  @override
  String toString() => r'automationsProvider';
}

/// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
/// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
/// run now and delete.

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

/// The last few runs of the automation [jobId], newest first, each with
/// an excerpt of what it delivered (the run session's final answer; the
/// job's `last_output` for the newest run when its transcript says
/// nothing).

@ProviderFor(automationRuns)
final automationRunsProvider = AutomationRunsFamily._();

/// The last few runs of the automation [jobId], newest first, each with
/// an excerpt of what it delivered (the run session's final answer; the
/// job's `last_output` for the newest run when its transcript says
/// nothing).

final class AutomationRunsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AutomationRun>>,
          List<AutomationRun>,
          FutureOr<List<AutomationRun>>
        >
    with
        $FutureModifier<List<AutomationRun>>,
        $FutureProvider<List<AutomationRun>> {
  /// The last few runs of the automation [jobId], newest first, each with
  /// an excerpt of what it delivered (the run session's final answer; the
  /// job's `last_output` for the newest run when its transcript says
  /// nothing).
  AutomationRunsProvider._({
    required AutomationRunsFamily super.from,
    required (String, String, {String profile, int limit}) super.argument,
  }) : super(
         retry: null,
         name: r'automationRunsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$automationRunsHash();

  @override
  String toString() {
    return r'automationRunsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<AutomationRun>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AutomationRun>> create(Ref ref) {
    final argument =
        this.argument as (String, String, {String profile, int limit});
    return automationRuns(
      ref,
      argument.$1,
      argument.$2,
      profile: argument.profile,
      limit: argument.limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AutomationRunsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$automationRunsHash() => r'381321a510931e123bde4b03836aca5ac9a73c27';

/// The last few runs of the automation [jobId], newest first, each with
/// an excerpt of what it delivered (the run session's final answer; the
/// job's `last_output` for the newest run when its transcript says
/// nothing).

final class AutomationRunsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AutomationRun>>,
          (String, String, {String profile, int limit})
        > {
  AutomationRunsFamily._()
    : super(
        retry: null,
        name: r'automationRunsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The last few runs of the automation [jobId], newest first, each with
  /// an excerpt of what it delivered (the run session's final answer; the
  /// job's `last_output` for the newest run when its transcript says
  /// nothing).

  AutomationRunsProvider call(
    String instanceId,
    String jobId, {
    String profile = 'default',
    int limit = 10,
  }) => AutomationRunsProvider._(
    argument: (instanceId, jobId, profile: profile, limit: limit),
    from: this,
  );

  @override
  String toString() => r'automationRunsProvider';
}
