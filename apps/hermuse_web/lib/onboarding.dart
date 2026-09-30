import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'connections.dart';
import 'mascot.dart';
import 'scope.dart';
import 'screens.dart';

/// Onboarding flow for one instance, driven by [onboardingProvider].
///
/// Steps: `runtimeCheck` (problems + fixes) → `connections` (the Connections
/// page inline) → `defaultModel` (free-tier shortcut + picker) → `profile`
/// (guided presentation chat) → `ready`. [onDone] receives the setup
/// conversation to open, or null for the instance's main chat.
class HermuseOnboarding extends StatelessComponent {
  const HermuseOnboarding({
    required this.instance,
    required this.onDone,
    required this.onSkipToChat,
    super.key,
  });

  final HermesInstance instance;
  final ValueChanged<ThreadRef?> onDone;
  final VoidCallback onSkipToChat;

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: onboardingProvider(instance.id),
    builder: (context, onboarding) => _body(context, onboarding),
  );

  Component _body(
    BuildContext context,
    AsyncValue<OnboardingState> onboarding,
  ) {
    final state = onboarding.value;
    if (onboarding.isLoading && state == null) {
      return div(classes: 'hermuse-screen', [
        div(classes: 'hermuse-card hermuse-card-narrow', [
          HermuseCardArt(YsArt.check, busy: true),
          p(classes: 'hermuse-card-body', [.text('Checking this Hermes…')]),
        ]),
      ]);
    }
    if (state == null) {
      return div(classes: 'hermuse-screen', [
        div(classes: 'hermuse-card hermuse-card-narrow', [
          HermuseCardArt(YsArt.unreachable),
          h1(classes: 'hermuse-card-title', [.text('Setup unavailable')]),
          p(classes: 'hermuse-card-error', [.text('${onboarding.error}')]),
          div(classes: 'hermuse-card-actions', [
            YsButton.neutral(label: 'Back to chat', onPressed: onSkipToChat),
            YsButton.primary(
              label: 'Retry',
              onPressed: () => unawaited(
                context.container
                    .read(onboardingProvider(instance.id).notifier)
                    .refresh(),
              ),
            ),
          ]),
        ]),
      ]);
    }
    // Each step comes on screen with the page motion.
    return div(key: ValueKey(state.step), classes: 'hermuse-ob-page ys-enter', [
      switch (state.step) {
        OnboardingStep.runtimeCheck => _RuntimeCheck(
          instanceId: instance.id,
          state: state,
          onSkipToChat: onSkipToChat,
        ),
        OnboardingStep.connections => HermuseConnections(
          instance: instance,
          onBack: onSkipToChat,
        ),
        OnboardingStep.defaultModel => _DefaultModel(
          instanceId: instance.id,
          state: state,
          onSkipToChat: onSkipToChat,
        ),
        OnboardingStep.profile => _ProfileStep(
          instanceId: instance.id,
          state: state,
          onDone: onDone,
          onSkipToChat: onSkipToChat,
        ),
        OnboardingStep.ready => _ReadyStep(
          instanceId: instance.id,
          label: instance.label,
          state: state,
          onDone: onDone,
        ),
      },
    ]);
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseScreenStyles,
    // A step fills the shell like the screen it holds.
    css('.hermuse-ob-page').styles(
      display: .flex,
      flex: Flex(grow: 1, shrink: 1, basis: .auto),
      raw: {'min-width': '0', 'min-height': '0'},
    ),
    css('.hermuse-ob-art').styles(display: .inlineFlex),
    css(
      '.hermuse-ob-providers',
    ).styles(display: .flex, flexDirection: .column, gap: .all(YsSpace.sm.px)),
    css('.hermuse-ob-provider', [
      css('&').styles(
        width: 100.percent,
        padding: .all(YsSpace.md.px),
        border: .all(
          style: .solid,
          color: .variable('--line'),
          width: ysHairline.px,
        ),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        alignItems: .center,
        gap: .all((YsSpace.sm + YsSpace.xxs).px),
        color: .variable('--content'),
        textAlign: .left,
        backgroundColor: .variable('--neutral-ambient'),
      ),
      css('&.ys-lift').styles(
        raw: {
          'transition':
              'background-color ${YsMotion.base}ms linear, '
              'border-color ${YsMotion.base}ms linear, $ysLiftTransition',
        },
      ),
      css('&[aria-pressed="true"]').styles(
        backgroundColor: .variable('--primary-wash'),
        raw: {'border-color': 'var(--primary)'},
      ),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.hermuse-ob-provider-logo').styles(
        width: 28.px,
        height: 28.px,
        radius: .circular((YsRadius.row - 2).px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content'),
        fontSize: YsType.monogram.size.px,
        fontWeight: .w600,
        lineHeight: YsType.monogram.lineHeight.px,
        backgroundColor: .variable('--paper-clear'),
        raw: {'flex-shrink': '0'},
      ),
      css('&[aria-pressed="true"] .hermuse-ob-provider-logo').styles(
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
      ),
      css('.hermuse-ob-provider-text').styles(
        display: .flex,
        flexDirection: .column,
        flex: Flex(grow: 1, shrink: 1, basis: .zero),
        raw: {'min-width': '0'},
      ),
      css('.hermuse-ob-provider-name').styles(
        overflow: .hidden,
        fontSize: YsType.label.size.px,
        fontWeight: .w500,
        lineHeight: YsType.label.lineHeight.px,
        textOverflow: .ellipsis,
        whiteSpace: .noWrap,
      ),
      css('.hermuse-ob-provider-count').styles(
        color: .variable('--content-muted'),
        fontSize: YsType.caption.size.px,
        lineHeight: YsType.caption.lineHeight.px,
      ),
      css('.hermuse-ob-provider-tick').styles(
        display: .inlineFlex,
        opacity: 0,
        color: .variable('--primary'),
        raw: {'transition': 'opacity ${YsMotion.base}ms linear'},
      ),
      css('&[aria-pressed="true"] .hermuse-ob-provider-tick')
          .styles(opacity: 1),
    ]),
    css('.hermuse-ob-problem').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 12.px, horizontal: 14.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(4.px),
      backgroundColor: .variable('--canvas'),
    ),
    css('.hermuse-ob-problem-msg').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 22.px,
      color: .variable('--content'),
    ),
    css('.hermuse-ob-problem-hint').styles(
      margin: .zero,
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-ob-tier').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 12.px, horizontal: 14.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(8.px),
      backgroundColor: .variable('--primary-muted'),
      border: .all(style: .solid, color: .variable('--primary'), width: 1.2.px),
    ),
    css('.hermuse-ob-tier-title').styles(
      margin: .zero,
      fontSize: 15.px,
      lineHeight: 20.px,
      fontWeight: .w600,
    ),
    css('.hermuse-ob-row').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-ob-grow').styles(flex: .grow(1)),
    css('.hermuse-ob-link').styles(
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--primary-2'),
      cursor: .pointer,
      border: .none,
      backgroundColor: Colors.transparent,
    ),
  ];
}

