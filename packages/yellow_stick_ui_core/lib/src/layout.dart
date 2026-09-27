/// App-shell metrics shared by every surface (logical px).
abstract final class YsLayout {
  /// Width of the navigation rail.
  static const railWidth = 72.0;

  /// Height of one rail destination.
  static const railItemHeight = 56.0;

  /// Size of rail destination icons.
  static const railIconSize = 32.0;

  /// Stroke width of rail icons in 24-unit viewBox space: ~1.8 px at
  /// [railIconSize], the weight of the rail glyphs.
  static const railIconStroke = 1.35;

  /// Width of the collapsible side-chats column.
  static const sidebarWidth = 240.0;

  /// Width of the docked profile panel.
  static const panelWidth = 360.0;

  /// Maximum width of the conversation column (messages and composer).
  static const threadMaxWidth = 768.0;

  /// Side padding inside the thread column (desktop).
  static const threadGutter = 24.0;

  /// Side padding inside the thread column (phone).
  static const threadGutterPhone = 16.0;

  /// Top padding of the thread scroller (clears the floating header).
  static const threadTopPad = 72.0;

  /// Bottom padding of the thread scroller.
  static const threadBottomPad = 32.0;

  /// Maximum width of a user bubble (px cap).
  static const userBubbleMaxWidth = 520.0;

  /// Maximum width of an agent bubble, as a fraction of the column.
  static const agentBubbleMaxFraction = 0.85;

  /// Diameter of the reaction chip.
  static const reactionSize = 40.0;

  /// Size of the activity-row tile in the profile panel.
  static const activityTileSize = 40.0;

  /// Width of a structured card (flight results).
  static const cardWidth = 345.0;

  /// Width of dialog cards (welcome, relay-required).
  static const dialogWidth = 480.0;

  /// Width of narrow dialog cards (add-instance, boot).
  static const dialogNarrow = 420.0;

  /// Width of list cards (instances).
  static const listWidth = 640.0;

  /// Height of the composer bar.
  static const composerHeight = 58.0;

  /// Height of floating pills (Chats, Invite).
  static const pillHeight = 36.0;

  /// Height of the phone bottom navigation bar.
  static const bottomNavHeight = 52.0;

  /// Size of the phone bottom navigation icons.
  static const bottomNavIconSize = 28.0;

  /// At or above this width the panel docks beside the thread.
  static const wideMin = 768.0;

  /// Below this width the app switches to the compact (phone) shell.
  static const compactMax = 768.0;
}

/// Shell variant for a given viewport width.
enum YsShell {
  compact,
  medium,
  wide;

  static YsShell forWidth(double width) => width >= YsLayout.wideMin
      ? wide
      : width < YsLayout.compactMax
      ? compact
      : medium;
}
