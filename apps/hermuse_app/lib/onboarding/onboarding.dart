import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../product/route.dart';
import 'connections.dart';
import '../shell/mascot.dart';
import '../shell/screens.dart';

/// Onboarding flow for one instance, driven by [onboardingProvider] (web
/// `HermuseOnboarding` parity).
///
/// Steps: `runtimeCheck` (problems + fixes) → `connections` (the Connections
/// page inline) → `defaultModel` (free-tier shortcut + picker) → `profile`
/// (guided presentation chat) → `ready` (hands [ThreadRef] back to the chat).
final class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    required this.instance,
    required this.onDone,
    required this.onSkipToChat,
    this.onServerSetup,
    super.key,
  });

  final HermesInstance instance;
  final ValueChanged<ThreadRef> onDone;
  final VoidCallback onSkipToChat;

  /// Opens what is installed on the instance's server (remote only): the
  /// subscription sign-ins need its Hermuse plugin up to date.
  final VoidCallback? onServerSetup;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

final class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider(widget.instance.id));
    final state = onboarding.value;
    if (onboarding.isLoading && state == null) {
      return YsDialogCard(
        narrow: true,
        children: [
          YsDialogArt(YsArt.check, busy: true),
          const YsDialogBody('Checking this Hermes…'),
        ],
      );
    }
    if (state == null) {
      return YsDialogCard(
        narrow: true,
        children: [
          YsDialogArt(YsArt.unreachable),
          const YsDialogTitle('Setup unavailable'),
          YsDialogBody('${onboarding.error}'),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              YsButton.neutral(
                label: 'Back to chat',
                onPressed: widget.onSkipToChat,
              ),
              // The first look failed: nothing to refresh, read it anew (the
              // "Checking this Hermes…" card shows meanwhile).
              YsButton.primary(
                label: 'Retry',
                onPressed: () =>
                    ref.invalidate(onboardingProvider(widget.instance.id)),
              ),
            ],
          ),
        ],
      );
    }
    // Each step comes on screen with the page motion.
    return YsEntrance(
      key: ValueKey(state.step),
      child: switch (state.step) {
        OnboardingStep.runtimeCheck => _RuntimeCheck(
          instanceId: widget.instance.id,
          state: state,
          onSkipToChat: widget.onSkipToChat,
        ),
        OnboardingStep.connections => ConnectionsScreen(
          instance: widget.instance,
          onBack: widget.onSkipToChat,
          lead: const _StepDots(OnboardingStep.connections),
          onServerSetup: widget.onServerSetup,
        ),
        OnboardingStep.defaultModel => _DefaultModel(
          instanceId: widget.instance.id,
          state: state,
          onSkipToChat: widget.onSkipToChat,
        ),
        OnboardingStep.profile => _ProfileStep(
          instanceId: widget.instance.id,
          state: state,
          onDone: widget.onDone,
          onSkipToChat: widget.onSkipToChat,
        ),
        OnboardingStep.ready => _ReadyStep(
          instanceId: widget.instance.id,
          label: widget.instance.label,
          state: state,
          onDone: widget.onDone,
        ),
      },
    );
  }
}

/// Stepper shared by the onboarding steps, then the step's illustration.
final class _StepDots extends StatelessWidget {
  const _StepDots(this.step, {this.art});

  final OnboardingStep step;
  final YsArt? art;

  static const _order = [
    (OnboardingStep.runtimeCheck, YsIcon.bot, 'Check'),
    (OnboardingStep.connections, YsIcon.keyRound, 'Accounts'),
    (OnboardingStep.defaultModel, YsIcon.sparkles, 'Model'),
    (OnboardingStep.profile, YsIcon.smile, 'Tour'),
  ];

