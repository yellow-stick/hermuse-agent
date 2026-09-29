import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// Where a setup step stands.
enum YsStepState {
  /// Not reached yet: muted.
  pending,

  /// Being looked at: a short arc scans the ring, the glyph breathes.
  checking,

  /// Already in place and working: a calm tick on a soft disc, not drawn.
  found,

  /// In progress: an arc sweeps the ring, or fills it to a known progress.
  working,

  /// Completed now: the ring closes and the tick draws stroke by stroke.
  done,

  /// Waits on the user: accent ring.
  needsAction,

  /// Failed: the cross draws, then shakes its head.
  failed,

  /// Not needed here: a dash.
  skipped;

  /// The mark this state settles on; null while it shows the step's glyph.
  YsStepMark? get mark => switch (this) {
    done => YsStepMark.tick,
    found => YsStepMark.calmTick,
    failed => YsStepMark.cross,
    skipped => YsStepMark.dash,
    pending || checking || working || needsAction => null,
  };

  /// Whether the step is behind the user: done, found or not needed.
  bool get settled => this == done || this == found || this == skipped;
}

/// The animated status badge of a setup step: [icon] in a ring that scans
/// while checking, sweeps while working (filling to [progress] when known)
/// and turns accent when the step needs the user. A settled or failed step
/// plays its [YsStepState.mark] in once; a new badge draws its glyph in,
/// stroke after stroke. Consecutive states crossfade.
///
/// With animations disabled (`MediaQuery.disableAnimations`, or a muted
/// [TickerMode]) every state shows its final look at once and nothing
/// loops.
final class YsStepBadge extends StatefulWidget {
  const YsStepBadge({
    required this.state,
    required this.icon,
    this.progress,
    this.size = YsLayout.stepBadge,
    super.key,
  });

  final YsStepState state;
  final YsIcon icon;

  /// Share of a [YsStepState.working] step done, 0..1; null when unknown.
  final double? progress;

  /// Outer diameter of the ring.
  final double size;

  @override
  State<YsStepBadge> createState() => _YsStepBadgeState();
}

final class _YsStepBadgeState extends State<YsStepBadge>
    with TickerProviderStateMixin {
  /// The one-shot motion of the state shown: its mark, or its glyph
  /// drawing in.
  late final _entry = AnimationController(vsync: this);

  /// The loop of a checking or an indeterminate working state.
  late final _cycle = AnimationController(vsync: this);

  /// The crossfade from the previous state.
  late final _swap = AnimationController(vsync: this, value: 1);

  /// The known progress, eased to each new value.
  late final _progress = AnimationController(vsync: this);

  /// The previous state, fading out.
  _Look? _from;

  /// Frames the current [_entry] spans.
  double _frames = 0;

  /// Whether [_entry] draws the glyph in rather than playing a mark.
  bool _drawIn = false;

  bool _started = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (!_started) {
      _started = true;
      _play(drawIn: true);
      _syncProgress();
    }
    if (_still) _settle();
    _syncCycle();
  }

  @override
  void didUpdateWidget(YsStepBadge old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.icon != widget.icon) {
      _from = _Look(
        state: old.state,
        icon: old.icon,
        cycle: _cycle.value,
        progress: old.progress == null ? null : _progress.value,
      );
      if (_still) {
        _swap.value = 1;
      } else {
        _swap
          ..duration = const Duration(milliseconds: YsStepMotion.swap)
          ..forward(from: 0);
      }
      // The glyph draws in again when it comes back from a mark (a retry).
      _play(drawIn: old.state.mark != null || old.icon != widget.icon);
      _syncCycle();
    }
    if (old.progress != widget.progress) _syncProgress();
  }

  @override
  void dispose() {
    _entry.dispose();
    _cycle.dispose();
    _swap.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// Starts the entry motion of the current state.
  void _play({required bool drawIn}) {
    final mark = widget.state.mark;
    _drawIn = mark == null && drawIn;
    _frames =
        mark?.frames ??
        (_drawIn
            ? YsStepMotion.drawFrames(YsSvgShape.of(widget.icon.body).length)
            : 0);
    if (_still || _frames == 0) {
      _entry.value = 1;
      return;
    }
    _entry
      ..duration = Duration(milliseconds: (_frames * 1000 / 60).round())
      ..forward(from: 0);
  }

  /// Jumps every one-shot motion to its end.
  void _settle() {
    _entry.value = 1;
    _swap.value = 1;
    _progress.value = widget.progress ?? _progress.value;
  }

  void _syncCycle() {
    final period = switch (widget.state) {
      YsStepState.checking => YsStepMotion.pulse,
      YsStepState.working when widget.progress == null => YsStepMotion.spin,
      _ => null,
    };
    if (period == null || _still) {
      _cycle.stop();
      return;
    }
    final duration = Duration(milliseconds: period);
    if (_cycle.isAnimating && _cycle.duration == duration) return;
    _cycle
      ..duration = duration
      ..repeat();
  }

  void _syncProgress() {
    final target = widget.progress;
    if (target == null) return;
    if (_still) {
      _progress.value = target;
      return;
    }
    _progress.animateTo(
      target.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: YsStepMotion.progress),
      curve: YsEase.standard.curve,
    );
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _BadgePainter(
        badge: this,
        palette: YsTheme.of(context),
        look: _Look(
          state: widget.state,
          icon: widget.icon,
          cycle: 0,
          progress: widget.progress,
        ),
        from: _from,
      ),
    ),
  );
}

