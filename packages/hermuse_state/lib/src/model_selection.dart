import 'dart:async';
import 'dart:convert';

import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'connections.dart';
import 'model_tiers.dart';
import 'onboarding.dart';
import 'providers.dart';
import 'server_bridge.dart';

part 'model_selection.g.dart';

/// One provider's models, tiered and ranked, with the user's ≤2 selection.
///
/// [providerId] is the card id: a Hermes slug (`anthropic`, `zai`, …), a
/// custom endpoint card (`custom:<slug>`, sent to Hermes as `<slug>`, see
/// [hermesProviderId]) or a bridge card id (`bridge:meta`, …). [allModels]
/// is the full discovered list (native and custom endpoints: the
/// `model.options` row; bridge: `/v1/models` of the bridge serving the
/// instance, filtered to the spec owners); [large]/[small] hold at most one
/// id each — the current selection, defaulting to the newest large + newest
/// small (a custom endpoint: the model it was saved with as large).
final class ModelSelection {
  const ModelSelection({
    required this.providerId,
    required this.providerName,
    required this.allModels,
    required this.tiers,
    this.large,
    this.small,
  });

  factory ModelSelection.fromJson(
    String providerId,
    String providerName,
    List<String> allModels,
    Map<String, Object?> json,
  ) {
    final tiers = {for (final id in allModels) id: classifyModel(id)};
    String? pick(String key) {
      final id = json[key] as String?;
      return id != null && allModels.contains(id) ? id : null;
    }

    return ModelSelection(
      providerId: providerId,
      providerName: providerName,
      allModels: allModels,
      tiers: tiers,
      large: pick('large'),
      small: pick('small'),
    );
  }

  final String providerId;
  final String providerName;
  final List<String> allModels;
  final Map<String, ModelTier> tiers;
  final String? large;
  final String? small;

  /// Ids actually offered to the chat picker (≤2, large first).
  List<String> get selected => [
    ?large,
    if (small != null && small != large) small!,
  ];

  Map<String, Object?> toJson() => {
    if (large != null) 'large': large,
    if (small != null) 'small': small,
  };

  ModelSelection copyWith({
    String? Function()? large,
    String? Function()? small,
  }) => ModelSelection(
    providerId: providerId,
    providerName: providerName,
    allModels: allModels,
    tiers: tiers,
    large: large == null ? this.large : large(),
    small: small == null ? this.small : small(),
  );
}

/// One entry of the flat chat-picker list.
final class AvailableModel {
  const AvailableModel({
    required this.providerId,
    required this.providerName,
    required this.modelId,
    required this.tier,
  });

  /// The provider as Hermes resolves it (`ChatModel.provider`): a custom
  /// endpoint's slug, not its `custom:` card id ([hermesProviderId]).
  final String providerId;
  final String providerName;
  final String modelId;
  final ModelTier tier;
}

/// Per-provider model selection (≤2: newest large + newest small by default).
///
/// Discovery: native providers read their `model.options` row over the live
/// connection; bridge cards read the `/v1/models` catalogue of the bridge
/// serving the instance (this desktop's sidecar, or the bridge of the
/// Hermuse plugin on its server — see [bridgeOnServer]) filtered to the spec
/// owners. The selection persists in the settings table under
/// `model_selection:<instanceId>:<providerId>` as `{large?, small?}`; a
/// stored id that vanished from discovery is dropped (never offered), and an
/// empty slot reverts to the newest discovered id of that tier on next load.
///
/// Only *connected* providers resolve: native cards in `connected` state,
/// bridge cards with usable bridge credentials. Anything else throws
/// [StateError].
@Riverpod(name: 'modelSelectionProvider')
class ModelSelectionState extends _$ModelSelectionState {
  @override
  Future<ModelSelection> build(
    String instanceId,
    String providerId, {
    String profile = 'default',
  }) async {
    final db = ref.watch(hermuseDatabaseProvider);
    final cards = await ref.watch(connectionCardsProvider(instanceId).future);
    final card = cards.cards.where((c) => c.id == providerId).firstOrNull;
    if (card == null) throw StateError('unknown provider $providerId');
    if (card.state != ConnectionCardState.connected) {
      throw StateError('$providerId is not connected');
    }
    final models = await _discoverModels(card);
    final saved = await db.readSetting(_key(instanceId, providerId, profile));
    final stored = saved == null
        ? const <String, Object?>{}
        : jsonDecode(saved) as Map<String, Object?>;
    var selection = ModelSelection.fromJson(
      providerId,
      card.name,
      models,
      stored,
    );
    // Fill empty slots: a custom endpoint's large slot is the model it was
    // saved with; otherwise the newest discovered id of that tier.
    final defaults = pickLargeAndSmall(models);
    final configured =
        card.flow == ConnectionFlow.customEndpoint &&
            models.contains(card.defaultModel)
        ? card.defaultModel
        : null;
    if (selection.large == null && (configured ?? defaults.large) != null) {
      selection = selection.copyWith(large: () => configured ?? defaults.large);
    }
    if (selection.small == null &&
        defaults.small != null &&
        defaults.small != selection.large) {
      selection = selection.copyWith(small: () => defaults.small);
    }
    return selection;
  }

