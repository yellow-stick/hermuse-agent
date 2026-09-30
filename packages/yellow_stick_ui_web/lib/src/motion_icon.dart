import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'keyframes.dart';
import 'motion.dart';

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
    // Per-part rules are more specific: this one must still win.
    css.media(MediaQuery.raw(ysReducedMotionQuery), [
      css('.ys-motion[data-playing] *')
          .styles(raw: {'animation': 'none !important'}),
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
        YsIconMotion.of(component.icon) != null &&
        !ysReducedMotion()) {
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
                      ysSvgElement(
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
      rules.add(ysKeyframes(name, ysTrackSteps(track, frames: motion.frames)));
    }
    final trimEnd = part.track(YsMotionProperty.trimEnd);
    if (trimEnd != null) {
      final name = '$cls-trim';
      animations.add('$name ${ms}ms linear both');
      rules.add(ysKeyframes(name, ysTrimSteps(part, frames: motion.frames)));
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
