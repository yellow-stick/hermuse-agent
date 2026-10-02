import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart';
import 'package:web_socket/web_socket.dart';

import 'computer_frames.dart';

/// A demo-only [WebSocketConnector] replaying the fake computer's screen.
///
/// The stream sends the plugin's `geometry` + `state` messages, then loops
/// two JPEG frames (the fictional sites from [computer_frames.dart]) a few
/// seconds apart, the way the real plugin streams the computer's screen.
/// Control messages from the viewer (`take`, `release`, `mode`, `tab`) are
/// answered locally: `take`/`release` flip the reported control, `mode`
/// flips browser/desktop (and its frame), tab switches change the active
/// tab. Nothing leaves the browser; input is swallowed.
WebSocketConnector demoComputerConnector({
  String browserFrame = 'energy-form',
  String desktopFrame = 'desktop',
  List<Map<String, Object?>> tabs = const [
    {
      'id': 'compare',
      'url': 'https://compare.watto.example/energy-lyon',
      'title': 'Watto Compare — Green electricity in Lyon',
      'active': false,
    },
    {
      'id': 'switch',
      'url': 'https://switch.lumenpure.example/form',
      'title': 'Lumen Pure — Switch form',
      'active': true,
    },
  ],
}) => (Uri uri) async {
  final (socket, server) = _loopingPair(
    browserFrame: browserFrame,
    desktopFrame: desktopFrame,
    tabs: tabs,
  );
  return socket;
};

/// The two ends of a replayed computer stream: [socket] goes to the
/// [ComputerClient], [server] feeds it frames and answers control messages.
(NewWebSocket, _DemoComputerServer) _loopingPair({
  required String browserFrame,
  required String desktopFrame,
  required List<Map<String, Object?>> tabs,
}) {
  final toViewer = StreamController<WebSocketEvent>.broadcast();
  final toServer = StreamController<WebSocketEvent>.broadcast();
  final socket = _DemoWebSocket(toViewer.stream, toServer);
  final server = _DemoComputerServer(
    out: toViewer,
    browserFrame: browserFrame,
    desktopFrame: desktopFrame,
    tabs: [for (final t in tabs) Map<String, Object?>.of(t)],
  );
  toServer.stream.listen(server.onMessage);
  // The real server sends geometry + state first, then frames.
  Timer.run(() {
    server.sendState();
    server.sendFrame();
  });
  // Loop the two frames, a few seconds apart: the viewer looks alive.
  server.timer = Timer.periodic(const Duration(seconds: 4), (_) {
    server.sendFrame();
  });
  return (socket, server);
}

typedef NewWebSocket = WebSocket;

/// Fake server side of the computer stream (test- and demo-only).
final class _DemoComputerServer {
  _DemoComputerServer({
    required this.out,
    required this.browserFrame,
    required this.desktopFrame,
    required this.tabs,
  });

  final StreamController<WebSocketEvent> out;
  final String browserFrame;
  final String desktopFrame;
  final List<Map<String, Object?>> tabs;
  Timer? timer;
  var mode = 'browser';
  var control = 'agent';
  var mine = false;
  var frameFlip = false;

  void sendState() {
    out.add(
      TextDataReceived(
        jsonEncode({'t': 'geometry', 'w': 1280, 'h': 800, 'mode': mode}),
      ),
    );
    out.add(
      TextDataReceived(
        jsonEncode({
          't': 'state',
          'control': control,
          'mine': mine,
          'mode': mode,
          'tabs': tabs,
        }),
      ),
    );
  }

  void sendFrame() {
    frameFlip = !frameFlip;
    final name = mode == 'desktop'
        ? desktopFrame
        : (frameFlip ? 'energy' : browserFrame);
    try {
      out.add(BinaryDataReceived(demoComputerFrame(name)));
    } on Object {
      // No frame embedded under that name: skip the tick.
    }
  }

  void onMessage(WebSocketEvent event) {
    if (event is! TextDataReceived) return;
    final Object? message;
    try {
      message = jsonDecode(event.text);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    switch (message['t']) {
      case 'take':
        // Read-only demo: the button shows but takes nothing — the agent
        // keeps driving. Answer with the state so the tap is not an error.
        sendState();
      case 'release':
        control = 'agent';
        mine = false;
        sendState();
      case 'mode':
        if (message['mode'] == 'desktop' || message['mode'] == 'browser') {
          mode = message['mode'] as String;
          sendState();
          sendFrame();
        }
      case 'tab':
        if (message['action'] == 'activate' && message['id'] is String) {
          final id = message['id'] as String;
          for (final t in tabs) {
            t['active'] = t['id'] == id;
          }
          sendState();
          // Show the matching still per tab.
          out.add(
            BinaryDataReceived(
              demoComputerFrame(switch (id) {
                'compare' => 'energy',
                'stay' => 'annecy',
                _ => browserFrame,
              }),
            ),
          );
        }
    }
  }

  void close() {
    timer?.cancel();
    unawaited(out.close());
  }
}

/// Client end of the replayed stream: events in, control messages out.
final class _DemoWebSocket implements WebSocket {
  _DemoWebSocket(this._events, this._toServer);

  final Stream<WebSocketEvent> _events;
  final StreamController<WebSocketEvent> _toServer;
  var _closed = false;

  @override
  Stream<WebSocketEvent> get events => _events;

  @override
  String get protocol => 'demo';

  @override
  void sendBytes(Uint8List bytes) {
    if (_closed) throw WebSocketConnectionClosed();
  }

  @override
  void sendText(String text) {
    if (_closed) throw WebSocketConnectionClosed();
    _toServer.add(TextDataReceived(text));
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_closed) throw WebSocketConnectionClosed();
    _closed = true;
  }
}