  static String _key(String instanceId, String providerId, String profile) =>
      profile == 'default'
      ? 'model_selection:$instanceId:$providerId'
      : 'model_selection:$instanceId:profile:'
            '${Uri.encodeComponent(profile)}:$providerId';

  /// User override of one slot. [modelId] must belong to this
  /// provider's discovered list; null clears the slot.
  Future<void> select(ModelTier tier, String? modelId) async {
    final current = state.value;
    if (current == null) throw StateError('selection is still loading');
    if (modelId != null && !current.allModels.contains(modelId)) {
      throw ArgumentError.value(modelId, 'modelId', 'not a discovered model');
    }
    ModelSelection next;
    if (tier == ModelTier.large) {
      next = current.copyWith(large: () => modelId);
    } else if (tier == ModelTier.small) {
      next = current.copyWith(small: () => modelId);
    } else {
      throw ArgumentError.value(tier, 'tier', 'large or small');
    }
    // Max 2, and both slots may never hold the same id: setting a slot to
    // the other slot's id clears the other slot.
    if (next.large != null && next.large == next.small) {
      next = tier == ModelTier.large
          ? next.copyWith(small: () => null)
          : next.copyWith(large: () => null);
    }
    state = AsyncData(next);
    await ref
        .read(hermuseDatabaseProvider)
        .writeSetting(
          _key(instanceId, providerId, profile),
          jsonEncode(next.toJson()),
        );
  }

  /// Clears one slot (it reverts to the newest discovered id on next load).
  Future<void> clear(ModelTier tier) => select(tier, null);

  /// Makes this provider the instance default: large → main slot
  /// (`POST /api/model/set`, scope `main`), small → every auxiliary slot
  /// (scope `auxiliary`, empty task = all slots). For bridge cards the
  /// Hermes custom endpoint is first re-registered with exactly the ≤2
  /// selected models, at the bridge serving the instance. Custom endpoints,
  /// bridges included, are referenced by their `providers.<key>` in Hermes:
  /// [hermesProviderId] for a saved endpoint, the `id` the registration
  /// answers for a bridge (its display name is no provider id).
  ///
  /// Hermes guards expensive and data-training models: it answers
  /// `confirm_required` and changes nothing. That throws
  /// [ExpensiveModelConfirmation] with its message; call again with
  /// [confirmExpensiveModel] once the user agreed. Any other `ok: false`
  /// throws [ConnectionRejected].
  Future<void> makeDefault({bool confirmExpensiveModel = false}) async {
    final current = state.value;
    if (current == null) throw StateError('selection is still loading');
    final large = current.large;
    if (large == null) throw StateError('no large model selected');
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    Future<void> assign(Map<String, Object?> body) async {
      final response = await rest.postJson('/api/model/set', {
        ...body,
        if (confirmExpensiveModel) 'confirm_expensive_model': true,
      });
      if (response['confirm_required'] == true) {
        throw ExpensiveModelConfirmation(
          message:
              response['confirm_message'] as String? ??
              'This model needs your confirmation.',
        );
      }
      if (response['ok'] == false) {
        throw ConnectionRejected(
          response['message'] as String? ??
              response['error'] as String? ??
              'Hermes did not change the model.',
        );
      }
    }

    final spec = bridgeSpecForCard(providerId);
    final String provider;
    Uri? bridgeUrl;
    if (spec != null) {
      final bridge = await _bridge(
        await ref.read(restClientProvider(instanceId).future),
      );
      bridgeUrl = bridge.baseUrl.replace(path: '/v1');
      final registered = await rest.postJson(
        '/api/providers/custom-endpoints',
        hermesCustomEndpoint(
          cliproxyBaseUrl: bridge.baseUrl,
          apiKey: bridge.apiKey,
          name: spec.label,
          model: large,
          models: current.selected,
          chatCompletionsPath: true,
        ),
      );
      final key = registered['id'];
      if (key is! String || key.isEmpty) {
        throw ConnectionRejected(
          'Hermes saved ${spec.label} without saying how to name it.',
        );
      }
      provider = key;
      await assign({
        'scope': 'main',
        'provider': provider,
        'model': large,
        'base_url': bridgeUrl.toString(),
        'api_key': bridge.apiKey,
      });
    } else {
      provider = hermesProviderId(providerId);
      await assign({'scope': 'main', 'provider': provider, 'model': large});
    }
    final small = current.small;
    if (small != null) {
      await assign({
        'scope': 'auxiliary',
        'provider': provider,
        'model': small,
        if (bridgeUrl != null) 'base_url': bridgeUrl.toString(),
      });
    }
    // The cards mark the provider now running the main model.
    for (final refresh in [
      ref.read(connectionCardsProvider(instanceId).notifier).refresh,
      ref.read(onboardingProvider(instanceId).notifier).refresh,
    ]) {
      unawaited(refresh().then((_) {}, onError: (_) {}));
    }
  }

