import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

/// Labeled wrapper for a [child] field (text/options/notes).
class YsField extends StatelessComponent {
  const YsField({required this.label, required this.child, super.key});

  final String label;
  final Component child;

  @override
  Component build(BuildContext context) => div(classes: 'ys-field', [
    span(classes: 'ys-field-label', [.text(label)]),
    child,
  ]);

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-field', [
      css('&').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        gap: .all(6.px),
      ),
      css('.ys-field-label').styles(
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content-muted'),
      ),
    ]),
  ];
}

/// A boxed text input (44 high, canvas fill, hairline border).
class YsInputBox extends StatelessComponent {
  const YsInputBox({
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.name,
    this.label,
    this.obscure = false,
    this.autocomplete,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final String? placeholder;
  final String? name;
  final String? label;
  final bool obscure;
  final String? autocomplete;

  @override
  Component build(BuildContext context) => input<String>(
    type: obscure ? .password : .text,
    name: name,
    value: value,
    classes: 'ys-inputbox',
    attributes: {
      'placeholder': ?placeholder,
      'aria-label': ?(label ?? placeholder),
      'autocomplete': ?autocomplete,
    },
    onInput: onChanged,
    events: {
      'keydown': (event) {
        if ((event as web.KeyboardEvent).key == 'Enter') {
          event.preventDefault();
          onSubmitted?.call();
        }
      },
    },
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-inputbox', [
      css('&').styles(
        height: 44.px,
        padding: .symmetric(horizontal: 14.px),
        radius: .circular(10.px),
        color: .variable('--content'),
        backgroundColor: .variable('--canvas'),
        border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
        fontSize: 15.px,
        lineHeight: 24.px,
        raw: {'outline': 'none', 'font-family': 'inherit'},
      ),
      css('&:focus').styles(
        border: .all(
          style: .solid,
          color: .variable('--primary'),
          width: 1.2.px,
        ),
      ),
      css('&::placeholder').styles(color: .variable('--content-subtle')),
    ]),
  ];
}

/// A multi-line boxed editor (grows with content up to [maxHeight]).
class YsTextBox extends StatelessComponent {
  const YsTextBox({
    required this.value,
    required this.onChanged,
    this.placeholder,
    this.name,
    this.label,
    this.maxHeight = 320,
    this.minHeight = 120,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? placeholder;
  final String? name;
  final String? label;
  final double maxHeight;
  final double minHeight;

  @override
  Component build(BuildContext context) => textarea(
    [.text(value)],
    classes: 'ys-textbox',
    styles: Styles(
      raw: {'min-height': '${minHeight}px', 'max-height': '${maxHeight}px'},
    ),
    placeholder: placeholder,
    name: name,
    attributes: {'aria-label': ?(label ?? placeholder)},
    onInput: onChanged,
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-textbox', [
      css('&').styles(
        width: 100.percent,
        padding: .all(14.px),
        radius: .circular(10.px),
        color: .variable('--content'),
        backgroundColor: .variable('--canvas'),
        border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
        overflow: .only(y: .auto, x: .hidden),
        fontSize: 15.px,
        lineHeight: 24.px,
        raw: {
          'outline': 'none',
          'font-family': 'inherit',
          'white-space': 'pre-wrap',
          'resize': 'vertical',
        },
      ),
      css('&:focus').styles(
        border: .all(
          style: .solid,
          color: .variable('--primary'),
          width: 1.2.px,
        ),
      ),
      css('&::placeholder').styles(color: .variable('--content-subtle')),
    ]),
  ];
}

/// A `<select>` dropdown in a 44-high box.
class YsSelect extends StatelessComponent {
  const YsSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    super.key,
  });

  /// Currently selected option value.
  final String value;

  /// (value, label) pairs.
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;
  final String? label;

  @override
  Component build(BuildContext context) => select(
    classes: 'ys-select',
    attributes: {'aria-label': ?label},
    events: {
      'change': (event) {
        // Typed access: a dynamic `.value` on a JS object throws once
        // compiled to JavaScript.
        onChanged((event.target! as web.HTMLSelectElement).value);
      },
    },
    [
      for (final (v, l) in options)
        option(value: v, selected: v == value, [.text(l)]),
    ],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-select').styles(
      height: 44.px,
      padding: .symmetric(horizontal: 14.px),
      radius: .circular(10.px),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
      fontSize: 15.px,
      lineHeight: 24.px,
      raw: {'outline': 'none', 'font-family': 'inherit'},
    ),
  ];
}
