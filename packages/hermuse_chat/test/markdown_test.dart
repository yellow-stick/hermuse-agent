import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:test/test.dart';

void main() {
  test('tight bullet list keeps one item per line', () {
    final blocks = parseMarkdown(
      '- Host: Linux vmi3607390\n- Date: Sun Sep 27 13:18 CEST 2026',
    );
    final list = blocks.single as MdList;
    expect(list.ordered, isFalse);
    expect(
      [
        for (final item in list.items)
          (item.single as MdParagraph).spans.map((s) => s.text).join(),
      ],
      ['Host: Linux vmi3607390', 'Date: Sun Sep 27 13:18 CEST 2026'],
    );
  });

  test('inline styles, safe links only, and literal HTML', () {
    final spans =
        (parseMarkdown(
                  'A **bold** `code` [ok](https://x.dev) '
                  '[bad](javascript:alert(1)) <b>raw</b> &amp;',
                ).single
                as MdParagraph)
            .spans;
    expect(spans.firstWhere((s) => s.text == 'bold').bold, isTrue);
    expect(spans.firstWhere((s) => s.text == 'code').code, isTrue);
    expect(spans.firstWhere((s) => s.text == 'ok').href, 'https://x.dev');
    expect(spans.firstWhere((s) => s.text == 'bad').href, isNull);
    final plain = spans.map((s) => s.text).join();
    expect(plain, contains('<b>raw</b>'));
    // Entities decode to their character (Markdown semantics), as text.
    expect(plain, endsWith('<b>raw</b> &'));
  });

  test('fenced code, numbered list start, heading, paragraphs', () {
    final blocks = parseMarkdown(
      '# Title\n\nFirst para.\n\nSecond para.\n\n3. three\n4. four\n\n'
      '```dart\nvoid main() {}\n```',
    );
    expect(blocks, hasLength(5));
    expect((blocks[0] as MdHeading).level, 1);
    expect((blocks[3] as MdList).start, 3);
    final code = blocks[4] as MdCodeBlock;
    expect((code.code, code.language), ('void main() {}', 'dart'));
  });
}
