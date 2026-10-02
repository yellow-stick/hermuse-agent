import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart' show HermesException;
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/brand.dart';
import '../shell/screens.dart' show YsDialogError;

/// Profile panel: avatar, name, status, then the Activity, Approvals,
/// Automations and Connectors tabs.
final class ProfilePanel extends ConsumerStatefulWidget {
  const ProfilePanel({
    required this.instanceId,
    required this.agentName,
    required this.approvals,
    required this.threadIds,
    required this.onOpenThread,
    required this.onOpenComputer,
    required this.onClose,
    super.key,
  });

  /// Hermes instance of the chat: its activity and automations show.
  final String instanceId;
  final String agentName;

  /// Approval requests Hermes still waits on, in the current chat.
  final List<ApprovalRequest> approvals;

  /// Threads of the current chat: activity from one of them opens it.
  final Set<String> threadIds;

  /// Opens a thread of the current chat (an approval, an activity row).
  final ValueChanged<String> onOpenThread;

  /// Shows the agent's computer (its browser, its desktop) at will.
  final VoidCallback onOpenComputer;
  final VoidCallback onClose;

  @override
  ConsumerState<ProfilePanel> createState() => ProfilePanelState();
}

final class ProfilePanelState extends ConsumerState<ProfilePanel> {
  PanelTab _tab = PanelTab.activity;

  static YsIcon _iconFor(PanelTab tab) => switch (tab) {
    PanelTab.activity => YsIcon.activity,
    PanelTab.approvals => YsIcon.approvals,
    PanelTab.automations => YsIcon.upcoming,
    PanelTab.connectors => YsIcon.link,
  };

  void _select(PanelTab tab) {
    // Opening Automations always shows Hermes' current jobs.
    if (tab == PanelTab.automations && tab != _tab) {
      ref.invalidate(automationsProvider(widget.instanceId));
    }
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    // No fill of its own: the shell paints the canvas, so the hairline the
    // shell draws on the panel's edge stays visible.
    return Padding(
      // The close button sits on the floating header row (top 16, like the
      // web panel's -54 px margin); the avatar starts at 70.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 44),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: YsButton.icon(
              icon: YsIcon.close,
              onPressed: widget.onClose,
              semanticLabel: 'Close panel',
              tooltip: 'Close panel',
              size: 36,
              iconSize: 18,
            ),
          ),
          const SizedBox(height: 18),
          YsAvatar(
            hermuseAvatar,
            size: 100,
            semanticLabel: 'Hermuse avatar',
            badgeIcon: YsIcon.pencil,
            onBadgePressed: () {},
            badgeSemanticLabel: 'Edit avatar and name',
          ),
          const SizedBox(height: 8),
          Text(
            widget.agentName,
            style: YsType.title.flutter.copyWith(color: palette.contentColor),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              YsPing(
                live: true,
                color: palette.successColor,
                child: YsIconWidget.raw(
                  ysConnectedSvg(palette.success.css),
                  size: 16,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'Connected',
                style: YsType.status.flutter.copyWith(
                  color: palette.contentMutedColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          YsButton.neutral(
            label: 'Open computer',
            onPressed: widget.onOpenComputer,
          ),
          const SizedBox(height: 44),
          SizedBox(
            width: 327,
            child: YsSegmentedTabs(
              semanticLabel: 'Profile sections',
              segments: [
                for (final tab in PanelTab.values)
                  YsSegment(icon: _iconFor(tab), label: tab.label),
              ],
              selectedIndex: _tab.index,
              onSelected: (index) => _select(PanelTab.values[index]),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _tabBody()),
        ],
      ),
    );
  }

  Widget _tabBody() => switch (_tab) {
    PanelTab.activity => _ActivityTab(
      instanceId: widget.instanceId,
      threadIds: widget.threadIds,
      onOpenThread: widget.onOpenThread,
    ),
    PanelTab.approvals =>
      widget.approvals.isEmpty
          ? const _TabEmptyState(tab: PanelTab.approvals)
          : _ApprovalsList(
              approvals: widget.approvals,
              onOpen: (request) => widget.onOpenThread(request.threadId),
            ),
    PanelTab.automations => _AutomationsTab(instanceId: widget.instanceId),
    PanelTab.connectors => const _TabEmptyState(tab: PanelTab.connectors),
  };
}

/// "Today", "Yesterday", … heading over a group of rows.
final class _DayHeading extends StatelessWidget {
  const _DayHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: YsType.heading.flutter.copyWith(
        color: YsTheme.of(context).contentColor,
      ),
    ),
  );
}

/// Rounded tile with a muted icon, at the start of every panel row.
final class _RowTile extends StatelessWidget {
  const _RowTile(this.icon);

  final YsIcon icon;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralAmbientColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: SizedBox(
        width: YsLayout.activityTileSize,
        height: YsLayout.activityTileSize,
        child: Center(
          child: YsIconWidget(icon, size: 18, color: palette.contentMutedColor),
        ),
      ),
    );
  }
}

