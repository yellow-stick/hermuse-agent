import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'ys_theme.dart';

/// Indeterminate circular spinner: a `contentMuted` arc sweeping on
/// `neutralFilm`, 900 ms per turn.
final class YsSpinner extends StatefulWidget {
  const YsSpinner({super.key, this.size = 16, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  State<YsSpinner> createState() => _YsSpinnerState();
}

final class _YsSpinnerState extends State<YsSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Reduced motion: the arc stands still.
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final arc = _SweepArc(
      track: palette.neutralFilmColor,
      arc: palette.contentMutedColor,
      size: widget.size,
      strokeWidth: widget.strokeWidth,
    );
    // Muted (e.g. widget tests settling) or reduced motion: static arc, no
    // scheduled frames.
    if (_still || !TickerMode.valuesOf(context).enabled) return arc;
    return RotationTransition(turns: _turn, child: arc);
  }
}

/// Static sweep arc: identical look without the repeating animation.
final class _SweepArc extends StatelessWidget {
  const _SweepArc({
    required this.track,
    required this.arc,
    required this.size,
    required this.strokeWidth,
  });

  final Color track;
  final Color arc;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _ArcPainter(track: track, arc: arc, strokeWidth: strokeWidth),
  );
}

final class _ArcPainter extends CustomPainter {
  _ArcPainter({
    required this.track,
    required this.arc,
    required this.strokeWidth,
  });

  final Color track;
  final Color arc;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 1.2,
      false,
      paint..color = arc,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.track != track || old.arc != arc || old.strokeWidth != strokeWidth;
}
