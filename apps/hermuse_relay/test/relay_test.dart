// End-to-end tests: the relay handler plus a fake upstream shelf server,
// both served in-process on ephemeral ports.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:hermuse_relay/src/config.dart';
import 'package:hermuse_relay/src/cookie_jar.dart';
import 'package:hermuse_relay/src/normalize.dart';
import 'package:hermuse_relay/src/registry.dart';
import 'package:hermuse_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _adminToken = 'test-admin-token';
const _origin = 'http://localhost:9999';

/// Fake upstream dashboard state, observable by tests.
class FakeUpstream {
  String? lastHost;
  String? lastCookie;
  String? lastWsOrigin;
  String? lastWsCookie;
  final wsClosed = Completer<void>();

  Handler get handler {
    return (Request request) async {
      lastHost = request.headers['host'];
      lastCookie = request.headers['cookie'];
      if (request.url.path == 'login') {
        return Response.ok(
          'logged in',
          headers: {'set-cookie': 'session=abc123; Path=/'},
        );
      }
      if (request.url.path == 'whoami') {
        return Response.ok('cookie:${request.headers['cookie'] ?? '<none>'}');
      }
      if (request.url.path == 'echo-body') {
        return Response.ok(await request.readAsString());
      }
      if (request.url.path == 'submit') {
        return Response.ok('submitted');
      }
      if (request.url.path == 'ws') {
        return webSocketHandler((WebSocketChannel socket, String? protocol) {
          lastWsOrigin = request.headers['origin'];
          lastWsCookie = request.headers['cookie'];
          socket.stream.listen(
            (message) => socket.sink.add('echo:$message'),
            onDone: () {
              if (!wsClosed.isCompleted) wsClosed.complete();
            },
          );
        })(request);
      }
      return Response.notFound('nope');
    };
  }
}

class Harness {
  late final FakeUpstream fake;
  late final HttpServer upstreamServer;
  late final HttpServer relayServer;
  late final UpstreamRegistry registry;
  late final String upstreamId;
  final browser = http.Client();

  Uri get relayBase => Uri.parse('http://127.0.0.1:${relayServer.port}');

  Future<void> start() async {
    fake = FakeUpstream();
    upstreamServer = await shelf_io.serve(
      fake.handler,
      InternetAddress.loopbackIPv4,
      0,
    );
    registry = UpstreamRegistry(sqlite3.openInMemory());
    final config = RelayConfig(
      port: 0,
      dbPath: ':memory:',
      adminToken: _adminToken,
      origin: _origin,
    );
    relayServer = await shelf_io.serve(
      buildHandler(config: config, registry: registry, jar: CookieJar()),
      InternetAddress.loopbackIPv4,
      0,
    );
    final base = 'http://127.0.0.1:${upstreamServer.port}';
    upstreamId = registry.register(base, 'fake').id;
  }

  Map<String, String> get adminHeaders => {
    'authorization': 'Bearer $_adminToken',
    'origin': _origin,
    'content-type': 'application/json',
  };

  Uri relayUri(String path, [Map<String, String>? query]) =>
      relayBase.replace(path: path, queryParameters: query);

