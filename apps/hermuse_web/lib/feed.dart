import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show formatTimestamp;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'route.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Shown when the Hermuse plugin backend is missing on an instance.
///
/// The page keeps the destination title and offers, in a card headed by
/// the plugin drawing, to install the plugin through the instance's
/// dashboard ([installHermusePlugin]), with the commands to install it by
/// hand from a Hermuse checkout as a fallback.
class HermusePluginMissing extends StatefulComponent {
  const HermusePluginMissing({
    required this.instance,
    required this.title,
    super.key,
  });

  final HermesInstance instance;

  /// Destination title (Feed, Ideas, Goals, Library).
  final String title;

  static const commands =
      '# on your computer, from the Hermuse repository\n'
      'scp -r hermes-plugin/hermuse you@your-server:~/.hermes/plugins/\n'
      '# on the server\n'
      'hermes plugins enable hermuse\n'
      'hermes hermuse enable\n'
      '# then restart Hermes (hermes serve or the dashboard)';

  @override
  State<HermusePluginMissing> createState() => _HermusePluginMissingState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-plugin-card').styles(
      padding: .all(20.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(12.px),
      backgroundColor: .variable('--paper'),
    ),
    // The card's drawing sits at its start, like the text under it.
    css('.hermuse-plugin-card .hermuse-card-art')
        .styles(margin: .only(bottom: YsSpace.xs.px)),
    css('.hermuse-plugin-heading').styles(
      margin: .zero,
      fontSize: 16.px,
      lineHeight: 22.px,
      fontWeight: .w500,
    ),
    css('.hermuse-plugin-body').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
    ),
    // Hermes' scan report behind the consent prompt, in small text.
    css('.hermuse-plugin-consent').styles(
      margin: .zero,
      fontSize: 12.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'anywhere'},
    ),
    css('.hermuse-plugin-actions')
        .styles(display: .flex, gap: .all(8.px), raw: {'flex-wrap': 'wrap'}),
    css('.hermuse-plugin-cmd').styles(
      width: 100.percent,
      margin: .zero,
      padding: .all(14.px),
      radius: .circular(YsRadius.row.px),
      color: .variable('--content'),
      backgroundColor: .variable('--canvas'),
      fontSize: 13.px,
      lineHeight: 20.px,
      raw: {
        'overflow-x': 'auto',
        'white-space': 'pre',
        'box-sizing': 'border-box',
        'font-family':
            'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      },
    ),
  ];
}

class _HermusePluginMissingState extends State<HermusePluginMissing> {
  var _busy = false;
  String? _error;
  List<PluginScanFinding> _findings = const [];

  /// The dashboard installed the plugin but must restart to serve it.
  var _needsRestart = false;

  /// Hermes' scan report while the install waits for the user's consent.
  String? _consent;

