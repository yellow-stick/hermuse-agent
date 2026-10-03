import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart' show HermesException;
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/screens.dart' show YsDialogError;
import 'panel_parts.dart';

/// The Upcoming tab: scheduled jobs by section (Reminders, Daily, Weekly,
/// Other recurring, Heartbeat); a row opens its sheet.
final class UpcomingTab extends ConsumerStatefulWidget {
  const UpcomingTab({
    required this.instanceId,
    required this.profile,
    super.key,
  });

  final String instanceId;
  final String profile;

  @override
  ConsumerState<UpcomingTab> createState() => _UpcomingTabState();
}

final class _UpcomingTabState extends ConsumerState<UpcomingTab> {
  final _sheet = OverlayPortalController();

  /// Id of the job whose sheet is open.
  String? _openId;

  void _open(Automation automation) {
    setState(() => _openId = automation.id);
    _sheet.show();
  }

  void _close() {
    _sheet.hide();
    setState(() => _openId = null);
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(
      automationsProvider(widget.instanceId, profile: widget.profile),
    );
    return OverlayPortal(
      controller: _sheet,
      overlayChildBuilder: (context) => UpcomingSheet(
        instanceId: widget.instanceId,
        profile: widget.profile,
        jobId: _openId ?? '',
        onClose: _close,
      ),
      child: switch (board) {
        AsyncValue(value: final AutomationBoard value) => _board(value),
        AsyncValue(:final error?) => _loadError(error),
        _ => const _UpcomingSkeleton(),
      },
    );
  }

  Widget _loadError(Object error) => ListView(
    padding: const EdgeInsets.only(top: YsSpace.sm),
    children: [
      YsDialogError("Couldn't load upcoming items: ${_reason(error)}"),
      const SizedBox(height: YsSpace.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: YsButton.neutral(
          label: 'Retry',
          onPressed: () => ref.invalidate(
            automationsProvider(widget.instanceId, profile: widget.profile),
          ),
        ),
      ),
    ],
  );

