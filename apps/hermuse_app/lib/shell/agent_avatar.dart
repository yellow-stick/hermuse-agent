import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart' show HermesException;
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Bundled stand-in shown while a generated portrait loads, or when the
/// agent has none.
final customAvatarStandIn = AssetImage(
  'assets/images/${AgentAvatar.custom.assetPath}',
);

/// What a failed avatar or media action says: the server's reason, never
/// a raw exception.
String avatarErrorText(Object error) => switch (error) {
  final HermesException e => hermesReason(e),
  ArgumentError(:final message) => '$message',
  StateError(:final message) => message,
  _ => '$error',
};

/// The picture of a generated avatar, for owners that hand an
/// [ImageProvider] down (shell → panel, thread header): the state clip of
/// the chat when motion is allowed, else the portrait. The last loaded image
/// stays until the next one has arrived, so state changes never flash.
final class CustomAvatarImage {
  CustomAvatarImage(this._changed);

  /// Rebuilds the owner once a new image is in.
  final VoidCallback _changed;

  (String, String)? _owner;
  Object? _key;
  ImageProvider? _image;
  bool _disposed = false;

  void dispose() => _disposed = true;

  /// Watches [profile]'s avatar from the owner's `build`.
  ImageProvider resolve(
    WidgetRef ref, {
    required String instanceId,
    required String profile,
    ChatState? chat,
    bool animate = false,
  }) {
    final provider = agentAvatarProvider(instanceId, profile: profile);
    final avatar = ref.watch(provider).value;
    if (_owner != (instanceId, profile)) {
      _owner = (instanceId, profile);
      _key = null;
      _image = null;
    }
    if (avatar == null || !avatar.hasPortrait) {
      _key = null;
      _image = null;
      return customAvatarStandIn;
    }
    final state = customAvatarState(
      avatar.states.keys,
      chat: chat,
      animate: animate,
    );
    final key = (
      state,
      avatar.updatedAt,
      avatar.portraitUrl,
      state == null ? null : avatar.states[state],
    );
    if (key != _key) {
      _key = key;
      unawaited(_load(ref.read(provider.notifier), state, key));
    }
    return _image ?? customAvatarStandIn;
  }

  Future<void> _load(
    AgentAvatarState notifier,
    String? state,
    Object key,
  ) async {
    Uint8List bytes;
    try {
      bytes = await notifier.imageBytes(state);
    } on Object {
      // A clip that does not load falls back to the portrait; no portrait
      // keeps what is on screen.
      if (state == null) return;
      try {
        bytes = await notifier.portraitBytes();
      } on Object {
        return;
      }
    }
    if (_disposed || _key != key) return;
    final image = MemoryImage(bytes);
    if (image == _image) return;
    _image = image;
    _changed();
  }
}

/// An agent's avatar: the bundled portrait, or the generated one (animated
/// with [chat]'s state when motion is allowed).
final class AgentPortrait extends ConsumerStatefulWidget {
  const AgentPortrait({
    required this.instanceId,
    required this.profile,
    required this.avatarId,
    required this.size,
    this.chat,
    this.semanticLabel,
    super.key,
  });

  final String instanceId;
  final String profile;
  final String avatarId;
  final double size;

  /// Chat whose state picks the clip; null shows the still portrait.
  final ChatState? chat;
  final String? semanticLabel;

  @override
  ConsumerState<AgentPortrait> createState() => _AgentPortraitState();
}

final class _AgentPortraitState extends ConsumerState<AgentPortrait> {
  late final _custom = CustomAvatarImage(() {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatar = AgentAvatar.byId(widget.avatarId);
    final image = avatar.isCustom
        ? _custom.resolve(
            ref,
            instanceId: widget.instanceId,
            profile: widget.profile,
            chat: widget.chat,
            animate: !MediaQuery.disableAnimationsOf(context),
          )
        : AssetImage('assets/images/${avatar.assetPath}');
    return YsAvatar(
      image,
      size: widget.size,
      semanticLabel: widget.semanticLabel,
    );
  }
}

/// The agent editor's Generate view: description → portrait candidates →
/// pick → Animate with its cost and per-state progress.
final class AvatarGenerator extends ConsumerStatefulWidget {
  const AvatarGenerator({
    required this.instanceId,
    required this.profile,
    required this.ensureProfile,
    required this.onPicked,
    this.onOpenSettings,
    super.key,
  });

