import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'linux_setup.dart';
import 'setup_view.dart';

/// The Linux setup assistant on screen: [LinuxSetupView] of the running
/// [LinuxSetupController].
final class LinuxSetupGate extends ConsumerWidget {
  const LinuxSetupGate({required this.canLeave, super.key});

  /// Whether Cancel may leave the assistant; false while registered
  /// instances wait for a working keyring.
  final bool canLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LinuxSetupView(
    setup: ref.watch(linuxSetupProvider),
    controller: ref.read(linuxSetupProvider.notifier),
    canLeave: canLeave,
  );
}

/// One checklist of what this computer needs (system packages, keyring,
/// Docker, Hermes Agent, the plugin, the subscription bridge, the agent's
/// computer): each part found in place or prepared now, what needs the
/// user with its action inline, every failure with its retry, and a short
/// "ready" moment once the goal is reached. [controller] answers the
/// buttons.
final class LinuxSetupView extends StatelessWidget {
  const LinuxSetupView({
    required this.setup,
    required this.controller,
    required this.canLeave,
    super.key,
  });

  final LinuxSetupState setup;
  final LinuxSetupController controller;

  /// Whether Cancel may leave the assistant.
  final bool canLeave;

  @override
  Widget build(BuildContext context) {
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
    final checklist = _Checklist(setup, controller);
    // Neutral buttons only: the release smoke finds these labels by OCR,
    // which misses text on the filled accent button.
    final actions = <Widget>[
      if (busy) ...[
        if (userGoal)
          YsButton.neutral(
            label: 'Cancel',
            onPressed: setup.stopping ? null : controller.cancel,
          ),
      ] else if (phase is! SetupFinished) ...[
        if (!checklist.checksAgain)
          YsButton.neutral(
            label: 'Check again',
            onPressed: controller.checkAgain,
          ),
        if (canLeave)
          YsButton.neutral(label: 'Cancel', onPressed: controller.cancel),
      ],
    ];
    return ColoredBox(
      color: palette.canvasColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          vertical: YsSpace.xxl + YsSpace.lg,
          horizontal: YsSpace.xl,
        ),
        child: SetupCard(
          title: setup.showsReady
              ? 'Ready'
              : setup.goal == LinuxSetupGoal.computer
              ? "Prepare the agent's computer"
              : 'Prepare this computer',
          status: _status(setup),
          items: checklist.items,
          notices: _notices(setup),
          log: setup.log,
          actions: actions,
          onReady: setup.showsReady ? controller.acknowledge : null,
        ),
      ),
    );
  }

  /// What the assistant does now, under the title.
  static String _status(LinuxSetupState setup) => switch (setup.phase) {
    SetupIdle() => 'Checking what this computer already has…',
    SetupWorking(:final activity) => switch (activity) {
      SetupActivity.inspectingSystem =>
        'Checking what this computer already has…',
      SetupActivity.checkingKeyring => 'Checking the system keyring…',
      SetupActivity.checkingDocker =>
        "Checking Docker for the agent's computer…",
      SetupActivity.lookingForHermes => 'Looking for Hermes Agent…',
      SetupActivity.readingInstallPlan =>
        'Reading the Hermes Agent install plan…',
      SetupActivity.waitingForOtherInstall =>
        'Another Hermuse Agent window is installing Hermes Agent. Waiting '
            'for it to finish…',
      SetupActivity.startingHermes => 'Starting Hermes Agent…',
      SetupActivity.installingPlugin => 'Installing the Hermuse plugin…',
      SetupActivity.checkingBridge => 'Checking the subscription bridge…',
      SetupActivity.checkingPlugin => 'Checking the Hermuse plugin…',
    },
    SetupReview(:final plan?, :final steps) when steps.isNotEmpty =>
      plan.needsAuthorization
          ? 'Hermuse Agent needs the changes marked below. Your system asks '
                'once for an administrator password to make them.'
          : 'Hermuse Agent needs the changes marked below.',
    SetupReview(keyring: _?) => 'The system keyring needs you.',
    SetupReview() => 'Something needs you before going on.',
    SetupApplying(running: LinuxDependencyStep.authorization) =>
      'Waiting for the administrator authorization…',
    SetupApplying() => 'Preparing this computer…',
    SetupInstalling() => 'Installing Hermes Agent…',
    SetupInstallFailed() => 'The Hermes Agent install stopped on a failure.',
    SetupHermesKept() => 'Hermes Agent on this computer needs you.',
    SetupComputer() => "Preparing the agent's computer…",
    SetupFailed() => 'A step failed.',
    SetupStopped() =>
      'Stopped before the next step. Choose Check again to continue.',
    SetupFinished() => 'Everything is in place.',
  };

  /// What concerns no single row.
  static List<SetupNotice> _notices(LinuxSetupState setup) => [
    if (setup.phase case SetupReview(:final lastRun?))
      SetupNotice(_outcome(lastRun), alert: true),
    if (setup.phase case SetupReview(:final blockers))
      for (final blocker in blockers)
        if (blocker.part == null)
          SetupNotice(
            blocker.explanation,
            details: blocker.details,
            alert: true,
          ),
    if (setup.phase case SetupFailed(:final message, part: null))
      SetupNotice(message, alert: true),
    if (setup.stopping)
      const SetupNotice('Finishing the current step before stopping…'),
  ];

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
}

