import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'provider.dart';

/// How the user completes a subscription login started with [startLogin].
enum AuthFlow {
  /// A browser URL finishes the OAuth callback (`auth_files_provider_oauth.go`
  /// plain `{status, url, state}` response).
  browser,

  /// A device-code flow: the user opens [AuthStart.url] and types
  /// [AuthStart.userCode] (`{..., flow: "device", user_code, expires_in}`).
  device,
}

/// Result of `GET /v0/management/<provider>-auth-url`.
///
/// Every provider returns `{status: "ok", url, state}`; device-code providers
/// (meta, xai, kimi, kimi-ai) add `flow: "device"` plus `user_code` and
/// `expires_in`.
final class AuthStart {
  const AuthStart({
    required this.url,
    required this.state,
    required this.flow,
    this.userCode,
    this.expiresIn,
  });

  factory AuthStart.fromJson(Map<String, Object?> json) {
    final url = json['url'] as String?;
    final state = json['state'] as String?;
    if (url == null || url.isEmpty || state == null || state.isEmpty) {
      throw CliproxyProtocolError('auth-url response misses url/state: $json');
    }
    final flow = json['flow'] == 'device' ? AuthFlow.device : AuthFlow.browser;
    final userCode = json['user_code'] as String?;
    final expiresIn = switch (json['expires_in']) {
      final int v => v,
      final num v => v.toInt(),
      _ => null,
    };
    return AuthStart(
      url: url,
      state: state,
      flow: flow,
      userCode: userCode?.isEmpty ?? true ? null : userCode,
      expiresIn: expiresIn,
    );
  }

  /// Where the user completes the login (browser URL or device verification).
  final String url;

  /// Opaque session id for [CliproxyManagement.pollLogin].
  final String state;
  final AuthFlow flow;

  /// Code the user types on the device verification page, if any.
  final String? userCode;

  /// Device-code lifetime in seconds, if the server reported one.
  final int? expiresIn;
}

/// Result of `GET /v0/management/get-auth-status?state=`.
///
/// The server reports `status: "wait"` while pending, `"ok"` when the
/// credential file was saved, and `"error"` with an `error` message on
/// failure (`GetAuthStatus`).
enum AuthState { pending, ok, error }

final class AuthStatus {
  const AuthStatus._(this.state, this.error);

  factory AuthStatus.fromJson(Map<String, Object?> json) {
    return switch (json['status']) {
      'wait' => const AuthStatus._(AuthState.pending, null),
      'ok' => const AuthStatus._(AuthState.ok, null),
      'error' => AuthStatus._(
        AuthState.error,
        json['error'] as String? ?? 'Authentication failed',
      ),
      final other => throw CliproxyProtocolError('unknown auth status: $other'),
    };
  }

  final AuthState state;

  /// Set when [state] is [AuthState.error].
  final String? error;

  bool get isPending => state == AuthState.pending;
  bool get isOk => state == AuthState.ok;
}

/// One entry of the sidecar `GET /v1/models` catalogue (`{id, object,
/// created?, owned_by?}`, filtered by `OpenAIModels` to those four fields).
final class SidecarModel {
  const SidecarModel({required this.id, this.ownedBy});

  factory SidecarModel.fromJson(Map<String, Object?> json) => SidecarModel(
    id: json['id'] as String? ?? '',
    ownedBy: json['owned_by'] as String?,
  );

  /// Model id as the chat API expects it, verbatim from the sidecar catalogue.
  final String id;

  /// Vendor from the embedded catalogue (e.g. `meta`, `anthropic`); absent
  /// for models without static metadata.
  final String? ownedBy;
}

/// One credential file from `GET /v0/management/auth-files`
/// (`buildAuthFileEntryLocked`): tolerant reader over the fields bridge cards
/// need; unknown fields are ignored.
final class AuthFile {
  const AuthFile({
    required this.id,
    required this.name,
    required this.provider,
    required this.label,
    required this.status,
    required this.statusMessage,
    required this.disabled,
    required this.unavailable,
    this.email,
  });

  factory AuthFile.fromJson(Map<String, Object?> json) => AuthFile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    provider: json['provider'] as String? ?? json['type'] as String? ?? '',
    label: json['label'] as String? ?? '',
    status: json['status'] as String? ?? '',
    statusMessage: json['status_message'] as String? ?? '',
    disabled: json['disabled'] as bool? ?? false,
    unavailable: json['unavailable'] as bool? ?? false,
    email: json['email'] as String?,
  );

  final String id;
  final String name;
  final String provider;
  final String label;

  /// Credential status (`active`, …).
  final String status;
  final String statusMessage;
  final bool disabled;
  final bool unavailable;
  final String? email;

  bool get usable => !disabled && !unavailable;
}

