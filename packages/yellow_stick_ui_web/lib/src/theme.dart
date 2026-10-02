import 'package:jaspr/dom.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Global Yellow Stick theme: custom properties from [YsPalette.light] with
/// dark overrides under `prefers-color-scheme` / `[data-theme]`, the
/// Inter `@font-face`, and body reset.
///
/// Consumed in styles via `Color.variable('<token>')` (rendered
/// `var(--<token>)`).
@css
List<StyleRule> get ysThemeStyles => [
  css.fontFace(family: YsType.family, url: '/fonts/InterVariable.woff2'),
  css(':root').styles(
    raw: {
      'color-scheme': 'light dark',
      for (final MapEntry(key: name, value: color)
          in YsPalette.light.byCssName.entries)
        '--$name': color.css,
    },
  ),
  css.media(MediaQuery.raw('(prefers-color-scheme: dark)'), [
    css(':root:not([data-theme="light"])').styles(
      raw: {
        for (final MapEntry(key: name, value: color)
            in YsPalette.dark.byCssName.entries)
          '--$name': color.css,
      },
    ),
  ]),
  css(':root[data-theme="dark"]').styles(
    raw: {
      for (final MapEntry(key: name, value: color)
          in YsPalette.dark.byCssName.entries)
        '--$name': color.css,
    },
  ),
  css(':root[data-theme="light"]').styles(
    raw: {
      for (final MapEntry(key: name, value: color)
          in YsPalette.light.byCssName.entries)
        '--$name': color.css,
    },
  ),
  css('html, body').styles(
    width: 100.percent,
    minHeight: 100.vh,
    padding: .zero,
    margin: .zero,
    color: .variable('--content'),
    backgroundColor: .variable('--canvas'),
    fontFamily: .list([
      FontFamily(YsType.family),
      FontFamily('system-ui'),
      FontFamilies.sansSerif,
    ]),
  ),
  css('body').styles(raw: {'-webkit-font-smoothing': 'antialiased'}),
  css('*, *::before, *::after').styles(boxSizing: .borderBox),
];

/// Shorthand access to the theme custom properties as [Color]s.
abstract final class YsTheme {
  static Color get canvas => .variable('--canvas');
  static Color get paper => .variable('--paper');
  static Color get paperClear => .variable('--paper-clear');
  static Color get neutralAmbient => .variable('--neutral-ambient');
  static Color get neutralFilm => .variable('--neutral-film');
  static Color get content => .variable('--content');
  static Color get contentMuted => .variable('--content-muted');
  static Color get contentSubtle => .variable('--content-subtle');
  static Color get primary => .variable('--primary');
  static Color get primary2 => .variable('--primary-2');
  static Color get primaryMuted => .variable('--primary-muted');
  static Color get primaryWash => .variable('--primary-wash');
  static Color get primaryContent => .variable('--primary-content');
  static Color get line => .variable('--line');
  static Color get backdrop => .variable('--backdrop');
  static Color get success => .variable('--success');
  static Color get successMuted => .variable('--success-muted');
  static Color get error => .variable('--error');
  static Color get errorWash => .variable('--error-wash');
  static Color get logoSurface => .variable('--logo-surface');
  static Color get avatarSurface => .variable('--avatar-surface');
  static Color get shadow => .variable('--shadow');
}