/// The rows of the assistant's state, in the order it prepares their
/// parts: what this session established about each part, overridden by
/// what the current phase does to it.
final class _Checklist {
  _Checklist(this.setup, this.controller) {
    items = [for (final part in _parts) _row(part)];
  }

  final LinuxSetupState setup;
  final LinuxSetupController controller;
  late final List<YsChecklistItem> items;

  /// Whether a row offers "Check again" itself.
  bool checksAgain = false;

  /// Whether a row already offers "Prepare".
  bool _prepareShown = false;

  List<SetupPart> get _parts => switch (setup.goal) {
    LinuxSetupGoal.local => SetupPart.values,
    LinuxSetupGoal.computer => const [
      SetupPart.systemPackages,
      SetupPart.keyring,
      SetupPart.docker,
      SetupPart.hermes,
      SetupPart.computer,
    ],
    LinuxSetupGoal.connect => const [SetupPart.keyring],
    LinuxSetupGoal.reopen || null => [
      SetupPart.keyring,
      if (setup.parts.containsKey(SetupPart.docker) ||
          switch (setup.phase) {
            SetupWorking(activity: SetupActivity.checkingDocker) => true,
            _ => false,
          })
        SetupPart.docker,
    ],
  };

  /// Whether the system half of the goal covers [part].
  bool _inSystem(SetupPart part) => switch (part) {
    SetupPart.keyring => true,
    SetupPart.systemPackages || SetupPart.docker =>
      setup.goal?.targets.contains(LinuxTarget.local) ?? false,
    _ => false,
  };

