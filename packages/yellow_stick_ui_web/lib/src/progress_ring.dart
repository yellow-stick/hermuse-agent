import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// A small ring filled to [value] (0..1), easing to each new value, with
/// [label] in its middle (`3/7`) (Flutter `YsProgressRing` parity).
///
/// [complete] is the "ready" moment: the ring fills and turns to the
/// success colour, the label gives way to the tick of [YsStepMark.tick]
/// drawn stroke by stroke with a soft pop ([YsStepMotion.readyPop]); the
/// moment holds [YsStepMotion.readyHold] ms, then [onCompleted] fires once.
/// With reduced motion it shows the final look at once and fires right
/// away. Decorative: the host says the progress in words.
class YsProgressRing extends StatefulComponent {
  const YsProgressRing({
    required this.value,
    this.label,
    this.complete = false,
    this.onCompleted,
    super.key,
  });

  final double value;
  final String? label;
  final bool complete;
  final VoidCallback? onCompleted;

  @override
  State<YsProgressRing> createState() => _YsProgressRingState();

  static const _size = YsLayout.progressRing;
  static const _stroke = YsLayout.progressRingStroke;

  /// Side of the tick, at the share of the ring a step badge gives its
  /// glyph.
  static const _glyph = _size * YsLayout.stepGlyph / YsLayout.stepBadge;

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    final keyframes = YsKeyframeSet('ys-ring-k');
    const frames = YsStepMotion.readyFrames;
    final origin = '${ysNum(_size / 2)}px ${ysNum(_size / 2)}px';
    final ease = YsEase.standard.css;
    final rules = [
      css('.ys-ring', [
        css('&').styles(
          position: .relative(),
          display: .inlineFlex,
          width: _size.px,
          height: _size.px,
          alignItems: .center,
          justifyContent: .center,
          raw: {'flex-shrink': '0'},
        ),
        css('.ys-ring-svg').styles(
          position: .absolute(top: .zero, left: .zero),
          raw: {'overflow': 'visible'},
        ),
        css('.ys-ring-svg *').styles(raw: {'transform-box': 'view-box'}),
        css('.ys-ring-track').styles(
          raw: {
            'stroke': 'var(--neutral-film)',
            'stroke-width': ysNum(_stroke),
          },
        ),
        css('.ys-ring-value').styles(
          raw: {
            'stroke': 'var(--primary)',
            'stroke-width': ysNum(_stroke),
            'rotate': '-90deg',
            'transform-origin': origin,
            'transition':
                'stroke-dasharray ${YsStepMotion.progress}ms $ease, '
                'stroke ${ysFramesMs(YsStepMotion.readyTurn)}ms $ease',
          },
        ),
        css('.ys-ring-label').styles(
          color: .variable('--content-muted'),
          fontSize: YsType.caption.size.px,
          lineHeight: YsType.caption.lineHeight.px,
          raw: {
            'font-variant-numeric': 'tabular-nums',
            'transition': 'opacity ${YsStepMotion.swap}ms $ease',
          },
        ),
        css('.ys-ring-tick').styles(opacity: 0, color: .variable('--success')),
      ]),
      css('.ys-ring[data-complete]', [
        css('.ys-ring-value').styles(raw: {'stroke': 'var(--success)'}),
        css('.ys-ring-label').styles(opacity: 0),
        css('.ys-ring-svg').styles(
          raw: {
            'transform-origin': origin,
            'animation': ysAnimations(
              YsStepMotion.readyPop,
              keyframes,
              frames: frames,
              fill: 'backwards',
            ),
          },
        ),
        css('.ys-ring-tick').styles(opacity: 1),
        css('.ys-ring-tick path').styles(
          raw: {
            'animation': ysAnimations(
              YsStepMark.tick.part(0)!,
              keyframes,
              frames: frames,
              fill: 'backwards',
            ),
          },
        ),
      ]),
    ];
    return [
      ...keyframes.rules,
      ...rules,
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-ring *').styles(
          raw: {
            'animation': 'none !important',
            'transition': 'none !important',
          },
        ),
      ]),
    ];
  }
}

class _YsProgressRingState extends State<YsProgressRing> {
  Timer? _moment;
  var _fired = false;

  /// The moment in milliseconds: tick and pop, then the hold.
  static int get _readyMs =>
      ysFramesMs(YsStepMotion.readyFrames) + YsStepMotion.readyHold;

  @override
  void initState() {
    super.initState();
    if (component.complete) _complete();
  }

  @override
  void didUpdateComponent(YsProgressRing oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (component.complete && !oldComponent.complete) _complete();
    if (!component.complete && oldComponent.complete) {
      _moment?.cancel();
      _fired = false;
    }
  }

  @override
  void dispose() {
    _moment?.cancel();
    super.dispose();
  }

  void _complete() {
    if (!kIsWeb) return;
    _moment?.cancel();
    _moment = Timer(
      Duration(milliseconds: ysReducedMotion() ? 0 : _readyMs),
      _fire,
    );
  }

  void _fire() {
    if (!mounted || !component.complete || _fired) return;
    _fired = true;
    component.onCompleted?.call();
  }

  @override
  Component build(BuildContext context) {
    const size = YsProgressRing._size;
    const center = size / 2;
    final value = component.complete ? 1.0 : component.value.clamp(0.0, 1.0);
    Component circle(String classes, {Styles? styles}) => Component.element(
      tag: 'circle',
      classes: classes,
      styles: styles,
      attributes: {
        'cx': ysNum(center),
        'cy': ysNum(center),
        'r': ysNum((size - YsProgressRing._stroke) / 2),
        'pathLength': '1',
      },
    );
    final label = component.label;
    const glyph = YsProgressRing._glyph;
    const inset = (size - glyph) / 2;
    return span(
      classes: 'ys-ring',
      attributes: {
        'aria-hidden': 'true',
        if (component.complete) 'data-complete': '',
      },
      [
        Component.element(
          tag: 'svg',
          classes: 'ys-ring-svg',
          attributes: {
            'viewBox': '0 0 ${ysNum(size)} ${ysNum(size)}',
            'width': ysNum(size),
            'height': ysNum(size),
            'fill': 'none',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          },
          children: [
            circle('ys-ring-track'),
            if (value > 0)
              circle(
                'ys-ring-value',
                styles: Styles(
                  raw: {
                    'stroke-dasharray':
                        '${ysNum(value < 0.02 ? 0.02 : value)} 2',
                  },
                ),
              ),
            Component.element(
              tag: 'svg',
              classes: 'ys-ring-tick',
              attributes: {
                'x': ysNum(inset),
                'y': ysNum(inset),
                'width': ysNum(glyph),
                'height': ysNum(glyph),
                'viewBox': '0 0 24 24',
                'stroke': 'currentColor',
                'stroke-width': ysNum(YsLayout.stepGlyphStroke),
              },
              children: [
                ysSvgElement(
                  ysSvgElements(YsStepMark.tick.body).single,
                  trimmed: true,
                ),
              ],
            ),
          ],
        ),
        if (label != null) span(classes: 'ys-ring-label', [.text(label)]),
      ],
    );
  }
}
