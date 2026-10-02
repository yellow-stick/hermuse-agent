// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Onboarding state machine of one instance, over its shared connection.
///
/// Re-reads both readiness probes whenever the boot bootstrap re-announces
/// `setup.ready` (the event payload is only a hint), and advances
/// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
/// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
///
/// Auto-disposed with its screen so it does not pin the instance connection.

@ProviderFor(Onboarding)
final onboardingProvider = OnboardingFamily._();

/// Onboarding state machine of one instance, over its shared connection.
///
/// Re-reads both readiness probes whenever the boot bootstrap re-announces
/// `setup.ready` (the event payload is only a hint), and advances
/// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
/// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
///
/// Auto-disposed with its screen so it does not pin the instance connection.
final class OnboardingProvider
    extends $AsyncNotifierProvider<Onboarding, OnboardingState> {
  /// Onboarding state machine of one instance, over its shared connection.
  ///
  /// Re-reads both readiness probes whenever the boot bootstrap re-announces
  /// `setup.ready` (the event payload is only a hint), and advances
  /// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
  /// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
  ///
  /// Auto-disposed with its screen so it does not pin the instance connection.
  OnboardingProvider._({
    required OnboardingFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'onboardingProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$onboardingHash();

  @override
  String toString() {
    return r'onboardingProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  Onboarding create() => Onboarding();

  @override
  bool operator ==(Object other) {
    return other is OnboardingProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$onboardingHash() => r'13dd85f84961dd3550e2d9bf3be0a792b0381ea8';

/// Onboarding state machine of one instance, over its shared connection.
///
/// Re-reads both readiness probes whenever the boot bootstrap re-announces
/// `setup.ready` (the event payload is only a hint), and advances
/// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
/// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
///
/// Auto-disposed with its screen so it does not pin the instance connection.

final class OnboardingFamily extends $Family
    with
        $ClassFamilyOverride<
          Onboarding,
          AsyncValue<OnboardingState>,
          OnboardingState,
          FutureOr<OnboardingState>,
          String
        > {
  OnboardingFamily._()
    : super(
        retry: null,
        name: r'onboardingProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Onboarding state machine of one instance, over its shared connection.
  ///
  /// Re-reads both readiness probes whenever the boot bootstrap re-announces
  /// `setup.ready` (the event payload is only a hint), and advances
  /// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
  /// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
  ///
  /// Auto-disposed with its screen so it does not pin the instance connection.

  OnboardingProvider call(String instanceId) =>
      OnboardingProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'onboardingProvider';
}

/// Onboarding state machine of one instance, over its shared connection.
///
/// Re-reads both readiness probes whenever the boot bootstrap re-announces
/// `setup.ready` (the event payload is only a hint), and advances
/// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
/// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
///
/// Auto-disposed with its screen so it does not pin the instance connection.

abstract class _$Onboarding extends $AsyncNotifier<OnboardingState> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<OnboardingState> build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<OnboardingState>, OnboardingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<OnboardingState>, OnboardingState>,
              AsyncValue<OnboardingState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Authenticated REST client of one instance, borrowed from its live
/// [DashboardTransport]. Overridable for tests whose transport is a fake.

@ProviderFor(restClient)
final restClientProvider = RestClientFamily._();

/// Authenticated REST client of one instance, borrowed from its live
/// [DashboardTransport]. Overridable for tests whose transport is a fake.

final class RestClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<HermesRestClient>,
          HermesRestClient,
          FutureOr<HermesRestClient>
        >
    with $FutureModifier<HermesRestClient>, $FutureProvider<HermesRestClient> {
  /// Authenticated REST client of one instance, borrowed from its live
  /// [DashboardTransport]. Overridable for tests whose transport is a fake.
  RestClientProvider._({
    required RestClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'restClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$restClientHash();

  @override
  String toString() {
    return r'restClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<HermesRestClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<HermesRestClient> create(Ref ref) {
    final argument = this.argument as String;
    return restClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RestClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$restClientHash() => r'8d16d079fa3a7fb6642547053d20738e81274c93';

/// Authenticated REST client of one instance, borrowed from its live
/// [DashboardTransport]. Overridable for tests whose transport is a fake.

final class RestClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<HermesRestClient>, String> {
  RestClientFamily._()
    : super(
        retry: null,
        name: r'restClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Authenticated REST client of one instance, borrowed from its live
  /// [DashboardTransport]. Overridable for tests whose transport is a fake.

  RestClientProvider call(String instanceId) =>
      RestClientProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'restClientProvider';
}

/// The desktop CLIProxyAPI sidecar, or null where there is none (web/mobile:
/// bridge cards of an instance on this machine stay hidden; an instance on a
/// server signs in on its own bridge). The desktop app overrides this with a
/// [SupervisorBridgeHost] from `package:hermuse_host`.

@ProviderFor(bridgeHost)
final bridgeHostProvider = BridgeHostProvider._();

/// The desktop CLIProxyAPI sidecar, or null where there is none (web/mobile:
/// bridge cards of an instance on this machine stay hidden; an instance on a
/// server signs in on its own bridge). The desktop app overrides this with a
/// [SupervisorBridgeHost] from `package:hermuse_host`.

final class BridgeHostProvider
    extends $FunctionalProvider<BridgeHost?, BridgeHost?, BridgeHost?>
    with $Provider<BridgeHost?> {
  /// The desktop CLIProxyAPI sidecar, or null where there is none (web/mobile:
  /// bridge cards of an instance on this machine stay hidden; an instance on a
  /// server signs in on its own bridge). The desktop app overrides this with a
  /// [SupervisorBridgeHost] from `package:hermuse_host`.
  BridgeHostProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'bridgeHostProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$bridgeHostHash();

  @$internal
  @override
  $ProviderElement<BridgeHost?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BridgeHost? create(Ref ref) {
    return bridgeHost(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BridgeHost? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BridgeHost?>(value),
    );
  }
}

String _$bridgeHostHash() => r'e760e28ce8fd1313889b4ccf4598ac13ecd5044a';
