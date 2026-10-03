// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permissions.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The approval policy of [profile] on [instanceId] (`config.get` /
/// `config.set` of [approvalsModeKey] on that profile's connection).

@ProviderFor(ApprovalsModeSetting)
final approvalsModeProvider = ApprovalsModeSettingFamily._();

/// The approval policy of [profile] on [instanceId] (`config.get` /
/// `config.set` of [approvalsModeKey] on that profile's connection).
final class ApprovalsModeSettingProvider
    extends $AsyncNotifierProvider<ApprovalsModeSetting, ApprovalsMode> {
  /// The approval policy of [profile] on [instanceId] (`config.get` /
  /// `config.set` of [approvalsModeKey] on that profile's connection).
  ApprovalsModeSettingProvider._({
    required ApprovalsModeSettingFamily super.from,
    required (String, {String profile}) super.argument,
  }) : super(
         retry: null,
         name: r'approvalsModeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$approvalsModeSettingHash();

  @override
  String toString() {
    return r'approvalsModeProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ApprovalsModeSetting create() => ApprovalsModeSetting();

  @override
  bool operator ==(Object other) {
    return other is ApprovalsModeSettingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$approvalsModeSettingHash() =>
    r'f410b6f971964f369655e6758c5e084e31011cda';

/// The approval policy of [profile] on [instanceId] (`config.get` /
/// `config.set` of [approvalsModeKey] on that profile's connection).

final class ApprovalsModeSettingFamily extends $Family
    with
        $ClassFamilyOverride<
          ApprovalsModeSetting,
          AsyncValue<ApprovalsMode>,
          ApprovalsMode,
          FutureOr<ApprovalsMode>,
          (String, {String profile})
        > {
  ApprovalsModeSettingFamily._()
    : super(
        retry: null,
        name: r'approvalsModeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The approval policy of [profile] on [instanceId] (`config.get` /
  /// `config.set` of [approvalsModeKey] on that profile's connection).

  ApprovalsModeSettingProvider call(
    String instanceId, {
    String profile = 'default',
  }) => ApprovalsModeSettingProvider._(
    argument: (instanceId, profile: profile),
    from: this,
  );

  @override
  String toString() => r'approvalsModeProvider';
}

/// The approval policy of [profile] on [instanceId] (`config.get` /
/// `config.set` of [approvalsModeKey] on that profile's connection).

abstract class _$ApprovalsModeSetting extends $AsyncNotifier<ApprovalsMode> {
  late final _$args = ref.$arg as (String, {String profile});
  String get instanceId => _$args.$1;
  String get profile => _$args.profile;

  FutureOr<ApprovalsMode> build(
    String instanceId, {
    String profile = 'default',
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ApprovalsMode>, ApprovalsMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ApprovalsMode>, ApprovalsMode>,
              AsyncValue<ApprovalsMode>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, profile: _$args.profile),
    );
  }
}
