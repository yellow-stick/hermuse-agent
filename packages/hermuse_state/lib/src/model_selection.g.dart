// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'model_selection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-provider model selection (≤2: newest large + newest small by default).
///
/// Discovery: native providers read their `model.options` row over the live
/// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
/// to the spec owners. The selection persists in the settings table under
/// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
/// stored id that vanished from discovery is dropped (never offered), and an
/// empty slot reverts to the newest discovered id of that tier on next load.
///
/// Only *connected* providers resolve: native cards in `connected` state,
/// bridge cards with usable sidecar credentials. Anything else throws
/// [StateError].

@ProviderFor(ModelSelectionState)
final modelSelectionProvider = ModelSelectionStateFamily._();

/// Per-provider model selection (≤2: newest large + newest small by default).
///
/// Discovery: native providers read their `model.options` row over the live
/// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
/// to the spec owners. The selection persists in the settings table under
/// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
/// stored id that vanished from discovery is dropped (never offered), and an
/// empty slot reverts to the newest discovered id of that tier on next load.
///
/// Only *connected* providers resolve: native cards in `connected` state,
/// bridge cards with usable sidecar credentials. Anything else throws
/// [StateError].
final class ModelSelectionStateProvider
    extends $AsyncNotifierProvider<ModelSelectionState, ModelSelection> {
  /// Per-provider model selection (≤2: newest large + newest small by default).
  ///
  /// Discovery: native providers read their `model.options` row over the live
  /// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
  /// to the spec owners. The selection persists in the settings table under
  /// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
  /// stored id that vanished from discovery is dropped (never offered), and an
  /// empty slot reverts to the newest discovered id of that tier on next load.
  ///
  /// Only *connected* providers resolve: native cards in `connected` state,
  /// bridge cards with usable sidecar credentials. Anything else throws
  /// [StateError].
  ModelSelectionStateProvider._({
    required ModelSelectionStateFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'modelSelectionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$modelSelectionStateHash();

  @override
  String toString() {
    return r'modelSelectionProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  ModelSelectionState create() => ModelSelectionState();

  @override
  bool operator ==(Object other) {
    return other is ModelSelectionStateProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$modelSelectionStateHash() =>
    r'ed5906b351f393b78e615946b368105582a3c832';

/// Per-provider model selection (≤2: newest large + newest small by default).
///
/// Discovery: native providers read their `model.options` row over the live
/// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
/// to the spec owners. The selection persists in the settings table under
/// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
/// stored id that vanished from discovery is dropped (never offered), and an
/// empty slot reverts to the newest discovered id of that tier on next load.
///
/// Only *connected* providers resolve: native cards in `connected` state,
/// bridge cards with usable sidecar credentials. Anything else throws
/// [StateError].

final class ModelSelectionStateFamily extends $Family
    with
        $ClassFamilyOverride<
          ModelSelectionState,
          AsyncValue<ModelSelection>,
          ModelSelection,
          FutureOr<ModelSelection>,
          (String, String)
        > {
  ModelSelectionStateFamily._()
    : super(
        retry: null,
        name: r'modelSelectionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Per-provider model selection (≤2: newest large + newest small by default).
  ///
  /// Discovery: native providers read their `model.options` row over the live
  /// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
  /// to the spec owners. The selection persists in the settings table under
  /// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
  /// stored id that vanished from discovery is dropped (never offered), and an
  /// empty slot reverts to the newest discovered id of that tier on next load.
  ///
  /// Only *connected* providers resolve: native cards in `connected` state,
  /// bridge cards with usable sidecar credentials. Anything else throws
  /// [StateError].

  ModelSelectionStateProvider call(String instanceId, String providerId) =>
      ModelSelectionStateProvider._(
        argument: (instanceId, providerId),
        from: this,
      );

  @override
  String toString() => r'modelSelectionProvider';
}

/// Per-provider model selection (≤2: newest large + newest small by default).
///
/// Discovery: native providers read their `model.options` row over the live
/// connection; bridge cards read the sidecar `/v1/models` catalogue filtered
/// to the spec owners. The selection persists in the settings table under
/// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
/// stored id that vanished from discovery is dropped (never offered), and an
/// empty slot reverts to the newest discovered id of that tier on next load.
///
/// Only *connected* providers resolve: native cards in `connected` state,
/// bridge cards with usable sidecar credentials. Anything else throws
/// [StateError].

abstract class _$ModelSelectionState extends $AsyncNotifier<ModelSelection> {
  late final _$args = ref.$arg as (String, String);
  String get instanceId => _$args.$1;
  String get providerId => _$args.$2;

  FutureOr<ModelSelection> build(String instanceId, String providerId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ModelSelection>, ModelSelection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ModelSelection>, ModelSelection>,
              AsyncValue<ModelSelection>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Flat chat-picker list: union of the ≤2 selected models of every connected
/// provider on [instanceId] (native + bridge). Providers whose selection
/// fails to load (disconnected mid-flight, empty discovery) are skipped, so
/// one broken provider never empties the picker.

@ProviderFor(availableModels)
final availableModelsProvider = AvailableModelsFamily._();

/// Flat chat-picker list: union of the ≤2 selected models of every connected
/// provider on [instanceId] (native + bridge). Providers whose selection
/// fails to load (disconnected mid-flight, empty discovery) are skipped, so
/// one broken provider never empties the picker.

final class AvailableModelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AvailableModel>>,
          List<AvailableModel>,
          FutureOr<List<AvailableModel>>
        >
    with
        $FutureModifier<List<AvailableModel>>,
        $FutureProvider<List<AvailableModel>> {
  /// Flat chat-picker list: union of the ≤2 selected models of every connected
  /// provider on [instanceId] (native + bridge). Providers whose selection
  /// fails to load (disconnected mid-flight, empty discovery) are skipped, so
  /// one broken provider never empties the picker.
  AvailableModelsProvider._({
    required AvailableModelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'availableModelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$availableModelsHash();

  @override
  String toString() {
    return r'availableModelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AvailableModel>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AvailableModel>> create(Ref ref) {
    final argument = this.argument as String;
    return availableModels(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AvailableModelsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$availableModelsHash() => r'83e697a95c54449fd36ebed1334de72f127561c1';

/// Flat chat-picker list: union of the ≤2 selected models of every connected
/// provider on [instanceId] (native + bridge). Providers whose selection
/// fails to load (disconnected mid-flight, empty discovery) are skipped, so
/// one broken provider never empties the picker.

final class AvailableModelsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<AvailableModel>>, String> {
  AvailableModelsFamily._()
    : super(
        retry: null,
        name: r'availableModelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Flat chat-picker list: union of the ≤2 selected models of every connected
  /// provider on [instanceId] (native + bridge). Providers whose selection
  /// fails to load (disconnected mid-flight, empty discovery) are skipped, so
  /// one broken provider never empties the picker.

  AvailableModelsProvider call(String instanceId) =>
      AvailableModelsProvider._(argument: instanceId, from: this);

  @override
  String toString() => r'availableModelsProvider';
}