/// A state as painted: [cycle] and [progress] are live for the current
/// state, frozen for the one fading out.
final class _Look {
  const _Look({
    required this.state,
    required this.icon,
    required this.cycle,
    required this.progress,
  });

  final YsStepState state;
  final YsIcon icon;
  final double cycle;

  /// Null: indeterminate.
  final double? progress;
}

final class _BadgePainter extends CustomPainter {
  _BadgePainter({
    required this.badge,
    required this.palette,
    required this.look,
    required this.from,
  }) : super(
         repaint: Listenable.merge([
           badge._entry,
           badge._cycle,
           badge._swap,
           badge._progress,
         ]),
       );

  final _YsStepBadgeState badge;
  final YsPalette palette;
  final _Look look;
  final _Look? from;

  @override
  void paint(Canvas canvas, Size size) {
    final swap = badge._swap.value;
    final previous = from;
    if (previous != null && swap < 1) {
      _paintLook(
        canvas,
        size,
        previous,
        frame: double.infinity,
        drawIn: false,
        cycle: previous.cycle,
        progress: previous.progress,
        alpha: 1 - swap,
      );
    }
    _paintLook(
      canvas,
      size,
      look,
      frame: badge._entry.value * badge._frames,
      drawIn: badge._drawIn,
      cycle: badge._cycle.value,
      progress: look.progress == null ? null : badge._progress.value,
      alpha: previous == null ? 1 : swap,
    );
  }