  final String instanceId;

  /// The agent's profile; null while a new agent is not created yet.
  final String? profile;

  /// Creates the new agent (generation is per profile); null when it could
  /// not be created (the editor says why).
  final Future<String?> Function() ensureProfile;

  /// Saves the agent with its generated portrait once a candidate is picked.
  final Future<void> Function() onPicked;

  /// Opens Settings → Image generation; null hides the button.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<AvatarGenerator> createState() => _AvatarGeneratorState();
}

final class _AvatarGeneratorState extends ConsumerState<AvatarGenerator> {
  final _description = TextEditingController();
  String? _busy;
  String? _error;
  int? _picked;

  /// Keeps a just-created profile's avatar (and its polling) alive until
  /// this view watches it.
  ProviderSubscription<AsyncValue<Avatar>>? _keep;

  @override
  void dispose() {
    _keep?.close();
    _description.dispose();
    super.dispose();
  }

  AgentAvatarStateProvider _provider(String profile) =>
      agentAvatarProvider(widget.instanceId, profile: profile);

  Future<void> _run(String action, Future<void> Function() body) async {
    setState(() {
      _busy = action;
      _error = null;
    });
    try {
      await body();
    } on Object catch (error) {
      if (mounted) setState(() => _error = avatarErrorText(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _generate() => _run('generate', () async {
    final description = _description.text.trim();
    final profile = widget.profile ?? await widget.ensureProfile();
    if (profile == null || !mounted) return;
    _keep?.close();
    _keep = ref.listenManual(_provider(profile), (_, _) {});
    await ref.read(_provider(profile).notifier).generatePortraits(description);
    if (mounted) setState(() => _picked = null);
  });

  Future<void> _pick(String profile, int candidate) => _run('pick', () async {
    await ref.read(_provider(profile).notifier).select(candidate);
    if (mounted) setState(() => _picked = candidate);
    await widget.onPicked();
  });

  Future<void> _animate(String profile, List<String>? states) =>
      _run('animate', () async {
        await ref.read(_provider(profile).notifier).animate(states: states);
      });

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final muted = YsType.body.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    final errorStyle = YsType.body.flutter.copyWith(color: palette.errorColor);
    final config = ref.watch(mediaConfigProvider(widget.instanceId));
    final status = ref.watch(mediaStatusProvider(widget.instanceId)).value;
    final configValue = config.value;
    if (configValue == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.hasError) ...[
            Text(avatarErrorText(config.error!), style: errorStyle),
            const SizedBox(height: YsSpace.sm),
            YsButton.neutral(
              label: 'Try again',
              onPressed: () =>
                  ref.invalidate(mediaConfigProvider(widget.instanceId)),
            ),
          ] else
            Text('Checking the image service…', style: muted),
        ],
      );
    }
    if (!configValue.configured || status?.configured == false) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Portrait generation needs an image service. Set it up in '
            'Settings → Image generation.',
            style: muted,
          ),
          if (widget.onOpenSettings case final open?) ...[
            const SizedBox(height: YsSpace.sm),
            YsButton.neutral(
              label: 'Open Settings',
              icon: YsIcon.menu,
              onPressed: open,
            ),
          ],
        ],
      );
    }
    final profile = widget.profile;
    final value = profile == null ? null : ref.watch(_provider(profile));
    final avatar = value?.value;
    final job = avatar?.job;
    final running = job?.running ?? false;
    final generating =
        _busy == 'generate' || (job?.kind == AvatarJobKind.portrait && running);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsField(
          label: 'Describe your agent',
          child: YsTextArea(
            controller: _description,
            semanticLabel: 'Describe your agent',
            placeholder:
                'A cheerful plush fox with round glasses and a green scarf',
            minLines: 2,
            maxLines: 4,
            textInputAction: TextInputAction.newline,
            enterSubmits: false,
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: YsSpace.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: YsButton.neutral(
            label: generating ? 'Generating…' : 'Generate portraits',
            icon: YsIcon.sparkles,
            onPressed:
                _busy != null || running || _description.text.trim().isEmpty
                ? null
                : () => unawaited(_generate()),
          ),
        ),
        if (value != null && value.hasError && avatar == null) ...[
          const SizedBox(height: YsSpace.sm),
          Text(avatarErrorText(value.error!), style: errorStyle),
        ],
        if (job != null && job.kind == AvatarJobKind.portrait) ...[
          const SizedBox(height: YsSpace.md),
          if (job.running)
            _Progress('Generating portraits… this takes about 15 seconds.')
          else if (job.status == AvatarJobStatus.failed)
            Text(job.error ?? 'Portrait generation failed.', style: errorStyle)
          else if (job.candidates.isNotEmpty && profile != null) ...[
            Text(
              'Pick a portrait',
              style: YsType.label.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
            const SizedBox(height: YsSpace.sm),
            _Candidates(
              notifier: ref.read(_provider(profile).notifier),
              urls: job.candidates,
              picked: _picked,
              onPick: _busy != null || running
                  ? null
                  : (i) => unawaited(_pick(profile, i)),
            ),
          ],
        ],
        if (avatar != null && avatar.hasPortrait && profile != null)
          ..._animation(context, profile, avatar, status),
        if (_error case final error?) ...[
          const SizedBox(height: YsSpace.sm),
          Text(error, style: errorStyle),
        ] else if (value != null && value.hasError && avatar != null) ...[
          // A failed poll: the last state stays, polling goes on.
          const SizedBox(height: YsSpace.sm),
          Text(avatarErrorText(value.error!), style: errorStyle),
        ],
      ],
    );
  }

  List<Widget> _animation(
    BuildContext context,
    String profile,
    Avatar avatar,
    MediaStatus? status,
  ) {
    final palette = YsTheme.of(context);
    final job = avatar.job;
    final running = job?.running ?? false;
    final animation = job?.kind == AvatarJobKind.animate ? job : null;
    final failed = <String>[
      for (final MapEntry(:key, :value)
          in animation?.states.entries ??
              const <MapEntry<String, AvatarStateStatus>>[])
        if (value == AvatarStateStatus.failed) key,
    ];
    final missing = [
      for (final state in customAvatarStates)
        if (!avatar.states.containsKey(state)) state,
    ];
    final (String label, List<String>? states) = animation != null && running
        // The run in progress: its own clips and price.
        ? ('Animate', animation.states.keys.toList())
        : !running && failed.isNotEmpty
        ? ('Retry failed', failed)
        : missing.isEmpty
        ? ('Animate again', null)
        : (
            'Animate',
            missing.length == customAvatarStates.length ? null : missing,
          );
    final target = states ?? customAvatarStates;
    return [
      const SizedBox(height: YsSpace.lg),
      Row(
        children: [
          AgentPortrait(
            instanceId: widget.instanceId,
            profile: profile,
            avatarId: AgentAvatar.customId,
            size: 56,
            semanticLabel: 'Generated portrait',
          ),
          const SizedBox(width: YsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YsButton.neutral(
                  label: label,
                  icon: YsIcon.play,
                  onPressed: _busy != null || running
                      ? null
                      : () => unawaited(_animate(profile, states)),
                ),
                const SizedBox(height: YsSpace.xs),
                Text(
                  animationCostLine(target, status),
                  style: YsType.caption.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (animation != null) ...[
        const SizedBox(height: YsSpace.md),
        for (final MapEntry(:key, :value) in animation.states.entries)
          _StateRow(state: key, status: value),
        if (animation.status == AvatarJobStatus.failed &&
            animation.error != null) ...[
          const SizedBox(height: YsSpace.xs),
          Text(
            animation.error!,
            style: YsType.body.flutter.copyWith(color: palette.errorColor),
          ),
        ],
        if (animation.running) ...[
          const SizedBox(height: YsSpace.sm),
          Text(
            'You can save the agent now; the animations keep going on the '
            'server.',
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ],
    ];
  }
}

final class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Row(
      children: [
        const YsSpinner(),
        const SizedBox(width: YsSpace.sm),
        Expanded(
          child: Text(
            label,
            style: YsType.body.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Portrait candidates, four to a row, cropped square like the portrait.
final class _Candidates extends StatelessWidget {
  const _Candidates({
    required this.notifier,
    required this.urls,
    required this.picked,
    required this.onPick,
  });

  final AgentAvatarState notifier;
  final List<String> urls;
  final int? picked;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const columns = 4;
      final side =
          (constraints.maxWidth - YsSpace.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: YsSpace.sm,
        runSpacing: YsSpace.sm,
        children: [
          for (var i = 0; i < urls.length; i++)
            _Candidate(
              bytes: notifier.candidateBytes(urls[i]),
              index: i,
              side: side,
              selected: picked == i,
              onPressed: onPick == null ? null : () => onPick!(i),
            ),
        ],
      );
    },
  );
}

final class _Candidate extends StatelessWidget {
  const _Candidate({
    required this.bytes,
    required this.index,
    required this.side,
    required this.selected,
    required this.onPressed,
  });

  final Future<Uint8List> bytes;
  final int index;
  final double side;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      semanticLabel: 'Portrait ${index + 1}${selected ? ', selected' : ''}',
      onPressed: onPressed,
      builder: (context, state) => YsFocusRing(
        visible: state.focused,
        radius: YsRadius.navRow,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: palette.avatarSurfaceColor,
            borderRadius: BorderRadius.circular(YsRadius.navRow),
            border: Border.all(
              color: selected
                  ? palette.contentColor
                  : state.hovered
                  ? palette.contentSubtleColor
                  : palette.lineColor,
              width: selected ? ysHairline * 2 : ysHairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: FutureBuilder<Uint8List>(
            future: bytes,
            builder: (context, snapshot) => switch (snapshot) {
              AsyncSnapshot(:final data?) => Image.memory(
                data,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
              ),
              AsyncSnapshot(hasError: true) => Center(
                child: YsIconWidget(
                  YsIcon.xCircle,
                  size: YsLayout.inlineIcon,
                  color: palette.errorColor,
                ),
              ),
              _ => const Center(child: YsSpinner()),
            },
          ),
        ),
      ),
    );
  }
}

/// One clip of an animation run: name and where it is.
final class _StateRow extends StatelessWidget {
  const _StateRow({required this.state, required this.status});

  final String state;
  final AvatarStateStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final name = state.isEmpty
        ? state
        : '${state[0].toUpperCase()}${state.substring(1)}';
    final (label, color) = switch (status) {
      AvatarStateStatus.queued => ('Queued', palette.contentMutedColor),
      AvatarStateStatus.running => ('Generating…', palette.contentColor),
      AvatarStateStatus.done => ('Done', palette.successColor),
      AvatarStateStatus.failed => ('Failed', palette.errorColor),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: YsSpace.xxs),
      child: Row(
        children: [
          SizedBox.square(
            dimension: YsLayout.inlineIcon,
            child: switch (status) {
              AvatarStateStatus.running => const YsSpinner(),
              AvatarStateStatus.done => YsIconWidget(
                YsIcon.checkCircle,
                size: YsLayout.inlineIcon,
                color: color,
              ),
              AvatarStateStatus.failed => YsIconWidget(
                YsIcon.xCircle,
                size: YsLayout.inlineIcon,
                color: color,
              ),
              AvatarStateStatus.queued => YsIconWidget(
                YsIcon.upcoming,
                size: YsLayout.inlineIcon,
                color: color,
              ),
            },
          ),
          const SizedBox(width: YsSpace.sm),
          Expanded(child: Text(name, style: YsType.body.flutter)),
          Text(label, style: YsType.caption.flutter.copyWith(color: color)),
        ],
      ),
    );
  }
}
