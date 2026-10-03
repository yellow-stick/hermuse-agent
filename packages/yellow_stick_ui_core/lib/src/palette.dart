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
    required this.glass,
    required this.glassShine,
    required this.glassRim,
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
    required this.soulStart,
    required this.soulEnd,
    required this.memoryStart,
    required this.memoryEnd,
    required this.identityContent,
  });

  /// App background.
  final YsColor canvas;

  /// Raised surface: agent bubbles, cards.
  final YsColor paper;

  /// Translucent chrome: pills, composer, floating buttons.
  final YsColor paperClear;

  /// Hairline ring around raised [paper] and [paperClear] surfaces resting on
  /// [canvas]: dark ink in light, a faint light rim in dark, where a shadow
  /// alone would not read.
  final YsColor paperEdge;

  /// Resting shadow under the same raised surfaces.
  final YsColor paperShadow;

  /// Liquid glass tint over the blurred, saturated backdrop: floating
  /// header controls (Chats pill, agent switcher). See [YsGlassMaterial].
  final YsColor glass;

  /// Sheen washing down from the top edge of [glass] and the dim end of
  /// its rim.
  final YsColor glassShine;

  /// Specular rim along the top edge of [glass].
  final YsColor glassRim;

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

  /// Warm gradient of the Identity SOUL card, top-left [soulStart] to
  /// bottom-right [soulEnd].
  final YsColor soulStart;
  final YsColor soulEnd;

  /// Cool gradient of the Identity MEMORY card, top-left [memoryStart] to
  /// bottom-right [memoryEnd].
  final YsColor memoryStart;
  final YsColor memoryEnd;

  /// Text and glyphs drawn on the SOUL and MEMORY gradients.
  final YsColor identityContent;

  /// Yellow Stick dark theme: near-black canvas, raised surfaces a step
  /// lighter with a faint rim, warm off-white text, warm professional
  /// yellow. Text and ink stay readable (WCAG AA) on every surface.
  static const dark = YsPalette(
    canvas: YsColor(0xFF181819),
    paper: YsColor(0xFF222224),
    paperClear: YsColor(0xD9303033),
    paperEdge: YsColor(0x13FFFFFF),
    paperShadow: YsColor(0x38000000),
    glass: YsColor(0x5C2A2A2D),
    glassShine: YsColor(0x14FFFFFF),
    glassRim: YsColor(0x47FFFFFF),
    neutralAmbient: YsColor(0xFF2A2A2D),
    neutralFilm: YsColor(0xFF3A3A3E),
    neutralWash: YsColor(0x663A3A3E),
    content: YsColor(0xFFF2F2F0),
    contentMuted: YsColor(0x99F2F2F0),
    contentSubtle: YsColor(0x6BF2F2F0),
    primary: YsColor(0xFFF5C21B),
    primary2: YsColor(0xFFFFD44D),
    primaryInk: YsColor(0xFFF5C21B),
    primaryMuted: YsColor(0x29F5C21B),
    primaryWash: YsColor(0x14F5C21B),
    primaryContent: YsColor(0xFF1A1505),
    line: YsColor(0x1FF2F2F0),
    backdrop: YsColor(0x8C000000),
    success: YsColor(0xFF07B123),
    successMuted: YsColor(0x2907B123),
    info: YsColor(0xFF5B9BFF),
    infoMuted: YsColor(0x295B9BFF),
    error: YsColor(0xFFF0656A),
    errorWash: YsColor(0x14F0656A),
    errorContent: YsColor(0xFF1F0A0B),
    logoSurface: YsColor(0xFFFFFFFF),
    avatarSurface: YsColor(0xFFEDE7DF),
    shadow: YsColor(0x73000000),
    soulStart: YsColor(0xFFE9B48C),
    soulEnd: YsColor(0xFFD9817A),
    memoryStart: YsColor(0xFF9CC3E6),
    memoryEnd: YsColor(0xFFA9A4E0),
    identityContent: YsColor(0xFF1C1712),
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
    glass: YsColor(0x8CFFFFFF),
    glassShine: YsColor(0x80FFFFFF),
    glassRim: YsColor(0xF2FFFFFF),
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
    soulStart: YsColor(0xFFF8D2B0),
    soulEnd: YsColor(0xFFEFA59A),
    memoryStart: YsColor(0xFFC3DDF4),
    memoryEnd: YsColor(0xFFC9C3F0),
    identityContent: YsColor(0xFF1C1712),
  );

  /// Every role by its CSS custom-property name (`--paper-clear`, ...).
  Map<String, YsColor> get byCssName => {
    'canvas': canvas,
    'paper': paper,
    'paper-clear': paperClear,
    'paper-edge': paperEdge,
    'paper-shadow': paperShadow,
    'glass': glass,
    'glass-shine': glassShine,
    'glass-rim': glassRim,
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
    'soul-start': soulStart,
    'soul-end': soulEnd,
    'memory-start': memoryStart,
    'memory-end': memoryEnd,
    'identity-content': identityContent,
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
