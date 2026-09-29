import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_focus_ring.dart';
import 'ys_icon_widget.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';

/// Circular avatar image on an `avatarSurface` disc, with an optional badge
/// button. Transparent artwork is drawn over the disc.
final class YsAvatar extends StatelessWidget {
  const YsAvatar(
    this.image, {
    super.key,
    this.size = 100,
    this.badgeIcon,
    this.onBadgePressed,
    this.badgeSemanticLabel,
    this.semanticLabel,
  });

  final ImageProvider image;
  final double size;
  final YsIcon? badgeIcon;
  final VoidCallback? onBadgePressed;
  final String? badgeSemanticLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final badgeIcon = this.badgeIcon;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: ColoredBox(
                color: palette.avatarSurfaceColor,
                child: Image(
                  image: image,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  excludeFromSemantics: true,
                ),
              ),
            ),
            if (badgeIcon != null)
              Positioned(
                right: -2,
                bottom: -2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.canvasColor, width: 2),
                  ),
                  child: YsPressable(
                    onPressed: onBadgePressed,
                    semanticLabel: badgeSemanticLabel,
                    builder: (context, state) => YsFocusRing(
                      visible: state.focused,
                      radius: YsRadius.pill,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: YsMotion.fast),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: state.hovered || state.pressed
                              ? palette.neutralFilmColor
                              : palette.neutralAmbientColor,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: YsIconWidget(
                            badgeIcon,
                            size: 14,
                            color: palette.contentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
