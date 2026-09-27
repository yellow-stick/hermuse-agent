import 'models.dart';

/// Where a message sits inside a run of consecutive same-author messages.
///
/// Bubbles use it to shrink the corner that touches a neighbour.
enum GroupPosition {
  single,
  first,
  middle,
  last;

  /// A previous message by the same author sits directly above.
  bool get joinsAbove => this == middle || this == last;

  /// A next message by the same author sits directly below.
  bool get joinsBelow => this == first || this == middle;
}

GroupPosition groupPositionAt(List<Message> messages, int index) {
  final author = messages[index].author;
  final above = index > 0 && messages[index - 1].author == author;
  final below =
      index < messages.length - 1 && messages[index + 1].author == author;
  return switch ((above, below)) {
    (false, false) => GroupPosition.single,
    (false, true) => GroupPosition.first,
    (true, true) => GroupPosition.middle,
    (true, false) => GroupPosition.last,
  };
}
