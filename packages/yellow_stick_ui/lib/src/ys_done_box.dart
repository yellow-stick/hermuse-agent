import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_burst.dart';
import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// A "mark done" box: empty, with a faint tick while [hovered]. When [done]
/// turns on it fills with the success colour while the tick of
/// [YsStepMark.tick] draws in it and [YsBurst] sparks fly out. A box built
/// done shows done at once, as does every change with animations disabled.
final class YsDoneBox extends StatefulWidget {
  const YsDoneBox({
    required this.done,
    this.hovered = false,
    this.size = 22,
    super.key,
  });

  final bool done;
  final bool hovered;
  final double size;

  @override
  State<YsDoneBox> createState() => _YsDoneBoxState();
}

final class _YsDoneBoxState extends State<YsDoneBox>
    with SingleTickerProviderStateMixin {
  late final _tick = AnimationController(
    vsync: this,
    value: widget.done ? 1 : 0,
    duration: Duration(milliseconds: YsStepMark.tick.durationMs),
  );

  @override
  void didUpdateWidget(YsDoneBox old) {
    super.didUpdateWidget(old);
    if (old.done == widget.done) return;
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (widget.done && !still) {
      _tick.forward(from: 0);
    } else {
      _tick.value = widget.done ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsBurstView(
      play: widget.done && _tick.isAnimating,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _BoxPainter(
          tick: _tick,
          done: widget.done,
          hovered: widget.hovered,
          border: palette.contentMutedColor,
          hover: palette.neutralFilmColor,
          hint: palette.contentSubtleColor,
          fill: palette.successColor,
          mark: palette.canvasColor,
        ),
      ),
    );
  }
}

final class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.tick,
    required this.done,
    required this.hovered,
    required this.border,
    required this.hover,
    required this.hint,
    required this.fill,
    required this.mark,
  }) : super(repaint: tick);

  final AnimationController tick;
  final bool done;
  final bool hovered;
  final Color border;
  final Color hover;
  final Color hint;
  final Color fill;
  final Color mark;

  /// Corner radius and tick inset of the box.
  static const _radius = 6.0;
  static const _inset = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const glyph = YsStepMark.tick;
    final box = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(_radius),
    );
    final frame = done ? tick.value * glyph.frames : 0.0;
    // The box fills as the tick's ring would close.
    final filled = done
        ? glyph.ring!.valueAt(YsMotionProperty.trimEnd, frame)
        : 0.0;
    if (hovered && !done) canvas.drawRRect(box, Paint()..color = hover);
    if (filled > 0) {
      canvas.drawRRect(
        box,
        Paint()..color = fill.withValues(alpha: fill.a * filled),
      );
    }
    canvas.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Color.lerp(border, fill, filled)!,
    );
    if (!done && !hovered) return;
    final shape = YsSvgShape.of(glyph.body).single;
    final part = done ? glyph.part(0) : null;
    final opacity = part?.valueAt(YsMotionProperty.opacity, frame) ?? 1;
    if (opacity <= 0) return;
    canvas
      ..save()
      ..translate(_inset, _inset)
      ..scale((size.width - _inset * 2) / 24);
    shape.paint(
      canvas,
      part == null ? shape.path : ysPartPath(shape.path, part, frame),
      done ? mark : hint,
      YsLayout.stepGlyphStroke + 0.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoxPainter old) =>
      old.tick != tick ||
      old.done != done ||
      old.hovered != hovered ||
      old.border != border ||
      old.hover != hover ||
      old.hint != hint ||
      old.fill != fill ||
      old.mark != mark;
}
