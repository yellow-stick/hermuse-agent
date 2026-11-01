import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'agents.dart';
import 'identity.dart';
import 'screens.dart';
import 'tool_icon.dart';
import 'upcoming.dart';

/// Profile panel (360 wide): avatar, name, what the agent does now, tabs,
/// and the selected tab: activity, approvals, upcoming or identity.
class HermusePanel extends StatelessComponent {
  const HermusePanel({
    required this.agentName,
    required this.instanceId,
    required this.profile,
    required this.avatarId,
    required this.chat,
    this.onEditAgent,
    required this.threadIds,
    required this.approvals,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.onOpenThread,
    required this.onOpenApproval,
    required this.onStop,
    this.onOpenComputer,
    super.key,
  });

  final String agentName;
  final String instanceId;
  final String profile;
  final String avatarId;
  final ChatState chat;
  final VoidCallback? onEditAgent;

  /// The current chat's threads: activity of these opens its chat.
  final Set<String> threadIds;
  final List<ApprovalRequest> approvals;
  final PanelTab tab;
  final ValueChanged<PanelTab> onTab;
  final VoidCallback onClose;

  /// Opens a thread of the current chat from an activity row.
  final ValueChanged<String> onOpenThread;

  /// Opens the conversation waiting on an approval.
  final ValueChanged<String> onOpenApproval;

  /// Stops the turn running in a thread (the Stop button of a running
  /// task).
  final ValueChanged<String> onStop;

  /// Shows the agent's computer (its browser and desktop) at will; null
  /// hides the button. The read-only demo shows its fake computer too:
  /// its stream is replayed frames, input stays inert.
  final VoidCallback? onOpenComputer;

  @override
  Component build(BuildContext context) {
    final step = chat.agentStep;
    return aside(
      classes: 'hermuse-panel',
      attributes: {'aria-label': 'Profile'},
      [
        div(classes: 'hermuse-panel-close', [
          YsButton.icon(
            icon: YsIcon.close,
            label: 'Close panel',
            onPressed: onClose,
          ),
        ]),
        div(classes: 'hermuse-panel-avatar', [
          HermuseAgentAvatar(
            instanceId: instanceId,
            profile: profile,
            avatarId: avatarId,
            chat: chat,
            alt: '$agentName avatar',
            size: 100,
            onEdit: onEditAgent,
          ),
        ]),
        h1(classes: 'hermuse-panel-name', [.text(agentName)]),
        div(
          classes: 'hermuse-panel-status',
          attributes: {'role': 'status', 'aria-live': 'polite'},
          [
            if (step == null)
              span(classes: 'hermuse-panel-status-icon', [
                YsPing(
                  live: true,
                  color: YsTheme.success,
                  child: RawText(ysConnectedSvg('currentColor')),
                ),
              ])
            else
              span(classes: 'hermuse-panel-status-icon hermuse-panel-working', [
                YsPing(
                  live: true,
                  color: YsTheme.primary,
                  child: span(classes: 'hermuse-panel-working-dot', []),
                ),
              ]),
            span(classes: 'hermuse-panel-status-text', [
              .text(step ?? 'Connected'),
            ]),
          ],
        ),
        if (onOpenComputer case final onOpen?)
          div(classes: 'hermuse-panel-computer', [
            YsButton.neutral(label: 'Open computer', onPressed: onOpen),
          ]),
        div(classes: 'hermuse-panel-tabs', [
          YsSegmentedTabs<PanelTab>(
            segments: [
              for (final t in PanelTab.values)
                YsSegment(value: t, icon: _tabIcon(t), label: t.label),
            ],
            selected: tab,
            onSelected: onTab,
          ),
        ]),
        switch (tab) {
          PanelTab.activity => HermuseWatch(
            provider: tasksProvider(instanceId, profile: profile),
            builder: (context, tasks) => _activity(tasks),
          ),
          PanelTab.approvals => _approvals(),
          PanelTab.upcoming => HermuseUpcoming(
            key: ValueKey('upcoming:$instanceId:$profile'),
            instanceId: instanceId,
            profile: profile,
          ),
          PanelTab.identity => HermuseIdentity(
            key: ValueKey('identity:$instanceId:$profile'),
            instanceId: instanceId,
            profile: profile,
            agentName: agentName,
            onEditAgent: onEditAgent,
          ),
        },
      ],
    );
  }

  Component _activity(AsyncValue<List<Task>> tasks) {
    final running = chat.runningTasks;
    final items = tasks.value ?? const <Task>[];
    if (running.isEmpty && items.isEmpty) {
      if (tasks.isLoading) {
        return p(
          classes: 'hermuse-panel-note',
          attributes: {'role': 'status'},
          [.text('Loading activity…')],
        );
      }
      return HermusePanelEmpty(
        PanelTab.activity,
        help: tasks.hasError
            ? 'Could not load activity: ${hermuseErrorText(tasks.error!)}'
            : null,
      );
    }
    return div(classes: 'hermuse-panel-section', [
      if (running.isNotEmpty) ...[
        h2(classes: 'hermuse-panel-heading', [.text('Now')]),
        for (final task in running) _runningRow(task),
      ],
      for (final day in activityDays(items, DateTime.now())) ...[
        h2(classes: 'hermuse-panel-heading', [.text(day.label)]),
        for (final task in day.items) _taskRow(task),
      ],
    ]);
  }

