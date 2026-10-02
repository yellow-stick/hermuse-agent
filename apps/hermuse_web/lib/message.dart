import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'browser_card.dart';
import 'markdown_view.dart';

YsColor _brand(int value) => YsColor(value);

/// One message row: bubble + reaction chip + hover actions.
class MessageRow extends StatelessComponent {
  const MessageRow({
    required this.message,
    required this.position,
    required this.selectedOffer,
    required this.onToggleReaction,
    required this.onReply,
    required this.onCopy,
    required this.copied,
    required this.onChoose,
    required this.customAnswer,
    required this.onCustomAnswer,
    required this.onSelectOffer,
    required this.instanceId,
    required this.taskTitle,
    required this.onOpenComputer,
    super.key,
  });

  final Message message;
  final GroupPosition position;
  final String? selectedOffer;
  final VoidCallback onToggleReaction;

  /// Null hides the Reply action (read-only transcripts).
  final VoidCallback? onReply;
  final VoidCallback onCopy;

  /// True while the copy button shows its check state.
  final bool copied;

  /// Answers the choice at [blockIndex] of this message (approval/clarify).
  final void Function(String answer, int blockIndex) onChoose;
  final String customAnswer;
  final ValueChanged<String> onCustomAnswer;
  final ValueChanged<String> onSelectOffer;

  /// Instance of the conversation (the browser card's computer).
  final String instanceId;

  /// Title of the browser task ([browserTaskTitle]).
  final String taskTitle;

  /// Opens the computer viewer (the browser card's buttons).
  final VoidCallback onOpenComputer;

  @override
  Component build(BuildContext context) {
    final isUser = message.author == Author.user;
    // The browser card is a bubble of its own above the turn's other
    // blocks, joined to them like grouped messages.
    final card = message.blocks.whereType<BrowserBlock>().firstOrNull;
    final hasRest = message.blocks.any((block) => block is! BrowserBlock);
    final choices = [
      for (final b in message.blocks)
        if (b is ChoiceBlock) b,
    ];
    return div(
      classes: isUser
          ? 'hermuse-msg hermuse-msg-user'
          : 'hermuse-msg hermuse-msg-agent',
      [
        div(classes: 'hermuse-msg-inner', [
          if (isUser)
            div(classes: 'hermuse-actions', [
              _action(YsIcon.copy, 'Copy', onCopy, copied: copied),
              if (onReply case final reply?)
                _action(YsIcon.reply, 'Reply', reply),
            ]),
          div(
            classes: card == null
                ? 'hermuse-bubble-wrap'
                : 'hermuse-bubble-wrap hermuse-bubble-wrap-browser',
            [
              if (card != null)
                div(
                  classes: 'hermuse-bubble hermuse-bubble-agent hermuse-bubble-browser',
                  styles: Styles(
                    radius: _bubbleRadius(
                      isUser,
                      joinsAbove: position.joinsAbove,
                      joinsBelow: hasRest || position.joinsBelow,
                    ),
                  ),
                  [
                    HermuseBrowserCard(
                      block: card,
                      title: taskTitle,
                      instanceId: instanceId,
                      onOpen: onOpenComputer,
                    ),
                  ],
                ),
              if (card == null || hasRest)
                div(
                  classes: isUser
                      ? 'hermuse-bubble hermuse-bubble-user'
                      : 'hermuse-bubble hermuse-bubble-agent',
                  styles: Styles(
                    radius: _bubbleRadius(
                      isUser,
                      joinsAbove: card != null || position.joinsAbove,
                      joinsBelow: position.joinsBelow,
                    ),
                  ),
                  [
                    for (final block in message.blocks)
                      switch (block) {
                        TextBlock(:final text) =>
                          isUser
                              ? p(classes: 'hermuse-text', [.text(text)])
                              : HermuseMarkdown(text),
                        BulletsBlock(:final items) => ul(
                          classes: 'hermuse-bullets',
                          [
                            for (final item in items)
                              li(classes: 'hermuse-bullet', [
                                span(classes: 'hermuse-bullet-dot', [
                                  .text('•'),
                                ]),
                                span(classes: 'hermuse-bullet-text', [
                                  .text(item),
                                ]),
                              ]),
                          ],
                        ),
                        ChoiceBlock choice => HermuseChoice(
                          key: ValueKey(choices.indexOf(choice)),
                          messageId: message.id,
                          choice: choice,
                          onChoose: (answer) =>
                              onChoose(answer, choices.indexOf(choice)),
                          customAnswer: customAnswer,
                          onCustomAnswer: onCustomAnswer,
                        ),
                        ReasoningBlock(:final text) => HermuseReasoning(
                          text: text,
                        ),
                        ToolCallBlock tool => HermuseToolCall(tool: tool),
                        // Drawn as the bubble above.
                        BrowserBlock() => .fragment([]),
                        NoticeBlock(:final text, :final isError) =>
                          HermuseNotice(text: text, isError: isError),
                        WaitBlock(:final text) => HermuseWait(text: text),
                        CommandBlock command => HermuseCommand(
                          command: command,
                        ),
                        FlightResultsBlock(:final title, :final offers) => div(
                          classes: 'hermuse-flights',
                          [
                            p(classes: 'hermuse-flights-title', [.text(title)]),
                            for (final offer in offers)
                              HermuseOfferRow(
                                offer: offer,
                                selected: selectedOffer == offer.id,
                                onSelect: () => onSelectOffer(offer.id),
                              ),
                          ],
                        ),
                      },
                  ],
                ),
              if (message.reactions.isNotEmpty)
                div(classes: 'hermuse-reactions', [
                  for (final emoji in message.reactions)
                    YsPressable(
                      onPressed: onToggleReaction,
                      label: 'Remove $emoji reaction',
                      classes: 'hermuse-reaction',
                      builder: (context, press) => span(
                        classes: 'hermuse-reaction-emoji',
                        [.text(emoji)],
                      ),
                    ),
                ]),
            ],
          ),
          if (!isUser)
            div(classes: 'hermuse-actions', [
              _action(YsIcon.smile, 'React', onToggleReaction),
              if (onReply case final reply?)
                _action(YsIcon.reply, 'Reply', reply),
              _action(YsIcon.copy, 'Copy', onCopy, copied: copied),
            ]),
        ]),
      ],
    );
  }

