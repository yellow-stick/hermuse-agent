import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';

import 'product.dart';

/// Base route of the subscription bridge in the Hermuse plugin
/// (`hermes-plugin/hermuse/subscription_bridge.py`).
const hermuseBridgeRoute = '$hermusePluginRoute/bridge';

/// Bridge-card detail and sign-in error when the Hermuse plugin on the server
/// predates the subscription bridge.
const serverBridgeUpdatePlugin = 'Update the Hermuse plugin on this server';

/// Same, when the server has no Hermuse plugin at all.
const serverBridgeInstallPlugin = 'Install the Hermuse plugin on this server';

/// Whether the bridge cards of [instance] use the subscription bridge of the
/// Hermuse plugin on its server instead of this desktop's sidecar.
///
/// A Hermes reached over the network calls its custom endpoint from its own
/// host, where the sidecar's `127.0.0.1` is the server itself. A `remote`
/// instance on this machine's loopback keeps the sidecar.
bool bridgeOnServer(HermesInstance? instance) {
  if (instance == null || instance.kind != InstanceKind.remote) return false;
  final host = instance.baseUrl.host;
  return host != 'localhost' && host != '::1' && !host.startsWith('127.');
}

/// A failure of the subscription bridge on a server; [message] is shown to
/// the user as is.
sealed class ServerBridgeException implements Exception {
  const ServerBridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Hermuse plugin on the server has no subscription bridge: it predates
/// it ([serverBridgeUpdatePlugin]) or is missing ([serverBridgeInstallPlugin]).
final class ServerBridgeUnavailable extends ServerBridgeException {
  const ServerBridgeUnavailable(super.message);
}

/// The bridge refused or failed: unsupported host, download, CLIProxyAPI.
final class ServerBridgeFailed extends ServerBridgeException {
  const ServerBridgeFailed(super.message, {this.statusCode});

  /// HTTP status of the plugin's answer; null when it gave none.
  final int? statusCode;
}

/// One account of the server bridge (`GET /bridge/status` `accounts`).
final class ServerBridgeAccount {
  const ServerBridgeAccount({
    required this.name,
    required this.provider,
    this.email = '',
    this.usable = false,
  });

  factory ServerBridgeAccount.fromJson(Map<String, Object?> json) =>
      ServerBridgeAccount(
        name: json['name'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
        email: json['email'] as String? ?? '',
        usable: json['usable'] as bool? ?? false,
      );

  /// Account file name (`claude-<email>.json`, …).
  final String name;

  /// CLIProxyAPI provider (`claude`, `codex`, …), as in
  /// [BridgeCardSpec.authFileProviders].
  final String provider;
  final String email;

  /// The bridge runs and can serve this account.
  final bool usable;
}

/// `GET /bridge/status` of the Hermuse plugin on a server.
final class ServerBridgeStatus {
  const ServerBridgeStatus({
    this.supported = true,
    this.running = false,
    this.baseUrl,
    this.accounts = const [],
    this.detail = '',
    this.signIn = true,
  });

  /// The server cannot sign subscriptions in; [detail] says what to do.
  const ServerBridgeStatus.unavailable(this.detail)
    : supported = false,
      running = false,
      baseUrl = null,
      accounts = const [],
      signIn = false;

  factory ServerBridgeStatus.fromJson(Map<String, Object?> json) =>
      ServerBridgeStatus(
        supported: json['supported'] as bool? ?? false,
        running: json['running'] as bool? ?? false,
        baseUrl: switch (json['base_url']) {
          final String url when url.isNotEmpty => Uri.tryParse(url),
          _ => null,
        },
        accounts: [
          for (final entry in (json['accounts'] as List?) ?? const [])
            if (entry is Map<String, Object?>)
              ServerBridgeAccount.fromJson(entry),
        ],
        detail: json['detail'] as String? ?? '',
        signIn: json['sign_in'] as bool? ?? false,
      );

  /// The host can run the bridge and the plugin has it.
  final bool supported;

  /// CLIProxyAPI answers: [accounts] are live (else read from its files,
  /// none usable).
  final bool running;

  /// Bridge origin on the server's loopback; null until it was set up.
  final Uri? baseUrl;
  final List<ServerBridgeAccount> accounts;

  /// Why the bridge cannot serve, when it cannot.
  final String detail;

  /// Subscriptions sign in on this bridge (`POST /bridge/login`); false for
  /// a plugin that predates it ([serverBridgeUpdatePlugin]).
  final bool signIn;

  /// `<baseUrl>/v1`: the Hermes custom endpoint pointing at this bridge.
  String? get endpoint => baseUrl?.replace(path: '/v1').toString();
}

/// `POST /bridge/ensure`: where Hermes reaches the bridge on its own host.
final class ServerBridgeConnection {
  const ServerBridgeConnection({required this.baseUrl, required this.apiKey});