  Component _runningRow(RunningTask task) {
    final title = task.request.isNotEmpty
        ? task.request
        : task.threadTitle.isNotEmpty
        ? task.threadTitle
        : task.isMain
        ? 'Main chat'
        : 'New chat';
    final body = [
      div(classes: 'hermuse-activity-icon hermuse-activity-live', [
        YsIconView(YsIcon.sparkles, size: 18),
      ]),
      div(classes: 'hermuse-activity-body', [
        p(classes: 'hermuse-activity-title hermuse-activity-clamp', [
          .text(title),
        ]),
        p(classes: 'hermuse-activity-desc', [.text(task.step)]),
      ]),
    ];
    return div(classes: 'hermuse-activity hermuse-activity-running', [
      if (threadIds.contains(task.threadId))
        YsPressable(
          classes: 'hermuse-activity-main hermuse-activity-link',
          onPressed: () => onOpenThread(task.threadId),
          builder: (context, state) =>
              span(classes: 'hermuse-activity-row', body),
        )
      else
        div(classes: 'hermuse-activity-main', body),
      YsTooltip(
        label: 'Stop',
        child: YsButton.icon(
          icon: YsIcon.stop,
          label: 'Stop $title',
          size: 32,
          iconSize: 16,
          onPressed: () => onStop(task.threadId),
        ),
      ),
    ]);
  }

  Component _taskRow(Task task) {
    final status = switch (task.status) {
      TaskStatus.completed => null,
      TaskStatus.failed => 'Failed',
      TaskStatus.interrupted => 'Stopped',
    };
    final content = [
      div(classes: 'hermuse-activity-icon', [
        YsIconView(toolIcon(task.kind), size: 18),
      ]),
      div(classes: 'hermuse-activity-body', [
        p(classes: 'hermuse-activity-title', [.text(task.title)]),
        if (task.summary.isNotEmpty)
          p(classes: 'hermuse-activity-desc hermuse-activity-clamp', [
            .text(task.summary),
          ]),
        p(classes: 'hermuse-activity-time', [
          .text([formatChatTime(task.finishedAt), ?status].join(' · ')),
        ]),
      ]),
    ];
    if (!threadIds.contains(task.sessionId)) {
      return div(classes: 'hermuse-activity', content);
    }
    return YsPressable(
      classes: 'hermuse-activity hermuse-activity-link',
      onPressed: () => onOpenThread(task.sessionId),
      builder: (context, state) =>
          span(classes: 'hermuse-activity-row', content),
    );
  }

  Component _approvals() {
    if (approvals.isEmpty) return const HermusePanelEmpty(PanelTab.approvals);
    return div(classes: 'hermuse-panel-section', [
      h2(classes: 'hermuse-panel-heading', [.text('Pending')]),
      for (final request in approvals)
        YsPressable(
          classes: 'hermuse-activity hermuse-activity-link',
          onPressed: () => onOpenApproval(request.threadId),
          builder: (context, state) => span(classes: 'hermuse-activity-row', [
            div(classes: 'hermuse-activity-icon', [
              YsIconView(YsIcon.approvals, size: 18),
            ]),
            div(classes: 'hermuse-activity-body', [
              p(classes: 'hermuse-activity-title hermuse-approval-command', [
                .text(request.command.split('\n').first),
              ]),
              p(classes: 'hermuse-activity-time', [.text(request.threadTitle)]),
            ]),
          ]),
        ),
    ]);
  }

