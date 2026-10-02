import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

/// Progress through a short flow: one badge per step with its label under
/// it, joined by lines. Steps before [current] show a calm green tick on a
/// soft success disc ([YsStepMark.calmTick]) and a filled line, the current
/// one its icon in an accent ring, later ones stay muted. Icons draw in
/// stroke after stroke ([YsStepMotion.drawIn]) and the line into the current
/// step fills ([YsStepMotion.progress] ms) when the stepper shows.
///
/// Announced as "Step 2 of 4: Accounts"; with reduced motion everything
/// shows at once.
class YsStepper extends StatelessComponent {
  const YsStepper({required this.steps, required this.current, super.key});

  final List<({YsIcon icon, String label})> steps;
  final int current;

  @override
  Component build(BuildContext context) => div(classes: 'ys-stepper', [
    span(classes: 'ys-stepper-status', [
      .text('Step ${current + 1} of ${steps.length}: ${steps[current].label}'),
    ]),
    ol(
      classes: 'ys-stepper-steps',
      attributes: {'aria-hidden': 'true'},
      [
        for (final (i, step) in steps.indexed)
          li(
            classes: 'ys-step',
            attributes: {
              'data-state': i < current
                  ? 'done'
                  : i == current
                  ? 'current'
                  : 'next',
            },
            [
              _badge(step.icon, done: i < current),
              span(classes: 'ys-step-label', [.text(step.label)]),
            ],
          ),
      ],
    ),
  ]);

  static const _size = YsLayout.stepperBadge;

  /// Side of the glyph inside a badge, and its offset from the badge edge.
  static const _glyph = _size * YsLayout.stepGlyph / YsLayout.stepBadge;
  static const _inset = (_size - _glyph) / 2;

