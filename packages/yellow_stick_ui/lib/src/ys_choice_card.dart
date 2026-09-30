import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_art.dart';
import 'ys_focus_ring.dart';
import 'ys_lift.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';

/// A big selectable card: [art] above [title] and [body], centred. The
/// whole card is the button: pointing at it lifts it, tints its outline and
/// plays the art's hover motion; keyboard focus draws the focus ring;
/// Enter or Space activates it.
///
/// [title] stays one plain line of text so it can be read (and clicked) as
/// such.
final class YsChoiceCard extends StatelessWidget {
  const YsChoiceCard({
    required this.art,
    required this.title,
    required this.onPressed,
    this.body,
    this.autofocus = false,
    super.key,
  });

  final YsArt art;
  final String title;
  final String? body;
  final VoidCallback? onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onPressed != null,
    label: title,
    hint: body,
    child: YsPressable(
      onPressed: onPressed,
      excludeSemantics: true,
      autofocus: autofocus,
      builder: (context, state) {
        final palette = YsTheme.of(context);
        final active = (state.hovered || state.focused) && !state.disabled;
        final still = MediaQuery.disableAnimationsOf(context);
        final body = this.body;
        return ExcludeSemantics(
          child: YsFocusRing(
            visible: state.focused && !state.disabled,
            radius: YsRadius.bubble,
            child: YsLift(
              lifted: active,
              pressed: state.pressed,
              radius: YsRadius.bubble,
              child: AnimatedContainer(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: YsMotion.base),
                curve: YsEase.standard.curve,
                padding: const EdgeInsets.fromLTRB(
                  YsSpace.xl,
                  YsSpace.xl,
                  YsSpace.xl,
                  YsSpace.xl - YsSpace.xs,
                ),
                decoration: BoxDecoration(
                  color: palette.paperColor,
                  borderRadius: BorderRadius.circular(YsRadius.bubble),
                  border: Border.all(
                    color: active
                        ? palette.primaryMutedColor
                        : palette.lineColor,
                    width: ysHairline,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YsArtView(art, size: YsLayout.artChoice, active: active),
                    const SizedBox(height: YsSpace.md),
                    Text(
                      title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      textAlign: TextAlign.center,
                      style: YsType.heading.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: YsSpace.xs),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: YsType.small.flutter.copyWith(
                          color: palette.contentMutedColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