/// Stepper shared by the onboarding steps, then the step's illustration
/// (pointing at it plays it again).
Component _stepper(OnboardingStep step, {YsArt? art}) {
  const order = [
    (OnboardingStep.runtimeCheck, YsIcon.bot, 'Check'),
    (OnboardingStep.connections, YsIcon.keyRound, 'Accounts'),
    (OnboardingStep.defaultModel, YsIcon.sparkles, 'Model'),
    (OnboardingStep.profile, YsIcon.smile, 'Tour'),
  ];
  return .fragment([
    YsStepper(
      steps: [for (final (_, icon, label) in order) (icon: icon, label: label)],
      current: order.indexWhere((entry) => entry.$1 == step),
    ),
    if (art != null)
      YsHover(
        builder: (context, hovered) => span(classes: 'hermuse-ob-art', [
          YsArtView(art, size: YsLayout.artStep, active: hovered),
        ]),
      ),
  ]);
}

/// A provider to pick, as a card: its monogram, name and model count; the
/// picked one wears the accent outline and a tick.
class _ProviderCard extends StatelessComponent {
  const _ProviderCard({
    required this.provider,
    required this.selected,
    required this.onPressed,
  });

  final ModelOptionProvider provider;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Component build(BuildContext context) {
    final name = provider.name.trim();
    final models = provider.models?.length ?? 0;
    return YsPressable(
      onPressed: onPressed,
      label: name,
      classes: 'hermuse-ob-provider ys-lift ys-press',
      attributes: {'aria-pressed': '$selected'},
      builder: (context, state) => .fragment([
        span(classes: 'hermuse-ob-provider-logo', [
          .text(name.isEmpty ? '?' : name[0].toUpperCase()),
        ]),
        span(classes: 'hermuse-ob-provider-text', [
          span(classes: 'hermuse-ob-provider-name', [.text(name)]),
          span(classes: 'hermuse-ob-provider-count', [
            .text(models == 1 ? '1 model' : '$models models'),
          ]),
        ]),
        span(classes: 'hermuse-ob-provider-tick', [
          YsIconView(YsIcon.check, size: 16),
        ]),
      ]),
    );
  }
}