  /// A done step's calm tick, or [icon] drawing in inside its ring.
  static Component _badge(YsIcon icon, {required bool done}) {
    final elements = ysSvgElements(done ? YsStepMark.calmTick.body : icon.body);
    final drawIn = YsStepMotion.drawIn(elements.length);
    return Component.element(
      tag: 'svg',
      classes: 'ys-step-badge',
      attributes: {
        'viewBox': '0 0 ${ysNum(_size)} ${ysNum(_size)}',
        'width': ysNum(_size),
        'height': ysNum(_size),
        'fill': 'none',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
      },
      children: [
        if (done)
          Component.element(
            tag: 'circle',
            classes: 'ys-step-disc',
            attributes: {
              'cx': ysNum(_size / 2),
              'cy': ysNum(_size / 2),
              'r': ysNum(_size / 2),
            },
          )
        else
          Component.element(
            tag: 'circle',
            classes: 'ys-step-ring',
            attributes: {
              'cx': ysNum(_size / 2),
              'cy': ysNum(_size / 2),
              'r': ysNum((_size - YsLayout.stepRingStroke) / 2),
            },
          ),
        Component.element(
          tag: 'g',
          classes: done ? 'ys-step-mark' : 'ys-step-glyph',
          children: [
            Component.element(
              tag: 'svg',
              attributes: {
                'x': ysNum(_inset),
                'y': ysNum(_inset),
                'width': ysNum(_glyph),
                'height': ysNum(_glyph),
                'viewBox': '0 0 24 24',
                'stroke': 'currentColor',
                'stroke-width': ysNum(YsLayout.stepGlyphStroke),
              },
              children: [
                for (final (i, markup) in elements.indexed)
                  done
                      ? ysSvgElement(markup)
                      : ysSvgElement(
                          markup,
                          classes: 'ys-step-draw',
                          trimmed: true,
                          // Each stroke draws like the first, from its own
                          // start.
                          styles: Styles(
                            raw: {
                              'animation-delay':
                                  '${ysFramesMs(ysWindow(drawIn[i]).$1)}ms',
                            },
                          ),
                        ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    final keyframes = YsKeyframeSet('ys-step-k');
    final calm = YsStepMark.calmTick;
    final firstStroke = YsStepMotion.drawIn(1).single;
    final gap = _size / 2 + YsSpace.xs;
    final rules = [
      css('.ys-stepper', [
        css('&').styles(position: .relative(), width: 100.percent),
        css('.ys-stepper-status').styles(
          position: .absolute(),
          width: 1.px,
          height: 1.px,
          overflow: .hidden,
          raw: {'clip-path': 'inset(50%)', 'white-space': 'nowrap'},
        ),
        // A row even inside hosts that stack their lists.
        css('.ys-stepper-steps').styles(
          display: .flex,
          flexDirection: .row,
          padding: .zero,
          margin: .zero,
          listStyle: .none,
        ),
        css('.ys-step').styles(
          position: .relative(),
          display: .flex,
          flexDirection: .column,
          alignItems: .center,
          flex: Flex(grow: 1, shrink: 1, basis: .zero),
          raw: {'min-width': '0'},
        ),
        // The line from the previous badge, then its filled part (nested
        // rules take one selector each).
        for (final part in const ['before', 'after'])
          css('.ys-step + .ys-step::$part').styles(
            content: '',
            position: .absolute(
              top: ((_size - YsLayout.stepperLine) / 2).px,
              left: .expression('calc(-50% + ${ysNum(gap)}px)'),
              right: .expression('calc(50% + ${ysNum(gap)}px)'),
            ),
            height: YsLayout.stepperLine.px,
            radius: .circular((YsLayout.stepperLine / 2).px),
            backgroundColor: .variable(
              part == 'before' ? '--line' : '--success',
            ),
          ),
        css('.ys-step + .ys-step::after')
            .styles(raw: {'transform-origin': 'left center', 'scale': '0 1'}),
        css('.ys-step + .ys-step[data-state="done"]::after')
            .styles(raw: {'scale': '1 1'}),
        css('.ys-step + .ys-step[data-state="current"]::after').styles(
          raw: {
            'scale': '1 1',
            'animation':
                'ys-step-fill ${YsStepMotion.progress}ms '
                '${YsEase.standard.css} backwards',
          },
        ),
        css('.ys-step-badge').styles(
          display: .block,
          raw: {'flex-shrink': '0', 'overflow': 'visible'},
        ),
        css('.ys-step-badge *').styles(raw: {'transform-box': 'view-box'}),
        css('.ys-step-ring').styles(
          raw: {'stroke': 'var(--line)', 'stroke-width': ysNum(ysHairline)},
        ),
        css('.ys-step-glyph').styles(color: .variable('--content-subtle')),
        css('[data-state="current"] .ys-step-ring').styles(
          raw: {
            'stroke': 'var(--primary)',
            'stroke-width': ysNum(YsLayout.stepRingStroke),
          },
        ),
        css('[data-state="current"] .ys-step-glyph')
            .styles(color: .variable('--primary')),
        css('.ys-step-draw').styles(
          raw: {
            'animation': ysAnimations(
              firstStroke,
              keyframes,
              frames: YsStepMotion.drawStroke,
              fill: 'backwards',
            ),
          },
        ),
        css('.ys-step-disc').styles(
          raw: {
            'fill': 'var(--success-muted)',
            'transform-origin': '${ysNum(_size / 2)}px ${ysNum(_size / 2)}px',
            'animation': ysAnimations(
              calm.ring!,
              keyframes,
              frames: calm.frames,
              fill: 'backwards',
            ),
          },
        ),
        css('.ys-step-mark').styles(
          color: .variable('--success'),
          raw: {
            'transform-origin': '${ysNum(_size / 2)}px ${ysNum(_size / 2)}px',
            'animation': ysAnimations(
              calm.root!,
              keyframes,
              frames: calm.frames,
              fill: 'backwards',
            ),
          },
        ),
        css('.ys-step-label').styles(
          display: .block,
          maxWidth: 100.percent,
          margin: .only(top: YsSpace.xs.px),
          overflow: .hidden,
          color: .variable('--content-muted'),
          fontSize: YsType.caption.size.px,
          lineHeight: YsType.caption.lineHeight.px,
          textOverflow: .ellipsis,
          whiteSpace: .noWrap,
        ),
        css('[data-state="current"] .ys-step-label')
            .styles(color: .variable('--content')),
      ]),
    ];
    return [
      css.keyframes('ys-step-fill', {
        '0%': Styles(raw: {'scale': '0 1'}),
        '100%': Styles(raw: {'scale': '1 1'}),
      }),
      ...keyframes.rules,
      ...rules,
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-stepper *, .ys-step::after')
            .styles(raw: {'animation': 'none !important'}),
      ]),
    ];
  }
}
