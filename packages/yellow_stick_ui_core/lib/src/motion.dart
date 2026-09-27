import 'icons.dart';

/// Cubic-bezier easing, same control points as CSS `cubic-bezier()`.
final class YsEase {
  const YsEase(this.x1, this.y1, this.x2, this.y2);

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  static const linear = YsEase(0, 0, 1, 1);

  /// Hover/press fills (Material "standard", Tailwind default).
  static const standard = YsEase(0.4, 0, 0.2, 1);

  /// Symmetric ease-in-out used by most icon keyframes.
  static const smooth = YsEase(0.333, 0, 0.667, 1);

  /// Near-linear segment between two keyframes of a continuous move.
  static const drift = YsEase(0.167, 0.167, 0.833, 0.833);

  /// CSS `animation-timing-function` / `transition-timing-function` value.
  String get css => 'cubic-bezier($x1, $y1, $x2, $y2)';

  /// Eased progress for linear progress [t] in 0..1.
  double transform(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    if (x1 == y1 && x2 == y2) return t;
    // Solve bx(s) = t for the curve parameter s (bisection: bx is monotonic
    // because x1, x2 are within 0..1), then return by(s).
    var lo = 0.0;
    var hi = 1.0;
    var s = t;
    for (var i = 0; i < 24; i++) {
      final x = _bezier(s, x1, x2);
      if ((x - t).abs() < 1e-5) break;
      if (x < t) {
        lo = s;
      } else {
        hi = s;
      }
      s = (lo + hi) / 2;
    }
    return _bezier(s, y1, y2);
  }

  static double _bezier(double s, double p1, double p2) {
    final u = 1 - s;
    return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s;
  }
}

/// One keyframe: [value] reached at [frame] (60 fps). [ease] shapes the
/// segment that starts here, like a CSS keyframe's timing function.
final class YsKeyframe {
  const YsKeyframe(this.frame, this.value, [this.ease = YsEase.smooth]);

  final double frame;
  final double value;
  final YsEase ease;
}

/// Animatable property of an icon part. Transforms apply in CSS
/// individual-transform order (translate, rotate, scale) around the part's
/// origin.
enum YsMotionProperty {
  /// Vertical offset, viewBox units.
  translateY(0),

  /// Degrees, clockwise.
  rotate(0),

  /// Uniform scale.
  scale(1),

  /// Horizontal scale only (flip).
  scaleX(1),

  opacity(1),

  /// Visible stroke range as fractions of the path length (path parts only).
  trimStart(0),
  trimEnd(1);

  const YsMotionProperty(this.rest);

  /// Value when the icon is idle.
  final double rest;

  bool get isTrim => this == trimStart || this == trimEnd;
}

/// Keyframes of one property.
final class YsMotionTrack {
  const YsMotionTrack(this.property, this.keyframes);

  final YsMotionProperty property;
  final List<YsKeyframe> keyframes;

  /// Value at [frame]; holds the first/last keyframe outside their range.
  double valueAt(double frame) {
    final first = keyframes.first;
    if (frame <= first.frame) return first.value;
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (frame < b.frame) {
        final t = a.ease.transform((frame - a.frame) / (b.frame - a.frame));
        return a.value + (b.value - a.value) * t;
      }
    }
    return keyframes.last.value;
  }
}

/// Motion of one SVG element of an icon ([part] indexes
/// [YsIconMotion.elements]) or of the whole glyph ([part] null).
final class YsPartMotion {
  const YsPartMotion({
    this.part,
    required this.originX,
    required this.originY,
    required this.tracks,
  });

  final int? part;

  /// Transform origin, viewBox units.
  final double originX;
  final double originY;

  final List<YsMotionTrack> tracks;

  YsMotionTrack? track(YsMotionProperty property) {
    for (final t in tracks) {
      if (t.property == property) return t;
    }
    return null;
  }

  /// [property] at [frame], or its rest value when not animated.
  double valueAt(YsMotionProperty property, double frame) =>
      track(property)?.valueAt(frame) ?? property.rest;
}

/// A one-shot hover animation of a rail icon, played from frame 0 to
/// [frames] at 60 fps each time the pointer enters the item.
///
/// Motion is authored for the Lucide geometry of [YsIcon] and animates the
/// rail (bubble bounce with typing dots, feed scroll, bulb swing
/// with a shine stroke, checkbox wobble with the tick redrawn, library
/// shapes flipping in turn).
final class YsIconMotion {
  YsIconMotion._({
    required this.icon,
    required this.frames,
    required this.parts,
    this.extras = '',
  });

  final YsIcon icon;

  /// Length in frames (60 fps).
  final double frames;

