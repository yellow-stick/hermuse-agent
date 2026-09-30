import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// A status dot that pings: when [live] turns on (or is on when it first
/// shows), a ring of [color] grows out of [child] to
/// [YsPingMotion.reach] times its size and fades, [YsPingMotion.pings]
/// times, then rests.
///
/// With animations disabled nothing moves.
final class YsPing extends StatefulWidget {
  const YsPing({
    required this.live,
    required this.color,
    required this.child,
    super.key,
  });

  final bool live;
  final Color color;
  final Widget child;

  @override
  State<YsPing> createState() => _YsPingState();
}

final class _YsPingState extends State<YsPing>
    with SingleTickerProviderStateMixin {
  late final _ping = AnimationController(
    vsync: this,
    duration: const Duration(
      milliseconds: YsPingMotion.period * YsPingMotion.pings,
    ),
  );
  bool _started = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (_still) {
      _ping
        ..stop()
        ..value = 0;
    } else if (!_started) {
      _started = true;
      if (widget.live) _play();
    }
  }

  @override
  void didUpdateWidget(YsPing old) {
    super.didUpdateWidget(old);
    if (!old.live && widget.live && !_still) _play();
  }

  void _play() => _ping.forward(from: 0).whenCompleteOrCancel(() {
    if (mounted) _ping.value = 0;
  });

  @override
  void dispose() {
    _ping.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RingPainter(_ping, widget.color),
    child: widget.child,
  );
}

final class _RingPainter extends CustomPainter {
  _RingPainter(this.ping, this.color) : super(repaint: ping);

  final AnimationController ping;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (!ping.isAnimating) return;
    // Position inside the current ping, 0..1.
    final t = (ping.value * YsPingMotion.pings) % 1;
    final eased = YsEase.settle.transform(t);
    final radius =
        size.shortestSide / 2 * (1 + (YsPingMotion.reach - 1) * eased);
    canvas.drawCircle(
      size.center(Offset.zero),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ysHairline
        ..color = color.withValues(alpha: color.a * (1 - t) * 0.9),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ping != ping || old.color != color;
}
