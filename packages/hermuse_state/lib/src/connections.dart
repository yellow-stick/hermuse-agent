import 'dart:async';
import 'dart:convert';

import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'model_tiers.dart';
import 'onboarding.dart';
import 'providers.dart';
import 'server_bridge.dart';

part 'connections.g.dart';

/// The server or provider refused an action; [message] is its sentence,
/// shown to the user as is.
final class ConnectionRejected implements Exception {
  const ConnectionRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

/// How a connection card authenticates.
enum ConnectionFlow {
  /// OAuth device-code flow (`POST …/start`, show code + URL, poll).
  deviceCode,

  /// API-key entry (`POST /api/providers/validate`, then `model.save_key`).
  apiKey,

  /// OpenAI-compatible endpoint (`POST /api/providers/custom-endpoints`).
  customEndpoint,

  /// Delegated to a terminal/CLI (`cli_command`); Hermes `/start` refuses it.
  external,

  /// Subscription login via the CLIProxyAPI sidecar (desktop only).
  bridge,
}

/// Login state of a connection card.
enum ConnectionCardState {
  connected,
  disconnected,

  /// A device-code login is in flight for this card.
  pending,
  error,
}

/// One model-account card of the Connexions page, driven by server data.
///
/// Cards merge `GET /api/providers/oauth` (flows, status, disconnect hints)
/// with `GET /api/credentials/pool` (per-provider pooled credentials) and the
/// `model.options` inventory rows (`auth_type`/`key_env` hints for API keys).
/// Unknown provider ids render as a generic card instead of failing.
final class ConnectionCard {
  const ConnectionCard({
    required this.id,
    required this.name,
    required this.logoKey,
    required this.flow,
    required this.state,
    this.detail = '',
    this.status,
    this.cliCommand = '',
    this.docsUrl = '',
    this.disconnectHint = '',
    this.disconnectable = true,
    this.disconnectCommand,
    this.poolEntries = const [],
    this.keyEnv = '',
    this.advanced = false,
    this.bridgeSpec,
    this.onServer = false,
    this.needsPlugin = false,
  });

  /// Provider id (`nous`, `openai-codex`, `openai-api`, `custom:<id>`, …).
  final String id;

  /// Display name from the OAuth catalog or inventory row.
  final String name;

  /// Asset key for the provider logo (`logos/<logoKey>`; id when unknown).
  final String logoKey;

  final ConnectionFlow flow;
  final ConnectionCardState state;

  /// One-line subtitle: source label, key hint, error or progress message.
  final String detail;

  /// Raw `status` card of `GET /api/providers/oauth` when present.
  final Map<String, Object?>? status;

  /// Terminal sign-in command for [ConnectionFlow.external] cards.
  final String cliCommand;

  final String docsUrl;

  /// Why this card cannot be disconnected automatically ('' when it can).
  final String disconnectHint;

  final bool disconnectable;

  /// Shell command to run for external-provider cleanup, when the server
  /// offers one (`claude-code` keychain/file removal).
  final String? disconnectCommand;

  /// Redacted pooled credentials of `GET /api/credentials/pool`.
  final List<PoolEntry> poolEntries;

  /// Env var an API key is saved to (from `model.options` `key_env`).
  final String keyEnv;

  /// True for subscription-bridge cards: using a consumer subscription
  /// outside the vendor's official clients may breach the vendor ToS and can
  /// break without notice. The UI marks these `advanced` / personal-use.
  final bool advanced;

  /// Bridge spec for [ConnectionFlow.bridge] cards, null otherwise.
  final BridgeCardSpec? bridgeSpec;

  /// True for bridge cards of an instance on a server: the subscription
  /// account lives in the bridge of the Hermuse plugin there (see
  /// [bridgeOnServer]), not in this desktop's sidecar.
  final bool onServer;

  /// True for a server bridge card whose server lacks a Hermuse plugin with
  /// the bridge: [detail] says whether to install or update it, which the
  /// server's setup checklist does.
  final bool needsPlugin;

  ConnectionCard copyWith({
    String? name,
    String? logoKey,
    ConnectionFlow? flow,
    ConnectionCardState? state,
    String? detail,
    Map<String, Object?>? Function()? status,
    String? cliCommand,
    String? docsUrl,
    String? disconnectHint,
    bool? disconnectable,
    String? Function()? disconnectCommand,
    List<PoolEntry>? poolEntries,
    String? keyEnv,
    bool? advanced,
    BridgeCardSpec? Function()? bridgeSpec,
    bool? onServer,
    bool? needsPlugin,
  }) => ConnectionCard(
    id: id,
    name: name ?? this.name,
    logoKey: logoKey ?? this.logoKey,
    flow: flow ?? this.flow,
    state: state ?? this.state,
    detail: detail ?? this.detail,
    status: status == null ? this.status : status(),
    cliCommand: cliCommand ?? this.cliCommand,
    docsUrl: docsUrl ?? this.docsUrl,
    disconnectHint: disconnectHint ?? this.disconnectHint,
    disconnectable: disconnectable ?? this.disconnectable,
    disconnectCommand: disconnectCommand == null
        ? this.disconnectCommand
        : disconnectCommand(),
    poolEntries: poolEntries ?? this.poolEntries,
    keyEnv: keyEnv ?? this.keyEnv,
    advanced: advanced ?? this.advanced,
    bridgeSpec: bridgeSpec == null ? this.bridgeSpec : bridgeSpec(),
    onServer: onServer ?? this.onServer,
    needsPlugin: needsPlugin ?? this.needsPlugin,
  );
}

/// One redacted credential-pool entry (index is 1-based, as listed).
final class PoolEntry {
  const PoolEntry({
    required this.index,
    required this.id,
    required this.label,
    required this.authType,
    required this.source,
    this.tokenPreview = '',
    this.hasRefresh = false,
  });

  factory PoolEntry.fromJson(Map<String, Object?> json) => PoolEntry(
    index: (json['index'] as num).toInt(),
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    authType: json['auth_type'] as String? ?? '',
    source: json['source'] as String? ?? '',
    tokenPreview: json['token_preview'] as String? ?? '',
    hasRefresh: json['has_refresh'] as bool? ?? false,
  );

  final int index;
  final String id;
  final String label;
  final String authType;
  final String source;
  final String tokenPreview;
  final bool hasRefresh;
}

/// An in-flight device-code login: what the UI shows while polling.
final class DeviceCodeLogin {
  const DeviceCodeLogin({
    required this.providerId,
    required this.sessionId,
    required this.userCode,
    required this.verificationUrl,
    this.expiresIn = 0,
    this.pollInterval = const Duration(seconds: 5),
  });