  Component _action(
    YsIcon icon,
    String label,
    VoidCallback onPressed, {
    bool copied = false,
  }) => YsPressable(
    onPressed: onPressed,
    label: label,
    classes: 'hermuse-action',
    builder: (context, press) =>
        YsIconView(copied ? YsIcon.check : icon, size: 16),
  );

  BorderRadius _bubbleRadius(
    bool isUser, {
    required bool joinsAbove,
    required bool joinsBelow,
  }) {
    final full = Radius.circular(YsRadius.bubble.px);
    final tail = Radius.circular(YsRadius.bubbleTail.px);
    final topJoin = joinsAbove ? tail : full;
    final bottomJoin = joinsBelow ? tail : full;
    return isUser
        ? BorderRadius.only(
            topLeft: full,
            topRight: topJoin,
            bottomLeft: full,
            bottomRight: bottomJoin,
          )
        : BorderRadius.only(
            topLeft: topJoin,
            topRight: full,
            bottomLeft: bottomJoin,
            bottomRight: full,
          );
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-msg', [
      css('&').styles(display: .flex, flexDirection: .column),
      css('.hermuse-msg-inner')
          .styles(display: .flex, flexDirection: .row, alignItems: .center),
      css('&.hermuse-msg-user .hermuse-msg-inner').styles(justifyContent: .end),
      css('.hermuse-bubble').styles(
        padding: .symmetric(vertical: 11.px, horizontal: 15.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(8.px),
      ),
      css('.hermuse-bubble-agent').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--paper'),
        fontSize: 15.px,
        lineHeight: 24.px,
        raw: {'box-shadow': 'var(--raised)'},
      ),
      css('.hermuse-bubble-user').styles(
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
        fontSize: 16.px,
        lineHeight: 24.px,
      ),
      // User text keeps its line breaks exactly as typed.
      css('.hermuse-text').styles(
        margin: .zero,
        raw: {'overflow-wrap': 'break-word', 'white-space': 'pre-wrap'},
      ),
      css('.hermuse-bullets').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(6.px),
        margin: .only(top: 4.px),
        padding: .zero,
        raw: {'list-style': 'none'},
      ),
      css('.hermuse-bullet').styles(display: .flex, flexDirection: .row),
      css('.hermuse-bullet-dot')
          .styles(width: 12.px, raw: {'flex-shrink': '0'}),
      css('.hermuse-bullet-text').styles(raw: {'overflow-wrap': 'break-word'}),
      // Reasoning: collapsed native disclosure.
      css('.hermuse-reasoning').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-reasoning summary')
          .styles(cursor: .pointer, raw: {'list-style': 'none'}),
      css('.hermuse-reasoning summary::-webkit-details-marker')
          .styles(raw: {'display': 'none'}),
      css('.hermuse-reasoning summary::before')
          .styles(raw: {'content': '"▸ "', 'color': 'var(--content-subtle)'}),
      css('.hermuse-reasoning[open] summary::before')
          .styles(raw: {'content': '"▾ "'}),
      css('.hermuse-reasoning-text').styles(
        margin: .only(top: 6.px, bottom: 2.px),
        raw: {'overflow-wrap': 'break-word', 'white-space': 'pre-wrap'},
      ),
      // Tool call: compact one-line status.
      css('.hermuse-tool').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(8.px),
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-tool-dot').styles(
        width: 8.px,
        height: 8.px,
        radius: .circular(4.px),
        backgroundColor: .variable('--success'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-tool-dot-running').styles(
        backgroundColor: .variable('--primary'),
        raw: {'animation': 'hermuse-pulse 1s ease-in-out infinite'},
      ),
      css('.hermuse-tool-text').styles(
        overflow: .hidden,
        textOverflow: .ellipsis,
        raw: {'white-space': 'nowrap'},
      ),
      // Notice: status line; errors get the accent tint.
      css('.hermuse-notice').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
        raw: {'overflow-wrap': 'break-word'},
      ),
      // Wait line of a pending turn (retry backoff, slow provider): wraps.
      css('.hermuse-wait-text').styles(raw: {'overflow-wrap': 'break-word'}),
      // Slash command row: the command over the server's answer, which
      // keeps its line breaks (tables, lists).
      css('.hermuse-command')
          .styles(display: .flex, flexDirection: .column, gap: .all(4.px)),
      css('.hermuse-command-name')
          .styles(fontWeight: .w500, raw: {'overflow-wrap': 'anywhere'}),
      css('.hermuse-tool-dot-error')
          .styles(backgroundColor: .variable('--primary-2')),
      css('.hermuse-command-output').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content'),
        raw: {'overflow-wrap': 'break-word', 'white-space': 'pre-wrap'},
      ),
      css('.hermuse-command-note').styles(color: .variable('--content-muted')),
      css('.hermuse-notice-error').styles(color: .variable('--primary-ink')),
      // Reaction chip overlapping the bubble's bottom edge.
      css('.hermuse-bubble-wrap').styles(
        position: .relative(),
        raw: {'min-width': '0', 'max-width': '100%'},
      ),
      // The 85% cap is taken on the wrap, sized against the message row: on
      // the shrink-wrapped bubble it would be 85% of its own text, wrapping
      // short replies letter by letter.
      css('&.hermuse-msg-agent .hermuse-bubble-wrap')
          .styles(maxWidth: (YsLayout.agentBubbleMaxFraction * 100).percent),
      css('&.hermuse-msg-user .hermuse-bubble-wrap').styles(
        maxWidth: YsLayout.userBubbleMaxWidth.px,
        raw: {'margin-left': 'auto'},
      ),
      // Browser card bubble over the turn's other blocks: each bubble
      // keeps its own width, 8 px apart.
      css('.hermuse-bubble-wrap-browser')
          .styles(display: .flex, flexDirection: .column, alignItems: .start),
      css('.hermuse-bubble-browser').styles(padding: .all(12.px)),
      css('.hermuse-bubble-browser + .hermuse-bubble')
          .styles(margin: .only(top: 8.px)),
      css('.hermuse-reactions').styles(
        display: .flex,
        flexDirection: .row,
        raw: {'margin-top': '-10px'},
      ),
      css('&.hermuse-msg-agent .hermuse-reactions')
          .styles(raw: {'margin-left': '8px'}),
      css('&.hermuse-msg-user .hermuse-reactions').styles(
        justifyContent: .end,
        raw: {'margin-right': '-6px', 'margin-bottom': '-10px'},
      ),
      css('.hermuse-reaction').styles(
        width: YsLayout.reactionSize.px,
        height: YsLayout.reactionSize.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        backgroundColor: .variable('--paper'),
        cursor: .pointer,
        border: .all(
          style: .solid,
          color: .variable('--canvas'),
          width: 1.2.px,
        ),
      ),
      css('.hermuse-reaction-emoji').styles(fontSize: 18.px, lineHeight: 18.px),
      // Hover actions beside the bubble.
      css('.hermuse-actions').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(0.px),
        margin: .symmetric(horizontal: 8.px),
        raw: {'opacity': '0', 'transition': 'opacity 120ms ease'},
      ),
      css('&:hover .hermuse-actions, &:focus-within .hermuse-actions')
          .styles(raw: {'opacity': '1'}),
      css('.hermuse-action').styles(
        width: 27.px,
        height: 27.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content-muted'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
      ),
      css('.hermuse-action:hover').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-film'),
      ),
      css('.hermuse-action:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
    css('@keyframes hermuse-pulse', [
      css('0%, 100%').styles(raw: {'opacity': '1'}),
      css('50%').styles(raw: {'opacity': '0.35'}),
    ]),
  ];
}

