import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// Renders a core [YsArt] line illustration: it draws in when it first
/// shows, plays its idle motion [YsArtMotion.idleCycles] times and rests;
/// each time [active] turns on (the pointer over its host) once the idle
/// has rested, it plays its hover motion, or one more idle cycle, through
/// to the end.
///
/// Every motion is CSS keyframes generated from the core timings: each part
/// sits in an idle group and a hover group, and the element itself draws in
/// with `pathLength="1"` dashes. With reduced motion it shows the finished
/// drawing and nothing moves. Decorative: hidden from assistive technology.
class YsArtView extends StatefulComponent {
  const YsArtView(
    this.art, {
    this.size = YsLayout.artEmpty,
    this.active = false,
    super.key,
  });

  final YsArt art;
  final double size;

  /// Pointer over the host; a rising edge plays the hover motion.
  final bool active;

  @override
  State<YsArtView> createState() => _YsArtViewState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-art', [
      css('&').styles(
        display: .inlineFlex,
        // The host tracks the pointer; the drawing never takes the events.
        raw: {'flex-shrink': '0', 'pointer-events': 'none'},
      ),
      css('svg').styles(
        width: 100.percent,
        height: 100.percent,
        display: .block,
        raw: {'overflow': 'visible'},
      ),
      css('svg *').styles(raw: {'transform-box': 'view-box'}),
    ]),
    for (final ink in YsArtInk.values)
      css('.ys-ink-${ink.name}').styles(
        color: .variable(switch (ink) {
          YsArtInk.line => '--content-muted',
          YsArtInk.accent => '--primary',
          YsArtInk.soft => '--neutral-ambient',
        }),
      ),
    ..._motionRules(),
    css.media(MediaQuery.raw(ysReducedMotionQuery), [
      css('.ys-art *').styles(raw: {'animation': 'none !important'}),
    ]),
  ];
}

class _YsArtViewState extends State<YsArtView> {
  /// When the current art started drawing in.
  var _shown = DateTime.now();
  var _hovering = false;

  /// Frames of the motion pointing at the art plays: its hover motion, or
  /// one idle cycle.
  double get _hoverFrames {
    final art = component.art;
    if (art.hover.isNotEmpty) return art.hoverFrames;
    return art.idle.isEmpty ? 0 : art.idleFrames;
  }

  /// Whether the draw-in and the idle cycles are over.
  bool get _rested {
    final art = component.art;
    final frames =
        art.entranceFrames +
        (art.idle.isEmpty
            ? 0
            : YsArtMotion.idleDelay + YsArtMotion.idleCycles * art.idleFrames);
    return DateTime.now().difference(_shown).inMilliseconds >=
        ysFramesMs(frames);
  }

  @override
  void didUpdateComponent(YsArtView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.art != component.art) {
      // A new drawing (a new element, see build) draws in again.
      _shown = DateTime.now();
      _hovering = false;
      return;
    }
    if (!oldComponent.active &&
        component.active &&
        !_hovering &&
        _hoverFrames > 0 &&
        _rested &&
        !ysReducedMotion()) {
      _hovering = true;
    }
  }

  /// The hover motion ended: its groups are the only `ys-a-h*` elements.
  void _onEnd(web.Event event) {
    if (!_hovering) return;
    final target = event.target as web.Element?;
    if (target?.getAttribute('class')?.startsWith('ys-a-h') ?? false) {
      setState(() => _hovering = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final art = component.art;
    return span(
      key: ValueKey(art.name),
      classes: 'ys-art ys-art-${art.name}',
      styles: Styles(width: component.size.px, height: component.size.px),
      attributes: {'aria-hidden': 'true', if (_hovering) 'data-hover': ''},
      events: {'animationend': _onEnd, 'animationcancel': _onEnd},
      [
        Component.element(
          tag: 'svg',
          attributes: {
            'viewBox': '0 0 ${ysNum(YsArt.viewBox)} ${ysNum(YsArt.viewBox)}',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': ysNum(YsArt.stroke),
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          },
          children: [
            for (final (i, part) in art.parts.indexed)
              Component.element(
                tag: 'g',
                classes: 'ys-a-i$i ys-ink-${part.ink.name}',
                children: [
                  Component.element(
                    tag: 'g',
                    classes: 'ys-a-h$i',
                    children: [
                      ysSvgElement(
                        part.markup,
                        classes: 'ys-a-e$i',
                        trimmed: !part.filled,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Keyframes and per-part rules of every [YsArt]: the draw-in on each
/// element, over its own frames from its start; the idle cycles on its idle
/// group, after the draw-in and [YsArtMotion.idleDelay]; the hover motion
/// (or one idle cycle) on its hover group while the art has `data-hover`.
List<StyleRule> _motionRules() {
  final keyframes = YsKeyframeSet('ys-art-k');
  final rules = YsRuleSet();
  void add(String selector, YsPartMotion motion, String animation) =>
      rules.add(selector, {
        if (ysTransforms(motion))
          'transform-origin':
              '${ysNum(motion.originX)}px ${ysNum(motion.originY)}px',
        'animation': animation,
      });
  for (final art in YsArt.values) {
    final scope = '.ys-art-${art.name}';
    for (var i = 0; i < art.parts.length; i++) {
      final entrance = art.entrancePart(i);
      final (start, end) = ysWindow(entrance);
      add(
        '$scope .ys-a-e$i',
        entrance,
        ysAnimations(
          entrance,
          keyframes,
          start: start,
          frames: end - start,
          delay: start,
          fill: 'backwards',
        ),
      );
      final idle = art.idlePart(i);
      if (idle != null) {
        add(
          '$scope .ys-a-i$i',
          idle,
          ysAnimations(
            idle,
            keyframes,
            frames: art.idleFrames,
            delay: art.entranceFrames + YsArtMotion.idleDelay,
            count: YsArtMotion.idleCycles,
          ),
        );
      }
      final (hover, hoverFrames) = art.hover.isEmpty
          ? (idle, art.idleFrames)
          : (art.hoverPart(i), art.hoverFrames);
      if (hover != null) {
        add(
          '$scope[data-hover] .ys-a-h$i',
          hover,
          ysAnimations(hover, keyframes, frames: hoverFrames),
        );
      }
    }
  }
  return [...keyframes.rules, ...rules.rules];
}