  factory DeviceCodeLogin.fromStart(
    String providerId,
    Map<String, Object?> start,
  ) => DeviceCodeLogin(
    providerId: providerId,
    sessionId: start['session_id'] as String,
    userCode: start['user_code'] as String? ?? '',
    verificationUrl: start['verification_url'] as String? ?? '',
    expiresIn: (start['expires_in'] as num?)?.toInt() ?? 0,
    pollInterval: Duration(
      seconds: (start['poll_interval'] as num?)?.toInt() ?? 5,
    ),
  );

  final String providerId;
  final String sessionId;
  final String userCode;
  final String verificationUrl;
  final int expiresIn;
  final Duration pollInterval;
}

/// An in-flight subscription-bridge login: what the UI shows while polling.
final class BridgeLogin {
  const BridgeLogin({
    required this.cardId,
    required this.provider,
    required this.url,
    required this.state,
    required this.deviceFlow,
    this.userCode,
    this.expiresIn,
  });

  factory BridgeLogin.fromStart(
    String cardId,
    CliproxyProvider provider,
    AuthStart start,
  ) => BridgeLogin(
    cardId: cardId,
    provider: provider,
    url: start.url,
    state: start.state,
    deviceFlow: start.flow == AuthFlow.device,
    userCode: start.userCode,
    expiresIn: start.expiresIn,
  );

  /// Bridge card id (`bridge:<slug>`).
  final String cardId;
  final CliproxyProvider provider;

  /// Where the user completes the login (browser URL or device page).
  final String url;

  /// Opaque sidecar session id for polling/cancel.
  final String state;
  final bool deviceFlow;
  final String? userCode;
  final int? expiresIn;
}

/// Terminal bridge-login poll outcome.
enum BridgePollOutcome { ok, error, cancelled, timeout }

/// What a bridge-login poll loop settled to.
final class BridgePollResult {
  const BridgePollResult(this.outcome, {this.message = ''});

  final BridgePollOutcome outcome;
  final String message;
}

/// Terminal device-code poll outcome.
enum DevicePollOutcome { approved, denied, expired, error, cancelled, timeout }

/// What a device-code poll loop settled to.
final class DevicePollResult {
  const DevicePollResult(this.outcome, {this.message = ''});

  final DevicePollOutcome outcome;
  final String message;
}

/// The Connexions page model of one instance.
final class ConnectionsState {
  const ConnectionsState({
    this.cards = const [],
    this.pendingLogin,
    this.pendingBridgeLogin,
  });

  final List<ConnectionCard> cards;

  /// Non-null while a device-code login is being polled.
  final DeviceCodeLogin? pendingLogin;

  /// Non-null while a subscription-bridge login is being polled.
  final BridgeLogin? pendingBridgeLogin;

