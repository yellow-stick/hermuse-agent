import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Interactive state surfaced by [YsPressable] to its [YsPressable.builder].
final class YsPressState {
  const YsPressState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.disabled = false,
  });

  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool disabled;
}

/// Headless pressable rendering a real `<button>`.
///
/// [builder] receives the current [YsPressState] (like lynx-ui's `ui-active`
/// / `ui-disabled`); the rendered state is also exposed on the DOM via
/// `data-hovered` / `data-pressed` / `data-focused` / `data-disabled`
/// attributes so plain CSS can target it. Enter/Space activation, keyboard
/// focusability and `aria-label` come from the native button.
class YsPressable extends StatefulComponent {
  const YsPressable({
    required this.builder,
    this.onPressed,
    this.label,
    this.classes,
    this.styles,
    this.attributes,
    super.key,
  });

  /// Renders the button content for the current press state.
  final Component Function(BuildContext context, YsPressState state) builder;

  /// `null` renders a disabled button with `data-disabled="true"`.
  final VoidCallback? onPressed;

  /// Accessible label for icon-only content (`aria-label`).
  final String? label;

  final String? classes;
  final Styles? styles;
  final Map<String, String>? attributes;

  @override
  State<YsPressable> createState() => _YsPressableState();

  // Zero-specificity reset (`:where`): a pressable is a bare <button>, so
  // without it the browser's grey, centred button chrome shows through;
  // any component class still overrides it.
  @css
  // ignore: unused_element
  static List<StyleRule> get resetStyles => [
    css(':where(.ys-pressable)').styles(
      margin: .zero,
      padding: .zero,
      color: .inherit,
      backgroundColor: Colors.transparent,
      border: .none,
      cursor: .pointer,
      textAlign: .inherit,
      raw: {'font': 'inherit'},
    ),
    css(':where(.ys-pressable:disabled)').styles(cursor: .defaultCursor),
  ];
}

class _YsPressableState extends State<YsPressable> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  bool get _disabled => component.onPressed == null;

  @override
  Component build(BuildContext context) {
    final state = YsPressState(
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
      disabled: _disabled,
    );
    return button(
      type: .button,
      disabled: _disabled,
      onClick: _disabled ? null : component.onPressed,
      classes: ['ys-pressable', ?component.classes].join(' '),
      styles: component.styles,
      attributes: {
        ...?component.attributes,
        if (component.label != null) 'aria-label': component.label!,
        'data-hovered': '$_hovered',
        'data-pressed': '$_pressed',
        'data-focused': '$_focused',
        'data-disabled': '$_disabled',
      },
      events: {
        'mouseenter': (_) => setState(() => _hovered = true),
        'mouseleave': (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        'mousedown': (_) => setState(() => _pressed = true),
        'mouseup': (_) => setState(() => _pressed = false),
        'focus': (_) => setState(() => _focused = true),
        'blur': (_) => setState(() => _focused = false),
      },
      [component.builder(context, state)],
    );
  }
}
