// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'computer.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Computer client of [instanceId], on its authenticated REST client.

@ProviderFor(computerClient)
final computerClientProvider = ComputerClientFamily._();

/// Computer client of [instanceId], on its authenticated REST client.

final class ComputerClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<ComputerClient>,
          ComputerClient,
          FutureOr<ComputerClient>
        >
    with $FutureModifier<ComputerClient>, $FutureProvider<ComputerClient> {
  /// Computer client of [instanceId], on its authenticated REST client.
  ComputerClientProvider._({
    required ComputerClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'computerClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$computerClientHash();

  @override
  String toString() {
    return r'computerClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<ComputerClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ComputerClient> create(Ref ref) {
    final argument = this.argument as String;
    return computerClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ComputerClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$computerClientHash() => r'8d76718a6fa53367806c84fc02acb6e588195b1f';

/// Computer client of [instanceId], on its authenticated REST client.

final class ComputerClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<ComputerClient>, String> {
  ComputerClientFamily._()
    : super(
        retry: null,
        name: r'computerClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Computer client of [instanceId], on its authenticated REST client.

  ComputerClientProvider call(String instanceId) =>
      ComputerClientProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'computerClientProvider';
}
