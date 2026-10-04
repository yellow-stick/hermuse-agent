import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show formatTimestamp;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/open_url.dart';
import '../shell/agents.dart' show nativeAgentProfileProvider;
import '../thread/markdown_view.dart';
import 'plugin_gate.dart';
import 'route.dart';
import 'widgets.dart';

/// Feed: the editable prompt (FEED_PROMPT.md) with Generate, then post
/// cards (Markdown body, optional image, sources, Love/Discuss, a "…" menu
/// with the exact date, "Why I created this" and Delete). Discuss marks the
/// post and opens a new chat seeded with it.
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
  var _generating = false;

  /// What the last Generate did: started, or why it could not.
  String? _generated;
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
            systemFileProvider(
              widget.instance.id,
              'FEED_PROMPT.md',
              profile: ref.read(nativeAgentProfileProvider),
            ).notifier,
          )
          .save(_prompt.text);
      if (mounted) setState(() => _editing = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  /// Runs a feed edition now; its posts arrive once the agent wrote them.
  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _generated = null;
    });
    String note;
    try {
      await ref
          .read(
            feedProvider(
              widget.instance.id,
              profile: ref.read(nativeAgentProfileProvider),
            ).notifier,
          )
          .generate();
      note = 'Generating… new posts appear in a few minutes';
    } on HermesHttpError catch (e) {
      note = e.statusCode == 409 ? 'Scheduled feed is off' : '$e';
    } on Object catch (e) {
      note = '$e';
    }
    if (!mounted) return;
    setState(() {
      _generating = false;
      _generated = note;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final prompt = ref.watch(
      systemFileProvider(
        widget.instance.id,
        'FEED_PROMPT.md',
        profile: ref.watch(nativeAgentProfileProvider),
      ),
    );
    final feed = ref.watch(
      feedProvider(
        widget.instance.id,
        profile: ref.watch(nativeAgentProfileProvider),
      ),
    );
    final posts = feed.value ?? const <FeedPost>[];
    final promptFile = prompt.value;
    return HermuseRoute(
      title: 'Feed',
      children: [
        ProductCard(
          children: [
            Text(
              'YOUR FEED PROMPT',
              style: YsType.caption.flutter.copyWith(
                color: palette.contentSubtleColor,
              ),
            ),
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
                  const SizedBox(width: YsSpace.sm),
                  YsButton.primary(
                    label: _saving ? 'Saving…' : 'Save',
                    onPressed: _saving ? null : () => unawaited(_save()),
                  ),
                ],
              ),
            ] else ...[
              if (prompt.hasError && promptFile == null)
                HermuseRouteError('Feed prompt failed: ${prompt.error}')
              else
                Text(
                  promptFile?.content ?? '',
                  style: YsType.body.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  YsButton.neutral(
                    label: 'Edit',
                    icon: YsIcon.pencil,
                    onPressed: promptFile == null
                        ? null
                        : () => setState(() {
                            _prompt.text = promptFile.content;
                            _editing = true;
                          }),
                  ),
                  const SizedBox(width: YsSpace.sm),
                  YsButton.primary(
                    label: _generating ? 'Generating…' : 'Generate',
                    icon: YsIcon.sparkles,
                    onPressed: _generating
                        ? null
                        : () => unawaited(_generate()),
                  ),
                ],
              ),
              if (_generated case final note?)
                Text(
                  note,
                  textAlign: TextAlign.end,
                  style: YsType.small.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
            ],
            if (_error case final error?) HermuseRouteError(error),
          ],
        ),
        if (feed.isLoading && feed.value == null)
          const HermuseRouteSkeleton(label: 'Loading feed…')
        else if (feed.hasError && feed.value == null)
          HermuseRouteError('Feed failed: ${feed.error}')
        else if (posts.isEmpty)
          HermuseRouteEmpty(
            art: YsArt.feed,
            title: 'Your feed is empty',
            body:
                'Posts show up here as your Hermes gets to know you. Edit the '
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
      ],
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// A post's `created_at` in full ("September 27, 2026 at 14:05", the time
/// left out for a bare date); text that is not a timestamp comes back as is.
String feedExactDate(String stamp) {
  final at = DateTime.tryParse(stamp);
  if (at == null) return stamp;
  final local = at.toLocal();
  final day = '${_monthNames[local.month - 1]} ${local.day}, ${local.year}';
  if (!stamp.contains(':')) return day;
  String two(int n) => n.toString().padLeft(2, '0');
  return '$day at ${two(local.hour)}:${two(local.minute)}';
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
  var _menuOpen = false;
  String? _error;

  /// "Why I created this", over the whole window.
  final _why = OverlayPortalController();

  Feed get _feed => ref.read(
    feedProvider(
      widget.instanceId,
      profile: ref.read(nativeAgentProfileProvider),
    ).notifier,
  );

  Future<bool> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = true;
    try {
      await call();
    } on Object catch (e) {
      ok = false;
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
    return ok;
  }

  Future<bool> _react(FeedReaction reaction) =>
      _run(() => _feed.react(widget.post.id, reaction));

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
    final image = post.imageUrl;
    final meta = [
      if (post.topic.isNotEmpty) post.topic,
      if (post.createdAt.isNotEmpty)
        formatTimestamp(post.createdAt, DateTime.now()),
    ].join(' · ');
    return OverlayPortal(
      controller: _why,
      overlayChildBuilder: (context) => YsDialog(
        title: 'Why I created this',
        onClose: _why.hide,
        child: Text(
          post.why,
          style: YsType.body.flutter.copyWith(color: palette.contentColor),
        ),
      ),
      child: YsHover(
        builder: (context, hovered) => ProductCard(
          lifted: hovered || _menuOpen,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.title,
                        style: YsType.title.flutter.copyWith(
                          color: palette.contentColor,
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Text(
                          meta,
                          style: YsType.caption.flutter.copyWith(
                            color: palette.contentSubtleColor,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: YsSpace.sm),
                YsMenuAnchor(
                  semanticLabel: 'Post actions',
                  onOpenChanged: (open) => setState(() => _menuOpen = open),
                  items: [
                    // The exact date: a label, picking it only closes the
                    // menu (the kit menu has no disabled entry).
                    if (post.createdAt.isNotEmpty)
                      YsMenuItem(
                        label: feedExactDate(post.createdAt),
                        icon: YsIcon.upcoming,
                        onSelected: () {},
                        enabled: false,
                      ),
                    if (post.why.isNotEmpty)
                      YsMenuItem(
                        label: 'Why I created this',
                        icon: YsIcon.ideas,
                        onSelected: _why.show,
                      ),
                    YsMenuItem(
                      label: 'Delete',
                      icon: YsIcon.trash,
                      destructive: true,
                      onSelected: () =>
                          unawaited(_run(() => _feed.delete(post.id))),
                    ),
                  ],
                  builder: (context, menu) => YsButton.icon(
                    icon: YsIcon.more,
                    onPressed: _busy ? null : () => menu.open(),
                    semanticLabel: 'More actions for ${post.title}',
                    tooltip: 'More',
                    iconSize: YsLayout.inlineIcon,
                  ),
                ),
              ],
            ),
            MarkdownView(post.body),
            if (image != null)
              _PostImage(instanceId: widget.instanceId, url: image),
            if (post.sources.isNotEmpty)
              Wrap(
                spacing: YsSpace.md,
                runSpacing: YsSpace.xs,
                children: [
                  for (final source in post.sources)
                    HermuseLink(
                      label: Uri.tryParse(source)?.host.isNotEmpty ?? false
                          ? Uri.parse(source).host
                          : source,
                      onPressed: () => unawaited(openExternalUrl(source)),
                    ),
                ],
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
                const SizedBox(width: YsSpace.md),
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
        ),
      ),
    );
  }
}

/// A post's picture, at most [YsLayout.feedImageMaxHeight] high: an
/// absolute URL from the network, an instance path through the profile's
/// REST client (it carries the instance's auth).
final class _PostImage extends ConsumerStatefulWidget {
  const _PostImage({required this.instanceId, required this.url});

  final String instanceId;
  final String url;

  @override
  ConsumerState<_PostImage> createState() => _PostImageState();
}

final class _PostImageState extends ConsumerState<_PostImage> {
  /// Bytes of an instance path; null for an absolute URL.
  Future<Uint8List>? _bytes;

  bool get _remote => Uri.tryParse(widget.url)?.hasScheme ?? false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PostImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  void _load() {
    if (_remote) {
      _bytes = null;
      return;
    }
    final rest = ref.read(
      restClientProvider(
        widget.instanceId,
        profile: ref.read(nativeAgentProfileProvider),
      ).future,
    );
    _bytes = rest.then((rest) => rest.getBytes(widget.url));
  }

  Widget _failed(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      'Image unavailable',
      style: YsType.caption.flutter.copyWith(color: palette.contentSubtleColor),
    );
  }

  Widget _frame(Widget image) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: YsLayout.feedImageMaxHeight),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(YsRadius.navRow),
      child: image,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes == null) {
      return _frame(
        Image.network(
          widget.url,
          width: double.infinity,
          fit: BoxFit.cover,
          semanticLabel: 'Post image',
          errorBuilder: (context, _, _) => _failed(context),
        ),
      );
    }
    return FutureBuilder(
      future: bytes,
      builder: (context, snapshot) => switch (snapshot) {
        AsyncSnapshot(:final data?) => _frame(
          Image.memory(
            data,
            width: double.infinity,
            fit: BoxFit.cover,
            semanticLabel: 'Post image',
            errorBuilder: (context, _, _) => _failed(context),
          ),
        ),
        AsyncSnapshot(hasError: true) => _failed(context),
        _ => const SizedBox.shrink(),
      },
    );
  }
}
