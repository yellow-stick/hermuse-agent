import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Title of a browser task on the card and the viewer: its thread's title,
/// or `Browser session` while the thread has none.
String browserTaskTitle(String threadTitle) =>
    threadTitle.isEmpty ? 'Browser session' : threadTitle;

/// Muse's action blue: Take control of the browser, the working globe.
const browserBlue = YsColor(0xFF1793FF);

/// Muse's grey pill: Open browser / Open preview, Stop while in control.
const browserPillGrey = YsColor(0xFF525456);

/// Browser glyphs the core icon set lacks, drawn like [YsIcon]: 24-unit
/// viewBox, round 1.75 strokes (Lucide geometry, ISC License).
enum BrowserGlyph {
  /// Lucide `globe`: the agent's browser at work, the page in front.
  globe(
    '<circle cx="12" cy="12" r="10"/>'
    '<path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>'
    '<path d="M2 12h20"/>',
  ),

  /// Globe with a check: a finished browser task.
  globeCheck(
    '<path d="M21 12a9 9 0 1 0-9 9"/><path d="M3.6 9h16.8"/>'
    '<path d="M3.6 15H11"/><path d="M11.5 3a17 17 0 0 0 0 18"/>'
    '<path d="M12.5 3a17 17 0 0 1 3 8"/><path d="m15 18.5 2 2 4.5-4.5"/>',
  ),

  /// A ring around a dot: Stop.
  record(
    '<circle cx="12" cy="12" r="9"/>'
    '<circle cx="12" cy="12" r="4" fill="currentColor" stroke="none"/>',
  );

  const BrowserGlyph(this.body);

  /// Inner SVG markup; `currentColor` takes the icon colour.
  final String body;
}

/// [glyph] in [color], [size] px square.
final class BrowserGlyphIcon extends StatelessWidget {
  const BrowserGlyphIcon(
    this.glyph, {
    required this.color,
    this.size = 20,
    super.key,
  });

  final BrowserGlyph glyph;
  final YsColor color;
  final double size;

  @override
  Widget build(BuildContext context) => YsIconWidget.raw(
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="${color.css}" '
    'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
    '${glyph.body.replaceAll('currentColor', color.css)}</svg>',
    size: size,
  );
}

/// Muse's 36 px pill buttons around the browser (Open browser, Take control
/// of the browser / Done, Stop). A pill without [background] is bare and
/// washes on hover; a filled one lightens on hover and darkens while
/// pressed. It hugs its label unless its parent sets its width.
final class BrowserPill extends StatelessWidget {
  const BrowserPill({
    required this.label,
    required this.onPressed,
    required this.foreground,
    this.background,
    this.leading,
    this.semanticLabel,
    this.radius = YsRadius.pill,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    super.key,
  });

  final String label;

  /// Null disables the pill (half opacity).
  final VoidCallback? onPressed;

  /// Label colour.
  final Color foreground;
  final Color? background;

  /// Icon before the label.
  final Widget? leading;

  /// Accessible name when it differs from [label].
  final String? semanticLabel;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final enabled = onPressed != null;
    final leading = this.leading;
    // One node per button, named by its label (as YsButton).
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      child: YsPressable(
        onPressed: onPressed,
        excludeSemantics: true,
        builder: (context, state) {
          final background = this.background;
          final fill = background == null
              ? (state.hovered || state.pressed
                    ? palette.neutralWashColor
                    : const Color(0x00000000))
              : _brightness(
                  background,
                  state.pressed
                      ? 0.9
                      : state.hovered
                      ? 1.15
                      : 1,
                );
          return ExcludeSemantics(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: YsMotion.fast),
                height: 36,
                padding: padding,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: Center(
                  widthFactor: 1,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leading != null) ...[
                        leading,
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        style: YsType.label.flutter.copyWith(color: foreground),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// CSS `filter: brightness(factor)` applied to an opaque [color].
Color _brightness(Color color, double factor) => Color.from(
  alpha: color.a,
  red: (color.r * factor).clamp(0, 1),
  green: (color.g * factor).clamp(0, 1),
  blue: (color.b * factor).clamp(0, 1),
);

/// Encoded picture [bytes] (the computer's JPEG frames and thumbnails),
/// decoded outside the image cache: each new picture replaces the previous
/// one, which stays on screen until the new one is decoded. Pictures that
/// arrive during a decode are skipped but the latest.
final class FrameImage extends StatefulWidget {
  const FrameImage(this.bytes, {this.fit = BoxFit.contain, super.key});

  final Uint8List bytes;
  final BoxFit fit;

  @override
  State<FrameImage> createState() => _FrameImageState();
}

final class _FrameImageState extends State<FrameImage> {
  ui.Image? _image;
  bool _decoding = false;
  Uint8List? _next;

  @override
  void initState() {
    super.initState();
    _decode(widget.bytes);
  }

  @override
  void didUpdateWidget(FrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bytes, oldWidget.bytes)) _decode(widget.bytes);
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _decode(Uint8List bytes) {
    if (_decoding) {
      _next = bytes;
      return;
    }
    _decoding = true;
    unawaited(_run(bytes));
  }

  Future<void> _run(Uint8List bytes) async {
    ui.Image? image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        image = (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } on Exception {
      // A corrupt picture leaves the previous one on screen.
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    if (image != null) {
      final decoded = image;
      setState(() {
        _image?.dispose();
        _image = decoded;
      });
    }
    _decoding = false;
    if (_next case final next?) {
      _next = null;
      _decode(next);
    }
  }

  @override
  Widget build(BuildContext context) =>
      RawImage(image: _image, fit: widget.fit);
}