/// A panel row: tile then [body]; pressable (hover fill) only with
/// [onPressed].
final class _PanelRow extends StatelessWidget {
  const _PanelRow({
    required this.icon,
    required this.body,
    this.onPressed,
    this.semanticLabel,
  });

  final YsIcon icon;
  final Widget body;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  Widget _row(Color fill) => AnimatedContainer(
    duration: const Duration(milliseconds: YsMotion.fast),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(YsRadius.row),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RowTile(icon),
        const SizedBox(width: 8),
        Expanded(child: body),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    const clear = Color(0x00000000);
    final onPressed = this.onPressed;
    if (onPressed == null) return MergeSemantics(child: _row(clear));
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      builder: (context, state) =>
          _row(state.hovered ? palette.neutralWashColor : clear),
    );
  }
}

// ---------------------------------------------------------------- activity

final class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({
    required this.instanceId,
    required this.threadIds,
    required this.onOpenThread,
  });

  final String instanceId;
  final Set<String> threadIds;
  final ValueChanged<String> onOpenThread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items =
        ref.watch(activityProvider(instanceId)).value ?? const <ActivityItem>[];
    // Nothing happened yet: the tab's empty state, not a lone heading.
    if (items.isEmpty) return const _TabEmptyState(tab: PanelTab.activity);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final day in activityDays(items, DateTime.now())) ...[
          _DayHeading(day.label),
          for (final item in day.items)
            _ActivityRow(
              item: item,
              onOpen: threadIds.contains(item.sessionId)
                  ? () => onOpenThread(item.sessionId)
                  : null,
            ),
        ],
      ],
    );
  }
}

