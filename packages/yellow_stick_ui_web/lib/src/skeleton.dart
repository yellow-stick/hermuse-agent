import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// Loading placeholder: [children] lay out [YsSkeletonBox]es where the
/// content will be, and a highlight band [YsShimmerMotion.band] of the
/// skeleton's width sweeps across them every [YsShimmerMotion.period] ms.
/// The band crosses every box at the same place, like one light passing
/// over the whole skeleton, since boxes start at its left edge.
///
/// Decorative: hosts announce the loading themselves. With reduced motion
/// the boxes stay still.
class YsSkeleton extends StatelessComponent {
  const YsSkeleton({required this.children, super.key});

  final List<Component> children;

  @override
  Component build(BuildContext context) => div(
    classes: 'ys-skeleton',
    attributes: {'aria-hidden': 'true'},
    children,
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    const band = YsShimmerMotion.band;
    // The band image is `band` of the skeleton wide; it travels from fully
    // left of it to fully right of it (container query units).
    String at(double position) => '${ysNum(position * 100)}cqw 0px';
    return [
      css.keyframes('ys-skeleton-sweep', {
        '0%': Styles(raw: {'background-position': at(-band * 1.5)}),
        '100%': Styles(raw: {'background-position': at(1 + band / 2)}),
      }),
      css('.ys-skeleton').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .start,
        raw: {'container-type': 'inline-size'},
      ),
      css('.ys-skeleton-box').styles(
        maxWidth: 100.percent,
        radius: .circular(YsRadius.row.px),
        backgroundColor: .variable('--neutral-ambient'),
        raw: {
          'background-image':
              'linear-gradient(90deg, var(--neutral-ambient), '
              'var(--neutral-film), var(--neutral-ambient))',
          'background-size': '${ysNum(band * 100)}cqw 100%',
          'background-repeat': 'no-repeat',
          'animation':
              'ys-skeleton-sweep ${YsShimmerMotion.period}ms linear infinite',
        },
      ),
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-skeleton-box')
            .styles(raw: {'animation': 'none', 'background-image': 'none'}),
      ]),
    ];
  }
}

/// One placeholder block of a [YsSkeleton]: [height] px high, [width] wide
/// (the skeleton's width when null), [top] px below the block above.
class YsSkeletonBox extends StatelessComponent {
  const YsSkeletonBox({
    required this.height,
    this.width,
    this.top = 0,
    super.key,
  });

  final double height;
  final Unit? width;
  final double top;

  @override
  Component build(BuildContext context) => div(
    classes: 'ys-skeleton-box',
    styles: Styles(
      width: width ?? 100.percent,
      height: height.px,
      margin: top == 0 ? null : .only(top: top.px),
    ),
    [],
  );
}
