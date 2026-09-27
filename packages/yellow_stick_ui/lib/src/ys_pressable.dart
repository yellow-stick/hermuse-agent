import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Interaction state handed to an [YsPressable] builder.
final class YsPressableState {
  const YsPressableState({
    this.pressed = false,
    this.hovered = false,
    this.focused = false,
    this.disabled = false,
  });

  final bool pressed;
  final bool hovered;
  final bool focused;
  final bool disabled;
}

/// Headless pressable: tracks pressed/hovered/focused/disabled and hands the
/// state to [builder], like lynx-ui `ui-active`/`ui-disabled` variants.
///
/// Keyboard focusable; Enter/Space activate [onPressed] when enabled.
final class YsPressable extends StatefulWidget {
  const YsPressable({
    required this.builder,
    super.key,
    this.onPressed,
    this.semanticLabel,
    this.excludeSemantics = false,
    this.autofocus = false,
    this.focusNode,
    this.cursor = MouseCursor.defer,
    this.hitTestBehavior = HitTestBehavior.opaque,
  });

  final Widget Function(BuildContext context, YsPressableState state) builder;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final bool excludeSemantics;
  final bool autofocus;
  final FocusNode? focusNode;
  final MouseCursor cursor;
  final HitTestBehavior hitTestBehavior;

  bool get enabled => onPressed != null;

  @override
  State<YsPressable> createState() => _YsPressableState();
}

final class _YsPressableState extends State<YsPressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  void _activate() => widget.onPressed?.call();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enabled) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final state = YsPressableState(
      pressed: _pressed,
      hovered: _hovered,
      focused: _focused,
      disabled: !widget.enabled,
    );
    Widget child = widget.builder(context, state);
    if (!widget.excludeSemantics) {
      child = Semantics(
        button: true,
        label: widget.semanticLabel,
        enabled: widget.enabled,
        child: child,
      );
    }
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: widget.enabled ? SystemMouseCursors.click : widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          behavior: widget.hitTestBehavior,
          onTapDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.enabled ? _activate : null,
          child: child,
        ),
      ),
    );
  }
}
