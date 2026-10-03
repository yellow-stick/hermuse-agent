import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../computer/browser_parts.dart' show browserTaskTitle;
import 'browser_card.dart';
import 'flight_card.dart' show FlightCard;
import 'markdown_view.dart';
import 'tool_icon.dart';

/// One message row: bubble or card, reaction chip, hover actions.
final class MessageRow extends StatefulWidget {
  const MessageRow({
    required this.message,
    required this.position,
    required this.selectedOfferId,
    required this.controller,
    required this.columnWidth,
    required this.threadTitle,
    super.key,
  });

  final Message message;
  final GroupPosition position;
  final String? selectedOfferId;
  final ChatController controller;
  final double columnWidth;

  /// Title of the message's thread (the browser card's task title).
  final String threadTitle;

  @override
  State<MessageRow> createState() => _MessageRowState();
}

final class _MessageRowState extends State<MessageRow> {
  bool _hovered = false;
  bool _copied = false;

  bool get _isUser => widget.message.author == Author.user;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.message.plainText));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCard = widget.message.blocks.any((b) => b is FlightResultsBlock);
    final bubble = isCard
        ? FlightCard(
            message: widget.message,
            position: widget.position,
            selectedOfferId: widget.selectedOfferId,
            controller: widget.controller,
            maxWidth: widget.columnWidth >= YsLayout.compactMax
                ? YsLayout.cardWidth
                : (widget.columnWidth < YsLayout.cardWidth
                      ? widget.columnWidth
                      : YsLayout.cardWidth),
          )
        : _Bubble(
            message: widget.message,
            position: widget.position,
            controller: widget.controller,
            threadTitle: widget.threadTitle,
            maxWidth: _isUser
                ? widget.columnWidth.clamp(0.0, YsLayout.userBubbleMaxWidth)
                : widget.columnWidth * YsLayout.agentBubbleMaxFraction,
          );
    final withReaction = widget.message.reactions.isEmpty
        ? bubble
        : _ReactionStack(
            message: widget.message,
            isUser: _isUser,
            controller: widget.controller,
            child: bubble,
          );
    final actions = _HoverActions(
      message: widget.message,
      isUser: _isUser,
      copied: _copied,
      controller: widget.controller,
      onCopy: _copy,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onLongPress: () => setState(() => _hovered = !_hovered),
        behavior: HitTestBehavior.translucent,
        // The bubble hugs its content: the hover actions sit right beside
        // it (web `.hermuse-msg-inner`), not at the far edge of the column.
        child: _isUser
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (_hovered) ...[actions, const SizedBox(width: 8)],
                  Flexible(child: withReaction),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(child: withReaction),
                  if (_hovered) ...[const SizedBox(width: 8), actions],
                ],
              ),
      ),
    );
  }
}

BorderRadius _bubbleRadius(GroupPosition position, bool isUser) {
  const all = Radius.circular(YsRadius.bubble);
  const tail = Radius.circular(YsRadius.bubbleTail);
  if (isUser) {
    return BorderRadius.only(
      topLeft: all,
      topRight: position.joinsAbove ? tail : all,
      bottomLeft: all,
      bottomRight: position.joinsBelow ? tail : all,
    );
  }
  return BorderRadius.only(
    topLeft: position.joinsAbove ? tail : all,
    topRight: all,
    bottomLeft: position.joinsBelow ? tail : all,
    bottomRight: all,
  );
}

final class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.position,
    required this.controller,
    required this.threadTitle,
    required this.maxWidth,
  });

  final Message message;
  final GroupPosition position;
  final ChatController controller;
  final String threadTitle;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isUser = message.author == Author.user;
    Widget bubble(
      GroupPosition position,
      List<Block> blocks, {
      EdgeInsets padding = const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 11,
      ),
    }) => _BubbleShell(
      message: message,
      blocks: blocks,
      position: position,
      controller: controller,
      threadTitle: threadTitle,
      maxWidth: maxWidth,
      padding: padding,
    );
    final card = isUser
        ? null
        : message.blocks.whereType<BrowserBlock>().firstOrNull;
    if (card == null) return bubble(position, message.blocks);
    // The browser card is a bubble of its own, first in the turn (Muse);
    // the rest of the turn follows in a second bubble joined to it.
    const cardPadding = EdgeInsets.all(12);
    final rest = [
      for (final block in message.blocks)
        if (block is! BrowserBlock) block,
    ];
    if (rest.isEmpty) return bubble(position, [card], padding: cardPadding);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        bubble(_joined(position, below: true), [card], padding: cardPadding),
        const SizedBox(height: 8),
        bubble(_joined(position, above: true), rest),
      ],
    );
  }
}

