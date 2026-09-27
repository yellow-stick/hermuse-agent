import 'dart:async';
import 'dart:typed_data';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'browser_card.dart';

/// Status polling while the computer is being prepared.
const _fastPoll = Duration(milliseconds: 1500);

/// Status polling while it waits on the user (Docker missing or stopped,
/// no plugin, a failure).
const _slowPoll = Duration(seconds: 5);

/// Local wheel travel (px) sent as one wheel notch.
const _wheelNotch = 50.0;

/// The agent's computer, live: frames, Chromium's tabs, Take control /
/// Done, Stop and the Browser | Desktop switch. Replaces everything right
/// of the rail while [ChatState.computerOpen].
///
/// The stream opens only once `status()` says the computer is startable;
/// until then the stage shows why (and retries by itself). Closing the
/// viewer closes the stream, which hands a held control back to the agent.
///
/// Built only in the browser, inside the `@client` [HermuseChatRoot]
/// island (which renders no chat while pre-rendering); `@client` itself
/// cannot take the [controller] parameter. Keyed by instance by its parent.
class HermuseComputerViewer extends StatefulComponent {
  const HermuseComputerViewer({
    required this.controller,
    required this.instanceId,
    super.key,
  });

  final ChatController controller;
  final String instanceId;

  @override
  State<HermuseComputerViewer> createState() => _HermuseComputerViewerState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-computer', [
      css('&').styles(
        height: 100.percent,
        display: .flex,
        flexDirection: .column,
        flex: .grow(1),
        color: .variable('--content'),
        backgroundColor: .variable('--canvas'),
        raw: {'min-width': '0', 'min-height': '0'},
      ),
      css('.hermuse-computer-head').styles(
        minHeight: 48.px,
        display: .flex,
        flexDirection: .row,
        flexWrap: .wrap,
        alignItems: .center,
        gap: .all(8.px),
        padding: .symmetric(horizontal: 16.px, vertical: 6.px),
        border: .only(
          bottom: .solid(color: .variable('--line'), width: 1.px),
        ),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-computer-titles').styles(
        display: .flex,
        flexDirection: .column,
        flex: .grow(1),
        raw: {'min-width': '0', 'flex-basis': '0'},
      ),
      css('.hermuse-computer-title').styles(
        margin: .zero,
        overflow: .hidden,
        fontSize: 15.px,
        lineHeight: 20.px,
        fontWeight: .w600,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-computer-subtitle').styles(
        margin: .zero,
        overflow: .hidden,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-computer-actions').styles(
        display: .flex,
        flexDirection: .row,
        flexWrap: .wrap,
        alignItems: .center,
        justifyContent: .end,
        gap: .all(8.px),
      ),
      css('.hermuse-computer-close').styles(display: .flex),
      // Browser | Desktop: a segmented track with text segments.
      css('.hermuse-computer-modes').styles(
        height: 36.px,
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        padding: .all(4.px),
        radius: .circular(YsRadius.pill.px),
        backgroundColor: .variable('--neutral-ambient'),
      ),
      css('.hermuse-computer-mode').styles(
        height: 28.px,
        padding: .symmetric(horizontal: 12.px),
        radius: .circular(YsRadius.segment.px),
        color: .variable('--content-muted'),
        fontSize: 13.px,
        lineHeight: 18.px,
        fontWeight: .w500,
      ),
      css('.hermuse-computer-mode:hover:enabled')
          .styles(color: .variable('--content')),
      css('.hermuse-computer-mode-on').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-film'),
      ),
      css('.hermuse-computer-stop').styles(
        height: 36.px,
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(6.px),
        padding: .symmetric(horizontal: 12.px),
        radius: .circular(YsRadius.pill.px),
        color: .variable('--error'),
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-computer-stop:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-computer-stop-filled')
          .styles(color: Colors.white, backgroundColor: browserPillGrey),
      css('.hermuse-computer-stop-filled .ys-icon')
          .styles(color: .variable('--error')),
      css('.hermuse-computer-stop-filled:hover').styles(
        backgroundColor: browserPillGrey,
        raw: {'filter': 'brightness(1.15)'},
      ),
      css('.hermuse-computer-primary').styles(
        height: 36.px,
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(6.px),
        padding: .symmetric(horizontal: 16.px),
        radius: .circular(24.px),
        color: Colors.black,
        backgroundColor: browserBlue,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-computer-primary:hover:enabled')
          .styles(raw: {'filter': 'brightness(1.1)'}),
      css('.hermuse-computer-primary:disabled').styles(opacity: 0.5),
      css(
        '.hermuse-computer-mode:focus-visible, '
        '.hermuse-computer-stop:focus-visible, '
        '.hermuse-computer-primary:focus-visible, '
        '.hermuse-computer-retry:focus-visible, '
        '.hermuse-computer-tab-main:focus-visible, '
        '.hermuse-computer-tab-close:focus-visible, '
        '.hermuse-computer-canvas:focus-visible',
      ).styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
      // One tab per Chromium page.
      css('.hermuse-computer-tabs').styles(
        display: .flex,
        flexDirection: .row,
        gap: .all(4.px),
        padding: .symmetric(horizontal: 12.px, vertical: 6.px),
        overflow: .only(x: .auto, y: .hidden),
        border: .only(
          bottom: .solid(color: .variable('--line'), width: 1.px),
        ),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-computer-tab').styles(
        width: 172.px,
        height: 40.px,
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        radius: .circular(YsRadius.row.px),
        color: .variable('--content-muted'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-computer-tab:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-computer-tab-active').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-ambient'),
      ),
      css('.hermuse-computer-tab-main').styles(
        height: 100.percent,
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        flex: .grow(1),
        gap: .all(6.px),
        padding: .only(left: 10.px, right: 2.px),
        radius: .circular(YsRadius.row.px),
        fontSize: 13.px,
        lineHeight: 18.px,
        raw: {'min-width': '0'},
      ),
      css('.hermuse-computer-tab-host').styles(
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-computer-tab-close').styles(
        width: 24.px,
        height: 24.px,
        margin: .only(right: 6.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        radius: .circular(YsRadius.pill.px),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-computer-tab-close:hover').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-film'),
      ),
      // The frame, contain-fitted and centred.
      css('.hermuse-computer-stage').styles(
        position: .relative(),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        padding: .all(16.px),
        overflow: .hidden,
        raw: {'flex': '1 1 0', 'min-height': '0'},
      ),
      css('.hermuse-computer-canvas').styles(
        display: .block,
        maxWidth: 100.percent,
        maxHeight: 100.percent,
        radius: .circular(6.px),
        backgroundColor: Colors.black,
        raw: {'min-width': '0', 'min-height': '0'},
      ),
      css('.hermuse-computer-canvas-idle').styles(display: .none),
      css('.hermuse-computer-canvas-live')
          .styles(raw: {'touch-action': 'none'}),
      css('.hermuse-computer-notice').styles(
        position: .absolute(top: 0.px, left: 0.px, right: 0.px, bottom: 0.px),
        display: .flex,
        flexDirection: .column,
        justifyContent: .center,
        alignItems: .center,
        gap: .all(12.px),
        padding: .all(24.px),
        textAlign: .center,
      ),
      css('.hermuse-computer-notice-text').styles(
        margin: .zero,
        maxWidth: 420.px,
        fontSize: 14.px,
        lineHeight: 20.px,
        color: .variable('--content-muted'),
        raw: {'overflow-wrap': 'anywhere'},
      ),
      css('.hermuse-computer-retry').styles(
        height: 36.px,
        padding: .symmetric(horizontal: 16.px),
        radius: .circular(YsRadius.pill.px),
        color: Colors.white,
        backgroundColor: browserPillGrey,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-computer-retry:hover, .hermuse-computer-copy:hover')
          .styles(raw: {'filter': 'brightness(1.15)'}),
      // Command to paste on the Hermes host (Docker missing).
      css('.hermuse-computer-command').styles(
        display: .flex,
        alignItems: .center,
        gap: .all(8.px),
        maxWidth: 560.px,
        padding: .only(left: 14.px, top: 8.px, right: 8.px, bottom: 8.px),
        radius: .circular(YsRadius.row.px),
        backgroundColor: .variable('--paper'),
      ),
      css('.hermuse-computer-command-text').styles(
        margin: .zero,
        color: .variable('--content'),
        fontSize: 13.px,
        lineHeight: 20.px,
        textAlign: .left,
        raw: {
          'user-select': 'all',
          'overflow-wrap': 'anywhere',
          'white-space': 'pre-wrap',
          'font-family':
              'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        },
      ),
      css('.hermuse-computer-copy').styles(
        height: 28.px,
        padding: .symmetric(horizontal: 12.px),
        radius: .circular(YsRadius.pill.px),
        color: Colors.white,
        backgroundColor: browserPillGrey,
        fontSize: 13.px,
        lineHeight: 18.px,
        fontWeight: .w500,
        raw: {'flex-shrink': '0'},
      ),
    ]),
    // Narrow: the title shares its row with the close button only; the
    // actions wrap onto a second row, right-aligned.
    css.media(MediaQuery.screen(maxWidth: 639.px), [
      css('.hermuse-computer .hermuse-computer-titles')
          .styles(raw: {'order': '1'}),
      css('.hermuse-computer .hermuse-computer-close')
          .styles(raw: {'order': '2'}),
      css('.hermuse-computer .hermuse-computer-actions')
          .styles(width: 100.percent, raw: {'order': '3'}),
    ]),
  ];
}