/// Agent reasoning: a collapsed native `<details>` disclosure.
class HermuseReasoning extends StatelessComponent {
  const HermuseReasoning({required this.text, super.key});

  final String text;

  @override
  Component build(BuildContext context) =>
      details(classes: 'hermuse-reasoning', [
        summary([.text('Reasoning')]),
        p(classes: 'hermuse-reasoning-text', [.text(text)]),
      ]);
}

/// One tool call: compact line with a spinner dot while running.
class HermuseToolCall extends StatelessComponent {
  const HermuseToolCall({required this.tool, super.key});

  final ToolCallBlock tool;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-tool', [
    div(
      classes: tool.running
          ? 'hermuse-tool-dot hermuse-tool-dot-running'
          : 'hermuse-tool-dot',
      [],
    ),
    span(classes: 'hermuse-tool-text', [
      .text(
        tool.summary.isEmpty ? tool.name : '${tool.name} — ${tool.summary}',
      ),
    ]),
  ]);
}

/// A status line inside the conversation (errors, cancelled requests).
class HermuseNotice extends StatelessComponent {
  const HermuseNotice({required this.text, required this.isError, super.key});

  final String text;
  final bool isError;

  @override
  Component build(BuildContext context) => p(
    classes: isError ? 'hermuse-notice hermuse-notice-error' : 'hermuse-notice',
    [.text(text)],
  );
}

