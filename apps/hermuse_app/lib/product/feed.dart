import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'plugin_gate.dart';
import 'route.dart';
import 'widgets.dart';

/// Feed: editable prompt (FEED_PROMPT.md) + post cards with Love/Discuss.
/// Discuss marks the post and opens a new chat seeded with it.
final class FeedScreen extends StatelessWidget {
  const FeedScreen({
    required this.instance,
    required this.onDiscuss,
    super.key,
  });

  final HermesInstance instance;
  final ValueChanged<String> onDiscuss;

  @override
  Widget build(BuildContext context) => PluginGate(
    instance: instance,
    title: 'Feed',
    child: _Feed(instance: instance, onDiscuss: onDiscuss),
  );
}

final class _Feed extends ConsumerStatefulWidget {
  const _Feed({required this.instance, required this.onDiscuss});

  final HermesInstance instance;
  final ValueChanged<String> onDiscuss;

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

final class _FeedState extends ConsumerState<_Feed> {
  final _prompt = TextEditingController();
  var _editing = false;
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(
            systemFileProvider(widget.instance.id, 'FEED_PROMPT.md').notifier,
          )
          .save(_prompt.text);
      if (mounted) setState(() => _editing = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final prompt = ref.watch(
      systemFileProvider(widget.instance.id, 'FEED_PROMPT.md'),
    );
    final feed = ref.watch(feedProvider(widget.instance.id));
    final posts = feed.value ?? const <FeedPost>[];
    final promptFile = prompt.value;
    return HermuseRoute(
      title: 'Feed',
      children: [
        HermuseRouteSection(
          head: 'YOUR FEED PROMPT',
          children: [
            if (_editing) ...[
              YsTextBox(
                controller: _prompt,
                semanticLabel: 'Feed prompt',
                minHeight: 96,
                maxHeight: 240,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  YsButton.neutral(
                    label: 'Cancel',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _editing = false),
                  ),
                  const SizedBox(width: 8),
                  YsButton.primary(
                    label: _saving ? 'Saving…' : 'Save',
                    onPressed: _saving ? null : () => unawaited(_save()),
                  ),
                ],
              ),
            ] else ...[
              Text(
                promptFile?.content ?? '',
                style: YsType.body.flutter.copyWith(
                  color: palette.contentMutedColor,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: YsButton.neutral(
                  label: 'Edit',
                  onPressed: promptFile == null
                      ? null
                      : () => setState(() {
                          _prompt.text = promptFile.content;
                          _editing = true;
                        }),
                ),
              ),
            ],
          ],
        ),
        if (feed.isLoading && feed.value == null)
          const HermuseRouteSub('Loading feed…')
        else if (feed.hasError && feed.value == null)
          HermuseRouteError('Feed failed: ${feed.error}')
        else if (posts.isEmpty)
          const HermuseRouteEmpty(
            icon: YsIcon.feed,
            title: 'Your feed is empty',
            body:
                'Posts appear here as your Hermes gets to know you. Edit the '
                'prompt above to steer it.',
          )
        else
          for (final post in posts)
            _PostCard(
              key: ValueKey(post.id),
              instanceId: widget.instance.id,
              post: post,
              onDiscuss: widget.onDiscuss,
            ),
        if (_error case final error?) HermuseRouteError(error),
      ],
    );
  }
}

final class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({
    required this.instanceId,
    required this.post,
    required this.onDiscuss,
    super.key,
  });

  final String instanceId;
  final FeedPost post;
  final ValueChanged<String> onDiscuss;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

final class _PostCardState extends ConsumerState<_PostCard> {
  var _busy = false;
  String? _error;

  Future<bool> _react(FeedReaction reaction) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = true;
    try {
      await ref
          .read(feedProvider(widget.instanceId).notifier)
          .react(widget.post.id, reaction);
    } on Object catch (e) {
      ok = false;
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<void> _discuss() async {
    final post = widget.post;
    if (!post.reacted(FeedReaction.discuss) &&
        !await _react(FeedReaction.discuss)) {
      return;
    }
    widget.onDiscuss("Let's discuss: ${post.title}\n\n${post.body}");
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final post = widget.post;
    final meta = [
      if (post.topic.isNotEmpty) post.topic,
      if (post.createdAt.isNotEmpty) post.createdAt,
    ].join(' · ');
    return ProductCard(
      children: [
        Text(
          post.title,
          style: YsType.title.flutter.copyWith(color: palette.contentColor),
        ),
        if (meta.isNotEmpty)
          Text(
            meta,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentSubtleColor,
            ),
          ),
        Text(
          post.body,
          style: YsType.agentBubble.flutter.copyWith(
            color: palette.contentColor,
          ),
        ),
        Row(
          children: [
            ProductPill(
              label: 'Love',
              semanticLabel: 'Love this post',
              on: post.reacted(FeedReaction.love),
              onPressed: _busy
                  ? null
                  : () => unawaited(_react(FeedReaction.love)),
            ),
            const SizedBox(width: 12),
            ProductPill(
              label: 'Discuss',
              semanticLabel: 'Discuss this post',
              on: post.reacted(FeedReaction.discuss),
              onPressed: _busy ? null : () => unawaited(_discuss()),
            ),
          ],
        ),
        if (_error case final error?) HermuseRouteError(error),
      ],
    );
  }
}
