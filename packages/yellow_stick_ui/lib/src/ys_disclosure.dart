import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_focus_ring.dart';
import 'ys_icon_widget.dart';
import 'ys_pressable.dart';
import 'ys_resize.dart';
import 'ys_theme.dart';

/// A quiet toggle ([label], then [openLabel] once open) that unfolds
/// [child] under it: the chevron turns, the height eases. Closed at first;
/// [child] is not built while closed.
final class YsDisclosure extends StatefulWidget {
  const YsDisclosure({
    required this.label,
    required this.openLabel,
    required this.child,
    super.key,
  });

  final String label;
  final String openLabel;
  final Widget child;

  @override
  State<YsDisclosure> createState() => _YsDisclosureState();
}

final class _YsDisclosureState extends State<YsDisclosure> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final label = _open ? widget.openLabel : widget.label;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          expanded: _open,
          child: YsPressable(
            onPressed: () => setState(() => _open = !_open),
            semanticLabel: label,
            builder: (context, state) {
              final color = state.hovered || state.focused
                  ? palette.contentColor
                  : palette.contentMutedColor;
              return YsFocusRing(
                visible: state.focused,
                radius: YsRadius.row,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: YsType.label.flutter.copyWith(color: color),
                    ),
                    const SizedBox(width: YsSpace.xs),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: Duration(
                        milliseconds: still ? 0 : YsStepMotion.swap,
                      ),
                      curve: YsEase.standard.curve,
                      child: YsIconWidget(
                        YsIcon.chevronDown,
                        size: YsLayout.inlineIcon,
                        color: color,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        YsResize(
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: YsSpace.sm),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
