// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [target]'s entries for [profile] on [instanceId] (the Identity tab's
/// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
/// keeps them in the memory file, separated by `§` lines, written under its
/// memory lock.

@ProviderFor(AgentMemoryState)
final agentMemoryProvider = AgentMemoryStateFamily._();

/// [target]'s entries for [profile] on [instanceId] (the Identity tab's
/// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
/// keeps them in the memory file, separated by `§` lines, written under its
/// memory lock.
final class AgentMemoryStateProvider
    extends $AsyncNotifierProvider<AgentMemoryState, AgentMemory> {
  /// [target]'s entries for [profile] on [instanceId] (the Identity tab's
  /// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
  /// keeps them in the memory file, separated by `§` lines, written under its
  /// memory lock.
  AgentMemoryStateProvider._({
    required AgentMemoryStateFamily super.from,
    required (String, MemoryTarget, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'agentMemoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentMemoryStateHash();

  @override
  String toString() {
    return r'agentMemoryProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AgentMemoryState create() => AgentMemoryState();

  @override
  bool operator ==(Object other) {
    return other is AgentMemoryStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentMemoryStateHash() => r'7d9e212f471ec25e75382ad5310f8094f71145ca';

/// [target]'s entries for [profile] on [instanceId] (the Identity tab's
/// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
/// keeps them in the memory file, separated by `§` lines, written under its
/// memory lock.

final class AgentMemoryStateFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentMemoryState,
          AsyncValue<AgentMemory>,
          AgentMemory,
          FutureOr<AgentMemory>,
          (String, MemoryTarget, {String profile})
        > {
  AgentMemoryStateFamily._()
    : super(
        retry: null,
        name: r'agentMemoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [target]'s entries for [profile] on [instanceId] (the Identity tab's
  /// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
  /// keeps them in the memory file, separated by `§` lines, written under its
  /// memory lock.

  AgentMemoryStateProvider call(
    String instanceId,
    MemoryTarget target, {
    String profile = 'default',
  }) => AgentMemoryStateProvider._(
    argument: (instanceId, target, profile: profile),
    from: this,
  );

  @override
  String toString() => r'agentMemoryProvider';
}

/// [target]'s entries for [profile] on [instanceId] (the Identity tab's
/// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
/// keeps them in the memory file, separated by `§` lines, written under its
/// memory lock.

abstract class _$AgentMemoryState extends $AsyncNotifier<AgentMemory> {
  late final _$args = ref.$arg as (String, MemoryTarget, {String profile});
  String get instanceId => _$args.$1;
  MemoryTarget get target => _$args.$2;
  String get profile => _$args.profile;

  FutureOr<AgentMemory> build(
    String instanceId,
    MemoryTarget target, {
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<AgentMemory>, AgentMemory>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AgentMemory>, AgentMemory>,
              AsyncValue<AgentMemory>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, profile: _$args.profile),
    );
  }
}