final class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.onOpen});

  final ActivityItem item;

  /// Opens the chat it ran in; null when that chat is not in this one.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return _PanelRow(
      icon: item.kind == ActivityKind.webSearch
          ? YsIcon.webSearch
          : YsIcon.checkCircle,
      onPressed: onOpen,
      semanticLabel: item.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: YsType.label.flutter.copyWith(color: palette.contentColor),
          ),
          if (item.summary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              item.summary,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
          const SizedBox(height: 2),
          Text(
            formatChatTime(item.at),
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- approvals

final class _ApprovalsList extends StatelessWidget {
  const _ApprovalsList({required this.approvals, required this.onOpen});

  final List<ApprovalRequest> approvals;
  final ValueChanged<ApprovalRequest> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _DayHeading('Pending'),
        for (final request in approvals)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _PanelRow(
              icon: YsIcon.approvals,
              onPressed: () => onOpen(request),
              semanticLabel: 'Open approval in ${request.threadTitle}',
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.command.split('\n').first,
                    style: YsType.label.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    request.threadTitle,
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- automations

final class _AutomationsTab extends ConsumerStatefulWidget {
  const _AutomationsTab({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_AutomationsTab> createState() => _AutomationsTabState();
}

final class _AutomationsTabState extends ConsumerState<_AutomationsTab> {
  /// Automation awaiting the delete confirmation.
  Automation? _deleting;
  final _deleteDialog = OverlayPortalController();

  void _perform(Automation automation, AutomationAction action) => unawaited(
    ref
        .read(automationsProvider(widget.instanceId).notifier)
        .perform(automation, action),
  );

  void _confirmDelete(Automation automation) {
    setState(() => _deleting = automation);
    _deleteDialog.show();
  }

  void _closeDelete() {
    _deleteDialog.hide();
    setState(() => _deleting = null);
  }

  void _delete() {
    final target = _deleting;
    _closeDelete();
    if (target != null) _perform(target, AutomationAction.delete);
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(automationsProvider(widget.instanceId));
    return OverlayPortal(
      controller: _deleteDialog,
      overlayChildBuilder: _deleteConfirmation,
      child: switch (board) {
        AsyncValue(value: final AutomationBoard value) => _board(value),
        AsyncValue(:final error?) => _loadError(error),
        _ => const _AutomationsSkeleton(),
      },
    );
  }

  Widget _loadError(Object error) => ListView(
    padding: const EdgeInsets.only(top: YsSpace.sm),
    children: [
      YsDialogError(
        "Couldn't load automations: ${switch (error) {
          final HermesException e => hermesReason(e),
          _ => '$error',
        }}",
      ),
      const SizedBox(height: YsSpace.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: YsButton.neutral(
          label: 'Retry',
          onPressed: () =>
              ref.invalidate(automationsProvider(widget.instanceId)),
        ),
      ),
    ],
  );

  Widget _board(AutomationBoard board) {
    final palette = YsTheme.of(context);
    final error = board.error;
    final notices = [
      if (error != null) YsDialogError(error),
      if (board.schedulerStopped)
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.neutralAmbientColor,
            borderRadius: BorderRadius.circular(YsRadius.row),
          ),
          child: Padding(
            padding: const EdgeInsets.all(YsSpace.md),
            child: Text(
              "The scheduler isn't running on this server: automations only "
              'run when started here until the Hermes gateway runs.',
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ),
        ),
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
          const _TabEmptyState(
            tab: PanelTab.automations,
            help: 'Ask your agent: "Every morning at 8, send me…"',
          )
        else ...[
          const SizedBox(height: YsSpace.sm),
          for (final automation in board.automations)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _AutomationRow(
                key: ValueKey(automation.id),
                automation: automation,
                busy: board.busy[automation.id],
                onAction: (action) => action == AutomationAction.delete
                    ? _confirmDelete(automation)
                    : _perform(automation, action),
              ),
            ),
        ],
      ],
    );
  }

  Widget _deleteConfirmation(BuildContext context) {
    final palette = YsTheme.of(context);
    final name = _deleting?.name ?? '';
    return YsDialog(
      title: 'Delete automation?',
      onClose: _closeDelete,
      actions: [
        YsButton.neutral(label: 'Cancel', onPressed: _closeDelete),
        YsButton.destructive(label: 'Delete', onPressed: _delete),
      ],
      child: Text(
        '“$name” stops running and is removed from this Hermes. '
        'This cannot be undone.',
        style: YsType.small.flutter.copyWith(color: palette.contentColor),
      ),
    );
  }
}

final class _AutomationsSkeleton extends StatelessWidget {
  const _AutomationsSkeleton();

  @override
  Widget build(BuildContext context) => YsSkeleton(
    semanticLabel: 'Loading automations…',
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
                      SizedBox(height: YsSpace.xs),
                      FractionallySizedBox(
                        widthFactor: 0.4,
                        child: YsSkeletonBox(height: 12),
                      ),
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

final class _AutomationRow extends StatelessWidget {
  const _AutomationRow({
    required this.automation,
    required this.busy,
    required this.onAction,
    super.key,
  });

  final Automation automation;

  /// The action in flight on it, if any.
  final AutomationAction? busy;
  final ValueChanged<AutomationAction> onAction;

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

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final a = automation;
    final muted = YsType.caption.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    final lastRunAt = a.lastRunAt;
    final nextRunAt = a.nextRunAt;
    final outcome = a.lastOutcome;
    final failed = outcome != null && outcome != AutomationOutcome.ok;
    final busy = this.busy;
    return _PanelRow(
      icon: YsIcon.upcoming,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  a.name,
                  style: YsType.label.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (a.owner == AutomationOwner.hermuse) ...[
                const SizedBox(width: YsSpace.xs),
                const _OwnerTag(),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            a.schedule,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
          if (a.paused)
            Text('Paused', style: muted)
          else if (nextRunAt != null)
            Text('Next: ${formatAutomationTime(nextRunAt)}', style: muted),
          if (lastRunAt != null)
            Text.rich(
              TextSpan(
                text: 'Last: ${formatAutomationTime(lastRunAt)}',
                children: [
                  if (outcome != null)
                    TextSpan(
                      text: switch (outcome) {
                        AutomationOutcome.ok => ' · OK',
                        AutomationOutcome.failed => ' · Failed',
                        AutomationOutcome.deliveryFailed => ' · Not delivered',
                      },
                      style: failed
                          ? muted.copyWith(color: palette.errorColor)
                          : null,
                    ),
                ],
              ),
              style: muted,
            ),
          if (failed && a.lastError.isNotEmpty)
            Text(
              a.lastError,
              style: muted.copyWith(color: palette.errorColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: YsSpace.xs),
          Row(
            children: [
              for (final action in a.actions)
                YsButton.icon(
                  icon: _icon(action),
                  onPressed: busy == null ? () => onAction(action) : null,
                  semanticLabel: '${_label(action)} ${a.name}',
                  tooltip: _label(action),
                  size: 27,
                  iconSize: 16,
                ),
              if (busy != null) ...[
                const SizedBox(width: YsSpace.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(_inFlight(busy), style: muted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// "Hermuse" beside an automation the Hermuse plugin scheduled.
final class _OwnerTag extends StatelessWidget {
  const _OwnerTag();

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YsRadius.pill),
        border: Border.all(color: palette.lineColor, width: ysHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.sm,
          vertical: YsSpace.xxs,
        ),
        child: Text(
          'Hermuse',
          style: YsType.caption.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- empty state

final class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({required this.tab, this.help});

  final PanelTab tab;

  /// A hint under the empty text (how to fill the tab).
  final String? help;

  static YsArt _artFor(PanelTab tab) => switch (tab) {
    PanelTab.activity => YsArt.activity,
    PanelTab.approvals => YsArt.approvals,
    PanelTab.automations => YsArt.upcoming,
    PanelTab.connectors => YsArt.plugin,
  };

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final help = this.help;
    final small = YsType.small.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    return YsHover(
      builder: (context, hovered) => Column(
        children: [
          const SizedBox(height: YsSpace.xl),
          YsArtView(_artFor(tab), size: YsLayout.artCompact, active: hovered),
          const SizedBox(height: YsSpace.sm),
          Text(
            tab.label,
            style: YsType.label.flutter.copyWith(color: palette.contentColor),
          ),
          const SizedBox(height: YsSpace.xs),
          Text(tab.emptyText, style: small),
          if (help != null) ...[
            const SizedBox(height: YsSpace.xs),
            Text(help, style: small, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
