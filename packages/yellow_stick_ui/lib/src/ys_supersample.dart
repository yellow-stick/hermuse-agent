import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Times the device resolution a drawing is rendered at by [ysSupersample].
const ysSupersampling = 3;

/// Draws [draw] (in a [size] box) through a picture [ysSupersampling] times
/// larger than the device pixels, then samples it back down onto [canvas].
///
/// Impeller's OpenGL ES backend has no multisampling on some drivers (the
/// NVIDIA desktop one among them), so a path drawn straight onto the canvas
/// has hard stair-step edges, even with `isAntiAlias`. Filtering a larger
/// picture down gives the edges their gray levels on every backend.
void ysSupersample(
  Canvas canvas,
  Size size,
  double pixelRatio,
  void Function(Canvas canvas) draw,
) {
  if (size.isEmpty) return;
  final scale = pixelRatio * ysSupersampling;
  final width = (size.width * scale).round();
  final height = (size.height * scale).round();
  final recorder = ui.PictureRecorder();
  final inner = Canvas(recorder)
    ..scale(width / size.width, height / size.height);
  draw(inner);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.medium,
  );
  image.dispose();
}
