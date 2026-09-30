import 'motion.dart';

/// Ink of an illustration part; each kit maps it to a palette role.
enum YsArtInk {
  /// Outlines, in `contentMuted`.
  line,

  /// Highlights, in `primary`.
  accent,

  /// The soft disc behind the drawing, in `neutralAmbient`.
  soft,
}

/// One SVG element of a [YsArt] (`path`, `rect` or `circle`, self-closing,
/// on the 64-unit viewBox) and the ink it is painted with.
final class YsArtPart {
  const YsArtPart(this.markup, [this.ink = YsArtInk.line]);

  final String markup;
  final YsArtInk ink;

  /// Filled (`fill="currentColor"`): it pops in instead of drawing in.
  bool get filled => markup.contains('fill="currentColor"');

  /// Centre of a circle (its pop origin); the viewBox centre otherwise.
  (double, double) get center {
    double? n(String name) => double.tryParse(
      RegExp('$name="([^"]*)"').firstMatch(markup)?.group(1) ?? '',
    );
    return (n('cx') ?? YsArt.viewBox / 2, n('cy') ?? YsArt.viewBox / 2);
  }
}

/// Timing of every illustration (frames at 60 fps, like [YsIconMotion]).
///
/// An illustration draws in once when it appears: the soft disc grows, then
/// each outline draws stroke by stroke ([drawStroke] frames, [stagger]
/// frames apart) and filled dots pop. [idleDelay] frames later its idle
/// motion plays [idleCycles] times and rests; pointing at it plays one more
/// cycle, or its own hover motion.
abstract final class YsArtMotion {
  static const backdrop = 18.0;
  static const lead = 6.0;
  static const drawStroke = 28.0;
  static const stagger = 5.0;
  static const pop = 14.0;
  static const idleDelay = 12.0;
  static const idleCycles = 2;
}

/// A small line illustration: Lucide-weight outlines on a soft disc, with a
/// yellow accent, a draw-in, a subtle idle loop and a hover motion.
///
/// Geometry is authored on a [viewBox]-unit square; kits stroke it at
/// [stroke] units with round caps and joins.
final class YsArt {
  YsArt._(
    this.name, {
    required this.parts,
    required this.idleFrames,
    required this.idle,
    this.hoverFrames = 0,
    this.hover = const [],
  });

  static const viewBox = 64.0;
  static const stroke = 1.75;

  /// Identifier (CSS class names on the web).
  final String name;

  final List<YsArtPart> parts;

  /// Length of one idle cycle in frames; [idle] keyframes start and end at
  /// rest so cycles loop seamlessly.
  final double idleFrames;
  final List<YsPartMotion> idle;

  /// One-shot motion when pointed at; empty plays one [idle] cycle.
  final double hoverFrames;
  final List<YsPartMotion> hover;

  /// Markup of every part, in order.
  List<String> get elements => [for (final p in parts) p.markup];

  late final List<YsPartMotion> entrance = [
    for (var i = 0; i < parts.length; i++) _entry(i),
  ];

  /// Frames of [entrance].
  late final double entranceFrames = parts.isEmpty
      ? 0
      : [for (var i = 0; i < parts.length; i++) _start(i) + _length(i)]
            .reduce((a, b) => a > b ? a : b);

  double _start(int i) => i == 0 && parts[0].ink == YsArtInk.soft
      ? 0
      : YsArtMotion.lead + i * YsArtMotion.stagger;

  double _length(int i) => parts[i].ink == YsArtInk.soft
      ? YsArtMotion.backdrop
      : parts[i].filled
      ? YsArtMotion.pop
      : YsArtMotion.drawStroke;

