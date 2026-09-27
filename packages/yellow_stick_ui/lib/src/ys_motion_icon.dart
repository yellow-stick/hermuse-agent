import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

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
    final shapes = _Shape.of(icon);
    // Idle (null frame): body only, no transforms, extras hidden.
    final frame = motion != null && controller.isAnimating
        ? controller.value * motion.frames
        : null;
    canvas.scale(size.width / 24, size.height / 24);
    final root = frame == null ? null : motion!.root;
    if (root != null) _transform(canvas, root, frame!);
    final bodyCount = motion?.bodyCount ?? shapes.length;
    for (var i = 0; i < shapes.length; i++) {
      if (frame == null && i >= bodyCount) break;
      final part = frame == null ? null : motion!.part(i);
      var opacity = part?.valueAt(YsMotionProperty.opacity, frame!) ?? 1;
      opacity *= root?.valueAt(YsMotionProperty.opacity, frame!) ?? 1;
      if (opacity <= 0) continue;
      canvas.save();
      if (part != null) _transform(canvas, part, frame!);
      final shape = shapes[i];
      var path = shape.path;
      if (part?.track(YsMotionProperty.trimEnd) != null) {
        path = _trim(
          path,
          part!.valueAt(YsMotionProperty.trimStart, frame!),
          part.valueAt(YsMotionProperty.trimEnd, frame),
        );
      }
      final paint = Paint()
        ..color = color.withValues(alpha: color.a * opacity.clamp(0, 1))
        ..isAntiAlias = true;
      if (shape.fill) {
        canvas.drawPath(path, paint..style = PaintingStyle.fill);
      } else {
        canvas.drawPath(
          path,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.restore();
    }
  }

  /// CSS individual-transform order around the part origin: translate,
  /// rotate, scale.
  static void _transform(Canvas canvas, YsPartMotion part, double frame) {
    final scale = part.valueAt(YsMotionProperty.scale, frame);
    canvas
      ..translate(part.originX, part.originY)
      ..translate(0, part.valueAt(YsMotionProperty.translateY, frame))
      ..rotate(part.valueAt(YsMotionProperty.rotate, frame) * math.pi / 180)
      ..scale(scale * part.valueAt(YsMotionProperty.scaleX, frame), scale)
      ..translate(-part.originX, -part.originY);
  }

  /// The [start]..[end] fraction of [path]'s length.
  static Path _trim(Path path, double start, double end) {
    final out = Path();
    if (end <= start) return out;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
    var offset = 0.0;
    for (final m in metrics) {
      final from = (start * total - offset).clamp(0.0, m.length);
      final to = (end * total - offset).clamp(0.0, m.length);
      if (to > from) out.addPath(m.extractPath(from, to), Offset.zero);
      offset += m.length;
    }
    return out;
  }

  @override
  bool shouldRepaint(_MotionPainter old) =>
      old.icon != icon ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.controller != controller;
}

/// One parsed element of an icon (24-unit viewBox).
final class _Shape {
  const _Shape(this.path, {required this.fill});

  final Path path;

  /// Filled (`fill="currentColor"`) rather than stroked.
  final bool fill;

  static final _cache = <YsIcon, List<_Shape>>{};
  static final _tag = RegExp(r'^<(\w+)');
  static final _attribute = RegExp(r'([\w-]+)="([^"]*)"');

  /// Body elements, then motion extras.
  static List<_Shape> of(YsIcon icon) => _cache.putIfAbsent(
    icon,
    () => [
      for (final markup
          in YsIconMotion.of(icon)?.elements ?? ysSvgElements(icon.body))
        _parse(markup),
    ],
  );

  static _Shape _parse(String markup) {
    final tag = _tag.firstMatch(markup)!.group(1)!;
    final a = {
      for (final m in _attribute.allMatches(markup)) m.group(1)!: m.group(2)!,
    };
    double n(String key) => double.tryParse(a[key] ?? '') ?? 0;
    final path = Path();
    switch (tag) {
      case 'path':
        writeSvgPathDataToPath(a['d'], _PathProxy(path));
      case 'rect':
        final rx = n('rx');
        path.addRRect(
          RRect.fromRectXY(
            Rect.fromLTWH(n('x'), n('y'), n('width'), n('height')),
            rx,
            rx,
          ),
        );
      case 'circle':
        path.addOval(
          Rect.fromCircle(center: Offset(n('cx'), n('cy')), radius: n('r')),
        );
    }
    return _Shape(path, fill: a['fill'] == 'currentColor');
  }
}

final class _PathProxy extends PathProxy {
  _PathProxy(this.path);

  final ui.Path path;

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}
