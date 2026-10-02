import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// A small ring filled to [value] (0..1), easing to each new value, with
/// [label] in its middle (`3/7`).
///
/// [complete] is the "ready" moment: the ring fills and turns to the
/// success colour, the label gives way to a tick drawn stroke by stroke
/// with a soft pop, the moment holds [YsStepMotion.readyHold] ms, then
/// [onCompleted] fires once. With animations disabled it shows the final
/// look at once and fires on the next frame.
final class YsProgressRing extends StatefulWidget {
  const YsProgressRing({
    required this.value,
    this.label,
    this.complete = false,
    this.onCompleted,
    this.size = YsLayout.progressRing,
    super.key,
  });

  final double value;
  final String? label;
  final bool complete;
  final VoidCallback? onCompleted;
  final double size;

  @override
  State<YsProgressRing> createState() => _YsProgressRingState();
}

final class _YsProgressRingState extends State<YsProgressRing>
    with TickerProviderStateMixin {
  late final _value = AnimationController(vsync: this);

  /// The ready moment: the tick and the pop, then the hold.
  late final _ready = AnimationController(vsync: this);

  bool _started = false;
  bool _still = false;
  bool _fired = false;

  /// The moment in milliseconds: tick and pop, then the hold.
  static int get _readyMs =>
      (YsStepMotion.readyFrames * 1000 / 60).round() + YsStepMotion.readyHold;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (!_started) {
      _started = true;
      _syncValue();
      if (widget.complete) _complete();
    }
  }

  @override
  void didUpdateWidget(YsProgressRing old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value || old.complete != widget.complete) {
      _syncValue();
    }
    if (widget.complete && !old.complete) _complete();
    if (!widget.complete && old.complete) {
      _ready.value = 0;
      _fired = false;
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _ready.dispose();
    super.dispose();
  }

  void _syncValue() {
    final target = widget.complete ? 1.0 : widget.value.clamp(0.0, 1.0);
    if (_still) {
      _value.value = target;
      return;
    }
    _value.animateTo(
      target,
      duration: const Duration(milliseconds: YsStepMotion.progress),
      curve: YsEase.standard.curve,
    );
  }

  void _complete() {
    if (_still) {
      _ready.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fire());
      return;
    }
    _ready
      ..duration = Duration(milliseconds: _readyMs)
      ..forward(from: 0).whenCompleteOrCancel(_fire);
  }

  void _fire() {
    if (!mounted || !widget.complete || _fired) return;
    _fired = true;
    widget.onCompleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final label = widget.label;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  value: _value,
                  ready: _ready,
                  readyFrames: _readyMs * 60 / 1000,
                  palette: palette,
                ),
              ),
            ),
            if (label != null)
              AnimatedBuilder(
                animation: _ready,
                // The label gives way to the tick as the moment starts.
                builder: (context, child) => Opacity(
                  opacity: widget.complete
                      ? (1 - _ready.value * _readyMs / YsStepMotion.swap).clamp(
                          0.0,
                          1.0,
                        )
                      : 1,
                  child: child,
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  style: YsType.caption.flutter.copyWith(
                    color: palette.contentMutedColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.ready,
    required this.readyFrames,
    required this.palette,
  }) : super(repaint: Listenable.merge([value, ready]));

  final Animation<double> value;
  final Animation<double> ready;

  /// Frames [ready] spans, hold included.
  final double readyFrames;
  final YsPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = ready.value * readyFrames;
    final done = ready.value > 0;
    if (done) {
      final pop = YsStepMotion.readyPop.valueAt(YsMotionProperty.scale, frame);
      final centre = size.center(Offset.zero);
      canvas
        ..translate(centre.dx, centre.dy)
        ..scale(pop)
        ..translate(-centre.dx, -centre.dy);
    }
    final rect = (Offset.zero & size).deflate(YsLayout.progressRingStroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = YsLayout.progressRingStroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawOval(rect, paint..color = palette.neutralFilmColor);
    final sweep = value.value;
    if (sweep > 0) {
      final turn = done
          ? (frame / YsStepMotion.readyTurn).clamp(0.0, 1.0)
          : 0.0;
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.max(sweep, 0.02) * 2 * math.pi,
        false,
        paint
          ..color = Color.lerp(
            palette.primaryInkColor,
            palette.successColor,
            turn,
          )!,
      );
    }
    if (!done) return;
    // The tick of a step badge, at the same share of the ring.
    final glyph = size.shortestSide * YsLayout.stepGlyph / YsLayout.stepBadge;
    canvas
      ..translate((size.width - glyph) / 2, (size.height - glyph) / 2)
      ..scale(glyph / 24);
    const mark = YsStepMark.tick;
    final shape = YsSvgShape.of(mark.body).single;
    final part = mark.part(0);
    final opacity = part?.valueAt(YsMotionProperty.opacity, frame) ?? 1;
    if (opacity <= 0) return;
    shape.paint(
      canvas,
      ysPartPath(shape.path, part, frame),
      palette.successColor.withValues(alpha: opacity.clamp(0.0, 1.0)),
      YsLayout.stepGlyphStroke,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value ||
      old.ready != ready ||
      old.readyFrames != readyFrames ||
      old.palette != palette;
}
