/// Corner radii (logical px).
abstract final class YsRadius {
  /// Fully rounded: pills, circular buttons.
  static const pill = 999.0;

  /// Chat bubbles and cards.
  static const bubble = 22.0;

  /// The corner of a bubble that continues a group (tail side).
  static const bubbleTail = 6.0;

  /// Composer.
  static const composer = 32.0;

  /// Segments inside a segmented track.
  static const segment = 16.0;

  /// List rows (activity, flights).
  static const row = 10.0;

  /// Navigation rows (library / side nav).
  static const navRow = 12.0;

  /// Choice options.
  static const option = 10.0;
}

/// Spacing scale (logical px).
abstract final class YsSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Hairline width used for borders and dividers.
const ysHairline = 1.2;

/// Liquid glass: the backdrop of a floating control is blurred by [blur]
/// px and saturated by [saturation], then tinted with the palette `glass`
/// roles. Flutter kit `YsGlass`, web kit class `ys-glass`.
abstract final class YsGlassMaterial {
  static const blur = 20.0;
  static const saturation = 1.8;
}

/// Motion timings (milliseconds).
abstract final class YsMotion {
  static const fast = 120;
  static const base = 200;
  static const slow = 320;
}
