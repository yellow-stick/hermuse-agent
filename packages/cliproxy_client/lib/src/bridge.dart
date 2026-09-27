import 'package:cliproxy_client/cliproxy_client.dart';

/// Read-only view of the CLIProxyAPI sidecar a bridge login needs.
///
/// Lives in `cliproxy_client` (pure Dart, no `dart:io`, no Riverpod) so both
/// the state layer (`hermuse_state`, web-safe) and the desktop host layer
/// (`hermuse_host`, `dart:io`) can depend on it without a dependency cycle:
///
/// ```text
/// hermuse_state ──▶ cliproxy_client ◀── hermuse_host
///       (web-safe)      (pure)            (dart:io)
/// ```
///
/// `hermuse_host` must never be imported by `hermuse_state` (it pulls in
/// `dart:io`, which breaks the Jaspr web build); `hermuse_state` must not be
/// imported by `hermuse_host` either, or the desktop app could not override
/// the provider without dragging Riverpod state into the host layer. The
/// interface in the shared leaf package keeps both directions clean.
abstract interface class BridgeHost {
  /// Starts the sidecar unless already running; returns its origin plus the
  /// two keys a bridge login needs.
  Future<BridgeConnection> ensureStarted();
}

/// What [BridgeHost.ensureStarted] resolves to.
final class BridgeConnection {
  const BridgeConnection({
    required this.baseUrl,
    required this.apiKey,
    required this.managementKey,
  });

  /// Sidecar origin, e.g. `http://127.0.0.1:8317`.
  final Uri baseUrl;

  /// Bearer key for the sidecar's `/v1/*` routes: persisted into the Hermes
  /// custom-endpoint entry (via its `key_env` indirection, never plaintext).
  final String apiKey;

  /// Key for the `/v0/management/*` API (used with [CliproxyManagement]).
  final String managementKey;
}

/// Subscription providers the bridge can sign in, in card order.
const bridgeProviders = CliproxyProvider.values;

/// Display metadata of one bridge card: endpoint name, Hermes `external`
/// provider ids routed to it, the auth-file `provider` strings that mark it
/// connected, and the `/v1/models` `owned_by` values that select its models.
final class BridgeCardSpec {
  const BridgeCardSpec({
    required this.provider,
    required this.label,
    required this.hermesIds,
    required this.authFileProviders,
    required this.modelOwners,
  });

  final CliproxyProvider provider;
  final String label;

  /// Hermes `/api/providers/oauth` ids whose `external` flow this card
  /// replaces (terminal-only upstream; bridgeable via the sidecar).
  final List<String> hermesIds;

  /// CLIProxyAPI auth-file `provider` values counting as connected.
  final List<String> authFileProviders;

  /// `/v1/models` `owned_by` values selecting this card's models. No model
  /// ids are hardcoded anywhere: registration always uses ids the sidecar
  /// actually advertises for these owners.
  final List<String> modelOwners;

  /// Card id: `bridge:<route-without--auth-url>`, e.g. `bridge:meta`.
  String get cardId => 'bridge:${provider.route.replaceFirst('-auth-url', '')}';
}

/// Card specs for every bridgeable subscription, in display order.
///
/// `authFileProviders` are the exact `auth.Provider` strings CLIProxyAPI
/// v7.3.18 writes into credential files (see `Request<Provider>Token` in
/// `auth_files_provider_oauth.go`: `claude`, `codex`, `meta`, `antigravity`,
/// `kimi`/`kimi-ai`, `devin`, `xai`). `modelOwners` are the `/v1/models`
/// `owned_by` values from the embedded catalogue
/// (`internal/registry/models/models.json`): `anthropic`, `openai`, `meta`,
/// `antigravity`, `moonshot`, `xai`. Devin has no catalogue section, so its
/// card falls back to unfiltered discovery.
const bridgeCardSpecs = [
  BridgeCardSpec(
    provider: CliproxyProvider.anthropic,
    label: 'Claude Pro/Max (bridge)',
    hermesIds: ['anthropic', 'claude-code'],
    authFileProviders: ['claude'],
    modelOwners: ['anthropic'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.codex,
    label: 'ChatGPT (bridge)',
    hermesIds: ['openai-codex'],
    authFileProviders: ['codex'],
    modelOwners: ['openai'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.meta,
    label: 'Meta (bridge)',
    hermesIds: [],
    authFileProviders: ['meta'],
    modelOwners: ['meta'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.antigravity,
    label: 'Antigravity (bridge)',
    hermesIds: [],
    authFileProviders: ['antigravity'],
    modelOwners: ['antigravity'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.kimi,
    label: 'Kimi (bridge)',
    hermesIds: [],
    authFileProviders: ['kimi'],
    modelOwners: ['moonshot'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.kimiAi,
    label: 'Kimi.ai (bridge)',
    hermesIds: [],
    authFileProviders: ['kimi-ai'],
    modelOwners: ['moonshot'],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.devin,
    label: 'Devin (bridge)',
    hermesIds: [],
    authFileProviders: ['devin'],
    modelOwners: [],
  ),
  BridgeCardSpec(
    provider: CliproxyProvider.xai,
    label: 'xAI (bridge)',
    hermesIds: ['xai-oauth'],
    authFileProviders: ['xai'],
    modelOwners: ['xai'],
  ),
];

/// Spec for a card id (`bridge:<slug>`), or null.
BridgeCardSpec? bridgeSpecForCard(String cardId) =>
    bridgeCardSpecs.where((s) => s.cardId == cardId).firstOrNull;

/// Spec routed from a Hermes `external` provider id, or null.
BridgeCardSpec? bridgeSpecForHermes(String hermesId) =>
    bridgeCardSpecs.where((s) => s.hermesIds.contains(hermesId)).firstOrNull;
