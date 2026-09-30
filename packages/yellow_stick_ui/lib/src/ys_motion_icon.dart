import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// Renders a core [YsIcon] and plays its [YsIconMotion] once each time
/// [hovered] turns on (rail destinations). Icons without a motion render
/// still.
///
/// The playthrough always completes, even if the pointer leaves early. The
/// glyph is painted from the same SVG geometry as
/// [YsIconWidget], so the idle icon matches it.
final class YsMotionIcon extends StatefulWidget {
  const YsMotionIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.75,
    this.hovered = false,
  });

  final YsIcon icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  /// Pointer over the host control; a rising edge starts the animation.
  final bool hovered;

  @override
  State<YsMotionIcon> createState() => _YsMotionIconState();
}

final class _YsMotionIconState extends State<YsMotionIcon>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);

  @override
  void didUpdateWidget(YsMotionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final motion = YsIconMotion.of(widget.icon);
    if (!oldWidget.hovered &&
        widget.hovered &&
        motion != null &&
        !_controller.isAnimating &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..duration = Duration(milliseconds: motion.durationMs)
        ..forward(from: 0).whenCompleteOrCancel(() {
          if (mounted) _controller.value = 0;
        });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _MotionPainter(
        icon: widget.icon,
        controller: _controller,
        color: widget.color ?? YsTheme.of(context).contentColor,
        strokeWidth: widget.strokeWidth,
      ),
    ),
  );
}

final class _MotionPainter extends CustomPainter {
  _MotionPainter({
    required this.icon,
    required this.controller,
    required this.color,
    required this.strokeWidth,
  }) : super(repaint: controller);

  final YsIcon icon;
  final AnimationController controller;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final motion = YsIconMotion.of(icon);
    final shapes = YsSvgShape.of(icon.body + (motion?.extras ?? ''));
    // Idle (null frame): body only, no transforms, extras hidden.
    final frame = motion != null && controller.isAnimating
        ? controller.value * motion.frames
        : null;
    canvas.scale(size.width / 24, size.height / 24);
    final root = frame == null ? null : motion!.root;
    if (root != null) ysTransformPart(canvas, root, frame!);
    final bodyCount = motion?.bodyCount ?? shapes.length;
    for (var i = 0; i < shapes.length; i++) {
      if (frame == null && i >= bodyCount) break;
      final part = frame == null ? null : motion!.part(i);
      var opacity = part?.valueAt(YsMotionProperty.opacity, frame!) ?? 1;
      opacity *= root?.valueAt(YsMotionProperty.opacity, frame!) ?? 1;
      if (opacity <= 0) continue;
      canvas.save();
      if (part != null) ysTransformPart(canvas, part, frame!);
      final shape = shapes[i];
      shape.paint(
        canvas,
        frame == null ? shape.path : ysPartPath(shape.path, part, frame),
        color.withValues(alpha: color.a * opacity.clamp(0, 1)),
        strokeWidth,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MotionPainter old) =>
      old.icon != icon ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.controller != controller;
}