  /// Elements appended after the icon body, invisible at rest (typing dots,
  /// shine stroke). Their parts must animate [YsMotionProperty.opacity].
  final String extras;

  final List<YsPartMotion> parts;

  int get durationMs => (frames * 1000 / 60).round();

  /// Top-level SVG elements: the icon body, then [extras].
  List<String> get elements => ysSvgElements(icon.body + extras);

  /// Number of elements coming from the icon body (the rest are extras).
  int get bodyCount => ysSvgElements(icon.body).length;

  /// Motion of the whole glyph, if any.
  YsPartMotion? get root => _find(null);

  /// Motion of element [index], if any.
  YsPartMotion? part(int index) => _find(index);

  YsPartMotion? _find(int? index) {
    for (final p in parts) {
      if (p.part == index) return p;
    }
    return null;
  }

  /// Hover animation of [icon], or null for icons that stay still.
  static YsIconMotion? of(YsIcon icon) => switch (icon) {
    YsIcon.chat => _chat,
    YsIcon.feed => _feed,
    YsIcon.ideas => _ideas,
    YsIcon.goals => _goals,
    YsIcon.library => _library,
    _ => null,
  };

  static final _chat = YsIconMotion._(
    icon: YsIcon.chat,
    frames: 65,
    extras:
        '<circle cx="8" cy="12" r="1.25" fill="currentColor" stroke="none"/>'
        '<circle cx="12" cy="12" r="1.25" fill="currentColor" stroke="none"/>'
        '<circle cx="16" cy="12" r="1.25" fill="currentColor" stroke="none"/>',
    parts: [
      // Bubble hops and rocks on its tail.
      YsPartMotion(
        originX: 4,
        originY: 20,
        tracks: [
          YsMotionTrack(YsMotionProperty.translateY, [
            YsKeyframe(5, 0, YsEase(0.551, 0, 0.667, 1)),
            YsKeyframe(13, -0.7),
            YsKeyframe(29, 0.38, YsEase(0.333, 0, 0.236, 1)),
            YsKeyframe(52, 0),
          ]),
          YsMotionTrack(YsMotionProperty.rotate, [
            YsKeyframe(5, 0, YsEase(0.167, 0, 0.833, 1)),
            YsKeyframe(8, 1, YsEase(0.167, 0.087, 0.667, 1)),
            YsKeyframe(16, -2.5),
            YsKeyframe(32, 2, YsEase(0.333, 0, 0.236, 1)),
            YsKeyframe(55, 0),
          ]),
        ],
      ),
      _chatDot(1, 0),
      _chatDot(2, 2),
      _chatDot(3, 4),
    ],
  );

  static final _feed = YsIconMotion._(
    icon: YsIcon.feed,
    frames: 65,
    parts: [
      YsPartMotion(
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.translateY, [
            YsKeyframe(5, 0),
            YsKeyframe(20, 0.96),
            YsKeyframe(34, -0.3),
            YsKeyframe(50, 0),
          ]),
        ],
      ),
      // The three text lines scroll out downwards, a new page scrolls in.
      _feedLine(5),
      _feedLine(6),
      _feedLine(7),
    ],
  );

  static final _ideas = YsIconMotion._(
    icon: YsIcon.ideas,
    frames: 65,
    extras: '<path d="M12 5a3 3 0 0 1 3 3"/>',
    parts: [
      // Bulb swings from its base.
      YsPartMotion(
        originX: 12,
        originY: 22,
        tracks: [
          YsMotionTrack(YsMotionProperty.rotate, [
            YsKeyframe(7, 0),
            YsKeyframe(17, -5),
            YsKeyframe(36, 2),
            YsKeyframe(48, 0),
          ]),
        ],
      ),
      // Shine stroke sweeps across the glass.
      YsPartMotion(
        part: 3,
        originX: 12,
        originY: 8,
        tracks: [
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(6, 0, YsEase(0.167, 0.167, 0.56, 1)),
            YsKeyframe(33, 1),
          ]),
          YsMotionTrack(YsMotionProperty.trimStart, [
            YsKeyframe(15, 0, YsEase(0.44, 0, 0.56, 1)),
            YsKeyframe(50, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(6, 0, YsEase.linear),
            YsKeyframe(7, 1, YsEase.linear),
            YsKeyframe(49, 1, YsEase.linear),
            YsKeyframe(50, 0),
          ]),
        ],
      ),
    ],
  );

  static final _goals = YsIconMotion._(
    icon: YsIcon.goals,
    frames: 65,
    parts: [
      // Checkbox wobbles right, then left.
      YsPartMotion(
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.rotate, [
            YsKeyframe(3, 0, YsEase(0.2, 0.12, 0, 1)),
            YsKeyframe(9, 6.5),
            YsKeyframe(22, 6.5, YsEase(0.2, 0.12, 0, 1)),
            YsKeyframe(30, -8),
            YsKeyframe(34, -8, YsEase(0.2, 0.12, 0, 1)),
            YsKeyframe(43, 0),
          ]),
        ],
      ),
      // Tick is erased, then drawn again in two strokes.
      YsPartMotion(
        part: 1,
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(0, 1),
            YsKeyframe(3, 0),
            YsKeyframe(12, 0, YsEase(0.15, 1, 0.4, 1)),
            YsKeyframe(19, 0.323),
            YsKeyframe(22, 0.323, YsEase(0.45, 0.1, 0.2, 1)),
            YsKeyframe(33, 1),
          ]),
          // A zero-length stroke would still paint its round caps.
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(2.9, 1, YsEase.linear),
            YsKeyframe(3, 0, YsEase.linear),
            YsKeyframe(12, 0, YsEase.linear),
            YsKeyframe(12.1, 1),
          ]),
        ],
      ),
    ],
  );

  static final _library = YsIconMotion._(
    icon: YsIcon.library,
    frames: 65,
    parts: [
      _libraryFlip(0, 12, 6.25, 5),
      _libraryFlip(1, 6.5, 17.5, 8),
      _libraryFlip(2, 17.5, 17.5, 11),
    ],
  );
}

