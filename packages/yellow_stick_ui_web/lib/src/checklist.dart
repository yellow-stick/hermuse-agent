import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'burst.dart';
import 'keyframes.dart';
import 'motion.dart';

/// How a [YsChecklistNote] reads.
enum YsNoteTone {
  /// Explanations.
  muted,

  /// Warnings and errors.
  alert,
}

/// A line under a checklist row that needs the user, failed or waits on
/// another step: what a change does, what it waits for, a warning, an error.
class YsChecklistNote {
  const YsChecklistNote(
    this.text, {
    this.caption,
    this.tone = YsNoteTone.muted,
  });

  final String text;

  /// Short heading above [text] ("Root access").
  final String? caption;
  final YsNoteTone tone;
}

/// One row of a [YsChecklist].
class YsChecklistItem {
  const YsChecklistItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.state,
    this.status = '',
    this.progress,
    this.trailing,
    this.notes = const [],
    this.actions = const [],
  });

  /// Stable identity across rebuilds: the row keeps its element.
  final String id;
  final YsIcon icon;
  final String title;
  final YsStepState state;

  /// One line under the title.
  final String status;

  /// Share done of a [YsStepState.working] row, 0..1; null when unknown.
  final double? progress;

  /// A short caption at the end of the title line (`4/10`).
  final String? trailing;

  /// Lines under the status of a row that needs the user, failed or waits
  /// on another step.
  final List<YsChecklistNote> notes;

  /// Buttons of a row that needs the user, failed or waits on another step
  /// (disabled then: what it will do), one per line under its notes.
  final List<Component> actions;

  /// Whether the row shows its [notes] and [actions].
  bool get expanded =>
      state == YsStepState.needsAction ||
      state == YsStepState.failed ||
      state == YsStepState.pending;
}

/// A vertical checklist of setup steps (Flutter `YsChecklist` parity): each
/// row a [YsStepBadge], a title and a one-line status. A row that needs the
/// user takes an accent wash, a failed one an error wash; both unfold their
/// notes and actions, as does a row waiting on another step. A row that
/// reaches done sends sparks out of its badge. Rows enter one after the
/// other ([YsStepMotion.stagger]); a new status fades in.
///
/// With reduced motion rows appear and change at once.
class YsChecklist extends StatefulComponent {
  const YsChecklist({required this.items, super.key});

  final List<YsChecklistItem> items;

