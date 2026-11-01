import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart' show HermesException;
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/agents.dart';
import '../shell/brand.dart';
import '../shell/screens.dart' show YsDialogError;
import '../thread/tool_icon.dart';
import 'identity.dart';
import 'panel_parts.dart';
import 'upcoming.dart';

/// Profile panel: avatar, name, status (or the agent's live step), then the
/// Activity, Approvals, Upcoming and Identity tabs.
final class ProfilePanel extends ConsumerStatefulWidget {
  const ProfilePanel({
    required this.instanceId,
    required this.agentName,
    required this.approvals,
    required this.threadIds,
    required this.onOpenThread,
    required this.onOpenComputer,
    required this.onClose,
    this.runningTasks = const [],
    this.agentStep,
    this.onStop,
    this.profile = 'default',
    this.avatar = hermuseAvatar,
    super.key,
  });

  /// Hermes instance of the chat: its tasks and scheduled jobs show.
  final String instanceId;
  final String agentName;
  final String profile;
  final ImageProvider avatar;

  /// Approval requests Hermes still waits on, in the current chat.
  final List<ApprovalRequest> approvals;

  /// Turns the agent is running now (`ChatState.runningTasks`).
  final List<RunningTask> runningTasks;

  /// What the agent is doing now (`ChatState.agentStep`); null while idle.
  final String? agentStep;

  /// Stops the turn running in a thread (`ChatController.interrupt`).
  final ValueChanged<String>? onStop;

  /// Threads of the current chat: a task from one of them opens it.
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
    PanelTab.upcoming => YsIcon.upcoming,
    PanelTab.identity => YsIcon.identity,
  };

  void _select(PanelTab tab) {
    if (tab != _tab) {
      // Opening a server-backed tab always shows the server's current data.
      switch (tab) {
        case PanelTab.activity:
          ref
              .read(
                tasksProvider(
                  widget.instanceId,
                  profile: widget.profile,
                ).notifier,
              )
              .refresh();
        case PanelTab.upcoming:
          ref.invalidate(
            automationsProvider(widget.instanceId, profile: widget.profile),
          );
        case PanelTab.approvals || PanelTab.identity:
          break;
      }
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
          AgentEditorAnchor(
            instanceId: widget.instanceId,
            profile: widget.profile,
            builder: (context, edit) => YsAvatar(
              widget.avatar,
              size: 100,
              semanticLabel: '${widget.agentName} avatar',
              badgeIcon: YsIcon.pencil,
              onBadgePressed: edit,
              badgeSemanticLabel: 'Edit avatar and name',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.agentName,
            style: YsType.title.flutter.copyWith(color: palette.contentColor),
          ),
          const SizedBox(height: 2),
          _StatusLine(step: widget.agentStep),
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
      profile: widget.profile,
      running: widget.runningTasks,
      threadIds: widget.threadIds,
      onOpenThread: widget.onOpenThread,
      onStop: widget.onStop,
    ),
    PanelTab.approvals =>
      widget.approvals.isEmpty
          ? const PanelEmptyState(tab: PanelTab.approvals)
          : _ApprovalsList(
              approvals: widget.approvals,
              onOpen: (request) => widget.onOpenThread(request.threadId),
            ),
    PanelTab.upcoming => UpcomingTab(
      instanceId: widget.instanceId,
      profile: widget.profile,
    ),
    PanelTab.identity => IdentityTab(
      instanceId: widget.instanceId,
      profile: widget.profile,
      agentName: widget.agentName,
    ),
  };
}

/// "Connected" while idle; the agent's live step ("Searching the web")
/// while it works.
final class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.step});

  final String? step;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final step = this.step;
    final style = YsType.status.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (step == null)
            YsPing(
              live: true,
              color: palette.successColor,
              child: YsIconWidget.raw(
                ysConnectedSvg(palette.success.css),
                size: 16,
              ),
            )
          else
            const YsSpinner(),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              step ?? 'Connected',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- activity

