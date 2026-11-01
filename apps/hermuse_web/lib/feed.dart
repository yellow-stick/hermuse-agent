import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show formatTimestamp, urlHost;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'markdown_view.dart';
import 'route.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Shown when the Hermuse plugin backend is missing on an instance.
///
/// The page keeps the destination title and offers, in a card headed by
/// the plugin drawing, to install the plugin through the instance's
/// dashboard ([installHermusePlugin]); the server guide covers installing
/// it by hand.
class HermusePluginMissing extends StatefulComponent {
  const HermusePluginMissing({
    required this.instance,
    required this.title,
    super.key,
  });

  final HermesInstance instance;

  /// Destination title (Feed, Ideas, Goals, Library).
  final String title;

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
      raw: {'box-shadow': 'var(--raised)'},
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
    css('.hermuse-plugin-body a').styles(
      color: .variable('--primary-ink'),
      raw: {'text-decoration': 'underline', 'text-underline-offset': '2px'},
    ),
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

  /// How to restart the dashboard, which installed the plugin but must
  /// restart to serve it: the way that works on that server.
  ServerStep? _restart;

  /// Hermes' scan report while the install waits for the user's consent.
  String? _consent;

  /// [force] once the user allowed a "caution" scan verdict.
  Future<void> _install({bool force = false}) async {
    final id = component.instance.id;
    setState(() {
      _busy = true;
      _error = null;
      _findings = const [];
      _restart = null;
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
          final restart = (await readDashboardHost(rest)).restartDashboard;
          if (mounted) setState(() => _restart = restart);
        case PluginInstallFailed(:final message, :final findings):
          setState(() {
            _error = message;
            _findings = findings;
          });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
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
          if (_restart case final restart?) ...[
            p(classes: 'hermuse-plugin-body', [
              .text(
                'Restart the Hermes dashboard to finish installing Hermuse. '
                '${restart.note}',
              ),
            ]),
            if (restart.command case final command?)
              pre(classes: 'hermuse-plugin-cmd', [.text(command)]),
          ],
          if (_error case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
          if (_findings.isNotEmpty)
            pre(classes: 'hermuse-plugin-cmd', [
              .text([for (final f in _findings) '$f'].join('\n')),
            ]),
          p(classes: 'hermuse-plugin-body', [
            .text('To install it by hand instead, follow the '),
            a(
              href: hermusePluginByHandGuide,
              target: .blank,
              attributes: const {'rel': 'noopener noreferrer'},
              [.text('server guide')],
            ),
            .text('.'),
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

/// Feed: the editable prompt (FEED_PROMPT.md) with Generate, then post
/// cards: Markdown body, optional image, sources, a "…" menu (exact date,
/// "Why I created this", Delete) and Love / Discuss.
///
/// Discuss toggles the reaction and opens a new chat seeded with the post.
class HermuseFeed extends StatefulComponent {
  const HermuseFeed({
    required this.instance,
    required this.profile,
    required this.onDiscuss,
    super.key,
  });

  final HermesInstance instance;
  final String profile;
  final void Function(String seed) onDiscuss;

  @override
  State<HermuseFeed> createState() => _HermuseFeedState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-feed-prompt-card').styles(
      padding: .all(YsSpace.lg.px),
      radius: .circular(YsRadius.bubble.px),
      backgroundColor: .variable('--paper'),
      raw: {'box-shadow': 'var(--raised)'},
    ),
    // Beats the route's section-head size (`.hermuse-route …`).
    css('.hermuse-route .hermuse-feed-prompt-card .hermuse-feed-prompt-label')
        .styles(
          fontSize: 12.px,
          lineHeight: 16.px,
          color: .variable('--content-muted'),
          raw: {'letter-spacing': '0.06em'},
        ),
    css('.hermuse-feed-prompt').styles(
      margin: .zero,
      fontSize: 16.px,
      lineHeight: 22.px,
      color: .variable('--content'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'break-word'},
    ),
    css('.hermuse-feed-note').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-feed-left').styles(textAlign: .left),
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
      // Rests raised; `ys-lift` still swaps in its hover shadow.
      raw: {'--ys-lift-rest': 'var(--raised)'},
    ),
    css('.hermuse-feed-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-feed-more').styles(
      display: .inlineFlex,
      color: .variable('--content-muted'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-feed-title').styles(
      margin: .zero,
      flex: Flex(grow: 1, shrink: 1, basis: .zero),
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
    css('.hermuse-feed-image').styles(
      maxWidth: 100.percent,
      maxHeight: YsLayout.feedImageMaxHeight.px,
      radius: .circular(YsRadius.row.px),
      raw: {'display': 'block', 'object-fit': 'cover', 'align-self': 'start'},
    ),
    css(
      '.hermuse-feed-body',
    ).styles(fontSize: 15.px, lineHeight: 24.px, color: .variable('--content')),
    css('.hermuse-feed-sources').styles(
      margin: .zero,
      padding: .zero,
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
      raw: {'flex-wrap': 'wrap', 'list-style': 'none'},
    ),
    css('.hermuse-feed-sources a').styles(
      color: .variable('--primary-ink'),
      raw: {'text-decoration': 'underline', 'text-underline-offset': '2px'},
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

  var _generating = false;

  /// Told once an edition started ("Generating…").
  String? _generated;
  String? _generateError;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: component.instance,
    title: 'Feed',
    child: HermuseWatch(
      provider: systemFileProvider(
        component.instance.id,
        'FEED_PROMPT.md',
        profile: component.profile,
      ),
      builder: (context, prompt) => HermuseWatch(
        provider: feedProvider(
          component.instance.id,
          profile: component.profile,
        ),
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
        div(classes: 'hermuse-route-section hermuse-feed-prompt-card', [
          h2(classes: 'hermuse-route-section-head hermuse-feed-prompt-label', [
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
              YsButton.primary(
                label: _generating ? 'Starting…' : 'Generate',
                onPressed: _generating
                    ? null
                    : () => unawaited(_generate(context)),
              ),
            ]),
          ],
          if (_generated case final note?)
            p(classes: 'hermuse-feed-note', [.text(note)]),
          if (_generateError case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
          if (_error case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
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
                'the prompt above to steer it, or Generate an edition now.',
          )
        else
          for (final post in posts)
            _FeedCard(
              key: ValueKey(post.id),
              instanceId: component.instance.id,
              profile: component.profile,
              post: post,
              onDiscuss: component.onDiscuss,
            ),
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
              profile: component.profile,
            ).notifier,
          )
          .save(_promptDraft);
      if (mounted) setState(() => _editingPrompt = false);
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
    }
    if (mounted) setState(() => _savingPrompt = false);
  }

  /// Runs a feed edition now; its posts arrive once the agent wrote them.
  Future<void> _generate(BuildContext context) async {
    setState(() {
      _generating = true;
      _generated = null;
      _generateError = null;
    });
    String? note;
    String? error;
    try {
      await context.container
          .read(
            feedProvider(
              component.instance.id,
              profile: component.profile,
            ).notifier,
          )
          .generate();
      note = 'Generating… new posts appear in a few minutes';
    } on HermesHttpError catch (e) {
      error = e.statusCode == 409
          ? 'Scheduled feed is off'
          : 'Could not generate the feed: ${e.message}';
    } on Object catch (e) {
      error = 'Could not generate the feed: ${hermuseErrorText(e)}';
    }
    if (!mounted) return;
    setState(() {
      _generating = false;
      _generated = note;
      _generateError = error;
    });
  }
}

class _FeedCard extends StatefulComponent {
  const _FeedCard({
    required this.instanceId,
    required this.profile,
    required this.post,
    required this.onDiscuss,
    super.key,
  });

  final String instanceId;
  final String profile;
  final FeedPost post;
  final void Function(String seed) onDiscuss;

  @override
  State<_FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<_FeedCard> {
  var _busy = false;
  String? _error;
  final _more = GlobalNodeKey<web.HTMLElement>();

  /// Where the "…" menu opens; null while it is closed.
  YsMenuAnchor? _menu;
  var _whyOpen = false;

  Feed get _feed => context.container.read(
    feedProvider(component.instanceId, profile: component.profile).notifier,
  );

  void _openMenu() {
    final trigger = _more.currentNode;
    if (trigger != null) setState(() => _menu = YsMenuAnchor.of(trigger));
  }

  @override
  Component build(BuildContext context) {
    final post = component.post;
    final at = DateTime.tryParse(post.createdAt);
    // The menu and dialog sit beside the card: its hover lift (a
    // translate) would anchor their fixed layers to the card.
    return .fragment([
      article(classes: 'hermuse-feed-card ys-lift', [
        div(classes: 'hermuse-feed-head', [
          h2(classes: 'hermuse-feed-title', [.text(post.title)]),
          span(key: _more, classes: 'hermuse-feed-more', [
            YsButton.icon(
              icon: YsIcon.more,
              label: 'More actions for ${post.title}',
              onPressed: _openMenu,
              attributes: {
                'aria-haspopup': 'menu',
                'aria-expanded': '${_menu != null}',
              },
            ),
          ]),
        ]),
        if (at != null || post.topic.isNotEmpty)
          p(classes: 'hermuse-feed-meta', [
            .text(
              [
                if (post.topic.isNotEmpty) post.topic,
                if (at != null) formatTimestamp(post.createdAt, DateTime.now()),
              ].join(' · '),
            ),
          ]),
        if (post.imageUrl case final url?)
          _FeedImage(
            key: ValueKey(url),
            instanceId: component.instanceId,
            profile: component.profile,
            url: url,
          ),
        div(classes: 'hermuse-feed-body', [HermuseMarkdown(post.body)]),
        if (post.sources.isNotEmpty)
          ul(classes: 'hermuse-feed-sources', [
            li([.text('Sources')]),
            for (final source in post.sources) li([_source(source)]),
          ]),
        div(classes: 'hermuse-feed-actions', [
          YsPressable(
            onPressed: _busy
                ? null
                : () => unawaited(_react(FeedReaction.love)),
            label: 'Love this post',
            classes: post.reacted(FeedReaction.love)
                ? 'hermuse-feed-react hermuse-feed-react-on'
                : 'hermuse-feed-react',
            builder: (context, press) => span([.text('Love')]),
          ),
          YsPressable(
            onPressed: _busy ? null : () => unawaited(_discuss()),
            label: 'Discuss this post',
            classes: post.reacted(FeedReaction.discuss)
                ? 'hermuse-feed-react hermuse-feed-react-on'
                : 'hermuse-feed-react',
            builder: (context, press) => span([.text('Discuss')]),
          ),
        ]),
        if (_error case final error?)
          p(classes: 'hermuse-route-error', [.text(error)]),
      ]),
      if (_menu case final anchor?)
        YsMenu(
          label: 'Actions for ${post.title}',
          anchor: anchor,
          onClose: () => setState(() => _menu = null),
          items: [
            // The exact time; picking it only closes the menu.
            if (at != null)
              YsMenuItem(
                label: _exactTime(at),
                icon: YsIcon.upcoming,
                enabled: false,
                onSelected: () {},
              ),
            if (post.why.isNotEmpty)
              YsMenuItem(
                label: 'Why I created this',
                icon: YsIcon.sparkles,
                onSelected: () => setState(() => _whyOpen = true),
              ),
            YsMenuItem(
              label: 'Delete',
              icon: YsIcon.trash,
              destructive: true,
              onSelected: () => unawaited(_delete()),
            ),
          ],
        ),
      if (_whyOpen)
        YsDialog(
          title: 'Why I created this',
          onClose: () => setState(() => _whyOpen = false),
          child: p(classes: 'hermuse-card-body hermuse-feed-left', [
            .text(post.why),
          ]),
        ),
    ]);
  }

  /// A source: a link named by its host when it is a web address.
  static Component _source(String source) {
    final uri = Uri.tryParse(source.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return .text(source);
    }
    final host = urlHost(source);
    return a(
      href: uri.toString(),
      target: .blank,
      attributes: const {'rel': 'noopener noreferrer'},
      [.text(host.isEmpty ? source : host)],
    );
  }

  Future<void> _react(FeedReaction reaction) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _feed.react(component.post.id, reaction);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not save the reaction: ${hermuseErrorText(e)}',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _discuss() async {
    final post = component.post;
    if (!post.reacted(FeedReaction.discuss)) {
      await _react(FeedReaction.discuss);
    }
    if (mounted) {
      component.onDiscuss("Let's discuss: ${post.title}\n\n${post.body}");
    }
  }

  /// Deletes the post; the list drops it, a refusal is told on the card.
  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _feed.delete(component.post.id);
      return;
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not delete this post: ${hermuseErrorText(e)}',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// A post's image, at most [YsLayout.feedImageMaxHeight] tall: an http(s)
/// URL loads as is; a path on the instance loads through the profile's
/// REST client and shows from a blob URL.
class _FeedImage extends StatefulComponent {
  const _FeedImage({
    required this.instanceId,
    required this.profile,
    required this.url,
    super.key,
  });

  final String instanceId;
  final String profile;
  final String url;

  @override
  State<_FeedImage> createState() => _FeedImageState();
}

class _FeedImageState extends State<_FeedImage> {
  String? _src;

  /// The blob URL this image owns (revoked on dispose).
  String? _blob;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final url = component.url;
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.isScheme('https') || uri.isScheme('http'))) {
      _src = url;
    } else if (kIsWeb) {
      unawaited(_load(url.startsWith('/') ? url : '/$url'));
    }
  }

  Future<void> _load(String path) async {
    try {
      final rest = await context.container.read(
        restClientProvider(
          component.instanceId,
          profile: component.profile,
        ).future,
      );
      final bytes = await rest.getBytes(path);
      if (!mounted) return;
      final blob = web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
      setState(() => _src = _blob = blob);
    } on Object catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_blob case final blob?) web.URL.revokeObjectURL(blob);
    super.dispose();
  }

  @override
  Component build(BuildContext context) {
    if (_failed) {
      return p(classes: 'hermuse-feed-meta', [
        .text("This post's image could not load."),
      ]);
    }
    final src = _src;
    if (src == null) return .fragment(const []);
    return img(
      src: src,
      alt: '',
      loading: .lazy,
      referrerPolicy: .noReferrer,
      classes: 'hermuse-feed-image',
      events: {'error': (_) => setState(() => _failed = true)},
    );
  }
}

const _months = [
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

/// "October 3, 2026 at 9:05 AM", local time (the chat's 12-hour clock).
String _exactTime(DateTime at) {
  final local = at.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} ${local.day}, ${local.year} at '
      '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}