  @override
  State<YsChecklist> createState() => _YsChecklistState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css.keyframes('ys-check-enter', {
      '0%': Styles(
        opacity: 0,
        raw: {'translate': '0px ${ysNum(YsStepMotion.rise)}px'},
      ),
      '100%': Styles(opacity: 1, raw: {'translate': '0px 0px'}),
    }),
    css.keyframes('ys-check-swap', {
      '0%': Styles(opacity: 0),
      '100%': Styles(opacity: 1),
    }),
    css('.ys-checklist', [
      css('&').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(YsSpace.xs.px),
        padding: .zero,
        margin: .zero,
        listStyle: .none,
      ),
      css('.ys-check').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .start,
        gap: .all(YsSpace.md.px),
        padding: .all(YsSpace.sm.px),
        radius: .circular(YsRadius.row.px),
        backgroundColor: Colors.transparent,
        raw: {
          'transition':
              'background-color ${YsStepMotion.swap}ms ${YsEase.standard.css}, '
              'opacity ${YsStepMotion.swap}ms ${YsEase.standard.css}',
          'animation':
              'ys-check-enter ${YsStepMotion.enter}ms '
              '${YsEase.settle.css} backwards',
        },
      ),
      css('.ys-check[data-state="needsAction"]')
          .styles(backgroundColor: .variable('--primary-wash')),
      css('.ys-check[data-state="failed"]')
          .styles(backgroundColor: .variable('--error-wash')),
      css('.ys-check[data-state="skipped"]').styles(opacity: 0.7),
      css('.ys-check-body').styles(
        display: .flex,
        flexDirection: .column,
        flex: .grow(1),
        raw: {'min-width': '0'},
      ),
      css('.ys-check-line').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .baseline,
        gap: .all(YsSpace.sm.px),
      ),
      css('.ys-check-title').styles(
        flex: .grow(1),
        overflow: .hidden,
        color: .variable('--content'),
        fontSize: YsType.label.size.px,
        fontWeight: .w500,
        lineHeight: YsType.label.lineHeight.px,
        textOverflow: .ellipsis,
        whiteSpace: .noWrap,
        raw: {
          'min-width': '0',
          'transition': 'color ${YsStepMotion.swap}ms ${YsEase.standard.css}',
        },
      ),
      css('.ys-check[data-state="pending"] .ys-check-title')
          .styles(color: .variable('--content-muted')),
      css('.ys-check[data-state="skipped"] .ys-check-title')
          .styles(color: .variable('--content-subtle')),
      css('.ys-check-trailing').styles(
        color: .variable('--content-subtle'),
        fontSize: YsType.caption.size.px,
        lineHeight: YsType.caption.lineHeight.px,
        raw: {'font-variant-numeric': 'tabular-nums', 'flex-shrink': '0'},
      ),
      css('.ys-check-status').styles(
        display: .block,
        overflow: .hidden,
        color: .variable('--content-muted'),
        fontSize: YsType.small.size.px,
        lineHeight: YsType.small.lineHeight.px,
        textOverflow: .ellipsis,
        whiteSpace: .noWrap,
        raw: {
          'animation':
              'ys-check-swap ${YsStepMotion.swap}ms ${YsEase.standard.css} '
              'backwards',
        },
      ),
      css('.ys-check[data-state="needsAction"] .ys-check-status')
          .styles(color: .variable('--primary-ink')),
      css('.ys-check[data-state="failed"] .ys-check-status')
          .styles(color: .variable('--error')),
      css(
        '.ys-check[data-state="pending"] .ys-check-status, '
        '.ys-check[data-state="skipped"] .ys-check-status',
      ).styles(color: .variable('--content-subtle')),
      // Notes and actions come in with the page motion.
      css('.ys-check-more').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .start,
        raw: {
          'animation':
              'ys-check-enter ${YsStepMotion.resize}ms '
              '${YsEase.standard.css} backwards',
        },
      ),
      css('.ys-check-note').styles(
        display: .flex,
        flexDirection: .column,
        margin: .only(top: YsSpace.sm.px),
        color: .variable('--content-muted'),
      ),
      css('.ys-check-note[data-tone="alert"]')
          .styles(color: .variable('--error')),
      css('.ys-check-note-caption').styles(
        fontSize: YsType.caption.size.px,
        lineHeight: YsType.caption.lineHeight.px,
      ),
      css('.ys-check-note-text').styles(
        fontSize: YsType.small.size.px,
        lineHeight: YsType.small.lineHeight.px,
        raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'anywhere'},
      ),
      css('.ys-check-action').styles(
        display: .flex,
        margin: .only(top: YsSpace.md.px),
        raw: {'max-width': '100%'},
      ),
    ]),
    css.media(MediaQuery.raw(ysReducedMotionQuery), [
      css('.ys-check, .ys-check-status, .ys-check-more')
          .styles(raw: {'animation': 'none', 'transition': 'none'}),
    ]),
  ];
}

class _YsChecklistState extends State<YsChecklist> {
  /// Entrance delay of each row, staggered among the rows that appeared
  /// together.
  final _delays = <String, int>{};

  @override
  void initState() {
    super.initState();
    _stagger(const {});
  }

  @override
  void didUpdateComponent(YsChecklist oldComponent) {
    super.didUpdateComponent(oldComponent);
    _stagger({for (final item in oldComponent.items) item.id});
  }

  void _stagger(Set<String> shown) {
    final ids = {for (final item in component.items) item.id};
    _delays.removeWhere((id, _) => !ids.contains(id));
    var fresh = 0;
    for (final id in ids) {
      if (shown.contains(id)) continue;
      _delays[id] = YsStepMotion.stagger * fresh++;
    }
  }

  @override
  Component build(BuildContext context) => ul(classes: 'ys-checklist', [
    for (final item in component.items)
      _Row(key: ValueKey(item.id), item: item, delay: _delays[item.id] ?? 0),
  ]);
}

class _Row extends StatelessComponent {
  const _Row({required this.item, required this.delay, super.key});

  final YsChecklistItem item;

  /// Milliseconds before the row enters.
  final int delay;

