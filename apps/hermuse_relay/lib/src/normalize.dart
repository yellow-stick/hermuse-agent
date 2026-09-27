// Canonicalisation of upstream URLs, shared by registration and resolve.
library;

/// Normalises a user-typed or registered upstream URL:
/// trims whitespace, lowercases scheme and host, drops default ports
/// (80/443) and any query/fragment, and strips trailing slashes.
///
/// Throws [FormatException] when [raw] is not an absolute http(s) URL.
String normalizeUpstreamUrl(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    throw FormatException('Not an absolute URL: "$raw".');
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw FormatException('Only http(s) upstreams are supported: "$raw".');
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) {
    throw FormatException('URL has no host: "$raw".');
  }
  final isDefaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  final port = uri.hasPort && !isDefaultPort ? ':${uri.port}' : '';
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') path = '';
  return '$scheme://$host$port$path';
}

/// Returns the origin (`scheme://host[:port]`) of an already-normalised URL.
String originOfNormalized(String normalized) {
  final uri = Uri.parse(normalized);
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
