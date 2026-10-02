/// A colour as 0xAARRGGBB, readable by Flutter (`Color(value)`) and CSS
/// ([YsColor.css]).
extension type const YsColor(int value) {
  int get alpha => (value >> 24) & 0xFF;
  int get red => (value >> 16) & 0xFF;
  int get green => (value >> 8) & 0xFF;
  int get blue => value & 0xFF;

  /// CSS `rgb()`/`rgba()` notation.
  String get css {
    if (alpha == 0xFF) return 'rgb($red, $green, $blue)';
    final a = (alpha / 255).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
    return 'rgba($red, $green, $blue, $a)';
  }
}

/// Semantic colour roles, named after the Luna token vocabulary.
///
/// Components read roles, never raw values, so a theme swap is one object.
final class YsPalette {
  const YsPalette({
    required this.canvas,
    required this.paper,
    required this.paperClear,
    required this.paperEdge,
    required this.paperShadow,
    required this.neutralAmbient,
    required this.neutralFilm,
    required this.neutralWash,
    required this.content,
    required this.contentMuted,
    required this.contentSubtle,
    required this.primary,
    required this.primary2,
    required this.primaryInk,
    required this.primaryMuted,
    required this.primaryWash,
    required this.primaryContent,
    required this.line,
    required this.backdrop,
    required this.success,
    required this.successMuted,
    required this.info,
    required this.infoMuted,
    required this.error,
    required this.errorWash,
    required this.errorContent,
    required this.logoSurface,
    required this.avatarSurface,
    required this.shadow,
  });

  /// App background.
  final YsColor canvas;

  /// Raised surface: agent bubbles, cards.
  final YsColor paper;

  /// Translucent chrome: pills, composer, floating buttons.
  final YsColor paperClear;

  /// Hairline ring around raised [paper] and [paperClear] surfaces resting on
  /// [canvas]. Transparent in dark, where tone alone lifts them.
  final YsColor paperEdge;

  /// Resting shadow under the same raised surfaces. Transparent in dark.
  final YsColor paperShadow;

  /// Solid neutral fill: tab track, avatar badges, monogram logos.
  final YsColor neutralAmbient;

  /// Selected segment inside a neutral track, hover fill.
  final YsColor neutralFilm;

  /// Faint hover wash where a full [neutralFilm] already marks the selected
  /// item (segmented tabs, panel rows, browser chrome). Translucent, so it
  /// reads on canvas, paper and a neutral track alike.
  final YsColor neutralWash;

  /// Primary text and icons.
  final YsColor content;

  /// Secondary text: timestamps, captions, inactive icons.
  final YsColor contentMuted;

  /// Tertiary text: totals, placeholders.
  final YsColor contentSubtle;

  /// Brand accent as a fill: user bubbles, primary actions, selection.
  final YsColor primary;

  /// Pressed/hovered accent fill.
  final YsColor primary2;

  /// Brand accent drawn as text, icon or stroke on [canvas]/[paper]: links,
  /// text actions, focus rings, selected outlines, active glyphs. Same as
  /// [primary] in dark; a deep gold in light, where the yellow fill is too
  /// pale to read.
  final YsColor primaryInk;

  /// Accent wash behind selected rows.
  final YsColor primaryMuted;

  /// Faint accent wash behind a row that waits on the user.
  final YsColor primaryWash;

  /// Text/icons drawn on [primary].
  final YsColor primaryContent;

  /// Hairlines, dashed option borders, dividers.
  final YsColor line;

  /// Scrim under drawers and sheets.
  final YsColor backdrop;

  /// Positive status (Connected).
  final YsColor success;

  /// Positive wash: behind the calm tick of a flow step the user has gone
  /// past.
  final YsColor successMuted;

  /// Informational status: something already in place, nothing done now.
  final YsColor info;

  /// Informational wash: behind the tick of a check already in place.
  final YsColor infoMuted;

  /// Negative status (errors, destructive actions).
  final YsColor error;

  /// Faint negative wash behind a failed row.
  final YsColor errorWash;

  /// Text/icons drawn on [error] (destructive buttons).
  final YsColor errorContent;

  /// Light disc behind airline marks.
  final YsColor logoSurface;

  /// Warm light disc behind transparent avatar artwork, so dark artwork stays
  /// readable on [canvas].
  final YsColor avatarSurface;

  /// Soft shadow under a card lifted by the pointer.
  final YsColor shadow;

