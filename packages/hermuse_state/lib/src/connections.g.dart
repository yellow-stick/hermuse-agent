// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connections.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Connection cards of one instance: data-driven descriptors plus the
/// device-code / API-key / custom-endpoint / disconnect actions.
///
/// Auto-disposed with its screen (it pins the instance connection while
/// alive); an in-flight login holds a keep-alive link until it settles.

@ProviderFor(ConnectionCards)
final connectionCardsProvider = ConnectionCardsFamily._();

/// Connection cards of one instance: data-driven descriptors plus the
/// device-code / API-key / custom-endpoint / disconnect actions.
///
/// Auto-disposed with its screen (it pins the instance connection while
/// alive); an in-flight login holds a keep-alive link until it settles.
final class ConnectionCardsProvider
    extends $AsyncNotifierProvider<ConnectionCards, ConnectionsState> {
  /// Connection cards of one instance: data-driven descriptors plus the
  /// device-code / API-key / custom-endpoint / disconnect actions.
  ///
  /// Auto-disposed with its screen (it pins the instance connection while
  /// alive); an in-flight login holds a keep-alive link until it settles.
  ConnectionCardsProvider._({
    required ConnectionCardsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'connectionCardsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$connectionCardsHash();

  @override
  String toString() {
    return r'connectionCardsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ConnectionCards create() => ConnectionCards();

  @override
  bool operator ==(Object other) {
    return other is ConnectionCardsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionCardsHash() => r'be5ce19b97a726b8bfde8c58cd52c0c116b3dc07';

/// Connection cards of one instance: data-driven descriptors plus the
/// device-code / API-key / custom-endpoint / disconnect actions.
///
/// Auto-disposed with its screen (it pins the instance connection while
/// alive); an in-flight login holds a keep-alive link until it settles.

final class ConnectionCardsFamily extends $Family
    with
        $ClassFamilyOverride<
          ConnectionCards,
          AsyncValue<ConnectionsState>,
          ConnectionsState,
          FutureOr<ConnectionsState>,
          String
        > {
  ConnectionCardsFamily._()
    : super(
        retry: null,
        name: r'connectionCardsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Connection cards of one instance: data-driven descriptors plus the
  /// device-code / API-key / custom-endpoint / disconnect actions.
  ///
  /// Auto-disposed with its screen (it pins the instance connection while
  /// alive); an in-flight login holds a keep-alive link until it settles.

  ConnectionCardsProvider call(String instanceId) =>
      ConnectionCardsProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'connectionCardsProvider';
}

/// Connection cards of one instance: data-driven descriptors plus the
/// device-code / API-key / custom-endpoint / disconnect actions.
///
/// Auto-disposed with its screen (it pins the instance connection while
/// alive); an in-flight login holds a keep-alive link until it settles.

abstract class _$ConnectionCards extends $AsyncNotifier<ConnectionsState> {
  late final _$args = ref.$arg as String;
  String get instanceId => _$args;

  FutureOr<ConnectionsState> build(String instanceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ConnectionsState>, ConnectionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ConnectionsState>, ConnectionsState>,
              AsyncValue<ConnectionsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
