import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// Sparks flying out around [child] once each time [play] turns on: the
/// [YsBurst] rays, accent and success in turn, in a [YsLayout.burst]
/// square centred on the child. They paint outside the child's box and
/// take no room.
///
/// With animations disabled nothing flies.
final class YsBurstView extends StatefulWidget {
  const YsBurstView({required this.play, required this.child, super.key});

  final bool play;
  final Widget child;

  @override
  State<YsBurstView> createState() => _YsBurstViewState();
}

final class _YsBurstViewState extends State<YsBurstView>
    with SingleTickerProviderStateMixin {
  late final _burst = AnimationController(
    vsync: this,
    duration: Duration(microseconds: (YsBurst.frames * 1e6 / 60).round()),
  );

  @override
  void didUpdateWidget(YsBurstView old) {
    super.didUpdateWidget(old);
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (!old.play && widget.play && !still) {
      _burst.forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) _burst.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return CustomPaint(
      foregroundPainter: _BurstPainter(
        _burst,
        palette.primaryColor,
        palette.successColor,
      ),
      child: widget.child,
    );
  }
}

final class _BurstPainter extends CustomPainter {
  _BurstPainter(this.burst, this.accent, this.success) : super(repaint: burst);

  final AnimationController burst;
  final Color accent;
  final Color success;

  @override
  void paint(Canvas canvas, Size size) {
    if (!burst.isAnimating) return;
    final frame = burst.value * YsBurst.frames;
    final shapes = YsSvgShape.of(YsBurst.body);
    const scale = YsLayout.burst / YsBurst.viewBox;
    canvas
      ..save()
      ..translate(
        size.width / 2 - YsLayout.burst / 2,
        size.height / 2 - YsLayout.burst / 2,
      )
      ..scale(scale);
    for (var i = 0; i < shapes.length; i++) {
      final part = YsBurst.motion[i];
      final opacity = part.valueAt(YsMotionProperty.opacity, frame);
      if (opacity <= 0) continue;
      final color = i.isEven ? accent : success;
      shapes[i].paint(
        canvas,
        ysPartPath(shapes[i].path, part, frame),
        color.withValues(alpha: color.a * opacity),
        YsArt.stroke,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.burst != burst || old.accent != accent || old.success != success;
}
