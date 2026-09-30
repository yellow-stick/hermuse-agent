import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_svg_shape.dart';
import 'ys_theme.dart';

/// Renders a core [YsArt] line illustration: it draws in when it first
/// shows, plays its idle motion [YsArtMotion.idleCycles] times and rests;
/// each time [active] turns on (the pointer over its host) it plays its
/// hover motion, or one more idle cycle. While [busy] that motion plays over
/// and over.
///
/// With animations disabled (`MediaQuery.disableAnimations`, or a muted
/// [TickerMode]) it shows the finished drawing and never schedules a frame.
/// Decorative: it has no semantics.
final class YsArtView extends StatefulWidget {
  const YsArtView(
    this.art, {
    super.key,
    this.size = YsLayout.artEmpty,
    this.active = false,
    this.busy = false,
    this.soft,
  }) : hero = false;

  /// The drawing heading a full-page status: [YsLayout.artHero] big, its
  /// lines at [YsArt.heroStroke], without the soft disc.
  const YsArtView.hero(
    this.art, {
    super.key,
    this.active = false,
    this.busy = false,
  }) : size = YsLayout.artHero,
       soft = null,
       hero = true;

  final YsArt art;
  final double size;

  /// Pointer over the host; a rising edge plays the hover motion.
  final bool active;

  /// Work under way (a check running): the hover motion, or one idle cycle,
  /// plays over and over. When it turns off, the cycle under way plays to
  /// its end and the drawing rests.
  final bool busy;

  /// Colour of the soft disc; `neutralAmbient` by default.
  final Color? soft;

  /// Drawn as a hero ([YsArtView.hero]).
  final bool hero;

  @override
  State<YsArtView> createState() => _YsArtViewState();
}

final class _YsArtViewState extends State<YsArtView>
    with TickerProviderStateMixin {
  late final _entrance = AnimationController(vsync: this);

  /// [YsArtMotion.idleDelay] frames of rest, then the idle cycles.
  late final _idle = AnimationController(vsync: this);

  /// The hover motion, or one idle cycle.
  late final _hover = AnimationController(vsync: this);

  bool _started = false;
  bool _still = false;

  /// Whether [_hover] repeats for [YsArtView.busy].
  bool _looping = false;

  static Duration _frames(double frames) =>
      Duration(microseconds: (frames * 1e6 / 60).round());

  double get _idleTotal =>
      YsArtMotion.idleDelay + YsArtMotion.idleCycles * widget.art.idleFrames;

  /// Frames of the motion pointing at the art plays: its hover motion, or
  /// one idle cycle.
  double get _hoverFrames {
    final art = widget.art;
    return art.hover.isEmpty ? art.idleFrames : art.hoverFrames;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (_still) {
      _settle();
    } else if (!_started) {
      _started = true;
      _entrance
        ..duration = _frames(widget.art.entranceFrames)
        ..forward(from: 0).whenComplete(_startIdle);
    }
    _syncBusy();
  }

  void _startIdle() {
    if (!mounted || _still || widget.art.idle.isEmpty) return;
    _idle
      ..duration = _frames(_idleTotal)
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted) _idle.value = 0;
      });
  }

  /// Everything at rest, finished drawing.
  void _settle() {
    _looping = false;
    _entrance.value = 1;
    _idle
      ..stop()
      ..value = 0;
    _hover
      ..stop()
      ..value = 0;
  }

  /// Starts the busy loop, or lets its last cycle play to the end.
  void _syncBusy() {
    if (_still) return;
    if (widget.busy) {
      final frames = _hoverFrames;
      if (_looping || frames <= 0) return;
      _looping = true;
      _hover
        ..duration = _frames(frames)
        ..repeat();
    } else if (_looping) {
      _looping = false;
      _hover.forward().whenCompleteOrCancel(_restHover);
    }
  }

  /// The hover motion ended; a busy loop that took over keeps going.
  void _restHover() {
    if (mounted && !_looping) _hover.value = 0;
  }

  @override
  void didUpdateWidget(YsArtView old) {
    super.didUpdateWidget(old);
    if (old.art != widget.art && !_still) {
      _looping = false;
      _idle.value = 0;
      _hover.value = 0;
      _entrance
        ..duration = _frames(widget.art.entranceFrames)
        ..forward(from: 0).whenComplete(_startIdle);
      _syncBusy();
      return;
    }
    if (old.busy != widget.busy) _syncBusy();
    if (!old.active &&
        widget.active &&
        !_still &&
        _entrance.isCompleted &&
        !_idle.isAnimating &&
        !_hover.isAnimating) {
      final frames = _hoverFrames;
      if (frames <= 0) return;
      _hover
        ..duration = _frames(frames)
        ..forward(from: 0).whenCompleteOrCancel(_restHover);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    _hover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ExcludeSemantics(
      child: RepaintBoundary(
        // A sized box, not a sized paint: rows measuring intrinsic heights
        // (equal-height cards) see the art.
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(
            painter: _ArtPainter(
              art: widget.art,
              state: this,
              line: palette.contentMutedColor,
              accent: palette.primaryColor,
              soft: widget.hero
                  ? null
                  : widget.soft ?? palette.neutralAmbientColor,
              stroke: widget.hero ? YsArt.heroStroke : YsArt.stroke,
            ),
          ),
        ),
      ),
    );
  }
}

