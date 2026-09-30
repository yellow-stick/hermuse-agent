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
/// to the end. While [busy] that motion plays over and over.
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
    this.busy = false,
    super.key,
  }) : hero = false;

  /// The drawing heading a full-page status: [YsLayout.artHero] big, its
  /// lines at [YsArt.heroStroke], without the soft disc.
  const YsArtView.hero(
    this.art, {
    this.active = false,
    this.busy = false,
    super.key,
  }) : size = YsLayout.artHero,
       hero = true;

  final YsArt art;
  final double size;

  /// Pointer over the host; a rising edge plays the hover motion.
  final bool active;

  /// Work under way (a check running): the hover motion, or one idle cycle,
  /// plays over and over. When it turns off, the cycle under way plays to
  /// its end and the drawing rests.
  final bool busy;

  /// Drawn as a hero ([YsArtView.hero]).
  final bool hero;

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

  /// Whether the busy loop plays: from [YsArtView.busy] turning on to the
  /// end of the cycle under way when it turns off.
  var _looping = false;

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
  void initState() {
    super.initState();
    _looping = component.busy && _hoverFrames > 0 && !ysReducedMotion();
  }

  @override
  void didUpdateComponent(YsArtView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.art != component.art) {
      // A new drawing (a new element, see build) draws in again.
      _shown = DateTime.now();
      _hovering = false;
      _looping = component.busy && _hoverFrames > 0 && !ysReducedMotion();
      return;
    }
    if (component.busy && !_looping && _hoverFrames > 0 && !ysReducedMotion()) {
      _looping = true;
      _hovering = false;
    }
    if (!oldComponent.active &&
        component.active &&
        !_hovering &&
        !_looping &&
        _hoverFrames > 0 &&
        _rested &&
        !ysReducedMotion()) {
      _hovering = true;
    }
  }

  /// Whether [event] comes from a hover group, the only `ys-a-h*` elements.
  static bool _fromHover(web.Event event) {
    final target = event.target as web.Element?;
    return target?.getAttribute('class')?.startsWith('ys-a-h') ?? false;
  }

  /// The hover motion ended.
  void _onEnd(web.Event event) {
    if (_hovering && _fromHover(event)) setState(() => _hovering = false);
  }

  /// A busy cycle ended: the loop stops there once the work is over, where
  /// every part is at rest.
  void _onIteration(web.Event event) {
    if (_looping && !component.busy && _fromHover(event)) {
      setState(() => _looping = false);
    }
  }

  @override
  Component build(BuildContext context) {
    final art = component.art;
    return span(
      key: ValueKey(art.name),
      classes: 'ys-art ys-art-${art.name}',
      styles: Styles(width: component.size.px, height: component.size.px),
      attributes: {
        'aria-hidden': 'true',
        if (_looping) 'data-busy': '' else if (_hovering) 'data-hover': '',
      },
      events: {
        'animationend': _onEnd,
        'animationcancel': _onEnd,
        'animationiteration': _onIteration,
      },
      [
        Component.element(
          tag: 'svg',
          attributes: {
            'viewBox': '0 0 ${ysNum(YsArt.viewBox)} ${ysNum(YsArt.viewBox)}',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': ysNum(
              component.hero ? YsArt.heroStroke : YsArt.stroke,
            ),
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
          },
          children: [
            for (final (i, part) in art.parts.indexed)
              // A hero leaves the soft disc out.
              if (!component.hero || part.ink != YsArtInk.soft)
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
/// (or one idle cycle) on its hover group while the art has `data-hover`,
/// endlessly while it has `data-busy`. A busy loop of idle cycles replaces
/// the idle motion, as on desktop, instead of adding to it.
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
      if (idle != null && art.hover.isEmpty) {
        rules.add('$scope[data-busy] .ys-a-i$i', {'animation': 'none'});
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
        add(
          '$scope[data-busy] .ys-a-h$i',
          hover,
          ysAnimations(hover, keyframes, frames: hoverFrames, loop: true),
        );
      }
    }
  }
  return [...keyframes.rules, ...rules.rules];
}