/// What a pending turn waits on (an API retry backoff, a slow provider):
/// a pulsing dot and the line, announced as it changes.
class HermuseWait extends StatelessComponent {
  const HermuseWait({required this.text, super.key});

  final String text;

  @override
  Component build(BuildContext context) => div(
    classes: 'hermuse-tool',
    attributes: {'role': 'status'},
    [
      div(classes: 'hermuse-tool-dot hermuse-tool-dot-running', []),
      span(classes: 'hermuse-wait-text', [.text(text)]),
    ],
  );
}

/// A slash command run on the server: the command, then its answer.
class HermuseCommand extends StatelessComponent {
  const HermuseCommand({required this.command, super.key});

  final CommandBlock command;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-command', [
    div(classes: 'hermuse-tool', [
      div(
        classes: command.running
            ? 'hermuse-tool-dot hermuse-tool-dot-running'
            : command.isError
            ? 'hermuse-tool-dot hermuse-tool-dot-error'
            : 'hermuse-tool-dot',
        [],
      ),
      span(classes: 'hermuse-command-name', [.text(command.command)]),
    ]),
    if (command.output.isNotEmpty)
      p(
        // While running, the text is a note (waiting), not an answer.
        classes: command.isError
            ? 'hermuse-command-output hermuse-notice-error'
            : command.running
            ? 'hermuse-command-output hermuse-command-note'
            : 'hermuse-command-output',
        [.text(command.output)],
      ),
  ]);
}

