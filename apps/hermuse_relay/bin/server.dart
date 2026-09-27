// Entry point: `dart run` / compiled `server`. Refuses to start without
// HERMUSE_RELAY_ADMIN_TOKEN.
import 'dart:io';

import 'package:hermuse_relay/src/config.dart';
import 'package:hermuse_relay/src/cookie_jar.dart';
import 'package:hermuse_relay/src/registry.dart';
import 'package:hermuse_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  late final RelayConfig config;
  try {
    config = RelayConfig.fromEnv(Platform.environment);
  } on StateError catch (e) {
    stderr.writeln('hermuse_relay: ${e.message}');
    exit(2);
  }
  final registry = UpstreamRegistry.open(config.dbPath);
  final jar = CookieJar();
  final handler = const Pipeline()
      // Query strings carry credentials (`?ticket=`, loopback `?token=`):
      // log method, path and status only.
      .addMiddleware(
        logRequests(
          logger: (message, isError) =>
              (isError ? stderr : stdout).writeln(_redactQuery(message)),
        ),
      )
      .addHandler(buildHandler(config: config, registry: registry, jar: jar));
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln(
    'hermuse_relay listening on port ${server.port} '
    '(origin=${config.origin})',
  );
}

/// Drops `?…` from a shelf log line (`<time> <elapsed> <METHOD> [<status>] <path?query>`).
String _redactQuery(String line) =>
    line.replaceAllMapped(RegExp(r'\?\S*'), (_) => '?<redacted>');
