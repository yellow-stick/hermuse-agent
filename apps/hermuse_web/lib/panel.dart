import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'brand.dart';
import 'scope.dart';
import 'screens.dart';

/// Profile panel (360 wide): avatar, name, status, tabs, and the selected
/// tab: activity, approvals, automations or connectors.
class HermusePanel extends StatelessComponent {
  const HermusePanel({
    required this.agentName,
    required this.instanceId,
    required this.threadIds,
    required this.approvals,
    required this.tab,
    required this.onTab,
    required this.onClose,
    required this.onOpenThread,
    required this.onOpenApproval,
    this.onOpenComputer,
    super.key,
  });

  final String agentName;
  final String instanceId;

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

  /// Shows the agent's computer (its browser and desktop) at will; null
  /// hides the button. The read-only demo shows its fake computer too:
  /// its stream is replayed frames, input stays inert.
  final VoidCallback? onOpenComputer;

  @override
  Component build(BuildContext context) => aside(
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
        YsAvatar(
          src: hermuseAvatarUrl,
          alt: '$agentName avatar',
          size: 100,
          onEdit: () {},
          editLabel: 'Edit avatar',
        ),
      ]),
      h1(classes: 'hermuse-panel-name', [.text(agentName)]),
      div(classes: 'hermuse-panel-status', [
        span(classes: 'hermuse-panel-status-icon', [
          YsPing(
            live: true,
            color: YsTheme.success,
            child: RawText(ysConnectedSvg('currentColor')),
          ),
        ]),
        span(classes: 'hermuse-panel-status-text', [.text('Connected')]),
      ]),
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
          provider: activityProvider(instanceId),
          builder: (context, activity) => _activity(activity.value ?? []),
        ),
        PanelTab.approvals => _approvals(),
        PanelTab.automations => _AutomationsTab(
          key: ValueKey(instanceId),
          instanceId: instanceId,
        ),
        PanelTab.connectors => const _PanelEmpty(PanelTab.connectors),
      },
    ],
  );

  Component _activity(List<ActivityItem> items) {
    if (items.isEmpty) return const _PanelEmpty(PanelTab.activity);
    return div(classes: 'hermuse-panel-section', [
      for (final day in activityDays(items, DateTime.now())) ...[
        h2(classes: 'hermuse-panel-heading', [.text(day.label)]),
        for (final item in day.items) _activityRow(item),
      ],
    ]);
  }

  Component _activityRow(ActivityItem item) {
    final content = [
      div(classes: 'hermuse-activity-icon', [
        YsIconView(
          item.kind == ActivityKind.webSearch
              ? YsIcon.webSearch
              : YsIcon.checkCircle,
          size: 18,
        ),
      ]),
      div(classes: 'hermuse-activity-body', [
        p(classes: 'hermuse-activity-title', [.text(item.title)]),
        if (item.summary.isNotEmpty)
          p(classes: 'hermuse-activity-desc', [.text(item.summary)]),
        p(classes: 'hermuse-activity-time', [.text(formatChatTime(item.at))]),
      ]),
    ];
    if (!threadIds.contains(item.sessionId)) {
      return div(classes: 'hermuse-activity', content);
    }
    return YsPressable(
      classes: 'hermuse-activity hermuse-activity-link',
      onPressed: () => onOpenThread(item.sessionId),
      builder: (context, state) =>
          span(classes: 'hermuse-activity-row', content),
    );
  }

  Component _approvals() {
    if (approvals.isEmpty) return const _PanelEmpty(PanelTab.approvals);
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
    PanelTab.automations => YsIcon.upcoming,
    PanelTab.connectors => YsIcon.link,
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
      css('.hermuse-automations').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        gap: .all(1.px),
      ),
      css('.hermuse-automations-note').styles(
        margin: .symmetric(vertical: YsSpace.xs.px),
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-automations-error').styles(
        margin: .symmetric(vertical: YsSpace.xs.px),
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--error'),
        raw: {'overflow-wrap': 'anywhere'},
      ),
      css('.hermuse-automation').styles(
        padding: .all(8.px),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        gap: .all(8.px),
      ),
      css('.hermuse-automation .hermuse-activity-body')
          .styles(raw: {'flex': '1', 'min-width': '0'}),
      css('.hermuse-automation-name').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(YsSpace.xs.px),
      ),
      css('.hermuse-automation-tag').styles(
        padding: .symmetric(horizontal: 6.px),
        radius: .circular(YsRadius.pill.px),
        fontSize: 11.px,
        lineHeight: 16.px,
        fontWeight: .w500,
        color: .variable('--content-muted'),
        backgroundColor: .variable('--neutral-ambient'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-automation-failed').styles(color: .variable('--error')),
      css('.hermuse-automation-actions').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .start,
        raw: {'flex-shrink': '0'},
      ),
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
class _PanelEmpty extends StatelessComponent {
  const _PanelEmpty(this.tab, {this.help});

  final PanelTab tab;
  final String? help;

  @override
  Component build(BuildContext context) => YsHover(
    builder: (context, hovered) => div(classes: 'hermuse-panel-empty', [
      YsArtView(
        switch (tab) {
          PanelTab.activity => YsArt.activity,
          PanelTab.approvals => YsArt.approvals,
          PanelTab.automations => YsArt.upcoming,
          PanelTab.connectors => YsArt.plugin,
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

/// Hermes' cron jobs of [instanceId], reloaded whenever the tab opens, with
/// pause/resume, run now and delete (after a confirmation).
class _AutomationsTab extends StatefulComponent {
  const _AutomationsTab({required this.instanceId, super.key});

  final String instanceId;

  @override
  State<_AutomationsTab> createState() => _AutomationsTabState();
}

class _AutomationsTabState extends State<_AutomationsTab> {
  Automation? _deleting;

  @override
  void initState() {
    super.initState();
    // Fresh on every opening: jobs run and change on the server meanwhile.
    context.container.invalidate(automationsProvider(component.instanceId));
  }

  void _perform(Automation automation, AutomationAction action) {
    context.container
        .read(automationsProvider(component.instanceId).notifier)
        .perform(automation, action);
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: automationsProvider(component.instanceId),
    builder: (context, async) {
      final board = async.value;
      if (board == null) {
        if (async.error case final error?) {
          return div(classes: 'hermuse-automations', [
            p(classes: 'hermuse-automations-error', [
              .text('Could not load automations: $error'),
            ]),
            div([
              YsButton.neutral(
                label: 'Retry',
                onPressed: () => context.container.invalidate(
                  automationsProvider(component.instanceId),
                ),
              ),
            ]),
          ]);
        }
        return p(
          classes: 'hermuse-automations-note',
          attributes: {'role': 'status'},
          [.text('Loading automations…')],
        );
      }
      return div(classes: 'hermuse-automations', [
        if (board.error case final error?)
          p(
            classes: 'hermuse-automations-error',
            attributes: {'role': 'alert'},
            [.text(error)],
          ),
        if (board.schedulerStopped)
          p(classes: 'hermuse-automations-note', [
            .text(
              "The scheduler isn't running on this server: automations only "
              'run when started here until the Hermes gateway runs.',
            ),
          ]),
        if (board.automations.isEmpty)
          const _PanelEmpty(
            PanelTab.automations,
            help: 'Ask your agent: "Every morning at 8, send me…"',
          )
        else
          for (final automation in board.automations)
            _row(automation, board.busy[automation.id]),
        if (_deleting case final deleting?)
          YsDialog(
            title: 'Delete automation?',
            onClose: () => setState(() => _deleting = null),
            actions: [
              YsButton.neutral(
                label: 'Cancel',
                onPressed: () => setState(() => _deleting = null),
              ),
              YsButton.destructive(
                label: 'Delete',
                onPressed: () {
                  setState(() => _deleting = null);
                  _perform(deleting, AutomationAction.delete);
                },
              ),
            ],
            child: p([
              .text(
                '“${deleting.name}” stops running and is removed from this '
                'Hermes. This cannot be undone.',
              ),
            ]),
          ),
      ]);
    },
  );

  Component _row(Automation automation, AutomationAction? busy) {
    final last = automation.lastRunAt;
    final failed = automation.lastOutcome == AutomationOutcome.failed;
    final next = automation.nextRunAt;
    return div(classes: 'hermuse-automation', [
      div(classes: 'hermuse-activity-icon', [
        YsIconView(YsIcon.upcoming, size: 18),
      ]),
      div(classes: 'hermuse-activity-body', [
        p(classes: 'hermuse-activity-title hermuse-automation-name', [
          span([.text(automation.name)]),
          if (automation.owner == AutomationOwner.hermuse)
            span(classes: 'hermuse-automation-tag', [.text('Hermuse')]),
        ]),
        p(classes: 'hermuse-activity-desc', [.text(automation.schedule)]),
        p(classes: 'hermuse-activity-time', [
          .text(switch (busy) {
            AutomationAction.pause => 'Pausing…',
            AutomationAction.resume => 'Resuming…',
            AutomationAction.runNow => 'Running…',
            AutomationAction.delete => 'Deleting…',
            null when automation.paused => 'Paused',
            null when next != null => 'Next: ${formatAutomationTime(next)}',
            null => 'Not scheduled',
          }),
        ]),
        if (last != null)
          p(
            classes: [
              'hermuse-activity-time',
              if (failed) 'hermuse-automation-failed',
            ].join(' '),
            attributes: {
              if (failed && automation.lastError.isNotEmpty)
                'title': automation.lastError,
            },
            [
              .text(
                'Last: ${formatAutomationTime(last)}'
                '${switch (automation.lastOutcome) {
                  AutomationOutcome.ok => ' · OK',
                  AutomationOutcome.failed => ' · Failed',
                  AutomationOutcome.deliveryFailed => ' · Not delivered',
                  null => '',
                }}',
              ),
            ],
          ),
        if (failed && automation.lastError.isNotEmpty)
          p(classes: 'hermuse-activity-time hermuse-automation-failed', [
            .text(automation.lastError),
          ]),
      ]),
      div(classes: 'hermuse-automation-actions', [
        for (final action in automation.actions)
          YsTooltip(
            label: _actionLabel(action),
            child: YsButton.icon(
              icon: switch (action) {
                AutomationAction.pause => YsIcon.pause,
                AutomationAction.resume => YsIcon.play,
                AutomationAction.runNow => YsIcon.zap,
                AutomationAction.delete => YsIcon.trash,
              },
              label: '${_actionLabel(action)} ${automation.name}',
              size: 32,
              iconSize: 16,
              onPressed: busy != null
                  ? null
                  : action == AutomationAction.delete
                  ? () => setState(() => _deleting = automation)
                  : () => _perform(automation, action),
            ),
          ),
      ]),
    ]);
  }

  static String _actionLabel(AutomationAction action) => switch (action) {
    AutomationAction.pause => 'Pause',
    AutomationAction.resume => 'Resume',
    AutomationAction.runNow => 'Run now',
    AutomationAction.delete => 'Delete',
  };
}
