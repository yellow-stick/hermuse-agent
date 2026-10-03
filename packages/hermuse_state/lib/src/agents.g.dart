// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'agents.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AgentProfiles)
final agentProfilesProvider = AgentProfilesFamily._();

final class AgentProfilesProvider
    extends $AsyncNotifierProvider<AgentProfiles, List<AgentProfile>> {
  AgentProfilesProvider._({
    required AgentProfilesFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'agentProfilesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProfilesHash();

  @override
  String toString() {
    return r'agentProfilesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AgentProfiles create() => AgentProfiles();

  @override
  bool operator ==(Object other) {
    return other is AgentProfilesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProfilesHash() => r'1e74d2847e4a137900065db0dbcb685ee5224609';

final class AgentProfilesFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentProfiles,
          AsyncValue<List<AgentProfile>>,
          List<AgentProfile>,
          FutureOr<List<AgentProfile>>,
          String
        > {
  AgentProfilesFamily._()
    : super(
        retry: _noRetry,
        name: r'agentProfilesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentProfilesProvider call(String instanceId) =>
      AgentProfilesProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'agentProfilesProvider';
}

abstract class _$AgentProfiles extends $AsyncNotifier<List<AgentProfile>> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<List<AgentProfile>> build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<AgentProfile>>, List<AgentProfile>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<AgentProfile>>, List<AgentProfile>>,
              AsyncValue<List<AgentProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

@ProviderFor(agentDetails)
final agentDetailsProvider = AgentDetailsFamily._();

final class AgentDetailsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentDetails>,
          AgentDetails,
          FutureOr<AgentDetails>
        >
    with $FutureModifier<AgentDetails>, $FutureProvider<AgentDetails> {
  AgentDetailsProvider._({
    required AgentDetailsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'agentDetailsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentDetailsHash();

  @override
  String toString() {
    return r'agentDetailsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentDetails> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentDetails> create(Ref ref) {
    final argument = this.argument as (String, String);
    return agentDetails(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentDetailsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentDetailsHash() => r'41febc46e5d72374d437dd52439a7aef3e2a9dba';

final class AgentDetailsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentDetails>, (String, String)> {
  AgentDetailsFamily._()
    : super(
        retry: _noRetry,
        name: r'agentDetailsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentDetailsProvider call(String instanceId, String profile) =>
      AgentDetailsProvider._(argument: (instanceId, profile), from: this);

  @override
  String toString() => r'agentDetailsProvider';
}

@ProviderFor(agentProfile)
final agentProfileProvider = AgentProfileFamily._();

final class AgentProfileProvider
    extends $FunctionalProvider<AgentProfile?, AgentProfile?, AgentProfile?>
    with $Provider<AgentProfile?> {
  AgentProfileProvider._({
    required AgentProfileFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'agentProfileProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentProfileHash();

  @override
  String toString() {
    return r'agentProfileProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<AgentProfile?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AgentProfile? create(Ref ref) {
    final argument = this.argument as (String, String);
    return agentProfile(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentProfile? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentProfile?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentProfileProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentProfileHash() => r'9c30e5f488c7d2df95761741f92cc1ac200de6a5';

final class AgentProfileFamily extends $Family
    with $FunctionalFamilyOverride<AgentProfile?, (String, String)> {
  AgentProfileFamily._()
    : super(
        retry: null,
        name: r'agentProfileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentProfileProvider call(String instanceId, String profile) =>
      AgentProfileProvider._(argument: (instanceId, profile), from: this);

  @override
  String toString() => r'agentProfileProvider';
}
