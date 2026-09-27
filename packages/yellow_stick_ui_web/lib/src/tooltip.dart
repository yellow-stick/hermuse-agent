import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Where a [YsTooltip] shows relative to its target.
enum YsTooltipSide { above, below, right }

/// CSS-only tooltip: a small dark chip (neutralAmbient, caption text) beside
/// the target on hover/focus ([side]: above by default; rails use right so
/// the chip never covers the neighbouring item).
///
/// Wrap the target; the [label] span shows when the wrapper is hovered or
/// focus-visible. The parent establishes positioning context.
class YsTooltip extends StatelessComponent {
  const YsTooltip({
    required this.label,
    required this.child,
    this.side = YsTooltipSide.above,
    super.key,
  });

  final String label;
  final Component child;
  final YsTooltipSide side;

  @override
  Component build(BuildContext context) => span(classes: 'ys-has-tooltip', [
    child,
    span(classes: 'ys-tooltip ys-tooltip-${side.name}', [.text(label)]),
  ]);

  // Flat rules on purpose: selectors nested under `css('.ys-tooltip', [...])`
  // compile to descendant selectors (`.ys-tooltip .ys-tooltip-right`) and
  // never match.
  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-has-tooltip').styles(position: .relative(), display: .inlineFlex),
    css('.ys-tooltip').styles(
      position: .absolute(),
      padding: .symmetric(vertical: 4.px, horizontal: 8.px),
      radius: .circular(6.px),
      color: .variable('--content'),
      backgroundColor: .variable('--neutral-ambient'),
      fontSize: 12.px,
      lineHeight: 16.px,
      raw: {
        'white-space': 'nowrap',
        'pointer-events': 'none',
        'opacity': '0',
        'transition': 'opacity 120ms ease',
        'z-index': '50',
        'left': '50%',
        'transform': 'translateX(-50%)',
      },
    ),
    css('.ys-tooltip-above').styles(raw: {'bottom': 'calc(100% + 6px)'}),
    css('.ys-tooltip-below').styles(raw: {'top': 'calc(100% + 6px)'}),
    css('.ys-tooltip-right').styles(
      raw: {
        'left': 'calc(100% + 8px)',
        'top': '50%',
        'transform': 'translateY(-50%)',
      },
    ),
    // Plain `.ys-tooltip` spans embedded in buttons (no .ys-has-tooltip
    // wrapper) centre the same way.
    css('button > .ys-tooltip, .ys-btn-pill > .ys-tooltip')
        .styles(position: .absolute()),
    css(
      '.ys-has-tooltip:hover > .ys-tooltip, '
      '.ys-has-tooltip:has(:focus-visible) > .ys-tooltip, '
      'button:hover > .ys-tooltip, button:focus-visible > .ys-tooltip, '
      '.ys-btn-pill:hover > .ys-tooltip, .ys-btn-pill:focus-visible > .ys-tooltip',
    ).styles(raw: {'opacity': '1'}),
  ];
}
