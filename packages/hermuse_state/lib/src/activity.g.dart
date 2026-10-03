// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tools the agent finished on [instanceId], newest first, as kept on this
/// device across launches.

@ProviderFor(activity)
final activityProvider = ActivityFamily._();

/// Tools the agent finished on [instanceId], newest first, as kept on this
/// device across launches.

final class ActivityProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ActivityItem>>,
          List<ActivityItem>,
          Stream<List<ActivityItem>>
        >
    with
        $FutureModifier<List<ActivityItem>>,
        $StreamProvider<List<ActivityItem>> {
  /// Tools the agent finished on [instanceId], newest first, as kept on this
  /// device across launches.
  ActivityProvider._({
    required ActivityFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'activityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$activityHash();

  @override
  String toString() {
    return r'activityProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<ActivityItem>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ActivityItem>> create(Ref ref) {
    final argument = this.argument as (String, {String profile});
    return activity(ref, argument.$1, profile: argument.profile);
  }

  @override
  bool operator ==(Object other) {
    return other is ActivityProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$activityHash() => r'27bff9dd2782a3aff21591e74e9c9f3b9462fcc2';

/// Tools the agent finished on [instanceId], newest first, as kept on this
/// device across launches.

final class ActivityFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<List<ActivityItem>>,
          (String, {String profile})
        > {
  ActivityFamily._()
    : super(
        retry: null,
        name: r'activityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Tools the agent finished on [instanceId], newest first, as kept on this
  /// device across launches.

  ActivityProvider call(String instanceId, {String profile = 'default'}) =>
      ActivityProvider._(argument: (instanceId, profile: profile), from: this);

  @override
  String toString() => r'activityProvider';
}