  static YsIcon _tabIcon(PanelTab tab) => switch (tab) {
    PanelTab.activity => YsIcon.activity,
    PanelTab.approvals => YsIcon.approvals,
    PanelTab.upcoming => YsIcon.upcoming,
    PanelTab.identity => YsIcon.identity,
  };

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-panel', [
      css('&').styles(
        width: YsLayout.panelWidth.px,
        height: 100.percent,
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        padding: .only(top: 70.px, left: 16.px, right: 16.px, bottom: 44.px),
        backgroundColor: .variable('--canvas'),
        border: .only(
          left: .solid(color: .variable('--line'), width: 1.2.px),
        ),
        overflow: .only(y: .auto, x: .hidden),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-panel-close').styles(
        width: 100.percent,
        display: .flex,
        justifyContent: .end,
        raw: {'margin-top': '-54px', 'margin-bottom': '18px'},
      ),
      css('.hermuse-panel-name').styles(
        margin: .only(top: 8.px),
        fontSize: 22.px,
        lineHeight: 28.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-panel-status').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(5.px),
        margin: .only(top: 2.px),
      ),
      css('.hermuse-panel-status-icon')
          .styles(display: .inlineFlex, color: YsTheme.success),
      css('.hermuse-panel-status-text').styles(
        fontSize: 17.px,
        lineHeight: 22.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-panel-computer').styles(margin: .only(top: 16.px)),
      css('.hermuse-panel-tabs').styles(
        width: 327.px,
        margin: .only(top: 44.px),
      ),
      css('.hermuse-panel-section').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        gap: .all(1.px),
      ),
      css('.hermuse-panel-heading').styles(
        margin: .only(top: 8.px, bottom: 0.px),
        fontSize: 16.px,
        lineHeight: 22.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-activity').styles(
        padding: .all(8.px),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        gap: .all(8.px),
      ),
      css('.hermuse-activity-link')
          .styles(width: 100.percent, textAlign: .left, cursor: .pointer),
      css('.hermuse-activity-link:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-activity-row').styles(display: .contents),
      css('.hermuse-activity-icon').styles(
        width: YsLayout.activityTileSize.px,
        height: YsLayout.activityTileSize.px,
        radius: .circular(YsRadius.row.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content-muted'),
        backgroundColor: .variable('--neutral-ambient'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-activity-body')
          .styles(display: .flex, flexDirection: .column, gap: .all(2.px)),
      css('.hermuse-activity-title').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-activity-desc').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-activity-clamp').styles(
        overflow: .hidden,
        raw: {
          'display': '-webkit-box',
          '-webkit-line-clamp': '2',
          '-webkit-box-orient': 'vertical',
          'overflow-wrap': 'anywhere',
        },
      ),
      css('.hermuse-activity-mono').styles(
        fontSize: YsType.code.size.px,
        lineHeight: YsType.code.lineHeight.px,
        raw: {'font-family': YsType.monoFamily},
      ),
      css('.hermuse-activity-time').styles(
        margin: .zero,
        fontSize: 12.px,
        lineHeight: 16.px,
        color: .variable('--content-subtle'),
      ),
      css('.hermuse-approval-command').styles(
        overflow: .hidden,
        raw: {
          'display': '-webkit-box',
          '-webkit-line-clamp': '2',
          '-webkit-box-orient': 'vertical',
          'overflow-wrap': 'anywhere',
        },
      ),
      css('.hermuse-panel-note').styles(
        width: 100.percent,
        margin: .symmetric(vertical: YsSpace.xs.px),
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-panel-working-dot').styles(
        width: YsLayout.statusDot.px,
        height: YsLayout.statusDot.px,
        margin: .all(4.px),
        radius: .circular(YsRadius.pill.px),
        display: .block,
        backgroundColor: .variable('--primary'),
      ),
      css('.hermuse-activity-running').styles(alignItems: .center),
      css('.hermuse-activity-main').styles(
        display: .flex,
        flexDirection: .row,
        gap: .all(8.px),
        raw: {'flex': '1', 'min-width': '0'},
      ),
      css('.hermuse-activity-running .hermuse-activity-link')
          .styles(padding: .zero, radius: .circular(YsRadius.row.px)),
      css('.hermuse-activity-live').styles(color: .variable('--primary-ink')),
      css('.hermuse-activity-body').styles(raw: {'min-width': '0'}),
      css('.hermuse-panel-empty-help').styles(
        margin: .fromLTRB(.zero, YsSpace.sm.px, .zero, .zero),
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-subtle'),
      ),
      css('.hermuse-panel-empty').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        padding: .only(top: YsSpace.xl.px),
        color: .variable('--content-muted'),
        textAlign: .center,
      ),
      css('.hermuse-panel-empty-title').styles(
        margin: .fromLTRB(.zero, YsSpace.sm.px, .zero, .zero),
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-panel-empty-body').styles(
        margin: .fromLTRB(.zero, YsSpace.xs.px, .zero, .zero),
        fontSize: 13.px,
        lineHeight: 18.px,
      ),
    ]),
  ];
}

/// The empty state of [tab]: its art, name and empty text, and an optional
/// [help] line.
class HermusePanelEmpty extends StatelessComponent {
  const HermusePanelEmpty(this.tab, {this.help, super.key});

  final PanelTab tab;
  final String? help;

  @override
  Component build(BuildContext context) => YsHover(
    builder: (context, hovered) => div(classes: 'hermuse-panel-empty', [
      YsArtView(
        switch (tab) {
          PanelTab.activity => YsArt.activity,
          PanelTab.approvals => YsArt.approvals,
          PanelTab.upcoming => YsArt.upcoming,
          PanelTab.identity => YsArt.activity,
        },
        size: YsLayout.artCompact,
        active: hovered,
      ),
      p(classes: 'hermuse-panel-empty-title', [.text(tab.label)]),
      p(classes: 'hermuse-panel-empty-body', [.text(tab.emptyText)]),
      if (help case final help?)
        p(classes: 'hermuse-panel-empty-help', [.text(help)]),
    ]),
  );
}