/// [position] with one more bubble of the same author joined [above] or
/// [below].
GroupPosition _joined(
  GroupPosition position, {
  bool above = false,
  bool below = false,
}) => switch ((above || position.joinsAbove, below || position.joinsBelow)) {
  (false, false) => GroupPosition.single,
  (false, true) => GroupPosition.first,
  (true, true) => GroupPosition.middle,
  (true, false) => GroupPosition.last,
};

final class _BubbleShell extends StatelessWidget {
  const _BubbleShell({
    required this.message,
    required this.blocks,
    required this.position,
    required this.controller,
    required this.threadTitle,
    required this.maxWidth,
    required this.padding,
  });

  final Message message;

  /// The part of [message] this bubble shows.
  final List<Block> blocks;
  final GroupPosition position;
  final ChatController controller;
  final String threadTitle;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final isUser = message.author == Author.user;
    var choiceIndex = -1;
    return Align(
      widthFactor: 1,
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isUser ? palette.primaryColor : palette.paperColor,
            borderRadius: _bubbleRadius(position, isUser),
            boxShadow: isUser ? const [] : palette.raisedShadows,
          ),
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  if (i > 0)
                    SizedBox(
                      // Consecutive tool rows read as one list.
                      height:
                          blocks[i] is ToolCallBlock &&
                              blocks[i - 1] is ToolCallBlock
                          ? 4
                          : 8,
                    ),
                  _BlockView(
                    block: blocks[i],
                    messageId: message.id,
                    isUser: isUser,
                    blockIndex: blocks[i] is ChoiceBlock ? ++choiceIndex : -1,
                    controller: controller,
                    threadTitle: threadTitle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _BlockView extends StatelessWidget {
  const _BlockView({
    required this.block,
    required this.messageId,
    required this.isUser,
    required this.blockIndex,
    required this.controller,
    required this.threadTitle,
  });

  final Block block;
  final String messageId;
  final bool isUser;

  /// Index of this choice among the message's [ChoiceBlock]s
  /// (`controller.choose` block index); -1 for non-choice blocks.
  final int blockIndex;
  final ChatController controller;
  final String threadTitle;

  @override
  Widget build(BuildContext context) {
    final block = this.block;
    return switch (block) {
      TextBlock(:final text) => _BodyText(text: text, isUser: isUser),
      BulletsBlock(:final items) => _Bullets(items: items, isUser: isUser),
      ChoiceBlock() => _ChoiceBlockView(
        block: block,
        messageId: messageId,
        blockIndex: blockIndex,
        controller: controller,
      ),
      ReasoningBlock() => _ReasoningView(block: block),
      ToolCallBlock() => _ToolCallView(block: block),
      // Keyed by message: list rows are reused by position, and a card must
      // not show another turn's picture.
      BrowserBlock() => BrowserCard(
        key: ValueKey(messageId),
        block: block,
        title: browserTaskTitle(threadTitle),
        instanceId: controller.instanceId,
        onOpen: controller.openComputer,
      ),
      NoticeBlock() => _NoticeView(block: block),
      WaitBlock(:final text) => _WaitView(text: text),
      CommandBlock() => _CommandView(block: block),
      FlightResultsBlock() => const SizedBox.shrink(),
    };
  }
}

final class _ReasoningView extends StatefulWidget {
  const _ReasoningView({required this.block});

  final ReasoningBlock block;

  @override
  State<_ReasoningView> createState() => _ReasoningViewState();
}

final class _ReasoningViewState extends State<_ReasoningView> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: () => setState(() => _expanded = !_expanded),
      semanticLabel: _expanded ? 'Hide reasoning' : 'Show reasoning',
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              YsIconWidget(
                _expanded ? YsIcon.chevronDown : YsIcon.chevronRight,
                size: 14,
                color: palette.contentMutedColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Reasoning',
                style: YsType.small.flutter.copyWith(
                  color: palette.contentMutedColor,
                ),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            Text(
              widget.block.text,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tool call: icon, name, what it works on (the command in monospace),
/// time and status. Opens on click to the full command, its output, Hermes'
/// result line and the failure reason.
final class _ToolCallView extends StatefulWidget {
  const _ToolCallView({required this.block});

  final ToolCallBlock block;

  @override
  State<_ToolCallView> createState() => _ToolCallViewState();
}

final class _ToolCallViewState extends State<_ToolCallView> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final block = widget.block;
    final kind = block.kind;
    final title = block.title;
    final mono = block.monospace;
    final firstLine = block.headline;
    final expandable = block.expandable;
    final detailStyle = mono
        ? YsType.code.flutter.copyWith(
            fontFamily: YsType.monoFamily,
            color: palette.contentMutedColor,
          )
        : YsType.small.flutter.copyWith(color: palette.contentMutedColor);
    final status = block.running
        ? const YsSpinner(size: 12)
        : YsIconWidget(
            block.failed ? YsIcon.xCircle : YsIcon.check,
            size: 13,
            // A reloaded row finished, but whether it worked is unknown.
            color: block.failed
                ? palette.errorColor
                : block.outcomeKnown
                ? palette.successColor
                : palette.contentSubtleColor,
          );
    Widget header(bool hovered) => Row(
      children: [
        YsIconWidget(
          toolIcon(kind),
          size: 15,
          color: block.failed ? palette.errorColor : palette.contentMutedColor,
        ),
        const SizedBox(width: YsSpace.sm),
        Text(
          title,
          style: YsType.small.flutter.copyWith(
            color: palette.contentColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (firstLine.isNotEmpty) ...[
          const SizedBox(width: YsSpace.sm),
          Expanded(
            child: Text(
              firstLine,
              style: detailStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ] else
          const Spacer(),
        const SizedBox(width: YsSpace.sm),
        if (block.duration case final duration?) ...[
          Text(
            formatToolDuration(duration),
            style: YsType.caption.flutter.copyWith(
              color: palette.contentSubtleColor,
            ),
          ),
          const SizedBox(width: YsSpace.sm),
        ],
        SizedBox(width: 14, child: Center(child: status)),
        if (expandable) ...[
          const SizedBox(width: YsSpace.xs),
          YsIconWidget(
            _expanded ? YsIcon.chevronDown : YsIcon.chevronRight,
            size: 13,
            color: hovered
                ? palette.contentMutedColor
                : palette.contentSubtleColor,
          ),
        ],
      ],
    );
    final semantic = [
      if (block.running) 'Running',
      title,
      if (firstLine.isNotEmpty) firstLine,
      if (block.failed) 'failed: ${block.error}',
    ].join(', ');
    return Semantics(
      label: semantic,
      expanded: expandable ? _expanded : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.neutralWashColor,
          border: Border.all(
            color: block.failed ? palette.errorWashColor : palette.lineColor,
          ),
          borderRadius: BorderRadius.circular(YsRadius.row),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.md - 2,
            vertical: YsSpace.sm - 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expandable)
                YsPressable(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  semanticLabel: _expanded
                      ? 'Hide $title details'
                      : 'Show $title details',
                  builder: (context, state) => header(state.hovered),
                )
              else
                header(false),
              if (_expanded && expandable) ...[
                const SizedBox(height: YsSpace.sm),
                _ToolDetails(block: block),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The opened tool row: the full command (`$ …`) and its output in a
/// scrollable monospace well, Hermes' result line, the failure reason.
final class _ToolDetails extends StatelessWidget {
  const _ToolDetails({required this.block});

  final ToolCallBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final code = YsType.code.flutter.copyWith(fontFamily: YsType.monoFamily);
    final mono = block.monospace;
    final line = block.line;
    final hasWell = mono || block.output.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasWell)
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvasColor,
              borderRadius: BorderRadius.circular(YsRadius.row - 4),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(YsSpace.sm + 2),
                child: SelectableText.rich(
                  // WidgetsApp has no Material localization delegates.
                  // Selection and keyboard copy remain available.
                  contextMenuBuilder: null,
                  TextSpan(
                    children: [
                      if (line.isNotEmpty)
                        TextSpan(
                          text: mono ? '\$ $line' : line,
                          style: code.copyWith(color: palette.contentColor),
                        ),
                      if (line.isNotEmpty && block.output.isNotEmpty)
                        const TextSpan(text: '\n'),
                      if (block.output.isNotEmpty)
                        TextSpan(
                          text: block.output,
                          style: code.copyWith(
                            color: palette.contentMutedColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (line.isNotEmpty)
          SelectableText(
            line,
            contextMenuBuilder: null,
            style: YsType.small.flutter.copyWith(color: palette.contentColor),
          ),
        if (block.resultLine.isNotEmpty) ...[
          const SizedBox(height: YsSpace.xs + 2),
          Text(
            block.resultLine,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
        if (block.failed) ...[
          const SizedBox(height: YsSpace.xs + 2),
          Text(
            block.error,
            style: YsType.caption.flutter.copyWith(color: palette.errorColor),
          ),
        ],
      ],
    );
  }
}

final class _NoticeView extends StatelessWidget {
  const _NoticeView({required this.block});

  final NoticeBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      block.text,
      style: YsType.small.flutter.copyWith(
        color: block.isError ? palette.errorColor : palette.contentMutedColor,
      ),
    );
  }
}

/// What a pending turn waits on: an API retry backoff, a slow provider.
final class _WaitView extends StatelessWidget {
  const _WaitView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 14,
            height: 18,
            child: Center(child: YsSpinner(size: 12)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slash command run on the server: the command, then its answer.
final class _CommandView extends StatelessWidget {
  const _CommandView({required this.block});

  final CommandBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final small = YsType.small.flutter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: block.running ? 'Running ${block.command}' : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 14,
                height: 18,
                child: Center(
                  child: block.running
                      ? const YsSpinner(size: 12)
                      : YsIconWidget(
                          block.isError ? YsIcon.close : YsIcon.check,
                          size: 12,
                          color: block.isError
                              ? palette.errorColor
                              : palette.successColor,
                        ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  block.command,
                  style: small.copyWith(
                    color: palette.contentMutedColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (block.output.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            block.output,
            style: small.copyWith(
              // While running, the text is a note (waiting), not an answer.
              color: block.isError
                  ? palette.errorColor
                  : block.running
                  ? palette.contentMutedColor
                  : palette.contentColor,
            ),
          ),
        ],
      ],
    );
  }
}

final class _BodyText extends StatelessWidget {
  const _BodyText({required this.text, required this.isUser});

  final String text;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    if (!isUser) return MarkdownView(text);
    final palette = YsTheme.of(context);
    return Text(
      text,
      style: (isUser ? YsType.bubble : YsType.agentBubble).flutter.copyWith(
        color: isUser ? palette.primaryContentColor : palette.contentColor,
      ),
    );
  }
}

final class _Bullets extends StatelessWidget {
  const _Bullets({required this.items, required this.isUser});

  final List<String> items;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final style = (isUser ? YsType.bubble : YsType.agentBubble).flutter
        .copyWith(
          color: isUser ? palette.primaryContentColor : palette.contentColor,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 12, child: Text('•', style: style)),
                Flexible(child: Text(items[i], style: style)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final class _ChoiceBlockView extends StatelessWidget {
  const _ChoiceBlockView({
    required this.block,
    required this.messageId,
    required this.blockIndex,
    required this.controller,
  });

  final ChoiceBlock block;
  final String messageId;
  final int blockIndex;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          block.prompt,
          style: YsType.agentBubble.flutter.copyWith(
            color: palette.contentColor,
          ),
        ),
        const SizedBox(height: 12),
        for (final option in block.options) ...[
          _ChoiceOption(
            label: option,
            selected: block.selected == option,
            onPressed: block.selected != null
                ? null
                : () => controller.choose(
                    messageId,
                    option,
                    blockIndex: blockIndex,
                  ),
          ),
          const SizedBox(height: 10),
        ],
        // Approval cards (`customPlaceholder == ''`) have no free-text field.
        if (block.customPlaceholder.isNotEmpty)
          _CustomOption(
            block: block,
            messageId: messageId,
            blockIndex: blockIndex,
            controller: controller,
          ),
      ],
    );
  }
}

final class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: YsMotion.fast),
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? palette.primaryMutedColor
              : state.hovered
              ? palette.neutralFilmColor
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(YsRadius.option),
          border: selected
              ? Border.all(color: palette.primaryInkColor, width: ysHairline)
              : null,
        ),
        foregroundDecoration: selected
            ? null
            : DashedRRectDecoration(
                color: palette.lineColor,
                strokeWidth: ysHairline,
                radius: YsRadius.option,
              ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: YsType.choiceOption.flutter.copyWith(
              color: palette.contentColor,
            ),
          ),
        ),
      ),
    );
  }
}

final class _CustomOption extends StatefulWidget {
  const _CustomOption({
    required this.block,
    required this.messageId,
    required this.blockIndex,
    required this.controller,
  });

