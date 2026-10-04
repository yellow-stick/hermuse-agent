// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The generation service settings of [instanceId]'s server (stored by the
/// default profile, shared by every agent).

@ProviderFor(MediaConfigState)
final mediaConfigProvider = MediaConfigStateFamily._();

/// The generation service settings of [instanceId]'s server (stored by the
/// default profile, shared by every agent).
final class MediaConfigStateProvider
    extends $AsyncNotifierProvider<MediaConfigState, MediaConfig> {
  /// The generation service settings of [instanceId]'s server (stored by the
  /// default profile, shared by every agent).
  MediaConfigStateProvider._({
    required MediaConfigStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'mediaConfigProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaConfigStateHash();

  @override
  String toString() {
    return r'mediaConfigProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaConfigState create() => MediaConfigState();

  @override
  bool operator ==(Object other) {
    return other is MediaConfigStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaConfigStateHash() => r'63bc534ee4bd74a6200f7c2353e8c483c5b528df';

/// The generation service settings of [instanceId]'s server (stored by the
/// default profile, shared by every agent).

final class MediaConfigStateFamily extends $Family
    with
        $ClassFamilyOverride<
          MediaConfigState,
          AsyncValue<MediaConfig>,
          MediaConfig,
          FutureOr<MediaConfig>,
          String
        > {
  MediaConfigStateFamily._()
    : super(
        retry: _noRetry,
        name: r'mediaConfigProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The generation service settings of [instanceId]'s server (stored by the
  /// default profile, shared by every agent).

  MediaConfigStateProvider call(String instanceId) =>
      MediaConfigStateProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'mediaConfigProvider';
}

/// The generation service settings of [instanceId]'s server (stored by the
/// default profile, shared by every agent).

abstract class _$MediaConfigState extends $AsyncNotifier<MediaConfig> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<MediaConfig> build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MediaConfig>, MediaConfig>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MediaConfig>, MediaConfig>,
              AsyncValue<MediaConfig>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Whether the generation service answers, its credits and the price of
/// an animation clip (Settings' Test; the editor's cost line).

@ProviderFor(MediaStatusState)
final mediaStatusProvider = MediaStatusStateFamily._();

/// Whether the generation service answers, its credits and the price of
/// an animation clip (Settings' Test; the editor's cost line).
final class MediaStatusStateProvider
    extends $AsyncNotifierProvider<MediaStatusState, MediaStatus> {
  /// Whether the generation service answers, its credits and the price of
  /// an animation clip (Settings' Test; the editor's cost line).
  MediaStatusStateProvider._({
    required MediaStatusStateFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noRetry,
         name: r'mediaStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaStatusStateHash();

  @override
  String toString() {
    return r'mediaStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaStatusState create() => MediaStatusState();

  @override
  bool operator ==(Object other) {
    return other is MediaStatusStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaStatusStateHash() => r'c1e3f8f3bef95649bec922d2c30c9b69f79e89e2';

/// Whether the generation service answers, its credits and the price of
/// an animation clip (Settings' Test; the editor's cost line).

final class MediaStatusStateFamily extends $Family
    with
        $ClassFamilyOverride<
          MediaStatusState,
          AsyncValue<MediaStatus>,
          MediaStatus,
          FutureOr<MediaStatus>,
          String
        > {
  MediaStatusStateFamily._()
    : super(
        retry: _noRetry,
        name: r'mediaStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the generation service answers, its credits and the price of
  /// an animation clip (Settings' Test; the editor's cost line).

  MediaStatusStateProvider call(String instanceId) =>
      MediaStatusStateProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'mediaStatusProvider';
}

/// Whether the generation service answers, its credits and the price of
/// an animation clip (Settings' Test; the editor's cost line).

abstract class _$MediaStatusState extends $AsyncNotifier<MediaStatus> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<MediaStatus> build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<MediaStatus>, MediaStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<MediaStatus>, MediaStatus>,
              AsyncValue<MediaStatus>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// How often a running avatar job is polled.

@ProviderFor(avatarJobPollInterval)
final avatarJobPollIntervalProvider = AvatarJobPollIntervalProvider._();

/// How often a running avatar job is polled.

final class AvatarJobPollIntervalProvider
    extends $FunctionalProvider<Duration, Duration, Duration>
    with $Provider<Duration> {
  /// How often a running avatar job is polled.
  AvatarJobPollIntervalProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'avatarJobPollIntervalProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$avatarJobPollIntervalHash();

  @$internal
  @override
  $ProviderElement<Duration> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Duration create(Ref ref) {
    return avatarJobPollInterval(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Duration value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Duration>(value),
    );
  }
}

String _$avatarJobPollIntervalHash() =>
    r'aaee809e3ccd7c4fc11e8e6aaac92a4c200f9481';

/// The generated portrait and animations of [profile] on [instanceId].
///
/// While a job runs it is polled every [avatarJobPollIntervalProvider] and
/// the avatar follows it (new clips appear as they finish); polling stops
/// when the job ends or the provider is disposed. A failed poll keeps the
/// avatar as the error's value and polls again. Actions throw
/// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
/// a job runs, 422 without a portrait, 502 when the service refused.

@ProviderFor(AgentAvatarState)
final agentAvatarProvider = AgentAvatarStateFamily._();

/// The generated portrait and animations of [profile] on [instanceId].
///
/// While a job runs it is polled every [avatarJobPollIntervalProvider] and
/// the avatar follows it (new clips appear as they finish); polling stops
/// when the job ends or the provider is disposed. A failed poll keeps the
/// avatar as the error's value and polls again. Actions throw
/// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
/// a job runs, 422 without a portrait, 502 when the service refused.
final class AgentAvatarStateProvider
    extends $AsyncNotifierProvider<AgentAvatarState, Avatar> {
  /// The generated portrait and animations of [profile] on [instanceId].
  ///
  /// While a job runs it is polled every [avatarJobPollIntervalProvider] and
  /// the avatar follows it (new clips appear as they finish); polling stops
  /// when the job ends or the provider is disposed. A failed poll keeps the
  /// avatar as the error's value and polls again. Actions throw
  /// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
  /// a job runs, 422 without a portrait, 502 when the service refused.
  AgentAvatarStateProvider._({
    required AgentAvatarStateFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: _noRetry,
         name: r'agentAvatarProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentAvatarStateHash();

  @override
  String toString() {
    return r'agentAvatarProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AgentAvatarState create() => AgentAvatarState();

  @override
  bool operator ==(Object other) {
    return other is AgentAvatarStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentAvatarStateHash() => r'824413776d046f5523e373ed14ad84b4d0ebeede';

/// The generated portrait and animations of [profile] on [instanceId].
///
/// While a job runs it is polled every [avatarJobPollIntervalProvider] and
/// the avatar follows it (new clips appear as they finish); polling stops
/// when the job ends or the provider is disposed. A failed poll keeps the
/// avatar as the error's value and polls again. Actions throw
/// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
/// a job runs, 422 without a portrait, 502 when the service refused.

final class AgentAvatarStateFamily extends $Family
    with
        $ClassFamilyOverride<
          AgentAvatarState,
          AsyncValue<Avatar>,
          Avatar,
          FutureOr<Avatar>,
          (String, {String profile})
        > {
  AgentAvatarStateFamily._()
    : super(
        retry: _noRetry,
        name: r'agentAvatarProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The generated portrait and animations of [profile] on [instanceId].
  ///
  /// While a job runs it is polled every [avatarJobPollIntervalProvider] and
  /// the avatar follows it (new clips appear as they finish); polling stops
  /// when the job ends or the provider is disposed. A failed poll keeps the
  /// avatar as the error's value and polls again. Actions throw
  /// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
  /// a job runs, 422 without a portrait, 502 when the service refused.

  AgentAvatarStateProvider call(
    String instanceId, {
    String profile = 'default',
  }) => AgentAvatarStateProvider._(
    argument: (instanceId, profile: profile),
    from: this,
  );

  @override
  String toString() => r'agentAvatarProvider';
}

/// The generated portrait and animations of [profile] on [instanceId].
///
/// While a job runs it is polled every [avatarJobPollIntervalProvider] and
/// the avatar follows it (new clips appear as they finish); polling stops
/// when the job ends or the provider is disposed. A failed poll keeps the
/// avatar as the error's value and polls again. Actions throw
/// [HermesHttpError] with the server's reason ([hermesReason]): 409 while
/// a job runs, 422 without a portrait, 502 when the service refused.

abstract class _$AgentAvatarState extends $AsyncNotifier<Avatar> {
  late final _$args = ref.$arg as (String, {String profile});
  String get instanceId => _$args.$1;
  String get profile => _$args.profile;

  FutureOr<Avatar> build(String instanceId, {String profile = 'default'});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Avatar>, Avatar>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Avatar>, Avatar>,
              AsyncValue<Avatar>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, profile: _$args.profile),
    );
  }
}