/// Typing dot [part] inside the chat bubble, [delay] frames after the
/// first: pops in, bounces twice, shrinks away.
YsPartMotion _chatDot(int part, double delay) {
  YsKeyframe k(double frame, double value, [YsEase ease = YsEase.smooth]) =>
      YsKeyframe(frame + delay, value, ease);
  return YsPartMotion(
    part: part,
    originX: 8.0 + (part - 1) * 4,
    originY: 12,
    tracks: [
      YsMotionTrack(YsMotionProperty.scale, [
        k(5, 0, const YsEase(0.167, 0.167, 0.46, 1)),
        k(12, 0.9),
        k(17, 0.85),
        k(44, 0.85, const YsEase(1, 0, 1, 1)),
        k(53, 0.25),
      ]),
      YsMotionTrack(YsMotionProperty.translateY, [
        k(5, 0, const YsEase(0.167, 0.167, 0.667, 1)),
        k(12, -0.75),
        k(25, 0),
        k(37, -0.75),
        k(47, 0, const YsEase(1, 0, 1, 1)),
        k(53, -0.75),
      ]),
      YsMotionTrack(YsMotionProperty.opacity, [
        k(52.9, 1, YsEase.linear),
        k(53, 0),
      ]),
    ],
  );
}

/// Feed text line [part]: slides down and fades, then a new one slides in
/// from above.
YsPartMotion _feedLine(int part) => YsPartMotion(
  part: part,
  originX: 12,
  originY: 12,
  tracks: const [
    YsMotionTrack(YsMotionProperty.translateY, [
      YsKeyframe(5, 0, YsEase(0.55, 0, 0.833, 0.833)),
      YsKeyframe(24, 6, YsEase.linear),
      YsKeyframe(35.9, 6, YsEase.linear),
      YsKeyframe(36, -6, YsEase(0.167, 0.167, 0.23, 1)),
      YsKeyframe(55, 0),
    ]),
    YsMotionTrack(YsMotionProperty.opacity, [
      YsKeyframe(5, 1, YsEase(0.55, 0, 0.833, 0.833)),
      YsKeyframe(16, 0, YsEase.linear),
      YsKeyframe(36, 0, YsEase(0.167, 0.167, 0.23, 1)),
      YsKeyframe(46, 1),
    ]),
  ],
);

/// Library shape [part] centred on ([x], [y]): flips around its vertical
/// axis twice from frame [start], settling slowly.
YsPartMotion _libraryFlip(int part, double x, double y, double start) {
  YsKeyframe k(double frame, double value, [YsEase ease = YsEase.drift]) =>
      YsKeyframe(frame + start, value, ease);
  return YsPartMotion(
    part: part,
    originX: x,
    originY: y,
    tracks: [
      YsMotionTrack(YsMotionProperty.scaleX, [
        k(0, 1, const YsEase(0.587, 0, 0.833, 0.833)),
        k(6, 0.1),
        k(11, 1),
        k(20, 0),
        k(26, 0.7),
        k(32, 0.9, const YsEase(0.167, 0.167, 0.424, 1)),
        k(42, 1),
      ]),
    ],
  );
}

final _element = RegExp(r'<(path|rect|circle)\b[^>]*/>');

/// Splits SVG markup made of self-closing `path`/`rect`/`circle` elements.
List<String> ysSvgElements(String markup) => [
  for (final m in _element.allMatches(markup)) m.group(0)!,
];
