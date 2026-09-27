import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// Small dark chip (neutralAmbient, caption text) above its child on hover.
final class YsTooltip extends StatefulWidget {
  const YsTooltip({required this.message, required this.child, super.key});

  final String message;
  final Widget child;

  @override
  State<YsTooltip> createState() => _YsTooltipState();
}

final class _YsTooltipState extends State<YsTooltip> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return MouseRegion(
      onEnter: (_) => _controller.show(),
      onExit: (_) => _controller.hide(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _controller,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -6),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.neutralAmbientColor,
                  borderRadius: BorderRadius.circular(YsRadius.row),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    widget.message,
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
