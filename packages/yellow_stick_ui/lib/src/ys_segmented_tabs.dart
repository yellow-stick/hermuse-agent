import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_focus_ring.dart';
import 'ys_icon_widget.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';
import 'ys_tooltip.dart';

/// One icon-only tab with a hover tooltip label.
final class YsSegment {
  const YsSegment({required this.icon, required this.label});

  final YsIcon icon;
  final String label;
}

/// Icon-only segmented control: neutralAmbient track (h36, radius pill,
/// pad 4), h28 radius-16 segments, selected segment neutralFilm, thin divider
/// between non-selected neighbours.
final class YsSegmentedTabs extends StatelessWidget {
  const YsSegmentedTabs({
    required this.segments,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
    this.semanticLabel,
  }) : assert(segments.length > 0, 'segments must not be empty');

  final List<YsSegment> segments;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Semantics(
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.neutralAmbientColor,
          borderRadius: BorderRadius.circular(YsRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < segments.length; i++) ...[
                if (i > 0 && i - 1 != selectedIndex && i != selectedIndex)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: SizedBox(
                      width: 1,
                      height: 16,
                      child: ColoredBox(color: palette.lineColor),
                    ),
                  ),
                Flexible(
                  child: _SegmentButton(
                    segment: segments[i],
                    selected: i == selectedIndex,
                    onPressed: () => onSelected(i),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.segment,
    required this.selected,
    required this.onPressed,
  });

  final YsSegment segment;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsTooltip(
      message: segment.label,
      child: YsPressable(
        onPressed: onPressed,
        semanticLabel: segment.label,
        builder: (context, state) => YsFocusRing(
          visible: state.focused,
          radius: YsRadius.segment,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: YsMotion.fast),
            height: 28,
            decoration: BoxDecoration(
              color: selected
                  ? palette.neutralFilmColor
                  : state.hovered
                  ? palette.neutralFilmColor.withValues(alpha: 0.4)
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(YsRadius.segment),
            ),
            child: Center(
              child: YsIconWidget(
                segment.icon,
                size: 18,
                color: selected
                    ? palette.contentColor
                    : palette.contentMutedColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
