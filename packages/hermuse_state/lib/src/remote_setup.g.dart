// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_setup.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(remoteSetupTiming)
final remoteSetupTimingProvider = RemoteSetupTimingProvider._();

final class RemoteSetupTimingProvider
    extends
        $FunctionalProvider<
          RemoteSetupTiming,
          RemoteSetupTiming,
          RemoteSetupTiming
        >
    with $Provider<RemoteSetupTiming> {
  RemoteSetupTimingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteSetupTimingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteSetupTimingHash();

  @$internal
  @override
  $ProviderElement<RemoteSetupTiming> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RemoteSetupTiming create(Ref ref) {
    return remoteSetupTiming(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteSetupTiming value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteSetupTiming>(value),
    );
  }
}

String _$remoteSetupTimingHash() => r'b6829ad55a8f8aadce2294a51b1e9747684f5278';

/// The component checklist of the Hermes [instanceId] reaches over the
/// network: each part Hermuse needs there, found in place, or installed
/// through the Hermes dashboard and the Hermuse plugin (never a shell on the
/// server). What only the user can do (a command on the server, a consent,
/// a model to connect) says so, with the command to copy.
///
/// It looks as soon as it is read, after each install and on [checkAgain];
/// a computer being prepared is looked at every [RemoteSetupTiming.poll]
/// until it is ready or failed. Parts that need another one (the jobs, Docker
/// and the computer need the plugin; the computer needs Docker) wait for it.
/// One install runs at a time.

@ProviderFor(RemoteSetup)
final remoteSetupProvider = RemoteSetupFamily._();

/// The component checklist of the Hermes [instanceId] reaches over the
/// network: each part Hermuse needs there, found in place, or installed
/// through the Hermes dashboard and the Hermuse plugin (never a shell on the
/// server). What only the user can do (a command on the server, a consent,
/// a model to connect) says so, with the command to copy.
///
/// It looks as soon as it is read, after each install and on [checkAgain];
/// a computer being prepared is looked at every [RemoteSetupTiming.poll]
/// until it is ready or failed. Parts that need another one (the jobs, Docker
/// and the computer need the plugin; the computer needs Docker) wait for it.
/// One install runs at a time.
final class RemoteSetupProvider
    extends $NotifierProvider<RemoteSetup, RemoteSetupState> {
  /// The component checklist of the Hermes [instanceId] reaches over the
  /// network: each part Hermuse needs there, found in place, or installed
  /// through the Hermes dashboard and the Hermuse plugin (never a shell on the
  /// server). What only the user can do (a command on the server, a consent,
  /// a model to connect) says so, with the command to copy.
  ///
  /// It looks as soon as it is read, after each install and on [checkAgain];
  /// a computer being prepared is looked at every [RemoteSetupTiming.poll]
  /// until it is ready or failed. Parts that need another one (the jobs, Docker
  /// and the computer need the plugin; the computer needs Docker) wait for it.
  /// One install runs at a time.
  RemoteSetupProvider._({
    required RemoteSetupFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'remoteSetupProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$remoteSetupHash();

  @override
  String toString() {
    return r'remoteSetupProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RemoteSetup create() => RemoteSetup();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteSetupState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteSetupState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RemoteSetupProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$remoteSetupHash() => r'59cf948da1cfc26bdf9e204a995a9bd8227732d0';

/// The component checklist of the Hermes [instanceId] reaches over the
/// network: each part Hermuse needs there, found in place, or installed
/// through the Hermes dashboard and the Hermuse plugin (never a shell on the
/// server). What only the user can do (a command on the server, a consent,
/// a model to connect) says so, with the command to copy.
///
/// It looks as soon as it is read, after each install and on [checkAgain];
/// a computer being prepared is looked at every [RemoteSetupTiming.poll]
/// until it is ready or failed. Parts that need another one (the jobs, Docker
/// and the computer need the plugin; the computer needs Docker) wait for it.
/// One install runs at a time.

final class RemoteSetupFamily extends $Family
    with
        $ClassFamilyOverride<
          RemoteSetup,
          RemoteSetupState,
          RemoteSetupState,
          RemoteSetupState,
          String
        > {
  RemoteSetupFamily._()
    : super(
        retry: null,
        name: r'remoteSetupProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The component checklist of the Hermes [instanceId] reaches over the
  /// network: each part Hermuse needs there, found in place, or installed
  /// through the Hermes dashboard and the Hermuse plugin (never a shell on the
  /// server). What only the user can do (a command on the server, a consent,
  /// a model to connect) says so, with the command to copy.
  ///
  /// It looks as soon as it is read, after each install and on [checkAgain];
  /// a computer being prepared is looked at every [RemoteSetupTiming.poll]
  /// until it is ready or failed. Parts that need another one (the jobs, Docker
  /// and the computer need the plugin; the computer needs Docker) wait for it.
  /// One install runs at a time.

  RemoteSetupProvider call(String instanceId) =>
      RemoteSetupProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'remoteSetupProvider';
}

/// The component checklist of the Hermes [instanceId] reaches over the
/// network: each part Hermuse needs there, found in place, or installed
/// through the Hermes dashboard and the Hermuse plugin (never a shell on the
/// server). What only the user can do (a command on the server, a consent,
/// a model to connect) says so, with the command to copy.
///
/// It looks as soon as it is read, after each install and on [checkAgain];
/// a computer being prepared is looked at every [RemoteSetupTiming.poll]
/// until it is ready or failed. Parts that need another one (the jobs, Docker
/// and the computer need the plugin; the computer needs Docker) wait for it.
/// One install runs at a time.

abstract class _$RemoteSetup extends $Notifier<RemoteSetupState> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  RemoteSetupState build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RemoteSetupState, RemoteSetupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RemoteSetupState, RemoteSetupState>,
              RemoteSetupState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
