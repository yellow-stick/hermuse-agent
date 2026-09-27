// Relay-side cookie jar: upstream Set-Cookie headers are stored server-side,
// keyed by opaque relay session id + upstream id, and replayed as Cookie
// headers on later upstream requests. The browser only ever sees the
// HttpOnly `hermuse_relay_sid` session cookie.
library;

import 'dart:math';

/// Name of the opaque relay session cookie set on the browser.
const sessionCookieName = 'hermuse_relay_sid';

/// Sessions idle for longer than this are dropped.
const sessionIdleTimeout = Duration(hours: 12);

/// A stored upstream cookie: name=value plus scope (domain/path subset we
/// honour) and expiry. Public so tests can assert on jar behaviour through
/// [CookieJar.cookiesForTest].
class JarCookie {
  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expiresAt;
  final bool secureOnly;

  JarCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.expiresAt,
    required this.secureOnly,
  });

  bool get expired =>
      expiresAt != null && !DateTime.now().toUtc().isBefore(expiresAt!);

  @override
  String toString() => '$name=$value (domain=$domain path=$path)';
}

/// Per-browser-session state: upstream cookie stores plus last-use time.
class _Session {
  DateTime lastUsed = DateTime.now().toUtc();
  final Map<String, List<JarCookie>> cookiesByUpstream = {};
}

/// In-memory jar: `sessionId -> upstreamId -> cookies`.
///
/// Sessions are created by [create] (called when a browser arrives without a
/// valid session cookie) and expire after [sessionIdleTimeout] without use.
/// Not persisted: a relay restart logs browsers out of upstreams, which is
/// the safe default.
class CookieJar {
  final Map<String, _Session> _sessions = {};
  final Random _random;

  CookieJar({Random? random}) : _random = random ?? Random.secure();