  Future<void> stop() async {
    browser.close();
    await relayServer.close(force: true);
    await upstreamServer.close(force: true);
    registry.close();
  }
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.start();
  });
  tearDown(() async {
    await h.stop();
  });

  test('health returns ok', () async {
    final res = await h.browser.get(h.relayUri('/relay/health'));
    expect(res.statusCode, 200);
    expect(jsonDecode(res.body), {'ok': true});
  });

  test('admin endpoints require the bearer token', () async {
    expect(
      (await h.browser.get(h.relayUri('/admin/upstreams'))).statusCode,
      401,
    );
    final wrong = await h.browser.get(
      h.relayUri('/admin/upstreams'),
      headers: {'authorization': 'Bearer wrong'},
    );
    expect(wrong.statusCode, 401);
    final ok = await h.browser.get(
      h.relayUri('/admin/upstreams'),
      headers: {'authorization': 'Bearer $_adminToken'},
    );
    expect(ok.statusCode, 200);
  });

  test('register is idempotent and resolve normalises URLs', () async {
    final base = 'http://127.0.0.1:${h.upstreamServer.port}';
    final res = await h.browser.post(
      h.relayUri('/admin/upstreams'),
      headers: h.adminHeaders,
      body: jsonEncode({'base_url': '$base/', 'label': 'local'}),
    );
    expect(res.statusCode, 200);
    final id = (jsonDecode(res.body) as Map)['id'] as String;

    // Same URL with different case, trailing slashes and query resolves equal.
    for (final variant in [
      base,
      '${base.toUpperCase()}///',
      '$base/?ticket=xyz',
      '  $base  ',
    ]) {
      final resolved = await h.browser.get(
        h.relayUri('/relay/resolve', {
          'url': variant.replaceFirst('HTTP', 'http'),
        }),
      );
      expect(resolved.statusCode, 200, reason: variant);
      expect((jsonDecode(resolved.body) as Map)['id'], id);
    }
    // Unknown URL → 404.
    final missing = await h.browser.get(
      h.relayUri('/relay/resolve', {'url': 'http://127.0.0.1:9'}),
    );
    expect(missing.statusCode, 404);

    // Deleting unknown id → 404; deleting the id removes it.
    final delMissing = await h.browser.delete(
      h.relayUri('/admin/upstreams/nope'),
      headers: h.adminHeaders,
    );
    expect(delMissing.statusCode, 404);
    final del = await h.browser.delete(
      h.relayUri('/admin/upstreams/$id'),
      headers: h.adminHeaders,
    );
    expect(del.statusCode, 200);
    expect(
      (await h.browser.get(h.relayUri('/relay/resolve', {'url': base})))
          .statusCode,
      404,
    );
  });

  test(
    'proxied requests reach upstream with upstream Host, query kept',
    () async {
      final res = await h.browser.get(
        h.relayUri('/hermes/${h.upstreamId}/whoami', {'a': 'b'}),
      );
      expect(res.statusCode, 200);
      expect(h.fake.lastHost, '127.0.0.1:${h.upstreamServer.port}');
      expect(res.body, contains('<none>')); // no browser cookie leaked upstream
    },
  );

  test('request bodies stream through the relay', () async {
    final res = await h.browser.post(
      h.relayUri('/hermes/${h.upstreamId}/echo-body'),
      headers: {'origin': _origin},
      body: 'hello-relay',
    );
    expect(res.statusCode, 200);
    expect(res.body, 'hello-relay');
  });

  test(
    'upstream Set-Cookie never reaches the browser; jar replays it',
    () async {
      // Browser A logs in: upstream sets a cookie.
      final login = await h.browser.get(
        h.relayUri('/hermes/${h.upstreamId}/login'),
      );
      expect(login.statusCode, 200);
      expect(
        login.headers['set-cookie'] ?? '',
        isNot(contains('session=abc123')),
        reason: 'upstream Set-Cookie must not leak to the browser',
      );
      final sid = _relaySid(login);
      expect(sid, isNotNull, reason: 'relay must set its session cookie');

      // Same relay session → jar replays the upstream cookie.
      final whoami = await h.browser.get(
        h.relayUri('/hermes/${h.upstreamId}/whoami'),
        headers: {'cookie': '$sessionCookieName=$sid'},
      );
      expect(whoami.body, contains('session=abc123'));

      // A fresh browser (no relay cookie) shares nothing.
      final stranger = await h.browser.get(
        h.relayUri('/hermes/${h.upstreamId}/whoami'),
      );
      expect(stranger.body, contains('<none>'));
      final strangerSid = _relaySid(stranger);
      expect(strangerSid, isNot(sid));
      expect(
        (await h.browser.get(
          h.relayUri('/hermes/${h.upstreamId}/whoami'),
          headers: {'cookie': '$sessionCookieName=$strangerSid'},
        )).body,
        contains('<none>'),
      );
    },
  );

  test(
    'state-changing requests without the relay Origin are rejected',
    () async {
      final noOrigin = await h.browser.post(
        h.relayUri('/hermes/${h.upstreamId}/submit'),
        body: 'x',
      );
      expect(noOrigin.statusCode, 403);

      final wrongOrigin = await h.browser.post(
        h.relayUri('/hermes/${h.upstreamId}/submit'),
        headers: {'origin': 'https://evil.example'},
        body: 'x',
      );
      expect(wrongOrigin.statusCode, 403);

      final ok = await h.browser.post(
        h.relayUri('/hermes/${h.upstreamId}/submit'),
        headers: {'origin': _origin},
        body: 'x',
      );
      expect(ok.statusCode, 200);
      expect(ok.body, 'submitted');
    },
  );

  test('unknown upstream id → 404', () async {
    expect(
      (await h.browser.get(h.relayUri('/hermes/nope/api/status'))).statusCode,
      404,
    );
  });

  test('websocket frames pipe both ways; upstream sees no Origin', () async {
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${h.relayServer.port}/hermes/${h.upstreamId}/ws',
      headers: {'Origin': _origin},
    );
    socket.add('ping');
    socket.add('second');
    final frames = await socket
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 5));
    expect(frames, ['echo:ping', 'echo:second']);
    expect(h.fake.lastWsOrigin, isNull);

    await socket.close();
    await h.fake.wsClosed.future.timeout(const Duration(seconds: 5));
  });

  test('websocket with wrong Origin is refused', () async {
    expect(
      WebSocket.connect(
        'ws://127.0.0.1:${h.relayServer.port}/hermes/${h.upstreamId}/ws',
        headers: {'Origin': 'https://evil.example'},
      ),
      throwsA(isA<WebSocketException>()),
    );
  });

  group('normalizeUpstreamUrl', () {
    test('lowercases scheme/host, strips slash/query/fragment', () {
      expect(
        normalizeUpstreamUrl('HTTP://Example.COM:8080/a///?x=1#y'),
        'http://example.com:8080/a',
      );
      expect(normalizeUpstreamUrl('https://h:443/'), 'https://h');
      expect(normalizeUpstreamUrl('http://h:80'), 'http://h');
    });
    test('rejects non-absolute and non-http URLs', () {
      expect(() => normalizeUpstreamUrl('notaurl'), throwsFormatException);
      expect(() => normalizeUpstreamUrl('ftp://h/x'), throwsFormatException);
    });
  });

  group('RelayConfig.fromEnv', () {
    test('refuses to start without an admin token', () {
      expect(() => RelayConfig.fromEnv({}), throwsStateError);
      expect(
        () => RelayConfig.fromEnv({'HERMUSE_RELAY_ADMIN_TOKEN': '  '}),
        throwsStateError,
      );
    });
    test('parses port and optional values', () {
      final config = RelayConfig.fromEnv({
        'HERMUSE_RELAY_ADMIN_TOKEN': 'tok',
        'HERMUSE_RELAY_PORT': '9000',
        'HERMUSE_RELAY_ORIGIN': _origin,
      });
      expect(config.port, 9000);
      expect(config.origin, _origin);
      expect(config.staticDir, isNull);
      expect(
        () => RelayConfig.fromEnv({
          'HERMUSE_RELAY_ADMIN_TOKEN': 'tok',
          'HERMUSE_RELAY_PORT': 'bogus',
        }),
        throwsStateError,
      );
    });
    test('parses declared upstreams, normalised and deduplicated', () {
      Map<String, String> env(String? upstreams) => {
        'HERMUSE_RELAY_ADMIN_TOKEN': 'tok',
        'HERMUSE_RELAY_ORIGIN': _origin,
        'HERMUSE_RELAY_UPSTREAMS': ?upstreams,
      };
      expect(RelayConfig.fromEnv(env(null)).upstreams, isEmpty);
      expect(RelayConfig.fromEnv(env(' , ')).upstreams, isEmpty);
      expect(
        RelayConfig.fromEnv(
          env(
            ' HTTPS://Hermuse.203-0-113-10.sslip.io/ ,,http://h:8080/x/,'
            'https://hermuse.203-0-113-10.sslip.io:443',
          ),
        ).upstreams,
        ['https://hermuse.203-0-113-10.sslip.io', 'http://h:8080/x'],
      );
      for (final bad in ['hermuse.example.com', 'ftp://h', 'https://ok,/rel']) {
        expect(
          () => RelayConfig.fromEnv(env(bad)),
          throwsStateError,
          reason: bad,
        );
      }
    });
    test('refuses to start without a valid web app origin', () {
      for (final origin in [null, '', 'chat.example.com', 'https://a/b']) {
        expect(
          () => RelayConfig.fromEnv({
            'HERMUSE_RELAY_ADMIN_TOKEN': 'tok',
            'HERMUSE_RELAY_ORIGIN': ?origin,
          }),
          throwsStateError,
          reason: '$origin',
        );
      }
    });
  });

  group('upstreamTarget', () {
    final base = Uri.parse('https://h.example/prefix');
    test('keeps every request on the upstream and under its base path', () {
      expect(
        upstreamTarget(base, 'api/status', 'a=1').toString(),
        'https://h.example/prefix/api/status?a=1',
      );
      expect(
        upstreamTarget(base, '', '').toString(),
        'https://h.example/prefix/',
      );
    });
    test('rejects paths that could switch host or escape the prefix', () {
      for (final rest in [
        '/evil.example/x', // becomes //evil.example/x
        'api/../../x',
        'api/./x',
        '%2Fevil.example',
        '..%2Fx',
        '%2E%2E',
      ]) {
        expect(upstreamTarget(base, rest, ''), isNull, reason: rest);
      }
    });
  });

  test('idle sessions expire after 12h', () {
    final jar = CookieJar();
    final sid = jar.create();
    expect(jar.lookup(sid), isTrue);
    jar.debugSetLastUsed(
      sid,
      DateTime.now().toUtc().subtract(const Duration(hours: 13)),
    );
    expect(jar.lookup(sid), isFalse);
  });
}

String? _relaySid(http.Response res) {
  final setCookie = res.headers['set-cookie'];
  if (setCookie == null) return null;
  return CookieJar.sessionIdFromCookieHeader(setCookie);
}
