import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'feed.dart';
import 'route.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Ideas: the starter catalog and the agent's own ideas, grouped by theme.
/// Each row: its icon, title and pitch, "Try it" (sends the idea's first
/// step, else its title, in the main chat) and a "…" menu (feedback on the
/// agent's ideas, Dismiss).
class HermuseIdeas extends StatelessComponent {
  const HermuseIdeas({
    required this.instance,
    required this.profile,
    required this.onStartInChat,
    super.key,
  });

  final HermesInstance instance;
  final String profile;
  final void Function(String seed) onStartInChat;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: instance,
    title: 'Ideas',
    child: HermuseWatch(
      provider: ideasProvider(instance.id, profile: profile),
      builder: (context, ideas) => _body(context, ideas),
    ),
  );

  Component _body(BuildContext context, AsyncValue<List<Idea>> ideas) {
    final all = ideas.value ?? const <Idea>[];
    final groups = <String, List<Idea>>{};
    for (final idea in all) {
      (groups[idea.group.isEmpty ? 'Featured' : idea.group] ??= []).add(idea);
    }
    final ordered = groups.keys.toList()
      ..sort(
        (first, second) => first == 'Featured'
            ? -1
            : second == 'Featured'
            ? 1
            : first.compareTo(second),
      );
    return div(classes: 'hermuse-route', [
      div(classes: 'hermuse-route-column', [
        div(classes: 'hermuse-route-head', [
          h1(classes: 'hermuse-route-title', [.text('Ideas')]),
        ]),
        p(classes: 'hermuse-route-sub', [
          .text(
            "I'm always thinking about new ways to help. My favorites land here.",
          ),
        ]),
        if (ideas.isLoading && ideas.value == null)
          const HermuseRouteSkeleton(label: 'Loading ideas…')
        else if (ideas.hasError && ideas.value == null)
          p(classes: 'hermuse-route-error', [
            .text('Ideas failed: ${ideas.error}'),
          ])
        else if (all.isEmpty)
          HermuseRouteEmpty(
            art: YsArt.ideas,
            title: 'No ideas yet',
            body: 'Ideas land here as your Hermes thinks of them.',
          )
        else
          for (final group in ordered)
            div(classes: 'hermuse-route-section', [
              h2(classes: 'hermuse-route-section-head', [.text(group)]),
              for (final idea in groups[group]!)
                _IdeaRow(
                  key: ValueKey(idea.id),
                  instanceId: instance.id,
                  profile: profile,
                  idea: idea,
                  onStartInChat: onStartInChat,
                ),
            ]),
      ]),
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-idea-wrap')
        .styles(display: .flex, flexDirection: .column, gap: .all(8.px)),
    css('.hermuse-ob-grow').styles(flex: .grow(1)),
    css('.hermuse-idea-card').styles(
      width: 100.percent,
      padding: .all(YsSpace.lg.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.md.px),
      color: .variable('--content'),
      backgroundColor: .variable('--paper'),
      raw: {'box-shadow': 'var(--raised)'},
    ),
    // The idea's icon lights up and grows while the idea takes off.
    css('.hermuse-idea-icon').styles(
      display: .inlineFlex,
      padding: .only(top: 1.px),
      color: .variable('--content-muted'),
      raw: {
        'transition':
            'color ${YsMotion.fast}ms linear, '
            'scale ${YsMotion.fast}ms ${YsEase.settle.css}',
      },
    ),
    css('.hermuse-idea-icon[data-on]')
        .styles(color: .variable('--primary-ink'), raw: {'scale': '1.25'}),
    css('.hermuse-idea-text').styles(
      flex: Flex(grow: 1, shrink: 1, basis: .zero),
      display: .flex,
      flexDirection: .column,
      gap: .all(4.px),
      raw: {'min-width': '0'},
    ),
    css('.hermuse-idea-title').styles(
      margin: .zero,
      fontSize: 16.px,
      lineHeight: 22.px,
      fontWeight: .w600,
    ),
    css('.hermuse-idea-pitch').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'break-word'},
    ),
    css('.hermuse-idea-actions').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.xs.px),
      color: .variable('--content-muted'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-idea-feedback').styles(
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      padding: .symmetric(horizontal: YsSpace.lg.px),
    ),
    css('.hermuse-idea-feedback-row').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-idea-feedback-past').styles(
      margin: .zero,
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-subtle'),
    ),
  ];
}

/// The icon of an idea's [Idea.icon] key (desktop mapping).
YsIcon _ideaIcon(String key) => switch (key) {
  'workout' => YsIcon.dumbbell,
  'shopping' => YsIcon.shoppingBag,
  'people' => YsIcon.users,
  'city' => YsIcon.building,
  'documents' => YsIcon.fileText,
  'returns' => YsIcon.undo,
  'inbox' => YsIcon.inbox,
  'money' => YsIcon.wallet,
  'health' => YsIcon.heartPulse,
  'travel' => YsIcon.plane,
  _ => YsIcon.ideas,
};