  /// Whether the instance's bridge cards use the bridge on its server.
  Future<bool> _bridgeOnServer() async => bridgeOnServer(
    (await ref.read(registryProvider.future)).byId(instanceId),
  );

  /// Where Hermes reaches the bridge serving this instance: the bridge of
  /// the Hermuse plugin on its server, or this desktop's sidecar.
  Future<({Uri baseUrl, String apiKey})> _bridge(HermesRestClient rest) async {
    if (await _bridgeOnServer()) {
      final bridge = await ServerBridgeClient(rest).ensure();
      return (baseUrl: bridge.baseUrl, apiKey: bridge.apiKey);
    }
    final host = ref.read(bridgeHostProvider);
    if (host == null) {
      throw UnsupportedError('no subscription-bridge host on this platform');
    }
    final sidecar = await host.ensureStarted();
    return (baseUrl: sidecar.baseUrl, apiKey: sidecar.apiKey);
  }

  Future<List<String>> _discoverModels(ConnectionCard card) async {
    final spec = card.bridgeSpec ?? bridgeSpecForCard(card.id);
    if (spec != null) {
      final List<SidecarModel> catalogue;
      if (await _bridgeOnServer()) {
        final rest = await ref.read(restClientProvider(instanceId).future);
        catalogue = await ServerBridgeClient(rest).models();
      } else {
        final host = ref.read(bridgeHostProvider);
        if (host == null) return const [];
        final sidecar = await host.ensureStarted();
        catalogue = await CliproxyManagement(
          ref.read(httpClientProvider),
          baseUrl: sidecar.baseUrl,
          managementKey: sidecar.managementKey,
        ).listModels(apiKey: sidecar.apiKey);
      }
      return {
        for (final model in catalogue)
          if (model.id.isNotEmpty &&
              isSelectableModelId(model.id) &&
              (spec.modelOwners.isEmpty ||
                  (model.ownedBy != null &&
                      spec.modelOwners.contains(model.ownedBy))))
            model.id,
      }.toList();
    }
    final connection = await ref.read(
      connectionProvider(instanceId, profile: profile).future,
    );
    final options = await connection.transport.call(
      HermesMethods.modelOptions,
      const ModelOptionsParams(),
    );
    final row = options.providers
        .where((p) => p.slug == card.hermesProvider)
        .firstOrNull;
    // A custom endpoint is a `model.options` row under its slug; its own
    // saved list stands in when the row is missing, and the model it was
    // saved with is always offered.
    return {
      if (card.flow == ConnectionFlow.customEndpoint &&
          card.defaultModel.isNotEmpty)
        card.defaultModel,
      for (final id
          in row?.models ??
              (card.flow == ConnectionFlow.customEndpoint
                  ? card.models
                  : const <String>[]))
        if (isSelectableModelId(id)) id,
    }.toList();
  }
}

/// Flat chat-picker list: union of the ≤2 selected models of every connected
/// provider on [instanceId] (native + bridge). Providers whose selection
/// fails to load (disconnected mid-flight, empty discovery) are skipped, so
/// one broken provider never empties the picker.
@riverpod
Future<List<AvailableModel>> availableModels(
  Ref ref,
  String instanceId, {
  String profile = 'default',
}) async {
  final cards = await ref.watch(connectionCardsProvider(instanceId).future);
  final models = <AvailableModel>[];
  for (final card in cards.cards) {
    if (card.state != ConnectionCardState.connected) continue;
    // Only providers with a model list: native inventory rows (any flow —
    // `anthropic` is `external` upstream yet serves models), bridge cards,
    // and custom endpoints. Pure terminal cards without inventory rows are
    // skipped by the empty discovery inside the selection provider.
    if (card.flow != ConnectionFlow.apiKey &&
        card.flow != ConnectionFlow.deviceCode &&
        card.flow != ConnectionFlow.external &&
        card.flow != ConnectionFlow.bridge &&
        card.flow != ConnectionFlow.customEndpoint) {
      continue;
    }
    try {
      final selection = await ref.watch(
        modelSelectionProvider(instanceId, card.id, profile: profile).future,
      );
      for (final id in selection.selected) {
        models.add(
          AvailableModel(
            providerId: card.hermesProvider,
            providerName: card.name,
            modelId: id,
            tier: selection.tiers[id] ?? ModelTier.unknown,
          ),
        );
      }
    } on Object {
      continue;
    }
  }
  return models;
}