  final ChoiceBlock block;
  final String messageId;
  final int blockIndex;
  final ChatController controller;

  @override
  State<_CustomOption> createState() => _CustomOptionState();
}

final class _CustomOptionState extends State<_CustomOption> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final selected = widget.block.isCustomSelected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: YsMotion.fast),
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? palette.primaryMutedColor : const Color(0x00000000),
        borderRadius: BorderRadius.circular(YsRadius.option),
        border: selected
            ? Border.all(color: palette.primaryInkColor, width: ysHairline)
            : null,
      ),
      foregroundDecoration: selected
          ? null
          : DashedRRectDecoration(
              color: palette.lineColor,
              strokeWidth: ysHairline,
              radius: YsRadius.option,
            ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: selected
            ? Text(
                widget.block.selected!,
                style: YsType.choiceOption.flutter.copyWith(
                  color: palette.contentColor,
                ),
              )
            : YsTextField(
                controller: _text,
                placeholder: widget.block.customPlaceholder,
                semanticLabel: widget.block.customPlaceholder,
                textStyle: YsType.choiceOption,
                onSubmitted: (value) => widget.controller.choose(
                  widget.messageId,
                  value,
                  blockIndex: widget.blockIndex,
                ),
              ),
      ),
    );
  }
}

final class _ReactionStack extends StatelessWidget {
  const _ReactionStack({
    required this.message,
    required this.isUser,
    required this.controller,
    required this.child,
  });

