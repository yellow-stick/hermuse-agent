import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Renders an agent reply's Markdown with Jaspr elements only (the parsed
/// tree carries no HTML, so nothing is injected).
class HermuseMarkdown extends StatelessComponent {
  const HermuseMarkdown(this.source, {super.key});

  final String source;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-md', [
    for (final b in parseMarkdown(source)) _block(b),
  ]);

  static Component _block(MdBlock block) => switch (block) {
    MdParagraph(:final spans) => p([for (final s in spans) _span(s)]),
    MdHeading(:final level, :final spans) => div(
      classes: 'hermuse-md-h hermuse-md-h$level',
      [for (final s in spans) _span(s)],
    ),
    MdList(:final ordered, :final start, :final items) =>
      ordered
          ? ol(
              attributes: {if (start != 1) 'start': '$start'},
              [
                for (final item in items) li([for (final b in item) _block(b)]),
              ],
            )
          : ul([
              for (final item in items) li([for (final b in item) _block(b)]),
            ]),
    MdCodeBlock(:final code) => pre([
      Component.element(tag: 'code', children: [.text(code)]),
    ]),
    MdQuote(:final blocks) => blockquote([for (final b in blocks) _block(b)]),
    MdRule() => hr(),
  };

  static Component _span(MdSpan s) {
    Component node = .text(s.text);
    if (s.code) {
      node = Component.element(tag: 'code', children: [node]);
    }
    if (s.bold) node = strong([node]);
    if (s.italic) node = em([node]);
    if (s.strike) node = Component.element(tag: 'del', children: [node]);
    if (s.href case final href?) {
      node = a(
        href: href,
        target: Target.blank,
        attributes: {'rel': 'noopener noreferrer'},
        [node],
      );
    }
    return node;
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-md', [
      css('&').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(8.px),
        raw: {'overflow-wrap': 'break-word'},
      ),
      css('p, ul, ol, pre, blockquote, hr').styles(margin: .zero),
      css('ul, ol').styles(
        padding: .only(left: 22.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(4.px),
      ),
      css('li > ul, li > ol').styles(margin: .only(top: 4.px)),
      css('li').styles(raw: {'padding-left': '2px'}),
      css('.hermuse-md-h').styles(fontWeight: .w600, lineHeight: 24.px),
      css('.hermuse-md-h1, .hermuse-md-h2').styles(fontSize: 17.px),
      css('.hermuse-md-h3, .hermuse-md-h4, .hermuse-md-h5, .hermuse-md-h6')
          .styles(fontSize: 15.px),
      css('code').styles(
        padding: .symmetric(horizontal: 5.px, vertical: 1.px),
        radius: .circular(5.px),
        backgroundColor: .variable('--neutral-ambient'),
        fontSize: 13.px,
        raw: {
          'font-family':
              'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
        },
      ),
      css('pre').styles(
        padding: .all(12.px),
        radius: .circular(YsRadius.row.px),
        backgroundColor: .variable('--canvas'),
        overflow: .only(x: .auto),
        fontSize: 13.px,
        lineHeight: 20.px,
      ),
      css('pre code').styles(
        padding: .zero,
        backgroundColor: Colors.transparent,
        raw: {'white-space': 'pre'},
      ),
      css('blockquote').styles(
        padding: .only(left: 12.px),
        color: .variable('--content-muted'),
        raw: {'border-left': '2px solid var(--line)'},
      ),
      css('hr').styles(
        border: .none,
        height: 1.px,
        backgroundColor: .variable('--line'),
      ),
      css('a').styles(
        color: .variable('--primary-2'),
        raw: {'text-decoration': 'underline', 'text-underline-offset': '2px'},
      ),
    ]),
  ];
}
