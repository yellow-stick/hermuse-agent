import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'instance.dart';

/// Public `/api/status` probe result (no auth needed).
final class HermesStatus {
  const HermesStatus({
    required this.version,
    required this.authRequired,
    required this.authProviders,
    required this.authFlows,
    required this.raw,
  });

  factory HermesStatus.fromJson(Map<String, Object?> json) => HermesStatus(
    version: json['version'] as String? ?? '',
    authRequired: json['auth_required'] as bool? ?? false,
    authProviders: [...?(json['auth_providers'] as List?)?.cast<String>()],
    authFlows: [...?(json['auth_flows'] as List?)?.cast<String>()],
    raw: json,
  );

  /// Hermes release, e.g. `0.21.5`.
  final String version;

  /// True when the dashboard gate is engaged (cookie/ticket auth).
  final bool authRequired;

  /// Registered auth providers, e.g. `basic`, `nous`, `self_hosted`.
  final List<String> authProviders;

  /// `cookie` and/or `native_pkce`.
  final List<String> authFlows;
  final Map<String, Object?> raw;

  /// How a client signs in to this Hermes: no dashboard gate means the
  /// session token `hermes serve` always puts on `/api/ws`
  /// (`HERMES_DASHBOARD_SESSION_TOKEN`); a gate with the `basic` provider
  /// means username and password. Null when the only providers are ones
  /// Hermuse cannot use.
  AuthMethod? get loginMethod => !authRequired
      ? AuthMethod.loopbackToken
      : authProviders.contains('basic')
      ? AuthMethod.password
      : null;
}

/// The Hermes minor line this build's generated contract targets.
const supportedHermesLine = '0.21';

/// Throws [UnsupportedServerVersion] unless [version] is on [supportedHermesLine].
void checkSupportedVersion(String version) {
  final clean = version.startsWith('v') ? version.substring(1) : version;
  if (clean != supportedHermesLine &&
      !clean.startsWith('$supportedHermesLine.')) {
    throw UnsupportedServerVersion(version, supportedHermesLine);
  }
}

/// Hermes Agent releases Hermuse works with (its plugin's `requires_hermes`),
/// as a version specifier.
const supportedHermesVersions = '>=0.21.5 <0.22';

/// First `X.Y.Z` release in a text, plus what follows it (`rc1`, `.post1`,
/// `+local`, …).
final _releasePattern = RegExp(r'(\d+)\.(\d+)\.(\d+)([0-9A-Za-z.+-]*)');

/// A pre-release or development suffix: sorts before the release itself.
final _preReleasePattern = RegExp(
  r'^[-.]?(?:a|alpha|b|beta|c|rc|pre|preview|dev)\d*',
  caseSensitive: false,
);

/// The release [text] names (`0.21.5`, `0.22.0rc1`, …), or null when it
/// names none. [text] is a bare version (`/api/status`) or a `--version`
/// line (`Hermes Agent v0.21.5 (2026.9.24) · upstream 130b8f2c`).
String? hermesVersionOf(String text) =>
    _releasePattern.firstMatch(text)?.group(0);

/// Whether the release [text] names is within [supportedHermesVersions]. A
/// pre-release of 0.21.5 is below the floor and none of 0.22 is admitted
/// (PEP 440).
bool hermesVersionSupported(String text) {
  final match = _releasePattern.firstMatch(text);
  if (match == null) return false;
  final major = int.tryParse(match[1]!);
  final minor = int.tryParse(match[2]!);
  final patch = int.tryParse(match[3]!);
  if (major != 0 || minor != 21 || patch == null || patch < 5) return false;
  return patch > 5 || !_preReleasePattern.hasMatch(match[4]!);
}

/// Minimal typed client of the dashboard REST API.
///
/// Authentication is either the loopback [sessionToken] header or the cookie
/// session obtained by [passwordLogin]. Cookies are held in memory only; on
/// the web the browser owns them and the jar stays empty.
final class HermesRestClient {
  HermesRestClient(this._client, {required this.baseUrl, this.sessionToken});

  final Uri baseUrl;
  final String? sessionToken;
  final http.Client _client;
  final Map<String, String> _cookies = {};

  /// Whether a cookie session is held (native platforms only).
  bool get hasCookieSession => _cookies.isNotEmpty;

  Uri resolve(String path, [Map<String, String>? query]) => baseUrl.replace(
    path: '${baseUrl.path}$path',
    queryParameters: query == null || query.isEmpty ? null : query,
  );