  YsChecklistItem _row(SetupPart part) {
    final (icon, title) = switch (part) {
      SetupPart.systemPackages => (YsIcon.package, 'System packages'),
      SetupPart.keyring => (YsIcon.keyRound, 'System keyring'),
      SetupPart.docker => (YsIcon.container, 'Docker'),
      SetupPart.hermes => (YsIcon.bot, 'Hermes Agent'),
      SetupPart.plugin => (YsIcon.puzzle, 'Hermuse plugin'),
      SetupPart.bridge => (YsIcon.link, 'Subscription bridge'),
      SetupPart.computer => (YsIcon.monitor, "Agent's computer"),
    };
    YsChecklistItem item(
      YsStepState state,
      String status, {
      double? progress,
      String? trailing,
      List<YsChecklistNote> notes = const [],
      List<Widget> actions = const [],
    }) => YsChecklistItem(
      id: part,
      icon: icon,
      title: title,
      state: state,
      status: status,
      progress: progress,
      trailing: trailing,
      notes: notes,
      actions: actions,
    );
    final settled = switch (setup.parts[part]) {
      SetupPartReadiness.found => item(YsStepState.found, _found(part)),
      SetupPartReadiness.prepared => item(YsStepState.done, _prepared(part)),
      null => item(YsStepState.pending, 'Waiting'),
    };
    final version = setup.hermesVersion;
    switch (setup.phase) {
      case SetupIdle() when _inSystem(part):
        return item(YsStepState.checking, 'Checking…');
      case SetupWorking(activity: SetupActivity.inspectingSystem)
          when _inSystem(part):
        return item(YsStepState.checking, 'Checking…');
      case SetupWorking(:final activity) when activity.part == part:
        return switch (activity) {
          SetupActivity.checkingKeyring => item(
            YsStepState.checking,
            'Checking it keeps a secret…',
          ),
          SetupActivity.checkingDocker => item(
            YsStepState.checking,
            'Checking it answers…',
          ),
          SetupActivity.lookingForHermes => item(
            YsStepState.checking,
            'Looking for it on this computer…',
          ),
          SetupActivity.readingInstallPlan => item(
            YsStepState.working,
            'Reading the install plan…',
          ),
          SetupActivity.waitingForOtherInstall => item(
            YsStepState.working,
            'Another window is installing it…',
          ),
          // A Hermes Agent found in place is started, not installed.
          SetupActivity.startingHermes
              when setup.parts[part] == SetupPartReadiness.found =>
            item(
              YsStepState.checking,
              'Found${version == null ? '' : ' $version'} — starting it…',
            ),
          SetupActivity.startingHermes => item(
            YsStepState.working,
            'Starting it…',
          ),
          SetupActivity.installingPlugin => item(
            YsStepState.working,
            'Installing…',
          ),
          SetupActivity.checkingBridge => item(
            YsStepState.checking,
            'Verifying the bundled bridge…',
          ),
          // The final check leaves the plugin's row as it is; the header
          // says it runs.
          SetupActivity.checkingPlugin ||
          SetupActivity.inspectingSystem => settled,
        };
      case SetupReview() && final review:
        return _review(part, review, item) ?? settled;
      case SetupApplying() && final applying:
        return _applying(part, applying, item) ?? settled;
      case SetupInstalling(:final manifest, :final done, :final running)
          when part == SetupPart.hermes:
        final total = manifest.stages.length;
        return item(
          YsStepState.working,
          running == null
              ? 'Preparing the next step…'
              : _stageTitle(manifest, running),
          progress: total == 0 ? null : done.length / total,
          trailing: '${done.length}/$total',
        );
      case SetupInstallFailed(
            :final message,
            :final manifest,
            :final done,
            :final stage,
          )
          when part == SetupPart.hermes:
        return item(
          YsStepState.failed,
          stage == null
              ? 'The install failed'
              : 'Failed at “${_stageTitle(manifest, stage)}”',
          trailing: manifest == null
              ? null
              : '${done.length}/${manifest.stages.length}',
          notes: [
            YsChecklistNote(message, tone: YsNoteTone.alert),
            if (stage != null)
              const YsChecklistNote(
                'Fix the cause, then retry just this stage.',
              ),
          ],
          actions: [
            if (stage != null)
              YsButton.neutral(
                label: 'Retry this stage',
                onPressed: controller.retryStage,
              ),
          ],
        );
      case SetupHermesKept(:final message, :final found)
          when part == SetupPart.hermes:
        return item(
          YsStepState.needsAction,
          switch (found?.semver) {
            final semver? => 'Found $semver — not supported',
            null => 'Left as it is',
          },
          notes: [
            YsChecklistNote(message),
            if (found != null)
              const YsChecklistNote(
                'Update or remove it yourself, then choose Check again.',
              ),
          ],
          actions: [_checkAgain()],
        );
      case SetupComputer(:final status) when part == SetupPart.computer:
        return item(YsStepState.working, switch (status) {
          ComputerStatus(state: ComputerState.building, :final detail)
              when detail.isNotEmpty =>
            detail,
          ComputerStatus(state: ComputerState.stopped) => 'Starting it…',
          ComputerStatus(state: ComputerState.running) =>
            'Checking its screen…',
          _ => 'Preparing its image…',
        });
      case SetupFailed(:final message, part: final failed) when failed == part:
        return item(
          YsStepState.failed,
          'Failed',
          notes: [YsChecklistNote(message, tone: YsNoteTone.alert)],
        );
      default:
        return settled;
    }
  }

