// The shelf application: routing, admin auth, CSRF checks, HTTP reverse
// proxy with relay-side cookie jar, and WebSocket bridging.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'config.dart';
import 'cookie_jar.dart';
import 'normalize.dart';
import 'registry.dart';

/// Builds the relay [Handler]. [client] sends upstream requests (inject a
/// fake in tests); [registry] and [jar] are shared mutable state.
Handler buildHandler({
  required RelayConfig config,
  required UpstreamRegistry registry,
  required CookieJar jar,
  http.Client? client,
}) {
  final httpClient = client ?? http.Client();

  Future<Response> proxy(Request request, String id, String rest) async {
    final upstream = registry.byId(id);
    if (upstream == null) return _json(404, {'error': 'unknown upstream'});
    final target = upstreamTarget(
      Uri.parse(upstream.baseUrl),
      rest,
      request.url.query,
    );
    if (target == null) return _json(400, {'error': 'invalid path'});

    // WebSocket upgrade on the same prefix: /hermes/<id>/api/ws?...
    if (_isWsUpgrade(request)) {
      return _proxyWs(request, config, jar, upstream, target);
    }
    return _proxyHttp(request, config, jar, httpClient, upstream, target);
  }

  final router = Router()
    ..get('/relay/health', (_) => _json(200, {'ok': true}))
    ..get('/relay/resolve', (Request request) {
      final raw = request.url.queryParameters['url'];
      if (raw == null || raw.trim().isEmpty) {
        return _json(400, {'error': 'missing ?url='});
      }
      late final String normalized;
      try {
        normalized = normalizeUpstreamUrl(raw);
      } on FormatException catch (e) {
        return _json(400, {'error': e.message});
      }
      final upstream = registry.byUrl(normalized);
      if (upstream == null) return _json(404, {'error': 'not registered'});
      return _json(200, {'id': upstream.id, 'label': upstream.label});
    })
    ..get('/admin/upstreams', (Request request) {
      if (!_isAdmin(request, config)) {
        return _json(401, {'error': 'unauthorized'});
      }
      return _json(200, {
        'upstreams': [for (final u in registry.list()) u.toJson()],
      });
    })
    ..post('/admin/upstreams', (Request request) async {
      if (!_isAdmin(request, config)) {
        return _json(401, {'error': 'unauthorized'});
      }
      final csrf = _checkCsrf(request, config);
      if (csrf != null) return csrf;
      late final Map<String, Object?> body;
      try {
        body = jsonDecode(await request.readAsString()) as Map<String, Object?>;
      } on FormatException {
        return _json(400, {'error': 'invalid JSON body'});
      }
      final rawUrl = body['base_url'];
      if (rawUrl is! String || rawUrl.trim().isEmpty) {
        return _json(400, {'error': 'base_url is required'});
      }
      late final String normalized;
      try {
        normalized = normalizeUpstreamUrl(rawUrl);
      } on FormatException catch (e) {
        return _json(400, {'error': e.message});
      }
      final label = body['label'];
      if (label != null && label is! String) {
        return _json(400, {'error': 'label must be a string'});
      }
      final upstream = registry.register(
        normalized,
        label is String && label.trim().isNotEmpty ? label.trim() : null,
      );
      return _json(200, {'id': upstream.id});
    })
    ..delete('/admin/upstreams/<id>', (Request request, String id) {
      if (!_isAdmin(request, config)) {
        return _json(401, {'error': 'unauthorized'});
      }
      final csrf = _checkCsrf(request, config);
      if (csrf != null) return csrf;
      if (!registry.remove(id)) return _json(404, {'error': 'unknown id'});
      return _json(200, {'ok': true});
    })
    // Proxy: every method under /hermes/<id>/ (and bare /hermes/<id>).
    ..all(
      '/hermes/<id>',
      (Request request, String id) => proxy(request, id, ''),
    )
    ..all('/hermes/<id>/<rest|.*>', (Request request, String id, String rest) {
      return proxy(request, id, rest);
    });

  Handler handler = router.call;
  final staticDir = config.staticDir;
  if (staticDir != null) {
    final fileHandler = createStaticHandler(
      staticDir,
      defaultDocument: 'index.html',
    );
    final relay = handler;
    handler = (Request request) async {
      final response = await relay(request);
      // Fall through to static files only when the relay has no route.
      if (response.statusCode != 404) return response;
      final fileResponse = await fileHandler(request);
      if (fileResponse.statusCode != 404) return fileResponse;
      // SPA fallback: unknown non-API paths serve index.html so client-side
      // routing works when served same-origin.
      if (request.method == 'GET' &&
          !request.url.path.startsWith('hermes/') &&
          !request.url.path.startsWith('admin/') &&
          !request.url.path.startsWith('relay/')) {
        return fileHandler(
          Request('GET', request.requestedUri.replace(path: '/index.html')),
        );
      }
      return response;
    };
  }
  return handler;
}

