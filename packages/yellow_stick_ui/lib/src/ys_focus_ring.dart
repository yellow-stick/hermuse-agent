import 'package:flutter/widgets.dart';

import 'ys_theme.dart';

/// Keyboard focus outline around [child], the web kit's `:focus-visible`
/// rule: a 2 px `primary` outline hugging the shape, drawn outside the box so
/// nothing moves. [radius] rounds it like the child (a pill radius makes a
/// circle of a square child).
final class YsFocusRing extends StatelessWidget {
  const YsFocusRing({
    required this.visible,
    required this.radius,
    required this.child,
    super.key,
  });

  final bool visible;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: visible
        ? _RingPainter(YsTheme.of(context).primaryColor, radius)
        : null,
    child: child,
  );
}

final class _RingPainter extends CustomPainter {
  const _RingPainter(this.color, this.radius);

  final Color color;
  final double radius;

  /// Outline width of the web kit's focus rule.
  static const _width = 2.0;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    RRect.fromRectAndRadius(
      (Offset.zero & size).inflate(_width / 2),
      Radius.circular(radius + _width / 2),
    ),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..color = color,
  );

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
