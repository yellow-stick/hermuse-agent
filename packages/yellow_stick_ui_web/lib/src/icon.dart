import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// An icon rendered as inline SVG inheriting the text colour (`currentColor`).
class YsIconView extends StatelessComponent {
  const YsIconView(
    this.icon, {
    this.size = 18,
    this.strokeWidth = 1.75,
    super.key,
  });

  final YsIcon icon;
  final double size;
  final double strokeWidth;

  @override
  Component build(BuildContext context) => span(
    classes: 'ys-icon',
    styles: Styles(width: size.px, height: size.px),
    [RawText(icon.svg(strokeWidth: strokeWidth))],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-icon', [
      css('&').styles(
        display: .inlineFlex,
        justifyContent: .center,
        alignItems: .center,
        // Clicks must land on the control, not on the SVG: pressables
        // rebuild on mousedown and the re-rendered SVG would detach the
        // mousedown target, so the browser fires no click at all.
        raw: {'flex-shrink': '0', 'pointer-events': 'none'},
      ),
      css('svg')
          .styles(width: 100.percent, height: 100.percent, display: .block),
    ]),
  ];
}
