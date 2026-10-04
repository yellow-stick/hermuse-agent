import 'tools.dart';

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
    this.detail = '',
    this.output = '',
    this.error = '',
    this.duration,
    this.outcomeKnown = true,
    this.running = true,
  });

  final String toolId;

  /// Tool name, e.g. `terminal`, `web_search`.
  final String name;

  /// Hermes' one line: its preview while running, the result once done.
  final String summary;

  /// What the call works on: the full command, the query, the address
  /// (`toolDetail`).
  final String detail;

  /// The command's printed output (terminal tools).
  final String output;

  /// Why it failed, one line; '' when it succeeded or still runs.
  final String error;

  /// How long it ran, when Hermes timed it.
  final Duration? duration;

  /// Whether [output] and [error] are known: a reloaded transcript omits
  /// most tool results, so its rows cannot tell success from failure.
  final bool outcomeKnown;
  final bool running;

  bool get failed => error.isNotEmpty;

  // How the row reads, the same in both apps.

  ToolKind get kind => toolKindOf(name);

  String get title => toolTitle(name);

  /// Commands and code show in monospace.
  bool get monospace => kind == ToolKind.terminal || kind == ToolKind.code;

  /// What the row says: [detail], else Hermes' line.
  String get line => detail.isNotEmpty ? detail : summary;

  /// The first line of [line], on the closed row.
  String get headline => line.split('\n').first;

  /// Hermes' result line when it adds to [line] (`Did 5 searches in 1.9s`
  /// under a query); a command's preview only repeats the command.
  String get resultLine =>
      !monospace && summary.isNotEmpty && summary != line ? summary : '';

  /// Whether opening the row shows more than its closed line.
  bool get expandable =>
      output.isNotEmpty ||
      failed ||
      line.contains('\n') ||
      headline.length > 60 ||
      resultLine.isNotEmpty;

  ToolCallBlock done({
    required String summary,
    String? detail,
    String output = '',
    String error = '',
    Duration? duration,
  }) => ToolCallBlock(
    toolId: toolId,
    name: name,
    summary: summary,
    detail: detail == null || detail.isEmpty ? this.detail : detail,
    output: output,
    error: error,
    duration: duration,
    running: false,
  );
}

/// Whether [name] is one of Hermes' `browser_*` tools, shown as a
/// [BrowserBlock] instead of tool call rows.
bool isBrowserTool(String name) => name.startsWith('browser_');

/// The agent's browser in a turn: one card, first in the bubble, standing
/// for every `browser_*` tool call of that turn.
final class BrowserBlock extends Block {
  const BrowserBlock({
    required this.lastToolId,
    this.running = true,
    this.step = '',
    this.host = '',
  });

  /// Id of the turn's latest browser tool call (keys its saved snapshot).
  final String lastToolId;

  /// The turn is still in progress.
  final bool running;

  /// What the agent is doing while [running] (`Opening example.com`).
  final String step;

  /// Host of the last page the agent opened, when known.
  final String host;

  BrowserBlock copyWith({
    String? lastToolId,
    bool? running,
    String? step,
    String? host,
  }) => BrowserBlock(
    lastToolId: lastToolId ?? this.lastToolId,
    running: running ?? this.running,
    step: step ?? this.step,
    host: host ?? this.host,
  );
}

/// A status line inside the conversation (errors, cancelled requests).
final class NoticeBlock extends Block {
  const NoticeBlock(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

/// What a pending turn is waiting on (an API retry backoff, a slow
/// provider), last in its bubble until content streams or the turn ends.
final class WaitBlock extends Block {
  const WaitBlock(this.text);
  final String text;
}

/// A slash command run on the server (`/model …`) and what it answered: a
/// row of the thread, not a message to the agent.
final class CommandBlock extends Block {
  const CommandBlock({
    required this.command,
    this.output = '',
    this.running = true,
    this.isError = false,
  });

  /// The command as typed.
  final String command;

  /// The server's answer once done.
  final String output;
  final bool running;

  /// [output] is the error that stopped the command.
  final bool isError;

  CommandBlock done(String output, {bool isError = false}) => CommandBlock(
    command: command,
    output: output,
    running: false,
    isError: isError,
  );
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

  /// The answer as readable plain text (copy, reply quotes): reasoning,
  /// tool activity and a pending turn's wait are not part of what was said.
  String get plainText => [
    for (final block in blocks)
      if (block is! ReasoningBlock &&
          block is! ToolCallBlock &&
          block is! BrowserBlock &&
          block is! WaitBlock)
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
          BrowserBlock(:final step) => step,
          NoticeBlock(:final text) => text,
          WaitBlock(:final text) => text,
          CommandBlock(:final command, :final output) =>
            output.isEmpty ? command : '$command\n$output',
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

/// A turn the agent is running in one chat: the live row on top of the
/// profile panel's Activity tab, stopped with `ChatController.interrupt`.
final class RunningTask {
  const RunningTask({
    required this.threadId,
    required this.isMain,
    required this.threadTitle,
    required this.request,
    required this.step,
  });

  final String threadId;

  /// It runs in the main chat (a scheduled job or a heartbeat lands there).
  final bool isMain;

  /// Title of the side chat it runs in ('' while untitled); the apps name
  /// the main chat themselves.
  final String threadTitle;

  /// First line of the user's message that started it; '' for a turn the
  /// server started (a scheduled job, the heartbeat).
  final String request;

  /// What the agent is doing now ([agentStepLabel]): "Searching the web".
  final String step;
}

/// Name of the scheduled job whose output [text] hands to the main chat
/// (Hermes' `[Cronjob "<name>" output — …]` brief), or null when [text] is
/// no such brief.
String? cronBriefJobName(String text) =>
    _cronBrief.firstMatch(text.trimLeft())?.group(1);

final _cronBrief = RegExp(r'^\[Cronjob "(.*?)" output — ');

/// An approval request of the agent nobody answered yet.
final class ApprovalRequest {
  const ApprovalRequest({
    required this.threadId,
    required this.threadTitle,
    required this.messageId,
    required this.prompt,
  });

  final String threadId;
  final String threadTitle;
  final String messageId;

  /// "Approve this command?" then the command and Hermes' reason.
  final String prompt;

  /// The command line(s) asked about: [prompt] without its question.
  String get command {
    final lines = prompt.split('\n');
    return lines.length > 1 ? lines.skip(1).join('\n') : prompt;
  }
}

/// Tabs of the profile panel.
enum PanelTab {
  activity('Activity', 'Nothing yet'),
  approvals('Approvals', 'No approvals yet'),
  upcoming('Upcoming', 'Nothing scheduled'),
  identity('Identity', '');

  const PanelTab(this.label, this.emptyText);
  final String label;
  final String emptyText;
}
