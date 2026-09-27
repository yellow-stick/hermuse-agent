import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// Base state for the single- and multi-line inputs: owns an optional focus
/// node and repaints the placeholder overlay as the text changes.
mixin _InputState<T extends StatefulWidget> on State<T> {
  TextEditingController get controller;
  FocusNode? get focusNodeParam;
  bool get autofocusParam;

  late FocusNode focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _adoptFocusNode(null);
    controller.addListener(_onTextChanged);
  }

  void _adoptFocusNode(FocusNode? old) {
    final next = focusNodeParam;
    if (next == null) {
      focusNode = FocusNode();
      _ownsFocusNode = true;
    } else {
      focusNode = next;
      _ownsFocusNode = false;
    }
  }

  void didUpdateFocusNode(FocusNode? old) {
    if (focusNodeParam != old) {
      if (_ownsFocusNode) {
        focusNode.dispose();
      }
      _adoptFocusNode(old);
    }
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    controller.removeListener(_onTextChanged);
    if (_ownsFocusNode) {
      focusNode.dispose();
    }
    super.dispose();
  }

  /// Renders [child] with a placeholder overlay when the field is empty.
  Widget withPlaceholder(
    YsPalette palette,
    YsTextStyle textStyle,
    String placeholder,
    String? semanticLabel,
    Widget child,
  ) {
    final field = controller.text.isEmpty && placeholder.isNotEmpty
        ? Stack(
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  // The field's label already names it.
                  child: ExcludeSemantics(
                    child: Text(
                      placeholder,
                      style: textStyle.flutter.copyWith(
                        color: palette.contentSubtleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          )
        : child;
    // Its own node: a neighbouring button must not merge into the field.
    return Semantics(
      container: true,
      textField: true,
      label: semanticLabel ?? placeholder,
      value: controller.text,
      child: field,
    );
  }
}

/// Auto-growing multiline input (1–6 lines), Enter submits, Shift+Enter adds
/// a newline.
final class YsTextArea extends StatefulWidget {
  const YsTextArea({
    required this.controller,
    super.key,
    this.placeholder = '',
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.textStyle = YsType.input,
    this.semanticLabel,
    this.minLines = 1,
    this.maxLines = 6,
    this.textInputAction = TextInputAction.send,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final YsTextStyle textStyle;
  final String? semanticLabel;
  final int minLines;
  final int maxLines;
  final TextInputAction textInputAction;

  @override
  State<YsTextArea> createState() => _YsTextAreaState();
}

final class _YsTextAreaState extends State<YsTextArea> with _InputState {
  @override
  TextEditingController get controller => widget.controller;
  @override
  FocusNode? get focusNodeParam => widget.focusNode;
  @override
  bool get autofocusParam => widget.autofocus;

  @override
  void didUpdateWidget(YsTextArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    didUpdateFocusNode(oldWidget.focusNode);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    widget.onSubmitted?.call(widget.controller.text);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return withPlaceholder(
      palette,
      widget.textStyle,
      widget.placeholder,
      widget.semanticLabel,
      Focus(
        // Own internal node: must differ from the EditableText node below.
        onKeyEvent: _onKey,
        child: EditableText(
          controller: widget.controller,
          focusNode: focusNode,
          autofocus: widget.autofocus,
          style: widget.textStyle.flutter.copyWith(color: palette.contentColor),
          cursorColor: palette.primaryColor,
          backgroundCursorColor: palette.contentMutedColor,
          selectionColor: palette.primaryMutedColor,
          keyboardType: TextInputType.multiline,
          textInputAction: widget.textInputAction,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
        ),
      ),
    );
  }
}

/// Single-line input (sidebar search, custom choice answer).
final class YsTextField extends StatefulWidget {
  const YsTextField({
    required this.controller,
    super.key,
    this.placeholder = '',
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.textStyle = YsType.input,
    this.semanticLabel,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final YsTextStyle textStyle;
  final String? semanticLabel;
  final TextInputAction textInputAction;

  @override
  State<YsTextField> createState() => _YsTextFieldState();
}

final class _YsTextFieldState extends State<YsTextField> with _InputState {
  @override
  TextEditingController get controller => widget.controller;
  @override
  FocusNode? get focusNodeParam => widget.focusNode;
  @override
  bool get autofocusParam => widget.autofocus;

  @override
  void didUpdateWidget(YsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    didUpdateFocusNode(oldWidget.focusNode);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return withPlaceholder(
      palette,
      widget.textStyle,
      widget.placeholder,
      widget.semanticLabel,
      EditableText(
        controller: widget.controller,
        focusNode: focusNode,
        autofocus: widget.autofocus,
        style: widget.textStyle.flutter.copyWith(color: palette.contentColor),
        cursorColor: palette.primaryColor,
        backgroundCursorColor: palette.contentMutedColor,
        selectionColor: palette.primaryMutedColor,
        keyboardType: TextInputType.text,
        textInputAction: widget.textInputAction,
        maxLines: 1,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
