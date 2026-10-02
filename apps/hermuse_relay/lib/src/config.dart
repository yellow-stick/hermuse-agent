import 'normalize.dart';

// Relay configuration, parsed from environment variables.
class RelayConfig {
  /// TCP port to listen on. Defaults to 8787.
  final int port;

  /// Path of the sqlite database holding the upstream registry.
  final String dbPath;

  /// Bearer token guarding the /admin/* endpoints. Required.
  final String adminToken;

  /// Public origin of the web app (e.g. https://chat.example.com), used for
  /// the CSRF Origin check and the WebSocket origin check. Required by
  /// [RelayConfig.fromEnv]; only in-process tests construct it empty.
  final String origin;

  /// Optional directory holding the built Jaspr site, served same-origin.
  final String? staticDir;

  /// Hermes dashboard base URLs (normalised) registered at startup, from the
  /// comma-separated `HERMUSE_RELAY_UPSTREAMS`. Registration is idempotent.
  final List<String> upstreams;

  const RelayConfig({
    this.port = 8787,
    this.dbPath = 'hermuse_relay.db',
    required this.adminToken,
    required this.origin,
    this.staticDir,
    this.upstreams = const [],
  });

  /// Reads configuration from [env] (defaults to `Platform.environment`).
  /// Throws [StateError] when the required admin token is missing or a value
  /// is malformed; `bin/server.dart` turns that into "refuse to start".
  factory RelayConfig.fromEnv(Map<String, String> env) {
    final token = (env['HERMUSE_RELAY_ADMIN_TOKEN'] ?? '').trim();
    if (token.isEmpty) {
      throw StateError(
        'HERMUSE_RELAY_ADMIN_TOKEN is required; refusing to start.',
      );
    }
    final portRaw = (env['HERMUSE_RELAY_PORT'] ?? '8787').trim();
    final port = int.tryParse(portRaw);
    if (port == null || port < 0 || port > 65535) {
      throw StateError('HERMUSE_RELAY_PORT "$portRaw" is not a valid port.');
    }
    final origin = (env['HERMUSE_RELAY_ORIGIN'] ?? '').trim();
    final originUri = Uri.tryParse(origin);
    if (originUri == null ||
        !const {'http', 'https'}.contains(originUri.scheme) ||
        originUri.host.isEmpty ||
        originUri.hasQuery ||
        (originUri.path.isNotEmpty && originUri.path != '/')) {
      throw StateError(
        'HERMUSE_RELAY_ORIGIN must be the web app origin, e.g. '
        'https://chat.example.com; refusing to start.',
      );
    }
    final staticDir = env['HERMUSE_RELAY_STATIC_DIR']?.trim();
    final upstreams = <String>[];
    for (final entry in (env['HERMUSE_RELAY_UPSTREAMS'] ?? '').split(',')) {
      if (entry.trim().isEmpty) continue;
      try {
        final url = normalizeUpstreamUrl(entry);
        if (!upstreams.contains(url)) upstreams.add(url);
      } on FormatException catch (e) {
        throw StateError(
          'HERMUSE_RELAY_UPSTREAMS: ${e.message}; refusing to start.',
        );
      }
    }
    return RelayConfig(
      port: port,
      dbPath: (env['HERMUSE_RELAY_DB'] ?? 'hermuse_relay.db').trim(),
      adminToken: token,
      origin: originUri.origin,
      staticDir: staticDir == null || staticDir.isEmpty ? null : staticDir,
      upstreams: upstreams,
    );
  }
}
