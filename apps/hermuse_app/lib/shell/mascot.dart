import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'brand.dart';

/// Width over height of the mascot artwork.
const _aspect = 328 / 628;

/// Hermuse on her stage: the full-body mascot standing on a rounded
/// `primary` stage, her head above its top edge. She waves hello a few
/// times, then stands; with animations disabled she just stands.
/// Decorative.
final class HermuseMascot extends StatelessWidget {
  const HermuseMascot({
    this.height = YsLayout.mascotHeight,
    this.stageWidth = YsLayout.mascotStageWidth,
    super.key,
  });

  final double height;
  final double stageWidth;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    // The stage stops below her head, so she stands out of it.
    final stageHeight = height * 0.86;
    return ExcludeSemantics(
      child: SizedBox(
        width: stageWidth,
        height: height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              width: stageWidth,
              height: stageHeight,
              decoration: BoxDecoration(
                color: palette.primaryColor,
                borderRadius: BorderRadius.circular(YsRadius.pill),
              ),
            ),
            Image(
              image: still ? hermuseStanding : hermuseWave,
              width: height * _aspect,
              height: height,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
    );
  }
}