  /// [part] in a review: what it needs (the planned changes, with
  /// "Prepare" on the first row concerned), what holds it back, how its
  /// last run ended. Null when the review concerns another part.
  YsChecklistItem? _review(
    SetupPart part,
    SetupReview review,
    YsChecklistItem Function(
      YsStepState state,
      String status, {
      List<YsChecklistNote> notes,
      List<Widget> actions,
    })
    item,
  ) {
    final steps = [
      for (final planned in review.steps)
        if (planned.step.part == part) planned,
    ];
    final blockers = [
      for (final blocker in review.blockers)
        if (blocker.part == part) blocker,
    ];
    final failures = [
      for (final finished
          in review.lastRun?.finished ?? const <LinuxDependencyFinished>[])
        if (finished.step.part == part &&
            finished.outcome == LinuxStepOutcome.failed)
          finished,
    ];
    final keyring = part == SetupPart.keyring ? review.keyring : null;
    if (steps.isEmpty && blockers.isEmpty && keyring == null) return null;
    final prepare = steps.isNotEmpty && !_prepareShown;
    if (prepare) _prepareShown = true;
    final checkAgain = keyring != null && steps.isEmpty;
    if (checkAgain) checksAgain = true;
    final choice = blockers.any((b) => b.offersLocalDockerEngine);
    final state =
        failures.isNotEmpty ||
            (keyring != null && !keyring.locked) ||
            (blockers.isNotEmpty && !choice && steps.isEmpty)
        ? YsStepState.failed
        : YsStepState.needsAction;
    final status = failures.isNotEmpty
        ? 'Failed — Prepare tries again'
        : keyring != null
        ? (keyring.locked ? 'Locked' : 'Does not work yet')
        : blockers.isNotEmpty && steps.isEmpty
        ? _held(blockers.first)
        : review.plan?.needsAuthorization == true &&
              steps.any((s) => s.step.privileged)
        ? 'Needs administrator approval'
        : 'Ready to set up';
    return item(
      state,
      status,
      notes: [
        if (keyring != null)
          keyring.locked
              ? const YsChecklistNote(
                  'Your system keyring is locked. Unlock it when your system '
                  'asks, then choose Check again. Hermuse Agent stores '
                  'nothing until it works.',
                )
              : YsChecklistNote(
                  'The system keyring does not work yet: ${keyring.detail}. '
                  'Hermuse Agent keeps credentials only there, never in plain '
                  'text.',
                  tone: YsNoteTone.alert,
                ),
        for (final failure in failures)
          if (failure.detail.isNotEmpty)
            YsChecklistNote(failure.detail, tone: YsNoteTone.alert),
        for (final blocker in blockers) ...[
          YsChecklistNote(blocker.explanation, tone: YsNoteTone.alert),
          for (final detail in blocker.details) YsChecklistNote(detail),
        ],
        for (final planned in steps) ...[
          YsChecklistNote(planned.explanation),
          if (planned.warning case final warning?)
            YsChecklistNote(
              warning,
              caption: 'Root access',
              tone: YsNoteTone.alert,
            ),
        ],
      ],
      actions: [
        if (prepare)
          YsButton.neutral(label: 'Prepare', onPressed: controller.authorize),
        if (choice && review.offersLocalDockerEngine)
          YsButton.neutral(
            label: "Use this computer's Docker",
            onPressed: controller.useLocalDockerEngine,
          ),
        if (checkAgain) _checkAgain(),
      ],
    );
  }

  /// [part] while the planned steps run; null when none concerns it.
  YsChecklistItem? _applying(
    SetupPart part,
    SetupApplying applying,
    YsChecklistItem Function(
      YsStepState state,
      String status, {
      List<YsChecklistNote> notes,
    })
    item,
  ) {
    final steps = [
      for (final planned in applying.plan.steps)
        if (planned.step.part == part) planned,
    ];
    if (steps.isEmpty) return null;
    if (applying.running == LinuxDependencyStep.authorization &&
        steps.any((s) => s.step.privileged)) {
      return item(
        YsStepState.needsAction,
        'Approve in the system dialog',
        notes: [
          for (final planned in steps) ...[
            YsChecklistNote(planned.explanation),
            if (planned.warning case final warning?)
              YsChecklistNote(
                warning,
                caption: 'Root access',
                tone: YsNoteTone.alert,
              ),
          ],
        ],
      );
    }
    final outcomes = [for (final s in steps) applying.outcomes[s.step]];
    if (outcomes.any(
      (o) =>
          o == LinuxStepOutcome.failed ||
          o == LinuxStepOutcome.dismissed ||
          o == LinuxStepOutcome.denied,
    )) {
      return item(YsStepState.failed, 'Failed');
    }
    if (outcomes.every((o) => o != null)) {
      return outcomes.every((o) => o == LinuxStepOutcome.skipped)
          ? item(YsStepState.found, 'Found — nothing to change')
          : item(YsStepState.done, _prepared(part));
    }
    // One step runs at a time: the other rows wait for their next one.
    final next = steps.firstWhere((s) => applying.outcomes[s.step] == null);
    return next.step == applying.running
        ? item(YsStepState.working, _doing(next))
        : item(YsStepState.pending, _next(next));
  }