final class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({
    required this.instanceId,
    required this.profile,
    required this.running,
    required this.threadIds,
    required this.onOpenThread,
    required this.onStop,
  });

  final String instanceId;
  final String profile;
  final List<RunningTask> running;
  final Set<String> threadIds;
  final ValueChanged<String> onOpenThread;
  final ValueChanged<String>? onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = tasksProvider(instanceId, profile: profile);
    final tasks = ref.watch(provider);
    final items = tasks.value ?? const <Task>[];
    final error = tasks.hasValue ? null : tasks.error;
    // A missing plugin (StateError) records no tasks: the empty state says
    // so; any other failure is named, with a retry.
    final failure = error is StateError ? null : error;
    final reason = failure == null
        ? null
        : "Couldn't load activity: ${switch (failure) {
            final HermesException e => hermesReason(e),
            _ => '$failure',
          }}";
    final retry = YsButton.neutral(
      label: 'Retry',
      onPressed: () => ref.read(provider.notifier).refresh(),
    );
    if (running.isEmpty && items.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          PanelEmptyState(tab: PanelTab.activity, help: reason),
          if (reason != null) ...[
            const SizedBox(height: YsSpace.sm),
            Center(child: retry),
          ],
        ],
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (running.isNotEmpty) ...[
          const PanelHeading('Now'),
          for (final task in running)
            _RunningRow(
              key: ValueKey('running-${task.threadId}'),
              task: task,
              onOpen: threadIds.contains(task.threadId)
                  ? () => onOpenThread(task.threadId)
                  : null,
              onStop: onStop == null ? null : () => onStop!(task.threadId),
            ),
        ],
        if (reason != null) ...[
          const SizedBox(height: YsSpace.sm),
          YsDialogError(reason),
          const SizedBox(height: YsSpace.sm),
          Align(alignment: Alignment.centerLeft, child: retry),
        ],
        for (final day in activityDays(items, DateTime.now())) ...[
          PanelHeading(day.label),
          for (final task in day.items)
            _TaskRow(
              key: ValueKey('task-${task.id}'),
              task: task,
              onOpen: threadIds.contains(task.sessionId)
                  ? () => onOpenThread(task.sessionId)
                  : null,
            ),
        ],
      ],
    );
  }
}

/// A turn running now: its request (or chat), live step and Stop.
final class _RunningRow extends StatelessWidget {
  const _RunningRow({
    required this.task,
    required this.onOpen,
    required this.onStop,
    super.key,
  });

  final RunningTask task;
  final VoidCallback? onOpen;
  final VoidCallback? onStop;

  String get _title => task.request.isNotEmpty
      ? task.request
      : task.threadTitle.isNotEmpty
      ? task.threadTitle
      : task.isMain
      ? 'Main chat'
      : 'New chat';

  @override
  Widget build(BuildContext context) {
    final title = _title;
    return PanelRow(
      icon: YsIcon.zap,
      onPressed: onOpen,
      trailing: YsButton.icon(
        icon: YsIcon.stop,
        onPressed: onStop,
        semanticLabel: 'Stop $title',
        tooltip: 'Stop',
        size: 32,
        iconSize: 16,
      ),
      body: PanelRowText(title: title, summary: task.step),
    );
  }
}

final class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onOpen, super.key});

  final Task task;

  /// Opens the chat it ran in; null when that chat is not in this one.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => PanelRow(
    icon: task.status == TaskStatus.failed
        ? YsIcon.xCircle
        : toolIcon(task.kind),
    onPressed: onOpen,
    body: PanelRowText(
      title: task.title,
      summary: task.summary,
      time: formatChatTime(task.finishedAt),
    ),
  );
}

// --------------------------------------------------------------- approvals

final class _ApprovalsList extends StatelessWidget {
  const _ApprovalsList({required this.approvals, required this.onOpen});

  final List<ApprovalRequest> approvals;
  final ValueChanged<ApprovalRequest> onOpen;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.zero,
    children: [
      const PanelHeading('Pending'),
      for (final request in approvals)
        Padding(
          padding: const EdgeInsets.only(bottom: YsSpace.xxs),
          child: PanelRow(
            icon: YsIcon.approvals,
            onPressed: () => onOpen(request),
            semanticLabel: 'Open approval in ${request.threadTitle}',
            body: PanelRowText(
              title: request.command.split('\n').first,
              time: request.threadTitle,
            ),
          ),
        ),
    ],
  );
}
