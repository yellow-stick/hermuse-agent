// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_sign_in.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The dashboard account saved for [instanceId], so its owner can read it
/// again (to sign in from another computer or the web app). Null when the
/// instance does not sign in with a password or this app holds none (the
/// web app keeps secrets for the tab only). Read from the [SecretStore] on
/// demand and dropped once nothing shows it.

@ProviderFor(savedSignIn)
final savedSignInProvider = SavedSignInFamily._();

/// The dashboard account saved for [instanceId], so its owner can read it
/// again (to sign in from another computer or the web app). Null when the
/// instance does not sign in with a password or this app holds none (the
/// web app keeps secrets for the tab only). Read from the [SecretStore] on
/// demand and dropped once nothing shows it.

final class SavedSignInProvider
    extends
        $FunctionalProvider<
          AsyncValue<SavedSignIn?>,
          SavedSignIn?,
          FutureOr<SavedSignIn?>
        >
    with $FutureModifier<SavedSignIn?>, $FutureProvider<SavedSignIn?> {
  /// The dashboard account saved for [instanceId], so its owner can read it
  /// again (to sign in from another computer or the web app). Null when the
  /// instance does not sign in with a password or this app holds none (the
  /// web app keeps secrets for the tab only). Read from the [SecretStore] on
  /// demand and dropped once nothing shows it.
  SavedSignInProvider._({
    required SavedSignInFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'savedSignInProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$savedSignInHash();

  @override
  String toString() {
    return r'savedSignInProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<SavedSignIn?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<SavedSignIn?> create(Ref ref) {
    final argument = this.argument as String;
    return savedSignIn(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is SavedSignInProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$savedSignInHash() => r'bbd43cf4e4bf12736346a6cd9b519a9b054696a1';

/// The dashboard account saved for [instanceId], so its owner can read it
/// again (to sign in from another computer or the web app). Null when the
/// instance does not sign in with a password or this app holds none (the
/// web app keeps secrets for the tab only). Read from the [SecretStore] on
/// demand and dropped once nothing shows it.

final class SavedSignInFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<SavedSignIn?>, String> {
  SavedSignInFamily._()
    : super(
        retry: null,
        name: r'savedSignInProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The dashboard account saved for [instanceId], so its owner can read it
  /// again (to sign in from another computer or the web app). Null when the
  /// instance does not sign in with a password or this app holds none (the
  /// web app keeps secrets for the tab only). Read from the [SecretStore] on
  /// demand and dropped once nothing shows it.

  SavedSignInProvider call(String instanceId) =>
      SavedSignInProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'savedSignInProvider';
}
