import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// Sparks flying out around [child] once each time [play] turns on: the
/// [YsBurst] rays, accent and success in turn, in a [YsLayout.burst] square
/// centred on the child. They paint outside the child's box and take no
/// room.
///
/// With reduced motion nothing flies.
class YsBurstView extends StatefulComponent {
  const YsBurstView({required this.play, required this.child, super.key});

  final bool play;
  final Component child;

  @override
  State<YsBurstView> createState() => _YsBurstViewState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    final keyframes = YsKeyframeSet('ys-burst-k');
    final rays = YsRuleSet();
    for (final (i, ray) in YsBurst.motion.indexed) {
      rays.add('.ys-burst .ys-burst-r$i', {
        'animation': ysAnimations(ray, keyframes, frames: YsBurst.frames),
      });
    }
    const size = YsLayout.burst;
    return [
      ...keyframes.rules,
      css('.ys-burst-host').styles(
        position: .relative(),
        display: .inlineFlex,
        raw: {'flex-shrink': '0'},
      ),
      css('.ys-burst', [
        css('&').styles(
          position: .absolute(top: 50.percent, left: 50.percent),
          width: size.px,
          height: size.px,
          margin: .only(top: (-size / 2).px, left: (-size / 2).px),
          overflow: .visible,
          pointerEvents: .none,
        ),
        // Between plays (and once a ray has flown) nothing shows.
        css('path').styles(opacity: 0),
        css('path:nth-child(odd)').styles(color: .variable('--primary')),
        css('path:nth-child(even)').styles(color: .variable('--success')),
      ]),
      ...rays.rules,
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-burst').styles(display: .none),
      ]),
    ];
  }
}

class _YsBurstViewState extends State<YsBurstView> {
  /// Bursts played so far; each is a new element, so its animations start
  /// over.
  var _plays = 0;
  var _flying = false;

  @override
  void didUpdateComponent(YsBurstView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (!oldComponent.play && component.play && !ysReducedMotion()) {
      _plays++;
      _flying = true;
    }
  }

  @override
  Component build(BuildContext context) => span(classes: 'ys-burst-host', [
    component.child,
    if (_flying)
      Component.element(
        key: ValueKey(_plays),
        tag: 'svg',
        classes: 'ys-burst',
        attributes: {
          'viewBox': '0 0 ${ysNum(YsBurst.viewBox)} ${ysNum(YsBurst.viewBox)}',
          'fill': 'none',
          'stroke': 'currentColor',
          'stroke-width': ysNum(YsArt.stroke),
          'stroke-linecap': 'round',
          'aria-hidden': 'true',
        },
        // Every ray lasts the whole burst: the first end is the last.
        events: {'animationend': (_) => setState(() => _flying = false)},
        children: [
          for (final (i, ray) in ysSvgElements(YsBurst.body).indexed)
            ysSvgElement(ray, classes: 'ys-burst-r$i', trimmed: true),
        ],
      ),
  ]);
}
