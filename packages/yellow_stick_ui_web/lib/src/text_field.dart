import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

/// Single-line text input (sidebar search, custom choice answer).
///
/// Controlled through [value]/[onChanged]; Enter submits via [onSubmitted],
/// Escape calls [onEscape] (and stops there, so outer Escape handlers such
/// as a panel close do not also fire).
class YsTextField extends StatelessComponent {
  const YsTextField({
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.onEscape,
    this.placeholder,
    this.name,
    this.label,
    this.classes,
    this.autofocus = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final VoidCallback? onEscape;
  final String? placeholder;
  final String? name;
  final String? label;
  final String? classes;
  final bool autofocus;

  @override
  Component build(BuildContext context) => input<String>(
    type: .text,
    name: name,
    value: value,
    classes: ['ys-textfield', ?classes].join(' '),
    attributes: {
      'placeholder': ?placeholder,
      'aria-label': ?(label ?? placeholder),
    },
    onInput: onChanged,
    events: {
      'keydown': (event) {
        final key = (event as web.KeyboardEvent).key;
        if (key == 'Enter') {
          event.preventDefault();
          onSubmitted?.call();
        } else if (key == 'Escape' && onEscape != null) {
          event.preventDefault();
          event.stopPropagation();
          onEscape!();
        }
      },
    },
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-textfield', [
      css('&').styles(
        width: 100.percent,
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        border: .none,
        fontSize: 15.px,
        lineHeight: 24.px,
        raw: {'outline': 'none', 'font-family': 'inherit'},
      ),
      css('&::placeholder').styles(color: .variable('--content-subtle')),
      css('&:focus').styles(raw: {'outline': 'none'}),
    ]),
  ];
}
