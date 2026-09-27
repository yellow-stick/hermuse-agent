import 'package:markdown/markdown.dart' as md;

/// Agent replies are Markdown. This is a renderer-neutral tree of it (no
/// HTML anywhere, so nothing can inject markup) that the Flutter and Jaspr
/// apps turn into their own widgets.
sealed class MdBlock {
  const MdBlock();
}

final class MdParagraph extends MdBlock {
  const MdParagraph(this.spans);
  final List<MdSpan> spans;
}

final class MdHeading extends MdBlock {
  const MdHeading(this.level, this.spans);

  /// 1–6.
  final int level;
  final List<MdSpan> spans;
}

final class MdList extends MdBlock {
  const MdList({required this.ordered, required this.items, this.start = 1});
  final bool ordered;

  /// Number of the first item of an ordered list.
  final int start;

  /// Each item is a list of blocks (paragraphs, nested lists…).
  final List<List<MdBlock>> items;
}

final class MdCodeBlock extends MdBlock {
  const MdCodeBlock(this.code, {this.language = ''});
  final String code;
  final String language;
}

final class MdQuote extends MdBlock {
  const MdQuote(this.blocks);
  final List<MdBlock> blocks;
}

final class MdRule extends MdBlock {
  const MdRule();
}

/// A run of inline text with its styles.
final class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;

  /// Link target (http/https/mailto only; others render as plain text).
  final String? href;

  MdSpan _with({
    bool? bold,
    bool? italic,
    bool? code,
    bool? strike,
    String? href,
  }) => MdSpan(
    text,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    code: code ?? this.code,
    strike: strike ?? this.strike,
    href: href ?? this.href,
  );
}

/// Parses GitHub-flavoured Markdown; inline HTML stays literal text.
List<MdBlock> parseMarkdown(String source) {
  final document = md.Document(
    extensionSet: md.ExtensionSet(
      md.ExtensionSet.gitHubFlavored.blockSyntaxes,
      [
        for (final syntax in md.ExtensionSet.gitHubFlavored.inlineSyntaxes)
          if (syntax is! md.InlineHtmlSyntax) syntax,
      ],
    ),
    encodeHtml: false,
  );
  final nodes = document.parse(source.replaceAll('\r\n', '\n'));
  return _blocks(nodes);
}

List<MdBlock> _blocks(List<md.Node> nodes) {
  final out = <MdBlock>[];
  final loose = <md.Node>[];
  void flushLoose() {
    final spans = _spans(loose, const MdSpan(''));
    if (spans.any((s) => s.text.trim().isNotEmpty)) out.add(MdParagraph(spans));
    loose.clear();
  }

  for (final node in nodes) {
    if (node is md.Element && _isBlock(node.tag)) {
      flushLoose();
      final block = _block(node);
      if (block != null) out.add(block);
    } else {
      // Tight list items hold inline nodes directly.
      loose.add(node);
    }
  }
  flushLoose();
  return out;
}

const _blockTags = {
  'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'pre', //
  'blockquote', 'hr', 'table', 'div',
};

bool _isBlock(String tag) => _blockTags.contains(tag);

MdBlock? _block(md.Element e) {
  final children = e.children ?? const <md.Node>[];
  switch (e.tag) {
    case 'p':
      return MdParagraph(_spans(children, const MdSpan('')));
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      return MdHeading(
        int.parse(e.tag.substring(1)),
        _spans(children, const MdSpan('')),
      );
    case 'ul' || 'ol':
      return MdList(
        ordered: e.tag == 'ol',
        start: int.tryParse(e.attributes['start'] ?? '') ?? 1,
        items: [
          for (final item in children)
            if (item is md.Element && item.tag == 'li')
              _blocks(item.children ?? const []),
        ],
      );
    case 'pre':
      final code = children.whereType<md.Element>().firstOrNull;
      final language = (code?.attributes['class'] ?? '').replaceFirst(
        'language-',
        '',
      );
      var text = (code ?? e).textContent;
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
      return MdCodeBlock(text, language: language);
    case 'blockquote':
      return MdQuote(_blocks(children));
    case 'hr':
      return const MdRule();
    case 'table':
      // Tables degrade to one paragraph per row, cells separated by " · ".
      return MdQuote([
        for (final row in _descendants(e, 'tr'))
          MdParagraph([
            MdSpan(
              [
                for (final cell in (row.children ?? const <md.Node>[]))
                  cell.textContent.trim(),
              ].join(' · '),
            ),
          ]),
      ]);
    default:
      final blocks = _blocks(children);
      return blocks.isEmpty ? null : MdQuote(blocks);
  }
}

Iterable<md.Element> _descendants(md.Element e, String tag) sync* {
  for (final child in e.children ?? const <md.Node>[]) {
    if (child is! md.Element) continue;
    if (child.tag == tag) {
      yield child;
    } else {
      yield* _descendants(child, tag);
    }
  }
}

List<MdSpan> _spans(List<md.Node> nodes, MdSpan style) {
  final out = <MdSpan>[];
  for (final node in nodes) {
    if (node is md.Text) {
      out.add(style._with()._text(node.text));
    } else if (node is md.Element) {
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'strong':
          out.addAll(_spans(children, style._with(bold: true)));
        case 'em':
          out.addAll(_spans(children, style._with(italic: true)));
        case 'del':
          out.addAll(_spans(children, style._with(strike: true)));
        case 'code':
          out.add(style._with(code: true)._text(node.textContent));
        case 'br':
          out.add(style._text('\n'));
        case 'a':
          final href = node.attributes['href'] ?? '';
          final safe = RegExp(
            r'^(https?:|mailto:)',
            caseSensitive: false,
          ).hasMatch(href);
          out.addAll(_spans(children, safe ? style._with(href: href) : style));
        case 'img':
          out.add(style._text(node.attributes['alt'] ?? ''));
        default:
          out.addAll(_spans(children, style));
      }
    }
  }
  return out;
}

extension on MdSpan {
  MdSpan _text(String text) => MdSpan(
    text,
    bold: bold,
    italic: italic,
    code: code,
    strike: strike,
    href: href,
  );
}