  ConnectionsState copyWith({
    List<ConnectionCard>? cards,
    DeviceCodeLogin? Function()? pendingLogin,
    BridgeLogin? Function()? pendingBridgeLogin,
  }) => ConnectionsState(
    cards: cards ?? this.cards,
    pendingLogin: pendingLogin == null ? this.pendingLogin : pendingLogin(),
    pendingBridgeLogin: pendingBridgeLogin == null
        ? this.pendingBridgeLogin
        : pendingBridgeLogin(),
  );
}

/// How long a device-code poll loop waits between polls at most.
const devicePollInterval = Duration(seconds: 5);

/// Builds the card list from the raw REST payloads (pure, unit-testable).
///
/// [oauth] is `GET /api/providers/oauth`, [pool] is
/// `GET /api/credentials/pool`, [options] is `model.options`
/// (`include_unconfigured`), [endpoints] is
/// `GET /api/providers/custom-endpoints`, [env] is `GET /api/env`.
/// [bridgeFiles] is the sidecar `listAuthFiles()` snapshot; [serverBridge]
/// replaces it for an instance on a server ([bridgeOnServer]). Both null
/// hides the bridge cards (web/mobile: no sidecar, no [BridgeHost]
/// override).
List<ConnectionCard> buildConnectionCards({
  required Map<String, Object?> oauth,
  required Map<String, Object?> pool,
  required ModelOptionsResult options,
  required Map<String, Object?> endpoints,
  required Map<String, Object?> env,
  List<AuthFile>? bridgeFiles,
  ServerBridgeStatus? serverBridge,
}) {
  final poolByProvider = <String, List<PoolEntry>>{};
  for (final entry in (pool['providers'] as List?) ?? const []) {
    final row = entry as Map<String, Object?>;
    final provider = row['provider'] as String? ?? '';
    poolByProvider[provider] = [
      for (final e in (row['entries'] as List?) ?? const [])
        PoolEntry.fromJson(e as Map<String, Object?>),
    ];
  }
  final optionsBySlug = {for (final p in options.providers) p.slug: p};
  final envRows = <String, Map<String, Object?>>{
    for (final e in env.entries)
      if (e.value is Map<String, Object?>)
        e.key: e.value as Map<String, Object?>,
  };

  final cards = <ConnectionCard>[];
  for (final entry in (oauth['providers'] as List?) ?? const []) {
    final row = entry as Map<String, Object?>;
    final id = row['id'] as String? ?? '';
    final name = row['name'] as String? ?? id;
    final status = row['status'] as Map<String, Object?>?;
    final option = optionsBySlug[id];
    final loggedIn = status?['logged_in'] as bool? ?? false;
    final authType = option?.authType ?? '';
    final keyEnv = option?.keyEnv ?? '';
    // Hermes `/start` refuses `external` providers; those cards delegate to
    // the terminal — except registry `api_key` providers like `anthropic`,
    // whose key can still be saved in-app.
    final flow = switch (row['flow']) {
      'device_code' => ConnectionFlow.deviceCode,
      'external' when authType == 'api_key' && keyEnv.isNotEmpty =>
        ConnectionFlow.apiKey,
      _ => ConnectionFlow.external,
    };
    cards.add(
      ConnectionCard(
        id: id,
        name: name,
        logoKey: id,
        flow: flow,
        state: loggedIn
            ? ConnectionCardState.connected
            : ConnectionCardState.disconnected,
        detail: _cardDetail(
          status: status,
          flow: flow,
          keyEnv: keyEnv,
          loggedIn: loggedIn,
        ),
        status: status,
        cliCommand: row['cli_command'] as String? ?? '',
        docsUrl: row['docs_url'] as String? ?? '',
        disconnectHint: row['disconnect_hint'] as String? ?? '',
        disconnectable: row['disconnectable'] as bool? ?? true,
        disconnectCommand: row['disconnect_command'] as String?,
        poolEntries: poolByProvider[id] ?? const [],
        keyEnv: keyEnv,
      ),
    );
  }
  final known = {for (final c in cards) c.id};

  // API-key inventory rows without an OAuth card get their own card.
  for (final option in options.providers) {
    if (known.contains(option.slug)) continue;
    if (option.authType != 'api_key' || (option.keyEnv ?? '').isEmpty) {
      continue;
    }
    final keyEnv = option.keyEnv!;
    final set = envRows[keyEnv]?['is_set'] as bool? ?? false;
    final authenticated = option.authenticated ?? false;
    final connected = authenticated || set;
    cards.add(
      ConnectionCard(
        id: option.slug,
        name: option.name,
        logoKey: option.slug,
        flow: ConnectionFlow.apiKey,
        state: connected
            ? ConnectionCardState.connected
            : ConnectionCardState.disconnected,
        detail: connected ? keyEnv : 'paste $keyEnv to activate',
        poolEntries: poolByProvider[option.slug] ?? const [],
        keyEnv: keyEnv,
      ),
    );
    known.add(option.slug);
  }

  // Pooled-only and env-only providers render as generic cards.
  for (final provider in poolByProvider.keys) {
    if (known.contains(provider)) continue;
    cards.add(
      ConnectionCard(
        id: provider,
        name: provider,
        logoKey: provider,
        flow: ConnectionFlow.external,
        state: ConnectionCardState.connected,
        detail: '${poolByProvider[provider]!.length} pooled credential(s)',
        poolEntries: poolByProvider[provider]!,
      ),
    );
    known.add(provider);
  }

  // Saved custom endpoints render as custom-endpoint cards.
  for (final entry in (endpoints['endpoints'] as List?) ?? const []) {
    final row = entry as Map<String, Object?>;
    final id = row['id'] as String? ?? '';
    final cardId = 'custom:$id';
    cards.add(
      ConnectionCard(
        id: cardId,
        name: row['name'] as String? ?? id,
        logoKey: 'custom-endpoint',
        flow: ConnectionFlow.customEndpoint,
        state: ConnectionCardState.connected,
        detail: row['base_url'] as String? ?? '',
        poolEntries: poolByProvider[cardId] ?? const [],
      ),
    );
  }

  // Subscription-bridge cards (desktop only): one per bridge provider,
  // connected when a usable account exists — in this desktop's sidecar, or
  // in the bridge on the instance's server — and Hermes has the endpoint. A
  // Hermes `external` OAuth card
  // routed to a bridge keeps its own card too — the bridge is the advanced
  // alternative, never a replacement of the terminal path.
  final files = bridgeFiles;
  if (serverBridge != null) {
    final rows = [
      for (final entry in (endpoints['endpoints'] as List?) ?? const [])
        if (entry is Map<String, Object?>) entry,
    ];
    for (final spec in bridgeCardSpecs) {
      cards.add(_serverBridgeCard(spec, serverBridge, rows));
    }
  } else if (files != null) {
    final usableByProvider = <String, List<AuthFile>>{};
    for (final file in files) {
      if (file.usable) {
        usableByProvider.putIfAbsent(file.provider, () => []).add(file);
      }
    }
    final endpointNames = {
      for (final entry in (endpoints['endpoints'] as List?) ?? const [])
        (entry as Map<String, Object?>)['name'] as String? ?? '',
    };
    for (final spec in bridgeCardSpecs) {
      final creds = [
        for (final p in spec.authFileProviders) ...?usableByProvider[p],
      ];
      final registered = endpointNames.contains(spec.label);
      final connected = creds.isNotEmpty && registered;
      final email = creds.isEmpty ? '' : (creds.first.email ?? '');
      cards.add(
        ConnectionCard(
          id: spec.cardId,
          name: spec.label,
          logoKey: spec.provider.name,
          flow: ConnectionFlow.bridge,
          state: connected
              ? ConnectionCardState.connected
              : ConnectionCardState.disconnected,
          detail: connected
              ? (email.isEmpty ? 'via sidecar' : 'via sidecar · $email')
              : creds.isEmpty
              ? 'advanced · sign in with your subscription'
              : 'advanced · tap to register in Hermes',
          disconnectable: connected || creds.isNotEmpty,
          disconnectHint: connected || creds.isNotEmpty
              ? ''
              : 'Nothing to disconnect yet.',
          advanced: true,
          bridgeSpec: spec,
        ),
      );
    }
  }
  return cards;
}

/// Bridge card of an instance served by its server's bridge: connected when
/// the server holds a usable account of [spec] AND Hermes has the card's
/// endpoint pointing at that bridge. An entry still pointing elsewhere (a
/// desktop sidecar) reads as not registered, so a tap re-registers it. A
/// server whose plugin lacks the bridge waits on its install or update
/// ([ConnectionCard.needsPlugin]); one that cannot run it (other host) puts
/// the card in error with why.
ConnectionCard _serverBridgeCard(
  BridgeCardSpec spec,
  ServerBridgeStatus server,
  List<Map<String, Object?>> endpoints,
) {
  final accounts = [
    for (final account in server.accounts)
      if (spec.authFileProviders.contains(account.provider)) account,
  ];
  final usable = [
    for (final account in accounts)
      if (account.usable) account,
  ];
  final named = [
    for (final row in endpoints)
      if (row['name'] == spec.label) row,
  ];
  final endpoint = server.endpoint;
  final registered =
      endpoint != null &&
      named.any((row) => _sameUrl(row['base_url'], endpoint));
  final connected = server.supported && usable.isNotEmpty && registered;
  final needsPlugin =
      !server.supported &&
      (server.detail == serverBridgeUpdatePlugin ||
          server.detail == serverBridgeInstallPlugin);
  final email = usable.isEmpty ? '' : usable.first.email;
  final removable = accounts.isNotEmpty || named.isNotEmpty;
  return ConnectionCard(
    id: spec.cardId,
    name: spec.label,
    logoKey: spec.provider.name,
    flow: ConnectionFlow.bridge,
    state: needsPlugin
        ? ConnectionCardState.disconnected
        : !server.supported
        ? ConnectionCardState.error
        : connected
        ? ConnectionCardState.connected
        : ConnectionCardState.disconnected,
    detail: !server.supported
        ? server.detail
        : connected
        ? (email.isEmpty ? 'on the server' : 'on the server · $email')
        : usable.isNotEmpty
        ? 'advanced · tap to register in Hermes'
        : accounts.isNotEmpty && !server.running
        ? 'advanced · the bridge on the server is stopped, tap to restart it'
        : 'advanced · sign in with your subscription',
    disconnectable: removable,
    disconnectHint: removable ? '' : 'Nothing to disconnect yet.',
    advanced: true,
    bridgeSpec: spec,
    onServer: true,
    needsPlugin: needsPlugin,
  );
}

/// Same URL, give or take a trailing slash.
bool _sameUrl(Object? url, String expected) {
  String trimmed(String text) =>
      text.endsWith('/') ? text.substring(0, text.length - 1) : text;
  return url is String && trimmed(url) == trimmed(expected);
}

String _cardDetail({
  required Map<String, Object?>? status,
  required ConnectionFlow flow,
  required String keyEnv,
  required bool loggedIn,
}) {
  final label = status?['source_label'] as String? ?? '';
  if (loggedIn) return label;
  if (status?['error'] is String && (status!['error'] as String).isNotEmpty) {
    return status['error'] as String;
  }
  if (flow == ConnectionFlow.apiKey && keyEnv.isNotEmpty) {
    return 'paste $keyEnv to activate';
  }
  return label;
}

/// Connection cards of one instance: data-driven descriptors plus the
/// device-code / API-key / custom-endpoint / disconnect actions.
///
/// Auto-disposed with its screen (it pins the instance connection while
/// alive); an in-flight login holds a keep-alive link until it settles.
@riverpod
class ConnectionCards extends _$ConnectionCards {
  Timer? _pollTimer;
  var _pollCancelled = false;

