import 'package:jaspr/dom.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Shared route-page styles for the product screens (Feed, Ideas, Goals,
/// Library): route header + content column + cards.
List<StyleRule> get hermuseRouteStyles => [
  css('.hermuse-route', [
    css('&').styles(
      flex: .grow(1),
      height: 100.percent,
      display: .flex,
      flexDirection: .column,
      alignItems: .center,
      overflow: .only(y: .auto, x: .hidden),
      backgroundColor: .variable('--canvas'),
      raw: {'min-height': '0'},
    ),
    css('.hermuse-route-column').styles(
      width: 100.percent,
      maxWidth: YsLayout.threadMaxWidth.px,
      margin: .symmetric(horizontal: .auto),
      padding: .only(
        top: 72.px,
        left: YsLayout.threadGutter.px,
        right: YsLayout.threadGutter.px,
        bottom: 48.px,
      ),
      display: .flex,
      flexDirection: .column,
      gap: .all(24.px),
    ),
    css('.hermuse-route-wide').styles(maxWidth: 1152.px),
    css('.hermuse-route-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(12.px),
    ),
    css('.hermuse-route-title').styles(
      margin: .zero,
      flex: .grow(1),
      fontSize: 34.px,
      lineHeight: 40.px,
      fontWeight: .w600,
    ),
    css('.hermuse-route-sub').styles(
      margin: .zero,
      fontSize: 16.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-route-section')
        .styles(display: .flex, flexDirection: .column, gap: .all(12.px)),
    css('.hermuse-route-section-head').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
      color: .variable('--content'),
    ),
    css('.hermuse-route-error').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--primary-ink'),
    ),
  ]),
  css.media(MediaQuery.screen(maxWidth: 767.px), [
    css('.hermuse-shell .hermuse-route .hermuse-route-column').styles(
      padding: .only(
        top: 16.px,
        left: YsLayout.threadGutterPhone.px,
        right: YsLayout.threadGutterPhone.px,
        bottom: YsLayout.threadBottomPad.px,
      ),
    ),
  ]),
];