  /// [force] once the user allowed a "caution" scan verdict.
  Future<void> _install({bool force = false}) async {
    final id = component.instance.id;
    setState(() {
      _busy = true;
      _error = null;
      _findings = const [];
      _needsRestart = false;
    });
    try {
      final rest = await context.container.read(restClientProvider(id).future);
      final result = await installHermusePlugin(rest, force: force);
      if (!mounted) return;
      setState(() => _consent = null);
      switch (result) {
        case PluginInstalled():
          context.container.invalidate(pluginStatusProvider(id));
        case PluginNeedsConsent(:final detail):
          setState(() => _consent = detail);
        case PluginNeedsDashboardRestart():
          setState(() => _needsRestart = true);
        case PluginInstallFailed(:final message, :final findings):
          setState(() {
            _error = message;
            _findings = findings;
          });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Component build(BuildContext context) {
    final instance = component.instance;
    return div(classes: 'hermuse-route', [
      div(classes: 'hermuse-route-column', [
        div(classes: 'hermuse-route-head', [
          h1(classes: 'hermuse-route-title', [.text(component.title)]),
        ]),
        div(classes: 'hermuse-plugin-card', [
          // The plugin piece, looping while it installs.
          HermuseCardArt(YsArt.plugin, busy: _busy),
          h2(classes: 'hermuse-plugin-heading', [
            .text('Turn on Feed, Ideas, Goals and Library'),
          ]),
          p(classes: 'hermuse-plugin-body', [
            .text(
              'These pages come from the Hermuse plugin, which runs on your '
              'Hermes. It is not installed on ${instance.label} yet.',
            ),
          ]),
          if (_consent case final consent?) ...[
            p(classes: 'hermuse-plugin-body', [
              .text(
                'Hermuse needs permission to install Docker with sudo on '
                'this server (Hermes flags this for review).',
              ),
            ]),
            p(classes: 'hermuse-plugin-consent', [.text(consent)]),
          ],
          div(classes: 'hermuse-plugin-actions', [
            if (_consent != null)
              YsButton.primary(
                label: _busy ? 'Installing…' : 'Allow and install',
                onPressed: _busy
                    ? null
                    : () => unawaited(_install(force: true)),
              )
            else
              YsButton.primary(
                label: _busy ? 'Installing…' : 'Install Hermuse on this Hermes',
                onPressed: _busy ? null : () => unawaited(_install()),
              ),
            YsButton.neutral(
              label: 'Check again',
              onPressed: () => context.container.invalidate(
                pluginStatusProvider(instance.id),
              ),
            ),
          ]),
          if (_needsRestart) ...[
            p(classes: 'hermuse-plugin-body', [
              .text(
                'Restart the Hermes dashboard to finish installing Hermuse. '
                'Under systemd run the command below; otherwise stop '
                '`hermes dashboard` and start it again. Then check again.',
              ),
            ]),
            pre(classes: 'hermuse-plugin-cmd', [
              .text('systemctl --user restart hermes-dashboard'),
            ]),
          ],
          if (_error case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
          if (_findings.isNotEmpty)
            pre(classes: 'hermuse-plugin-cmd', [
              .text([for (final f in _findings) '$f'].join('\n')),
            ]),
          p(classes: 'hermuse-plugin-body', [.text('Or install it by hand:')]),
          pre(classes: 'hermuse-plugin-cmd', [
            .text(HermusePluginMissing.commands),
          ]),
        ]),
      ]),
    ]);
  }
}

/// Gates [child] on the plugin backend: missing → [HermusePluginMissing];
/// out of reach → why, with Check again; loading → the page's cards
/// shimmering (desktop `PluginGate` parity).
class HermusePluginGate extends StatelessComponent {
  const HermusePluginGate({
    required this.instance,
    required this.title,
    required this.child,
    super.key,
  });

  final HermesInstance instance;

  /// Destination title shown while loading and when the plugin is missing.
  final String title;
  final Component child;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: pluginStatusProvider(instance.id),
    builder: (context, status) {
      final presence = status.value;
      // The page stays through a refresh; a failed check is not "missing".
      if (presence == PluginPresence.installed) return child;
      final error = status.error;
      if (error == null && presence == PluginPresence.missing) {
        return HermusePluginMissing(instance: instance, title: title);
      }
      return div(classes: 'hermuse-route', [
        div(classes: 'hermuse-route-column', [
          div(classes: 'hermuse-route-head', [
            h1(classes: 'hermuse-route-title', [.text(title)]),
          ]),
          // Out of reach, from the first failure: why, and the pulled plug
          // looping while a retry runs.
          if (error != null) ...[
            HermuseCardArt(YsArt.unreachable, busy: status.isLoading),
            p(classes: 'hermuse-route-error', [
              .text('Could not reach the Hermuse plugin: $error'),
            ]),
            div(classes: 'hermuse-plugin-actions', [
              YsButton.neutral(
                label: 'Check again',
                onPressed: () => context.container.invalidate(
                  pluginStatusProvider(instance.id),
                ),
              ),
            ]),
          ] else
            HermuseRouteSkeleton(label: 'Loading…'),
        ]),
      ]);
    },
  );
}

/// Feed: editable prompt (FEED_PROMPT.md) + post cards with Love/Discuss.
///
/// Discuss toggles the reaction and opens a new chat seeded with the post.
class HermuseFeed extends StatefulComponent {
  const HermuseFeed({
    required this.instance,
    required this.onDiscuss,
    super.key,
  });

  final HermesInstance instance;
  final void Function(String seed) onDiscuss;

  @override
  State<HermuseFeed> createState() => _HermuseFeedState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-feed-prompt').styles(
      margin: .zero,
      fontSize: 16.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-ob-row').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-ob-grow').styles(flex: .grow(1)),
    css('.hermuse-feed-card').styles(
      padding: .symmetric(vertical: 20.px, horizontal: 20.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(12.px),
      backgroundColor: .variable('--paper'),
    ),
    css('.hermuse-feed-title').styles(
      margin: .zero,
      fontSize: 22.px,
      lineHeight: 28.px,
      fontWeight: .w600,
    ),
    css('.hermuse-feed-meta').styles(
      margin: .zero,
      fontSize: 12.px,
      lineHeight: 16.px,
      color: .variable('--content-subtle'),
    ),
    css('.hermuse-feed-body').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 24.px,
      color: .variable('--content'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'break-word'},
    ),
    css('.hermuse-feed-actions')
        .styles(display: .flex, flexDirection: .row, gap: .all(12.px)),
    css('.hermuse-feed-react').styles(
      height: 36.px,
      padding: .symmetric(horizontal: 16.px),
      radius: .circular(YsRadius.pill.px),
      display: .inlineFlex,
      alignItems: .center,
      color: .variable('--content'),
      backgroundColor: .variable('--neutral-ambient'),
      cursor: .pointer,
      border: .none,
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
    ),
    css('.hermuse-feed-react-on').styles(
      color: .variable('--primary-content'),
      backgroundColor: .variable('--primary'),
    ),
  ];
}

class _HermuseFeedState extends State<HermuseFeed> {
  var _editingPrompt = false;
  var _promptDraft = '';
  var _promptLoaded = false;
  var _savingPrompt = false;
  String? _error;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: component.instance,
    title: 'Feed',
    child: HermuseWatch(
      provider: systemFileProvider(component.instance.id, 'FEED_PROMPT.md'),
      builder: (context, prompt) => HermuseWatch(
        provider: feedProvider(component.instance.id),
        builder: (context, feed) => _body(context, prompt, feed),
      ),
    ),
  );

