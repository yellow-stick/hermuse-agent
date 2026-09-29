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

  /// Decelerating entrance: quick start, long settle.
  static const settle = YsEase(0.2, 0, 0, 1);

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

/// Motion of a setup checklist: rows entering, glyphs drawing in, state
/// changes, the checking scan, the working arc and the "ready" moment
/// (milliseconds unless noted; frames are 60 fps, like [YsIconMotion]).
abstract final class YsStepMotion {
  /// A new row fades in while rising [rise] px over [enter] ms, [stagger] ms
  /// after the row above it, with the [YsEase.settle] curve.
  static const enter = 360;
  static const stagger = 60;
  static const rise = 8.0;

  /// Its glyph draws in stroke after stroke: each stroke takes [drawStroke]
  /// frames and the last one starts at frame [drawSpread] ([drawIn]).
  static const drawStroke = 16.0;
  static const drawSpread = 14.0;

  /// A state change: status, glyph and ring crossfade over [swap] ms and the
  /// row's height eases over [resize] ms ([YsEase.standard]).
  static const swap = 220;
  static const resize = 280;

  /// Checking: the glyph breathes and a short arc scans the ring, one cycle
  /// every [pulse] ms.
  static const pulse = 1600;

  /// Working without a known end: one arc turn every [spin] ms.
  static const spin = 1100;

  /// Working towards a known end, and the overall ring: each new value is
  /// reached in [progress] ms ([YsEase.standard]).
  static const progress = 600;

  /// Ready: the overall ring turns to the success colour over [readyTurn]
  /// frames while it draws the tick of [YsStepMark.tick], then pops
  /// ([readyPop]); after [readyFrames] frames the moment holds [readyHold]
  /// ms before the app goes on.
  static const readyTurn = 14.0;
  static const readyFrames = 34.0;
  static const readyHold = 600;
  static const readyPop = YsPartMotion(
    originX: 12,
    originY: 12,
    tracks: [
      YsMotionTrack(YsMotionProperty.scale, [
        YsKeyframe(20, 1, YsEase.standard),
        YsKeyframe(26, 1.06),
        YsKeyframe(34, 1),
      ]),
    ],
  );

  /// Frames of [drawIn] for [count] elements.
  static double drawFrames(int count) =>
      count <= 1 ? drawStroke : drawSpread + drawStroke;

  /// Each of [count] glyph elements drawing in ([YsMotionProperty.trimEnd]
  /// from 0 to 1), the starts spread over [drawSpread] frames.
  static List<YsPartMotion> drawIn(int count) => [
    for (var i = 0; i < count; i++)
      _drawStroke(i, count <= 1 ? 0 : drawSpread * i / (count - 1)),
  ];

  static YsPartMotion _drawStroke(int part, double start) => YsPartMotion(
    part: part,
    originX: 12,
    originY: 12,
    tracks: [
      YsMotionTrack(YsMotionProperty.trimEnd, [
        YsKeyframe(start, 0, YsEase.settle),
        YsKeyframe(start + drawStroke, 1),
      ]),
      // A zero-length stroke would still paint its round caps.
      YsMotionTrack(YsMotionProperty.opacity, [
        YsKeyframe(start, 0, YsEase.linear),
        YsKeyframe(start + 0.1, 1),
      ]),
    ],
  );
}

/// The mark a setup checklist row settles on — tick, calm tick, cross,
/// dash — with the one-shot motion that brings it in when the row reaches
/// that state: Lucide geometry on the 24-unit viewBox, keyframes at 60 fps
/// like [YsIconMotion].
final class YsStepMark {
  const YsStepMark._({
    required this.body,
    required this.frames,
    required this.parts,
    this.ring,
  });

  /// Glyph markup (24-unit viewBox), drawn inside the row's ring.
  final String body;

  /// Length in frames (60 fps).
  final double frames;

  /// Motion of the ring around the glyph: [YsMotionProperty.trimEnd]
  /// closes it, opacity and scale bring it in. Null: the ring just shows.
  final YsPartMotion? ring;

  /// Motion of the whole glyph (part null) and of its elements.
  final List<YsPartMotion> parts;

  int get durationMs => (frames * 1000 / 60).round();

  /// Top-level SVG elements of [body].
  List<String> get elements => ysSvgElements(body);

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

