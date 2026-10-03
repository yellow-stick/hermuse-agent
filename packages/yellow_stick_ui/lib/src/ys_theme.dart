import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Flutter [Color] view of a core [YsPalette].
///
/// Components read roles from here, never hex literals.
extension YsFlutterPalette on YsPalette {
  Color get canvasColor => Color(canvas.value);
  Color get paperColor => Color(paper.value);
  Color get paperClearColor => Color(paperClear.value);
  Color get paperEdgeColor => Color(paperEdge.value);
  Color get paperShadowColor => Color(paperShadow.value);
  Color get glassColor => Color(glass.value);
  Color get glassShineColor => Color(glassShine.value);
  Color get glassRimColor => Color(glassRim.value);
  Color get neutralAmbientColor => Color(neutralAmbient.value);
  Color get neutralFilmColor => Color(neutralFilm.value);
  Color get neutralWashColor => Color(neutralWash.value);
  Color get contentColor => Color(content.value);
  Color get contentMutedColor => Color(contentMuted.value);
  Color get contentSubtleColor => Color(contentSubtle.value);
  Color get primaryColor => Color(primary.value);
  Color get primary2Color => Color(primary2.value);
  Color get primaryInkColor => Color(primaryInk.value);
  Color get primaryMutedColor => Color(primaryMuted.value);
  Color get primaryWashColor => Color(primaryWash.value);
  Color get primaryContentColor => Color(primaryContent.value);
  Color get lineColor => Color(line.value);
  Color get backdropColor => Color(backdrop.value);
  Color get successColor => Color(success.value);
  Color get successMutedColor => Color(successMuted.value);
  Color get infoColor => Color(info.value);
  Color get infoMutedColor => Color(infoMuted.value);
  Color get errorColor => Color(error.value);
  Color get errorWashColor => Color(errorWash.value);
  Color get errorContentColor => Color(errorContent.value);
  Color get logoSurfaceColor => Color(logoSurface.value);
  Color get avatarSurfaceColor => Color(avatarSurface.value);
  Color get shadowColor => Color(shadow.value);

  /// Resting elevation of a raised [paper]/[paperClear] surface on [canvas]:
  /// a hairline ring and a soft two-step shadow (empty for a palette with
  /// neither). Web kit: `box-shadow: var(--raised)`.
  List<BoxShadow> get raisedShadows =>
      paperEdge.alpha == 0 && paperShadow.alpha == 0
      ? const []
      : [
          BoxShadow(color: paperEdgeColor, spreadRadius: 1),
          BoxShadow(
            color: paperShadowColor,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: paperShadowColor,
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ];
}

extension YsFlutterType on YsTextStyle {
  /// Converts a core text style to a Flutter [TextStyle] in Inter.
  TextStyle get flutter => TextStyle(
    fontFamily: YsType.family,
    package: 'yellow_stick_ui',
    fontSize: size,
    height: heightFactor,
    fontWeight: switch (weight) {
      YsWeight.regular => FontWeight.w400,
      YsWeight.medium => FontWeight.w500,
      YsWeight.semibold => FontWeight.w600,
    },
    leadingDistribution: TextLeadingDistribution.even,
  );
}

extension YsFlutterEase on YsEase {
  /// The same cubic-bezier as a Flutter [Curve].
  Curve get curve => Cubic(x1, y1, x2, y2);
}

/// Provides the [YsPalette] to the widget subtree.
final class YsTheme extends InheritedWidget {
  const YsTheme({required this.palette, required super.child, super.key});

  final YsPalette palette;

  static YsPalette of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<YsTheme>();
    assert(theme != null, 'No YsTheme found in context');
    return theme!.palette;
  }

  /// Reads the palette without registering a dependency.
  static YsPalette read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<YsTheme>();
    assert(element != null, 'No YsTheme found in context');
    return (element!.widget as YsTheme).palette;
  }

  @override
  bool updateShouldNotify(YsTheme oldWidget) => palette != oldWidget.palette;
}
