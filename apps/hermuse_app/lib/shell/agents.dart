import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'screens.dart' show YsDialogError;

/// The product subtree keeps its agent scope for the lifetime of its dialogs.
final nativeAgentProfileProvider = Provider<String>(
  (ref) => 'default',
  dependencies: const [],
);

ImageProvider agentImage(
  BuildContext context, {
  required String profile,
  AgentProfile? agent,
  ChatState? chat,
}) => AssetImage(
  'assets/images/${agentAvatarAsset(agent?.avatarId ?? 'hermuse', chat: chat, animate: profile == 'default' && !MediaQuery.disableAnimationsOf(context))}',
);

final class AgentEditorAnchor extends StatefulWidget {
  const AgentEditorAnchor({
    required this.instanceId,
    required this.builder,
    this.profile,
    super.key,
  });

  final String instanceId;
  final String? profile;
  final Widget Function(BuildContext, VoidCallback) builder;

  @override
  State<AgentEditorAnchor> createState() => _AgentEditorAnchorState();
}

final class _AgentEditorAnchorState extends State<AgentEditorAnchor> {
  final _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => _AgentEditor(
      instanceId: widget.instanceId,
      profile: widget.profile,
      onClose: _portal.hide,
    ),
    child: widget.builder(context, _portal.show),
  );
}

final class AgentSwitcher extends ConsumerStatefulWidget {
  const AgentSwitcher({
    required this.instanceId,
    required this.profile,
    this.subtitle,
    super.key,
  });

  final String instanceId;
  final String profile;

  /// Set in the phone top bar: the switcher renders as a centered two-line
  /// title (agent name over [subtitle], the chat on screen) instead of the
  /// bordered avatar pill of the floating header.
  final String? subtitle;

  @override
  ConsumerState<AgentSwitcher> createState() => _AgentSwitcherState();
}

final class _AgentSwitcherState extends ConsumerState<AgentSwitcher> {
  String? _error;
  String? _failedProfile;

  Future<void> _open(String profile) async {
    setState(() => _error = null);
    try {
      await ref
          .read(activeThreadProvider.notifier)
          .openAgent(widget.instanceId, profile);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _failedProfile = profile;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final instanceId = widget.instanceId;
    final profile = widget.profile;
    final roster = ref.watch(agentProfilesProvider(instanceId));
    final agent = ref.watch(agentProfileProvider(instanceId, profile));
    final status = _error != null
        ? 'Switch failed — retry'
        : roster.hasError
        ? 'Agents unavailable'
        : roster.isLoading
        ? 'Loading agents…'
        : null;
    final name = agent?.displayName ?? profile;
    final subtitle = widget.subtitle;
    return AgentEditorAnchor(
      instanceId: instanceId,
      builder: (context, create) => AgentEditorAnchor(
        instanceId: instanceId,
        profile: profile,
        builder: (context, edit) => YsMenuAnchor(
          semanticLabel: 'Switch agent',
          items: [
            for (final item in roster.value ?? <AgentProfile>[])
              YsMenuItem(
                label: item.displayName,
                checked: item.profile == profile,
                onSelected: () => unawaited(_open(item.profile)),
              ),
            if (_error case final error?)
              YsMenuItem(
                label: 'Switch failed: $error — retry',
                onSelected: () => unawaited(_open(_failedProfile!)),
              ),
            if (roster.hasError)
              YsMenuItem(
                label: 'Could not load agents: ${roster.error} — retry',
                icon: YsIcon.upcoming,
                onSelected: () => unawaited(
                  ref.read(agentProfilesProvider(instanceId).notifier).reload(),
                ),
              ),
            YsMenuItem(
              label: 'Create agent…',
              icon: YsIcon.plus,
              onSelected: create,
            ),
            YsMenuItem(
              label: 'Edit agent…',
              icon: YsIcon.pencil,
              onSelected: edit,
            ),
          ],
          builder: (context, menu) => YsPressable(
            semanticLabel: 'Switch agent: $name',
            onPressed: menu.open,
            builder: (context, state) => YsFocusRing(
              visible: state.focused,
              radius: subtitle == null ? YsRadius.pill : YsRadius.navRow,
              child: subtitle == null
                  ? _pill(context, state, agent, status ?? 'AGENT · $name')
                  : _title(context, state, status ?? name, subtitle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    YsPressableState state,
    AgentProfile? agent,
    String label,
  ) {
    final palette = YsTheme.of(context);
    return YsGlass(
      highlighted: state.hovered || state.pressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          YsSpace.xs,
          YsSpace.xs,
          YsSpace.md,
          YsSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YsAvatar(
              AssetImage(
                'assets/images/${agent?.avatar.assetPath ?? AgentAvatar.byId(null).assetPath}',
              ),
              size: 28,
            ),
            const SizedBox(width: YsSpace.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YsType.caption.flutter.copyWith(
                  color: palette.contentColor,
                ),
              ),
            ),
            const SizedBox(width: YsSpace.xs),
            const YsIconWidget(YsIcon.chevronDown, size: YsLayout.inlineIcon),
          ],
        ),
      ),
    );
  }

  Widget _title(
    BuildContext context,
    YsPressableState state,
    String label,
    String subtitle,
  ) {
    final palette = YsTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: YsMotion.fast),
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.sm,
        vertical: YsSpace.xxs,
      ),
      decoration: BoxDecoration(
        color: state.hovered || state.pressed
            ? palette.neutralWashColor
            : const Color(0x00000000),
        borderRadius: BorderRadius.circular(YsRadius.navRow),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: YsType.heading.flutter.copyWith(
                    color: _error != null
                        ? palette.errorColor
                        : palette.contentColor,
                  ),
                ),
              ),
              const SizedBox(width: YsSpace.xxs),
              YsIconWidget(
                YsIcon.chevronDown,
                size: YsLayout.inlineIcon,
                color: palette.contentMutedColor,
              ),
            ],
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

final class _AgentEditor extends ConsumerStatefulWidget {
  const _AgentEditor({
    required this.instanceId,
    required this.profile,
    required this.onClose,
  });