  Component _body(
    BuildContext context,
    AsyncValue<SystemFile> prompt,
    AsyncValue<List<FeedPost>> feed,
  ) {
    final posts = feed.value ?? const <FeedPost>[];
    final promptFile = prompt.value;
    if (!_promptLoaded && promptFile != null) {
      _promptLoaded = true;
      _promptDraft = promptFile.content;
    }
    return div(classes: 'hermuse-route', [
      div(classes: 'hermuse-route-column', [
        div(classes: 'hermuse-route-head', [
          h1(classes: 'hermuse-route-title', [.text('Feed')]),
        ]),
        div(classes: 'hermuse-route-section', [
          h2(classes: 'hermuse-route-section-head', [
            .text('YOUR FEED PROMPT'),
          ]),
          if (_editingPrompt) ...[
            YsTextBox(
              value: _promptDraft,
              onChanged: (v) => setState(() => _promptDraft = v),
              label: 'Feed prompt',
              minHeight: 96,
              maxHeight: 240,
            ),
            div(classes: 'hermuse-ob-row', [
              div(classes: 'hermuse-ob-grow', []),
              YsButton.neutral(
                label: 'Cancel',
                onPressed: _savingPrompt
                    ? null
                    : () => setState(() {
                        _editingPrompt = false;
                        _promptDraft = promptFile?.content ?? '';
                      }),
              ),
              YsButton.primary(
                label: _savingPrompt ? 'Saving…' : 'Save',
                onPressed: _savingPrompt
                    ? null
                    : () => unawaited(_savePrompt(context)),
              ),
            ]),
          ] else ...[
            p(classes: 'hermuse-feed-prompt', [
              .text(promptFile?.content ?? ''),
            ]),
            div(classes: 'hermuse-ob-row', [
              div(classes: 'hermuse-ob-grow', []),
              YsButton.neutral(
                label: 'Edit',
                onPressed: promptFile == null
                    ? null
                    : () => setState(() => _editingPrompt = true),
              ),
            ]),
          ],
        ]),
        if (feed.isLoading && feed.value == null)
          const HermuseRouteSkeleton(label: 'Loading feed…')
        else if (feed.hasError && feed.value == null)
          p(classes: 'hermuse-route-error', [
            .text('Feed failed: ${feed.error}'),
          ])
        else if (posts.isEmpty)
          HermuseRouteEmpty(
            art: YsArt.feed,
            title: 'Your feed is empty',
            body:
                'Posts show up here as your Hermes gets to know you. Edit '
                'the prompt above to steer it.',
          )
        else
          for (final post in posts)
            _FeedCard(
              key: ValueKey(post.id),
              instanceId: component.instance.id,
              post: post,
              onDiscuss: component.onDiscuss,
            ),
        if (_error case final error?)
          p(classes: 'hermuse-route-error', [.text(error)]),
      ]),
    ]);
  }