  /// Origin on the server's loopback, e.g. `http://127.0.0.1:41000`.
  final Uri baseUrl;

  /// Bearer key of the bridge's `/v1/*` routes (the management key never
  /// leaves the server).
  final String apiKey;
}

/// REST client of the subscription bridge in the Hermuse plugin of a server
/// (`/api/plugins/hermuse/bridge/*`, behind the dashboard login like every
/// plugin route).
final class ServerBridgeClient {
  const ServerBridgeClient(this._rest);

  final HermesRestClient _rest;

  /// Bridge state and accounts.
  Future<ServerBridgeStatus> status() async => ServerBridgeStatus.fromJson(
    await _guard(() => _rest.getJson('$hermuseBridgeRoute/status')),
  );

  /// Downloads (once) and starts the bridge; returns where Hermes reaches it.
  Future<ServerBridgeConnection> ensure() async {
    final json = await _guard(
      () => _rest.postJson('$hermuseBridgeRoute/ensure', const {}),
    );
    final baseUrl = Uri.tryParse(json['base_url'] as String? ?? '');
    final apiKey = json['api_key'] as String? ?? '';
    if (baseUrl == null || baseUrl.host.isEmpty || apiKey.isEmpty) {
      throw const ServerBridgeFailed(
        'The bridge on the server did not say where it runs.',
      );
    }
    return ServerBridgeConnection(baseUrl: baseUrl, apiKey: apiKey);
  }

  /// Starts a sign-in of [provider] on the bridge: the link to open, plus the
  /// code to enter on device-code sign-ins.
  Future<AuthStart> startLogin(CliproxyProvider provider) async {
    final json = await _guard(
      () => _rest.postJson('$hermuseBridgeRoute/login', {
        'provider': provider.route.replaceFirst('-auth-url', ''),
      }),
    );
    return AuthStart.fromJson(json);
  }

  /// Where sign-in [state] stands.
  Future<AuthStatus> pollLogin(String state) async => AuthStatus.fromJson(
    await _guard(
      () => _rest.getJson('$hermuseBridgeRoute/login/status', {'state': state}),
    ),
  );

  /// Finishes a browser sign-in with the address the browser was sent to; a
  /// [ServerBridgeFailed] 400 when no sign-in waits for it.
  Future<void> submitCallback(String redirectUrl) => _guard(
    () => _rest.postJson('$hermuseBridgeRoute/login/callback', {
      'redirect_url': redirectUrl,
    }),
  );

  /// Cancels sign-in [state].
  Future<void> cancelLogin(String state) => _guard(
    () => _rest.postJson('$hermuseBridgeRoute/login/cancel', {'state': state}),
  );

  /// Removes account [name]; false when the bridge has none by that name.
  Future<bool> deleteAccount(String name) async {
    try {
      await _guard(
        () => _rest.delete(
          '$hermuseBridgeRoute/accounts/${Uri.encodeComponent(name)}',
        ),
        // 404 is the route's "no such account"; an old plugin answers 405.
        missingRoute: const {405},
      );
      return true;
    } on ServerBridgeFailed catch (e) {
      if (e.statusCode == 404) return false;
      rethrow;
    }
  }

  /// Models the bridge can serve now: `/v1/models` of the server's
  /// CLIProxyAPI, limited to models of usable accounts.
  Future<List<SidecarModel>> models() async {
    final json = await _guard(
      () => _rest.getJson('$hermuseBridgeRoute/models'),
    );
    return [
      for (final entry in (json['data'] as List?) ?? const [])
        if (entry is Map<String, Object?>) SidecarModel.fromJson(entry),
    ];
  }

  /// Plugin answers as [ServerBridgeException]s. A missing route (`404`, or
  /// `405` from the dashboard's catch-all) means the plugin has no bridge.
  Future<Map<String, Object?>> _guard(
    Future<Map<String, Object?>> Function() call, {
    Set<int> missingRoute = const {404, 405},
  }) async {
    try {
      return await call();
    } on HermesHttpError catch (e) {
      if (missingRoute.contains(e.statusCode)) throw await _unavailable();
      throw ServerBridgeFailed(_detail(e), statusCode: e.statusCode);
    }
  }

  /// Why the bridge routes are missing: an older plugin, or none at all.
  Future<ServerBridgeUnavailable> _unavailable() async {
    try {
      await _rest.getJson('$hermusePluginRoute/files');
      return const ServerBridgeUnavailable(serverBridgeUpdatePlugin);
    } on HermesHttpError catch (e) {
      if (e.statusCode == 404) {
        return const ServerBridgeUnavailable(serverBridgeInstallPlugin);
      }
      rethrow;
    }
  }

  /// The plugin's `detail`, without the `METHOD /path: ` prefix
  /// [HermesHttpError] adds.
  static String _detail(HermesHttpError error) {
    final message = error.message;
    final separator = message.indexOf(': ');
    return separator < 0 ? message : message.substring(separator + 2);
  }
}
