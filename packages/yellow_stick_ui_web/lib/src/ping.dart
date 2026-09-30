import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// A status dot that pings: when [live] turns on (or is on when it first
/// shows), a ring of [color] grows out of [child] to [YsPingMotion.reach]
/// times its size and fades, [YsPingMotion.pings] times, then rests.
///
/// With reduced motion nothing moves.
class YsPing extends StatefulComponent {
  const YsPing({
    required this.live,
    required this.color,
    required this.child,
    super.key,
  });

  final bool live;
  final Color color;
  final Component child;

  @override
  State<YsPing> createState() => _YsPingState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    // The ring's box grows from the child's to `reach` times it.
    final grown = '${ysNum(-(YsPingMotion.reach - 1) / 2 * 100)}%';
    final period = '${YsPingMotion.period}ms';
    return [
      css.keyframes('ys-ping-grow', {
        '0%': Styles(raw: {'inset': '0px'}),
        '100%': Styles(raw: {'inset': grown}),
      }),
      css.keyframes('ys-ping-fade', {
        '0%': Styles(opacity: 0.9),
        '100%': Styles(opacity: 0),
      }),
      css('.ys-ping', [
        css('&').styles(
          position: .relative(),
          display: .inlineFlex,
          raw: {'flex-shrink': '0'},
        ),
        css('.ys-ping-ring').styles(
          position: .absolute(),
          radius: .circular(YsRadius.pill.px),
          opacity: 0,
          pointerEvents: .none,
          raw: {
            'inset': '0px',
            'border': '${ysNum(ysHairline)}px solid currentColor',
            'animation':
                'ys-ping-grow $period ${YsEase.settle.css} '
                '${YsPingMotion.pings}, '
                'ys-ping-fade $period linear ${YsPingMotion.pings}',
          },
        ),
      ]),
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-ping-ring').styles(display: .none),
      ]),
    ];
  }
}

class _YsPingState extends State<YsPing> {
  /// Pings played so far; each play is a new ring element.
  var _plays = 0;
  var _ringing = false;

  @override
  void initState() {
    super.initState();
    if (component.live) _play();
  }

  @override
  void didUpdateComponent(YsPing oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (!oldComponent.live && component.live) _play();
  }

  void _play() {
    if (ysReducedMotion()) return;
    _plays++;
    _ringing = true;
  }

  @override
  Component build(BuildContext context) => span(classes: 'ys-ping', [
    component.child,
    if (_ringing)
      span(
        key: ValueKey(_plays),
        classes: 'ys-ping-ring',
        styles: Styles(color: component.color),
        attributes: {'aria-hidden': 'true'},
        events: {
          'animationend': (event) {
            if ((event as web.AnimationEvent).animationName == 'ys-ping-fade') {
              setState(() => _ringing = false);
            }
          },
        },
        [],
      ),
  ]);
}
