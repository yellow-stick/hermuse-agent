// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tasks the agent ran on [instanceId] for [profile], newest first, across
/// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
/// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
/// written elsewhere (`sessions.changed`: scheduled runs, other clients).

@ProviderFor(Tasks)
final tasksProvider = TasksFamily._();

/// Tasks the agent ran on [instanceId] for [profile], newest first, across
/// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
/// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
/// written elsewhere (`sessions.changed`: scheduled runs, other clients).
final class TasksProvider extends $AsyncNotifierProvider<Tasks, List<Task>> {
  /// Tasks the agent ran on [instanceId] for [profile], newest first, across
  /// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
  /// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
  /// written elsewhere (`sessions.changed`: scheduled runs, other clients).
  TasksProvider._({
    required TasksFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'tasksProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tasksHash();

  @override
  String toString() {
    return r'tasksProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  Tasks create() => Tasks();

  @override
  bool operator ==(Object other) {
    return other is TasksProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tasksHash() => r'bcd46bb69ca2314efd1d36d8212e63dd2b824f19';

/// Tasks the agent ran on [instanceId] for [profile], newest first, across
/// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
/// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
/// written elsewhere (`sessions.changed`: scheduled runs, other clients).

final class TasksFamily extends $Family
    with
        $ClassFamilyOverride<
          Tasks,
          AsyncValue<List<Task>>,
          List<Task>,
          FutureOr<List<Task>>,
          (String, {String profile})
        > {
  TasksFamily._()
    : super(
        retry: null,
        name: r'tasksProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Tasks the agent ran on [instanceId] for [profile], newest first, across
  /// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
  /// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
  /// written elsewhere (`sessions.changed`: scheduled runs, other clients).

  TasksProvider call(String instanceId, {String profile = 'default'}) =>
      TasksProvider._(argument: (instanceId, profile: profile), from: this);

  @override
  String toString() => r'tasksProvider';
}

/// Tasks the agent ran on [instanceId] for [profile], newest first, across
/// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
/// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
/// written elsewhere (`sessions.changed`: scheduled runs, other clients).

abstract class _$Tasks extends $AsyncNotifier<List<Task>> {
  late final _$args = ref.$arg as (String, {String profile});
  String get instanceId => _$args.$1;
  String get profile => _$args.profile;

  FutureOr<List<Task>> build(String instanceId, {String profile = 'default'});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Task>>, List<Task>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Task>>, List<Task>>,
              AsyncValue<List<Task>>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, profile: _$args.profile),
    );
  }
}