  @override
  Component build(BuildContext context) {
    final trailing = item.trailing;
    final unfolded =
        item.expanded && (item.notes.isNotEmpty || item.actions.isNotEmpty);
    return li(
      classes: 'ys-check',
      styles: Styles(raw: {'animation-delay': '${delay}ms'}),
      attributes: {'data-state': item.state.name},
      [
        // Sparks when the step completes here, not when it shows done.
        YsBurstView(
          play: item.state == YsStepState.done,
          child: YsStepBadge(
            state: item.state,
            icon: item.icon,
            progress: item.progress,
          ),
        ),
        div(classes: 'ys-check-body', [
          div(classes: 'ys-check-line', [
            span(classes: 'ys-check-title', [.text(item.title)]),
            if (trailing != null)
              span(classes: 'ys-check-trailing', [.text(trailing)]),
          ]),
          // A new status is a new element: it fades in.
          span(
            key: ValueKey('${item.state.name}:${item.status}'),
            classes: 'ys-check-status',
            [.text(item.status)],
          ),
          if (unfolded)
            div(key: const ValueKey('more'), classes: 'ys-check-more', [
              for (final note in item.notes)
                div(
                  classes: 'ys-check-note',
                  attributes: {'data-tone': note.tone.name},
                  [
                    if (note.caption case final caption?)
                      span(classes: 'ys-check-note-caption', [.text(caption)]),
                    span(classes: 'ys-check-note-text', [.text(note.text)]),
                  ],
                ),
              // One button per line: each label stays alone on its line.
              for (final action in item.actions)
                div(classes: 'ys-check-action', [action]),
            ]),
        ]),
      ],
    );
  }
}

/// The animated status badge of a setup step (Flutter `YsStepBadge`
/// parity): [icon] in a ring that scans while checking, sweeps while
/// working (filling to [progress] when known) and turns accent when the step
/// needs the user. A settled or failed step plays its [YsStepState.mark] in
/// once; a new badge draws its glyph in, stroke after stroke, and so does a
/// step coming back from a mark (a retry). Ring colours ease between states.
///
/// With reduced motion every state shows its final look at once and nothing
/// loops. Decorative: the row's text says the state.
class YsStepBadge extends StatefulComponent {
  const YsStepBadge({
    required this.state,
    required this.icon,
    this.progress,
    super.key,
  });

  final YsStepState state;
  final YsIcon icon;

  /// Share of a [YsStepState.working] step done, 0..1; null when unknown.
  final double? progress;

  @override
  State<YsStepBadge> createState() => _YsStepBadgeState();

  static const _size = YsLayout.stepBadge;
  static const _center = _size / 2;

  /// Side of the glyph inside the badge, and its offset from the badge edge.
  static const _glyph = _size * YsLayout.stepGlyph / YsLayout.stepBadge;
  static const _inset = (_size - _glyph) / 2;

