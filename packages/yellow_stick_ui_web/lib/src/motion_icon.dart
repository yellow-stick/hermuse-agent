import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// An icon that plays its [YsIconMotion] once each time [hovered] turns on
/// (rail destinations). Icons without a motion render still.
///
/// The playthrough always completes, even if the pointer leaves early. The
/// SVG is real DOM (not raw HTML) so rebuilds of the hosting pressable keep
/// the running animation.
class YsMotionIconView extends StatefulComponent {
  const YsMotionIconView(
    this.icon, {
    this.size = 18,
    this.strokeWidth = 1.75,
    this.hovered = false,
    super.key,
  });

  final YsIcon icon;
  final double size;
  final double strokeWidth;

  /// Pointer over the host control; a rising edge starts the animation.
  final bool hovered;

  @override
  State<YsMotionIconView> createState() => _YsMotionIconViewState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-motion svg').styles(
      width: 100.percent,
      height: 100.percent,
      display: .block,
      raw: {'overflow': 'visible'},
    ),
    css('.ys-motion .ys-m-extra').styles(opacity: 0),
    for (final icon in YsIcon.values) ...?_motionRules(icon),
    css.media(MediaQuery.raw('(prefers-reduced-motion: reduce)'), [
      css('.ys-motion[data-playing] *').styles(raw: {'animation': 'none'}),
    ]),
  ];
}

class _YsMotionIconViewState extends State<YsMotionIconView> {
  var _playing = false;

  @override
  void didUpdateComponent(YsMotionIconView oldComponent) {
    super.didUpdateComponent(oldComponent);
    if (!oldComponent.hovered &&
        component.hovered &&
        !_playing &&
        YsIconMotion.of(component.icon) != null) {
      setState(() => _playing = true);
    }
  }

