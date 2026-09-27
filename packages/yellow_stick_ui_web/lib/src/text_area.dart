import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;

/// Auto-growing multiline input (1–6 lines).
///
/// Enter submits via [onSubmitted], Shift+Enter inserts a newline. The value
/// is controlled through [value]/[onChanged]. Auto-grow is implemented with
/// the classic mirror technique: an invisible `<div>` mirrors the text so the
/// `<textarea>` can size to its content without measuring on the server.
class YsTextArea extends StatefulComponent {
  const YsTextArea({
    required this.value,
    required this.onChanged,
    this.onSubmitted,
    this.placeholder,
    this.name,
    this.classes,
    this.autofocus = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final String? placeholder;
  final String? name;
  final String? classes;
  final bool autofocus;

  @override
  State<YsTextArea> createState() => _YsTextAreaState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-textarea', [
      css('&').styles(
        display: .grid,
        backgroundColor: Colors.transparent,
        raw: {
          'grid-template-areas': '"stack"',
          'min-height': '24px',
          'max-height': '192px',
        },
      ),
      css('.ys-textarea-mirror, .ys-textarea-input').styles(
        overflow: .hidden,
        fontSize: 15.px,
        lineHeight: 24.px,
        raw: {
          'grid-area': 'stack',
          'font-family': 'inherit',
          'white-space': 'pre-wrap',
          'word-break': 'break-word',
          'overflow-wrap': 'anywhere',
        },
      ),
      css('.ys-textarea-mirror').styles(
        margin: .zero,
        padding: .zero,
        visibility: .hidden,
        raw: {'pointer-events': 'none'},
      ),
      css('.ys-textarea-input').styles(
        width: 100.percent,
        height: 100.percent,
        margin: .zero,
        padding: .zero,
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        border: .none,
        raw: {'outline': 'none', 'resize': 'none'},
      ),
      css('.ys-textarea-input::placeholder')
          .styles(color: .variable('--content-subtle')),
      css('&:focus-within .ys-textarea-input').styles(raw: {'outline': 'none'}),
    ]),
  ];
}

class _YsTextAreaState extends State<YsTextArea> {
  final _key = GlobalNodeKey<web.HTMLTextAreaElement>();

  @override
  void didUpdateComponent(covariant YsTextArea oldComponent) {
    super.didUpdateComponent(oldComponent);
    // The textarea keeps its own DOM value while typing; when the controlled
    // value changes from outside (e.g. cleared after submit), push it into
    // the live element.
    final node = _key.currentNode;
    if (node != null && node.value != component.value) {
      node.value = component.value;
    }
  }

  @override
  Component build(BuildContext context) {
    final value = component.value;
    // A trailing newline keeps the mirror one line taller so the last visible
    // line never clips while typing.
    final mirror = value.isEmpty ? '\u200b' : '$value\n';
    return div(classes: ['ys-textarea', ?component.classes].join(' '), [
      div(
        classes: 'ys-textarea-mirror',
        attributes: {'aria-hidden': 'true'},
        [.text(mirror)],
      ),
      textarea(
        [.text(value)],
        key: _key,
        name: component.name,
        placeholder: component.placeholder,
        autofocus: component.autofocus,
        spellCheck: .isTrue,
        rows: 1,
        classes: 'ys-textarea-input',
        attributes: {'aria-label': ?component.placeholder},
        onInput: component.onChanged,
        events: {
          'keydown': (event) {
            final keyboard = event as web.KeyboardEvent;
            if (keyboard.key == 'Enter' && !keyboard.shiftKey) {
              event.preventDefault();
              component.onSubmitted?.call();
            }
          },
        },
      ),
    ]);
  }
}