  YsButton _checkAgain() {
    checksAgain = true;
    return YsButton.neutral(
      label: 'Check again',
      onPressed: controller.checkAgain,
    );
  }

  String _found(SetupPart part) => switch (part) {
    SetupPart.hermes => switch (setup.hermesVersion) {
      final version? => 'Found $version — reused',
      null => 'Found — reused',
    },
    SetupPart.bridge => 'Bundled — verified',
    SetupPart.computer => 'Found running — reused',
    _ => 'Found — reused',
  };

  String _prepared(SetupPart part) => switch (part) {
    SetupPart.systemPackages || SetupPart.plugin => 'Installed now',
    SetupPart.hermes => switch (setup.hermesVersion) {
      final version? => 'Installed now — $version',
      null => 'Installed now',
    },
    SetupPart.keyring || SetupPart.docker => 'Set up now',
    SetupPart.bridge => 'Verified',
    SetupPart.computer => 'Ready',
  };

  /// What a running system step does.
  static String _doing(LinuxPlannedStep planned) => switch (planned.step) {
    LinuxDependencyStep.hermesTools || LinuxDependencyStep.secretService
        when planned.packages.isNotEmpty =>
      'Installing ${planned.packages.join(', ')}…',
    LinuxDependencyStep.hermesTools => 'Installing packages…',
    LinuxDependencyStep.secretService => 'Installing the keyring…',
    LinuxDependencyStep.activateSecretService => 'Starting the keyring…',
    LinuxDependencyStep.dockerInstall => 'Installing Docker…',
    LinuxDependencyStep.dockerStart => 'Starting the Docker service…',
    LinuxDependencyStep.dockerGroup => 'Adding you to the docker group…',
    LinuxDependencyStep.startRootlessDocker => 'Starting your rootless Docker…',
    LinuxDependencyStep.authorization => 'Waiting for the authorization…',
  };

  /// Why a part is held back, in a few words.
  static String _held(LinuxBlocker blocker) => switch (blocker.kind) {
    LinuxBlockerKind.dockerRemoteContext => 'Set to a remote engine',
    LinuxBlockerKind.dockerContextUnavailable => 'Its engine does not answer',
    LinuxBlockerKind.dockerUnusable => 'Present but not usable',
    LinuxBlockerKind.systemdMissing => 'Needs systemd',
    LinuxBlockerKind.userManagerMissing => 'Cannot be started',
    LinuxBlockerKind.sessionBusMissing => 'No session bus',
    LinuxBlockerKind.helperUnavailable ||
    LinuxBlockerKind.unsupportedOs ||
    LinuxBlockerKind.authorizationUnavailable => 'Cannot be prepared here',
  };

  /// What a system step waiting its turn will do.
  static String _next(LinuxPlannedStep planned) => switch (planned.step) {
    LinuxDependencyStep.hermesTools => 'Next: install its packages',
    LinuxDependencyStep.secretService => 'Next: install the keyring',
    LinuxDependencyStep.activateSecretService => 'Next: start the keyring',
    LinuxDependencyStep.dockerInstall => 'Next: install Docker',
    LinuxDependencyStep.dockerStart => 'Next: start the Docker service',
    LinuxDependencyStep.dockerGroup => 'Next: add you to the docker group',
    LinuxDependencyStep.startRootlessDocker =>
      'Next: start your rootless Docker',
    LinuxDependencyStep.authorization => 'Next',
  };

  static String _stageTitle(InstallManifest? manifest, String stage) {
    for (final s in manifest?.stages ?? const <InstallStage>[]) {
      if (s.name == stage) return s.title;
    }
    return stage;
  }
}