  Future<void> _savePrompt(BuildContext context) async {
    setState(() {
      _savingPrompt = true;
      _error = null;
    });
    try {
      await context.container
          .read(
            systemFileProvider(
              component.instance.id,
              'FEED_PROMPT.md',
            ).notifier,
          )
          .save(_promptDraft);
      if (mounted) setState(() => _editingPrompt = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _savingPrompt = false);
  }
}

class _FeedCard extends StatefulComponent {
  const _FeedCard({
    required this.instanceId,
    required this.post,
    required this.onDiscuss,
    super.key,
  });

  final String instanceId;
  final FeedPost post;
  final void Function(String seed) onDiscuss;

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  var _busy = false;

  @override
  Component build(BuildContext context) {
    final post = component.post;
    return article(classes: 'hermuse-feed-card ys-lift', [
      h2(classes: 'hermuse-feed-title', [.text(post.title)]),
      if (post.createdAt.isNotEmpty || post.topic.isNotEmpty)
        p(classes: 'hermuse-feed-meta', [
          .text(
            [
              if (post.topic.isNotEmpty) post.topic,
              if (post.createdAt.isNotEmpty)
                formatTimestamp(post.createdAt, DateTime.now()),
            ].join(' · '),
          ),
        ]),
      p(classes: 'hermuse-feed-body', [.text(post.body)]),
      div(classes: 'hermuse-feed-actions', [
        YsPressable(
          onPressed: _busy
              ? null
              : () => unawaited(_react(context, FeedReaction.love)),
          label: 'Love this post',
          classes: post.reacted(FeedReaction.love)
              ? 'hermuse-feed-react hermuse-feed-react-on'
              : 'hermuse-feed-react',
          builder: (context, press) => span([.text('Love')]),
        ),
        YsPressable(
          onPressed: _busy ? null : () => unawaited(_discuss(context)),
          label: 'Discuss this post',
          classes: post.reacted(FeedReaction.discuss)
              ? 'hermuse-feed-react hermuse-feed-react-on'
              : 'hermuse-feed-react',
          builder: (context, press) => span([.text('Discuss')]),
        ),
      ]),
    ]);
  }

  Future<void> _react(BuildContext context, FeedReaction reaction) async {
    setState(() => _busy = true);
    try {
      await context.container
          .read(feedProvider(component.instanceId).notifier)
          .react(component.post.id, reaction);
    } on Object catch (_) {
      // The feed list refresh shows the truth; a toast would be nicer.
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _discuss(BuildContext context) async {
    final post = component.post;
    if (!post.reacted(FeedReaction.discuss)) {
      await _react(context, FeedReaction.discuss);
    }
    if (mounted) {
      component.onDiscuss("Let's discuss: ${post.title}\n\n${post.body}");
    }
  }
}
