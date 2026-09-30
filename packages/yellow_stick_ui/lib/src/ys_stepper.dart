import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_step_badge.dart';
import 'ys_theme.dart';

/// Progress through a short flow: one badge per step with its label under
/// it, joined by lines. Steps before [current] show a calm tick and a
/// filled line, the current one its icon in an accent ring, later ones stay
/// muted. The line into the current step fills as it appears.
final class YsStepper extends StatelessWidget {
  const YsStepper({required this.steps, required this.current, super.key});

  final List<({YsIcon icon, String label})> steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      label: 'Step ${current + 1} of ${steps.length}: ${steps[current].label}',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: still ? 1 : 0, end: 1),
          duration: still
              ? Duration.zero
              : const Duration(milliseconds: YsStepMotion.progress),
          curve: YsEase.standard.curve,
          builder: (context, fill, child) => CustomPaint(
            painter: _LinePainter(
              count: steps.length,
              current: current,
              fill: fill,
              done: palette.successColor,
              rest: palette.lineColor,
            ),
            child: child,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, step) in steps.indexed)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      YsStepBadge(
                        state: i < current
                            ? YsStepState.found
                            : i == current
                            ? YsStepState.needsAction
                            : YsStepState.pending,
                        icon: step.icon,
                        size: YsLayout.stepperBadge,
                      ),
                      const SizedBox(height: YsSpace.xs),
                      Text(
                        step.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: YsType.caption.flutter.copyWith(
                          color: i == current
                              ? palette.contentColor
                              : palette.contentMutedColor,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.count,
    required this.current,
    required this.fill,
    required this.done,
    required this.rest,
  });

  final int count;
  final int current;

  /// How far the line into [current] has filled, 0..1.
  final double fill;
  final Color done;
  final Color rest;

  @override
  void paint(Canvas canvas, Size size) {
    const y = YsLayout.stepperBadge / 2;
    const gap = YsLayout.stepperBadge / 2 + YsSpace.xs;
    final column = size.width / count;
    final paint = Paint()
      ..strokeWidth = YsLayout.stepperLine
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count - 1; i++) {
      final from = Offset(column * (i + 0.5) + gap, y);
      final to = Offset(column * (i + 1.5) - gap, y);
      if (to.dx <= from.dx) continue;
      canvas.drawLine(from, to, paint..color = rest);
      final filled = i < current - 1
          ? 1.0
          : i == current - 1
          ? fill
          : 0.0;
      if (filled > 0) {
        canvas.drawLine(
          from,
          Offset.lerp(from, to, filled)!,
          paint..color = done,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.count != count ||
      old.current != current ||
      old.fill != fill ||
      old.done != done ||
      old.rest != rest;
}