final class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.art,
    required this.state,
    required this.line,
    required this.accent,
    required this.soft,
    required this.stroke,
  }) : super(
         repaint: Listenable.merge([
           state._entrance,
           state._idle,
           state._hover,
         ]),
       );

  final YsArt art;
  final _YsArtViewState state;
  final Color line;
  final Color accent;

  /// Null leaves the soft disc out (a hero).
  final Color? soft;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = YsSvgShape.of(art.elements.join());
    final entrance = state._entrance;
    final drawing = entrance.value < 1;
    final entranceFrame = entrance.value * art.entranceFrames;
    // Idle: rest through the delay, then the cycles.
    double? idleFrame;
    if (state._idle.isAnimating) {
      final f =
          state._idle.value *
              (YsArtMotion.idleDelay +
                  YsArtMotion.idleCycles * art.idleFrames) -
          YsArtMotion.idleDelay;
      if (f >= 0) idleFrame = f % art.idleFrames;
    }
    // Hover: its own motion, or one idle cycle.
    final hovering = state._hover.isAnimating;
    final hoverOwn = art.hover.isNotEmpty;
    final hoverFrame =
        state._hover.value * (hoverOwn ? art.hoverFrames : art.idleFrames);
    if (hovering && !hoverOwn) idleFrame = hoverFrame;

    canvas.scale(size.width / YsArt.viewBox, size.height / YsArt.viewBox);
    for (var i = 0; i < shapes.length; i++) {
      final color = switch (art.parts[i].ink) {
        YsArtInk.line => line,
        YsArtInk.accent => accent,
        YsArtInk.soft => soft,
      };
      if (color == null) continue;
      final layers = <(YsPartMotion, double)>[
        if (drawing) (art.entrancePart(i), entranceFrame),
        if (idleFrame != null) ?_at(art.idlePart(i), idleFrame),
        if (hovering && hoverOwn) ?_at(art.hoverPart(i), hoverFrame),
      ];
      var opacity = 1.0;
      for (final (motion, frame) in layers) {
        opacity *= motion.valueAt(YsMotionProperty.opacity, frame);
      }
      if (opacity <= 0) continue;
      canvas.save();
      for (final (motion, frame) in layers) {
        ysTransformPart(canvas, motion, frame);
      }
      // The last layer that trims the stroke draws it.
      var path = shapes[i].path;
      for (final (motion, frame) in layers.reversed) {
        final trimmed = ysPartPath(path, motion, frame);
        if (!identical(trimmed, path)) {
          path = trimmed;
          break;
        }
      }
      shapes[i].paint(
        canvas,
        path,
        color.withValues(alpha: color.a * opacity.clamp(0, 1)),
        stroke,
      );
      canvas.restore();
    }
  }

  static (YsPartMotion, double)? _at(YsPartMotion? motion, double frame) =>
      motion == null ? null : (motion, frame);

  @override
  bool shouldRepaint(_ArtPainter old) =>
      old.art != art ||
      old.state != state ||
      old.line != line ||
      old.accent != accent ||
      old.soft != soft ||
      old.stroke != stroke;
}