class _HermuseComputerViewerState extends State<HermuseComputerViewer> {
  final _canvas = GlobalNodeKey<web.HTMLCanvasElement>();
  ProviderSubscription<Future<ComputerClient>>? _client;
  Timer? _poll;

  /// Last `status()` (or `setup()`) answer; null before the first one.
  ComputerStatus? _status;

  /// Why the last request or the stream failed; cleared by the next good
  /// status.
  String? _failure;

  /// `setup()` already ran for a missing image.
  var _setupAsked = false;

  /// The stream already failed once and was reopened from `status()`; a
  /// frame resets it.
  var _reopened = false;

  /// The Docker command was just copied (Copy reads "Copied" for 2 s).
  var _copied = false;
  Timer? _copiedReset;

  ComputerSession? _session;
  StreamSubscription<ComputerViewState>? _views;
  StreamSubscription<Uint8List>? _frames;
  var _view = const ComputerViewState();

  /// Size of the frame on the canvas; 0 before the first one.
  var _frameWidth = 0;
  var _frameHeight = 0;

  /// Newest frame not painted yet: frames arriving while one decodes
  /// replace each other.
  Uint8List? _pending;
  var _painting = false;

  /// Keysyms held down in the computer by this viewer, by DOM `code`, so
  /// each gets its key-up even when modifiers changed meanwhile.
  final _held = <String, String>{};
  var _wheel = 0.0;