  @css
  // ignore: unused_element
  static List<StyleRule> get styles {
    final keyframes = YsKeyframeSet('ys-sb-k');
    final firstStroke = YsStepMotion.drawIn(1).single;
    final origin = '${ysNum(_center)}px ${ysNum(_center)}px';
    String state(String name) => '.ys-sb[data-state="$name"]';
    String play(YsPartMotion motion, YsStepMark mark) =>
        ysAnimations(motion, keyframes, frames: mark.frames, fill: 'backwards');
    const tick = YsStepMark.tick;
    const calm = YsStepMark.calmTick;
    const cross = YsStepMark.cross;
    const dash = YsStepMark.dash;
    final ease = YsEase.standard.css;
    final swap = '${YsStepMotion.swap}ms $ease';
    final rules = [
      css('.ys-sb', [
        css('&').styles(
          display: .block,
          raw: {'flex-shrink': '0', 'overflow': 'visible'},
        ),
        css('*').styles(raw: {'transform-box': 'view-box'}),
        css('.ys-sb-track').styles(
          raw: {
            'stroke': 'var(--line)',
            'stroke-width': ysNum(ysHairline),
            'transition': 'stroke $swap, stroke-width $swap',
          },
        ),
        css('.ys-sb-arc').styles(
          raw: {
            'stroke': 'transparent',
            'stroke-width': ysNum(YsLayout.stepRingStroke),
            'stroke-dasharray': '0 2',
            'rotate': '-90deg',
            'transform-origin': origin,
          },
        ),
        css('.ys-sb-disc').styles(
          raw: {'fill': 'var(--info-muted)', 'transform-origin': origin},
        ),
        css('.ys-sb-glyph').styles(
          color: .variable('--content-subtle'),
          raw: {'transition': 'color $swap', 'transform-origin': origin},
        ),
        css('.ys-sb-draw').styles(
          raw: {
            'animation': ysAnimations(
              firstStroke,
              keyframes,
              frames: YsStepMotion.drawStroke,
              fill: 'backwards',
            ),
          },
        ),
      ]),
      // Checking: a short arc scans the ring while the glyph breathes.
      css(state('checking'), [
        css('.ys-sb-arc').styles(
          raw: {
            'stroke': 'var(--content-muted)',
            'stroke-dasharray': '0.28 2',
            'animation': 'ys-sb-turn ${YsStepMotion.pulse}ms linear infinite',
          },
        ),
        css('.ys-sb-glyph').styles(
          color: .variable('--content-muted'),
          raw: {
            'animation':
                'ys-sb-breathe ${YsStepMotion.pulse}ms ease-in-out infinite',
          },
        ),
      ]),
      // Working: an arc turns while it breathes, or fills to its progress.
      css(state('working'), [
        css('.ys-sb-track').styles(
          raw: {
            'stroke': 'var(--neutral-film)',
            'stroke-width': ysNum(YsLayout.stepRingStroke),
          },
        ),
        css('.ys-sb-arc').styles(
          raw: {
            'stroke': 'var(--primary-ink)',
            'stroke-dasharray': '0.2 2',
            'animation':
                'ys-sb-turn ${YsStepMotion.spin}ms linear infinite, '
                'ys-sb-sweep ${YsStepMotion.spin}ms ease-in-out infinite',
          },
        ),
        css('.ys-sb-glyph').styles(color: .variable('--content')),
      ]),
      css('${state('working')}[data-progress] .ys-sb-arc').styles(
        raw: {
          'animation': 'none',
          'transition': 'stroke-dasharray ${YsStepMotion.progress}ms $ease',
        },
      ),
      css(state('needsAction'), [
        css('.ys-sb-track').styles(
          raw: {
            'stroke': 'var(--primary-ink)',
            'stroke-width': ysNum(YsLayout.stepRingStroke),
          },
        ),
        css('.ys-sb-glyph').styles(color: .variable('--primary-ink')),
      ]),
      // Done now: the ring closes, then the tick draws.
      css(state('done'), [
        css('.ys-sb-track').styles(raw: {'stroke': 'transparent'}),
        css('.ys-sb-arc').styles(
          raw: {
            'stroke': 'var(--success)',
            'stroke-dasharray': 'none',
            'animation': play(tick.ring!, tick),
          },
        ),
        css('.ys-sb-glyph').styles(color: .variable('--success')),
        css('.ys-sb-m0').styles(raw: {'animation': play(tick.part(0)!, tick)}),
      ]),
      // Found (already in place): a soft blue disc grows behind a calm tick.
      css(state('found'), [
        css('.ys-sb-track').styles(raw: {'stroke': 'transparent'}),
        css('.ys-sb-disc').styles(raw: {'animation': play(calm.ring!, calm)}),
        css('.ys-sb-glyph').styles(
          color: .variable('--info'),
          raw: {'animation': play(calm.root!, calm)},
        ),
      ]),
      // Failed: the ring fades in, the cross draws, then shakes its head.
      css(state('failed'), [
        css('.ys-sb-track').styles(
          raw: {
            'stroke': 'var(--error)',
            'stroke-width': ysNum(YsLayout.stepRingStroke),
            'animation': play(cross.ring!, cross),
          },
        ),
        css('.ys-sb-glyph').styles(
          color: .variable('--error'),
          raw: {'animation': play(cross.root!, cross)},
        ),
        for (var i = 0; i < 2; i++)
          css('.ys-sb-m$i')
              .styles(raw: {'animation': play(cross.part(i)!, cross)}),
      ]),
      css(state('skipped'), [
        css('.ys-sb-m0').styles(raw: {'animation': play(dash.part(0)!, dash)}),
      ]),
    ];
    return [
      css.keyframes('ys-sb-turn', {
        '0%': Styles(raw: {'rotate': '-90deg'}),
        '100%': Styles(raw: {'rotate': '270deg'}),
      }),
      // The arc breathes from a fifth to two thirds of the ring.
      css.keyframes('ys-sb-sweep', {
        '0%': Styles(raw: {'stroke-dasharray': '0.2 2'}),
        '50%': Styles(raw: {'stroke-dasharray': '0.66 2'}),
        '100%': Styles(raw: {'stroke-dasharray': '0.2 2'}),
      }),
      // One breath per cycle, from full strength down to 55 %.
      css.keyframes('ys-sb-breathe', {
        '0%': Styles(opacity: 1),
        '50%': Styles(opacity: 0.55),
        '100%': Styles(opacity: 1),
      }),
      ...keyframes.rules,
      ...rules,
      css.media(MediaQuery.raw(ysReducedMotionQuery), [
        css('.ys-sb, .ys-sb *').styles(
          raw: {
            'animation': 'none !important',
            'transition': 'none !important',
          },
        ),
      ]),
    ];
  }
}

