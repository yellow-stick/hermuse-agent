/// Font weights used by the system (CSS numeric weights).
enum YsWeight {
  regular(400),
  medium(500),
  semibold(600);

  const YsWeight(this.value);
  final int value;
}

/// One text style: size, line height (both logical px) and weight.
final class YsTextStyle {
  const YsTextStyle(
    this.size,
    this.lineHeight, [
    this.weight = YsWeight.regular,
  ]);

  final double size;
  final double lineHeight;
  final YsWeight weight;

  /// Line height as a multiple of [size] (Flutter `TextStyle.height`).
  double get heightFactor => lineHeight / size;
}

/// The type scale. Family is Inter (SIL OFL 1.1), bundled by each kit.
abstract final class YsType {
  static const family = 'Inter';

  /// CSS fallback stack after [family].
  static const fallback = ['system-ui', 'sans-serif'];

  /// Route headers (Feed, Library, Goals).
  static const display = YsTextStyle(34, 40, YsWeight.semibold);

  /// Display name in the profile panel.
  static const title = YsTextStyle(22, 28, YsWeight.medium);

  /// User chat bubbles.
  static const bubble = YsTextStyle(16, 24);

  /// Paragraphs inside agent messages.
  static const agentBubble = YsTextStyle(15, 24);

  /// Choice option rows.
  static const choiceOption = YsTextStyle(15, 24);

  /// Sidebar / library navigation rows.
  static const navRow = YsTextStyle(16, 24);

  /// Feed/library prose.
  static const body = YsTextStyle(16, 22);

  /// Section headings ("Today"), pill labels ("Chats").
  static const heading = YsTextStyle(16, 22, YsWeight.medium);

  /// Composer input.
  static const input = YsTextStyle(15, 24);

  /// Status line under the name ("Connected").
  static const status = YsTextStyle(17, 22);

  /// Card titles, airline names, activity titles, small buttons.
  static const label = YsTextStyle(14, 20, YsWeight.medium);

  /// Secondary rows: activity descriptions, flight times.
  static const small = YsTextStyle(13, 18);

  /// Timestamps, totals, time-ago.
  static const caption = YsTextStyle(12, 16);

  /// Duration chips.
  static const micro = YsTextStyle(11, 13);

  /// Monogram inside logo discs.
  static const monogram = YsTextStyle(14, 20, YsWeight.semibold);
}
