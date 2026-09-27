import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_theme.dart';

/// Renders a core [YsIcon] (or any raw SVG string) at [size].
final class YsIconWidget extends StatelessWidget {
  const YsIconWidget(
    this.icon, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.75,
    this.semanticLabel,
  }) : rawSvg = null;

  /// Renders raw SVG markup (avatar, status glyph) at [size].
  const YsIconWidget.raw(
    this.rawSvg, {
    super.key,
    this.size = 24,
    this.color,
    this.strokeWidth = 1.75,
    this.semanticLabel,
  }) : icon = null;

  final YsIcon? icon;
  final String? rawSvg;
  final double size;
  final Color? color;
  final double strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final resolved = color ?? palette.contentColor;
    final raw = rawSvg;
    final svg = raw ?? icon!.svg(color: '#ffffff', strokeWidth: strokeWidth);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: raw == null
          ? ColorFilter.mode(resolved, BlendMode.srcIn)
          : null,
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
    );
  }
}
