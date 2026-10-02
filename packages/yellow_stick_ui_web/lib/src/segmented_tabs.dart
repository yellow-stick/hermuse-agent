import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'icon.dart';
import 'pressable.dart';

/// One segment of [YsSegmentedTabs]: an icon-only button with a hover label.
final class YsSegment<T> {
  const YsSegment({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final YsIcon icon;
  final String label;
}

/// Segmented tab track (neutralAmbient, h36, pill, pad 4) with icon-only
/// segments (h28, radius 16); the selected segment is neutralFilm. A thin 1px
/// divider ([line]) separates non-selected neighbours, as in the reference.
class YsSegmentedTabs<T> extends StatelessComponent {
  const YsSegmentedTabs({
    required this.segments,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<YsSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Component build(BuildContext context) => div(
    classes: 'ys-tabs',
    attributes: {'role': 'tablist'},
    [
      for (var i = 0; i < segments.length; i++) ...[
        if (i > 0 &&
            segments[i - 1].value != selected &&
            segments[i].value != selected)
          div(classes: 'ys-tabs-divider', []),
        _segment(segments[i]),
      ],
    ],
  );

  Component _segment(YsSegment<T> segment) {
    final isSelected = segment.value == selected;
    return YsPressable(
      onPressed: () => onSelected(segment.value),
      classes: isSelected ? 'ys-tab ys-tab-selected' : 'ys-tab',
      attributes: {
        'role': 'tab',
        'aria-selected': '$isSelected',
        'aria-label': segment.label,
      },
      builder: (context, state) => .fragment([
        YsIconView(segment.icon, size: 18),
        span(classes: 'ys-tooltip ys-tooltip-above', [.text(segment.label)]),
      ]),
    );
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-tabs', [
      css('&').styles(
        height: 36.px,
        padding: .all(4.px),
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        backgroundColor: .variable('--neutral-ambient'),
      ),
      css('.ys-tab').styles(
        height: 28.px,
        padding: .zero,
        radius: .circular(YsRadius.segment.px),
        flex: .grow(1),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content-muted'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        position: .relative(),
      ),
      css('.ys-tab:hover').styles(color: .variable('--content')),
      css('.ys-tab-selected').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-film'),
      ),
      css('.ys-tab:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.ys-tabs-divider').styles(
        width: 1.px,
        height: 16.px,
        backgroundColor: .variable('--line'),
      ),
    ]),
  ];
}
