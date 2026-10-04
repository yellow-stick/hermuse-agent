import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// Liquid glass surface for floating controls (Chats pill, agent switcher):
/// the backdrop blurred and saturated ([YsGlassMaterial]), tinted with the
/// palette `glass`, a sheen washing down from the top and a specular rim
/// bright at the top-left corner. Rests on the raised elevation.
/// [highlighted] (hover, press) lays the neutral wash over the tint.
///
/// Web kit: class `ys-glass`.
final class YsGlass extends StatelessWidget {
  const YsGlass({
    required this.child,
    this.radius = YsRadius.pill,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final double radius;
  final bool highlighted;

  static final _filter = ImageFilter.compose(
    outer: const ColorFilter.matrix(_saturate),
    inner: ImageFilter.blur(
      sigmaX: YsGlassMaterial.blur,
      sigmaY: YsGlassMaterial.blur,
    ),
  );

  /// CSS `saturate(YsGlassMaterial.saturation)` as a colour matrix.
  static const _saturate = <double>[
    0.213 + 0.787 * YsGlassMaterial.saturation,
    0.715 - 0.715 * YsGlassMaterial.saturation,
    0.072 - 0.072 * YsGlassMaterial.saturation,
    0,
    0,
    0.213 - 0.213 * YsGlassMaterial.saturation,
    0.715 + 0.285 * YsGlassMaterial.saturation,
    0.072 - 0.072 * YsGlassMaterial.saturation,
    0,
    0,
    0.213 - 0.213 * YsGlassMaterial.saturation,
    0.715 - 0.715 * YsGlassMaterial.saturation,
    0.072 + 0.928 * YsGlassMaterial.saturation,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final borderRadius = BorderRadius.circular(radius);
    // The resting elevation sits outside the blur clip, which would cut it.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: palette.raisedShadows,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: _filter,
          child: CustomPaint(
            foregroundPainter: _GlassRim(
              radius: radius,
              rim: palette.glassRimColor,
              shine: palette.glassShineColor,
            ),
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: YsMotion.fast),
              color: highlighted
                  ? Color.alphaBlend(
                      palette.neutralWashColor,
                      palette.glassColor,
                    )
                  : palette.glassColor,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      palette.glassShineColor,
                      palette.glassShineColor.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.55],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline rim: [rim] at the top-left, fading to [shine] at the
/// bottom-right (web `.ys-glass::before`).
final class _GlassRim extends CustomPainter {
  const _GlassRim({
    required this.radius,
    required this.rim,
    required this.shine,
  });

  final double radius;
  final Color rim;
  final Color shine;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [rim, shine, shine],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    final inner = rect.deflate(0.5);
    final r = radius.clamp(0, inner.shortestSide / 2).toDouble();
    canvas.drawRRect(RRect.fromRectAndRadius(inner, Radius.circular(r)), paint);
  }

  @override
  bool shouldRepaint(_GlassRim old) =>
      old.radius != radius || old.rim != rim || old.shine != shine;
}
