import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/open_url.dart';

/// Renders an agent reply's Markdown (web `markdown_view.dart` parity:
/// 8 gaps, 22 list indent, canvas code blocks, primary-2 links).
final class MarkdownView extends StatefulWidget {
  const MarkdownView(this.source, {super.key});

  final String source;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

final class _MarkdownViewState extends State<MarkdownView> {
  late List<MdBlock> _blocks = parseMarkdown(widget.source);
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _blocks = parseMarkdown(widget.source);
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final palette = YsTheme.of(context);
    final base = YsType.agentBubble.flutter.copyWith(
      color: palette.contentColor,
    );
    return _column([for (final b in _blocks) _block(b, base, palette)]);
  }

  Widget _column(List<Widget> children, {double gap = 8}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        children[i],
      ],
    ],
  );

  Widget _block(
    MdBlock block,
    TextStyle base,
    YsPalette palette,
  ) => switch (block) {
    MdParagraph(:final spans) => _rich(spans, base, palette),
    MdHeading(:final level, :final spans) => _rich(
      spans,
      base.copyWith(
        fontSize: level <= 2 ? 17 : 15,
        height: 24 / (level <= 2 ? 17 : 15),
        fontWeight: FontWeight.w600,
      ),
      palette,
    ),
    MdList(:final ordered, :final start, :final items) => _column(gap: 4, [
      for (final (i, item) in items.indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(ordered ? '${start + i}.' : '•', style: base),
            ),
            Flexible(
              child: _column(gap: 4, [
                for (final b in item) _block(b, base, palette),
              ]),
            ),
          ],
        ),
    ]),
    MdCodeBlock(:final code) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.canvasColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(code, style: _mono(base, 13, 20)),
      ),
    ),
    MdQuote(:final blocks) => Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.lineColor, width: 2)),
      ),
      child: _column([
        for (final b in blocks)
          _block(b, base.copyWith(color: palette.contentMutedColor), palette),
      ]),
    ),
    MdRule() => Container(height: 1, color: palette.lineColor),
  };

  /// A fresh style, not `base.copyWith`: [base] carries the kit's font
  /// package, which would resolve `monospace` as a missing package font.
  TextStyle _mono(TextStyle base, double size, double line) => TextStyle(
    color: base.color,
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier'],
    fontSize: size,
    height: line / size,
    leadingDistribution: TextLeadingDistribution.even,
  );

  Widget _rich(List<MdSpan> spans, TextStyle base, YsPalette palette) =>
      Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final s in spans)
              TextSpan(
                text: s.text,
                style: TextStyle(
                  fontWeight: s.bold ? FontWeight.w600 : null,
                  fontStyle: s.italic ? FontStyle.italic : null,
                  decoration: s.strike
                      ? TextDecoration.lineThrough
                      : s.href != null
                      ? TextDecoration.underline
                      : null,
                  color: s.href != null ? palette.primaryInkColor : null,
                  backgroundColor: s.code ? palette.neutralAmbientColor : null,
                  fontFamily: s.code ? 'monospace' : null,
                  fontSize: s.code ? 13 : null,
                ),
                recognizer: s.href == null ? null : _tap(s.href!),
              ),
          ],
        ),
      );

  TapGestureRecognizer _tap(String href) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => unawaited(openExternalUrl(href));
    _recognizers.add(recognizer);
    return recognizer;
  }
}