  final String instanceId;
  final String? profile;
  final VoidCallback onClose;

  @override
  ConsumerState<_AgentEditor> createState() => _AgentEditorState();
}

final class _AgentEditorState extends ConsumerState<_AgentEditor> {
  final _name = TextEditingController();
  final _prompt = TextEditingController();
  AgentProfile? _agent;
  String _avatarId = 'noah';
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.profile == null) {
      final avatar = AgentAvatar.byId(_avatarId);
      _name.text = avatar.name;
      _prompt.text = avatar.defaultPrompt;
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agents = await ref.read(
        agentProfilesProvider(widget.instanceId).future,
      );
      final agent = agents.firstWhere((item) => item.profile == widget.profile);
      final details = await ref.read(
        agentDetailsProvider(widget.instanceId, agent.profile).future,
      );
      if (!mounted) return;
      _name.text = agent.displayName;
      _prompt.text = details.prompt;
      setState(() {
        _agent = agent;
        _avatarId = agent.avatarId;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter an agent name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier = ref.read(
        agentProfilesProvider(widget.instanceId).notifier,
      );
      if (_agent case final agent?) {
        await notifier.saveAgent(
          agent: agent,
          name: _name.text.trim(),
          avatarId: _avatarId,
          prompt: _prompt.text,
        );
      } else {
        _agent = await notifier.create(
          name: _name.text.trim(),
          avatarId: _avatarId,
          prompt: _prompt.text,
        );
      }
      if (widget.profile == null && mounted) {
        await ref
            .read(activeThreadProvider.notifier)
            .openAgent(widget.instanceId, _agent!.profile);
      }
      if (mounted) widget.onClose();
    } catch (error) {
      if (error is AgentWriteException && error.createdAgent != null) {
        _agent = error.createdAgent;
      }
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _selectAvatar(AgentAvatar avatar) {
    final previous = AgentAvatar.byId(_avatarId);
    setState(() {
      _avatarId = avatar.id;
      // Templates only seed new agents; changing an existing avatar never
      // replaces that agent's independent SOUL or display name.
      if (widget.profile == null) {
        if (_name.text == previous.name) _name.text = avatar.name;
        if (_prompt.text == previous.defaultPrompt) {
          _prompt.text = avatar.defaultPrompt;
        }
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final ready = !_loading && (widget.profile == null || _agent != null);
    return YsDialog(
      title: widget.profile == null ? 'Create agent' : 'Edit agent',
      onClose: _saving ? () {} : widget.onClose,
      actions: [
        YsButton.neutral(
          label: 'Cancel',
          onPressed: _saving ? null : widget.onClose,
        ),
        YsButton.primary(
          label: _saving ? 'Saving…' : 'Save agent',
          onPressed: ready && !_saving ? () => unawaited(_save()) : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading) const Text('Loading agent prompt…'),
          if (_error case final error?) YsDialogError(error),
          if (!ready && !_loading)
            YsButton.neutral(
              label: 'Retry loading agent',
              onPressed: () => unawaited(_load()),
            ),
          if (ready)
            ExcludeFocus(
              excluding: _saving,
              child: AbsorbPointer(
                absorbing: _saving,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YsInputBox(
                      controller: _name,
                      semanticLabel: 'Agent name',
                      placeholder: 'Agent name',
                      autofocus: true,
                    ),
                    const SizedBox(height: YsSpace.lg),
                    Wrap(
                      spacing: YsSpace.sm,
                      runSpacing: YsSpace.sm,
                      children: [
                        for (final avatar in AgentAvatar.available)
                          YsPressable(
                            semanticLabel:
                                '${avatar.name} avatar${avatar.id == _avatarId ? ', selected' : ''}',
                            onPressed: () => _selectAvatar(avatar),
                            builder: (context, state) => YsFocusRing(
                              visible: state.focused,
                              radius: YsRadius.navRow,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: avatar.id == _avatarId
                                        ? palette.contentColor
                                        : palette.lineColor,
                                    width: ysHairline,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    YsRadius.navRow,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(YsSpace.xs),
                                  child: YsAvatar(
                                    AssetImage(
                                      'assets/images/${avatar.assetPath}',
                                    ),
                                    size: 48,
                                    semanticLabel: avatar.name,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: YsSpace.lg),
                    Text(
                      'SOUL prompt',
                      style: YsType.body.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                    ),
                    const SizedBox(height: YsSpace.sm),
                    YsTextArea(
                      controller: _prompt,
                      semanticLabel: 'Independent agent SOUL prompt',
                      minLines: 5,
                      maxLines: 8,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: YsSpace.sm),
                    Text(
                      'Applies to new conversations. This prompt belongs only to this agent. Shift+Enter adds a new line.',
                      style: YsType.caption.flutter.copyWith(
                        color: palette.contentMutedColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
