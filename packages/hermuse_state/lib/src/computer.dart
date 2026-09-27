import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:web_socket/web_socket.dart';

import 'onboarding.dart';
import 'product.dart';

part 'computer.g.dart';

/// Base route of the agent's computer (browser + desktop) in the plugin.
const hermuseComputerRoute = '$hermusePluginRoute/computer';

/// Readiness of the agent's computer: the plugin's `state` string, plus
/// [missing] when the plugin itself does not answer.
enum ComputerState {
  /// No `docker` binary on the Hermes host.
  dockerMissing('docker_missing'),

  /// Docker is installed but its daemon does not answer.
  daemonDown('daemon_down'),

  /// The computer image is not built yet (setup builds it).
  imageMissing('image_missing'),

  /// The computer image is being built.
  building('building'),

  /// Startable: the container is absent, created or exited.
  stopped('stopped'),

  /// The container runs.
  running('running'),

  /// Anything else failed; [ComputerStatus.detail] says what.
  error('error'),

  /// The Hermuse plugin routes 404 (not installed or not enabled).
  missing('missing');

  const ComputerState(this.wire);

  /// The plugin's `state` value.
  final String wire;

  /// Unknown values read as [error].
  static ComputerState fromWire(Object? value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => error);
}

/// What the stream shows: Chromium's window or the whole desktop.
enum ComputerMode { browser, desktop }

/// Who drives the computer: the agent, or a human who took control.
enum ComputerControl { agent, human }

ComputerMode _mode(Object? value) =>
    value == 'desktop' ? ComputerMode.desktop : ComputerMode.browser;

ComputerControl _control(Object? value) =>
    value == 'human' ? ComputerControl.human : ComputerControl.agent;

/// `GET /computer/status` (and the `POST /computer/setup` result). Shape:
/// `{state, detail, control?, mode?}`.
final class ComputerStatus {
  const ComputerStatus({
    required this.state,
    this.detail = '',
    this.control = ComputerControl.agent,
    this.mode = ComputerMode.browser,
  });

  factory ComputerStatus.fromJson(Map<String, Object?> json) => ComputerStatus(
    state: ComputerState.fromWire(json['state']),
    detail: json['detail'] as String? ?? '',
    control: _control(json['control']),
    mode: _mode(json['mode']),
  );

  final ComputerState state;

  /// Cause of [ComputerState.daemonDown] and [ComputerState.error] (a
  /// daemon message, a failed image build…); may be empty.
  final String detail;
  final ComputerControl control;
  final ComputerMode mode;
}

/// One page of the agent's Chromium. Shape: `{id, url, title, active}`.
final class ComputerTab {
  const ComputerTab({
    required this.id,
    required this.url,
    required this.title,
    required this.active,
  });

  factory ComputerTab.fromJson(Map<String, Object?> json) => ComputerTab(
    id: json['id'] as String? ?? '',
    url: json['url'] as String? ?? '',
    title: json['title'] as String? ?? '',
    active: json['active'] == true,
  );

  final String id;
  final String url;
  final String title;

  /// The page in front.
  final bool active;

  /// Host shown for the tab (`en.wikipedia.org`); the URL itself when it
  /// has none (`about:blank`).
  String get host {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? url : host;
  }
}

/// The viewer's picture of the computer, merged from the stream's
/// `geometry` and `state` messages.
final class ComputerViewState {
  const ComputerViewState({
    this.width = 0,
    this.height = 0,
    this.mode = ComputerMode.browser,
    this.control = ComputerControl.agent,
    this.mine = false,
    this.tabs = const [],
  });

  /// Frame size in pixels; 0 until the first `geometry` message.
  final int width;
  final int height;
  final ComputerMode mode;
  final ComputerControl control;

  /// This viewer holds the control lease.
  final bool mine;

  /// Chromium pages, the one in front first.
  final List<ComputerTab> tabs;

  /// The user is in control from this viewer: its input reaches the
  /// computer.
  bool get inControl => control == ComputerControl.human && mine;

  /// The page in front, when there is one.
  ComputerTab? get activeTab => tabs.where((t) => t.active).firstOrNull;

  ComputerViewState copyWith({
    int? width,
    int? height,
    ComputerMode? mode,
    ComputerControl? control,
    bool? mine,
    List<ComputerTab>? tabs,
  }) => ComputerViewState(
    width: width ?? this.width,
    height: height ?? this.height,
    mode: mode ?? this.mode,
    control: control ?? this.control,
    mine: mine ?? this.mine,
    tabs: tabs ?? this.tabs,
  );
}

/// REST and stream client of the agent's computer on one instance.
final class ComputerClient {
  ComputerClient(this._rest, {this._connect = WebSocket.connect});