  /// Completed now: the ring closes clockwise from the top, then the tick
  /// draws stroke by stroke, short leg then long leg (26 frames, ~430 ms).
  static const tick = YsStepMark._(
    // Lucide `check`, drawn from its short leg.
    body: '<path d="m4 12 5 5L20 6"/>',
    frames: 26,
    ring: YsPartMotion(
      originX: 12,
      originY: 12,
      tracks: [
        YsMotionTrack(YsMotionProperty.trimEnd, [
          YsKeyframe(0, 0, YsEase.standard),
          YsKeyframe(14, 1),
        ]),
      ],
    ),
    parts: [
      YsPartMotion(
        part: 0,
        originX: 12,
        originY: 12,
        tracks: [
          // The short leg is 0.3125 of the path.
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(6, 0, YsEase(0.15, 1, 0.4, 1)),
            YsKeyframe(12, 0.3125),
            YsKeyframe(14, 0.3125, YsEase(0.45, 0.1, 0.2, 1)),
            YsKeyframe(26, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(5.9, 0, YsEase.linear),
            YsKeyframe(6, 1),
          ]),
        ],
      ),
    ],
  );

  /// Already in place: a soft disc grows behind a tick that settles in,
  /// without being drawn (16 frames).
  static const calmTick = YsStepMark._(
    body: '<path d="m4 12 5 5L20 6"/>',
    frames: 16,
    ring: YsPartMotion(
      originX: 12,
      originY: 12,
      tracks: [
        YsMotionTrack(YsMotionProperty.scale, [
          YsKeyframe(0, 0.6, YsEase.settle),
          YsKeyframe(12, 1),
        ]),
        YsMotionTrack(YsMotionProperty.opacity, [
          YsKeyframe(0, 0, YsEase.standard),
          YsKeyframe(10, 1),
        ]),
      ],
    ),
    parts: [
      YsPartMotion(
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.scale, [
            YsKeyframe(2, 0.75, YsEase.settle),
            YsKeyframe(16, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(2, 0, YsEase.standard),
            YsKeyframe(12, 1),
          ]),
        ],
      ),
    ],
  );

  /// Failed: the ring fades in, the cross draws stroke by stroke, then it
  /// shakes its head, gently (38 frames).
  static const cross = YsStepMark._(
    // Lucide `x`.
    body: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
    frames: 38,
    ring: YsPartMotion(
      originX: 12,
      originY: 12,
      tracks: [
        YsMotionTrack(YsMotionProperty.opacity, [
          YsKeyframe(0, 0, YsEase.standard),
          YsKeyframe(8, 1),
        ]),
      ],
    ),
    parts: [
      YsPartMotion(
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.rotate, [
            YsKeyframe(16, 0),
            YsKeyframe(20, 9),
            YsKeyframe(25, -7),
            YsKeyframe(30, 4),
            YsKeyframe(35, -1.5),
            YsKeyframe(38, 0),
          ]),
        ],
      ),
      YsPartMotion(
        part: 0,
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(2, 0, YsEase.settle),
            YsKeyframe(10, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(2, 0, YsEase.linear),
            YsKeyframe(2.1, 1),
          ]),
        ],
      ),
      YsPartMotion(
        part: 1,
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(8, 0, YsEase.settle),
            YsKeyframe(16, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(8, 0, YsEase.linear),
            YsKeyframe(8.1, 1),
          ]),
        ],
      ),
    ],
  );

  /// Not needed: a dash draws from the left (12 frames).
  static const dash = YsStepMark._(
    // Lucide `minus`.
    body: '<path d="M5 12h14"/>',
    frames: 12,
    parts: [
      YsPartMotion(
        part: 0,
        originX: 12,
        originY: 12,
        tracks: [
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(0, 0, YsEase.standard),
            YsKeyframe(12, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(0, 0, YsEase.linear),
            YsKeyframe(0.1, 1),
          ]),
        ],
      ),
    ],
  );
}

final _element = RegExp(r'<(path|rect|circle)\b[^>]*/>');

/// Splits SVG markup made of self-closing `path`/`rect`/`circle` elements.
List<String> ysSvgElements(String markup) => [
  for (final m in _element.allMatches(markup)) m.group(0)!,
];
