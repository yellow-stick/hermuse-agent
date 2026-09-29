import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../host/linux_setup.dart';
import 'browser_parts.dart';

/// The agent's computer in place of the chat (Muse's browser session
/// viewer): live frames, the browser's windows, Take control / Done and
/// Stop; beyond Muse, the whole desktop.
///
/// The stream opens only once the computer can start: the viewer builds a
/// missing computer image and keeps polling while Docker or the image are
/// not ready, so starting Docker recovers without reopening it.
final class ComputerViewer extends ConsumerStatefulWidget {
  const ComputerViewer({
    required this.controller,
    required this.instanceId,
    super.key,
  });

  final ChatController controller;
  final String instanceId;

  @override
  ConsumerState<ComputerViewer> createState() => _ComputerViewerState();
}

final class _ComputerViewerState extends ConsumerState<ComputerViewer> {
  /// Polling while the computer image is missing or building.
  static const _preparing = Duration(milliseconds: 1500);

  /// Polling while the computer cannot run (no Docker, no plugin…).
  static const _waiting = Duration(seconds: 5);

  final _canvas = FocusNode(debugLabel: 'Browser session canvas');

  /// Last readiness answer; null before the first.
  ComputerStatus? _status;

  /// Why nothing shows when [_status] does not say: a request failed, or
  /// the stream was lost again right after its re-check.
  String? _failure;

  /// `setup()` ran for the missing image (once per viewer).
  bool _setupSent = false;

  /// The one re-check after a lost stream is spent; a frame renews it.
  bool _rechecked = false;

  Timer? _poll;

