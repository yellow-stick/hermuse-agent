import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// One parsed element of a glyph on the 24-unit viewBox, as the kit's
/// painters draw it (the same geometry [YsIconWidget] renders through SVG).
final class YsSvgShape {
  const YsSvgShape._(this.path, {required this.fill, required this.stroke});

  final Path path;

  /// Filled (`fill="currentColor"`).
  final bool fill;

  /// Stroked: every element but `stroke="none"` ones.
  final bool stroke;

  static final _cache = <String, List<YsSvgShape>>{};
  static final _tag = RegExp(r'^<(\w+)');
  static final _attribute = RegExp(r'([\w-]+)="([^"]*)"');

  /// The elements of [markup] (see [ysSvgElements]), parsed once.
  static List<YsSvgShape> of(String markup) => _cache.putIfAbsent(
    markup,
    () => [for (final element in ysSvgElements(markup)) _parse(element)],
  );

  static YsSvgShape _parse(String markup) {
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
    return YsSvgShape._(
      path,
      fill: a['fill'] == 'currentColor',
      stroke: a['stroke'] != 'none',
    );
  }

  /// Paints [path] (this shape's, possibly trimmed) in [color]: its fill,
  /// then its round-capped stroke of [strokeWidth] viewBox units.
  void paint(Canvas canvas, Path path, Color color, double strokeWidth) {
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (fill) canvas.drawPath(path, paint..style = PaintingStyle.fill);
    if (stroke) {
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }
}

/// The [start]..[end] fraction of [path]'s length.
Path ysTrimPath(Path path, double start, double end) {
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

/// Applies [part]'s transforms at [frame] around its origin, in CSS
/// individual-transform order: translate, rotate, scale.
void ysTransformPart(Canvas canvas, YsPartMotion part, double frame) {
  final scale = part.valueAt(YsMotionProperty.scale, frame);
  canvas
    ..translate(part.originX, part.originY)
    ..translate(0, part.valueAt(YsMotionProperty.translateY, frame))
    ..rotate(part.valueAt(YsMotionProperty.rotate, frame) * math.pi / 180)
    ..scale(scale * part.valueAt(YsMotionProperty.scaleX, frame), scale)
    ..translate(-part.originX, -part.originY);
}

/// [path] trimmed to [part]'s visible range at [frame] when it animates
/// one; [path] itself otherwise.
Path ysPartPath(Path path, YsPartMotion? part, double frame) {
  if (part == null ||
      (part.track(YsMotionProperty.trimStart) == null &&
          part.track(YsMotionProperty.trimEnd) == null)) {
    return path;
  }
  return ysTrimPath(
    path,
    part.valueAt(YsMotionProperty.trimStart, frame),
    part.valueAt(YsMotionProperty.trimEnd, frame),
  );
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
