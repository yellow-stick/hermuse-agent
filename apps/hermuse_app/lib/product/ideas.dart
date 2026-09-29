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

/// Ideas: grouped cards (Featured first); a card starts the idea in chat;
/// per-idea feedback.
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
        final ideas = ref.watch(ideasProvider(instance.id));
        final all = ideas.value ?? const <Idea>[];
        final groups = <String, List<Idea>>{};
        for (final idea in all) {
          (groups[idea.group.isEmpty ? 'Featured' : idea.group] ??= []).add(
            idea,
          );
        }
        final ordered = groups.keys.toList()
          ..sort(
            (a, b) => a == 'Featured'
                ? -1
                : b == 'Featured'
                ? 1
                : a.compareTo(b),
          );
        return HermuseRoute(
          title: 'Ideas',
          children: [
            const HermuseRouteSub(
              "I'm always thinking about new ways to help. My favorites land "
              'here.',
            ),
            if (ideas.isLoading && ideas.value == null)
              const HermuseRouteSub('Loading ideas…')
            else if (ideas.hasError && ideas.value == null)
              HermuseRouteError('Ideas failed: ${ideas.error}')
            else if (all.isEmpty)
              const HermuseRouteEmpty(
                icon: YsIcon.ideas,
                title: 'No ideas yet',
                body: 'Ideas appear here as your Hermes thinks of them.',
              )
            else
              for (final group in ordered)
                HermuseRouteSection(
                  head: group,
                  children: [
                    for (final idea in groups[group]!)
                      _IdeaCard(
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

final class _IdeaCard extends ConsumerStatefulWidget {
  const _IdeaCard({
    required this.instanceId,
    required this.idea,
    required this.onStartInChat,
    super.key,
  });

  final String instanceId;
  final Idea idea;
  final ValueChanged<String> onStartInChat;

  @override
  ConsumerState<_IdeaCard> createState() => _IdeaCardState();
}

final class _IdeaCardState extends ConsumerState<_IdeaCard> {
  final _feedback = TextEditingController();
  var _open = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _feedback.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ideasProvider(widget.instanceId).notifier)
          .feedback(widget.idea.id, text);
      if (mounted) {
        setState(() {
          _feedback.clear();
          _open = false;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final idea = widget.idea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsPressable(
          onPressed: () => widget.onStartInChat(
            "Let's do this: ${idea.title}\n\n${idea.pitch}",
          ),
          semanticLabel: 'Start in chat: ${idea.title}',
          builder: (context, state) => ProductCard(
            highlighted: state.hovered || state.pressed,
            children: [
              Text(
                idea.title,
                style: YsType.heading.flutter.copyWith(
                  color: palette.contentColor,
                ),
              ),
              Text(
                idea.pitch,
                style: YsType.agentBubble.flutter.copyWith(
                  color: palette.contentMutedColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: HermuseLink(
            label: 'Idea feedback',
            onPressed: () => setState(() => _open = !_open),
          ),
        ),
        if (_open) ...[
          for (final past in idea.feedback) ...[
            const SizedBox(height: 8),
            Text(
              past.text,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
          const SizedBox(height: 8),
          ProductInputRow(
            controller: _feedback,
            placeholder: 'What do you think?',
            action: 'Send',
            busy: _busy,
            onSubmit: () => unawaited(_send()),
          ),
          if (_error case final error?) HermuseRouteError(error),
        ],
      ],
    );
  }
}
