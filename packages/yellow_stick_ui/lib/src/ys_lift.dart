import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// A card rising under the pointer: while [lifted] it moves up
/// [YsLiftMotion.lift] px and casts a soft shadow rounded by [radius];
/// while [pressed] it settles back to [YsLiftMotion.press] scale.
///
/// With animations disabled it changes at once. The tree shape never
/// changes, so the card keeps its state.
final class YsLift extends StatelessWidget {
  const YsLift({
    required this.lifted,
    required this.radius,
    required this.child,
    this.pressed = false,
    super.key,
  });

  final bool lifted;
  final bool pressed;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final duration = still
        ? Duration.zero
        : const Duration(milliseconds: YsLiftMotion.duration);
    final shadow = palette.shadowColor;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: lifted && !pressed ? 1 : 0),
      duration: duration,
      curve: YsEase.standard.curve,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, -YsLiftMotion.lift * t),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: shadow.withValues(alpha: shadow.a * t),
                blurRadius: YsLiftMotion.shadowBlur,
                offset: Offset(0, YsLiftMotion.shadowY * t),
              ),
            ],
          ),
          child: child,
        ),
      ),
      child: AnimatedScale(
        scale: pressed ? YsLiftMotion.press : 1,
        duration: duration,
        curve: YsEase.standard.curve,
        child: child,
      ),
    );
  }
}