class _YsStepBadgeState extends State<YsStepBadge> {
  /// Bumped each time the glyph draws in again: a new element replays it.
  var _drawn = 0;

  @override
  void didUpdateComponent(YsStepBadge oldComponent) {
    super.didUpdateComponent(oldComponent);
    // The glyph draws in again when it comes back from a mark (a retry).
    if (oldComponent.state.mark != null ||
        oldComponent.icon != component.icon) {
      _drawn++;
    }
  }

  @override
  Component build(BuildContext context) {
    const size = YsStepBadge._size;
    const center = YsStepBadge._center;
    final state = component.state;
    final mark = state.mark;
    final progress = component.progress;
    final working = state == YsStepState.working && progress != null;
    final elements = ysSvgElements(mark?.body ?? component.icon.body);
    final drawIn = YsStepMotion.drawIn(elements.length);
    Component ring(String classes, {Key? key, Styles? styles}) =>
        Component.element(
          tag: 'circle',
          key: key,
          classes: classes,
          styles: styles,
          attributes: {
            'cx': ysNum(center),
            'cy': ysNum(center),
            'r': ysNum((size - YsLayout.stepRingStroke) / 2),
            'pathLength': '1',
          },
        );
    return Component.element(
      tag: 'svg',
      classes: 'ys-sb',
      attributes: {
        'viewBox': '0 0 ${ysNum(size)} ${ysNum(size)}',
        'width': ysNum(size),
        'height': ysNum(size),
        'fill': 'none',
        'stroke-linecap': 'round',
        'stroke-linejoin': 'round',
        'aria-hidden': 'true',
        'data-state': state.name,
        if (working) 'data-progress': '',
      },
      children: [
        if (state == YsStepState.found)
          Component.element(
            tag: 'circle',
            key: const ValueKey('disc'),
            classes: 'ys-sb-disc',
            attributes: {
              'cx': ysNum(center),
              'cy': ysNum(center),
              'r': ysNum(center),
            },
          ),
        ring('ys-sb-track'),
        // A new element per state: its motion starts with the state.
        ring(
          'ys-sb-arc',
          key: ValueKey('arc-${state.name}'),
          styles: working
              ? Styles(
                  raw: {
                    'stroke-dasharray': '${ysNum(progress.clamp(0.02, 1.0))} 2',
                  },
                )
              : null,
        ),
        Component.element(
          tag: 'g',
          key: ValueKey(mark == null ? 'glyph-$_drawn' : 'mark-${state.name}'),
          classes: 'ys-sb-glyph',
          children: [
            Component.element(
              tag: 'svg',
              attributes: {
                'x': ysNum(YsStepBadge._inset),
                'y': ysNum(YsStepBadge._inset),
                'width': ysNum(YsStepBadge._glyph),
                'height': ysNum(YsStepBadge._glyph),
                'viewBox': '0 0 24 24',
                'stroke': 'currentColor',
                'stroke-width': ysNum(YsLayout.stepGlyphStroke),
              },
              children: [
                for (final (i, markup) in elements.indexed)
                  mark != null
                      ? ysSvgElement(
                          markup,
                          classes: 'ys-sb-m$i',
                          trimmed: true,
                        )
                      : ysSvgElement(
                          markup,
                          classes: 'ys-sb-draw',
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
}