/// Joins [rest] under [base] as path segments. Returns null when [rest]
/// could leave the upstream: empty/dot segments (`//host`, `..`) would let
/// `Uri.resolve` switch host or escape the base path (SSRF).
Uri? upstreamTarget(Uri base, String rest, String query) {
  final segments = rest.isEmpty ? const <String>[] : rest.split('/');
  if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
  final decoded = <String>[];
  for (final s in segments) {
    final String value;
    try {
      value = Uri.decodeComponent(s);
    } on ArgumentError {
      return null;
    }
    // Encoded separators or dots must not reappear as structure upstream.
    if (value.contains('/') ||
        value.contains('\\') ||
        value == '..' ||
        value == '.') {
      return null;
    }
    decoded.add(value);
  }
  return base.replace(
    pathSegments: [
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...decoded,
      if (decoded.isEmpty) '',
    ],
    query: query.isEmpty ? null : query,
  );
}

/// True when [request] is an RFC 6455 upgrade request.
bool _isWsUpgrade(Request request) {
  if (request.method != 'GET') return false;
  final connection = request.headers['connection'];
  if (connection == null) return false;
  final tokens = connection.toLowerCase().split(',').map((t) => t.trim());
  if (!tokens.contains('upgrade')) return false;
  final upgrade = request.headers['upgrade'];
  if (upgrade == null || upgrade.toLowerCase() != 'websocket') return false;
  if (request.headers['sec-websocket-key'] == null) return false;
  final version = request.headers['sec-websocket-version'];
  return version == '13';
}

/// Builds the `Set-Cookie` header for a relay session. [isSecure] enables the
/// Secure attribute (only when served over https).
String sessionSetCookie(String sessionId, {required bool isSecure}) {
  final secure = isSecure ? '; Secure' : '';
  return '$sessionCookieName=$sessionId; Path=/; HttpOnly$secure; '
      'SameSite=Strict';
}

/// Bearer check with constant-time comparison (length + xor accumulation).
bool _isAdmin(Request request, RelayConfig config) {
  final auth = request.headers['authorization'];
  if (auth == null || !auth.startsWith('Bearer ')) return false;
  return _constantTimeEquals(auth.substring(7).trim(), config.adminToken);
}

bool _constantTimeEquals(String a, String b) {
  final aBytes = utf8.encode(a);
  final bBytes = utf8.encode(b);
  var diff = aBytes.length ^ bBytes.length;
  for (var i = 0; i < aBytes.length && i < bBytes.length; i++) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff == 0;
}

/// CSRF check: state-changing requests (anything but GET/HEAD/OPTIONS) must
/// carry `Origin: <HERMUSE_RELAY_ORIGIN>`. Returns `null` when the request
/// may proceed, otherwise the 403 [Response]. Disabled when no origin is
/// configured (local development).
Response? _checkCsrf(Request request, RelayConfig config) {
  if (config.origin.isEmpty) return null;
  if (request.method == 'GET' ||
      request.method == 'HEAD' ||
      request.method == 'OPTIONS') {
    return null;
  }
  if (request.headers['origin'] == config.origin) return null;
  return _json(403, {'error': 'bad origin'});
}

Future<Response> _proxyHttp(
  Request request,
  RelayConfig config,
  CookieJar jar,
  http.Client client,
  Upstream upstream,
  Uri target,
) async {
  final csrf = _checkCsrf(request, config);
  if (csrf != null) return csrf;

  // Sessions are created only when an upstream sets a cookie, so anonymous
  // traffic cannot grow the jar.
  var sessionId = CookieJar.sessionIdFromCookieHeader(
    request.headers['cookie'],
  );
  if (!jar.lookup(sessionId)) sessionId = null;
  String? newSessionCookie;

  final isSecureTarget = target.scheme == 'https';
  final outHeaders = <String, String>{};
  for (final entry in request.headers.entries) {
    final name = entry.key.toLowerCase();
    // Stripped: browser cookies (jar replays instead), origin/referer/host
    // (upstream must see its own authority — Hermes validates Host against
    // its bound address), and hop-by-hop headers.
    if (name == 'cookie' ||
        name == 'origin' ||
        name == 'referer' ||
        name == 'host' ||
        name == 'connection' ||
        name == 'keep-alive' ||
        name == 'proxy-connection' ||
        name == 'transfer-encoding' ||
        name == 'upgrade' ||
        name == 'trailer' ||
        name == 'te' ||
        name == 'proxy-authenticate' ||
        name == 'proxy-authorization') {
      continue;
    }
    if (name == 'content-length') continue; // recomputed by http client
    outHeaders[entry.key] = entry.value;
  }
  outHeaders['host'] = target.authority;
  final jarCookie = sessionId == null
      ? null
      : jar.headerFor(sessionId, upstream.id, target, isSecure: isSecureTarget);
  if (jarCookie != null) outHeaders['cookie'] = jarCookie;

  final upstreamReq = http.StreamedRequest(request.method, target)
    ..headers.addAll(outHeaders);
  final requestLength = request.contentLength;
  if (requestLength != null) upstreamReq.contentLength = requestLength;
  unawaitedBytes(upstreamReq.sink, request.read());

  late final http.StreamedResponse upstreamRes;
  try {
    upstreamRes = await client.send(upstreamReq);
  } on Object {
    return _withSession(
      _json(502, {'error': 'upstream unreachable'}),
      newSessionCookie,
    );
  }

  final setCookies =
      upstreamRes.headersSplitValues['set-cookie'] ?? const <String>[];
  if (setCookies.isNotEmpty) {
    if (sessionId == null) {
      sessionId = jar.create();
      final tls =
          request.requestedUri.scheme == 'https' ||
          (request.headers['x-forwarded-proto']?.split(',').first.trim() ==
              'https');
      newSessionCookie = sessionSetCookie(sessionId, isSecure: tls);
    }
    jar.store(sessionId, upstream.id, target, setCookies);
  }

  final resHeaders = <String, String>{};
  upstreamRes.headers.forEach((name, value) {
    final lower = name.toLowerCase();
    // NEVER forward upstream Set-Cookie to the browser; strip hop-by-hop.
    if (lower == 'set-cookie' ||
        lower == 'connection' ||
        lower == 'keep-alive' ||
        lower == 'proxy-connection' ||
        lower == 'transfer-encoding' ||
        lower == 'upgrade' ||
        lower == 'trailer' ||
        lower == 'content-length') {
      return;
    }
    resHeaders[name] = value;
  });
  // Stream the body (SSE/large responses) rather than buffering.
  return _withSession(
    Response(
      upstreamRes.statusCode,
      body: upstreamRes.stream,
      headers: resHeaders,
    ),
    newSessionCookie,
  );
}

