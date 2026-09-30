import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'brand.dart';

/// Width over height of the mascot artwork.
const _aspect = 328 / 628;

/// Share of the mascot's height the stage covers: it stops below her head,
/// so she stands out of it.
const _stage = 0.86;

/// Hermuse on her stage: the full-body mascot standing on a rounded
/// `primary` stage, her head above its top edge. She waves hello a few
/// times, then stands; with reduced motion she just stands. Decorative.
class HermuseMascot extends StatelessComponent {
  const HermuseMascot({
    this.height = YsLayout.mascotHeight,
    this.stageWidth = YsLayout.mascotStageWidth,
    super.key,
  });

  final double height;
  final double stageWidth;

  @override
  Component build(BuildContext context) => div(
    classes: 'hermuse-mascot',
    styles: Styles(width: stageWidth.px, height: height.px),
    attributes: {'aria-hidden': 'true'},
    [
      div(
        classes: 'hermuse-mascot-stage',
        styles: Styles(height: (height * _stage).px),
        [],
      ),
      Component.element(
        tag: 'picture',
        classes: 'hermuse-mascot-art',
        children: [
          source(
            type: 'image/webp',
            attributes: {
              'srcset': hermuseStandingUrl,
              'media': ysReducedMotionQuery,
            },
          ),
          img(
            src: hermuseWaveUrl,
            alt: '',
            width: (height * _aspect).round(),
            height: height.round(),
          ),
        ],
      ),
    ],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-mascot', [
      css('&').styles(
        position: .relative(),
        display: .flex,
        justifyContent: .center,
        alignItems: .end,
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-mascot-stage').styles(
        position: .absolute(bottom: .zero, left: .zero),
        width: 100.percent,
        radius: .circular(YsRadius.pill.px),
        backgroundColor: .variable('--primary'),
      ),
      css('.hermuse-mascot-art').styles(position: .relative(), display: .flex),
      css('.hermuse-mascot-art img').styles(display: .block),
    ]),
  ];
}
