import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// [child] whose size changes ease over [YsStepMotion.resize] ms
/// ([YsEase.standard]), anchored at the top start: a row unfolding, a
/// section coming or going. At once when animations are disabled.
final class YsResize extends StatelessWidget {
  const YsResize({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.disableAnimationsOf(context)
      ? child
      : AnimatedSize(
          duration: const Duration(milliseconds: YsStepMotion.resize),
          curve: YsEase.standard.curve,
          alignment: AlignmentDirectional.topStart,
          child: child,
        );
}