  @override
  Future<ConnectionsState> build(String instanceId) async {
    ref.onDispose(() {
      _pollTimer?.cancel();
    });
    ref.listen(connectionProvider(instanceId), (_, _) {});
    return ConnectionsState(cards: await _loadCards());
  }

  /// Re-reads every card source from the server.
  Future<void> refresh() async {
    final previous = state.value;
    // ignore: invalid_use_of_internal_member
    state = AsyncLoading<ConnectionsState>().copyWithPrevious(state);
    try {
      state = AsyncData(
        ConnectionsState(
          cards: await _loadCards(),
          pendingLogin: previous?.pendingLogin,
          pendingBridgeLogin: previous?.pendingBridgeLogin,
        ),
      );
    } on Object catch (error, stackTrace) {
      final failed = AsyncError<ConnectionsState>(error, stackTrace);
      // ignore: invalid_use_of_internal_member
      state = failed.copyWithPrevious(state);
    }
  }

  /// Starts a device-code login and polls `…/poll/{sessionId}` until it
  /// settles (approved/denied/expired/error), times out, or [cancelLogin]
  /// runs. The server saves credentials itself on approval; the UI shows
  /// [DeviceCodeLogin.userCode] + [DeviceCodeLogin.verificationUrl] meanwhile.
  Future<DevicePollResult> startDeviceCode(
    String providerId, {
    Duration timeout = const Duration(minutes: 15),
  }) async {
    final link = ref.keepAlive();
    try {
      return await _deviceCode(providerId, timeout);
    } finally {
      link.close();
    }
  }

  Future<DevicePollResult> _deviceCode(
    String providerId,
    Duration timeout,
  ) async {
    final current = state.value;
    if (current == null) throw StateError('connections are still loading');
    final rest = await ref.read(restClientProvider(instanceId).future);
    final started = await rest.postJson(
      '/api/providers/oauth/${Uri.encodeComponent(providerId)}/start',
      const {},
    );
    final login = DeviceCodeLogin.fromStart(providerId, started);
    _pollCancelled = false;
    state = AsyncData(
      current.copyWith(
        pendingLogin: () => login,
        cards: [
          for (final card in current.cards)
            if (card.id == providerId)
              card.copyWith(
                state: ConnectionCardState.pending,
                detail: 'waiting for browser approval…',
              )
            else
              card,
        ],
      ),
    );
    final outcome = await _pollUntilSettled(rest, login, timeout);
    _pollTimer?.cancel();
    _pollTimer = null;
    if (ref.mounted) {
      final cards = await _loadCards();
      state = AsyncData(
        ConnectionsState(
          cards: [
            for (final card in cards)
              if (card.id == providerId &&
                  outcome.outcome == DevicePollOutcome.error)
                card.copyWith(
                  state: ConnectionCardState.error,
                  detail: outcome.message,
                )
              else
                card,
          ],
          pendingLogin: null,
        ),
      );
    }
    if (outcome.outcome == DevicePollOutcome.approved && ref.mounted) {
      unawaited(
        ref
            .read(onboardingProvider(instanceId).notifier)
            .refresh()
            .then((_) {}, onError: (_) {}),
      );
    }
    return outcome;
  }