  bool get _hasFrame => _frameWidth > 0;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) unawaited(_check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _copiedReset?.cancel();
    _releaseKeys();
    unawaited(_views?.cancel());
    unawaited(_frames?.cancel());
    if (_session case final session?) unawaited(session.close());
    _client?.close();
    super.dispose();
  }

  Future<ComputerClient> _computer() =>
      (_client ??= listenComputerClient(component.instanceId)).read();

  static String _describe(Object error) =>
      error is HermesException ? error.message : '$error';

  void _schedule(Duration delay) {
    _poll?.cancel();
    _poll = Timer(delay, () => unawaited(_check()));
  }

  /// Opens the stream once the computer is startable, prepares it when its
  /// image is missing, and otherwise polls until the user fixed the cause.
  Future<void> _check() async {
    _poll?.cancel();
    final ComputerStatus status;
    try {
      status = await (await _computer()).status();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _failure = _describe(e));
      _schedule(_slowPoll);
      return;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _failure = null;
    });
    switch (status.state) {
      case ComputerState.imageMissing when !_setupAsked:
        _setupAsked = true;
        await _setup();
      case ComputerState.imageMissing || ComputerState.building:
        _schedule(_fastPoll);
      case ComputerState.stopped || ComputerState.running:
        await _open();
      case ComputerState.dockerMissing ||
          ComputerState.daemonDown ||
          ComputerState.error ||
          ComputerState.missing:
        _schedule(_slowPoll);
    }
  }

  /// Builds the image when missing (or retries a failed build), then polls.
  Future<void> _setup() async {
    _poll?.cancel();
    try {
      final status = await (await _computer()).setup();
      if (!mounted) return;
      setState(() => _status = status);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _failure = _describe(e));
    }
    _schedule(_fastPoll);
  }

  Future<void> _retry() async {
    setState(() {
      _failure = null;
      _reopened = false;
    });
    await _setup();
  }

  Future<void> _open() async {
    final ComputerSession session;
    try {
      session = await (await _computer()).open(fps: 5);
    } on Object catch (e) {
      if (mounted) _streamFailed(_describe(e));
      return;
    }
    if (!mounted) {
      unawaited(session.close());
      return;
    }
    _session = session;
    _views = session.states.listen(_onView);
    _frames = session.frames.listen(_onFrame);
    unawaited(
      session.closed.then((closed) {
        if (!mounted || !identical(_session, session)) return;
        _drop();
        _streamFailed(closed.reason);
      }),
    );
    setState(() {});
  }

  /// A refused ticket (4401), a computer that cannot start (4001) or a lost
  /// link: back to `status()` once, then the cause and Retry.
  void _streamFailed(String reason) {
    if (!_reopened) {
      _reopened = true;
      unawaited(_check());
      return;
    }
    setState(
      () => _failure = reason.isEmpty
          ? "Lost the connection to the agent's computer."
          : reason,
    );
  }

  void _drop() {
    unawaited(_views?.cancel());
    unawaited(_frames?.cancel());
    _views = null;
    _frames = null;
    _session = null;
    _held.clear();
    _pending = null;
    setState(() {
      _view = const ComputerViewState();
      _frameWidth = 0;
      _frameHeight = 0;
    });
  }

  void _onView(ComputerViewState view) {
    if (!mounted) return;
    final gained = view.inControl && !_view.inControl;
    // Control taken over elsewhere: this viewer's input is ignored now.
    if (!view.inControl) _held.clear();
    setState(() => _view = view);
    if (gained) {
      context.binding.addPostFrameCallback(() => _canvas.currentNode?.focus());
    }
  }

  void _onFrame(Uint8List jpeg) {
    _pending = jpeg;
    if (!_painting) unawaited(_paintPending());
  }

  Future<void> _paintPending() async {
    _painting = true;
    try {
      for (var jpeg = _pending; jpeg != null; jpeg = _pending) {
        _pending = null;
        final web.ImageBitmap bitmap;
        try {
          bitmap = await web.window
              .createImageBitmap(
                web.Blob(
                  [jpeg.toJS].toJS,
                  web.BlobPropertyBag(type: 'image/jpeg'),
                ),
              )
              .toDart;
        } on Object {
          continue; // An undecodable frame is skipped.
        }
        if (!mounted) {
          bitmap.close();
          return;
        }
        _paint(bitmap);
        bitmap.close();
      }
    } finally {
      _painting = false;
    }
  }

  void _paint(web.ImageBitmap bitmap) {
    final canvas = _canvas.currentNode;
    if (canvas == null) return;
    final width = bitmap.width;
    final height = bitmap.height;
    // Resizing clears the canvas: only on a new frame size. The same size
    // goes into the rendered attributes below so rebuilds keep it.
    if (canvas.width != width) canvas.width = width;
    if (canvas.height != height) canvas.height = height;
    canvas.context2D.drawImage(bitmap, 0, 0);
    if (width != _frameWidth || height != _frameHeight) {
      setState(() {
        _frameWidth = width;
        _frameHeight = height;
        _reopened = false;
      });
    }
  }

  /// [event]'s position in frame pixels, or null without a frame.
  ///
  /// Reads `x`/`y` (the client position as a double): pointer events carry
  /// fractional coordinates, which the `int` `clientX` binding rejects.
  ({double x, double y})? _at(web.MouseEvent event) {
    final canvas = _canvas.currentNode;
    if (canvas == null || !_hasFrame) return null;
    final box = canvas.getBoundingClientRect();
    if (box.width <= 0 || box.height <= 0) return null;
    return (
      x: ((event.x - box.left) / box.width * _frameWidth)
          .clamp(0, _frameWidth - 1)
          .toDouble(),
      y: ((event.y - box.top) / box.height * _frameHeight)
          .clamp(0, _frameHeight - 1)
          .toDouble(),
    );
  }

  /// The session to send input to: only while this viewer is in control.
  ComputerSession? get _input => _view.inControl ? _session : null;

  /// DOM button → X button: primary 1, middle 2, secondary 3.
  static int _button(int domButton) => switch (domButton) {
    1 => 2,
    2 => 3,
    _ => 1,
  };

  void _pointerDown(web.Event event) {
    final pointer = event as web.PointerEvent;
    final canvas = _canvas.currentNode;
    canvas?.focus();
    final session = _input;
    if (session == null) return;
    event.preventDefault();
    canvas?.setPointerCapture(pointer.pointerId);
    if (_at(pointer) case (:final x, :final y)) {
      session.down(x, y, button: _button(pointer.button));
    }
  }

  void _pointerMove(web.Event event) {
    final session = _input;
    if (session == null) return;
    if (_at(event as web.PointerEvent) case (:final x, :final y)) {
      session.move(x, y);
    }
  }

  void _pointerUp(web.Event event) {
    final session = _input;
    if (session == null) return;
    final pointer = event as web.PointerEvent;
    if (_at(pointer) case (:final x, :final y)) {
      session.up(x, y, button: _button(pointer.button));
    }
  }

  /// Wheel travel in notches; trackpads' small deltas add up to one.
  void _onWheel(web.Event event) {
    final session = _input;
    if (session == null) return;
    event.preventDefault();
    final wheel = event as web.WheelEvent;
    _wheel += switch (wheel.deltaMode) {
      web.WheelEvent.DOM_DELTA_LINE => wheel.deltaY * 40,
      web.WheelEvent.DOM_DELTA_PAGE => wheel.deltaY * 800,
      _ => wheel.deltaY,
    };
    final notches = (_wheel / _wheelNotch).truncate();
    if (notches == 0) return;
    _wheel -= notches * _wheelNotch;
    if (_at(wheel) case (:final x, :final y)) session.wheel(x, y, notches);
  }

  void _keyDown(web.Event event) {
    final session = _input;
    final key = event as web.KeyboardEvent;
    if (session == null || key.isComposing) return;
    final keysym = keysymFor(
      key.key,
      controlOrMeta: key.ctrlKey || key.metaKey,
    );
    if (keysym != null) {
      _held[_keyId(key)] = keysym;
      session.key(keysym, down: true);
    } else if (key.key.runes.length == 1) {
      session.text(key.key);
    } else {
      return; // Dead keys, CapsLock…: left to the browser.
    }
    // Everything else stays in the computer (Tab, Escape, shortcuts).
    event.preventDefault();
    event.stopPropagation();
  }

  void _keyUp(web.Event event) {
    final key = event as web.KeyboardEvent;
    final keysym = _held.remove(_keyId(key));
    if (keysym == null) return;
    _session?.key(keysym, down: false);
    event.preventDefault();
    event.stopPropagation();
  }

  static String _keyId(web.KeyboardEvent key) =>
      key.code.isEmpty ? key.key : key.code;

  /// Releases every key this viewer holds down (focus lost, Done, close).
  void _releaseKeys() {
    final session = _session;
    if (session != null) {
      for (final keysym in _held.values) {
        session.key(keysym, down: false);
      }
    }
    _held.clear();
  }

  void _done() {
    _releaseKeys();
    _session?.release();
  }

  /// What the stage says instead of the frame, with Retry when it helps and
  /// the shell command to paste on the Hermes host when there is one.
  ({String text, bool retry, String? command})? _notice({required bool busy}) {
    if (_failure case final failure?) {
      return (text: failure, retry: true, command: null);
    }
    final detail = _status?.detail ?? '';
    return switch (_status?.state) {
      ComputerState.dockerMissing => (
        text: 'Docker is not installed on the Hermes computer.',
        retry: false,
        command: detail.isEmpty ? null : detail,
      ),
      ComputerState.daemonDown => (
        text: 'Docker is installed but not running. Start Docker to continue.',
        retry: false,
        command: null,
      ),
      ComputerState.imageMissing => (
        text: "Preparing the agent's computer…",
        retry: false,
        command: null,
      ),
      ComputerState.building => (
        text: detail.isEmpty ? "Preparing the agent's computer…" : detail,
        retry: false,
        command: null,
      ),
      ComputerState.error => (
        text: detail.isEmpty ? "The agent's computer failed to start." : detail,
        retry: true,
        command: null,
      ),
      ComputerState.missing => (
        text: 'Install the Hermuse plugin on this Hermes to see its browser.',
        retry: false,
        command: null,
      ),
      null || ComputerState.stopped || ComputerState.running =>
        _hasFrame
            ? null
            : (
                text: busy
                    ? 'Loading browser task'
                    : 'Preparing browser preview',
                retry: false,
                command: null,
              ),
    };
  }

  void _copy(String command) {
    web.window.navigator.clipboard.writeText(command);
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Component build(BuildContext context) {
    final state = component.controller.state;
    final thread = state.activeThread;
    final block = _latestBrowserBlock(thread);
    final working = block?.running ?? false;
    final view = _view;
    final session = _session;
    final inControl = view.inControl;
    final elsewhere = view.control == ComputerControl.human && !view.mine;
    final tabHost = view.activeTab?.host ?? '';
    final host = tabHost.isNotEmpty ? tabHost : block?.host ?? '';
    final title = inControl
        ? "You're in control"
        : elsewhere
        ? 'Controlled from another device'
        : working && block!.step.isNotEmpty
        ? block.step
        : browserTaskTitle(thread.title);
    final subtitle = inControl || elsewhere || block == null
        ? host
        : [
            working ? 'Working' : 'Completed',
            if (host.isNotEmpty) host,
          ].join(' · ');
    final notice = _notice(busy: state.busy);
    return section(
      classes: 'hermuse-computer',
      attributes: {'aria-label': 'Browser session viewer'},
      [
        div(classes: 'hermuse-computer-head', [
          div(classes: 'hermuse-computer-titles', [
            h2(classes: 'hermuse-computer-title', [.text(title)]),
            if (subtitle.isNotEmpty)
              p(classes: 'hermuse-computer-subtitle', [.text(subtitle)]),
          ]),
          div(classes: 'hermuse-computer-actions', [
            _modes(session, view.mode),
            if (state.busy)
              YsPressable(
                onPressed: () => unawaited(component.controller.interrupt()),
                classes: inControl
                    ? 'hermuse-computer-stop hermuse-computer-stop-filled'
                    : 'hermuse-computer-stop',
                builder: (context, press) => .fragment([
                  BrowserGlyphView(BrowserGlyph.record, size: 18),
                  span([.text('Stop')]),
                ]),
              ),
            if (inControl)
              YsPressable(
                onPressed: _done,
                label: 'Hand browser control back to the assistant',
                classes: 'hermuse-computer-primary',
                builder: (context, press) => .fragment([
                  YsIconView(YsIcon.check, size: 18),
                  span([.text('Done')]),
                ]),
              )
            else
              YsPressable(
                onPressed: session?.take,
                classes: 'hermuse-computer-primary',
                builder: (context, press) =>
                    span([.text('Take control of the browser')]),
              ),
          ]),
          div(classes: 'hermuse-computer-close', [
            YsButton.icon(
              icon: YsIcon.close,
              label: 'Close browser session panel',
              onPressed: component.controller.closeComputer,
            ),
          ]),
        ]),
        if (view.tabs.isNotEmpty)
          div(
            classes: 'hermuse-computer-tabs',
            attributes: {
              'role': 'tablist',
              'aria-label': 'Open browser windows',
            },
            [
              for (final tab in view.tabs)
                _tab(tab, session, completed: !(working && tab.active)),
            ],
          ),
        div(classes: 'hermuse-computer-stage', [
          Component.element(
            tag: 'canvas',
            key: _canvas,
            classes: [
              'hermuse-computer-canvas',
              if (!_hasFrame) 'hermuse-computer-canvas-idle',
              if (inControl) 'hermuse-computer-canvas-live',
            ].join(' '),
            styles: _hasFrame
                ? Styles(raw: {'aspect-ratio': '$_frameWidth / $_frameHeight'})
                : null,
            attributes: {
              'role': 'img',
              'tabindex': '0',
              'aria-label': 'Browser session canvas',
              if (_hasFrame) 'width': '$_frameWidth',
              if (_hasFrame) 'height': '$_frameHeight',
            },
            events: {
              'pointerdown': _pointerDown,
              'pointermove': _pointerMove,
              'pointerup': _pointerUp,
              'wheel': _onWheel,
              'contextmenu': (event) {
                if (_input != null) event.preventDefault();
              },
              'keydown': _keyDown,
              'keyup': _keyUp,
              'blur': (_) => _releaseKeys(),
            },
          ),
          if (notice != null)
            div(
              classes: 'hermuse-computer-notice',
              attributes: {'role': 'status'},
              [
                p(classes: 'hermuse-computer-notice-text', [
                  .text(notice.text),
                ]),
                if (notice.command case final command?)
                  div(classes: 'hermuse-computer-command', [
                    code(classes: 'hermuse-computer-command-text', [
                      .text(command),
                    ]),
                    YsPressable(
                      onPressed: () => _copy(command),
                      classes: 'hermuse-computer-copy',
                      builder: (context, press) =>
                          span([.text(_copied ? 'Copied' : 'Copy')]),
                    ),
                  ]),
                if (notice.retry)
                  YsPressable(
                    onPressed: () => unawaited(_retry()),
                    classes: 'hermuse-computer-retry',
                    builder: (context, press) => span([.text('Retry')]),
                  ),
              ],
            ),
        ]),
      ],
    );
  }

  Component _modes(ComputerSession? session, ComputerMode current) => div(
    classes: 'hermuse-computer-modes',
    attributes: {'role': 'group', 'aria-label': 'Screen'},
    [
      for (final (mode, label) in const [
        (ComputerMode.browser, 'Browser'),
        (ComputerMode.desktop, 'Desktop'),
      ])
        YsPressable(
          onPressed: session == null
              ? null
              : () {
                  if (mode != current) session.setMode(mode);
                },
          classes: mode == current
              ? 'hermuse-computer-mode hermuse-computer-mode-on'
              : 'hermuse-computer-mode',
          attributes: {'aria-pressed': '${mode == current}'},
          builder: (context, press) => span([.text(label)]),
        ),
    ],
  );

  Component _tab(
    ComputerTab tab,
    ComputerSession? session, {
    required bool completed,
  }) => div(
    classes: tab.active
        ? 'hermuse-computer-tab hermuse-computer-tab-active'
        : 'hermuse-computer-tab',
    attributes: {'role': 'presentation'},
    [
      YsPressable(
        onPressed: session == null ? null : () => session.activateTab(tab.id),
        label: completed
            ? 'Browser window: ${tab.host}, Completed'
            : 'Browser window: ${tab.host}',
        classes: 'hermuse-computer-tab-main',
        attributes: {'role': 'tab', 'aria-selected': '${tab.active}'},
        builder: (context, press) => .fragment([
          if (completed)
            YsIconView(YsIcon.checkCircle, size: 16)
          else
            BrowserGlyphView(BrowserGlyph.globe, size: 16),
          span(classes: 'hermuse-computer-tab-host', [.text(tab.host)]),
        ]),
      ),
      YsPressable(
        onPressed: session == null ? null : () => session.closeTab(tab.id),
        label: 'Close browser window: ${tab.host}',
        classes: 'hermuse-computer-tab-close',
        builder: (context, press) => YsIconView(YsIcon.close, size: 14),
      ),
    ],
  );
}

/// The browser card of [thread]'s latest turn using the browser.
BrowserBlock? _latestBrowserBlock(Thread thread) {
  for (final message in thread.messages.reversed) {
    for (final block in message.blocks) {
      if (block is BrowserBlock) return block;
    }
  }
  return null;
}
