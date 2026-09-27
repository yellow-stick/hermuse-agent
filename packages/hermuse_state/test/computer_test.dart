import 'dart:convert';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:web_socket/testing.dart';
import 'package:web_socket/web_socket.dart';

void main() {
  // Relay-style base: every route keeps the `/hermes/<id>` prefix.
  const route = '/hermes/vps/api/plugins/hermuse/computer';
  late Map<String, http.Response Function(http.Request)> routes;
  late HermesRestClient rest;

  http.Response json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  setUp(() {
    routes = {};
    rest = HermesRestClient(
      MockClient((request) async {
        final handler = routes['${request.method} ${request.url.path}'];
        return handler == null
            ? json({'detail': 'Not Found'}, 404)
            : handler(request);
      }),
      baseUrl: Uri.parse('https://relay.example/hermes/vps'),
    );
  });

  test('status reads the plugin states; no plugin reads as missing', () async {
    final client = ComputerClient(rest);
    expect((await client.status()).state, ComputerState.missing);

    routes['GET $route/status'] = (_) => json({
      'state': 'daemon_down',
      'detail': 'Cannot connect to the Docker daemon',
      'control': 'human',
      'mode': 'desktop',
    });
    final status = await client.status();
    expect(
      (status.state, status.detail, status.control, status.mode),
      (
        ComputerState.daemonDown,
        'Cannot connect to the Docker daemon',
        ComputerControl.human,
        ComputerMode.desktop,
      ),
    );

    for (final (wire, state) in [
      ('docker_missing', ComputerState.dockerMissing),
      ('image_missing', ComputerState.imageMissing),
      ('building', ComputerState.building),
      ('stopped', ComputerState.stopped),
      ('running', ComputerState.running),
      ('error', ComputerState.error),
      ('something_new', ComputerState.error),
    ]) {
      routes['POST $route/setup'] = (_) => json({'state': wire, 'detail': ''});
      expect((await client.setup()).state, state, reason: wire);
    }
  });

  test('snapshot bytes, null when none was saved; thumbnail errors', () async {
    final jpeg = [0xff, 0xd8, 0xff, 0xd9];
    routes['GET $route/snapshots/call_1'] = (_) =>
        http.Response.bytes(jpeg, 200, headers: {'content-type': 'image/jpeg'});
    routes['GET $route/thumbnail'] = (_) =>
        json({'detail': 'computer is not running'}, 409);
    final client = ComputerClient(rest);
    expect(await client.snapshot('call_1'), jpeg);
    expect(await client.snapshot('call_2'), isNull);
    await expectLater(
      client.thumbnail(),
      throwsA(isA<HermesHttpError>().having((e) => e.statusCode, 'code', 409)),
    );
  });

  test('a session merges state, speaks the wire protocol, reports the close '
      'code', () async {
    routes['POST $route/ticket'] = (_) => json({'ticket': 'T1'});
    final (socket, server) = fakes();
    Uri? connected;
    final client = ComputerClient(
      rest,
      connect: (uri) async {
        connected = uri;
        return socket;
      },
    );
    final session = await client.open(fps: 8);
    expect('$connected', 'wss://relay.example$route/ws?ticket=T1&fps=8');

    final states = <ComputerViewState>[];
    final frames = <Uint8List>[];
    session.states.listen(states.add);
    session.frames.listen(frames.add);
    server
      ..sendText(
        jsonEncode({'t': 'geometry', 'w': 1920, 'h': 1040, 'mode': 'browser'}),
      )
      ..sendBytes(Uint8List.fromList([0xff, 0xd8]))
      ..sendText(
        jsonEncode({
          't': 'state',
          'control': 'human',
          'mine': true,
          'mode': 'browser',
          'tabs': [
            {
              'id': 'A',
              'url': 'https://en.wikipedia.org/wiki/Nantes',
              'title': 'Nantes',
              'active': true,
            },
            {'id': 'B', 'url': 'about:blank', 'title': '', 'active': false},
          ],
        }),
      )
      ..sendText('not json');
    await pumpEventQueue();
    expect(states, hasLength(2));
    final view = states.last;
    expect((view.width, view.height), (1920, 1040));
    expect(view.inControl, isTrue);
    expect(view.activeTab?.host, 'en.wikipedia.org');
    expect(view.tabs.last.host, 'about:blank');
    expect(frames.single, [0xff, 0xd8]);
    // A later listener starts from the current picture and frame.
    expect((await session.states.first).tabs, hasLength(2));
    expect(await session.frames.first, [0xff, 0xd8]);

    final sent = <Object?>[];
    server.events.listen((e) {
      if (e is TextDataReceived) sent.add(jsonDecode(e.text));
    });
    session
      ..take()
      ..move(10.4, 20.6)
      ..down(10, 21, button: 3)
      ..up(10, 21, button: 3)
      ..wheel(10, 21, -1)
      ..key('Return', down: true)
      ..key('Return', down: false)
      ..text('héllo')
      ..setMode(ComputerMode.desktop)
      ..activateTab('B')
      ..closeTab('B')
      ..release();
    await pumpEventQueue();
    expect(sent, [
      {'t': 'take'},
      {'t': 'move', 'x': 10, 'y': 21},
      {'t': 'down', 'x': 10, 'y': 21, 'b': 3},
      {'t': 'up', 'x': 10, 'y': 21, 'b': 3},
      {'t': 'wheel', 'x': 10, 'y': 21, 'dy': -1},
      {'t': 'key', 'k': 'Return', 'a': 'down'},
      {'t': 'key', 'k': 'Return', 'a': 'up'},
      {'t': 'text', 's': 'héllo'},
      {'t': 'mode', 'mode': 'desktop'},
      {'t': 'tab', 'action': 'activate', 'id': 'B'},
      {'t': 'tab', 'action': 'close', 'id': 'B'},
      {'t': 'release'},
    ]);

    await server.close(4001, 'Cannot connect to the Docker daemon');
    final closed = await session.closed;
    expect(
      (closed.code, closed.reason),
      (4001, 'Cannot connect to the Docker daemon'),
    );
    session.move(1, 1); // After the close: dropped, no throw.
    expect(await session.states.toList(), hasLength(1));
  });

  test('keysymFor names X keys; characters are text unless a shortcut', () {
    expect(
      [
        for (final key in [
          'Enter',
          'Backspace',
          'PageUp',
          'PageDown',
          'ArrowLeft',
          'Control',
          'Meta',
          'F12',
          ' ',
        ])
          keysymFor(key),
      ],
      [
        'Return',
        'BackSpace',
        'Prior',
        'Next',
        'Left',
        'Control_L',
        'Super_L',
        'F12',
        'space',
      ],
    );
    expect(keysymFor('F13'), isNull);
    expect(keysymFor('a'), isNull);
    expect(keysymFor('C', controlOrMeta: true), 'c');
    expect(keysymFor('7', controlOrMeta: true), '7');
    expect(keysymFor('é', controlOrMeta: true), isNull);
  });
}
