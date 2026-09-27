/// Who wrote a message.
enum Author { agent, user }

/// A piece of message content.
sealed class Block {
  const Block();
}

final class TextBlock extends Block {
  const TextBlock(this.text);
  final String text;
}

final class BulletsBlock extends Block {
  const BulletsBlock(this.items);
  final List<String> items;
}

/// A question with preset answers and a free-text answer.
final class ChoiceBlock extends Block {
  const ChoiceBlock({
    required this.prompt,
    required this.options,
    required this.customPlaceholder,
    this.selected,
  });

  final String prompt;
  final List<String> options;
  final String customPlaceholder;

  /// The chosen answer: one of [options] or custom text.
  final String? selected;

  bool get isCustomSelected => selected != null && !options.contains(selected);

  ChoiceBlock withSelected(String value) => ChoiceBlock(
    prompt: prompt,
    options: options,
    customPlaceholder: customPlaceholder,
    selected: value,
  );
}

/// The agent's reasoning, shown collapsed.
final class ReasoningBlock extends Block {
  const ReasoningBlock(this.text);
  final String text;
}

/// One tool call of an agent turn.
final class ToolCallBlock extends Block {
  const ToolCallBlock({
    required this.toolId,
    required this.name,
    this.summary = '',
    this.running = true,
  });

  final String toolId;

  /// Tool name, e.g. `terminal`, `web_search`.
  final String name;

  /// Preview while running, result summary once done.
  final String summary;
  final bool running;

  ToolCallBlock done(String summary) => ToolCallBlock(
    toolId: toolId,
    name: name,
    summary: summary,
    running: false,
  );
}

/// A status line inside the conversation (errors, cancelled requests).
final class NoticeBlock extends Block {
  const NoticeBlock(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// A structured card listing flight offers.
final class FlightResultsBlock extends Block {
  const FlightResultsBlock({required this.title, required this.offers});
  final String title;
  final List<FlightOffer> offers;
}

/// An amount in a currency, formatted the way the reference shows prices.
final class Money {
  const Money(this.amount, this.currency);

  final double amount;

  /// ISO 4217 code: `USD` or `EUR`.
  final String currency;

  String get symbol => switch (currency) {
    'USD' => r'$',
    'EUR' => '€',
    _ => '$currency ',
  };

  @override
  String toString() => '$symbol${amount.toStringAsFixed(2)}';
}

/// A monogram disc standing in for an airline logo.
///
/// Brand artwork is not bundled; [foreground] carries the brand colour
/// (0xAARRGGBB). [onLight] draws the disc light instead of neutral.
final class AirlineMark {
  const AirlineMark(this.monogram, this.foreground, {this.onLight = true});
  final String monogram;
  final int foreground;
  final bool onLight;
}

/// One direction of a round trip.
final class FlightLeg {
  const FlightLeg(this.departs, this.duration, this.arrives);
  final String departs;
  final String duration;
  final String arrives;
}

final class FlightOffer {
  const FlightOffer({
    required this.id,
    required this.airline,
    required this.marks,
    required this.price,
    required this.legs,
    required this.totalDuration,
  });

  final String id;
  final String airline;

  /// One mark, or two overlapping marks for a codeshare.
  final List<AirlineMark> marks;
  final Money price;
  final List<FlightLeg> legs;
  final String totalDuration;

  /// "Northwind · €287.41"
  String get headline => '$airline · $price';
}

final class Message {
  const Message({
    required this.id,
    required this.author,
    required this.blocks,
    this.reactions = const [],
    this.replyToId,
  });

  final String id;
  final Author author;
  final List<Block> blocks;
  final List<String> reactions;
  final String? replyToId;

  Message withId(String id) => Message(
    id: id,
    author: author,
    blocks: blocks,
    reactions: reactions,
    replyToId: replyToId,
  );

  Message copyWith({List<Block>? blocks, List<String>? reactions}) => Message(
    id: id,
    author: author,
    blocks: blocks ?? this.blocks,
    reactions: reactions ?? this.reactions,
    replyToId: replyToId,
  );

  /// The answer as readable plain text (copy, reply quotes): reasoning and
  /// tool activity are not part of what was said.
  String get plainText => [
    for (final block in blocks)
      if (block is! ReasoningBlock && block is! ToolCallBlock)
        switch (block) {
          TextBlock(:final text) => text,
          BulletsBlock(:final items) => items.map((i) => '• $i').join('\n'),
          ChoiceBlock(:final prompt, :final options) => [
            prompt,
            ...options,
          ].join('\n'),
          FlightResultsBlock(:final title, :final offers) => [
            title,
            for (final o in offers) o.headline,
          ].join('\n'),
          ReasoningBlock(:final text) => text,
          ToolCallBlock(:final name, :final summary) =>
            summary.isEmpty ? name : '$name: $summary',
          NoticeBlock(:final text) => text,
        },
  ].join('\n\n');
}

final class Thread {
  const Thread({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.messages,
  });

  final String id;
  final String title;

  /// Display time of the first message ("12:06 AM").
  final String startedAt;
  final List<Message> messages;

  Thread withMessages(List<Message> messages) =>
      Thread(id: id, title: title, startedAt: startedAt, messages: messages);
}

/// Link state between the chat and its Hermes instance.
enum ChatConnection {
  connecting,
  ready,

  /// Dropped; the transport retries on its own.
  reconnecting,

  /// Needs the user (credentials, unsupported version, unreachable host).
  error,
}

/// Icon shown beside an activity entry.
enum ActivityKind { webSearch, completed }

/// One entry of the profile panel's "Today" list.
final class ActivityItem {
  const ActivityItem({
    required this.kind,
    required this.title,
    required this.description,
    required this.time,
  });

  final ActivityKind kind;
  final String title;
  final String description;
  final String time;
}

/// Tabs of the profile panel.
enum PanelTab {
  activity('Activity', 'Nothing yet today'),
  approvals('Approvals', 'No approvals yet'),
  upcoming('Upcoming', 'Nothing scheduled'),
  identity('Identity', 'No identities connected');

  const PanelTab(this.label, this.emptyText);
  final String label;
  final String emptyText;
}
