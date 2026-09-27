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
    super.key,
  });

  final HermesInstance instance;
  final ValueChanged<ThreadRef> onDone;
  final VoidCallback onSkipToChat;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

final class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  @override
  Widget build(BuildContext context) {
    final onboarding = ref.watch(onboardingProvider(widget.instance.id));
    final state = onboarding.value;
    if (onboarding.isLoading && state == null) {
      return const YsDialogCard(
        narrow: true,
        children: [YsDialogBody('Checking this Hermes…')],
      );
    }
    if (state == null) {
      return YsDialogCard(
        narrow: true,
        children: [
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
              YsButton.primary(
                label: 'Retry',
                onPressed: () => unawaited(
                  ref
                      .read(onboardingProvider(widget.instance.id).notifier)
                      .refresh(),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return switch (state.step) {
      OnboardingStep.runtimeCheck => _RuntimeCheck(
        instanceId: widget.instance.id,
        state: state,
        onSkipToChat: widget.onSkipToChat,
      ),
      OnboardingStep.connections => ConnectionsScreen(
        instance: widget.instance,
        onBack: widget.onSkipToChat,
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
    };
  }
}

/// Step dots shared by the onboarding steps.
final class _StepDots extends StatelessWidget {
  const _StepDots(this.step);

  final OnboardingStep step;

  static const _order = [
    OnboardingStep.runtimeCheck,
    OnboardingStep.connections,
    OnboardingStep.defaultModel,
    OnboardingStep.profile,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final index = _order.indexOf(step);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _order.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          SizedBox(
            width: 8,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < index
                    ? palette.successColor
                    : i == index
                    ? palette.primaryColor
                    : palette.contentSubtleColor,
              ),
            ),
          ),
        ],
      ],
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
        const _StepDots(OnboardingStep.runtimeCheck),
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
            onPressed: () =>
                ref.read(onboardingProvider(widget.instanceId).notifier).skip(),
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
              const _StepDots(OnboardingStep.defaultModel),
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
                  child: YsSelect(
                    value: _provider,
                    options: [for (final p in providers) (p.slug, p.name)],
                    onChanged: (v) => setState(() {
                      _provider = v;
                      _model = '';
                    }),
                    semanticLabel: 'Provider',
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
                  label: busy ? '…' : 'Use ${tier.model}',
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
            const SizedBox(width: 12),
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
        const YsDialogIcon(YsIcon.check),
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