  Future<HermesStatus> getStatus() async =>
      HermesStatus.fromJson(await getJson('/api/status'));

  /// `POST /auth/password-login`; stores the session cookies.
  Future<void> passwordLogin({
    required String username,
    required String password,
    String provider = 'basic',
  }) async {
    await postJson('/auth/password-login', {
      'provider': provider,
      'username': username,
      'password': password,
    });
  }

  /// Single-use 30 s ticket for the `/api/ws` upgrade (gated mode only).
  Future<String> mintWsTicket() async {
    final body = await postJson('/api/auth/ws-ticket', const {});
    return body['ticket'] as String;
  }

  Future<Map<String, Object?>> listSessions({int limit = 50, int offset = 0}) =>
      getJson('/api/sessions', {'limit': '$limit', 'offset': '$offset'});

  /// OAuth-capable providers and their login state.
  Future<Map<String, Object?>> getProviders() =>
      getJson('/api/providers/oauth');

  /// Starts a device-code / PKCE flow; returns `session_id`, URL and code.
  Future<Map<String, Object?>> startOAuth(String providerId) => postJson(
    '/api/providers/oauth/${Uri.encodeComponent(providerId)}/start',
    const {},
  );

  Future<Map<String, Object?>> pollOAuth(
    String providerId,
    String sessionId,
  ) => getJson(
    '/api/providers/oauth/${Uri.encodeComponent(providerId)}/poll/${Uri.encodeComponent(sessionId)}',
  );

  Future<Map<String, Object?>> getModelOptions() =>
      getJson('/api/model/options');

  Future<Map<String, Object?>> setModel(Map<String, Object?> body) =>
      postJson('/api/model/set', body);

  Future<Map<String, Object?>> getJson(
    String path, [
    Map<String, String>? query,
  ]) => _send('GET', path, query: query);

  Future<Map<String, Object?>> postJson(String path, Object? body) =>
      _send('POST', path, body: body);

  Future<Map<String, Object?>> putJson(String path, Object? body) =>
      _send('PUT', path, body: body);

  Future<Map<String, Object?>> delete(String path) => _send('DELETE', path);

  /// `DELETE` with a JSON body (`DELETE /api/env` takes `{key, profile?}`).
  Future<Map<String, Object?>> deleteWithBody(String path, Object? body) =>
      _send('DELETE', path, body: body);

  /// `GET` of a binary body (images), with the same auth and error mapping
  /// as the JSON calls.
  Future<Uint8List> getBytes(String path, [Map<String, String>? query]) async =>
      (await _request('GET', path, query: query)).bodyBytes;

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final response = await _request(method, path, query: query, body: body);
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, Object?> ? decoded : {'data': decoded};
  }

  /// Sends one authenticated request; throws on transport failures and
  /// non-2xx statuses.
  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final request = http.Request(method, resolve(path, query))
      ..headers['accept'] = 'application/json'
      ..followRedirects = false;
    if (sessionToken case final token?) {
      request.headers['x-hermes-session-token'] = token;
    }
    if (_cookies.isNotEmpty) {
      request.headers['cookie'] = [
        for (final e in _cookies.entries) '${e.key}=${e.value}',
      ].join('; ');
    }
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e) {
      throw HermesUnreachable('${request.url.origin}: ${e.message}');
    }
    _storeCookies(response.headers['set-cookie']);
    final status = response.statusCode;
    if (status == 401 || status == 403 || status == 429) {
      throw HermesAuthFailed(_detail(response), statusCode: status);
    }
    if (status < 200 || status >= 300) {
      throw HermesHttpError(status, '$method $path: ${_detail(response)}');
    }
    return response;
  }

  String _detail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] != null) return '${body['detail']}';
    } on FormatException {
      // Not JSON: fall through to the status line.
    }
    return 'HTTP ${response.statusCode}';
  }

  void _storeCookies(String? header) {
    if (header == null || header.isEmpty) return;
    // `http` joins repeated Set-Cookie with ','; `Expires` dates contain one too.
    for (final cookie in header.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
      final attrs = cookie.split(';').map((a) => a.trim()).toList();
      final eq = attrs.first.indexOf('=');
      if (eq <= 0) continue;
      final name = attrs.first.substring(0, eq);
      final value = attrs.first.substring(eq + 1);
      final expired = attrs.any(
        (a) =>
            a.toLowerCase() == 'max-age=0' || a.toLowerCase() == 'max-age=-1',
      );
      if (expired || value.isEmpty) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  /// Drops the cookie session (logout or credential change).
  void clearSession() => _cookies.clear();
}