/// Typed client of the CLIProxyAPI management API (`/v0/management/*`).
///
/// Authentication follows `Handler.Middleware()`: the management key goes in
/// `Authorization: Bearer <key>` (with `X-Management-Key` as the accepted
/// alias); this client sends the Bearer form.
final class CliproxyManagement {
  CliproxyManagement(
    this._client, {
    required this.baseUrl,
    required this.managementKey,
  });

  final http.Client _client;

  /// Sidecar origin, e.g. `http://127.0.0.1:8317`.
  final Uri baseUrl;
  final String managementKey;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $managementKey',
    'Accept': 'application/json',
  };

  Uri _resolve(String path, [Map<String, String>? query]) => baseUrl
      .resolve(path.startsWith('/') ? path.substring(1) : path)
      .replace(queryParameters: query == null || query.isEmpty ? null : query);

  Future<Map<String, Object?>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final http.Response response;
    try {
      response = await _client.get(_resolve(path, query), headers: _headers);
    } on http.ClientException catch (e) {
      throw CliproxyUnreachable('${baseUrl.origin}: ${e.message}');
    }
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    Object? body;
    final text = response.body.trim();
    if (text.isNotEmpty) {
      try {
        body = jsonDecode(text);
      } on FormatException {
        body = null; // Non-JSON error page: fall back to the status line.
      }
    }
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw CliproxyAuthFailed(_detail(response, body), statusCode: status);
    }
    if (status < 200 || status >= 300) {
      throw CliproxyHttpError(status, _detail(response, body));
    }
    if (body is! Map<String, Object?>) {
      throw CliproxyProtocolError(
        'expected a JSON object, got: ${response.body}',
      );
    }
    if (body['error'] case final String error when body['status'] != 'ok') {
      throw CliproxyProtocolError(error);
    }
    return body;
  }

  String _detail(http.Response response, Object? body) {
    if (body is Map<String, Object?>) {
      final detail = body['error'] ?? body['message'];
      if (detail != null) return '$detail';
    }
    if (response.body.trim().isNotEmpty) return response.body.trim();
    return response.reasonPhrase ?? 'HTTP ${response.statusCode}';
  }

  /// Starts a subscription login for [provider]; open [AuthStart.url] (or show
  /// the device code) then poll [pollLogin] with [AuthStart.state].
  Future<AuthStart> startLogin(CliproxyProvider provider) async {
    final json = await _getJson('/v0/management/${provider.route}');
    return AuthStart.fromJson(json);
  }

  /// Polls a login started with [startLogin].
  Future<AuthStatus> pollLogin(String state) async {
    final json = await _getJson('/v0/management/get-auth-status', {
      'state': state,
    });
    return AuthStatus.fromJson(json);
  }

  /// Cancels a pending login (`DELETE /v0/management/oauth-session`).
  /// Returns whether a session was actually cancelled.
  Future<bool> cancelLogin(String state) async {
    final response = await _client.delete(
      _resolve('/v0/management/oauth-session', {'state': state}),
      headers: _headers,
    );
    final json = _decode(response);
    return json['cancelled'] as bool? ?? true;
  }

  /// Lists saved credential files (`GET /v0/management/auth-files`).
  ///
  /// The handler paginates only when `page`/`page_size` are passed; without
  /// them the response is `{observed_at, files: [...]}`.
  Future<List<AuthFile>> listAuthFiles({
    String? name,
    String? authIndex,
  }) async {
    final json = await _getJson('/v0/management/auth-files', {
      if (name != null && name.isNotEmpty) 'name': name,
      if (authIndex != null && authIndex.isNotEmpty) 'auth_index': authIndex,
    });
    final files = json['files'];
    if (files is! List) {
      throw CliproxyProtocolError('auth-files misses files: $json');
    }
    return [
      for (final file in files)
        if (file is Map<String, Object?>) AuthFile.fromJson(file),
    ];
  }

  /// Raw JSON text of credential file [name]
  /// (`GET /v0/management/auth-files/download?name=`, read from `auth-dir`).
  Future<String> downloadAuthFile(String name) async {
    final http.Response response;
    try {
      response = await _client.get(
        _resolve('/v0/management/auth-files/download', {'name': name}),
        headers: _headers,
      );
    } on http.ClientException catch (e) {
      throw CliproxyUnreachable('${baseUrl.origin}: ${e.message}');
    }
    final status = response.statusCode;
    // Errors are `{error}` objects: [_decode] throws the mapped exception.
    if (status < 200 || status >= 300) _decode(response);
    // JSON is UTF-8 whatever the headers say.
    return utf8.decode(response.bodyBytes);
  }

  /// Saves [content] (credential JSON) as file [name] and registers it at once
  /// (`POST /v0/management/auth-files?name=` with the raw JSON body).
  Future<void> uploadAuthFile(String name, String content) async {
    final http.Response response;
    try {
      response = await _client.post(
        _resolve('/v0/management/auth-files', {'name': name}),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: content,
      );
    } on http.ClientException catch (e) {
      throw CliproxyUnreachable('${baseUrl.origin}: ${e.message}');
    }
    _decode(response);
  }

  /// Removes credential file [name] (`DELETE /v0/management/auth-files?name=`);
  /// a missing file is a [CliproxyHttpError] 404.
  Future<void> deleteAuthFile(String name) async {
    final http.Response response;
    try {
      response = await _client.delete(
        _resolve('/v0/management/auth-files', {'name': name}),
        headers: _headers,
      );
    } on http.ClientException catch (e) {
      throw CliproxyUnreachable('${baseUrl.origin}: ${e.message}');
    }
    _decode(response);
  }

  /// Lists models the sidecar can serve right now (`GET /v1/models`, the
  /// OpenAI-compatible catalogue from `unifiedModelsHandler` →
  /// `OpenAIModels`: `{object: "list", data: [{id, object, created?,
  /// owned_by?}]}`).
  ///
  /// Only models with at least one available (non-suspended, non-quota-dead)
  /// credential are advertised (`GetAvailableModels`), so a model listed here
  /// is actually callable. Authentication is the sidecar **API key**
  /// (`Authorization: Bearer`, per `config_access/provider.go`), not the
  /// management key.
  Future<List<SidecarModel>> listModels({required String apiKey}) async {
    final http.Response response;
    try {
      response = await _client.get(
        _resolve('/v1/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
    } on http.ClientException catch (e) {
      throw CliproxyUnreachable('${baseUrl.origin}: ${e.message}');
    }
    final body = _decode(response);
    final data = body['data'];
    if (data is! List) {
      throw CliproxyProtocolError('v1/models misses data: $body');
    }
    return [
      for (final entry in data)
        if (entry is Map<String, Object?>) SidecarModel.fromJson(entry),
    ];
  }

  /// Readiness probe used before login calls: the management API only answers
  /// once a management key is configured (`server.go hasManagementSecret`).
  Future<bool> ping() async {
    try {
      await _getJson('/v0/management/config');
      return true;
    } on CliproxyException {
      return false;
    }
  }
}

/// Builds the JSON body for Hermes `POST /api/providers/custom-endpoints`
/// pointing a named endpoint at a CLIProxyAPI sidecar.
///
/// Field names follow `hermes_cli/web_models.py CustomEndpointUpdate`
/// (`name`, `base_url`, `model`, `api_key`, `discover_models`, `models`);
/// `base_url` must include scheme and host. `chatCompletionsPath` selects the
/// Chat-Completions transport Hermes defaults to for custom endpoints; pass
/// `null` to leave any hand-written `api_mode` alone.
///
/// [models] is the discovered catalogue to persist alongside the endpoint
/// (Hermes merges it into the entry's `models` map, so the picker offers the
/// full set even before its own live probe runs).
Map<String, Object?> hermesCustomEndpoint({
  required Uri cliproxyBaseUrl,
  required String apiKey,
  required String name,
  required String model,
  List<String> models = const [],
  bool discoverModels = true,
  bool? chatCompletionsPath,
}) => {
  'name': name,
  'base_url': cliproxyBaseUrl.replace(path: '/v1').toString(),
  'model': model,
  'api_key': apiKey,
  if (models.isNotEmpty) 'models': models,
  if (chatCompletionsPath != null)
    'api_mode': chatCompletionsPath ? 'chat_completions' : '',
  'discover_models': discoverModels,
};