  /// A stream is being opened: another check must not open a second one.
  bool _opening = false;
  ComputerSession? _session;
  StreamSubscription<Uint8List>? _frames;
  StreamSubscription<ComputerViewState>? _states;
  Uint8List? _frame;
  ComputerViewState _view = const ComputerViewState();

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    // Closing the stream hands a held control back to the agent.
    _drop();
    _canvas.dispose();
    super.dispose();
  }

  Future<ComputerClient> _computer() =>
      ref.read(computerClientProvider(widget.instanceId).future);

  void _pollIn(Duration delay) {
    _poll?.cancel();
    _poll = Timer(delay, () => unawaited(_check()));
  }

  /// Reads the computer's readiness and acts on it: builds a missing image,
  /// opens the stream of a startable computer, or polls.
  Future<void> _check() async {
    _poll?.cancel();
    final ComputerClient computer;
    final ComputerStatus status;
    try {
      computer = await _computer();
      status = await computer.status();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _failure = _describe(e));
      _pollIn(_waiting);
      return;
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      _failure = null;
    });
    switch (status.state) {
      case ComputerState.imageMissing:
        if (!_setupSent) {
          _setupSent = true;
          try {
            await computer.setup();
          } on Object catch (e) {
            if (mounted) setState(() => _failure = _describe(e));
          }
        }
        if (mounted) _pollIn(_preparing);
      case ComputerState.building:
        _pollIn(_preparing);
      case ComputerState.stopped || ComputerState.running:
        // The server starts a stopped computer.
        await _open(computer);
      case ComputerState.dockerMissing ||
          ComputerState.daemonDown ||
          ComputerState.error ||
          ComputerState.missing:
        _pollIn(_waiting);
    }
  }

  /// Retry of a failed computer: setup again (it rebuilds a failed image),
  /// then poll.
  Future<void> _retry() async {
    _poll?.cancel();
    setState(() {
      _failure = null;
      _rechecked = false;
    });
    try {
      final status = await (await _computer()).setup();
      if (mounted) setState(() => _status = status);
    } on Object catch (e) {
      if (mounted) setState(() => _failure = _describe(e));
    }
    if (mounted) _pollIn(_preparing);
  }

  Future<void> _open(ComputerClient computer) async {
    if (_opening || _session != null) return;
    _opening = true;
    final ComputerSession session;
    try {
      session = await computer.open(fps: 5);
    } on Object catch (e) {
      _opening = false;
      if (mounted) _lost(_describe(e));
      return;
    }
    _opening = false;
    if (!mounted) {
      unawaited(session.close());
      return;
    }
    _session = session;
    _frames = session.frames.listen(
      (frame) => setState(() {
        _frame = frame;
        _rechecked = false;
      }),
    );
    _states = session.states.listen(_onView);
    unawaited(
      session.closed.then((closed) {
        if (mounted && identical(session, _session)) _lost(closed.reason);
      }),
    );
    setState(() {});
  }

  /// The stream did not open or ended (4001 the computer cannot start, 4401
  /// ticket refused, or a lost link): check the computer once more with a
  /// new ticket, then show why.
  void _lost(String reason) {
    _drop();
    setState(() {
      _frame = null;
      _view = const ComputerViewState();
    });
    if (_rechecked) {
      setState(
        () => _failure = reason.isEmpty
            ? "Lost the connection to the agent's computer."
            : reason,
      );
      return;
    }
    _rechecked = true;
    unawaited(_check());
  }

  void _drop() {
    unawaited(_frames?.cancel());
    unawaited(_states?.cancel());
    final session = _session;
    _frames = null;
    _states = null;
    _session = null;
    if (session != null) unawaited(session.close());
  }

  void _onView(ComputerViewState view) {
    final gained = view.inControl && !_view.inControl;
    setState(() => _view = view);
    // Keys go to the page as soon as the user is in control.
    if (gained) _canvas.requestFocus();
  }

  static String _describe(Object error) => error is HermesException
      ? error.message
      : "Can't reach the agent's computer.";

  /// What the stage says until the first frame.
  String _statusText({required bool busy}) {
    if (_failure case final failure?) return failure;
    final status = _status;
    return switch (status?.state) {
      ComputerState.dockerMissing =>
        'Docker is not installed on the Hermes computer.',
      ComputerState.daemonDown =>
        'Docker is installed but not running. Start Docker to continue.',
      ComputerState.imageMissing => "Preparing the agent's computer…",
      ComputerState.building =>
        status!.detail.isEmpty
            ? "Preparing the agent's computer…"
            : status.detail,
      ComputerState.error =>
        status!.detail.isEmpty
            ? "The agent's computer could not start."
            : status.detail,
      ComputerState.missing =>
        'Install the Hermuse plugin on this Hermes to see its browser.',
      null || ComputerState.stopped || ComputerState.running =>
        busy ? 'Loading browser task' : 'Preparing browser preview',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the instance's computer client while the viewer shows.
    ref.watch(computerClientProvider(widget.instanceId));
    final palette = YsTheme.of(context);
    final chat = widget.controller.state;
    final thread = chat.activeThread;
    final block = _latestBrowserBlock(thread);
    final working = block?.running ?? false;
    final host = _view.activeTab?.host ?? block?.host ?? '';
    final view = _view;
    final session = _session;
    final frame = _frame;
    // On Linux the setup assistant installs or starts Docker for the
    // agent's computer; the viewer keeps polling meanwhile.
    final status = _status;
    final setUp =
        ref.watch(linuxSetupServicesProvider) != null &&
            _failure == null &&
            status != null &&
            (status.needsDesktopSetup ||
                status.state == ComputerState.daemonDown)
        ? () => unawaited(
            ref
                .read(linuxSetupProvider.notifier)
                .prepare(LinuxSetupGoal.computer),
          )
        : null;
    final (title, subtitle) = view.inControl
        ? ("You're in control", host)
        : view.control == ComputerControl.human
        ? ('Controlled from another device', host)
        : (
            working && block!.step.isNotEmpty
                ? block.step
                : browserTaskTitle(thread.title),
            [
              if (block != null) working ? 'Working' : 'Completed',
              if (host.isNotEmpty) host,
            ].join(' · '),
          );
    const black = Color(0xFF000000);
    final blue = Color(browserBlue.value);
    final actions = [
      if (session != null)
        _ModeToggle(
          mode: view.mode,
          onChanged: (mode) {
            if (mode != view.mode) session.setMode(mode);
          },
        ),
      if (chat.busy)
        BrowserPill(
          label: 'Stop',
          leading: BrowserGlyphIcon(
            BrowserGlyph.record,
            color: palette.error,
            size: 18,
          ),
          foreground: view.inControl
              ? palette.contentColor
              : palette.errorColor,
          background: view.inControl ? Color(browserPillGrey.value) : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          onPressed: () => unawaited(widget.controller.interrupt()),
        ),
      if (view.inControl)
        BrowserPill(
          label: 'Done',
          semanticLabel: 'Hand browser control back to the assistant',
          leading: const YsIconWidget(YsIcon.check, size: 18, color: black),
          foreground: black,
          background: blue,
          radius: 24,
          onPressed: session?.release,
        )
      else
        BrowserPill(
          label: 'Take control of the browser',
          foreground: black,
          background: blue,
          radius: 24,
          onPressed: session?.take,
        ),
    ];
    final live =
        session != null && frame != null && view.width > 0 && view.height > 0;
    return Semantics(
      container: true,
      role: SemanticsRole.region,
      label: 'Browser session viewer',
      explicitChildNodes: true,
      child: ColoredBox(
        color: palette.canvasColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: title,
              subtitle: subtitle,
              actions: actions,
              onClose: widget.controller.closeComputer,
            ),
            if (session != null && view.tabs.isNotEmpty)
              _Tabs(
                tabs: view.tabs,
                working: working,
                onActivate: session.activateTab,
                onClose: session.closeTab,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: live
                    ? _Screen(
                        frame: frame,
                        view: view,
                        session: session,
                        focusNode: _canvas,
                      )
                    : _Status(
                        text: _statusText(busy: chat.busy),
                        command: switch ((_failure, _status, setUp)) {
                          (
                            null,
                            ComputerStatus(
                              state: ComputerState.dockerMissing,
                              :final detail,
                            ),
                            null,
                          )
                              when detail.isNotEmpty =>
                            detail,
                          _ => null,
                        },
                        onRetry:
                            _failure != null ||
                                _status?.state == ComputerState.error
                            ? () => unawaited(_retry())
                            : null,
                        onSetUp: setUp,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The thread's latest browser card, which the viewer continues.
BrowserBlock? _latestBrowserBlock(Thread thread) {
  for (final message in thread.messages.reversed) {
    for (final block in message.blocks) {
      if (block is BrowserBlock) return block;
    }
  }
  return null;
}

/// Viewer header: title and subtitle, [actions], close. Below 640 px the
/// actions wrap on a row of their own.
final class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.onClose,
  });

  static const _titleStyle = YsTextStyle(15, 20, YsWeight.semibold);

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: _titleStyle.flutter.copyWith(color: palette.contentColor),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
    final close = YsButton.icon(
      icon: YsIcon.close,
      onPressed: onClose,
      semanticLabel: 'Close browser session panel',
      size: 36,
      iconSize: 20,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.lineColor, width: ysHairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 5, 12, 5),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 640
              ? Row(
                  children: [
                    Expanded(child: heading),
                    for (final action in actions) ...[
                      const SizedBox(width: 8),
                      action,
                    ],
                    const SizedBox(width: 8),
                    close,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: heading),
                        const SizedBox(width: 8),
                        close,
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: actions,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// `Browser | Desktop`: what the stream shows.
final class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final ComputerMode mode;
  final ValueChanged<ComputerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralAmbientColor,
        borderRadius: BorderRadius.circular(YsRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in const [
              ('Browser', ComputerMode.browser),
              ('Desktop', ComputerMode.desktop),
            ])
              Semantics(
                container: true,
                button: true,
                selected: mode == value,
                label: label,
                child: YsPressable(
                  onPressed: () => onChanged(value),
                  excludeSemantics: true,
                  builder: (context, state) => ExcludeSemantics(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: YsMotion.fast),
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: mode == value
                            ? palette.neutralFilmColor
                            : state.hovered
                            ? palette.neutralFilmColor.withValues(alpha: 0.4)
                            : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(YsRadius.segment),
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          style: YsType.label.flutter.copyWith(
                            color: mode == value
                                ? palette.contentColor
                                : palette.contentMutedColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One tab per browser window (Muse): the page in front while the agent
/// works on it shows a globe, finished ones a check.
final class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tabs,
    required this.working,
    required this.onActivate,
    required this.onClose,
  });

  final List<ComputerTab> tabs;
  final bool working;
  final ValueChanged<String> onActivate;
  final ValueChanged<String> onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Semantics(
      container: true,
      role: SemanticsRole.tabBar,
      label: 'Open browser windows',
      explicitChildNodes: true,
      child: Row(
        children: [
          for (final (i, tab) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 4),
            Flexible(
              child: SizedBox(
                width: 172,
                height: 40,
                child: _Tab(
                  tab: tab,
                  completed: !(working && tab.active),
                  onActivate: () => onActivate(tab.id),
                  onClose: () => onClose(tab.id),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

final class _Tab extends StatelessWidget {
  const _Tab({
    required this.tab,
    required this.completed,
    required this.onActivate,
    required this.onClose,
  });

  final ComputerTab tab;

  /// The agent is not working in it (any tab but the one in front of a
  /// working agent).
  final bool completed;
  final VoidCallback onActivate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final host = tab.host;
    return Semantics(
      container: true,
      role: SemanticsRole.tab,
      selected: tab.active,
      label: completed
          ? 'Browser window: $host, Completed'
          : 'Browser window: $host',
      child: YsPressable(
        onPressed: onActivate,
        excludeSemantics: true,
        builder: (context, state) => AnimatedContainer(
          duration: const Duration(milliseconds: YsMotion.fast),
          padding: const EdgeInsets.only(left: 12, right: 6),
          decoration: BoxDecoration(
            color: tab.active
                ? palette.neutralAmbientColor
                : state.hovered
                ? palette.neutralFilmColor.withValues(alpha: 0.4)
                : const Color(0x00000000),
            borderRadius: BorderRadius.circular(YsRadius.row),
          ),
          child: Row(
            children: [
              ExcludeSemantics(
                child: completed
                    ? YsIconWidget(
                        YsIcon.checkCircle,
                        size: 16,
                        color: palette.successColor,
                      )
                    : const BrowserGlyphIcon(
                        BrowserGlyph.globe,
                        color: browserBlue,
                        size: 16,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    host,
                    style: YsType.small.flutter.copyWith(
                      color: tab.active
                          ? palette.contentColor
                          : palette.contentMutedColor,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              YsButton.icon(
                icon: YsIcon.close,
                onPressed: onClose,
                semanticLabel: 'Close browser window: $host',
                size: 24,
                iconSize: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before the first frame: why the computer does not show yet, with the
/// shell [command] to paste on the Hermes host when there is one, or the
/// Linux setup assistant to open ([onSetUp]).
final class _Status extends StatelessWidget {
  const _Status({
    required this.text,
    required this.onRetry,
    this.command,
    this.onSetUp,
  });

  final String text;
  final String? command;
  final VoidCallback? onRetry;
  final VoidCallback? onSetUp;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final onRetry = this.onRetry;
    final onSetUp = this.onSetUp;
    final command = this.command;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: YsType.label.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (command != null) ...[
              const SizedBox(height: 12),
              _Command(command),
            ],
            if (onSetUp != null) ...[
              const SizedBox(height: 12),
              YsButton.neutral(label: 'Set up Docker', onPressed: onSetUp),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              YsButton.neutral(label: 'Retry', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shell command in a selectable monospace box, with a Copy button.
final class _Command extends StatefulWidget {
  const _Command(this.command);

  final String command;

  @override
  State<_Command> createState() => _CommandState();
}

final class _CommandState extends State<_Command> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.command));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.paperColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                widget.command,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 20 / 13,
                ).copyWith(color: palette.contentColor),
              ),
            ),
            const SizedBox(width: 8),
            YsButton.neutral(
              label: _copied ? 'Copied' : 'Copy',
              onPressed: _copy,
              textStyle: YsType.small,
              height: 28,
            ),
          ],
        ),
      ),
    );
  }
}

/// The live screen, contain-fit, that takes pointer and keyboard input
/// while the user is in control; coordinates are sent in frame pixels.
final class _Screen extends StatefulWidget {
  const _Screen({
    required this.frame,
    required this.view,
    required this.session,
    required this.focusNode,
  });

  final Uint8List frame;
  final ComputerViewState view;
  final ComputerSession session;
  final FocusNode focusNode;

  @override
  State<_Screen> createState() => _ScreenState();
}

final class _ScreenState extends State<_Screen> {
  /// Trackpad pixels per wheel notch.
  static const _notch = 40.0;

  /// X button held by each pointer.
  final _buttons = <int, int>{};

  /// Trackpad scroll not sent yet, positive downwards.
  double _pan = 0;

  ComputerSession get _session => widget.session;

  /// [local] (inside the picture of [size]) in frame pixels.
  (num, num) _at(Offset local, Size size) {
    final view = widget.view;
    return (
      (local.dx / size.width * view.width).clamp(0, view.width - 1),
      (local.dy / size.height * view.height).clamp(0, view.height - 1),
    );
  }

  void _move(PointerEvent event, Size size) {
    final (x, y) = _at(event.localPosition, size);
    _session.move(x, y);
  }

  void _down(PointerDownEvent event, Size size) {
    widget.focusNode.requestFocus();
    final buttons = event.buttons;
    final button = buttons & kSecondaryMouseButton != 0
        ? 3
        : buttons & kMiddleMouseButton != 0
        ? 2
        : 1;
    _buttons[event.pointer] = button;
    final (x, y) = _at(event.localPosition, size);
    _session.down(x, y, button: button);
  }

  void _up(PointerEvent event, Size size) {
    final button = _buttons.remove(event.pointer);
    if (button == null) return;
    final (x, y) = _at(event.localPosition, size);
    _session.up(x, y, button: button);
  }

  void _scroll(PointerSignalEvent event, Size size) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy.sign.toInt();
    if (dy == 0) return;
    final (x, y) = _at(event.localPosition, size);
    _session.wheel(x, y, dy);
  }

  /// Trackpad scrolling (macOS): content follows the fingers, one wheel
  /// notch per [_notch] pixels.
  void _pinch(PointerPanZoomUpdateEvent event, Size size) {
    _pan -= event.panDelta.dy;
    final (x, y) = _at(event.localPosition, size);
    while (_pan.abs() >= _notch) {
      final dy = _pan.sign.toInt();
      _session.wheel(x, y, dy);
      _pan -= dy * _notch;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final down = event is! KeyUpEvent;
    final keyboard = HardwareKeyboard.instance;
    final keysym =
        _keysym(event.logicalKey) ??
        // Control or Meta + letter or digit: a shortcut (Ctrl+C).
        keysymFor(
          event.logicalKey.keyLabel,
          controlOrMeta: keyboard.isControlPressed || keyboard.isMetaPressed,
        );
    if (keysym != null) {
      _session.key(keysym, down: down);
      return KeyEventResult.handled;
    }
    final text = event.character;
    if (text != null && _printable(text)) {
      if (down) _session.text(text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final input = view.inControl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / view.width,
          constraints.maxHeight / view.height,
        );
        final size = Size(view.width * scale, view.height * scale);
        return Center(
          child: Semantics(
            container: true,
            label: 'Browser session canvas',
            child: Focus(
              focusNode: widget.focusNode,
              onKeyEvent: input ? _onKey : null,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerHover: input ? (e) => _move(e, size) : null,
                onPointerMove: input ? (e) => _move(e, size) : null,
                onPointerDown: input ? (e) => _down(e, size) : null,
                onPointerUp: input ? (e) => _up(e, size) : null,
                onPointerCancel: input ? (e) => _up(e, size) : null,
                onPointerSignal: input ? (e) => _scroll(e, size) : null,
                onPointerPanZoomStart: input ? (_) => _pan = 0 : null,
                onPointerPanZoomUpdate: input ? (e) => _pinch(e, size) : null,
                child: SizedBox.fromSize(
                  size: size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FrameImage(widget.frame),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Keys sent as X keysyms, as [keysymFor] names them for the web.
String? _keysym(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'Return',
  LogicalKeyboardKey.backspace => 'BackSpace',
  LogicalKeyboardKey.tab => 'Tab',
  LogicalKeyboardKey.escape => 'Escape',
  LogicalKeyboardKey.delete => 'Delete',
  LogicalKeyboardKey.home => 'Home',
  LogicalKeyboardKey.end => 'End',
  LogicalKeyboardKey.pageUp => 'Prior',
  LogicalKeyboardKey.pageDown => 'Next',
  LogicalKeyboardKey.arrowLeft => 'Left',
  LogicalKeyboardKey.arrowRight => 'Right',
  LogicalKeyboardKey.arrowUp => 'Up',
  LogicalKeyboardKey.arrowDown => 'Down',
  LogicalKeyboardKey.shiftLeft || LogicalKeyboardKey.shiftRight => 'Shift_L',
  LogicalKeyboardKey.controlLeft ||
  LogicalKeyboardKey.controlRight => 'Control_L',
  // Not the right Alt: AltGr composes characters, typed as text.
  LogicalKeyboardKey.altLeft => 'Alt_L',
  LogicalKeyboardKey.metaLeft || LogicalKeyboardKey.metaRight => 'Super_L',
  LogicalKeyboardKey.f1 => 'F1',
  LogicalKeyboardKey.f2 => 'F2',
  LogicalKeyboardKey.f3 => 'F3',
  LogicalKeyboardKey.f4 => 'F4',
  LogicalKeyboardKey.f5 => 'F5',
  LogicalKeyboardKey.f6 => 'F6',
  LogicalKeyboardKey.f7 => 'F7',
  LogicalKeyboardKey.f8 => 'F8',
  LogicalKeyboardKey.f9 => 'F9',
  LogicalKeyboardKey.f10 => 'F10',
  LogicalKeyboardKey.f11 => 'F11',
  LogicalKeyboardKey.f12 => 'F12',
  LogicalKeyboardKey.space => 'space',
  _ => null,
};

/// Text a key typed: no control characters.
bool _printable(String text) =>
    text.isNotEmpty && text.runes.every((r) => r >= 0x20 && r != 0x7F);