  /// Cancels the in-flight device-code login (server `DELETE …/sessions/{id}`
  /// plus the local poll loop).
  Future<void> cancelLogin() async {
    final login = state.value?.pendingLogin;
    _pollCancelled = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pollCompleter != null && !_pollCompleter!.isCompleted) {
      _pollCompleter!.complete(
        const DevicePollResult(DevicePollOutcome.cancelled),
      );
    }
    _pollCompleter = null;
    if (login != null) {
      final rest = await ref.read(restClientProvider(instanceId).future);
      await rest.delete(
        '/api/providers/oauth/sessions/${Uri.encodeComponent(login.sessionId)}',
      );
    }
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        ConnectionsState(cards: await _loadCards(), pendingLogin: null),
      );
    }
  }

  /// Validates an API key (`POST /api/providers/validate`) and saves it via
  /// RPC `model.save_key` (Hermes then reconciles the boot record itself).
  ///
  /// When the probe cannot reach the provider (`reachable` false) the key is
  /// still saved — the server contract says not to hard-block offline users.
  Future<ModelOptionProvider> saveApiKey(String providerId, String key) async {
    if (key.trim().isEmpty) throw ArgumentError('key must not be empty');
    final rest = await ref.read(restClientProvider(instanceId).future);
    final connection = await ref.read(connectionProvider(instanceId).future);
    final cards = state.value?.cards ?? const <ConnectionCard>[];
    final card = cards.where((c) => c.id == providerId).firstOrNull;
    final keyEnv = card?.keyEnv ?? '';
    if (keyEnv.isEmpty) {
      throw StateError('provider $providerId has no API-key slot');
    }
    final probe = await rest.postJson('/api/providers/validate', {
      'key': keyEnv,
      'value': key.trim(),
    });
    // `ok` false + `reachable` true means the provider rejected the key:
    // surface the server sentence and do not persist.
    if (probe['ok'] != true && probe['reachable'] == true) {
      throw ConnectionRejected(
        probe['message'] as String? ?? 'The provider rejected this key.',
      );
    }
    final saved = await connection.transport.call(
      HermesMethods.modelSaveKey,
      ModelSaveKeyParams(slug: providerId, apiKey: key.trim()),
    );
    await refresh();
    if (ref.mounted) {
      unawaited(
        ref
            .read(onboardingProvider(instanceId).notifier)
            .refresh()
            .then((_) {}, onError: (_) {}),
      );
    }
    return saved.provider;
  }

  /// Validates then saves an OpenAI-compatible custom endpoint.
  ///
  /// Persists `resolved_base_url` (the base that actually served `/models`),
  /// never the URL as typed — the runtime appends `/chat/completions` to the
  /// saved URL verbatim.
  Future<String> addCustomEndpoint({
    required String name,
    required String baseUrl,
    String apiKey = '',
    String model = '',
  }) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final probe = await rest.postJson(
      '/api/providers/custom-endpoints/validate',
      {
        'name': name,
        'base_url': baseUrl,
        'model': model,
        if (apiKey.isNotEmpty) 'api_key': apiKey,
      },
    );
    if (probe['ok'] != true) {
      throw ConnectionRejected(
        probe['message'] as String? ?? 'The endpoint rejected this setup.',
      );
    }
    final resolved = probe['resolved_base_url'] as String? ?? baseUrl;
    final models = [
      if (model.isNotEmpty) model,
      ...((probe['models'] as List?)?.cast<String>() ?? const []),
    ];
    final saved = await rest.postJson('/api/providers/custom-endpoints', {
      'name': name,
      'base_url': resolved,
      'model': models.isEmpty ? '' : models.first,
      if (apiKey.isNotEmpty) 'api_key': apiKey,
      if (models.isNotEmpty) 'models': models.toSet().toList(),
    });
    await refresh();
    return saved['id'] as String? ?? '';
  }

  /// Deletes a saved custom endpoint.
  Future<void> deleteCustomEndpoint(String endpointId) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    await rest.delete(
      '/api/providers/custom-endpoints/${Uri.encodeComponent(endpointId)}',
    );
    await refresh();
  }

  /// Disconnects a provider: `custom:*` ids delete the endpoint, `bridge:*`
  /// ids delete the Hermes registration (the sidecar credential stays, so a
  /// re-tap re-registers without another OAuth dance), pooled-only cards
  /// delete their pool entries, OAuth cards use
  /// `DELETE /api/providers/oauth/{id}`, and API-key cards clear their env var
  /// (`DELETE /api/env`, preserving OAuth/device-code pool entries).
  Future<void> disconnect(String providerId) async {
    if (providerId.startsWith('custom:')) {
      await deleteCustomEndpoint(providerId.substring('custom:'.length));
      return;
    }
    if (providerId.startsWith('bridge:')) {
      await disconnectBridge(providerId);
      return;
    }
    final rest = await ref.read(restClientProvider(instanceId).future);
    final cards = state.value?.cards ?? const <ConnectionCard>[];
    final card = cards.where((c) => c.id == providerId).firstOrNull;
    if (card == null) throw StateError('unknown provider $providerId');
    if (!card.disconnectable && card.poolEntries.isEmpty) {
      throw ConnectionRejected(
        card.disconnectHint.isNotEmpty
            ? card.disconnectHint
            : '$providerId cannot be disconnected automatically.',
      );
    }
    if (card.poolEntries.isNotEmpty &&
        (card.flow == ConnectionFlow.external ||
            card.status == null ||
            !card.disconnectable)) {
      // Pooled-only or non-disconnectable card: remove the pool entries
      // (sticky: the server also suppresses their backing sources).
      for (final entry in [
        ...card.poolEntries,
      ]..sort((a, b) => b.index.compareTo(a.index))) {
        await rest.delete(
          '/api/credentials/pool/${Uri.encodeComponent(providerId)}/${entry.index}',
        );
      }
    } else if (card.status != null && card.disconnectable) {
      await rest.delete(
        '/api/providers/oauth/${Uri.encodeComponent(providerId)}',
      );
    } else if (card.keyEnv.isNotEmpty) {
      // `DELETE /api/env` takes a JSON body; the client's `delete` sends
      // none, so route through the raw client.
      await _deleteJson(rest, '/api/env', {'key': card.keyEnv});
    } else {
      throw ConnectionRejected(
        '$providerId cannot be disconnected automatically.',
      );
    }
    await refresh();
    if (ref.mounted) {
      unawaited(
        ref
            .read(onboardingProvider(instanceId).notifier)
            .refresh()
            .then((_) {}, onError: (_) {}),
      );
    }
  }

  Completer<DevicePollResult>? _pollCompleter;

  Future<DevicePollResult> _pollUntilSettled(
    HermesRestClient rest,
    DeviceCodeLogin login,
    Duration timeout,
  ) async {
    final completer = _pollCompleter = Completer<DevicePollResult>();
    final stopwatch = Stopwatch()..start();
    final interval = login.pollInterval < const Duration(milliseconds: 10)
        ? const Duration(milliseconds: 10)
        : login.pollInterval;
    Future<void> poll() async {
      if (_pollCancelled) {
        if (!completer.isCompleted) {
          completer.complete(
            const DevicePollResult(DevicePollOutcome.cancelled),
          );
        }
        return;
      }
      if (stopwatch.elapsed > timeout) {
        if (!completer.isCompleted) {
          completer.complete(
            const DevicePollResult(
              DevicePollOutcome.timeout,
              message: 'The login timed out before approval.',
            ),
          );
        }
        return;
      }
      try {
        final poll = await rest.getJson(
          '/api/providers/oauth/${Uri.encodeComponent(login.providerId)}'
          '/poll/${Uri.encodeComponent(login.sessionId)}',
        );
        switch (poll['status']) {
          case 'approved':
            if (!completer.isCompleted) {
              completer.complete(
                const DevicePollResult(DevicePollOutcome.approved),
              );
            }
            return;
          case 'denied':
            if (!completer.isCompleted) {
              completer.complete(
                DevicePollResult(
                  DevicePollOutcome.denied,
                  message:
                      poll['error_message'] as String? ??
                      'The login was denied.',
                ),
              );
            }
            return;
          case 'expired':
            if (!completer.isCompleted) {
              completer.complete(
                DevicePollResult(
                  DevicePollOutcome.expired,
                  message:
                      poll['error_message'] as String? ??
                      'The code expired before approval.',
                ),
              );
            }
            return;
          case 'error':
            if (!completer.isCompleted) {
              completer.complete(
                DevicePollResult(
                  DevicePollOutcome.error,
                  message:
                      poll['error_message'] as String? ?? 'The login failed.',
                ),
              );
            }
            return;
        }
      } on HermesHttpError catch (error) {
        // 404: the session vanished server-side (restart/GC) — stop polling.
        if (error.statusCode == 404 && !completer.isCompleted) {
          completer.complete(
            DevicePollResult(DevicePollOutcome.error, message: error.message),
          );
          return;
        }
      }
      _pollTimer = Timer(interval, poll);
    }

    unawaited(poll());
    try {
      return await completer.future;
    } finally {
      if (identical(_pollCompleter, completer)) _pollCompleter = null;
    }
  }

  /// Starts a subscription-bridge login for [cardId] (`bridge:<slug>`).
  ///
  /// Flow: sidecar [BridgeHost.ensureStarted] → sidecar `startLogin` (the UI
  /// shows [BridgeLogin.url], plus [BridgeLogin.userCode] on device flows) →
  /// poll `get-auth-status` → on ok, register the endpoint in Hermes via
  /// `POST /api/providers/custom-endpoints` ([hermesCustomEndpoint]) →
  /// refresh cards. When usable sidecar credentials already exist, [startLogin]
  /// is skipped and the card re-registers directly (idempotent: Hermes merges
  /// onto the existing entry by name).
  ///
  /// An instance on a server ([bridgeOnServer]) signs in on this desktop's
  /// sidecar too — the OAuth callback must reach this machine — but the
  /// account then lives in the bridge of the Hermuse plugin on the server,
  /// which Hermes points at (see [_serverBridgeLogin]).
  Future<BridgePollResult> startBridgeLogin(
    String cardId, {
    Duration timeout = const Duration(minutes: 15),
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    final link = ref.keepAlive();
    try {
      return await _bridgeLogin(cardId, timeout, pollInterval);
    } finally {
      link.close();
    }
  }

  Future<BridgePollResult> _bridgeLogin(
    String cardId,
    Duration timeout,
    Duration pollInterval,
  ) async {
    final spec = bridgeSpecForCard(cardId);
    if (spec == null) throw StateError('unknown bridge card $cardId');
    if (state.value == null) {
      throw StateError('connections are still loading');
    }
    final host = ref.read(bridgeHostProvider);
    if (host == null) {
      throw UnsupportedError('no subscription-bridge host on this platform');
    }
    final registry = await ref.read(registryProvider.future);
    if (bridgeOnServer(registry.byId(instanceId))) {
      try {
        return await _serverBridgeLogin(spec, host, timeout, pollInterval);
      } on ServerBridgeException catch (e) {
        return await _failBridge(cardId, e.message);
      }
    }
    final sidecar = await host.ensureStarted();
    final management = CliproxyManagement(
      ref.read(httpClientProvider),
      baseUrl: sidecar.baseUrl,
      managementKey: sidecar.managementKey,
    );
    // Re-registration shortcut: credentials exist, only the Hermes entry is
    // missing (e.g. after [disconnectBridge]).
    final files = await management.listAuthFiles();
    final usable = files.any(
      (f) => f.usable && spec.authFileProviders.contains(f.provider),
    );
    _showBridgeProgress(
      cardId,
      usable ? 'registering in Hermes…' : 'waiting for subscription approval…',
    );
    if (!usable) {
      final outcome = await _signInOnSidecar(
        management,
        spec,
        timeout,
        pollInterval,
      );
      if (outcome.outcome != BridgePollOutcome.ok) return outcome;
    }
    // Signed in (or already was): discover what the sidecar can actually
    // serve for this provider, then point a Hermes custom endpoint at it.
    final catalogue = await management.listModels(apiKey: sidecar.apiKey);
    return _registerBridge(
      spec,
      _bridgeModelIds(catalogue, spec),
      baseUrl: sidecar.baseUrl,
      apiKey: sidecar.apiKey,
      where: 'sidecar',
    );
  }

  /// Sign-in for an instance on a server ([bridgeOnServer]).
  ///
  /// The plugin's bridge is set up first, so an old plugin fails before any
  /// browser opens. Without a usable account on the server, the login runs
  /// on this desktop's sidecar (the OAuth callback must reach this machine)
  /// and the account file it saved moves to the server; the sidecar's own
  /// accounts of that provider are then put back as they were, so the
  /// sign-in lives in one CLIProxyAPI only — two refreshing one grant would
  /// rotate each other's refresh token out. Models come from the server
  /// bridge, and the Hermes endpoint points at its loopback address with its
  /// key.
  Future<BridgePollResult> _serverBridgeLogin(
    BridgeCardSpec spec,
    BridgeHost host,
    Duration timeout,
    Duration pollInterval,
  ) async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final server = ServerBridgeClient(rest);
    final found = await server.status();
    if (!found.supported) throw ServerBridgeFailed(found.detail);
    _showBridgeProgress(spec.cardId, 'preparing the bridge on the server…');
    final bridge = await server.ensure();
    final signedIn = (await server.status()).accounts.any(
      (a) => a.usable && spec.authFileProviders.contains(a.provider),
    );
    if (!signedIn) {
      _showBridgeProgress(spec.cardId, 'waiting for subscription approval…');
      final sidecar = await host.ensureStarted();
      final local = CliproxyManagement(
        ref.read(httpClientProvider),
        baseUrl: sidecar.baseUrl,
        managementKey: sidecar.managementKey,
      );
      final kept = await _sidecarAccounts(local, spec);
      final outcome = await _signInOnSidecar(
        local,
        spec,
        timeout,
        pollInterval,
      );
      if (outcome.outcome != BridgePollOutcome.ok) return outcome;
      try {
        final saved = await _sidecarAccounts(local, spec);
        final fresh = {
          for (final MapEntry(:key, :value) in saved.entries)
            if (kept[key] != value) key: value,
        };
        if (fresh.isEmpty) {
          return await _failBridge(
            spec.cardId,
            'Signed in, but the sidecar saved no ${spec.label} account.',
          );
        }
        _showBridgeProgress(spec.cardId, 'moving the account to the server…');
        for (final MapEntry(:key, :value) in fresh.entries) {
          await server.uploadAccount(key, value);
        }
      } finally {
        await _restoreSidecarAccounts(local, spec, kept);
      }
    }
    _showBridgeProgress(spec.cardId, 'registering in Hermes…');
    final discovered = await _serverBridgeModels(
      server,
      spec,
      retries: signedIn ? 0 : _serverModelRetries,
      delay: pollInterval < _serverModelDelay
          ? pollInterval
          : _serverModelDelay,
    );
    return _registerBridge(
      spec,
      discovered,
      baseUrl: bridge.baseUrl,
      apiKey: bridge.apiKey,
      where: 'server bridge',
    );
  }

  /// Shows [cardId] pending with [detail] while a bridge sign-in works.
  void _showBridgeProgress(String cardId, String detail) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        cards: [
          for (final card in current.cards)
            if (card.id == cardId)
              card.copyWith(state: ConnectionCardState.pending, detail: detail)
            else
              card,
        ],
      ),
    );
  }

  /// Starts [spec]'s login on this desktop's sidecar and polls it to its
  /// end. A login that does not end ok settles the cards (a failure shows on
  /// the card) and clears the pending login.
  Future<BridgePollResult> _signInOnSidecar(
    CliproxyManagement management,
    BridgeCardSpec spec,
    Duration timeout,
    Duration pollInterval,
  ) async {
    final start = await management.startLogin(spec.provider);
    final login = BridgeLogin.fromStart(spec.cardId, spec.provider, start);
    state = AsyncData(state.value!.copyWith(pendingBridgeLogin: () => login));
    final outcome = await _pollBridgeUntilSettled(
      management,
      login,
      timeout,
      pollInterval,
    );
    _pollTimer?.cancel();
    _pollTimer = null;
    if (outcome.outcome != BridgePollOutcome.ok && ref.mounted) {
      final cards = await _loadCards();
      state = AsyncData(
        ConnectionsState(
          cards: [
            for (final card in cards)
              if (card.id == spec.cardId &&
                  outcome.outcome == BridgePollOutcome.error)
                card.copyWith(
                  state: ConnectionCardState.error,
                  detail: outcome.message,
                )
              else
                card,
          ],
          pendingBridgeLogin: null,
        ),
      );
    }
    return outcome;
  }

  /// Persists the large + small pick of [discovered], points the Hermes
  /// custom endpoint of [spec] at the bridge ([baseUrl] with [apiKey]) and
  /// refreshes. The upsert merges by name, so re-running never forks a twin;
  /// only the ≤2 selected models are registered, never the catalogue.
  /// [where] names the bridge when it advertises no model of [spec].
  Future<BridgePollResult> _registerBridge(
    BridgeCardSpec spec,
    List<String> discovered, {
    required Uri baseUrl,
    required String apiKey,
    required String where,
  }) async {
    final pair = pickLargeAndSmall(discovered);
    final selected = [
      if (pair.large != null) pair.large!,
      if (pair.small != null) pair.small!,
    ];
    // Persist the default selection so the picker and `makeDefault` agree.
    final db = ref.read(hermuseDatabaseProvider);
    await db.writeSetting(
      'model_selection:$instanceId:${spec.cardId}',
      jsonEncode({
        if (pair.large != null) 'large': pair.large,
        if (pair.small != null) 'small': pair.small,
      }),
    );
    if (selected.isEmpty) {
      return _failBridge(
        spec.cardId,
        'Signed in, but the $where advertises no ${spec.label} models.',
        'The $where advertises no models for this subscription.',
      );
    }
    final rest = await ref.read(restClientProvider(instanceId).future);
    await rest.postJson(
      '/api/providers/custom-endpoints',
      hermesCustomEndpoint(
        cliproxyBaseUrl: baseUrl,
        apiKey: apiKey,
        name: spec.label,
        model: selected.first,
        models: selected,
        chatCompletionsPath: true,
      ),
    );
    await refresh();
    final settled = state.value;
    if (settled?.pendingBridgeLogin != null) {
      state = AsyncData(settled!.copyWith(pendingBridgeLogin: () => null));
    }
    if (ref.mounted) {
      unawaited(
        ref
            .read(onboardingProvider(instanceId).notifier)
            .refresh()
            .then((_) {}, onError: (_) {}),
      );
    }
    return const BridgePollResult(BridgePollOutcome.ok);
  }

  /// Settles a failed bridge sign-in: cards reloaded with [cardId] in error
  /// showing [detail], no pending login. The result carries [message]
  /// (default: [detail]).
  Future<BridgePollResult> _failBridge(
    String cardId,
    String detail, [
    String? message,
  ]) async {
    if (ref.mounted) {
      final cards = await _loadCards();
      state = AsyncData(
        ConnectionsState(
          cards: [
            for (final card in cards)
              if (card.id == cardId)
                card.copyWith(state: ConnectionCardState.error, detail: detail)
              else
                card,
          ],
          pendingBridgeLogin: null,
        ),
      );
    }
    return BridgePollResult(
      BridgePollOutcome.error,
      message: message ?? detail,
    );
  }

  /// Cancels the in-flight bridge login (sidecar `DELETE /oauth-session`
  /// plus the local poll loop).
  Future<void> cancelBridgeLogin() async {
    final login = state.value?.pendingBridgeLogin;
    _bridgeCancelled = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_bridgeCompleter != null && !_bridgeCompleter!.isCompleted) {
      _bridgeCompleter!.complete(
        const BridgePollResult(BridgePollOutcome.cancelled),
      );
    }
    _bridgeCompleter = null;
    if (login != null) {
      try {
        final host = ref.read(bridgeHostProvider);
        if (host == null) return;
        final sidecar = await host.ensureStarted();
        await CliproxyManagement(
          ref.read(httpClientProvider),
          baseUrl: sidecar.baseUrl,
          managementKey: sidecar.managementKey,
        ).cancelLogin(login.state);
      } on Object {
        // Best-effort: the local loop is already stopped.
      }
    }
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        ConnectionsState(cards: await _loadCards(), pendingBridgeLogin: null),
      );
    }
  }

  /// Deletes the Hermes custom-endpoint registration of a bridge card. The
  /// sidecar credential is deliberately kept: re-tapping the card re-registers
  /// without another OAuth dance. On an instance on a server
  /// ([bridgeOnServer]) the card's accounts are removed from the server's
  /// bridge too.
  Future<void> disconnectBridge(String cardId) async {
    final spec = bridgeSpecForCard(cardId);
    if (spec == null) throw StateError('unknown bridge card $cardId');
    final rest = await ref.read(restClientProvider(instanceId).future);
    final registry = await ref.read(registryProvider.future);
    final endpoints = await rest.getJson('/api/providers/custom-endpoints');
    String? endpointId;
    for (final entry in (endpoints['endpoints'] as List?) ?? const []) {
      final row = entry as Map<String, Object?>;
      if (row['name'] == spec.label) {
        endpointId = row['id'] as String?;
        break;
      }
    }
    final registered = endpointId != null && endpointId.isNotEmpty;
    if (endpointId != null && endpointId.isNotEmpty) {
      await rest.delete(
        '/api/providers/custom-endpoints/${Uri.encodeComponent(endpointId)}',
      );
    }
    final removed =
        bridgeOnServer(registry.byId(instanceId)) &&
        await _deleteServerAccounts(ServerBridgeClient(rest), spec);
    if (!registered && !removed) {
      throw StateError('${spec.label} is not registered in Hermes.');
    }
    await refresh();
  }

  /// Removes [spec]'s accounts from the server bridge; whether any went.
  static Future<bool> _deleteServerAccounts(
    ServerBridgeClient server,
    BridgeCardSpec spec,
  ) async {
    final ServerBridgeStatus status;
    try {
      status = await server.status();
    } on ServerBridgeUnavailable {
      return false; // no bridge there: none of the card's accounts either
    }
    var removed = false;
    for (final account in status.accounts) {
      if (spec.authFileProviders.contains(account.provider) &&
          await server.deleteAccount(account.name)) {
        removed = true;
      }
    }
    return removed;
  }

  var _bridgeCancelled = false;
  Completer<BridgePollResult>? _bridgeCompleter;

  Future<BridgePollResult> _pollBridgeUntilSettled(
    CliproxyManagement management,
    BridgeLogin login,
    Duration timeout,
    Duration pollInterval,
  ) async {
    final completer = _bridgeCompleter = Completer<BridgePollResult>();
    final stopwatch = Stopwatch()..start();
    final interval = pollInterval < const Duration(milliseconds: 10)
        ? const Duration(milliseconds: 10)
        : pollInterval;
    _bridgeCancelled = false;
    Future<void> poll() async {
      if (_bridgeCancelled) {
        if (!completer.isCompleted) {
          completer.complete(
            const BridgePollResult(BridgePollOutcome.cancelled),
          );
        }
        return;
      }
      if (stopwatch.elapsed > timeout) {
        if (!completer.isCompleted) {
          completer.complete(
            const BridgePollResult(
              BridgePollOutcome.timeout,
              message: 'The login timed out before approval.',
            ),
          );
        }
        return;
      }
      try {
        final status = await management.pollLogin(login.state);
        if (status.isOk) {
          if (!completer.isCompleted) {
            completer.complete(const BridgePollResult(BridgePollOutcome.ok));
          }
          return;
        }
        if (status.state == AuthState.error) {
          if (!completer.isCompleted) {
            completer.complete(
              BridgePollResult(
                BridgePollOutcome.error,
                message: status.error ?? 'The login failed.',
              ),
            );
          }
          return;
        }
      } on CliproxyProtocolError catch (error) {
        // Unknown/expired state: the session vanished sidecar-side — stop.
        if (!completer.isCompleted) {
          completer.complete(
            BridgePollResult(BridgePollOutcome.error, message: error.message),
          );
        }
        return;
      } on CliproxyException {
        // Transient sidecar/network failure: keep polling until the timeout.
      }
      _pollTimer = Timer(interval, poll);
    }

    unawaited(poll());
    try {
      return await completer.future;
    } finally {
      if (identical(_bridgeCompleter, completer)) _bridgeCompleter = null;
    }
  }

  Future<List<ConnectionCard>> _loadCards() async {
    final rest = await ref.read(restClientProvider(instanceId).future);
    final connection = await ref.read(connectionProvider(instanceId).future);
    final registry = await ref.read(registryProvider.future);
    final instance = registry.byId(instanceId);
    final profile = instance?.profile;
    final oauth = await rest.getJson('/api/providers/oauth');
    final pool = await rest.getJson('/api/credentials/pool');
    final endpoints = await rest.getJson('/api/providers/custom-endpoints');
    final env = await rest.getJson('/api/env');
    final options = await connection.transport.call(
      HermesMethods.modelOptions,
      ModelOptionsParams(
        profile: (profile == null || profile.isEmpty) ? null : profile,
        includeUnconfigured: true,
      ),
    );
    final onServer = bridgeOnServer(instance);
    return buildConnectionCards(
      oauth: oauth,
      pool: pool,
      options: options,
      endpoints: endpoints,
      env: env,
      bridgeFiles: onServer ? null : await _bridgeFiles(),
      serverBridge: onServer ? await _serverBridge(rest) : null,
    );
  }

  /// The server's bridge for an instance on a server, or null where this
  /// device has no sidecar for the sign-in's OAuth callback (web/mobile:
  /// bridge cards stay hidden). A plugin without the bridge yields what to
  /// do; an unreachable one renders the cards without connected state.
  Future<ServerBridgeStatus?> _serverBridge(HermesRestClient rest) async {
    if (ref.read(bridgeHostProvider) == null) return null;
    try {
      return await ServerBridgeClient(rest).status();
    } on ServerBridgeException catch (e) {
      return ServerBridgeStatus.unavailable(e.message);
    } on Object {
      return const ServerBridgeStatus();
    }
  }

  /// Sidecar auth-file snapshot, or null when there is no bridge host
  /// (web/mobile) or the sidecar is unreachable. Never starts the sidecar:
  /// card listing must not spawn processes; [startBridgeLogin] does that.
  Future<List<AuthFile>?> _bridgeFiles() async {
    final host = ref.read(bridgeHostProvider);
    if (host == null) return null;
    try {
      final sidecar = await host.ensureStarted();
      return await CliproxyManagement(
        ref.read(httpClientProvider),
        baseUrl: sidecar.baseUrl,
        managementKey: sidecar.managementKey,
      ).listAuthFiles();
    } on Object {
      // A dead sidecar must not break the whole Connexions page; the bridge
      // cards simply render without connected state.
      return const [];
    }
  }

  /// `DELETE /api/env` carries a JSON body, which [HermesRestClient.delete]
  /// cannot send.
  Future<Map<String, Object?>> _deleteJson(
    HermesRestClient rest,
    String path,
    Map<String, Object?> body,
  ) => rest.deleteWithBody(path, body);
}