  /// Yellow Stick dark theme: near-black canvas, warm professional yellow.
  static const dark = YsPalette(
    canvas: YsColor(0xFF181819),
    paper: YsColor(0xFF1F1F20),
    paperClear: YsColor(0xCC383838),
    paperEdge: YsColor(0x00000000),
    paperShadow: YsColor(0x00000000),
    neutralAmbient: YsColor(0xFF28292B),
    neutralFilm: YsColor(0xFF3A3B3E),
    neutralWash: YsColor(0x663A3B3E),
    content: YsColor(0xFFFFFFFF),
    contentMuted: YsColor(0x87F2F7FF),
    contentSubtle: YsColor(0x61F1F6FF),
    primary: YsColor(0xFFF5C21B),
    primary2: YsColor(0xFFFFD44D),
    primaryInk: YsColor(0xFFF5C21B),
    primaryMuted: YsColor(0x29F5C21B),
    primaryWash: YsColor(0x14F5C21B),
    primaryContent: YsColor(0xFF1A1505),
    line: YsColor(0x1FFFFFFF),
    backdrop: YsColor(0x8C000000),
    success: YsColor(0xFF07B123),
    successMuted: YsColor(0x2907B123),
    info: YsColor(0xFF3B82F6),
    infoMuted: YsColor(0x293B82F6),
    error: YsColor(0xFFE5484D),
    errorWash: YsColor(0x14E5484D),
    errorContent: YsColor(0xFFFFFFFF),
    logoSurface: YsColor(0xFFFFFFFF),
    avatarSurface: YsColor(0xFFEDE7DF),
    shadow: YsColor(0x73000000),
  );

  /// Yellow Stick light theme: soft neutral canvas, white raised surfaces
  /// lifted by a hairline ring and a resting shadow, yellow fills with gold
  /// ink. Text and ink stay readable (WCAG AA) on every surface.
  static const light = YsPalette(
    canvas: YsColor(0xFFF5F5F3),
    paper: YsColor(0xFFFFFFFF),
    paperClear: YsColor(0xF0FFFFFF),
    paperEdge: YsColor(0x12141412),
    paperShadow: YsColor(0x0F141412),
    neutralAmbient: YsColor(0xFFE9E9E6),
    neutralFilm: YsColor(0xFFDADAD6),
    neutralWash: YsColor(0x0F141412),
    content: YsColor(0xFF191917),
    contentMuted: YsColor(0xA3191917),
    contentSubtle: YsColor(0x7A191917),
    primary: YsColor(0xFFF5C21B),
    primary2: YsColor(0xFFE5B000),
    primaryInk: YsColor(0xFF8A6100),
    primaryMuted: YsColor(0x38F5C21B),
    primaryWash: YsColor(0x1FF5C21B),
    primaryContent: YsColor(0xFF1A1505),
    line: YsColor(0x24141412),
    backdrop: YsColor(0x66141412),
    success: YsColor(0xFF15803D),
    successMuted: YsColor(0x2915803D),
    info: YsColor(0xFF2563EB),
    infoMuted: YsColor(0x292563EB),
    error: YsColor(0xFFDC2626),
    errorWash: YsColor(0x14DC2626),
    errorContent: YsColor(0xFFFFFFFF),
    logoSurface: YsColor(0xFFFFFFFF),
    avatarSurface: YsColor(0xFFECE9E4),
    shadow: YsColor(0x2E141412),
  );

  /// Every role by its CSS custom-property name (`--paper-clear`, ...).
  Map<String, YsColor> get byCssName => {
    'canvas': canvas,
    'paper': paper,
    'paper-clear': paperClear,
    'paper-edge': paperEdge,
    'paper-shadow': paperShadow,
    'neutral-ambient': neutralAmbient,
    'neutral-film': neutralFilm,
    'neutral-wash': neutralWash,
    'content': content,
    'content-muted': contentMuted,
    'content-subtle': contentSubtle,
    'primary': primary,
    'primary-2': primary2,
    'primary-ink': primaryInk,
    'primary-muted': primaryMuted,
    'primary-wash': primaryWash,
    'primary-content': primaryContent,
    'line': line,
    'backdrop': backdrop,
    'success': success,
    'success-muted': successMuted,
    'info': info,
    'info-muted': infoMuted,
    'error': error,
    'error-wash': errorWash,
    'error-content': errorContent,
    'logo-surface': logoSurface,
    'avatar-surface': avatarSurface,
    'shadow': shadow,
  };
}

/// Which theme the app shows.
enum YsThemeMode { system, light, dark }

/// Resolves [mode] to a palette: [system] follows [platformDark].
YsPalette resolveTheme(YsThemeMode mode, {required bool platformDark}) =>
    switch (mode) {
      YsThemeMode.system => platformDark ? YsPalette.dark : YsPalette.light,
      YsThemeMode.light => YsPalette.light,
      YsThemeMode.dark => YsPalette.dark,
    };