Response _withSession(Response response, String? newSessionCookie) {
  if (newSessionCookie == null) return response;
  return response.change(headers: {'set-cookie': newSessionCookie});
}

/// Bridges a browser WebSocket on `/hermes/<id>/...` to the upstream WS
/// endpoint. The browser Origin must equal the configured origin; the
/// upstream dial carries jar cookies and no Origin header.
///
/// Implemented on dart:io directly (instead of `WebSocketChannel.connect`,
/// which cannot attach headers) so the jar's cookies reach the upstream.
/// `WebSocket.connect` sends no Origin header unless asked, satisfying
/// Hermes' mismatching-Origin rejection.
Future<Response> _proxyWs(
  Request request,
  RelayConfig config,
  CookieJar jar,
  Upstream upstream,
  Uri httpTarget,
) async {
  // shelf_web_socket enforces allowedOrigins itself (403 on mismatch); this
  // explicit check keeps the behaviour visible and testable at this layer.
  if (config.origin.isNotEmpty && request.headers['origin'] != config.origin) {
    return _json(403, {'error': 'bad origin'});
  }
  final cookieSession = CookieJar.sessionIdFromCookieHeader(
    request.headers['cookie'],
  );
  final sessionId = jar.lookup(cookieSession) ? cookieSession : null;
  final wsTarget = httpTarget.replace(
    scheme: httpTarget.scheme == 'https' ? 'wss' : 'ws',
  );
  return webSocketHandler((WebSocketChannel browser, String? protocol) async {
    final headers = <String, dynamic>{};
    final jarCookie = sessionId == null
        ? null
        : jar.headerFor(
            sessionId,
            upstream.id,
            httpTarget,
            isSecure: httpTarget.scheme == 'https',
          );
    if (jarCookie != null) headers[HttpHeaders.cookieHeader] = jarCookie;
    if (protocol != null) headers['Sec-WebSocket-Protocol'] = protocol;
    late final WebSocket upstreamSocket;
    try {
      // No 'Origin' key: dart:io only sends Origin when explicitly provided.
      upstreamSocket = await WebSocket.connect(
        wsTarget.toString(),
        headers: headers.isEmpty ? null : headers,
        protocols: protocol == null ? null : [protocol],
      );
    } on Object {
      await browser.sink.close(1011);
      return;
    }
    // Pipe text/binary frames both ways; propagate close codes (mapping the
    // "no status received" 1005 sentinel to null — it is not a valid code to
    // send on the wire and dart:io throws on it).
    int? cleanCode(int? code) => code == 1005 ? null : code;
    browser.stream.listen(
      (Object? message) => upstreamSocket.add(message),
      onError: (_) => upstreamSocket.close(1011),
      onDone: () => upstreamSocket.close(
        cleanCode(browser.closeCode),
        browser.closeReason,
      ),
      cancelOnError: false,
    );
    upstreamSocket.listen(
      (Object? message) => browser.sink.add(message),
      onError: (_) => browser.sink.close(1011),
      onDone: () => browser.sink.close(
        cleanCode(upstreamSocket.closeCode),
        upstreamSocket.closeReason,
      ),
      cancelOnError: false,
    );
  }, allowedOrigins: config.origin.isEmpty ? null : [config.origin])(request);
}

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

/// Forwards [body] into [sink] without awaiting (the http client consumes the
/// sink while we stream).
void unawaitedBytes(StreamSink<List<int>> sink, Stream<List<int>> body) {
  body.listen(
    sink.add,
    onError: sink.addError,
    onDone: sink.close,
    cancelOnError: false,
  );
}
