import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../host/setup_view.dart';
import '../shell/screens.dart';

/// What Hermuse needs on a Hermes it reaches over the network
/// ([remoteSetupProvider]): Hermes itself, the Hermuse plugin, its jobs,
/// Docker, the agent's computer and a model, each found in place or
/// installed from its row. What only the user can do says how, with the
/// command to run on the server. Continue opens the chat once a model
/// answers, the onboarding before; it waits while a look or an install runs.
final class ComponentsScreen extends ConsumerWidget {
  const ComponentsScreen({
    required this.instance,
    required this.onChat,
    required this.onSetUpModel,
    super.key,
  });

  final HermesInstance instance;

  /// Continue once a model answers: the instance's chat.
  final VoidCallback onChat;

  /// "Set up a model", and Continue before a model answers: the onboarding.
  final VoidCallback onSetUpModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = remoteSetupProvider(instance.id);
    final setup = ref.watch(provider);
    final checklist = ref.read(provider.notifier);
    final phase = setup.phase;
    final unreachable = phase == RemoteSetupPhase.unreachable;
    // A look or an install runs: what depends on its outcome waits for it.
    final working = _working(setup);
    // Installs need the Hermes to answer.
    final everything = !unreachable && setup.installable.length >= 2;
    final onContinue = working
        ? null
        : setup[RemotePart.model].status.settled
        ? onChat
        : onSetUpModel;
    return SetupCard(
      art: switch (phase) {
        RemoteSetupPhase.unreachable ||
        RemoteSetupPhase.failed => YsArt.unreachable,
        RemoteSetupPhase.ready => YsArt.ready,
        _ => YsArt.remote,
      },
      busy:
          phase == RemoteSetupPhase.checking ||
          phase == RemoteSetupPhase.installing,
      title: "What's on ${instance.label}",
      status: setup.headline,
      items: [
        for (final row in setup.parts)
          _item(row, () {
            if (row.action == RemoteAction.setUpModel) {
              onSetUpModel();
            } else {
              unawaited(checklist.run(row.part));
            }
          }),
      ],
      notices: [
        if (setup.unreachable case final reason?)
          SetupNotice(reason, alert: true),
      ],
      // One main action: the installs when offered, else reaching the
      // Hermes again when it does not answer, else Continue.
      actions: [
        if (everything)
          YsButton.primary(
            label: 'Install everything missing',
            onPressed: working
                ? null
                : () => unawaited(checklist.installEverything()),
          ),
        if (unreachable)
          YsButton.primary(
            label: working ? 'Checking…' : 'Check again',
            onPressed: working ? null : () => unawaited(checklist.checkAgain()),
          ),
        if (everything || unreachable)
          YsButton.neutral(label: 'Continue', onPressed: onContinue)
        else
          YsButton.primary(label: 'Continue', onPressed: onContinue),
      ],
      // The ring plays its ready moment; leaving stays the user's choice.
      onReady: phase == RemoteSetupPhase.ready ? () {} : null,
    );
  }

  /// The checklist row of [row]; its button runs [act].
  static YsChecklistItem _item(RemotePartState row, VoidCallback act) {
    final action = row.action;
    final report = row.report;
    final command = row.command;
    return YsChecklistItem(
      id: row.part,
      icon: switch (row.part) {
        RemotePart.hermes => YsIcon.bot,
        RemotePart.plugin => YsIcon.puzzle,
        RemotePart.jobs => YsIcon.upcoming,
        RemotePart.docker => YsIcon.container,
        RemotePart.computer => YsIcon.monitor,
        RemotePart.model => YsIcon.sparkles,
      },
      title: row.part.title,
      state: switch (row.status) {
        RemotePartStatus.checking => YsStepState.checking,
        RemotePartStatus.present => YsStepState.found,
        RemotePartStatus.installed => YsStepState.done,
        RemotePartStatus.missing ||
        RemotePartStatus.needsUser => YsStepState.needsAction,
        RemotePartStatus.blocked => YsStepState.pending,
        RemotePartStatus.installing => YsStepState.working,
        RemotePartStatus.failed => YsStepState.failed,
      },
      status: row.summary,
      notes: [
        for (final note in row.notes)
          YsChecklistNote(
            note,
            tone: row.alert ? YsNoteTone.alert : YsNoteTone.muted,
          ),
      ],
      actions: [
        if (report != null) InstallLogBox(log: [report], follow: false),
        if (command != null) CommandBox(command, onPaper: true),
        if (action != null)
          YsButton.neutral(
            label: action.label,
            onPressed: row.enabled ? act : null,
          ),
      ],
    );
  }
}

/// Whether a look or an install of [setup] runs: Continue, "Install
/// everything missing" and "Check again" wait for it. Web parity:
/// `HermuseComponents._working`.
bool _working(RemoteSetupState setup) =>
    setup.busy ||
    setup.parts.any(
      (row) =>
          row.status == RemotePartStatus.checking ||
          row.status == RemotePartStatus.installing,
    );
