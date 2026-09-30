import 'dart:math' as math;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// `@keyframes` steps as raw CSS declarations by percentage.
typedef YsSteps = Map<String, Map<String, String>>;

/// CSS declarations of [property] at [value]. Trims are drawn with stroke
/// dashes instead ([ysTrimSteps]).
Map<String, String> ysDeclare(YsMotionProperty property, double value) =>
    switch (property) {
      YsMotionProperty.translateY => {'translate': '0px ${ysNum(value)}px'},
      YsMotionProperty.rotate => {'rotate': '${ysNum(value)}deg'},
      YsMotionProperty.scale => {'scale': ysNum(value)},
      YsMotionProperty.scaleX => {'scale': '${ysNum(value)} 1'},
      YsMotionProperty.opacity => {'opacity': ysNum(value)},
      YsMotionProperty.trimStart ||
      YsMotionProperty.trimEnd => throw ArgumentError(property),
    };

/// Steps of [track] over the [frames] frames from [start]: one per keyframe
/// with its segment easing, the first and last values held at 0% and 100%.
YsSteps ysTrackSteps(
  YsMotionTrack track, {
  required double frames,
  double start = 0,
  Map<String, String> Function(YsMotionProperty, double) declare = ysDeclare,
}) {
  final steps = <String, Map<String, String>>{};
  final first = track.keyframes.first;
  final last = track.keyframes.last;
  if (first.frame > start) {
    steps['0%'] = declare(track.property, first.value);
  }
  for (final k in track.keyframes) {
    steps[_pct(k.frame - start, frames)] = {
      ...declare(track.property, k.value),
      'animation-timing-function': k.ease.css,
    };
  }
  if (last.frame < start + frames) {
    steps['100%'] = declare(track.property, last.value);
  }
  return steps;
}

/// Stroke dashes drawing the trim range of [part] over the [frames] frames
/// from [start]. The element needs `pathLength="1"` so dashes are fractions
/// of its length; trim start and end have independent keyframes and CSS
/// draws the range with one dash, so both are sampled every other frame.
YsSteps ysTrimSteps(
  YsPartMotion part, {
  required double frames,
  double start = 0,
}) {
  final end = start + frames;
  final samples = <double>{start, end};
  for (final property in const [
    YsMotionProperty.trimStart,
    YsMotionProperty.trimEnd,
  ]) {
    final track = part.track(property);
    if (track == null) continue;
    final a = track.keyframes.first.frame;
    final b = track.keyframes.last.frame;
    for (var f = a; f < b; f += 2) {
      samples.add(f);
    }
    for (final k in track.keyframes) {
      samples.add(k.frame);
    }
  }
  return {
    for (final f
        in samples.where((f) => f >= start && f <= end).toList()..sort())
      _pct(f - start, frames): () {
        final from = part.valueAt(YsMotionProperty.trimStart, f);
        final to = part.valueAt(YsMotionProperty.trimEnd, f);
        return {
          'stroke-dasharray': '${ysNum((to - from).clamp(0, 1))} 2',
          'stroke-dashoffset': ysNum(-from),
        };
      }(),
  };
}

/// The first and last frames [motion] animates.
(double, double) ysWindow(YsPartMotion motion) {
  var start = double.infinity;
  var end = double.negativeInfinity;
  for (final track in motion.tracks) {
    start = math.min(start, track.keyframes.first.frame);
    end = math.max(end, track.keyframes.last.frame);
  }
  return (start, end);
}

/// Whether [motion] moves its element (translate, rotate or scale), so its
/// transform origin matters.
bool ysTransforms(YsPartMotion motion) => motion.tracks.any(
  (track) => switch (track.property) {
    YsMotionProperty.translateY ||
    YsMotionProperty.rotate ||
    YsMotionProperty.scale ||
    YsMotionProperty.scaleX => true,
    _ => false,
  },
);

/// The `animation` list playing [motion] over the [frames] frames from
/// [start], after [delay] frames, [count] times (endlessly when [loop]) with
/// [fill]: one animation per transform or opacity track, one for its trim
/// range. Keyframes come from [keyframes].
String ysAnimations(
  YsPartMotion motion,
  YsKeyframeSet keyframes, {
  required double frames,
  double start = 0,
  double delay = 0,
  int count = 1,
  bool loop = false,
  String fill = 'none',
}) {
  String play(YsSteps steps) =>
      '${keyframes.name(steps)} ${ysFramesMs(frames)}ms linear '
      '${ysFramesMs(delay)}ms ${loop ? 'infinite' : count} $fill';
  return [
    for (final track in motion.tracks)
      if (!track.property.isTrim)
        play(ysTrackSteps(track, frames: frames, start: start)),
    if (motion.tracks.any((track) => track.property.isTrim))
      play(ysTrimSteps(motion, frames: frames, start: start)),
  ].join(', ');
}

/// Milliseconds of [frames] at 60 fps.
int ysFramesMs(double frames) => (frames * 1000 / 60).round();

/// [v] with at most three decimals and no trailing zeros.
String ysNum(double v) {
  var s = v.toStringAsFixed(3);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s == '-0' ? '0' : s;
}

/// `@keyframes [name]` playing [steps].
StyleRule ysKeyframes(String name, YsSteps steps) => css.keyframes(name, {
  for (final MapEntry(key: at, value: declarations) in steps.entries)
    at: Styles(raw: declarations),
});

String _pct(double frame, double frames) => '${ysNum(frame / frames * 100)}%';

/// `@keyframes` shared by every rule playing the same steps: each distinct
/// set of steps is emitted once, named [prefix] and its index.
final class YsKeyframeSet {
  YsKeyframeSet(this.prefix);

  final String prefix;
  final _names = <String, String>{};
  final _rules = <StyleRule>[];

  /// The `@keyframes` rules, in order of first use.
  List<StyleRule> get rules => _rules;

  /// Name of the keyframes playing [steps].
  String name(YsSteps steps) => _names.putIfAbsent('$steps', () {
    final name = '$prefix${_names.length}';
    _rules.add(ysKeyframes(name, steps));
    return name;
  });
}

/// Rules with the same declarations, emitted as one rule per distinct set
/// of declarations with all their selectors.
final class YsRuleSet {
  final _rules = <String, (List<String>, Map<String, String>)>{};

  void add(String selector, Map<String, String> declarations) =>
      (_rules['$declarations'] ??= ([], declarations)).$1.add(selector);

  List<StyleRule> get rules => [
    for (final (selectors, declarations) in _rules.values)
      css(selectors.join(', ')).styles(raw: declarations),
  ];
}

final _tag = RegExp(r'^<(\w+)');
final _attribute = RegExp(r'([\w-]+)="([^"]*)"');

/// DOM element for one `<path .../>`-style markup string, with [classes].
/// [trimmed] elements get `pathLength="1"` so dash offsets are length
/// fractions.
Component ysSvgElement(
  String markup, {
  String? classes,
  bool trimmed = false,
  Styles? styles,
}) => Component.element(
  tag: _tag.firstMatch(markup)!.group(1)!,
  classes: classes,
  styles: styles,
  attributes: {
    for (final m in _attribute.allMatches(markup)) m.group(1)!: m.group(2)!,
    if (trimmed) 'pathLength': '1',
  },
);