/// Choice block: prompt + dashed options + optional custom answer field.
///
/// Several blocks can live in one message (batch clarify); each answers
/// through [onChoose]. Approval blocks carry an empty [ChoiceBlock]
/// placeholder and render no free-text field.
class HermuseChoice extends StatelessComponent {
  const HermuseChoice({
    required this.messageId,
    required this.choice,
    required this.onChoose,
    required this.customAnswer,
    required this.onCustomAnswer,
    super.key,
  });

  final String messageId;
  final ChoiceBlock choice;
  final ValueChanged<String> onChoose;
  final String customAnswer;
  final ValueChanged<String> onCustomAnswer;

  @override
  Component build(BuildContext context) {
    final answered = choice.selected != null;
    return div(classes: 'hermuse-choice', [
      p(classes: 'hermuse-text', [.text(choice.prompt)]),
      div(classes: 'hermuse-choice-options', [
        for (final option in choice.options)
          YsPressable(
            onPressed: answered ? null : () => onChoose(option),
            classes: choice.selected == option
                ? 'hermuse-choice-option hermuse-choice-selected'
                : 'hermuse-choice-option',
            builder: (context, press) =>
                span(classes: 'hermuse-choice-label', [.text(option)]),
          ),
        if (choice.customPlaceholder.isNotEmpty)
          if (choice.isCustomSelected)
            div(
              classes:
                  'hermuse-choice-option hermuse-choice-selected '
                  'hermuse-choice-custom',
              [.text(choice.selected!)],
            )
          else if (!answered)
            div(classes: 'hermuse-choice-option hermuse-choice-custom', [
              YsTextField(
                value: customAnswer,
                onChanged: onCustomAnswer,
                onSubmitted: () => onChoose(customAnswer),
                placeholder: choice.customPlaceholder,
                name: 'custom-$messageId-${choice.prompt.hashCode}',
              ),
            ]),
      ]),
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-choice', [
      css('&').styles(display: .flex, flexDirection: .column),
      css('.hermuse-choice-options').styles(
        display: .flex,
        flexDirection: .column,
        gap: .all(10.px),
        margin: .only(top: 12.px),
      ),
      css('.hermuse-choice-option').styles(
        minHeight: 42.px,
        padding: .symmetric(vertical: 8.px, horizontal: 10.px),
        radius: .circular(YsRadius.option.px),
        display: .flex,
        alignItems: .center,
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .all(style: .dashed, color: .variable('--line'), width: 1.2.px),
        fontSize: 15.px,
        lineHeight: 24.px,
      ),
      css('button.hermuse-choice-option:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('button.hermuse-choice-option:disabled')
          .styles(cursor: .defaultCursor),
      css('.hermuse-choice-selected').styles(
        backgroundColor: .variable('--primary-muted'),
        border: .all(
          style: .solid,
          color: .variable('--primary-ink'),
          width: 1.2.px,
        ),
      ),
      css('.hermuse-choice-custom').styles(cursor: .text),
      css('.hermuse-choice-custom .ys-textfield')
          .styles(fontSize: 15.px, lineHeight: 24.px),
    ]),
  ];
}

/// One flight offer row inside a flight results card.
class HermuseOfferRow extends StatelessComponent {
  const HermuseOfferRow({
    required this.offer,
    required this.selected,
    required this.onSelect,
  });

  final FlightOffer offer;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Component build(BuildContext context) => YsPressable(
    onPressed: onSelect,
    classes: selected
        ? 'hermuse-offer hermuse-offer-selected'
        : 'hermuse-offer',
    attributes: {'aria-pressed': '$selected'},
    builder: (context, press) => .fragment([
      div(
        classes: offer.marks.length > 1
            ? 'hermuse-offer-logos hermuse-offer-logos-duo'
            : 'hermuse-offer-logos',
        [for (var i = 0; i < offer.marks.length; i++) _mark(offer.marks[i], i)],
      ),
      div(classes: 'hermuse-offer-body', [
        p(classes: 'hermuse-offer-headline', [.text(offer.headline)]),
        for (final leg in offer.legs)
          div(classes: 'hermuse-offer-leg', [
            span(classes: 'hermuse-offer-time', [.text(leg.departs)]),
            div(classes: 'hermuse-offer-line', []),
            span(classes: 'hermuse-offer-chip', [.text(leg.duration)]),
            div(classes: 'hermuse-offer-line', []),
            span(classes: 'hermuse-offer-time hermuse-offer-arrive', [
              .text(leg.arrives),
            ]),
          ]),
        p(classes: 'hermuse-offer-total', [.text(offer.totalDuration)]),
      ]),
    ]),
  );

