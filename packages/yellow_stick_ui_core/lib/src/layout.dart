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

  /// Status badge of a setup checklist row: the ring's outer diameter.
  static const stepBadge = 36.0;

  /// Glyph inside a [stepBadge].
  static const stepGlyph = 18.0;

  /// Stroke of a step badge's ring and arc.
  static const stepRingStroke = 2.0;

  /// Stroke of a step glyph, in 24-unit viewBox space (1.5 px at
  /// [stepGlyph]).
  static const stepGlyphStroke = 2.0;

  /// Overall progress ring of a setup card's header.
  static const progressRing = 44.0;

  /// Stroke of the [progressRing].
  static const progressRingStroke = 3.0;

  /// Tallest a technical log box grows before it scrolls.
  static const logMaxHeight = 160.0;

  /// Icon beside a line of label text (a disclosure's chevron), or leading
  /// the text of an input box.
  static const inlineIcon = 16.0;

  /// Soft ring of `primaryMuted` around a focused input box, outside it.
  static const inputHalo = 3.0;

  /// Illustration of a page's empty state (Feed, Ideas, Library…).
  static const artEmpty = 88.0;

  /// Illustration of an empty state in a side column (chats, panel tabs).
  static const artCompact = 72.0;

  /// Illustration of a big choice card (welcome).
  static const artChoice = 80.0;

  /// Narrowest a choice card gets beside another: its title stays on one
  /// line.
  static const choiceMin = 292.0;

  /// Illustration heading an onboarding step or a dialog card (an error
  /// card).
  static const artStep = 80.0;

  /// Illustration beside a dialog's title (Add a Hermes).
  static const artHeader = 64.0;

  /// The mascot on the welcome screen: its height, and the width of the
  /// rounded stage behind it.
  static const mascotHeight = 200.0;
  static const mascotStageWidth = 132.0;

  /// The mascot greeting in an onboarding step.
  static const mascotSmallHeight = 132.0;
  static const mascotSmallStageWidth = 88.0;

  /// Status badge of an onboarding stepper step, and the line joining two.
  static const stepperBadge = 28.0;
  static const stepperLine = 2.0;

  /// Marker of the rail's current destination, on the rail's left edge.
  static const railMarkerWidth = 3.0;
  static const railMarkerHeight = 20.0;

  /// Sparks around a completed check ([YsBurst] viewBox).
  static const burst = 44.0;

  /// Connection status dot.
  static const statusDot = 8.0;

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
