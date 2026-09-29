import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// Loading placeholder: [child] lays out [YsSkeletonBox]es where the
/// content will be, and a highlight band sweeps across them every
/// [YsShimmerMotion.period] ms while it is on screen.
///
/// With animations disabled the boxes stay still.
final class YsSkeleton extends StatefulWidget {
  const YsSkeleton({required this.child, this.semanticLabel, super.key});

  final Widget child;

  /// Announced instead of the boxes ("Loading feed").
  final String? semanticLabel;

  @override
  State<YsSkeleton> createState() => _YsSkeletonState();
}

final class _YsSkeletonState extends State<YsSkeleton>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: YsShimmerMotion.period),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (still) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final base = palette.neutralAmbientColor;
    final light = palette.neutralFilmColor;
    return Semantics(
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _sweep,
          builder: (context, child) {
            // The band enters from the left edge and leaves past the right.
            const band = YsShimmerMotion.band;
            final at = -band + _sweep.value * (1 + 2 * band);
            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                colors: [base, light, base],
                stops: [
                  (at - band / 2).clamp(0.0, 1.0),
                  at.clamp(0.0, 1.0),
                  (at + band / 2).clamp(0.0, 1.0),
                ],
              ).createShader(bounds),
              child: child,
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// One placeholder block of a [YsSkeleton]: [height] high, [width] wide
/// (the available width when null), rounded by [radius].
final class YsSkeletonBox extends StatelessWidget {
  const YsSkeletonBox({
    required this.height,
    this.width,
    this.radius = YsRadius.row,
    super.key,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: YsTheme.of(context).neutralAmbientColor,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}