/// Reads of the server catalogue after an account upload, [_serverModelDelay]
/// apart: CLIProxyAPI lists an uploaded account's models once its auth
/// watcher registered them, within about a second.
const _serverModelRetries = 10;
const _serverModelDelay = Duration(seconds: 1);

/// Ids of [catalogue] owned by [spec]'s vendors, in catalogue order (the
/// registry lists newest first). Empty [BridgeCardSpec.modelOwners] (Devin:
/// no catalogue section) keeps every advertised model.
List<String> _bridgeModelIds(
  Iterable<SidecarModel> catalogue,
  BridgeCardSpec spec,
) => {
  for (final model in catalogue)
    if (model.id.isNotEmpty &&
        (spec.modelOwners.isEmpty ||
            (model.ownedBy != null &&
                spec.modelOwners.contains(model.ownedBy))))
      model.id,
}.toList();

/// [spec]'s models on the server bridge, read again up to [retries] times
/// [delay] apart while there are none (an account just uploaded).
Future<List<String>> _serverBridgeModels(
  ServerBridgeClient server,
  BridgeCardSpec spec, {
  int retries = 0,
  Duration delay = Duration.zero,
}) async {
  var models = _bridgeModelIds(await server.models(), spec);
  for (var attempt = 0; models.isEmpty && attempt < retries; attempt++) {
    await Future<void>.delayed(delay);
    models = _bridgeModelIds(await server.models(), spec);
  }
  return models;
}