  @override
  Widget build(BuildContext context) {
    final art = this.art;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        YsStepper(
          steps: [
            for (final (_, icon, label) in _order) (icon: icon, label: label),
          ],
          current: _order.indexWhere((s) => s.$1 == step),
        ),
        if (art != null) ...[
          const SizedBox(height: YsSpace.lg),
          YsHover(
            builder: (context, hovered) =>
                YsArtView(art, size: YsLayout.artStep, active: hovered),
          ),
        ],
      ],
    );
  }
}

/// A provider to pick, as a card: its monogram, name and model count; the
/// picked one wears the accent outline and a tick.
final class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.selected,
    required this.onPressed,
  });

  final ModelOptionProvider provider;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final name = provider.name.trim();
    final models = provider.models?.length ?? 0;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: name,
      child: YsPressable(
        onPressed: onPressed,
        excludeSemantics: true,
        builder: (context, state) => ExcludeSemantics(
          child: YsFocusRing(
            visible: state.focused,
            radius: YsRadius.row,
            child: YsLift(
              lifted: state.hovered,
              pressed: state.pressed,
              radius: YsRadius.row,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: YsMotion.base),
                padding: const EdgeInsets.all(YsSpace.md),
                decoration: BoxDecoration(
                  color: selected
                      ? palette.primaryWashColor
                      : palette.neutralAmbientColor,
                  borderRadius: BorderRadius.circular(YsRadius.row),
                  border: Border.all(
                    color: selected ? palette.primaryColor : palette.lineColor,
                    width: ysHairline,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? palette.primaryColor
                            : palette.paperClearColor,
                        borderRadius: BorderRadius.circular(YsRadius.row - 2),
                      ),
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: YsType.monogram.flutter.copyWith(
                          color: selected
                              ? palette.primaryContentColor
                              : palette.contentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: YsSpace.sm + YsSpace.xxs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: YsType.label.flutter.copyWith(
                              color: palette.contentColor,
                            ),
                          ),
                          Text(
                            models == 1 ? '1 model' : '$models models',
                            style: YsType.caption.flutter.copyWith(
                              color: palette.contentMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: const Duration(milliseconds: YsMotion.base),
                      child: YsIconWidget(
                        YsIcon.check,
                        size: 16,
                        color: palette.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `runtimeCheck`: strict probe problems with fix hints.
final class _RuntimeCheck extends ConsumerStatefulWidget {
  const _RuntimeCheck({
    required this.instanceId,
    required this.state,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final VoidCallback onSkipToChat;

  @override
  ConsumerState<_RuntimeCheck> createState() => _RuntimeCheckState();
}

final class _RuntimeCheckState extends ConsumerState<_RuntimeCheck> {
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsDialogCard(
      narrow: true,
      children: [
        _StepDots(OnboardingStep.runtimeCheck, art: YsArt.check),
        const YsDialogTitle('Checking this Hermes'),
        if (widget.state.problems.isEmpty)
          const YsDialogBody('The configured model route cannot be served yet.')
        else
          for (final problem in widget.state.problems)
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.canvasColor,
                borderRadius: BorderRadius.circular(YsRadius.row),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      problem.message,
                      style: const YsTextStyle(
                        15,
                        22,
                      ).flutter.copyWith(color: palette.contentColor),
                    ),
                    if (problem.fixHint != null &&
                        problem.fixHint!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        problem.fixHint!,
                        style: YsType.small.flutter.copyWith(
                          color: palette.contentMutedColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            YsButton.neutral(
              label: 'Back to chat',
              onPressed: widget.onSkipToChat,
            ),
            YsButton.primary(
              label: _busy ? 'Checking…' : 'Check again',
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await ref
                          .read(onboardingProvider(widget.instanceId).notifier)
                          .refresh();
                      if (mounted) setState(() => _busy = false);
                    },
            ),
          ],
        ),
        Center(
          child: HermuseLink(
            label: 'Skip for now',
            onPressed: _busy
                ? null
                : () => ref
                      .read(onboardingProvider(widget.instanceId).notifier)
                      .skip(),
          ),
        ),
      ],
    );
  }
}

/// `defaultModel`: free-tier shortcut, then the model picker.
final class _DefaultModel extends ConsumerStatefulWidget {
  const _DefaultModel({
    required this.instanceId,
    required this.state,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final VoidCallback onSkipToChat;

  @override
  ConsumerState<_DefaultModel> createState() => _DefaultModelState();
}

final class _DefaultModelState extends ConsumerState<_DefaultModel> {
  var _busy = false;
  String? _error;

  /// Server message of a pending expensive-model confirmation.
  String? _confirm;
  String _provider = '';
  String _model = '';
  ModelOptionsResult? _options;

  Onboarding _onboarding() =>
      ref.read(onboardingProvider(widget.instanceId).notifier);

  @override
  void initState() {
    super.initState();
    _options = widget.state.modelOptions;
    if (_options == null) {
      Future.microtask(() async {
        try {
          final options = await _onboarding().loadModelOptions();
          if (mounted) setState(() => _options = options);
        } on Object catch (e) {
          if (mounted) setState(() => _error = '$e');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    _options ??= state.modelOptions;
    final options = _options;
    final providers = options?.providers ?? const <ModelOptionProvider>[];
    if (_provider.isEmpty && providers.isNotEmpty) {
      final current = providers
          .where((candidate) => candidate.isCurrent == true)
          .firstOrNull;
      _provider = (current ?? providers.first).slug;
    }
    final models =
        providers
            .where((candidate) => candidate.slug == _provider)
            .firstOrNull
            ?.models ??
        const <String>[];
    if (_model.isEmpty && models.isNotEmpty) _model = models.first;
    final freeTier = state.freeTier;
    final confirm = _confirm;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: YsDialogCard(
            narrow: true,
            children: [
              _StepDots(OnboardingStep.defaultModel, art: YsArt.model),
              const YsDialogTitle('Pick a default model'),
              if (freeTier != null && freeTier.enabled && freeTier.available)
                _FreeTierBox(
                  tier: freeTier,
                  busy: _busy,
                  onUse: () async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await _onboarding().ackFreeTierNotice();
                      await _onboarding().refresh();
                    } on Object catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                    if (mounted) setState(() => _busy = false);
                  },
                ),
              if (options == null)
                const YsDialogBody('Loading models…')
              else ...[
                YsField(
                  label: 'Provider',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, p) in providers.indexed) ...[
                        if (i > 0) const SizedBox(height: YsSpace.sm),
                        _ProviderCard(
                          provider: p,
                          selected: p.slug == _provider,
                          onPressed: () => setState(() {
                            _provider = p.slug;
                            _model = '';
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
                if (models.isNotEmpty)
                  YsField(
                    label: 'Model',
                    child: YsSelect(
                      value: _model,
                      options: [for (final m in models) (m, m)],
                      onChanged: (v) => setState(() => _model = v),
                      semanticLabel: 'Model',
                    ),
                  ),
              ],
              if (_error != null) YsDialogBody(_error!),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: YsButton.neutral(
                        label: 'Back to chat',
                        onPressed: widget.onSkipToChat,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: YsButton.primary(
                        label: _busy ? 'Saving…' : 'Continue',
                        onPressed:
                            _busy ||
                                options == null ||
                                _provider.isEmpty ||
                                _model.isEmpty
                            ? null
                            : () => unawaited(_choose(confirmExpensive: false)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (confirm != null)
          YsDialog(
            title: 'Expensive model',
            onClose: () => setState(() => _confirm = null),
            actions: [
              YsButton.neutral(
                label: 'Cancel',
                onPressed: () => setState(() => _confirm = null),
              ),
              YsButton.primary(
                label: 'Use it anyway',
                onPressed: () {
                  setState(() => _confirm = null);
                  unawaited(_choose(confirmExpensive: true));
                },
              ),
            ],
            child: Text(
              confirm,
              style: YsType.body.flutter.copyWith(
                color: YsTheme.of(context).contentMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  Future<void> _choose({required bool confirmExpensive}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _onboarding().chooseModel(
        provider: _provider,
        model: _model,
        confirmExpensiveModel: confirmExpensive,
      );
    } on ExpensiveModelConfirmation catch (e) {
      if (mounted) setState(() => _confirm = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}

final class _FreeTierBox extends StatelessWidget {
  const _FreeTierBox({
    required this.tier,
    required this.busy,
    required this.onUse,
  });

  final FreeTierInfo tier;
  final bool busy;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.primaryMutedColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
        border: Border.all(color: palette.primaryColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Start free with ${tier.label}',
              style: const YsTextStyle(
                15,
                20,
                YsWeight.semibold,
              ).flutter.copyWith(color: palette.contentColor),
            ),
            if (tier.noticePending) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: YsButton.neutral(
                  label: busy ? 'Saving…' : 'Use ${tier.model}',
                  onPressed: busy ? null : onUse,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `profile`: start the guided presentation conversation.
final class _ProfileStep extends ConsumerStatefulWidget {
  const _ProfileStep({
    required this.instanceId,
    required this.state,
    required this.onDone,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final ValueChanged<ThreadRef> onDone;
  final VoidCallback onSkipToChat;

  @override
  ConsumerState<_ProfileStep> createState() => _ProfileStepState();
}

final class _ProfileStepState extends ConsumerState<_ProfileStep> {
  var _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return YsDialogCard(
      narrow: true,
      children: [
        const _StepDots(OnboardingStep.profile),
        const Center(
          child: HermuseMascot(
            height: YsLayout.mascotSmallHeight,
            stageWidth: YsLayout.mascotSmallStageWidth,
          ),
        ),
        const YsDialogTitle('Meet your Hermes'),
        const YsDialogBody(
          'A short guided chat presents this assistant, then learns who you '
          'are and what you want to build.',
        ),
        if (_error != null) YsDialogBody(_error!),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            YsButton.neutral(
              label: 'Skip',
              onPressed: _busy
                  ? null
                  : () {
                      ref
                          .read(onboardingProvider(widget.instanceId).notifier)
                          .skip();
                      widget.onSkipToChat();
                    },
            ),
            YsButton.primary(
              label: _busy ? 'Starting…' : 'Start the tour',
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() {
                        _busy = true;
                        _error = null;
                      });
                      try {
                        final thread = await ref
                            .read(
                              onboardingProvider(widget.instanceId).notifier,
                            )
                            .startProfileConversation();
                        if (mounted) widget.onDone(thread);
                      } on Object catch (e) {
                        if (mounted) setState(() => _error = '$e');
                      }
                      if (mounted) setState(() => _busy = false);
                    },
            ),
          ],
        ),
      ],
    );
  }
}

/// Final step: one clear primary action (open the chat) and the two ways
/// back into setup as quiet links underneath.
final class _ReadyStep extends ConsumerWidget {
  const _ReadyStep({
    required this.instanceId,
    required this.label,
    required this.state,
    required this.onDone,
  });

  final String instanceId;
  final String label;
  final OnboardingState state;
  final ValueChanged<ThreadRef> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(onboardingProvider(instanceId).notifier);
    return YsDialogCard(
      narrow: true,
      children: [
        Center(child: YsArtView(YsArt.ready, size: YsLayout.artStep)),
        const YsDialogTitle('All set'),
        YsDialogBody('$label is ready to chat.'),
        YsDialogCta(
          label: 'Open chat',
          onPressed: () => onDone(
            state.setupSession ??
                ThreadRef(instanceId: instanceId, sessionId: ''),
          ),
        ),
        YsDialogLinks([
          (
            'Change default model',
            () => notifier.revisit(OnboardingStep.defaultModel),
          ),
          ('Take the tour', () => notifier.revisit(OnboardingStep.profile)),
        ]),
      ],
    );
  }
}