  Widget _board(AutomationBoard board) {
    final error = board.error;
    final notices = [
      if (error != null && _openId == null) YsDialogError(error),
      if (board.schedulerStopped) const SchedulerStoppedNotice(),
    ];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final notice in notices)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.sm),
            child: notice,
          ),
        if (board.automations.isEmpty)
          const PanelEmptyState(
            tab: PanelTab.upcoming,
            help: 'Ask your agent: "Every morning at 8, send me…"',
          )
        else
          for (final section in board.sections) ...[
            PanelHeading(section.group.label),
            for (final automation in section.automations)
              Padding(
                padding: const EdgeInsets.only(bottom: YsSpace.xxs),
                child: PanelRow(
                  key: ValueKey(automation.id),
                  icon: upcomingIcon(automation),
                  onPressed: () => _open(automation),
                  body: PanelRowText(
                    title: automation.name,
                    summary: upcomingSubtitle(automation),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

String _reason(Object error) => switch (error) {
  final HermesException e => hermesReason(e),
  _ => '$error',
};

/// Heart for the heartbeat, a clock for anything else scheduled.
YsIcon upcomingIcon(Automation automation) =>
    automation.group == UpcomingGroup.heartbeat
    ? YsIcon.heart
    : YsIcon.upcoming;

/// A row's line: a reminder's date ("Oct 4, 9:15 AM"), else its schedule in
/// words; "Paused" appended.
String upcomingSubtitle(Automation automation) {
  final next = automation.nextRunAt;
  final when = automation.group == UpcomingGroup.reminders && next != null
      ? formatShortDate(next)
      : automation.schedule;
  return automation.paused ? '$when · Paused' : when;
}

/// The scheduler on the server does not tick: jobs only run by hand.
final class SchedulerStoppedNotice extends StatelessWidget {
  const SchedulerStoppedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralAmbientColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(YsSpace.md),
        child: Text(
          "The scheduler isn't running on this server: scheduled items "
          'only run when started here until it runs again.',
          style: YsType.small.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
      ),
    );
  }
}

/// Sheet of one scheduled job: schedule, next run, run history and its
/// actions (Pause/Resume, Run now, Delete).
final class UpcomingSheet extends ConsumerStatefulWidget {
  const UpcomingSheet({
    required this.instanceId,
    required this.profile,
    required this.jobId,
    required this.onClose,
    super.key,
  });

  final String instanceId;
  final String profile;
  final String jobId;
  final VoidCallback onClose;

  @override
  ConsumerState<UpcomingSheet> createState() => _UpcomingSheetState();
}

final class _UpcomingSheetState extends ConsumerState<UpcomingSheet> {
  bool _confirmingDelete = false;

  static String _label(AutomationAction action) => switch (action) {
    AutomationAction.pause => 'Pause',
    AutomationAction.resume => 'Resume',
    AutomationAction.runNow => 'Run now',
    AutomationAction.delete => 'Delete',
  };

  static String _inFlight(AutomationAction action) => switch (action) {
    AutomationAction.pause => 'Pausing…',
    AutomationAction.resume => 'Resuming…',
    AutomationAction.runNow => 'Running…',
    AutomationAction.delete => 'Deleting…',
  };

  static YsIcon _icon(AutomationAction action) => switch (action) {
    AutomationAction.pause => YsIcon.pause,
    AutomationAction.resume => YsIcon.play,
    AutomationAction.runNow => YsIcon.zap,
    AutomationAction.delete => YsIcon.trash,
  };

  Automations get _automations => ref.read(
    automationsProvider(widget.instanceId, profile: widget.profile).notifier,
  );

  Future<void> _perform(Automation automation, AutomationAction action) async {
    await _automations.perform(automation, action);
    if (!mounted) return;
    if (action == AutomationAction.runNow) {
      ref.invalidate(
        automationRunsProvider(
          widget.instanceId,
          widget.jobId,
          profile: widget.profile,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = ref
        .watch(automationsProvider(widget.instanceId, profile: widget.profile))
        .value;
    final automation = board?.automations
        .where((a) => a.id == widget.jobId)
        .firstOrNull;
    if (board == null || automation == null) {
      // Deleted (or gone from the server): nothing left to show.
      return YsDialog(
        title: 'Scheduled item',
        onClose: widget.onClose,
        actions: [YsButton.neutral(label: 'Close', onPressed: widget.onClose)],
        child: _muted(context, 'This item is no longer scheduled.'),
      );
    }
    if (_confirmingDelete) return _deleteConfirmation(context, automation);
    final busy = board.busy[automation.id];
    final error = board.error;
    final next = automation.nextRunAt;
    return YsDialog(
      title: automation.name,
      onClose: widget.onClose,
      actions: [
        for (final action in automation.actions)
          action == AutomationAction.delete
              ? YsButton.destructive(
                  label: _label(action),
                  icon: _icon(action),
                  onPressed: busy == null
                      ? () => setState(() => _confirmingDelete = true)
                      : null,
                )
              : YsButton.neutral(
                  label: _label(action),
                  icon: _icon(action),
                  onPressed: busy == null
                      ? () => unawaited(_perform(automation, action))
                      : null,
                ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fact(context, 'Schedule', automation.schedule),
          _fact(
            context,
            'Next run',
            automation.paused
                ? 'Paused'
                : next == null
                ? 'Not scheduled'
                : formatAutomationTime(next),
          ),
          if (busy != null)
            Semantics(
              liveRegion: true,
              child: _muted(context, _inFlight(busy)),
            ),
          if (error != null) ...[
            const SizedBox(height: YsSpace.sm),
            YsDialogError(error),
          ],
          const SizedBox(height: YsSpace.lg),
          const PanelHeading('Run history'),
          const SizedBox(height: YsSpace.xs),
          _RunHistory(
            instanceId: widget.instanceId,
            profile: widget.profile,
            jobId: automation.id,
          ),
        ],
      ),
    );
  }

  Widget _deleteConfirmation(BuildContext context, Automation automation) {
    void cancel() => setState(() => _confirmingDelete = false);
    return YsDialog(
      title: 'Delete this item?',
      onClose: cancel,
      actions: [
        YsButton.neutral(label: 'Cancel', onPressed: cancel),
        YsButton.destructive(
          label: 'Delete',
          onPressed: () {
            // The sheet goes away first: perform on the tab's notifier.
            final automations = _automations;
            widget.onClose();
            unawaited(automations.perform(automation, AutomationAction.delete));
          },
        ),
      ],
      child: Text(
        '“${automation.name}” stops running and is removed from this '
        "Hermes. This can't be undone.",
        style: YsType.small.flutter.copyWith(
          color: YsTheme.of(context).contentColor,
        ),
      ),
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    final palette = YsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.xs),
      child: Text.rich(
        TextSpan(
          text: '$label  ',
          style: YsType.caption.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
          children: [
            TextSpan(
              text: value,
              style: YsType.small.flutter.copyWith(color: palette.contentColor),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _muted(BuildContext context, String text) => Text(
  text,
  style: YsType.small.flutter.copyWith(
    color: YsTheme.of(context).contentMutedColor,
  ),
);

/// The job's last runs: time, status, output excerpt.
final class _RunHistory extends ConsumerWidget {
  const _RunHistory({
    required this.instanceId,
    required this.profile,
    required this.jobId,
  });

  final String instanceId;
  final String profile;
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final provider = automationRunsProvider(
      instanceId,
      jobId,
      profile: profile,
    );
    return switch (ref.watch(provider)) {
      AsyncValue(value: final List<AutomationRun> runs) when runs.isEmpty =>
        _muted(context, 'Has not run yet'),
      AsyncValue(value: final List<AutomationRun> runs) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final run in runs)
            Padding(
              padding: const EdgeInsets.only(bottom: YsSpace.sm),
              child: _RunRow(run: run),
            ),
        ],
      ),
      AsyncValue(:final error?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YsDialogError("Couldn't load the run history: ${_reason(error)}"),
          const SizedBox(height: YsSpace.xs),
          YsButton.neutral(
            label: 'Retry',
            onPressed: () => ref.invalidate(provider),
          ),
        ],
      ),
      _ => Row(
        children: [
          const YsSpinner(),
          const SizedBox(width: YsSpace.sm),
          Text(
            'Loading runs…',
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ),
    };
  }
}

final class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final AutomationRun run;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final muted = YsType.caption.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    final (status, color) = switch (run.status) {
      AutomationRunStatus.running => ('Running', palette.contentMutedColor),
      AutomationRunStatus.ok => ('Done', palette.successColor),
      AutomationRunStatus.failed => ('Failed', palette.errorColor),
    };
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: formatAutomationTime(run.startedAt),
              children: [
                TextSpan(
                  text: ' · $status',
                  style: muted.copyWith(color: color),
                ),
              ],
            ),
            style: muted,
          ),
          if (run.output.isNotEmpty) ...[
            const SizedBox(height: YsSpace.xxs),
            Text(
              run.output,
              style: YsType.small.flutter.copyWith(color: palette.contentColor),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

final class _UpcomingSkeleton extends StatelessWidget {
  const _UpcomingSkeleton();

  @override
  Widget build(BuildContext context) => YsSkeleton(
    semanticLabel: 'Loading upcoming items…',
    child: Column(
      children: [
        for (var i = 0; i < 2; i++)
          const Padding(
            padding: EdgeInsets.all(YsSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                YsSkeletonBox(
                  height: YsLayout.activityTileSize,
                  width: YsLayout.activityTileSize,
                ),
                SizedBox(width: YsSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.6,
                        child: YsSkeletonBox(height: 14),
                      ),
                      SizedBox(height: YsSpace.xs),
                      YsSkeletonBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
