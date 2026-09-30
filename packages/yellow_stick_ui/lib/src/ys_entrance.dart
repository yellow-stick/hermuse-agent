import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// A page coming on screen: [child] fades in while rising
/// [YsPageMotion.rise] px once, when it is first built. Key it by the page
/// (route, step) so a new page enters again; the previous one is simply
/// gone, so no subtree is ever on screen twice.
///
/// With animations disabled it shows at once.
final class YsEntrance extends StatefulWidget {
  const YsEntrance({required this.child, super.key});

  final Widget child;

  @override
  State<YsEntrance> createState() => _YsEntranceState();
}

final class _YsEntranceState extends State<YsEntrance>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: YsPageMotion.enter),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: YsEase.settle.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (still) {
      _controller.value = 1;
    } else if (!_started) {
      _controller.forward(from: 0);
    }
    _started = true;
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  // One tree shape at every value: the child keeps its state when the
  // entrance ends.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    builder: (context, child) => Opacity(
      opacity: _curve.value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, YsPageMotion.rise * (1 - _curve.value)),
        child: child,
      ),
    ),
    child: widget.child,
  );
}