  final Message message;
  final bool isUser;
  final ChatController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 10), child: child),
        Positioned(
          bottom: 0,
          right: isUser ? 6 : null,
          left: isUser ? null : 8,
          child: YsPressable(
            onPressed: () =>
                controller.toggleReaction(message.id, message.reactions.first),
            semanticLabel: 'Assistant reaction: ${message.reactions.first}',
            builder: (context, state) => Container(
              width: YsLayout.reactionSize,
              height: YsLayout.reactionSize,
              decoration: BoxDecoration(
                color: palette.paperColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.canvasColor,
                  width: ysHairline,
                ),
              ),
              child: Center(
                child: Text(
                  message.reactions.first,
                  style: const TextStyle(fontSize: 18, height: 1),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _HoverActions extends StatelessWidget {
  const _HoverActions({
    required this.message,
    required this.isUser,
    required this.copied,
    required this.controller,
    required this.onCopy,
  });

  final Message message;
  final bool isUser;
  final bool copied;
  final ChatController controller;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final actions = isUser
        ? [
            YsButton.icon(
              icon: copied ? YsIcon.check : YsIcon.copy,
              onPressed: onCopy,
              semanticLabel: 'Copy response',
              tooltip: 'Copy response',
              size: 27,
              iconSize: 16,
            ),
            YsButton.icon(
              icon: YsIcon.reply,
              onPressed: () => controller.startReply(message.id),
              semanticLabel: 'Reply',
              tooltip: 'Reply',
              size: 27,
              iconSize: 16,
            ),
          ]
        : [
            YsButton.icon(
              icon: YsIcon.smile,
              onPressed: () => controller.toggleReaction(message.id, '👍'),
              semanticLabel: 'React',
              tooltip: 'React',
              size: 27,
              iconSize: 16,
            ),
            YsButton.icon(
              icon: YsIcon.reply,
              onPressed: () => controller.startReply(message.id),
              semanticLabel: 'Reply',
              tooltip: 'Reply',
              size: 27,
              iconSize: 16,
            ),
            YsButton.icon(
              icon: copied ? YsIcon.check : YsIcon.copy,
              onPressed: onCopy,
              semanticLabel: 'Copy response',
              tooltip: 'Copy response',
              size: 27,
              iconSize: 16,
            ),
          ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final action in actions) action],
    );
  }
}

/// Dashes a rounded-rectangle outline (choice options, 1.2 `line` border).
final class DashedRRectDecoration extends Decoration {
  const DashedRRectDecoration({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    this.dashLength = 5,
    this.gapLength = 4,
  });

  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedRRectPainter(this);

  @override
  EdgeInsetsGeometry get padding => EdgeInsets.all(strokeWidth);
}

final class _DashedRRectPainter extends BoxPainter {
  _DashedRRectPainter(this.decoration);

  final DashedRRectDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) {
      return;
    }
    final inset = decoration.strokeWidth / 2;
    final rect = Rect.fromLTWH(
      offset.dx + inset,
      offset.dy + inset,
      size.width - decoration.strokeWidth,
      size.height - decoration.strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(decoration.radius),
    );
    final paint = Paint()
      ..color = decoration.color
      ..strokeWidth = decoration.strokeWidth
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + decoration.dashLength).clamp(
          0.0,
          metric.length,
        );
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + decoration.gapLength;
      }
    }
  }
}
