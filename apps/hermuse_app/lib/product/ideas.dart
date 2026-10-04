import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/agents.dart' show nativeAgentProfileProvider;
import 'plugin_gate.dart';
import 'route.dart';
import 'widgets.dart';

/// Ideas: rows grouped under their heading (Featured, the ungrouped ones,
/// first; then the groups in list order). "Try it" starts the idea's first
/// step in the main chat; "…" holds Give feedback and Dismiss.
final class IdeasScreen extends ConsumerWidget {
  const IdeasScreen({
    required this.instance,
    required this.onStartInChat,
    super.key,
  });

  final HermesInstance instance;
  final ValueChanged<String> onStartInChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PluginGate(
    instance: instance,
    title: 'Ideas',
    child: Consumer(
      builder: (context, ref, _) {
        final ideas = ref.watch(
          ideasProvider(
            instance.id,
            profile: ref.watch(nativeAgentProfileProvider),
          ),
        );
        final all = ideas.value ?? const <Idea>[];
        final groups = <String, List<Idea>>{'Featured': []};
        for (final idea in all) {
          (groups[idea.group.isEmpty ? 'Featured' : idea.group] ??= []).add(
            idea,
          );
        }
        return HermuseRoute(
          title: 'Ideas',
          children: [
            const HermuseRouteSub(
              "I'm always thinking about new ways to help. My favorites land "
              'here.',
            ),
            if (ideas.isLoading && ideas.value == null)
              const HermuseRouteSkeleton(label: 'Loading ideas…')
            else if (ideas.hasError && ideas.value == null)
              HermuseRouteError('Ideas failed: ${ideas.error}')
            else if (all.isEmpty)
              HermuseRouteEmpty(
                art: YsArt.ideas,
                title: 'No ideas yet',
                body: 'Ideas land here as your Hermes thinks of them.',
              )
            else
              for (final MapEntry(key: group, value: list) in groups.entries)
                if (list.isNotEmpty)
                  HermuseRouteSection(
                    head: group,
                    children: [
                      for (final idea in list)
                        _IdeaRow(
                          key: ValueKey(idea.id),
                          instanceId: instance.id,
                          idea: idea,
                          onStartInChat: onStartInChat,
                        ),
                    ],
                  ),
          ],
        );
      },
    ),
  );
}

/// The glyph of an [Idea.icon] key; the ideas glyph when none matches.
YsIcon ideaIcon(String key) => switch (key) {
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

final class _IdeaRow extends ConsumerStatefulWidget {
  const _IdeaRow({
    required this.instanceId,
    required this.idea,
    required this.onStartInChat,
    super.key,
  });

  final String instanceId;
  final Idea idea;
  final ValueChanged<String> onStartInChat;

  @override
  ConsumerState<_IdeaRow> createState() => _IdeaRowState();
}

final class _IdeaRowState extends ConsumerState<_IdeaRow>
    with SingleTickerProviderStateMixin {
  final _feedback = TextEditingController();
  var _feedbackOpen = false;
  var _menuOpen = false;
  var _busy = false;
  String? _error;

  /// The accepted moment: sparks fly out of Try it, then the idea lands in
  /// the chat.
  late final _accept = AnimationController(
    vsync: this,
    duration: Duration(microseconds: (YsBurst.frames * 1e6 / 60).round()),
  );

  Ideas get _ideas => ref.read(
    ideasProvider(
      widget.instanceId,
      profile: ref.read(nativeAgentProfileProvider),
    ).notifier,
  );

  @override
  void dispose() {
    _accept.dispose();
    _feedback.dispose();
    super.dispose();
  }

  /// Try it: the idea's first step (its title when it has none) goes to the
  /// main chat.
  void _start() {
    final idea = widget.idea;
    final step = idea.firstStep.trim();
    void go() => widget.onStartInChat(step.isEmpty ? idea.title : step);
    if (_accept.isAnimating) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      go();
      return;
    }
    _accept.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _accept.value = 0;
      setState(() {});
      go();
    });
    setState(() {});
  }

  Future<void> _run(Future<void> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _send() async {
    final text = _feedback.text.trim();
    if (text.isEmpty || _busy) return;
    await _run(() async {
      await _ideas.feedback(widget.idea.id, text);
      if (mounted) {
        setState(() {
          _feedback.clear();
          _feedbackOpen = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final idea = widget.idea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsHover(
          builder: (context, hovered) => ProductCard(
            lifted: hovered || _menuOpen,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  YsIconWidget(
                    ideaIcon(idea.icon),
                    color: hovered
                        ? palette.primaryInkColor
                        : palette.contentMutedColor,
                  ),
                  const SizedBox(width: YsSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          idea.title,
                          style: YsType.heading.flutter.copyWith(
                            color: palette.contentColor,
                          ),
                        ),
                        if (idea.pitch.isNotEmpty)
                          Text(
                            idea.pitch,
                            style: YsType.small.flutter.copyWith(
                              color: palette.contentMutedColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: YsSpace.md),
                  YsBurstView(
                    play: _accept.isAnimating,
                    child: YsButton.neutral(
                      label: 'Try it',
                      semanticLabel: 'Try it: ${idea.title}',
                      onPressed: _start,
                    ),
                  ),
                  const SizedBox(width: YsSpace.xs),
                  YsMenuAnchor(
                    semanticLabel: 'Idea actions',
                    onOpenChanged: (open) => setState(() => _menuOpen = open),
                    items: [
                      YsMenuItem(
                        label: 'Give feedback',
                        icon: YsIcon.reply,
                        onSelected: () =>
                            setState(() => _feedbackOpen = !_feedbackOpen),
                      ),
                      YsMenuItem(
                        label: 'Dismiss',
                        icon: YsIcon.close,
                        destructive: true,
                        onSelected: () =>
                            unawaited(_run(() => _ideas.dismiss(idea.id))),
                      ),
                    ],
                    builder: (context, menu) => YsButton.icon(
                      icon: YsIcon.more,
                      onPressed: _busy ? null : () => menu.open(),
                      semanticLabel: 'More actions for ${idea.title}',
                      tooltip: 'More',
                      iconSize: YsLayout.inlineIcon,
                    ),
                  ),
                ],
              ),
              if (_error case final error?) HermuseRouteError(error),
            ],
          ),
        ),
        if (_feedbackOpen) ...[
          for (final past in idea.feedback) ...[
            const SizedBox(height: YsSpace.sm),
            Text(
              past.text,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
          const SizedBox(height: YsSpace.sm),
          ProductInputRow(
            controller: _feedback,
            placeholder: 'What do you think?',
            action: 'Send',
            busy: _busy,
            onSubmit: () => unawaited(_send()),
          ),
        ],
      ],
    );
  }
}