  final HermesRestClient _rest;
  final WebSocketConnector _connect;

  /// Readiness, control and mode; [ComputerState.missing] without the
  /// plugin.
  Future<ComputerStatus> status() =>
      _status(() => _rest.getJson('$hermuseComputerRoute/status'));

  /// Points Hermes' browser tools at the computer and builds its image when
  /// missing (a failed build is retried); returns the resulting status.
  Future<ComputerStatus> setup() =>
      _status(() => _rest.postJson('$hermuseComputerRoute/setup', const {}));

  /// Starts the computer; throws [HermesHttpError] (409, with the cause)
  /// when it cannot start.
  Future<void> start() async {
    await _rest.postJson('$hermuseComputerRoute/start', const {});
  }

  Future<void> stop() async {
    await _rest.postJson('$hermuseComputerRoute/stop', const {});
  }

  /// Current screen as a 640-wide JPEG; throws [HermesHttpError] (409)
  /// while the computer is not running.
  Future<Uint8List> thumbnail() =>
      _rest.getBytes('$hermuseComputerRoute/thumbnail');

  /// JPEG saved right after the browser tool call [toolId], or null when
  /// there is none.
  Future<Uint8List?> snapshot(String toolId) async {
    try {
      return await _rest.getBytes(
        '$hermuseComputerRoute/snapshots/${Uri.encodeComponent(toolId)}',
      );
    } on HermesHttpError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Opens the live stream at up to [fps] frames per second.
  ///
  /// The server starts a stopped computer first. It closes the socket with
  /// 4401 when the ticket is refused and 4001 when the computer cannot
  /// start (the close reason says why): see [ComputerSession.closed].
  Future<ComputerSession> open({int fps = 5}) async {
    final body = await _rest.postJson('$hermuseComputerRoute/ticket', const {});
    final http = _rest.resolve('$hermuseComputerRoute/ws', {
      'ticket': body['ticket'] as String,
      'fps': '$fps',
    });
    final WebSocket socket;
    try {
      socket = await _connect(
        http.replace(scheme: http.scheme == 'https' ? 'wss' : 'ws'),
      );
    } on WebSocketException catch (e) {
      throw HermesUnreachable('${http.origin}: ${e.message}');
    }
    return ComputerSession._(socket);
  }

  Future<ComputerStatus> _status(
    Future<Map<String, Object?>> Function() request,
  ) async {
    try {
      return ComputerStatus.fromJson(await request());
    } on HermesHttpError catch (e) {
      if (e.statusCode == 404) {
        return const ComputerStatus(state: ComputerState.missing);
      }
      rethrow;
    }
  }
}

/// One live connection to the computer: JPEG frames and state in, control
/// and input out. Closing it (or losing it) releases this viewer's control.
final class ComputerSession {
  ComputerSession._(this._socket) {
    _events = _socket.events.listen(
      _onEvent,
      // A transport error is followed by the close event.
      onError: (Object _) {},
      onDone: _finish,
    );
  }

  final WebSocket _socket;
  late final StreamSubscription<WebSocketEvent> _events;
  final _frames = StreamController<Uint8List>.broadcast();
  final _states = StreamController<ComputerViewState>.broadcast();
  final _closed = Completer<({int? code, String reason})>();
  Uint8List? _frame;
  ComputerViewState? _view;

  /// JPEG frames of the screen (Chromium's window in browser mode). A new
  /// listener first gets the latest frame.
  late final Stream<Uint8List> frames = _replaying(_frames, () => _frame);

  /// Size, mode, control and tabs on every change. A new listener first
  /// gets the latest state.
  late final Stream<ComputerViewState> states = _replaying(
    _states,
    () => _view,
  );

  /// Completes once the socket is closed, by [close] or by the server.
  /// Server codes: 4401 (ticket refused) and 4001 (the computer cannot
  /// start or its screen stream ended; `reason` says why).
  Future<({int? code, String reason})> get closed => _closed.future;

  /// Takes control from the agent (and from any other viewer): the agent's
  /// browser tools are refused until [release].
  void take() => _send({'t': 'take'});

  /// Hands control back to the agent.
  void release() => _send({'t': 'release'});

  void setMode(ComputerMode mode) => _send({'t': 'mode', 'mode': mode.name});

  /// Brings the page [id] to the front.
  void activateTab(String id) =>
      _send({'t': 'tab', 'action': 'activate', 'id': id});

  void closeTab(String id) => _send({'t': 'tab', 'action': 'close', 'id': id});

  // Input: frame pixel coordinates, applied by the server only while this
  // viewer is in control ([ComputerViewState.inControl]).

  void move(num x, num y) =>
      _send({'t': 'move', 'x': x.round(), 'y': y.round()});

