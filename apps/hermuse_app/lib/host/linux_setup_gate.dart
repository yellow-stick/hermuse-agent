import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/screens.dart';
import 'install_flow.dart';
import 'linux_setup.dart';

/// The Linux setup assistant on screen: what this computer still needs and
/// why, one "Prepare" for all of it, the progress of every step, and each
/// incomplete or blocked state with its retry.
final class LinuxSetupGate extends ConsumerWidget {
  const LinuxSetupGate({required this.canLeave, super.key});

  /// Whether Cancel may leave the assistant; false while registered
  /// instances wait for a working keyring.
  final bool canLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(linuxSetupProvider);
    final controller = ref.read(linuxSetupProvider.notifier);
    final palette = YsTheme.of(context);
    final phase = setup.phase;
    final userGoal = switch (setup.goal) {
      LinuxSetupGoal.connect ||
      LinuxSetupGoal.local ||
      LinuxSetupGoal.computer => true,
      LinuxSetupGoal.reopen || null => false,
    };
    final busy = switch (phase) {
      SetupIdle() ||
      SetupWorking() ||
      SetupApplying() ||
      SetupInstalling() ||
      SetupComputer() => true,
      _ => false,
    };
    final leave = canLeave
        ? YsButton.neutral(label: 'Cancel', onPressed: controller.cancel)
        : null;
    final checkAgain = YsButton.neutral(
      label: 'Check again',
      onPressed: controller.checkAgain,
    );
    // Neutral buttons only: the release smoke finds these labels by OCR,
    // which misses text on the filled accent button.
    final actions = <Widget>[
      if (busy) ...[
        if (userGoal)
          YsButton.neutral(
            label: 'Cancel',
            onPressed: setup.stopping ? null : controller.cancel,
          ),
      ] else ...[
        if (phase case SetupReview(:final steps) when steps.isNotEmpty)
          YsButton.neutral(label: 'Prepare', onPressed: controller.authorize),
        if (phase case SetupReview(offersLocalDockerEngine: true))
          YsButton.neutral(
            label: "Use this computer's Docker",
            onPressed: controller.useLocalDockerEngine,
          ),
        if (phase case SetupInstallFailed(stage: _?))
          YsButton.neutral(
            label: 'Retry this stage',
            onPressed: controller.retryStage,
          ),
        checkAgain,
        ?leave,
      ],
    ];
    return ColoredBox(
      color: palette.canvasColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: YsDialogCard(
          children: [
            YsDialogTitle(switch (phase) {
              SetupInstalling() || SetupInstallFailed() => 'Install Hermes',
              SetupComputer() => "Prepare the agent's computer",
              _ => 'Prepare this computer',
            }),
            ..._body(palette, setup),
            if (setup.stopping)
              _Line(
                'Finishing the current step before stopping…',
                color: palette.contentMutedColor,
              ),
            // One button per row: each label stays on its own line.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  actions[i],
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(YsPalette palette, LinuxSetupState setup) {
    final muted = palette.contentMutedColor;
    final error = palette.errorColor;
    return switch (setup.phase) {
      SetupIdle() => [const _Working('Checking this computer…')],
      SetupWorking(:final message) => [_Working(message)],
      SetupReview(
        :final plan,
        :final steps,
        :final blockers,
        :final keyring,
        :final lastRun,
      ) =>
        [
          if (lastRun != null) ...[
            _Line(_outcome(lastRun), color: error),
            if (lastRun.completed case final completed
                when completed.isNotEmpty)
              _Line(
                'Already done: ${completed.map(_stepName).join(', ')}.',
                color: muted,
              ),
          ],
          if (keyring != null)
            _Line(
              keyring.locked
                  ? 'Your system keyring is locked. Unlock it when your '
                        'system asks, then choose Check again. Hermuse Agent '
                        'stores nothing until it works.'
                  : 'The system keyring does not work yet: ${keyring.detail}. '
                        'Hermuse Agent keeps credentials only there, never '
                        'in plain text.',
              color: error,
            ),
          if (steps.isNotEmpty) ...[
            _Line(
              plan!.needsAuthorization
                  ? 'Hermuse Agent needs these changes on this computer. '
                        'Your system asks once for an administrator '
                        'password to make them.'
                  : 'Hermuse Agent needs these changes on this computer.',
              color: muted,
            ),
            _PlannedSteps(steps: steps),
          ],
          for (final blocker in blockers) _Blocker(blocker),
          if (setup.log.isNotEmpty && lastRun != null)
            InstallLogBox(log: setup.log),
        ],
      SetupApplying(:final plan, :final outcomes, :final running) => [
        _Working(
          running == LinuxDependencyStep.authorization
              ? 'Waiting for the administrator authorization…'
              : 'Preparing this computer…',
        ),
        _PlannedSteps(steps: plan.steps, outcomes: outcomes, running: running),
        if (setup.log.isNotEmpty) InstallLogBox(log: setup.log),
      ],
      SetupInstalling(:final manifest, :final done, :final running) => [
        _Line('Step ${done.length} of ${manifest.stages.length}', color: muted),
        InstallProgressBar(
          value: manifest.stages.isEmpty
              ? 1
              : done.length / manifest.stages.length,
        ),
        InstallStageList(manifest: manifest, done: done, running: running),
        if (setup.log.isNotEmpty) InstallLogBox(log: setup.log),
      ],
      SetupInstallFailed(
        :final message,
        :final manifest,
        :final done,
        :final stage,
      ) =>
        [
          _Line(message, color: error),
          if (stage != null)
            _Line(
              'Stage "$stage" failed; fix the cause, then retry just this '
              'stage.',
              color: muted,
            ),
          if (setup.log.isNotEmpty) InstallLogBox(log: setup.log),
          if (manifest != null)
            InstallStageList(manifest: manifest, done: done, running: null),
        ],
      SetupHermesKept(:final message, :final found) => [
        _Line(message, color: error),
        if (found != null)
          _Line(
            'Update or remove it yourself, then choose Check again.',
            color: muted,
          ),
      ],
      SetupComputer(:final status) => [_Working(_computerText(status))],
      SetupFailed(:final message) => [
        _Line(message, color: error),
        if (setup.log.isNotEmpty) InstallLogBox(log: setup.log),
      ],
      SetupStopped() => [
        _Line(
          'Stopped before the next step. Choose Check again to continue.',
          color: muted,
        ),
      ],
      SetupFinished() => [const _Working('Ready.')],
    };
  }

  static String _outcome(LinuxApplyReport report) {
    if (report.detail.isNotEmpty) return report.detail;
    return switch (report.outcome) {
      LinuxApplyOutcome.dismissed =>
        'The administrator authorization was dismissed.',
      LinuxApplyOutcome.denied =>
        'The administrator authorization was refused.',
      LinuxApplyOutcome.cancelled => 'Stopped before the next step.',
      LinuxApplyOutcome.failed => 'A step failed.',
      LinuxApplyOutcome.incomplete ||
      LinuxApplyOutcome.ready => 'Some preparation is still missing.',
    };
  }

  static String _computerText(ComputerStatus? status) => switch (status) {
    ComputerStatus(state: ComputerState.building, :final detail)
        when detail.isNotEmpty =>
      detail,
    ComputerStatus(state: ComputerState.stopped) =>
      "Starting the agent's computer…",
    ComputerStatus(state: ComputerState.running) =>
      "Checking the agent's screen…",
    _ => "Preparing the agent's computer…",
  };
}

/// Short name of a step, for "Already done".
String _stepName(LinuxDependencyStep step) => switch (step) {
  LinuxDependencyStep.authorization => 'authorization',
  LinuxDependencyStep.hermesTools => 'Hermes Agent build tools',
  LinuxDependencyStep.secretService => 'system keyring',
  LinuxDependencyStep.dockerInstall => 'Docker',
  LinuxDependencyStep.dockerStart => 'Docker service start',
  LinuxDependencyStep.dockerGroup => 'docker group membership',
  LinuxDependencyStep.activateSecretService => 'keyring service start',
  LinuxDependencyStep.startRootlessDocker => 'rootless Docker start',
};

final class _Working extends StatelessWidget {
  const _Working(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const YsSpinner(size: 16),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            message,
            style: YsType.body.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

final class _Line extends StatelessWidget {
  const _Line(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: YsType.body.flutter.copyWith(color: color),
    textAlign: TextAlign.center,
  );
}

final class _Blocker extends StatelessWidget {
  const _Blocker(this.blocker);

  final LinuxBlocker blocker;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          blocker.explanation,
          style: YsType.body.flutter.copyWith(color: palette.errorColor),
          textAlign: TextAlign.center,
        ),
        for (final detail in blocker.details)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              detail,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Planned steps with what each does, its consent warning, and, while they
/// run, their state.
final class _PlannedSteps extends StatelessWidget {
  const _PlannedSteps({
    required this.steps,
    this.outcomes = const {},
    this.running,
  });

  final List<LinuxPlannedStep> steps;
  final Map<LinuxDependencyStep, LinuxStepOutcome> outcomes;
  final LinuxDependencyStep? running;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final progress = running != null || outcomes.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final planned in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(child: _icon(palette, planned.step)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        planned.explanation,
                        style: YsType.label.flutter.copyWith(
                          color: palette.contentColor,
                        ),
                      ),
                      if (planned.warning case final warning?) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Root access',
                          style: YsType.caption.flutter.copyWith(
                            color: palette.errorColor,
                          ),
                        ),
                        Text(
                          warning,
                          style: YsType.small.flutter.copyWith(
                            color: palette.errorColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress) ...[
                  const SizedBox(width: 12),
                  Text(
                    _state(planned.step),
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _state(LinuxDependencyStep step) {
    if (step == running) return 'Running…';
    return switch (outcomes[step]) {
      null => 'Waiting',
      LinuxStepOutcome.done => 'Done',
      LinuxStepOutcome.skipped => 'Already done',
      LinuxStepOutcome.failed => 'Failed',
      LinuxStepOutcome.dismissed => 'Dismissed',
      LinuxStepOutcome.denied => 'Refused',
    };
  }

  Widget _icon(YsPalette palette, LinuxDependencyStep step) {
    if (step == running) return const YsSpinner(size: 14);
    return switch (outcomes[step]) {
      LinuxStepOutcome.done || LinuxStepOutcome.skipped => YsIconWidget(
        YsIcon.check,
        size: 14,
        color: palette.successColor,
      ),
      LinuxStepOutcome.failed ||
      LinuxStepOutcome.dismissed ||
      LinuxStepOutcome.denied => YsIconWidget(
        YsIcon.close,
        size: 14,
        color: palette.errorColor,
      ),
      null => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.lineColor, width: ysHairline),
        ),
        child: const SizedBox(width: 14, height: 14),
      ),
    };
  }
}
