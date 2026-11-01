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
    required (String, {String profile}) super.argument,
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
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<ComputerClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<ComputerClient> create(Ref ref) {
    final argument = this.argument as (String, {String profile});
    return computerClient(ref, argument.$1, profile: argument.profile);
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

String _$computerClientHash() => r'80fec40f728c17bf5ea14ee8ca56b0d34dd22b05';

/// Computer client of [instanceId], on its authenticated REST client.

final class ComputerClientFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<ComputerClient>,
          (String, {String profile})
        > {
  ComputerClientFamily._()
    : super(
        retry: null,
        name: r'computerClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Computer client of [instanceId], on its authenticated REST client.

  ComputerClientProvider call(
    String instanceId, {
    String profile = 'default',
  }) => ComputerClientProvider._(
    argument: (instanceId, profile: profile),
    from: this,
  );

  @override
  String toString() => r'computerClientProvider';
}