  @override
  Component build(BuildContext context) {
    final icon = component.icon;
    final motion = YsIconMotion.of(icon);
    final elements = motion?.elements ?? ysSvgElements(icon.body);
    final bodyCount = motion?.bodyCount ?? elements.length;
    return span(
      classes: 'ys-icon ys-motion',
      styles: Styles(width: component.size.px, height: component.size.px),
      attributes: {if (_playing) 'data-playing': ''},
      events: {
        // Every track of an icon lasts the full motion, so the first end
        // event is the end of the playthrough; a cancel (element hidden)
        // must not leave the icon stuck in the playing state.
        'animationend': (_) {
          if (_playing) setState(() => _playing = false);
        },
        'animationcancel': (_) {
          if (_playing) setState(() => _playing = false);
        },
      },
      [
        Component.element(
          tag: 'svg',
          attributes: {
            'viewBox': '0 0 24 24',
            'fill': 'none',
            'stroke': 'currentColor',
            'stroke-width': '${component.strokeWidth}',
            'stroke-linecap': 'round',
            'stroke-linejoin': 'round',
            'aria-hidden': 'true',
          },
          children: [
            Component.element(
              tag: 'g',
              classes: 'ys-m-${icon.name}-root',
              children: [
                for (var i = 0; i < elements.length; i++)
                  Component.element(
                    tag: 'g',
                    classes: [
                      'ys-m-${icon.name}-p$i',
                      if (i >= bodyCount) 'ys-m-extra',
                    ].join(' '),
                    children: [
                      _element(
                        elements[i],
                        trimmed:
                            motion?.part(i)?.track(YsMotionProperty.trimEnd) !=
                            null,
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

  static final _tag = RegExp(r'^<(\w+)');
  static final _attribute = RegExp(r'([\w-]+)="([^"]*)"');

  /// DOM element for one `<path .../>`-style markup string. [trimmed] paths
  /// get `pathLength="1"` so dash offsets are length fractions.
  static Component _element(String markup, {required bool trimmed}) =>
      Component.element(
        tag: _tag.firstMatch(markup)!.group(1)!,
        attributes: {
          for (final m in _attribute.allMatches(markup))
            m.group(1)!: m.group(2)!,
          if (trimmed) 'pathLength': '1',
        },
      );
}

/// Base + playing rules and keyframes of [icon]'s motion.
List<StyleRule>? _motionRules(YsIcon icon) {
  final motion = YsIconMotion.of(icon);
  if (motion == null) return null;
  final ms = motion.durationMs;
  final rules = <StyleRule>[];
  for (final part in motion.parts) {
    final id = part.part == null ? 'root' : 'p${part.part}';
    final cls = 'ys-m-${icon.name}-$id';
    final animations = <String>[];
    for (final track in part.tracks) {
      if (track.property.isTrim) continue;
      final name = '$cls-${track.property.name}';
      animations.add('$name ${ms}ms linear both');
      rules.add(
        css.keyframes(name, _keyframes(motion.frames, track, _declare)),
      );
    }
    final trimEnd = part.track(YsMotionProperty.trimEnd);
    if (trimEnd != null) {
      final name = '$cls-trim';
      animations.add('$name ${ms}ms linear both');
      rules.add(css.keyframes(name, _trimKeyframes(motion, part)));
    }
    rules
      ..add(
        css('.ys-motion .$cls').styles(
          raw: {
            'transform-box': 'view-box',
            'transform-origin': '${part.originX}px ${part.originY}px',
          },
        ),
      )
      ..add(
        css('.ys-motion[data-playing] .$cls')
            .styles(raw: {'animation': animations.join(', ')}),
      );
  }
  return rules;
}

/// CSS declarations of [property] at [value].
Map<String, String> _declare(YsMotionProperty property, double value) =>
    switch (property) {
      YsMotionProperty.translateY => {'translate': '0px ${_n(value)}px'},
      YsMotionProperty.rotate => {'rotate': '${_n(value)}deg'},
      YsMotionProperty.scale => {'scale': _n(value)},
      YsMotionProperty.scaleX => {'scale': '${_n(value)} 1'},
      YsMotionProperty.opacity => {'opacity': _n(value)},
      YsMotionProperty.trimStart ||
      YsMotionProperty.trimEnd => throw ArgumentError(property),
    };

/// `@keyframes` steps of [track]: one per keyframe with its segment easing,
/// holding the first/last value at 0% / 100%.
Map<String, Styles> _keyframes(
  double frames,
  YsMotionTrack track,
  Map<String, String> Function(YsMotionProperty, double) declare,
) {
  final steps = <String, Styles>{};
  final first = track.keyframes.first;
  final last = track.keyframes.last;
  if (first.frame > 0) {
    steps['0%'] = Styles(raw: declare(track.property, first.value));
  }
  for (final k in track.keyframes) {
    steps[_pct(k.frame, frames)] = Styles(
      raw: {
        ...declare(track.property, k.value),
        'animation-timing-function': k.ease.css,
      },
    );
  }
  if (last.frame < frames) {
    steps['100%'] = Styles(raw: declare(track.property, last.value));
  }
  return steps;
}

/// Trim start/end have independent keyframes; CSS draws the range with one
/// dash (`pathLength="1"`), so both are sampled every other frame.
Map<String, Styles> _trimKeyframes(YsIconMotion motion, YsPartMotion part) {
  final frames = <double>{0, motion.frames};
  for (final p in const [
    YsMotionProperty.trimStart,
    YsMotionProperty.trimEnd,
  ]) {
    final track = part.track(p);
    if (track == null) continue;
    final a = track.keyframes.first.frame;
    final b = track.keyframes.last.frame;
    for (var f = a; f < b; f += 2) {
      frames.add(f);
    }
    for (final k in track.keyframes) {
      frames.add(k.frame);
    }
  }
  final sorted = frames.toList()..sort();
  return {
    for (final f in sorted)
      _pct(f, motion.frames): () {
        final start = part.valueAt(YsMotionProperty.trimStart, f);
        final end = part.valueAt(YsMotionProperty.trimEnd, f);
        return Styles(
          raw: {
            'stroke-dasharray': '${_n((end - start).clamp(0, 1))} 2',
            'stroke-dashoffset': _n(-start),
          },
        );
      }(),
  };
}

String _pct(double frame, double frames) => '${_n(frame / frames * 100)}%';

String _n(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}