class _IdeaRow extends StatefulComponent {
  const _IdeaRow({
    required this.instanceId,
    required this.profile,
    required this.idea,
    required this.onStartInChat,
    super.key,
  });

  final String instanceId;
  final String profile;
  final Idea idea;
  final void Function(String seed) onStartInChat;

  @override
  State<_IdeaRow> createState() => _IdeaRowState();
}

class _IdeaRowState extends State<_IdeaRow> {
  final _more = GlobalNodeKey<web.HTMLElement>();

  /// Where the "…" menu opens; null while it is closed.
  YsMenuAnchor? _menu;

  var _feedbackOpen = false;
  var _feedback = '';
  var _busy = false;
  String? _error;

  /// The accepted moment: sparks fly out of the idea's icon, then the idea
  /// lands in the chat.
  var _accepting = false;
  Timer? _accept;

  Ideas get _ideas => context.container.read(
    ideasProvider(component.instanceId, profile: component.profile).notifier,
  );

  @override
  void dispose() {
    _accept?.cancel();
    super.dispose();
  }

  /// "Try it": the main chat starts on the idea's first step (its title
  /// when it has none).
  void _start() {
    final idea = component.idea;
    final seed = idea.firstStep.trim().isNotEmpty
        ? idea.firstStep.trim()
        : idea.title;
    void go() => component.onStartInChat(seed);
    if (_accepting) return;
    if (ysReducedMotion()) {
      go();
      return;
    }
    setState(() => _accepting = true);
    _accept = Timer(Duration(milliseconds: ysFramesMs(YsBurst.frames)), () {
      if (!mounted) return;
      setState(() => _accepting = false);
      go();
    });
  }

  void _openMenu() {
    final trigger = _more.currentNode;
    if (trigger != null) setState(() => _menu = YsMenuAnchor.of(trigger));
  }

  @override
  Component build(BuildContext context) {
    final idea = component.idea;
    return div(classes: 'hermuse-idea-wrap', [
      div(classes: 'hermuse-idea-card', [
        YsBurstView(
          play: _accepting,
          child: span(
            classes: 'hermuse-idea-icon',
            attributes: {if (_accepting) 'data-on': ''},
            [YsIconView(_ideaIcon(idea.icon), size: 20)],
          ),
        ),
        div(classes: 'hermuse-idea-text', [
          h3(classes: 'hermuse-idea-title', [.text(idea.title)]),
          if (idea.pitch.isNotEmpty)
            p(classes: 'hermuse-idea-pitch', [.text(idea.pitch)]),
        ]),
        div(classes: 'hermuse-idea-actions', [
          YsButton.pill(
            label: 'Try it',
            small: true,
            onPressed: _busy ? null : _start,
          ),
          span(key: _more, [
            YsButton.icon(
              icon: YsIcon.more,
              label: 'More actions for ${idea.title}',
              onPressed: _openMenu,
              attributes: {
                'aria-haspopup': 'menu',
                'aria-expanded': '${_menu != null}',
              },
            ),
          ]),
        ]),
      ]),
      if (_feedbackOpen)
        div(classes: 'hermuse-idea-feedback', [
          for (final past in idea.feedback)
            p(classes: 'hermuse-idea-feedback-past', [.text(past.text)]),
          div(classes: 'hermuse-idea-feedback-row', [
            div(classes: 'hermuse-ob-grow', [
              YsInputBox(
                value: _feedback,
                onChanged: (v) => setState(() => _feedback = v),
                onSubmitted: () => unawaited(_send()),
                placeholder: 'What do you think?',
                name: 'feedback-${idea.id}',
                label: 'Idea feedback',
              ),
            ]),
            YsButton.neutral(
              label: 'Cancel',
              onPressed: _busy
                  ? null
                  : () => setState(() => _feedbackOpen = false),
            ),
            YsButton.primary(
              label: _busy ? '…' : 'Send',
              onPressed: _busy || _feedback.trim().isEmpty
                  ? null
                  : () => unawaited(_send()),
            ),
          ]),
        ]),
      if (_error case final error?)
        p(classes: 'hermuse-route-error', [.text(error)]),
      if (_menu case final anchor?)
        YsMenu(
          label: 'Actions for ${idea.title}',
          anchor: anchor,
          onClose: () => setState(() => _menu = null),
          items: [
            // Starter ideas are static: only the agent's take feedback.
            if (!idea.seeded)
              YsMenuItem(
                label: 'Idea feedback',
                icon: YsIcon.reply,
                onSelected: () => setState(() => _feedbackOpen = true),
              ),
            YsMenuItem(
              label: 'Dismiss',
              icon: YsIcon.close,
              onSelected: () => unawaited(_dismiss()),
            ),
          ],
        ),
    ]);
  }

  /// Hides the idea; the list drops it, a refusal is told under the row.
  Future<void> _dismiss() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ideas.dismiss(component.idea.id);
      return;
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not dismiss this idea: ${hermuseErrorText(e)}',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _send() async {
    final text = _feedback.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _ideas.feedback(component.idea.id, text);
      if (mounted) {
        setState(() {
          _feedback = '';
          _feedbackOpen = false;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }
}
