import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/instances.dart';
import 'linux_setup.dart';
import 'setup_view.dart';

final class LinuxSetupGate extends ConsumerWidget {
  const LinuxSetupGate({required this.canLeave, super.key});
  final bool canLeave;
  @override
  Widget build(BuildContext context, WidgetRef ref) => LinuxSetupView(
    setup: ref.watch(linuxSetupProvider),
    controller: ref.read(linuxSetupProvider.notifier),
    canLeave: canLeave,
  );
}

final class LinuxSetupView extends StatelessWidget {
  const LinuxSetupView({
    required this.setup,
    required this.controller,
    required this.canLeave,
    super.key,
  });
  final LinuxSetupState setup;
  final LinuxSetupController controller;
  final bool canLeave;

  @override
  Widget build(BuildContext context) {
    final phase = setup.phase;
    if (phase is SetupDashboardLogin) {
      return AddInstanceScreen(
        localSystem: true,
        initialUrl: 'http://127.0.0.1:9119',
        autoProbe: true,
        onDone: controller.dashboardLoginCompleted,
        onCancel: controller.cancel,
      );
    }
    final review = phase is SetupReview ? phase : null;
    final dashboardLogin = setup.purpose == LinuxSetupPurpose.dashboardLogin;
    // The existing service's scheduler unit is missing, stopped or stale.
    final schedulerBroken = review?.inspection.schedulerReady == false;
    final connecting =
        setup.purpose == LinuxSetupPurpose.connect || dashboardLogin;
    final migration = review?.inspection.canonicalPresent == false
        ? review?.inspection.legacy
        : null;
    return SetupCard(
      title: connecting
          ? 'Connect to the existing service'
          : migration != null
          ? 'Review legacy migration'
          : 'Set up this computer',
      status: switch (phase) {
        SetupWorking(:final message) => message,
        SetupReview() =>
          connecting
              ? 'Authorize private desktop access'
              : 'One private, system-managed installation',
        SetupKeyringReview() => 'The desktop keyring needs attention',
        SetupFailed() => 'Setup did not finish',
        SetupStopped() => 'Setup stopped',
        SetupFinished() =>
          connecting ? 'Desktop access is ready' : 'This computer is ready',
        _ => connecting ? 'Preparing desktop access' : 'Preparing the service',
      },
      busy: setup.busy,
      notices: [
        if (dashboardLogin)
          const SetupNotice(
            'Desktop access uses the existing dashboard login. No administrator authorization, service restart, plugin adoption or installation was performed. Existing public access, password settings and legacy data are unchanged.',
          )
        else if (connecting)
          const SetupNotice(
            'Authorize access to the existing system service at http://127.0.0.1:9119. If a private desktop credential is missing, authorization prepares it and may restart the dashboard once. This does not reinstall or adopt the plugin, check or repair the runtime or computer, or change public access or password settings. Closing the app does not stop the service.',
          )
        else
          const SetupNotice(
            'Hermes runs as the dedicated hermes account in /home/hermes/.hermes. The desktop connects privately at http://127.0.0.1:9119. No firewall, Caddy, public IP or web publication is configured. Closing the app does not stop the service.',
          ),
        if (migration != null) migrationNotice(migration),
        if (review?.inspection.canonicalPresent == true &&
            (review!.inspection.legacyPresent ||
                review.inspection.legacy != null))
          const SetupNotice(
            'Legacy per-user data was also found. Reusing the canonical service leaves that data untouched; no migration or merge will run.',
          ),
        if (phase case SetupKeyringReview(:final message, :final plan)) ...[
          SetupNotice(message, alert: true),
          if (plan != null)
            for (final blocker in plan.blockers)
              SetupNotice(blocker.explanation, alert: true),
        ],
        if (phase case SetupFailed(:final message))
          SetupNotice(message, alert: true),
        if (setup.busy)
          SetupNotice(
            connecting
                ? 'Cancelling stops before the next safe stage. Desktop access already prepared remains available for retry.'
                : 'Cancelling stops before the next safe stage. Changes already installed remain available for retry.',
          ),
      ],
      log: setup.log,
      items: [
        YsChecklistItem(
          id: 'keyring',
          icon: YsIcon.keyRound,
          title: 'Desktop keyring',
          state: setup.keystoreVerified
              ? YsStepState.found
              : YsStepState.pending,
          status: setup.keystoreVerified
              ? 'Verified'
              : 'Required for saved credentials',
        ),
        if (schedulerBroken)
          const YsChecklistItem(
            id: 'scheduler-repair',
            icon: YsIcon.upcoming,
            title: 'Scheduler — needs repair',
            state: YsStepState.failed,
            status: 'Scheduled jobs, reminders and the heartbeat do not run',
          ),
        if (setup.goal == LinuxSetupGoal.local ||
            setup.goal == LinuxSetupGoal.computer)
          for (final step
              in dashboardLogin
                  ? const [RemoteInstallStep.verify]
                  : connecting
                  ? const [
                      RemoteInstallStep.connect,
                      RemoteInstallStep.dashboard,
                      RemoteInstallStep.verify,
                    ]
                  : const [
                      RemoteInstallStep.preflight,
                      RemoteInstallStep.hermesUser,
                      RemoteInstallStep.hermes,
                      RemoteInstallStep.plugin,
                      RemoteInstallStep.computer,
                      RemoteInstallStep.dashboard,
                      RemoteInstallStep.scheduler,
                      RemoteInstallStep.verify,
                    ])
            YsChecklistItem(
              id: step,
              icon: YsIcon.check,
              title: switch (step) {
                RemoteInstallStep.connect => 'Existing service identity',
                RemoteInstallStep.preflight => 'System requirements',
                RemoteInstallStep.hermesUser => 'Dedicated Hermes account',
                RemoteInstallStep.hermes => 'Pinned Hermes Agent',
                RemoteInstallStep.plugin => 'Hermuse plugin and jobs',
                RemoteInstallStep.computer => 'Docker and agent’s computer',
                RemoteInstallStep.dashboard =>
                  connecting
                      ? 'Private desktop credential'
                      : 'Private dashboard service',
                RemoteInstallStep.scheduler => 'Scheduler',
                _ =>
                  connecting
                      ? 'Authenticated desktop access'
                      : 'Final readiness checks',
              },
              state: setup.completed.contains(step)
                  ? YsStepState.done
                  : setup.running == step
                  ? (phase is SetupFailed
                        ? YsStepState.failed
                        : YsStepState.working)
                  : YsStepState.pending,
              status: setup.completed.contains(step)
                  ? 'Ready'
                  : setup.running == step
                  ? (phase is SetupFailed ? 'Failed' : 'Working…')
                  : 'Waiting',
            ),
      ],
      actions: [
        if (review != null && schedulerBroken)
          YsButton.primary(
            label: 'Repair scheduler',
            onPressed: () => controller.repairScheduler(),
          ),
        if (review != null && schedulerBroken && dashboardLogin)
          YsButton.neutral(
            label: 'Sign in without repair',
            onPressed: controller.skipSchedulerRepair,
          )
        else if (review != null)
          YsButton.primary(
            label: migration != null
                ? 'Approve backed-up migration'
                : connecting
                ? 'Authorize service access'
                : review.inspection.canonicalPresent
                ? 'Authorize computer setup'
                : 'Install private service',
            onPressed: () => controller.authorize(),
          ),
        if (phase is SetupKeyringReview &&
            phase.plan != null &&
            phase.plan!.steps.isNotEmpty &&
            phase.plan!.blockers.isEmpty)
          YsButton.primary(
            label: 'Prepare keyring',
            onPressed: () => controller.authorize(),
          ),
        if (phase is SetupFailed ||
            phase is SetupStopped ||
            phase is SetupKeyringReview)
          YsButton.neutral(
            label: 'Check again',
            onPressed: () => controller.checkAgain(),
          ),
        if (phase is SetupFinished)
          YsButton.primary(label: 'Continue', onPressed: controller.acknowledge)
        else if (canLeave || setup.busy)
          YsButton.neutral(
            label: setup.stopping ? 'Stopping…' : 'Cancel',
            onPressed: setup.stopping ? null : controller.cancel,
          ),
      ],
    );
  }
}

/// Shared informed review for local and SSH legacy migration.
SetupNotice migrationNotice(LegacyHermesMigration migration) => SetupNotice(
  'Source: ${migration.sourceHome}\nDestination: /home/hermes/.hermes\nBackup: /var/lib/hermuse-provision/migration-${migration.revision}/backup\n${migration.summary}\nThe backup is verified before migration and the original is retained. Existing canonical data is never merged or overwritten. Unowned running processes must be stopped by their owner before retrying. Cancel leaves your data untouched.',
  alert: true,
);
