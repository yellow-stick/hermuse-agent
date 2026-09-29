import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_icon_widget.dart';
import 'ys_menu.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';

/// Dropdown select in a 44-high box (web `YsSelect` parity).
///
/// Opens an [OverlayPortal] menu anchored under the box; Escape, scrim tap,
/// or an option tap closes it. The menu lists [(value, label)] pairs with
/// the selected value checked.
final class YsSelect extends StatefulWidget {
  const YsSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
    this.semanticLabel,
    this.placeholder = 'Select',
  });

  /// Currently selected option value ('': nothing selected).
  final String value;

  /// (value, label) pairs.
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final String? semanticLabel;
  final String placeholder;

  @override
  State<YsSelect> createState() => _YsSelectState();
}

final class _YsSelectState extends State<YsSelect> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final current = widget.options
        .where((o) => o.$1 == widget.value)
        .firstOrNull;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (context) => _Menu(
          link: _link,
          options: widget.options,
          selected: widget.value,
          onClose: _controller.hide,
          onChanged: widget.onChanged,
        ),
        child: YsPressable(
          onPressed: _controller.show,
          semanticLabel: widget.semanticLabel ?? widget.placeholder,
          builder: (context, state) => AnimatedContainer(
            duration: const Duration(milliseconds: YsMotion.fast),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.canvasColor,
              borderRadius: BorderRadius.circular(YsRadius.row),
              border: Border.all(
                color: state.focused ? palette.primaryColor : palette.lineColor,
                width: ysHairline,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current?.$2 ?? widget.placeholder,
                    style: YsType.input.flutter.copyWith(
                      color: current == null
                          ? palette.contentSubtleColor
                          : palette.contentColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                YsIconWidget(
                  YsIcon.chevronDown,
                  size: 18,
                  color: palette.contentMutedColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Menu extends StatelessWidget {
  const _Menu({
    required this.link,
    required this.options,
    required this.selected,
    required this.onClose,
    required this.onChanged,
  });

  final LayerLink link;
  final List<(String, String)> options;
  final String selected;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 288, minWidth: 200),
            child: YsMenuSurface(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (value, label) in options)
                      YsPressable(
                        onPressed: () {
                          onClose();
                          onChanged(value);
                        },
                        semanticLabel: label,
                        builder: (context, state) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: state.hovered || state.pressed
                                ? palette.neutralFilmColor
                                : const Color(0x00000000),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    label,
                                    style: YsType.input.flutter.copyWith(
                                      color: palette.contentColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (value == selected)
                                  YsIconWidget(
                                    YsIcon.check,
                                    size: 16,
                                    color: palette.primaryColor,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Labeled wrapper for a [child] field (web `YsField` parity).
final class YsField extends StatelessWidget {
  const YsField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: YsType.label.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Boxed single-line input: 44 high, canvas fill, hairline border
/// (web `YsInputBox` parity), with an `obscure` password mode.
final class YsInputBox extends StatefulWidget {
  const YsInputBox({
    required this.controller,
    super.key,
    this.placeholder = '',
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.obscure = false,
    this.textStyle = YsType.input,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final bool obscure;
  final YsTextStyle textStyle;

  @override
  State<YsInputBox> createState() => _YsInputBoxState();
}

final class _YsInputBoxState extends State<YsInputBox> {
  late FocusNode _focus;
  bool _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? (FocusNode()..addListener(_refocus));
    _ownsFocus = widget.focusNode == null;
    if (!_ownsFocus) _focus.addListener(_refocus);
    widget.controller.addListener(_repaint);
  }

  void _refocus() => setState(() {});
  void _repaint() => setState(() {});

  @override
  void didUpdateWidget(YsInputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_repaint);
      widget.controller.addListener(_repaint);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      _focus.removeListener(_refocus);
      if (_ownsFocus) _focus.dispose();
      _focus = widget.focusNode ?? (FocusNode()..addListener(_refocus));
      _ownsFocus = widget.focusNode == null;
      if (!_ownsFocus) _focus.addListener(_refocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_repaint);
    _focus.removeListener(_refocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final empty = widget.controller.text.isEmpty;
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.canvasColor,
          borderRadius: BorderRadius.circular(YsRadius.row),
          border: Border.all(
            color: _focus.hasFocus ? palette.primaryColor : palette.lineColor,
            width: ysHairline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          // The box is taller than one text line: centre the line so the
          // text, cursor and placeholder share the box's centre.
          child: Align(
            alignment: Alignment.centerLeft,
            child: Stack(
              children: [
                EditableText(
                  controller: widget.controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  style: widget.textStyle.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                  cursorColor: palette.primaryColor,
                  backgroundCursorColor: palette.contentMutedColor,
                  selectionColor: palette.primaryMutedColor,
                  keyboardType: widget.obscure
                      ? TextInputType.visiblePassword
                      : TextInputType.text,
                  obscureText: widget.obscure,
                  maxLines: 1,
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                ),
                if (empty && widget.placeholder.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          widget.placeholder,
                          style: widget.textStyle.flutter.copyWith(
                            color: palette.contentSubtleColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Multi-line boxed editor (web `YsTextBox` parity).
final class YsTextBox extends StatefulWidget {
  const YsTextBox({
    required this.controller,
    super.key,
    this.placeholder = '',
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.minHeight = 120,
    this.maxHeight = 320,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;
  final double minHeight;
  final double maxHeight;

  @override
  State<YsTextBox> createState() => _YsTextBoxState();
}

final class _YsTextBoxState extends State<YsTextBox> {
  late FocusNode _focus;
  bool _ownsFocus = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? (FocusNode()..addListener(_refocus));
    _ownsFocus = widget.focusNode == null;
    if (!_ownsFocus) _focus.addListener(_refocus);
    widget.controller.addListener(_repaint);
  }

  void _refocus() => setState(() {});
  void _repaint() => setState(() {});

  @override
  void didUpdateWidget(YsTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_repaint);
      widget.controller.addListener(_repaint);
    }
    if (widget.focusNode != oldWidget.focusNode) {
      _focus.removeListener(_refocus);
      if (_ownsFocus) _focus.dispose();
      _focus = widget.focusNode ?? (FocusNode()..addListener(_refocus));
      _ownsFocus = widget.focusNode == null;
      if (!_ownsFocus) _focus.addListener(_refocus);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_repaint);
    _focus.removeListener(_refocus);
    if (_ownsFocus) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final empty = widget.controller.text.isEmpty;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: widget.minHeight,
        maxHeight: widget.maxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.canvasColor,
          borderRadius: BorderRadius.circular(YsRadius.row),
          border: Border.all(
            color: _focus.hasFocus ? palette.primaryColor : palette.lineColor,
            width: ysHairline,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Stack(
            children: [
              EditableText(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                style: YsType.input.flutter.copyWith(
                  color: palette.contentColor,
                ),
                cursorColor: palette.primaryColor,
                backgroundCursorColor: palette.contentMutedColor,
                selectionColor: palette.primaryMutedColor,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                onChanged: widget.onChanged,
              ),
              if (empty && widget.placeholder.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        widget.placeholder,
                        style: YsType.input.flutter.copyWith(
                          color: palette.contentSubtleColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog: centered card over a backdrop scrim (web `YsDialog`
/// parity). [onClose] fires from the ✕ button, a scrim tap and Escape.
///
/// Modal: focus moves into the dialog (Tab stays inside) and returns where
/// it was when the dialog goes away; content behind it is hidden from
/// assistive technologies.
final class YsDialog extends StatefulWidget {
  const YsDialog({
    required this.title,
    required this.onClose,
    required this.child,
    this.actions = const [],
    this.wide = false,
    super.key,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final List<Widget> actions;
  final bool wide;

  @override
  State<YsDialog> createState() => _YsDialogState();
}

final class _YsDialogState extends State<YsDialog> {
  late final _scope = FocusScopeNode(
    debugLabel: 'YsDialog',
    onKeyEvent: _onKey,
  );
  final _returnFocus = FocusManager.instance.primaryFocus;

  @override
  void initState() {
    super.initState();
    // An `autofocus` child (applied after this frame) wins over the scope.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    final back = _returnFocus;
    if (back != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (back.context?.mounted ?? false) back.requestFocus();
      });
    }
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final actions = widget.actions;
    return BlockSemantics(
      child: FocusScope(
        node: _scope,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                excludeFromSemantics: true,
                child: ColoredBox(color: palette.backdropColor),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: widget.wide
                      ? YsLayout.listWidth
                      : YsLayout.dialogWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Semantics(
                    role: SemanticsRole.dialog,
                    scopesRoute: true,
                    namesRoute: true,
                    explicitChildNodes: true,
                    label: widget.title,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.paperColor,
                        borderRadius: BorderRadius.circular(YsRadius.bubble),
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.title,
                                      style: YsType.heading.flutter.copyWith(
                                        color: palette.contentColor,
                                      ),
                                    ),
                                  ),
                                  YsButtonIconClose(widget.onClose),
                                ],
                              ),
                              const SizedBox(height: 16),
                              widget.child,
                              if (actions.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    for (
                                      var i = 0;
                                      i < actions.length;
                                      i++
                                    ) ...[
                                      if (i > 0) const SizedBox(width: 12),
                                      actions[i],
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
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

/// Close (✕) icon button for dialog headers.
final class YsButtonIconClose extends StatelessWidget {
  const YsButtonIconClose(this.onClose, {super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => YsPressable(
    onPressed: onClose,
    semanticLabel: 'Close',
    builder: (context, state) => SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: YsIconWidget(
          YsIcon.close,
          size: 18,
          color: YsTheme.of(context).contentMutedColor,
        ),
      ),
    ),
  );
}
