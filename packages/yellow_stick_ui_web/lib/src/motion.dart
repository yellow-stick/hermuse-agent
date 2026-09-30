import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';

/// Media query of users asking for less motion: every animation of the kit
/// then shows its final state at once.
const ysReducedMotionQuery = '(prefers-reduced-motion: reduce)';

/// Whether the browser asks for reduced motion (never while pre-rendering).
bool ysReducedMotion() =>
    kIsWeb && web.window.matchMedia(ysReducedMotionQuery).matches;

/// `transition` entries of a card lifting under the pointer
/// ([YsLiftMotion]), for cards that list their own transitions too.
final ysLiftTransition = [
  for (final property in const ['translate', 'scale', 'box-shadow'])
    '$property ${YsLiftMotion.duration}ms ${YsEase.standard.css}',
].join(', ');

/// Declarations of a lifted card: risen, casting the palette `shadow`.
final ysLifted = {
  'translate': '0px -${ysNum(YsLiftMotion.lift)}px',
  'box-shadow':
      '0px ${ysNum(YsLiftMotion.shadowY)}px '
      '${ysNum(YsLiftMotion.shadowBlur)}px var(--shadow)',
};

/// Shadow of a card at rest: the lifted shadow, transparent and flat, so
/// the lift eases both ways.
final _restShadow = '0px 0px ${ysNum(YsLiftMotion.shadowBlur)}px transparent';

/// Page entrance and card lift, as classes:
///
/// - `ys-enter`: a page coming on screen fades in while rising
///   [YsPageMotion.rise] px ([YsPageMotion.enter] ms, [YsEase.settle]).
///   Put it on the element created for the page (key it by the page) so
///   rebuilds do not replay it.
/// - `ys-lift`: a card rises [YsLiftMotion.lift] px and casts the palette
///   `shadow` under a hovering pointer; with `ys-press`, pressing settles it
///   back to [YsLiftMotion.press] scale.
///
/// With reduced motion the page shows at once and the card changes without
/// easing.
@css
List<StyleRule> get ysMotionStyles => [
  css.keyframes('ys-enter', {
    '0%': Styles(
      opacity: 0,
      raw: {'translate': '0px ${ysNum(YsPageMotion.rise)}px'},
    ),
    '100%': Styles(opacity: 1, raw: {'translate': '0px 0px'}),
  }),
  css('.ys-enter').styles(
    raw: {
      'animation':
          'ys-enter ${YsPageMotion.enter}ms ${YsEase.settle.css} backwards',
    },
  ),
  css('.ys-lift')
      .styles(raw: {'transition': ysLiftTransition, 'box-shadow': _restShadow}),
  css.media(MediaQuery.raw('(hover: hover)'), [
    css('.ys-lift:hover').styles(raw: ysLifted),
  ]),
  css('.ys-lift.ys-press:active').styles(
    raw: {
      'translate': 'none',
      'scale': ysNum(YsLiftMotion.press),
      'box-shadow': _restShadow,
    },
  ),
  css.media(MediaQuery.raw(ysReducedMotionQuery), [
    css('.ys-enter').styles(raw: {'animation': 'none'}),
    css('.ys-lift').styles(raw: {'transition': 'none !important'}),
  ]),
];
