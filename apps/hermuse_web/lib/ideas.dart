import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'feed.dart';
import 'route.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Ideas: grouped cards; clicking one starts it in chat; per-idea feedback.
class HermuseIdeas extends StatelessComponent {
  const HermuseIdeas({
    required this.instance,
    required this.onStartInChat,
    super.key,
  });

  final HermesInstance instance;
  final void Function(String seed) onStartInChat;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: instance,
    title: 'Ideas',
    child: HermuseWatch(
      provider: ideasProvider(instance.id),
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
                _IdeaCard(
                  key: ValueKey(idea.id),
                  instanceId: instance.id,
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
    css('.hermuse-idea-wrap').styles(display: .flex, flexDirection: .column),
    css('.hermuse-ob-grow').styles(flex: .grow(1)),
    css('.hermuse-ob-link').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--primary-ink'),
      cursor: .pointer,
      border: .none,
      backgroundColor: Colors.transparent,
    ),
    css('.hermuse-idea-card').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 16.px, horizontal: 16.px),
      radius: .circular(YsRadius.bubble.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      color: .variable('--content'),
      backgroundColor: .variable('--paper'),
      cursor: .pointer,
      border: .none,
      textAlign: .left,
      // Rests raised; `ys-lift` still swaps in its hover shadow.
      raw: {'--ys-lift-rest': 'var(--raised)'},
    ),
    css('.hermuse-idea-card.ys-lift').styles(
      raw: {
        'transition':
            'background-color ${YsMotion.fast}ms linear, $ysLiftTransition',
      },
    ),
    css('.hermuse-idea-card:hover')
        .styles(backgroundColor: .variable('--neutral-film')),
    css('.hermuse-idea-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.md.px),
    ),
    css('.hermuse-idea-title').styles(
      margin: .zero,
      flex: Flex(grow: 1, shrink: 1, basis: .zero),
      fontSize: 16.px,
      lineHeight: 22.px,
      fontWeight: .w600,
    ),
    // The spark lights up under the pointer and grows while the idea
    // takes off.
    css('.hermuse-idea-spark').styles(
      display: .inlineFlex,
      color: .variable('--content-subtle'),
      raw: {
        'transition':
            'color ${YsMotion.fast}ms linear, '
            'scale ${YsMotion.fast}ms ${YsEase.settle.css}',
      },
    ),
    css(
      '.hermuse-idea-card:hover .hermuse-idea-spark, '
      '.hermuse-idea-spark[data-on]',
    ).styles(color: .variable('--primary-ink')),
    css('.hermuse-idea-spark[data-on]').styles(raw: {'scale': '1.25'}),
    css('.hermuse-idea-pitch').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 22.px,
      color: .variable('--content-muted'),
      raw: {'white-space': 'pre-wrap', 'overflow-wrap': 'break-word'},
    ),
    css('.hermuse-idea-feedback').styles(
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      margin: .only(top: 8.px),
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

class _IdeaCard extends StatefulComponent {
  const _IdeaCard({
    required this.instanceId,
    required this.idea,
    required this.onStartInChat,
    super.key,
  });

  final String instanceId;
  final Idea idea;
  final void Function(String seed) onStartInChat;

  @override
  State<_IdeaCard> createState() => _IdeaCardState();
}

class _IdeaCardState extends State<_IdeaCard> {
  var _feedbackOpen = false;
  var _feedback = '';
  var _busy = false;
  String? _error;

  /// The accepted moment: sparks fly out of the card's spark, then the idea
  /// lands in the chat.
  var _accepting = false;
  Timer? _accept;

  @override
  void dispose() {
    _accept?.cancel();
    super.dispose();
  }

  void _start() {
    final idea = component.idea;
    void go() => component.onStartInChat(
      "Let's do this: ${idea.title}\n\n${idea.pitch}",
    );
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

  @override
  Component build(BuildContext context) {
    final idea = component.idea;
    return div(classes: 'hermuse-idea-wrap', [
      YsPressable(
        onPressed: _start,
        label: 'Start in chat: ${idea.title}',
        classes: 'hermuse-idea-card ys-lift ys-press',
        builder: (context, press) => .fragment([
          div(classes: 'hermuse-idea-head', [
            h3(classes: 'hermuse-idea-title', [.text(idea.title)]),
            YsBurstView(
              play: _accepting,
              child: span(
                classes: 'hermuse-idea-spark',
                attributes: {if (_accepting) 'data-on': ''},
                [YsIconView(YsIcon.sparkles, size: 18)],
              ),
            ),
          ]),
          p(classes: 'hermuse-idea-pitch', [.text(idea.pitch)]),
        ]),
      ),
      div(classes: 'hermuse-idea-feedback', [
        YsPressable(
          onPressed: () => setState(() => _feedbackOpen = !_feedbackOpen),
          label: 'Idea feedback',
          classes: 'hermuse-ob-link',
          builder: (context, press) => span([.text('Idea feedback')]),
        ),
        if (_feedbackOpen) ...[
          for (final past in idea.feedback)
            p(classes: 'hermuse-idea-feedback-past', [.text(past.text)]),
          div(classes: 'hermuse-idea-feedback-row', [
            div(classes: 'hermuse-ob-grow', [
              YsInputBox(
                value: _feedback,
                onChanged: (v) => setState(() => _feedback = v),
                onSubmitted: () => unawaited(_send(context)),
                placeholder: 'What do you think?',
                name: 'feedback-${idea.id}',
                label: 'Idea feedback',
              ),
            ]),
            YsButton.primary(
              label: _busy ? '…' : 'Send',
              onPressed: _busy || _feedback.trim().isEmpty
                  ? null
                  : () => unawaited(_send(context)),
            ),
          ]),
          if (_error case final error?)
            p(classes: 'hermuse-route-error', [.text(error)]),
        ],
      ]),
    ]);
  }

  Future<void> _send(BuildContext context) async {
    final text = _feedback.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.container
          .read(ideasProvider(component.instanceId).notifier)
          .feedback(component.idea.id, text);
      if (mounted) {
        setState(() {
          _feedback = '';
          _feedbackOpen = false;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}