  Component _mark(AirlineMark mark, int index) => div(
    classes:
        '${mark.onLight ? 'hermuse-mark hermuse-mark-light' : 'hermuse-mark'} hermuse-mark-$index',
    styles: mark.onLight
        ? Styles(color: Color(_brand(mark.foreground).css))
        : null,
    [.text(mark.monogram)],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-flights', [
      css('&').styles(
        width: YsLayout.cardWidth.px,
        maxWidth: 100.percent,
        padding: .only(top: 12.px, left: 16.px, right: 16.px, bottom: 16.px),
        display: .flex,
        flexDirection: .column,
        gap: .all(16.px),
      ),
      css('.hermuse-flights-title').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-offer').styles(
        padding: .zero,
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        gap: .all(12.px),
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .all(style: .solid, color: Colors.transparent, width: 1.2.px),
        textAlign: .left,
      ),
      css('.hermuse-offer:hover').styles(
        backgroundColor: .variable('--neutral-film'),
        raw: {
          'background-clip': 'padding-box',
          'margin': '-6px',
          'padding': '6px',
        },
      ),
      css('.hermuse-offer-selected').styles(
        backgroundColor: .variable('--primary-muted'),
        border: .all(
          style: .solid,
          color: .variable('--primary-ink'),
          width: 1.2.px,
        ),
      ),
      css('.hermuse-offer-logos').styles(
        width: 40.px,
        height: 40.px,
        position: .relative(),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-mark').styles(
        width: 40.px,
        height: 40.px,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: Colors.white,
        backgroundColor: .variable('--neutral-ambient'),
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w600,
      ),
      css('.hermuse-mark-light').styles(
        backgroundColor: .variable('--logo-surface'),
        border: .all(style: .solid, color: .variable('--line'), width: 1.2.px),
      ),
      // Codeshare: two overlapping marks inside the 40px slot, the second
      // on top with a 2px paper ring; text column stays aligned.
      css(
        '.hermuse-offer-logos-duo .hermuse-mark',
      ).styles(width: 29.px, height: 29.px, fontSize: 11.px, lineHeight: 16.px),
      css('.hermuse-offer-logos-duo .hermuse-mark-0').styles(
        position: .absolute(top: 0.px, left: 0.px),
      ),
      css('.hermuse-offer-logos-duo .hermuse-mark-1').styles(
        position: .absolute(right: 0.px, bottom: 0.px),
        shadow: BoxShadow(
          offsetX: 0.px,
          offsetY: 0.px,
          spread: 2.px,
          color: .variable('--paper'),
        ),
      ),
      css('.hermuse-offer-body').styles(
        flex: .grow(1),
        display: .flex,
        flexDirection: .column,
        gap: .all(2.px),
      ),
      css('.hermuse-offer-headline').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
      ),
      css('.hermuse-offer-leg').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(4.px),
      ),
      css('.hermuse-offer-time').styles(
        width: 60.px,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-offer-arrive')
          .styles(textAlign: .right, raw: {'min-width': '60px'}),
      css('.hermuse-offer-line').styles(
        height: 1.2.px,
        flex: .grow(1),
        backgroundColor: .variable('--line'),
        raw: {'min-width': '8px'},
      ),
      css('.hermuse-offer-chip').styles(
        padding: .symmetric(vertical: 2.px, horizontal: 8.px),
        radius: .circular(YsRadius.pill.px),
        backgroundColor: .variable('--neutral-ambient'),
        fontSize: 11.px,
        lineHeight: 13.px,
        color: .variable('--content-muted'),
        raw: {'white-space': 'nowrap'},
      ),
      css('.hermuse-offer-total').styles(
        margin: .zero,
        fontSize: 12.px,
        lineHeight: 16.px,
        color: .variable('--content-subtle'),
      ),
    ]),
  ];
}
