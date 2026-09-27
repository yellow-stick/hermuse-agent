import 'dart:convert';

import 'package:http/http.dart' as http;

/// The Hermuse relay this web app talks to.
///
/// Browsers cannot reach Hermes instances directly (CORS is localhost-only
/// and `/api/ws` checks `Origin`), and the relay itself allows no
/// cross-origin callers (CSRF `Origin` check, `SameSite=Strict` session). So
/// the relay is always the origin that served this page:
///
/// - `GET <relay>/relay/health` → `{ok: true}` (detection)
/// - `GET <relay>/relay/resolve?url=<upstreamUrl>` → `{id, label}` (or 404)
/// - `ANY <relay>/hermes/<id>/<path>` → proxied to the upstream
final class Relay {
  const Relay._();

  /// Returns [page]'s origin when a Hermuse relay answers there, else null
  /// (the site is served by a plain static server).
  static Future<Uri?> detect(http.Client client, Uri page) async {
    final origin = Uri.parse(page.origin);
    try {
      final response = await client.get(origin.replace(path: '/relay/health'));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      return body is Map && body['ok'] == true ? origin : null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// The Hermes `baseUrl` of an instance behind upstream [upstreamId].
  static Uri instanceBase(Uri relay, String upstreamId) =>
      relay.replace(path: '${relay.path}/hermes/$upstreamId');

  /// Resolves a user-typed upstream URL to its relay id (`null` on 404).
  static Future<({String id, String label})?> resolve(
    http.Client client,
    Uri relay,
    String url,
  ) async {
    final response = await client.get(
      relay.replace(
        path: '${relay.path}/relay/resolve',
        queryParameters: {'url': url},
      ),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'relay resolve failed: HTTP ${response.statusCode}',
        response.request?.url,
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    // The relay returns `"label": null` when none was given at registration.
    return (id: body['id']! as String, label: body['label'] as String? ?? '');
  }
}
