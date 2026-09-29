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
    required this.neutralAmbient,
    required this.neutralFilm,
    required this.content,
    required this.contentMuted,
    required this.contentSubtle,
    required this.primary,
    required this.primary2,
    required this.primaryMuted,
    required this.primaryWash,
    required this.primaryContent,
    required this.line,
    required this.backdrop,
    required this.success,
    required this.successMuted,
    required this.error,
    required this.errorWash,
    required this.logoSurface,
    required this.avatarSurface,
  });

  /// App background.
  final YsColor canvas;

  /// Raised surface: agent bubbles, cards.
  final YsColor paper;

  /// Translucent chrome: pills, composer, floating buttons.
  final YsColor paperClear;

  /// Solid neutral fill: tab track, avatar badges, monogram logos.
  final YsColor neutralAmbient;

  /// Selected segment inside a neutral track, hover wash.
  final YsColor neutralFilm;

  /// Primary text and icons.
  final YsColor content;

  /// Secondary text: timestamps, captions, inactive icons.
  final YsColor contentMuted;

  /// Tertiary text: totals, placeholders.
  final YsColor contentSubtle;

  /// Brand accent: user bubbles, primary actions, selection.
  final YsColor primary;

  /// Pressed/hovered accent.
  final YsColor primary2;

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

  /// Positive wash: behind a check that was already in place.
  final YsColor successMuted;

  /// Negative status (errors, destructive actions).
  final YsColor error;

  /// Faint negative wash behind a failed row.
  final YsColor errorWash;

  /// Light disc behind airline marks.
  final YsColor logoSurface;

  /// Warm light disc behind transparent avatar artwork, so dark artwork stays
  /// readable on [canvas].
  final YsColor avatarSurface;

  /// Yellow Stick dark theme: near-black canvas, warm professional yellow.
  static const dark = YsPalette(
    canvas: YsColor(0xFF181819),
    paper: YsColor(0xFF1F1F20),
    paperClear: YsColor(0xCC383838),
    neutralAmbient: YsColor(0xFF28292B),
    neutralFilm: YsColor(0xFF3A3B3E),
    content: YsColor(0xFFFFFFFF),
    contentMuted: YsColor(0x87F2F7FF),
    contentSubtle: YsColor(0x61F1F6FF),
    primary: YsColor(0xFFF5C21B),
    primary2: YsColor(0xFFFFD44D),
    primaryMuted: YsColor(0x29F5C21B),
    primaryWash: YsColor(0x14F5C21B),
    primaryContent: YsColor(0xFF1A1505),
    line: YsColor(0x1FFFFFFF),
    backdrop: YsColor(0x8C000000),
    success: YsColor(0xFF07B123),
    successMuted: YsColor(0x2907B123),
    error: YsColor(0xFFE5484D),
    errorWash: YsColor(0x14E5484D),
    logoSurface: YsColor(0xFFFFFFFF),
    avatarSurface: YsColor(0xFFEDE7DF),
  );

  /// Every role by its CSS custom-property name (`--paper-clear`, ...).
  Map<String, YsColor> get byCssName => {
    'canvas': canvas,
    'paper': paper,
    'paper-clear': paperClear,
    'neutral-ambient': neutralAmbient,
    'neutral-film': neutralFilm,
    'content': content,
    'content-muted': contentMuted,
    'content-subtle': contentSubtle,
    'primary': primary,
    'primary-2': primary2,
    'primary-muted': primaryMuted,
    'primary-wash': primaryWash,
    'primary-content': primaryContent,
    'line': line,
    'backdrop': backdrop,
    'success': success,
    'success-muted': successMuted,
    'error': error,
    'error-wash': errorWash,
    'logo-surface': logoSurface,
    'avatar-surface': avatarSurface,
  };
}