/// Account files of [spec]'s providers on this desktop's sidecar: name →
/// JSON text, as CLIProxyAPI stored them.
Future<Map<String, String>> _sidecarAccounts(
  CliproxyManagement sidecar,
  BridgeCardSpec spec,
) async {
  final accounts = <String, String>{};
  for (final file in await sidecar.listAuthFiles()) {
    if (!file.name.endsWith('.json') ||
        !spec.authFileProviders.contains(file.provider)) {
      continue;
    }
    try {
      accounts[file.name] = await sidecar.downloadAuthFile(file.name);
    } on CliproxyHttpError catch (e) {
      // An account without a file (runtime-only) has nothing to move.
      if (e.statusCode != 404) rethrow;
    }
  }
  return accounts;
}

/// Puts [kept] back as the sidecar's [spec] accounts after a sign-in for a
/// server: a file the login added goes, one it replaced gets its previous
/// content again. Best effort: the server account is what the sign-in was
/// for.
Future<void> _restoreSidecarAccounts(
  CliproxyManagement sidecar,
  BridgeCardSpec spec,
  Map<String, String> kept,
) async {
  try {
    final now = await _sidecarAccounts(sidecar, spec);
    for (final name in now.keys) {
      if (!kept.containsKey(name)) await sidecar.deleteAuthFile(name);
    }
    for (final MapEntry(:key, :value) in kept.entries) {
      if (now[key] != value) await sidecar.uploadAuthFile(key, value);
    }
  } on Object {
    // The sidecar keeps a copy; the next refresh of either side may fail.
  }
}
