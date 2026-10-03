// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the Hermuse plugin backend answers on [instanceId].
///
/// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
/// router is not mounted (not installed/enabled); anything else propagates.

@ProviderFor(pluginStatus)
final pluginStatusProvider = PluginStatusFamily._();

/// Whether the Hermuse plugin backend answers on [instanceId].
///
/// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
/// router is not mounted (not installed/enabled); anything else propagates.

final class PluginStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<PluginPresence>,
          PluginPresence,
          FutureOr<PluginPresence>
        >
    with $FutureModifier<PluginPresence>, $FutureProvider<PluginPresence> {
  /// Whether the Hermuse plugin backend answers on [instanceId].
  ///
  /// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
  /// router is not mounted (not installed/enabled); anything else propagates.
  PluginStatusProvider._({
    required PluginStatusFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pluginStatusProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pluginStatusHash();

  @override
  String toString() {
    return r'pluginStatusProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<PluginPresence> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PluginPresence> create(Ref ref) {
    final argument = this.argument as String;
    return pluginStatus(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PluginStatusProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pluginStatusHash() => r'e6d7c4d1a197206a5dc5536af5aad93cc329605c';

/// Whether the Hermuse plugin backend answers on [instanceId].
///
/// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
/// router is not mounted (not installed/enabled); anything else propagates.

final class PluginStatusFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<PluginPresence>, String> {
  PluginStatusFamily._()
    : super(
        retry: null,
        name: r'pluginStatusProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the Hermuse plugin backend answers on [instanceId].
  ///
  /// Probes `GET /files` (the cheapest stable route): a 404 means the plugin
  /// router is not mounted (not installed/enabled); anything else propagates.

  PluginStatusProvider call(String instanceId) =>
      PluginStatusProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'pluginStatusProvider';
}

/// Feed posts, newest first.

@ProviderFor(Feed)
final feedProvider = FeedFamily._();

/// Feed posts, newest first.
final class FeedProvider extends $AsyncNotifierProvider<Feed, List<FeedPost>> {
  /// Feed posts, newest first.
  FeedProvider._({
    required FeedFamily super.from,
    required (String, {int limit, String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'feedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$feedHash();

  @override
  String toString() {
    return r'feedProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Feed create() => Feed();

  @override
  bool operator ==(Object other) {
    return other is FeedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$feedHash() => r'dea93d61bd31f09fd13227ace2ff84ea3b77a86b';

/// Feed posts, newest first.

final class FeedFamily extends $Family
    with
        $ClassFamilyOverride<
          Feed,
          AsyncValue<List<FeedPost>>,
          List<FeedPost>,
          FutureOr<List<FeedPost>>,
          (String, {int limit, String profile})
        > {
  FeedFamily._()
    : super(
        retry: null,
        name: r'feedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Feed posts, newest first.

  FeedProvider call(
    String instanceId, {
    int limit = 50,
    String profile = 'default',
  }) => FeedProvider._(
    argument: (instanceId, limit: limit, profile: profile),
    from: this,
  );

  @override
  String toString() => r'feedProvider';
}

/// Feed posts, newest first.

abstract class _$Feed extends $AsyncNotifier<List<FeedPost>> {
  late final _$args = ref.$arg as (String, {int limit, String profile});
  String get instanceId => _$args.$1;
  int get limit => _$args.limit;
  String get profile => _$args.profile;

  FutureOr<List<FeedPost>> build(
    String instanceId, {
    int limit = 50,
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<FeedPost>>, List<FeedPost>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<FeedPost>>, List<FeedPost>>,
              AsyncValue<List<FeedPost>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, limit: _$args.limit, profile: _$args.profile),
    );
  }
}

/// Ideas, newest first.

@ProviderFor(Ideas)
final ideasProvider = IdeasFamily._();

/// Ideas, newest first.
final class IdeasProvider extends $AsyncNotifierProvider<Ideas, List<Idea>> {
  /// Ideas, newest first.
  IdeasProvider._({
    required IdeasFamily super.from,
    required (String, {int limit, String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'ideasProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$ideasHash();

  @override
  String toString() {
    return r'ideasProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Ideas create() => Ideas();

  @override
  bool operator ==(Object other) {
    return other is IdeasProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$ideasHash() => r'158495c88952b63952945289fb086b4438c2fe50';

/// Ideas, newest first.

final class IdeasFamily extends $Family
    with
        $ClassFamilyOverride<
          Ideas,
          AsyncValue<List<Idea>>,
          List<Idea>,
          FutureOr<List<Idea>>,
          (String, {int limit, String profile})
        > {
  IdeasFamily._()
    : super(
        retry: null,
        name: r'ideasProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Ideas, newest first.

  IdeasProvider call(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  }) => IdeasProvider._(
    argument: (instanceId, limit: limit, profile: profile),
    from: this,
  );

  @override
  String toString() => r'ideasProvider';
}

/// Ideas, newest first.

abstract class _$Ideas extends $AsyncNotifier<List<Idea>> {
  late final _$args = ref.$arg as (String, {int limit, String profile});
  String get instanceId => _$args.$1;
  int get limit => _$args.limit;
  String get profile => _$args.profile;

  FutureOr<List<Idea>> build(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Idea>>, List<Idea>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Idea>>, List<Idea>>,
              AsyncValue<List<Idea>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, limit: _$args.limit, profile: _$args.profile),
    );
  }
}

/// Goals, newest first.

@ProviderFor(Goals)
final goalsProvider = GoalsFamily._();

/// Goals, newest first.
final class GoalsProvider extends $AsyncNotifierProvider<Goals, List<Goal>> {
  /// Goals, newest first.
  GoalsProvider._({
    required GoalsFamily super.from,
    required (String, {int limit, String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'goalsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$goalsHash();

  @override
  String toString() {
    return r'goalsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Goals create() => Goals();

  @override
  bool operator ==(Object other) {
    return other is GoalsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$goalsHash() => r'acf4fb0ef071aa7cc26c0c2e4470d49e1ce9c09b';

/// Goals, newest first.

final class GoalsFamily extends $Family
    with
        $ClassFamilyOverride<
          Goals,
          AsyncValue<List<Goal>>,
          List<Goal>,
          FutureOr<List<Goal>>,
          (String, {int limit, String profile})
        > {
  GoalsFamily._()
    : super(
        retry: null,
        name: r'goalsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Goals, newest first.

  GoalsProvider call(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  }) => GoalsProvider._(
    argument: (instanceId, limit: limit, profile: profile),
    from: this,
  );

  @override
  String toString() => r'goalsProvider';
}

/// Goals, newest first.

abstract class _$Goals extends $AsyncNotifier<List<Goal>> {
  late final _$args = ref.$arg as (String, {int limit, String profile});
  String get instanceId => _$args.$1;
  int get limit => _$args.limit;
  String get profile => _$args.profile;

  FutureOr<List<Goal>> build(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Goal>>, List<Goal>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Goal>>, List<Goal>>,
              AsyncValue<List<Goal>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, limit: _$args.limit, profile: _$args.profile),
    );
  }
}

/// Library artifacts, newest first.

@ProviderFor(artifacts)
final artifactsProvider = ArtifactsFamily._();

/// Library artifacts, newest first.

final class ArtifactsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Artifact>>,
          List<Artifact>,
          FutureOr<List<Artifact>>
        >
    with $FutureModifier<List<Artifact>>, $FutureProvider<List<Artifact>> {
  /// Library artifacts, newest first.
  ArtifactsProvider._({
    required ArtifactsFamily super.from,
    required (String, {int limit, String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'artifactsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$artifactsHash();

  @override
  String toString() {
    return r'artifactsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<Artifact>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Artifact>> create(Ref ref) {
    final argument = this.argument as (String, {int limit, String profile});
    return artifacts(
      ref,
      argument.$1,
      limit: argument.limit,
      profile: argument.profile,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ArtifactsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$artifactsHash() => r'3b6104ee716bea429e1fa3cc8883c2503868b598';

/// Library artifacts, newest first.

final class ArtifactsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<Artifact>>,
          (String, {int limit, String profile})
        > {
  ArtifactsFamily._()
    : super(
        retry: null,
        name: r'artifactsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Library artifacts, newest first.

  ArtifactsProvider call(
    String instanceId, {
    int limit = 200,
    String profile = 'default',
  }) => ArtifactsProvider._(
    argument: (instanceId, limit: limit, profile: profile),
    from: this,
  );

  @override
  String toString() => r'artifactsProvider';
}

/// Reflection journal entries, newest first.

@ProviderFor(reflections)
final reflectionsProvider = ReflectionsFamily._();

/// Reflection journal entries, newest first.

final class ReflectionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Reflection>>,
          List<Reflection>,
          FutureOr<List<Reflection>>
        >
    with $FutureModifier<List<Reflection>>, $FutureProvider<List<Reflection>> {
  /// Reflection journal entries, newest first.
  ReflectionsProvider._({
    required ReflectionsFamily super.from,
    required (String, {int limit, String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'reflectionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reflectionsHash();

  @override
  String toString() {
    return r'reflectionsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<Reflection>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Reflection>> create(Ref ref) {
    final argument = this.argument as (String, {int limit, String profile});
    return reflections(
      ref,
      argument.$1,
      limit: argument.limit,
      profile: argument.profile,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReflectionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reflectionsHash() => r'b85a536cb0e9f7307b186fb272309f124aed246e';

/// Reflection journal entries, newest first.

final class ReflectionsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<Reflection>>,
          (String, {int limit, String profile})
        > {
  ReflectionsFamily._()
    : super(
        retry: null,
        name: r'reflectionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Reflection journal entries, newest first.

  ReflectionsProvider call(
    String instanceId, {
    int limit = 90,
    String profile = 'default',
  }) => ReflectionsProvider._(
    argument: (instanceId, limit: limit, profile: profile),
    from: this,
  );

  @override
  String toString() => r'reflectionsProvider';
}

/// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
/// or [preferencesFileName].

@ProviderFor(SystemFileState)
final systemFileProvider = SystemFileStateFamily._();

/// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
/// or [preferencesFileName].
final class SystemFileStateProvider
    extends $AsyncNotifierProvider<SystemFileState, SystemFile> {
  /// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
  /// or [preferencesFileName].
  SystemFileStateProvider._({
    required SystemFileStateFamily super.from,
    required (String, String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'systemFileProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$systemFileStateHash();

  @override
  String toString() {
    return r'systemFileProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SystemFileState create() => SystemFileState();

  @override
  bool operator ==(Object other) {
    return other is SystemFileStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$systemFileStateHash() => r'93a57be0f3134fc5746869a3dbdac1d011fcf2af';

/// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
/// or [preferencesFileName].

final class SystemFileStateFamily extends $Family
    with
        $ClassFamilyOverride<
          SystemFileState,
          AsyncValue<SystemFile>,
          SystemFile,
          FutureOr<SystemFile>,
          (String, String, {String profile})
        > {
  SystemFileStateFamily._()
    : super(
        retry: null,
        name: r'systemFileProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
  /// or [preferencesFileName].

  SystemFileStateProvider call(
    String instanceId,
    String name, {
    String profile = 'default',
  }) => SystemFileStateProvider._(
    argument: (instanceId, name, profile: profile),
    from: this,
  );

  @override
  String toString() => r'systemFileProvider';
}

/// One managed system file (`FEED_PROMPT.md`, `IDENTITY.md`, `HEARTBEAT.md`)
/// or [preferencesFileName].

abstract class _$SystemFileState extends $AsyncNotifier<SystemFile> {
  late final _$args = ref.$arg as (String, String, {String profile});
  String get instanceId => _$args.$1;
  String get name => _$args.$2;
  String get profile => _$args.profile;

  FutureOr<SystemFile> build(
    String instanceId,
    String name, {
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SystemFile>, SystemFile>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SystemFile>, SystemFile>,
              AsyncValue<SystemFile>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, _$args.$2, profile: _$args.profile),
    );
  }
}
