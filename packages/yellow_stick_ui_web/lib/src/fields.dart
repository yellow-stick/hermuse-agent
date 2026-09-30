import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'icon.dart';
import 'keyframes.dart';
import 'motion.dart';

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

/// A boxed text input (44 high, canvas fill, hairline border) with an
/// optional leading [icon]. Focus eases the border to `primary`, lights the
/// icon and rings the box with a soft [YsLayout.inputHalo] halo.
class YsInputBox extends StatelessComponent {
  const YsInputBox({
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.name,
    this.label,
    this.obscure = false,
    this.url = false,
    this.icon,
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

  /// A web address (`type="url"`): phones offer their URL keyboard.
  final bool url;

  /// Glyph before the text, muted until the box has focus.
  final YsIcon? icon;
  final String? autocomplete;

  @override
  Component build(BuildContext context) {
    final field = input<String>(
      type: obscure
          ? .password
          : url
          ? .url
          : .text,
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
    final icon = this.icon;
    if (icon == null) return field;
    return span(classes: 'ys-inputbox-host', [
      span(classes: 'ys-inputbox-icon', [
        YsIconView(icon, size: YsLayout.inlineIcon),
      ]),
      field,
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    final ease = '${YsMotion.fast}ms ${YsEase.standard.css}';
    const pad = 14.0;
    return [
      css('.ys-inputbox', [
        css('&').styles(
          height: 44.px,
          padding: .symmetric(horizontal: pad.px),
          radius: .circular(10.px),
          color: .variable('--content'),
          backgroundColor: .variable('--canvas'),
          border: .all(
            style: .solid,
            color: .variable('--line'),
            width: 1.2.px,
          ),
          fontSize: 15.px,
          lineHeight: 24.px,
          raw: {
            'outline': 'none',
            'font-family': 'inherit',
            // The halo at rest: transparent, so focus eases it in.
            'box-shadow':
                '0px 0px 0px ${ysNum(YsLayout.inputHalo)}px '
                'transparent',
            'transition': 'border-color $ease, box-shadow $ease',
          },
        ),
        css('&:focus').styles(
          border: .all(
            style: .solid,
            color: .variable('--primary'),
            width: 1.2.px,
          ),
          raw: {
            'box-shadow':
                '0px 0px 0px ${ysNum(YsLayout.inputHalo)}px '
                'var(--primary-muted)',
          },
        ),
        css('&::placeholder').styles(color: .variable('--content-subtle')),
      ]),
      // With an icon, the box fills its host and its text clears the icon.
      css('.ys-inputbox-host', [
        css('&').styles(
          position: .relative(),
          display: .flex,
          alignItems: .center,
          raw: {'min-width': '0'},
        ),
        css('.ys-inputbox').styles(
          flex: .grow(1),
          padding: .only(
            left: (pad + YsLayout.inlineIcon + YsSpace.sm + YsSpace.xxs).px,
          ),
          raw: {'min-width': '0'},
        ),
        css('.ys-inputbox-icon').styles(
          position: .absolute(left: pad.px),
          display: .flex,
          color: .variable('--content-subtle'),
          pointerEvents: .none,
          raw: {'transition': 'color $ease'},
        ),
        css('&:focus-within .ys-inputbox-icon')
            .styles(color: .variable('--primary')),
      ]),
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-inputbox, .ys-inputbox-icon')
            .styles(raw: {'transition': 'none'}),
      ]),
    ];
  }
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