/// `runtimeCheck`: strict probe problems with fix hints.
class _RuntimeCheck extends StatefulComponent {
  const _RuntimeCheck({
    required this.instanceId,
    required this.state,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final VoidCallback onSkipToChat;

  @override
  State<_RuntimeCheck> createState() => _RuntimeCheckState();
}

class _RuntimeCheckState extends State<_RuntimeCheck> {
  var _busy = false;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-screen', [
    div(classes: 'hermuse-card hermuse-card-narrow', [
      _stepper(OnboardingStep.runtimeCheck, art: YsArt.check),
      h1(classes: 'hermuse-card-title', [.text('Checking this Hermes')]),
      if (component.state.problems.isEmpty)
        p(classes: 'hermuse-card-body', [
          .text('The configured model route cannot be served yet.'),
        ])
      else
        for (final problem in component.state.problems)
          div(classes: 'hermuse-ob-problem', [
            p(classes: 'hermuse-ob-problem-msg', [.text(problem.message)]),
            if (problem.fixHint != null && problem.fixHint!.isNotEmpty)
              p(classes: 'hermuse-ob-problem-hint', [.text(problem.fixHint!)]),
          ]),
      div(classes: 'hermuse-card-actions', [
        YsButton.neutral(
          label: 'Back to chat',
          onPressed: component.onSkipToChat,
        ),
        YsButton.primary(
          label: _busy ? 'Checking…' : 'Check again',
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await context.container
                      .read(onboardingProvider(component.instanceId).notifier)
                      .refresh();
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ]),
      YsPressable(
        onPressed: () => context.container
            .read(onboardingProvider(component.instanceId).notifier)
            .skip(),
        label: 'Skip this step',
        classes: 'hermuse-ob-link',
        builder: (context, press) => span([.text('Skip for now')]),
      ),
    ]),
  ]);
}

/// `defaultModel`: free-tier shortcut, then the model picker.
class _DefaultModel extends StatefulComponent {
  const _DefaultModel({
    required this.instanceId,
    required this.state,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final VoidCallback onSkipToChat;

  @override
  State<_DefaultModel> createState() => _DefaultModelState();
}

class _DefaultModelState extends State<_DefaultModel> {
  var _busy = false;
  String? _error;
  String _provider = '';
  String _model = '';
  var _loadedOptions = false;

  Onboarding _onboarding(BuildContext context) =>
      context.container.read(onboardingProvider(component.instanceId).notifier);

  @override
  Component build(BuildContext context) {
    final state = component.state;
    final options = state.modelOptions;
    if (options == null && !_loadedOptions) {
      _loadedOptions = true;
      Future.microtask(() async {
        try {
          await _onboarding(context).loadModelOptions();
        } on Object catch (e) {
          if (mounted) setState(() => _error = '$e');
        }
      });
    }
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
    return div(classes: 'hermuse-screen', [
      div(classes: 'hermuse-card hermuse-card-narrow', [
        _stepper(OnboardingStep.defaultModel, art: YsArt.model),
        h1(classes: 'hermuse-card-title', [.text('Pick a default model')]),
        if (freeTier != null && freeTier.enabled && freeTier.available)
          div(classes: 'hermuse-ob-tier', [
            p(classes: 'hermuse-ob-tier-title', [
              .text('Start free with ${freeTier.label}'),
            ]),
            if (freeTier.noticePending)
              div(classes: 'hermuse-ob-row', [
                YsButton.neutral(
                  label: _busy ? '…' : 'Use ${freeTier.model}',
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          try {
                            await _onboarding(context).ackFreeTierNotice();
                            await _chooseFreeTier(context, freeTier);
                          } on Object catch (e) {
                            if (mounted) setState(() => _error = '$e');
                          }
                          if (mounted) setState(() => _busy = false);
                        },
                ),
              ]),
          ]),
        if (options == null)
          p(classes: 'hermuse-card-body', [.text('Loading models…')])
        else ...[
          YsField(
            label: 'Provider',
            child: div(
              classes: 'hermuse-ob-providers',
              attributes: {'role': 'group', 'aria-label': 'Provider'},
              [
                for (final provider in providers)
                  _ProviderCard(
                    provider: provider,
                    selected: provider.slug == _provider,
                    onPressed: () => setState(() {
                      _provider = provider.slug;
                      _model = '';
                    }),
                  ),
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
                label: 'Model',
              ),
            ),
        ],
        if (_error case final error?)
          p(classes: 'hermuse-card-error', [.text(error)]),
        div(classes: 'hermuse-card-actions', [
          YsButton.neutral(
            label: 'Back to chat',
            onPressed: component.onSkipToChat,
          ),
          YsButton.primary(
            label: _busy ? 'Saving…' : 'Continue',
            onPressed:
                _busy || options == null || _provider.isEmpty || _model.isEmpty
                ? null
                : () => unawaited(_choose(context, confirmExpensive: false)),
          ),
        ]),
      ]),
      if (_error != null && _error!.startsWith('EXPENSIVE:'))
        YsDialog(
          title: 'Expensive model',
          onClose: () => setState(() => _error = null),
          child: p(classes: 'hermuse-card-body', [
            .text(_error!.substring('EXPENSIVE:'.length)),
          ]),
          actions: [
            YsButton.neutral(
              label: 'Cancel',
              onPressed: () => setState(() => _error = null),
            ),
            YsButton.primary(
              label: 'Use it anyway',
              onPressed: () {
                setState(() => _error = null);
                unawaited(_choose(context, confirmExpensive: true));
              },
            ),
          ],
        ),
    ]);
  }

  Future<void> _chooseFreeTier(BuildContext context, FreeTierInfo tier) async {
    // The free tier is a providerless shortcut: the server routes the carry
    // model itself once the notice is acked; refresh to advance the step.
    await _onboarding(context).refresh();
  }

  Future<void> _choose(
    BuildContext context, {
    required bool confirmExpensive,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _onboarding(context).chooseModel(
        provider: _provider,
        model: _model,
        confirmExpensiveModel: confirmExpensive,
      );
    } on ExpensiveModelConfirmation catch (e) {
      if (mounted) setState(() => _error = 'EXPENSIVE:${e.message}');
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// `profile`: start the guided presentation conversation.
class _ProfileStep extends StatefulComponent {
  const _ProfileStep({
    required this.instanceId,
    required this.state,
    required this.onDone,
    required this.onSkipToChat,
  });

  final String instanceId;
  final OnboardingState state;
  final ValueChanged<ThreadRef?> onDone;
  final VoidCallback onSkipToChat;

  @override
  State<_ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<_ProfileStep> {
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-screen', [
    div(classes: 'hermuse-card hermuse-card-narrow', [
      _stepper(OnboardingStep.profile),
      const HermuseMascot(
        height: YsLayout.mascotSmallHeight,
        stageWidth: YsLayout.mascotSmallStageWidth,
      ),
      h1(classes: 'hermuse-card-title', [.text('Meet your Hermes')]),
      p(classes: 'hermuse-card-body', [
        .text(
          'A short guided chat presents this assistant, then learns who you '
          'are and what you want to build.',
        ),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
      div(classes: 'hermuse-card-actions', [
        YsButton.neutral(
          label: 'Skip',
          onPressed: _busy
              ? null
              : () {
                  context.container
                      .read(onboardingProvider(component.instanceId).notifier)
                      .skip();
                  component.onSkipToChat();
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
                    final thread = await context.container
                        .read(onboardingProvider(component.instanceId).notifier)
                        .startProfileConversation();
                    if (mounted) component.onDone(thread);
                  } on Object catch (e) {
                    if (mounted) setState(() => _error = '$e');
                  }
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ]),
    ]),
  ]);
}

/// Final step: one clear primary action (open the chat) and the two ways
/// back into setup as quiet links underneath.
class _ReadyStep extends StatelessComponent {
  const _ReadyStep({
    required this.instanceId,
    required this.label,
    required this.state,
    required this.onDone,
  });

  final String instanceId;
  final String label;
  final OnboardingState state;
  final ValueChanged<ThreadRef?> onDone;

  @override
  Component build(BuildContext context) {
    Onboarding notifier() =>
        context.container.read(onboardingProvider(instanceId).notifier);
    return div(classes: 'hermuse-screen', [
      div(classes: 'hermuse-card hermuse-card-narrow', [
        YsArtView(YsArt.ready, size: YsLayout.artStep),
        h1(classes: 'hermuse-card-title', [.text('All set')]),
        p(classes: 'hermuse-card-body', [.text('$label is ready to chat.')]),
        div(classes: 'hermuse-card-cta', [
          YsButton.primary(
            label: 'Open chat',
            onPressed: () => onDone(state.setupSession),
          ),
        ]),
        div(classes: 'hermuse-card-links', [
          YsPressable(
            onPressed: () => notifier().revisit(OnboardingStep.defaultModel),
            label: 'Change default model',
            classes: 'hermuse-card-link',
            builder: (context, press) => span([.text('Change default model')]),
          ),
          span(classes: 'hermuse-card-links-dot', [.text('·')]),
          YsPressable(
            onPressed: () => notifier().revisit(OnboardingStep.profile),
            label: 'Take the tour',
            classes: 'hermuse-card-link',
            builder: (context, press) => span([.text('Take the tour')]),
          ),
        ]),
      ]),
    ]);
  }
}
