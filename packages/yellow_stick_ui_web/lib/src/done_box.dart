import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'burst.dart';
import 'keyframes.dart';
import 'motion.dart';

/// A "mark done" box: empty, with a faint tick while [hovered]. When [done]
/// turns on it fills with the success colour while the tick of
/// [YsStepMark.tick] draws in it and [YsBurst] sparks fly out. A box built
/// done shows done at once, as does every change with reduced motion.
/// Decorative: the host button carries the label.
class YsDoneBox extends StatefulComponent {
  const YsDoneBox({
    required this.done,
    this.hovered = false,
    this.size = 22,
    super.key,
  });

  final bool done;
  final bool hovered;
  final double size;

  @override
  State<YsDoneBox> createState() => _YsDoneBoxState();

  /// Corner radius of the box and inset of its tick.
  static const _radius = 6.0;
  static const _inset = 4.0;

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    const glyph = YsStepMark.tick;
    final keyframes = YsKeyframeSet('ys-done-k');
    // The box fills as the tick's ring would close.
    final fill = glyph.ring!.track(YsMotionProperty.trimEnd)!;
    String play(YsSteps steps) =>
        '${keyframes.name(steps)} ${glyph.durationMs}ms linear backwards';
    final rules = [
      css('.ys-done', [
        css('&').styles(
          position: .relative(),
          display: .inlineFlex,
          radius: .circular(_radius.px),
          border: .all(
            style: .solid,
            color: .variable('--content-muted'),
            width: 1.px,
          ),
          raw: {'flex-shrink': '0'},
        ),
        css('&[data-hovered]:not([data-done])')
            .styles(backgroundColor: .variable('--neutral-film')),
        css('.ys-done-fill').styles(
          position: .absolute(
            top: (-1).px,
            left: (-1).px,
            bottom: (-1).px,
            right: (-1).px,
          ),
          radius: .circular(_radius.px),
          opacity: 0,
          backgroundColor: .variable('--success'),
        ),
        css('&[data-done] .ys-done-fill').styles(opacity: 1),
        css('&[data-celebrate] .ys-done-fill').styles(
          raw: {
            'animation': play(
              ysTrackSteps(
                fill,
                frames: glyph.frames,
                declare: (_, value) => {'opacity': ysNum(value)},
              ),
            ),
          },
        ),
        css('.ys-done-tick').styles(
          position: .absolute(top: _inset.px, left: _inset.px),
          width: .expression('calc(100% - ${ysNum(_inset * 2)}px)'),
          height: .expression('calc(100% - ${ysNum(_inset * 2)}px)'),
          opacity: 0,
          overflow: .visible,
        ),
        css('&[data-hovered]:not([data-done]) .ys-done-tick')
            .styles(opacity: 1, color: .variable('--content-subtle')),
        css('&[data-done] .ys-done-tick')
            .styles(opacity: 1, color: .variable('--canvas')),
        css('&[data-celebrate] .ys-done-tick path').styles(
          raw: {
            'animation': ysAnimations(
              glyph.part(0)!,
              keyframes,
              frames: glyph.frames,
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
        css('.ys-done *').styles(raw: {'animation': 'none !important'}),
      ]),
    ];
  }
}

class _YsDoneBoxState extends State<YsDoneBox> {
  /// Done here, since this box showed: the fill, the tick and the sparks
  /// play.
  var _celebrate = false;

  @override
  void didUpdateComponent(YsDoneBox oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (oldComponent.done == component.done) return;
    _celebrate = component.done && !ysReducedMotion();
  }

  @override
  Component build(BuildContext context) => YsBurstView(
    play: _celebrate,
    child: span(
      classes: 'ys-done',
      styles: Styles(width: component.size.px, height: component.size.px),
      attributes: {
        'aria-hidden': 'true',
        if (component.done) 'data-done': '',
        if (_celebrate) 'data-celebrate': '',
        if (component.hovered) 'data-hovered': '',
      },
      [
        span(classes: 'ys-done-fill', []),
        Component.element(
          tag: 'svg',
          classes: 'ys-done-tick',
          attributes: {
            'viewBox': '0 0 24 24',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': ysNum(YsLayout.stepGlyphStroke + 0.5),
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
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
  );
}