  YsPartMotion _entry(int i) {
    final part = parts[i];
    final start = _start(i);
    final end = start + _length(i);
    final (x, y) = part.center;
    if (part.ink == YsArtInk.soft) {
      return YsPartMotion(
        part: i,
        originX: x,
        originY: y,
        tracks: [
          YsMotionTrack(YsMotionProperty.scale, [
            YsKeyframe(start, 0.8, YsEase.settle),
            YsKeyframe(end, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(start, 0, YsEase.standard),
            YsKeyframe(end, 1),
          ]),
        ],
      );
    }
    if (part.filled) {
      return YsPartMotion(
        part: i,
        originX: x,
        originY: y,
        tracks: [
          YsMotionTrack(YsMotionProperty.scale, [
            YsKeyframe(start, 0, YsEase.settle),
            YsKeyframe(start + YsArtMotion.pop * 0.6, 1.2, YsEase.standard),
            YsKeyframe(end, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(start, 0, YsEase.linear),
            YsKeyframe(start + 1, 1),
          ]),
        ],
      );
    }
    return YsPartMotion(
      part: i,
      originX: x,
      originY: y,
      tracks: [
        YsMotionTrack(YsMotionProperty.trimEnd, [
          YsKeyframe(start, 0, YsEase.settle),
          YsKeyframe(end, 1),
        ]),
        // A zero-length stroke would still paint its round caps.
        YsMotionTrack(YsMotionProperty.opacity, [
          YsKeyframe(start, 0, YsEase.linear),
          YsKeyframe(start + 0.1, 1),
        ]),
      ],
    );
  }

  /// Entrance motion of part [index].
  YsPartMotion entrancePart(int index) => entrance[index];

  /// Idle motion of part [index], if any.
  YsPartMotion? idlePart(int index) => _find(idle, index);

  /// Hover motion of part [index], if any.
  YsPartMotion? hoverPart(int index) => _find(hover, index);

  static YsPartMotion? _find(List<YsPartMotion> motions, int index) {
    for (final m in motions) {
      if (m.part == index) return m;
    }
    return null;
  }

  static const _disc = YsArtPart(
    '<circle cx="32" cy="34" r="26" fill="currentColor" stroke="none"/>',
    YsArtInk.soft,
  );

  /// A server with signal arcs: a Hermes reached over the network.
  static final remote = YsArt._(
    'remote',
    parts: const [
      _disc,
      YsArtPart('<rect x="17" y="30" width="30" height="10" rx="3"/>'),
      YsArtPart('<rect x="17" y="43" width="30" height="10" rx="3"/>'),
      YsArtPart('<path d="M23 35h6"/>'),
      YsArtPart('<path d="M23 48h6"/>'),
      YsArtPart(
        '<circle cx="41" cy="35" r="1.6" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
      YsArtPart(
        '<circle cx="41" cy="48" r="1.6" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
      YsArtPart('<path d="M27.76 21.76a6 6 0 0 1 8.48 0"/>', YsArtInk.accent),
      YsArtPart(
        '<path d="M24.22 18.22a11 11 0 0 1 15.56 0"/>',
        YsArtInk.accent,
      ),
      YsArtPart(
        '<path d="M20.69 14.69a16 16 0 0 1 22.62 0"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 96,
    idle: [
      _dip(7, 0),
      _dip(8, 8),
      _dip(9, 16),
      _dip(5, 50, depth: 0.25, length: 12),
      _dip(6, 58, depth: 0.25, length: 12),
    ],
    hoverFrames: 40,
    hover: [
      _redraw(7, 0, length: 16),
      _redraw(8, 5, length: 16),
      _redraw(9, 10, length: 16),
      _pop(5, 41, 35, 0),
      _pop(6, 41, 48, 6),
    ],
  );

  /// A laptop with a tick and a sparkle: Hermes installed right here.
  static final local = YsArt._(
    'local',
    parts: const [
      _disc,
      YsArtPart('<rect x="15" y="19" width="34" height="23" rx="3"/>'),
      YsArtPart('<path d="M10 47h44"/>'),
      YsArtPart('<path d="M13 42 10 47"/>'),
      YsArtPart('<path d="m51 42 3 5"/>'),
      YsArtPart('<path d="m25 31 5 5 9-10"/>', YsArtInk.accent),
      YsArtPart('<path d="M50 8v8"/>', YsArtInk.accent),
      YsArtPart('<path d="M46 12h8"/>', YsArtInk.accent),
    ],
    idleFrames: 90,
    idle: [
      ..._twinkle([6, 7], 50, 12, 0),
    ],
    hoverFrames: 40,
    hover: [
      _redraw(5, 0, length: 20),
      ..._twinkle([6, 7], 50, 12, 4),
    ],
  );

  /// A page and a plus: posts to come.
  static final feed = YsArt._(
    'feed',
    parts: const [
      _disc,
      YsArtPart('<rect x="18" y="12" width="28" height="38" rx="4"/>'),
      YsArtPart('<path d="M24 22h16"/>'),
      YsArtPart('<path d="M24 29h16"/>'),
      YsArtPart('<path d="M24 36h10"/>'),
      YsArtPart('<path d="M48 36v10"/>', YsArtInk.accent),
      YsArtPart('<path d="M43 41h10"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      _dip(2, 0, depth: 0.35),
      _dip(3, 8, depth: 0.35),
      _dip(4, 16, depth: 0.35),
      ..._twinkle([5, 6], 48, 41, 40),
    ],
  );

  /// A light bulb shining.
  static final ideas = YsArt._(
    'ideas',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="M26 40c-.5-2.6-1.9-4.4-3.7-6.4A12 12 0 1 1 44 26c0 2.8-1 '
        '5.3-2.3 7.6-1.8 2-3.2 3.8-3.7 6.4"/>',
      ),
      YsArtPart('<path d="M26 45h12"/>'),
      YsArtPart('<path d="M28 50h8"/>'),
      YsArtPart('<path d="M32 4v4"/>', YsArtInk.accent),
      YsArtPart('<path d="m17 10 2.8 2.8"/>', YsArtInk.accent),
      YsArtPart('<path d="m47 10-2.8 2.8"/>', YsArtInk.accent),
      YsArtPart('<path d="M11 25h4"/>', YsArtInk.accent),
      YsArtPart('<path d="M49 25h4"/>', YsArtInk.accent),
      YsArtPart(
        '<path d="M27 31c1.7 2 3.3 2 5 0s3.3-2 5 0"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 96,
    idle: [
      for (final i in [4, 5, 6, 7, 8]) _glow(i, 32, 26, 0),
      _flicker(9, 34),
    ],
  );

  /// A target with an arrow in the bullseye.
  static final goals = YsArt._(
    'goals',
    parts: const [
      _disc,
      YsArtPart('<circle cx="30" cy="36" r="17"/>'),
      YsArtPart('<circle cx="30" cy="36" r="10"/>'),
      YsArtPart(
        '<circle cx="30" cy="36" r="3" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
      YsArtPart('<path d="M30 36 47 19"/>', YsArtInk.accent),
      YsArtPart('<path d="M47 19v-6"/>', YsArtInk.accent),
      YsArtPart('<path d="M47 19h6"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      for (final i in [4, 5, 6]) _wobble(i, 30, 36, 0, const [-5, 3.5, -1.5]),
      _pop(3, 30, 36, 2, reach: 1.4),
    ],
  );

  /// Books on a shelf.
  static final library = YsArt._(
    'library',
    parts: const [
      _disc,
      YsArtPart('<path d="M10 50h44"/>'),
      YsArtPart('<rect x="15" y="26" width="9" height="24" rx="2"/>'),
      YsArtPart('<rect x="26" y="20" width="9" height="30" rx="2"/>'),
      YsArtPart('<path d="m38.5 27.6 8.1-2.2 6.2 23-8.1 2.2z"/>'),
      YsArtPart('<path d="M30.5 26v6"/>', YsArtInk.accent),
      YsArtPart('<path d="M19.5 32v4"/>', YsArtInk.accent),
    ],
    idleFrames: 110,
    idle: [
      for (final i in [3, 5]) _wobble(i, 30.5, 50, 0, const [-5, 2.5, 0]),
      for (final i in [2, 6]) _wobble(i, 19.5, 50, 14, const [-4, 2, 0]),
    ],
  );

  /// A crescent moon among twinkling stars: the nightly reflection.
  static final reflections = YsArt._(
    'reflections',
    parts: const [
      _disc,
      YsArtPart('<path d="M40 16a17 17 0 1 0 12 24 14 14 0 0 1-12-24z"/>'),
      YsArtPart('<path d="M17 12v8"/>', YsArtInk.accent),
      YsArtPart('<path d="M13 16h8"/>', YsArtInk.accent),
      YsArtPart('<path d="M13 38v4"/>', YsArtInk.accent),
      YsArtPart('<path d="M11 40h4"/>', YsArtInk.accent),
      YsArtPart(
        '<circle cx="27" cy="9" r="1.4" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 120,
    idle: [
      ..._twinkle([2, 3], 17, 16, 0),
      ..._twinkle([4, 5], 13, 40, 34),
      _dip(6, 64, depth: 0.2),
      _wobble(1, 38, 34, 0, const [-4, 0, 0], step: 40),
    ],
  );

  /// Two speech bubbles, one typing.
  static final chats = YsArt._(
    'chats',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="M12 18a5 5 0 0 1 5-5h20a5 5 0 0 1 5 5v9a5 5 0 0 1-5 5H22l-7 '
        '6v-6.4A5 5 0 0 1 12 27z"/>',
      ),
      YsArtPart(
        '<path d="M46 26h1a5 5 0 0 1 5 5v8a5 5 0 0 1-3 4.6V50l-7-6H34a5 5 0 0 '
        '1-5-5v-2"/>',
      ),
      YsArtPart(
        '<circle cx="21" cy="22.5" r="1.8" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
      YsArtPart(
        '<circle cx="27" cy="22.5" r="1.8" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
      YsArtPart(
        '<circle cx="33" cy="22.5" r="1.8" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 72,
    idle: [_hop(3, 0), _hop(4, 5), _hop(5, 10)],
  );

  /// The sun coming up: a day with nothing in it yet.
  static final activity = YsArt._(
    'activity',
    parts: const [
      _disc,
      YsArtPart('<path d="M9 46h46"/>'),
      YsArtPart('<path d="M17 52h30"/>'),
      YsArtPart('<path d="M20 46a12 12 0 0 1 24 0"/>', YsArtInk.accent),
      YsArtPart('<path d="M32 22v5"/>', YsArtInk.accent),
      YsArtPart('<path d="m18.6 29.6 3.5 3.5"/>', YsArtInk.accent),
      YsArtPart('<path d="m45.4 29.6-3.5 3.5"/>', YsArtInk.accent),
    ],
    idleFrames: 96,
    idle: [
      for (final i in [4, 5, 6]) _glow(i, 32, 46, 0),
    ],
  );

  /// A shield with a tick: nothing waits for the user's approval.
  static final approvals = YsArt._(
    'approvals',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="M48 33c0 11-7.7 16.5-16.9 19.7a2 2 0 0 1-1.5 0C21.7 49.5 16 '
        '44 16 33V17.6a2 2 0 0 1 2-2c4.4 0 9.9-2.6 13.7-6a2.6 2.6 0 0 1 3.4 '
        '0c3.8 3.4 9.3 6 13.7 6a2 2 0 0 1 2 2z"/>',
      ),
      YsArtPart('<path d="m25 32 6 6 10-11"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      _redraw(2, 0, length: 22, loop: true),
      _pop(1, 32, 34, 0, reach: 1.04),
    ],
  );

  /// A clock whose minute hand goes round.
  static final upcoming = YsArt._(
    'upcoming',
    parts: const [
      _disc,
      YsArtPart('<circle cx="32" cy="34" r="19"/>'),
      YsArtPart('<path d="M32 18.5v3"/>'),
      YsArtPart('<path d="M47.5 34h-3"/>'),
      YsArtPart('<path d="M32 49.5v-3"/>'),
      YsArtPart('<path d="M16.5 34h3"/>'),
      YsArtPart('<path d="M32 34v-9"/>'),
      YsArtPart('<path d="m32 34 8 5"/>', YsArtInk.accent),
      YsArtPart(
        '<circle cx="32" cy="34" r="2" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 120,
    idle: [
      const YsPartMotion(
        part: 7,
        originX: 32,
        originY: 34,
        tracks: [
          YsMotionTrack(YsMotionProperty.rotate, [
            YsKeyframe(0, 0, YsEase.smooth),
            YsKeyframe(120, 360),
          ]),
        ],
      ),
    ],
  );

  /// An identity card.
  static final identity = YsArt._(
    'identity',
    parts: const [
      _disc,
      YsArtPart('<rect x="11" y="19" width="42" height="30" rx="4"/>'),
      YsArtPart('<circle cx="23" cy="31" r="4.5"/>'),
      YsArtPart('<path d="M16 43a7 7 0 0 1 14 0"/>'),
      YsArtPart('<path d="M36 30h11"/>', YsArtInk.accent),
      YsArtPart('<path d="M36 37h7"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      _redraw(4, 0, length: 18, loop: true),
      _redraw(5, 8, length: 18, loop: true),
    ],
  );

  /// A monitor tracing a heartbeat: the instance being checked.
  static final check = YsArt._(
    'check',
    parts: const [
      _disc,
      YsArtPart('<rect x="12" y="15" width="40" height="28" rx="4"/>'),
      YsArtPart('<path d="M26 51h12"/>'),
      YsArtPart('<path d="M32 43v8"/>'),
      YsArtPart('<path d="M17 30h7l3-6 4 11 4-8 2 3h10"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      const YsPartMotion(
        part: 4,
        originX: 32,
        originY: 30,
        tracks: [
          // The trace runs off to the right, then a new one draws in.
          YsMotionTrack(YsMotionProperty.trimStart, [
            YsKeyframe(0, 0, YsEase.smooth),
            YsKeyframe(40, 1, YsEase.linear),
            YsKeyframe(40.1, 0),
          ]),
          YsMotionTrack(YsMotionProperty.trimEnd, [
            YsKeyframe(40, 1, YsEase.linear),
            YsKeyframe(40.1, 0, YsEase.settle),
            YsKeyframe(76, 1),
          ]),
          YsMotionTrack(YsMotionProperty.opacity, [
            YsKeyframe(40, 1, YsEase.linear),
            YsKeyframe(40.1, 0, YsEase.linear),
            YsKeyframe(41, 1),
          ]),
        ],
      ),
    ],
  );

  /// Two chain links and a sparkle: model accounts connected.
  static final accounts = YsArt._(
    'accounts',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="M28 38a8 8 0 0 0 11.3.8l6-6a8 8 0 0 0-11.3-11.3l-3.4 3.4"/>',
      ),
      YsArtPart(
        '<path d="M36 30a8 8 0 0 0-11.3-.8l-6 6a8 8 0 0 0 11.3 11.3l3.4-3.4"/>',
      ),
      YsArtPart('<path d="M49 12v8"/>', YsArtInk.accent),
      YsArtPart('<path d="M45 16h8"/>', YsArtInk.accent),
      YsArtPart(
        '<circle cx="14" cy="16" r="1.6" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 100,
    idle: [
      for (final i in [1, 2]) _wobble(i, 32, 34, 0, const [-7, 4, 0]),
      ..._twinkle([3, 4], 49, 16, 20),
      _dip(5, 44, depth: 0.2),
    ],
  );

  /// A chip with a sparkle: the model that does the thinking.
  static final model = YsArt._(
    'model',
    parts: const [
      _disc,
      YsArtPart('<rect x="19" y="21" width="26" height="26" rx="4"/>'),
      YsArtPart('<path d="M26 21v-5"/>'),
      YsArtPart('<path d="M38 21v-5"/>'),
      YsArtPart('<path d="M26 52v-5"/>'),
      YsArtPart('<path d="M38 52v-5"/>'),
      YsArtPart('<path d="M19 28h-5"/>'),
      YsArtPart('<path d="M19 40h-5"/>'),
      YsArtPart('<path d="M50 28h-5"/>'),
      YsArtPart('<path d="M50 40h-5"/>'),
      YsArtPart(
        '<path d="M32 27.5c.6 3.4 1.6 4.9 5 5.5-3.4.6-4.4 2.1-5 5.5-.6-3.4-'
        '1.6-4.9-5-5.5 3.4-.6 4.4-2.1 5-5.5z"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 90,
    idle: [
      ..._twinkle([10], 32, 33, 0),
    ],
  );

  /// A tick in a ring with rays: everything is ready.
  static final ready = YsArt._(
    'ready',
    parts: const [
      YsArtPart(
        '<circle cx="32" cy="32" r="26" fill="currentColor" stroke="none"/>',
        YsArtInk.soft,
      ),
      YsArtPart('<circle cx="32" cy="32" r="16"/>', YsArtInk.accent),
      YsArtPart('<path d="m25 32 5 5 10-10"/>', YsArtInk.accent),
      YsArtPart('<path d="M32 4v5"/>'),
      YsArtPart('<path d="m51.8 12.2-3.5 3.5"/>'),
      YsArtPart('<path d="M55 32h5"/>'),
      YsArtPart('<path d="m48.3 48.3 3.5 3.5"/>'),
      YsArtPart('<path d="M32 55v5"/>'),
      YsArtPart('<path d="m15.7 48.3-3.5 3.5"/>'),
      YsArtPart('<path d="M4 32h5"/>'),
      YsArtPart('<path d="m12.2 12.2 3.5 3.5"/>'),
    ],
    idleFrames: 90,
    idle: [for (var i = 3; i <= 10; i++) _glow(i, 32, 32, 0)],
  );

  /// A plug pulled out of its socket, a spark in the gap: something could
  /// not be reached (a Hermes, the keyring, the chat).
  static final unreachable = YsArt._(
    'unreachable',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="m32 22 12 12 4.6-4.6a4.8 4.8 0 0 0 0-6.8l-5.2-5.2a4.8 4.8 0 '
        '0 0-6.8 0z"/>',
      ),
      YsArtPart('<path d="m46 20 6-6"/>'),
      YsArtPart(
        '<path d="M20.6 50.6a4.8 4.8 0 0 0 6.8 0L32 46 20 34l-4.6 4.6a4.8 4.8 '
        '0 0 0 0 6.8z"/>',
      ),
      YsArtPart('<path d="m12 54 6-6"/>'),
      YsArtPart('<path d="m23 37 5-5"/>', YsArtInk.accent),
      YsArtPart('<path d="m29 43 5-5"/>', YsArtInk.accent),
      YsArtPart('<path d="M35.5 28 33.4 32h3.2l-2.1 4"/>', YsArtInk.accent),
    ],
    idleFrames: 100,
    idle: [
      // The plug jiggles as if trying its socket; the spark flickers.
      for (final i in [3, 4, 5, 6]) _wobble(i, 18, 48, 0, const [-6, 3, -1.5]),
      _flicker(7, 40),
    ],
    hoverFrames: 44,
    hover: [
      for (final i in [3, 4, 5, 6]) _wobble(i, 18, 48, 0, const [-9, 4, -2]),
      _redraw(7, 20, length: 16),
    ],
  );

  /// A browser and a Hermes, their links broken at an empty relay spot that
  /// sends out searching signals: no relay answers.
  static final relay = YsArt._(
    'relay',
    parts: const [
      _disc,
      YsArtPart('<rect x="8" y="31" width="14" height="12" rx="2.5"/>'),
      YsArtPart('<path d="M8 35h14"/>'),
      YsArtPart('<rect x="42" y="30" width="14" height="6" rx="2"/>'),
      YsArtPart('<rect x="42" y="38" width="14" height="6" rx="2"/>'),
      YsArtPart('<path d="M22 37h3.5"/>'),
      YsArtPart('<path d="M38.5 37H42"/>'),
      YsArtPart('<circle cx="32" cy="37" r="3.2"/>', YsArtInk.accent),
      YsArtPart('<path d="M28.46 29.96a5 5 0 0 1 7.08 0"/>', YsArtInk.accent),
      YsArtPart('<path d="M25.64 27.14a9 9 0 0 1 12.72 0"/>', YsArtInk.accent),
      YsArtPart(
        '<path d="M22.81 24.31a13 13 0 0 1 18.38 0"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 104,
    idle: [
      // The signals go out; the spot pops; the broken links flicker.
      _dip(8, 0),
      _dip(9, 8),
      _dip(10, 16),
      _pop(7, 32, 37, 44, reach: 1.3),
      _dip(5, 50, depth: 0.2, length: 16),
      _dip(6, 56, depth: 0.2, length: 16),
    ],
    hoverFrames: 40,
    hover: [
      _redraw(8, 0, length: 14),
      _redraw(9, 5, length: 14),
      _redraw(10, 10, length: 14),
      _pop(7, 32, 37, 18, reach: 1.3),
    ],
  );

  /// A puzzle piece with a sparkle: the Hermuse plugin to turn on.
  static final plugin = YsArt._(
    'plugin',
    parts: const [
      _disc,
      YsArtPart(
        '<path d="M38.102 20.302a1.8 1.8 0 0 0 3.024-.853 4.5 4.5 0 1 1 5.425 '
        '5.427 1.8 1.8 0 0 0-.853 3.024l3.029 3.028a4.345 4.345 0 0 1 0 6.145'
        'L45.698 40.102a1.8 1.8 0 0 1-3.024-.853 4.5 4.5 0 1 0-5.425 5.427 1.8 '
        '1.8 0 0 1 .853 3.024l-3.029 3.028a4.345 4.345 0 0 1-6.145 0L25.898 '
        '47.698a1.8 1.8 0 0 0-3.024.853 4.5 4.5 0 1 1-5.425-5.427 1.8 1.8 0 0 '
        '0 .853-3.024l-3.029-3.028a4.345 4.345 0 0 1 0-6.145L18.302 27.898a1.8 '
        '1.8 0 0 1 3.024.853 4.5 4.5 0 1 0 5.425-5.427 1.8 1.8 0 0 1-.853-3.024'
        'l3.029-3.028a4.345 4.345 0 0 1 6.145 0z"/>',
      ),
      YsArtPart('<path d="M52 9v8"/>', YsArtInk.accent),
      YsArtPart('<path d="M48 13h8"/>', YsArtInk.accent),
      YsArtPart(
        '<circle cx="12" cy="17" r="1.5" fill="currentColor" stroke="none"/>',
        YsArtInk.accent,
      ),
    ],
    idleFrames: 100,
    idle: [
      // The piece wiggles into place; the sparkle and the dot answer.
      _wobble(1, 32, 34, 0, const [-4, 2.5, -1]),
      ..._twinkle([2, 3], 52, 13, 30),
      _dip(4, 60, depth: 0.2),
    ],
    hoverFrames: 40,
    hover: [
      _pop(1, 32, 34, 0, reach: 1.06),
      ..._twinkle([2, 3], 52, 13, 4),
    ],
  );

  static final values = [
    remote,
    local,
    feed,
    ideas,
    goals,
    library,
    reflections,
    chats,
    activity,
    approvals,
    upcoming,
    identity,
    check,
    accounts,
    model,
    ready,
    unreachable,
    relay,
    plugin,
  ];
}

/// Opacity of [part] dips to [depth] and comes back, from frame [at].
YsPartMotion _dip(
  int part,
  double at, {
  double depth = 0.25,
  double length = 28,
}) => YsPartMotion(
  part: part,
  originX: 32,
  originY: 32,
  tracks: [
    YsMotionTrack(YsMotionProperty.opacity, [
      YsKeyframe(at, 1),
      YsKeyframe(at + length * 0.4, depth),
      YsKeyframe(at + length, 1),
    ]),
  ],
);

/// [part] grows away from ([x], [y]) and fades a little, then settles.
YsPartMotion _glow(int part, double x, double y, double at) => YsPartMotion(
  part: part,
  originX: x,
  originY: y,
  tracks: [
    YsMotionTrack(YsMotionProperty.scale, [
      YsKeyframe(at, 1),
      YsKeyframe(at + 14, 1.14),
      YsKeyframe(at + 30, 1),
    ]),
    YsMotionTrack(YsMotionProperty.opacity, [
      YsKeyframe(at, 1),
      YsKeyframe(at + 14, 0.45),
      YsKeyframe(at + 30, 1),
    ]),
  ],
);

/// A sparkle made of [parts] shrinks, flares with a little twist around
/// ([x], [y]) from frame [at], and settles back.
List<YsPartMotion> _twinkle(List<int> parts, double x, double y, double at) => [
  for (final part in parts)
    YsPartMotion(
      part: part,
      originX: x,
      originY: y,
      tracks: [
        YsMotionTrack(YsMotionProperty.scale, [
          YsKeyframe(at, 1),
          YsKeyframe(at + 10, 0.6),
          YsKeyframe(at + 24, 1.25, YsEase.settle),
          YsKeyframe(at + 36, 1),
        ]),
        YsMotionTrack(YsMotionProperty.rotate, [
          YsKeyframe(at, 0),
          YsKeyframe(at + 20, 30),
          YsKeyframe(at + 36, 0),
        ]),
      ],
    ),
];

/// [part] swings around ([x], [y]) through [swings] degrees from frame
/// [at], [step] frames per swing, and comes back to rest.
YsPartMotion _wobble(
  int part,
  double x,
  double y,
  double at,
  List<double> swings, {
  double step = 9,
}) => YsPartMotion(
  part: part,
  originX: x,
  originY: y,
  tracks: [
    YsMotionTrack(YsMotionProperty.rotate, [
      YsKeyframe(at, 0),
      for (var i = 0; i < swings.length; i++)
        YsKeyframe(at + step * (i + 1), swings[i]),
      YsKeyframe(at + step * (swings.length + 1), 0),
    ]),
  ],
);

/// [part] pops around ([x], [y]) from frame [at]: grows to [reach] and
/// settles.
YsPartMotion _pop(
  int part,
  double x,
  double y,
  double at, {
  double reach = 1.5,
}) => YsPartMotion(
  part: part,
  originX: x,
  originY: y,
  tracks: [
    YsMotionTrack(YsMotionProperty.scale, [
      YsKeyframe(at, 1, YsEase.standard),
      YsKeyframe(at + 6, reach, YsEase.settle),
      YsKeyframe(at + 18, 1),
    ]),
  ],
);

/// [part] draws in again from frame [at] over [length] frames. A [loop]ing
/// redraw starts from the drawn stroke, so an idle cycle begins at rest.
YsPartMotion _redraw(
  int part,
  double at, {
  required double length,
  bool loop = false,
}) => YsPartMotion(
  part: part,
  originX: 32,
  originY: 32,
  tracks: [
    YsMotionTrack(YsMotionProperty.trimEnd, [
      if (loop) YsKeyframe(at, 1, YsEase.linear),
      YsKeyframe(loop ? at + 0.1 : at, 0, YsEase.settle),
      YsKeyframe(at + length, 1),
    ]),
    // A zero-length stroke would still paint its round caps.
    YsMotionTrack(YsMotionProperty.opacity, [
      if (loop) YsKeyframe(at, 1, YsEase.linear),
      YsKeyframe(loop ? at + 0.1 : at, 0, YsEase.linear),
      YsKeyframe(at + 1, 1),
    ]),
  ],
);

/// [part] flickers like a filament warming up, from frame [at].
YsPartMotion _flicker(int part, double at) => YsPartMotion(
  part: part,
  originX: 32,
  originY: 32,
  tracks: [
    YsMotionTrack(YsMotionProperty.opacity, [
      YsKeyframe(at, 1, YsEase.linear),
      YsKeyframe(at + 4, 0.3, YsEase.linear),
      YsKeyframe(at + 8, 1, YsEase.linear),
      YsKeyframe(at + 12, 0.5, YsEase.linear),
      YsKeyframe(at + 16, 1),
    ]),
  ],
);

/// Typing dot [part] hops, [at] frames after the cycle starts.
YsPartMotion _hop(int part, double at) => YsPartMotion(
  part: part,
  originX: 32,
  originY: 32,
  tracks: [
    YsMotionTrack(YsMotionProperty.translateY, [
      YsKeyframe(at, 0, YsEase.standard),
      YsKeyframe(at + 7, -2.6, YsEase.standard),
      YsKeyframe(at + 16, 0),
    ]),
  ],
);