  /// Presses mouse [button]: 1 primary, 2 middle, 3 secondary.
  void down(num x, num y, {int button = 1}) =>
      _send({'t': 'down', 'x': x.round(), 'y': y.round(), 'b': button});

  void up(num x, num y, {int button = 1}) =>
      _send({'t': 'up', 'x': x.round(), 'y': y.round(), 'b': button});

  /// Scrolls [dy] notches, positive downwards.
  void wheel(num x, num y, int dy) =>
      _send({'t': 'wheel', 'x': x.round(), 'y': y.round(), 'dy': dy});

  /// Presses or releases the X [keysym] (see [keysymFor]).
  void key(String keysym, {required bool down}) =>
      _send({'t': 'key', 'k': keysym, 'a': down ? 'down' : 'up'});

  /// Types printable [text].
  void text(String text) => _send({'t': 'text', 's': text});

  /// Closes the stream; the server releases this viewer's control.
  Future<void> close() async {
    if (_closed.isCompleted) return;
    _finish(1000);
    try {
      await _socket.close(1000);
    } on WebSocketConnectionClosed {
      // The server closed it first.
    }
  }

  void _send(Map<String, Object?> message) {
    if (_closed.isCompleted) return;
    try {
      _socket.sendText(jsonEncode(message));
    } on WebSocketConnectionClosed {
      // Its close event is on the way; input after it is moot.
    }
  }

  void _onEvent(WebSocketEvent event) {
    switch (event) {
      case BinaryDataReceived(:final data):
        _frames.add(_frame = data);
      case TextDataReceived(:final text):
        if (_merge(text) case final view?) _states.add(_view = view);
      case CloseReceived(:final code, :final reason):
        _finish(code, reason);
    }
  }

  /// The view after a `geometry` or `state` message; null for anything else.
  ComputerViewState? _merge(String text) {
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (message is! Map<String, Object?>) return null;
    final view = _view ?? const ComputerViewState();
    return switch (message['t']) {
      'geometry' => view.copyWith(
        width: (message['w'] as num?)?.toInt(),
        height: (message['h'] as num?)?.toInt(),
        mode: _mode(message['mode']),
      ),
      'state' => view.copyWith(
        control: _control(message['control']),
        mine: message['mine'] == true,
        mode: _mode(message['mode']),
        tabs: [
          for (final tab in (message['tabs'] as List?) ?? const [])
            ComputerTab.fromJson(tab as Map<String, Object?>),
        ],
      ),
      _ => null,
    };
  }

  void _finish([int? code, String reason = '']) {
    if (_closed.isCompleted) return;
    _closed.complete((code: code, reason: reason));
    unawaited(_events.cancel());
    unawaited(_frames.close());
    unawaited(_states.close());
  }
}

/// [source]'s events, preceded for each new listener by the [latest] one.
Stream<T> _replaying<T extends Object>(
  StreamController<T> source,
  T? Function() latest,
) => Stream.multi((listener) {
  if (latest() case final value?) listener.add(value);
  final subscription = source.stream.listen(
    listener.add,
    onDone: listener.close,
  );
  listener.onCancel = subscription.cancel;
});

final _keysyms = {
  'Enter': 'Return',
  'Backspace': 'BackSpace',
  'Tab': 'Tab',
  'Escape': 'Escape',
  'Delete': 'Delete',
  'Home': 'Home',
  'End': 'End',
  'PageUp': 'Prior',
  'PageDown': 'Next',
  'ArrowLeft': 'Left',
  'ArrowRight': 'Right',
  'ArrowUp': 'Up',
  'ArrowDown': 'Down',
  'Shift': 'Shift_L',
  'Control': 'Control_L',
  'Alt': 'Alt_L',
  'Meta': 'Super_L',
  for (var i = 1; i <= 12; i++) 'F$i': 'F$i',
  ' ': 'space',
};

final _shortcutKey = RegExp(r'^[A-Za-z0-9]$');

/// X keysym name of a DOM `KeyboardEvent.key`, or null when the key is not
/// sent as a key press.
///
/// Single printable characters return null — type them with
/// [ComputerSession.text] — unless Control or Meta is held
/// ([controlOrMeta]): a letter or digit is then pressed as its lower-cased
/// keysym (`a`…`z`, `0`…`9`), so shortcuts such as Ctrl+C reach the page.
String? keysymFor(String domKey, {bool controlOrMeta = false}) =>
    _keysyms[domKey] ??
    (controlOrMeta && _shortcutKey.hasMatch(domKey)
        ? domKey.toLowerCase()
        : null);

/// Computer client of [instanceId], on its authenticated REST client.
@riverpod
Future<ComputerClient> computerClient(Ref ref, String instanceId) async =>
    ComputerClient(await ref.watch(restClientProvider(instanceId).future));