  /// Returns the session id from a `Cookie` header value, or `null`.
  static String? sessionIdFromCookieHeader(String? header) {
    if (header == null) return null;
    for (final part in header.split(';')) {
      final idx = part.indexOf('=');
      if (idx < 0) continue;
      if (part.substring(0, idx).trim() == sessionCookieName) {
        final value = part.substring(idx + 1).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Refreshes the last-use time of the session for [sessionId].
  /// Returns `true` when the session exists and is not idle-expired.
  bool lookup(String? sessionId) {
    final session = _sessions[sessionId];
    if (session == null) return false;
    if (DateTime.now().toUtc().difference(session.lastUsed) >
        sessionIdleTimeout) {
      _sessions.remove(sessionId);
      return false;
    }
    session.lastUsed = DateTime.now().toUtc();
    return true;
  }

  /// Creates a fresh session and returns its id (32 random bytes, hex).
  String create() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _sessions[id] = _Session();
    _evictExpired();
    return id;
  }

  /// Stores the `Set-Cookie` header values from an upstream response.
  void store(
    String sessionId,
    String upstreamId,
    Uri upstreamUri,
    List<String> setCookies,
  ) {
    final session = _sessions[sessionId];
    if (session == null) return;
    final jar = session.cookiesByUpstream.putIfAbsent(upstreamId, () => []);
    for (final header in setCookies) {
      final parsed = parseSetCookie(header, upstreamUri);
      if (parsed == null) continue;
      jar.removeWhere(
        (c) =>
            c.name == parsed.name &&
            c.domain == parsed.domain &&
            c.path == parsed.path,
      );
      if (!parsed.expired) jar.add(parsed);
    }
  }

  /// Builds the `Cookie` header value for an upstream request, or `null`
  /// when the jar holds nothing in scope.
  String? headerFor(
    String sessionId,
    String upstreamId,
    Uri target, {
    required bool isSecure,
  }) {
    final session = _sessions[sessionId];
    if (session == null) return null;
    final jar = session.cookiesByUpstream[upstreamId];
    if (jar == null) return null;
    jar.removeWhere((c) => c.expired);
    final pairs = <String>[];
    for (final c in jar) {
      if (c.secureOnly && !isSecure) continue;
      if (!_domainMatch(target.host.toLowerCase(), c.domain)) continue;
      if (!_pathMatch(target.path.isEmpty ? '/' : target.path, c.path)) {
        continue;
      }
      pairs.add('${c.name}=${c.value}');
    }
    if (pairs.isEmpty) return null;
    return pairs.join('; ');
  }

  int get sessionCount => _sessions.length;

  void _evictExpired() {
    final now = DateTime.now().toUtc();
    _sessions.removeWhere(
      (_, s) => now.difference(s.lastUsed) > sessionIdleTimeout,
    );
  }

  /// Test hook: override a session's last-use time to drive expiry.
  void debugSetLastUsed(String sessionId, DateTime t) {
    _sessions[sessionId]?.lastUsed = t;
  }
}

/// Minimal `Set-Cookie` parser honouring Domain/Path/Max-Age/Expires/Secure.
/// Unknown attributes are ignored. Returns `null` for malformed headers or
/// Domain values that do not cover [requestUri] (rejected outright so one
/// upstream can never plant cookies for another host).
JarCookie? parseSetCookie(String header, Uri requestUri) {
  final parts = header.split(';');
  if (parts.isEmpty) return null;
  final first = parts.first.trim();
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  final name = first.substring(0, eq).trim();
  var value = first.substring(eq + 1).trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  if (name.isEmpty) return null;

  var domain = requestUri.host.toLowerCase();
  var path = _defaultPath(requestUri.path);
  DateTime? expiresAt;
  var maxAgeSeen = false;
  var secureOnly = false;

  for (var i = 1; i < parts.length; i++) {
    final attr = parts[i].trim();
    final idx = attr.indexOf('=');
    final aName = (idx < 0 ? attr : attr.substring(0, idx))
        .trim()
        .toLowerCase();
    final aValue = idx < 0 ? '' : attr.substring(idx + 1).trim();
    switch (aName) {
      case 'domain':
        var d = aValue.toLowerCase();
        if (d.startsWith('.')) d = d.substring(1);
        // Reject cookies scoped to a host that does not cover the requester.
        if (!_domainMatch(requestUri.host.toLowerCase(), d)) return null;
        domain = d;
      case 'path':
        if (aValue.startsWith('/')) path = aValue;
      case 'max-age':
        final seconds = int.tryParse(aValue);
        if (seconds != null) {
          maxAgeSeen = true;
          expiresAt = DateTime.now().toUtc().add(Duration(seconds: seconds));
        }
      case 'expires':
        if (!maxAgeSeen) {
          try {
            expiresAt = DateTime.parse(aValue);
          } on FormatException {
            try {
              expiresAt = _httpDate(aValue);
            } on FormatException {
              expiresAt = null;
            }
          }
        }
      case 'secure':
        secureOnly = true;
    }
  }
  return JarCookie(
    name: name,
    value: value,
    domain: domain,
    path: path,
    expiresAt: expiresAt,
    secureOnly: secureOnly,
  );
}

String _defaultPath(String requestPath) {
  if (!requestPath.startsWith('/') || requestPath == '/') return '/';
  final lastSlash = requestPath.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return requestPath.substring(0, lastSlash);
}

bool _domainMatch(String host, String cookieDomain) {
  if (host == cookieDomain) return true;
  return host.endsWith('.$cookieDomain');
}

bool _pathMatch(String requestPath, String cookiePath) {
  if (requestPath == cookiePath) return true;
  if (requestPath.startsWith(cookiePath)) {
    if (cookiePath.endsWith('/')) return true;
    if (requestPath.length > cookiePath.length &&
        requestPath[cookiePath.length] == '/') {
      return true;
    }
  }
  return false;
}

DateTime _httpDate(String value) {
  // Parses IMF-fixdate, e.g. "Wed, 21 Oct 2015 07:28:00 GMT".
  const months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final m = RegExp(
    r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value.trim());
  if (m == null) throw FormatException('Not an HTTP date: $value');
  final month = months[m.group(2)!.toLowerCase()];
  if (month == null) throw FormatException('Bad month in $value');
  return DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