  void _paintLook(
    Canvas canvas,
    Size size,
    _Look look, {
    required double frame,
    required bool drawIn,
    required double cycle,
    required double? progress,
    required double alpha,
  }) {
    Color fade(Color c, [double opacity = 1]) =>
        c.withValues(alpha: c.a * alpha * opacity.clamp(0, 1));
    Paint ring(Color c, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = c;
    final rect = (Offset.zero & size).deflate(YsLayout.stepRingStroke / 2);
    const full = 2 * math.pi;
    const top = -math.pi / 2;
    final mark = look.state.mark;
    final markup = mark?.body ?? look.icon.body;
    final drawParts = drawIn
        ? YsStepMotion.drawIn(YsSvgShape.of(markup).length)
        : null;
    void glyph(Color color, [double opacity = 1]) => _paintGlyph(
      canvas,
      size,
      markup,
      fade(color, opacity),
      mark: mark,
      drawIn: drawParts,
      frame: frame,
    );

    switch (look.state) {
      case YsStepState.pending:
        canvas.drawOval(rect, ring(fade(palette.lineColor), ysHairline));
        glyph(palette.contentSubtleColor);
      case YsStepState.checking:
        canvas.drawOval(rect, ring(fade(palette.lineColor), ysHairline));
        canvas.drawArc(
          rect,
          top + cycle * full,
          0.28 * full,
          false,
          ring(fade(palette.contentMutedColor), YsLayout.stepRingStroke),
        );
        // One breath per cycle, from full strength down to 55 %.
        glyph(
          palette.contentMutedColor,
          0.775 + 0.225 * math.cos(cycle * full),
        );
      case YsStepState.working:
        canvas.drawOval(
          rect,
          ring(fade(palette.neutralFilmColor), YsLayout.stepRingStroke),
        );
        final arc = ring(fade(palette.primaryColor), YsLayout.stepRingStroke);
        if (progress != null) {
          canvas.drawArc(
            rect,
            top,
            math.max(progress, 0.02) * full,
            false,
            arc,
          );
        } else {
          // The arc turns once per cycle while it breathes from a fifth to
          // two thirds of the ring.
          final sweep = 0.2 + 0.23 * (1 - math.cos(cycle * full));
          canvas.drawArc(rect, top + cycle * full, sweep * full, false, arc);
        }
        glyph(palette.contentColor);
      case YsStepState.needsAction:
        canvas.drawOval(
          rect,
          ring(fade(palette.primaryColor), YsLayout.stepRingStroke),
        );
        glyph(palette.primaryColor);
      case YsStepState.done:
        final closed = mark!.ring!.valueAt(YsMotionProperty.trimEnd, frame);
        if (closed > 0) {
          canvas.drawArc(
            rect,
            top,
            closed * full,
            false,
            ring(fade(palette.successColor), YsLayout.stepRingStroke),
          );
        }
        glyph(palette.successColor);
      case YsStepState.found:
        final disc = mark!.ring!;
        canvas.drawCircle(
          size.center(Offset.zero),
          size.shortestSide / 2 * disc.valueAt(YsMotionProperty.scale, frame),
          Paint()
            ..color = fade(
              palette.successMutedColor,
              disc.valueAt(YsMotionProperty.opacity, frame),
            ),
        );
        glyph(palette.successColor);
      case YsStepState.failed:
        canvas.drawOval(
          rect,
          ring(
            fade(
              palette.errorColor,
              mark!.ring!.valueAt(YsMotionProperty.opacity, frame),
            ),
            YsLayout.stepRingStroke,
          ),
        );
        glyph(palette.errorColor);
      case YsStepState.skipped:
        canvas.drawOval(rect, ring(fade(palette.lineColor), ysHairline));
        glyph(palette.contentSubtleColor);
    }
  }

  /// [markup] at the glyph size in the middle of the badge, animated by
  /// [mark] or [drawIn] at [frame].
  static void _paintGlyph(
    Canvas canvas,
    Size size,
    String markup,
    Color color, {
    required YsStepMark? mark,
    required List<YsPartMotion>? drawIn,
    required double frame,
  }) {
    if (color.a <= 0) return;
    final glyph = size.shortestSide * YsLayout.stepGlyph / YsLayout.stepBadge;
    canvas
      ..save()
      ..translate((size.width - glyph) / 2, (size.height - glyph) / 2)
      ..scale(glyph / 24);
    final root = mark?.root;
    var rootOpacity = 1.0;
    if (root != null) {
      ysTransformPart(canvas, root, frame);
      rootOpacity = root.valueAt(YsMotionProperty.opacity, frame);
    }
    final shapes = YsSvgShape.of(markup);
    for (var i = 0; i < shapes.length; i++) {
      final part = mark?.part(i) ?? drawIn?[i];
      final opacity =
          (part?.valueAt(YsMotionProperty.opacity, frame) ?? 1) * rootOpacity;
      if (opacity <= 0) continue;
      canvas.save();
      if (part != null) ysTransformPart(canvas, part, frame);
      final shape = shapes[i];
      shape.paint(
        canvas,
        ysPartPath(shape.path, part, frame),
        color.withValues(alpha: color.a * opacity.clamp(0, 1)),
        YsLayout.stepGlyphStroke,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      old.badge != badge ||
      old.palette != palette ||
      old.look.state != look.state ||
      old.look.icon != look.icon ||
      old.look.progress != look.progress ||
      old.from != from;
}
