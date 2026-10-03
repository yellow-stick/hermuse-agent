import 'package:hermuse_chat/hermuse_chat.dart' show PanelTab, formatChatTime;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'panel.dart';
import 'scope.dart';
import 'screens.dart';

/// The panel's Upcoming tab: the agent's scheduled jobs of [instanceId]
/// grouped Reminders, Daily, Weekly, Other recurring and Heartbeat,
/// reloaded whenever the tab opens. A row opens its detail: schedule, next
/// run, run history and Pause/Resume, Run now, Delete.
class HermuseUpcoming extends StatefulComponent {
  const HermuseUpcoming({
    required this.instanceId,
    required this.profile,
    super.key,
  });

  final String instanceId;
  final String profile;

  @override
  State<HermuseUpcoming> createState() => _HermuseUpcomingState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-upcoming').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .column,
      gap: .all(1.px),
    ),
    css('.hermuse-upcoming-note').styles(
      margin: .symmetric(vertical: YsSpace.xs.px),
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-upcoming-error').styles(
      margin: .symmetric(vertical: YsSpace.xs.px),
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--error'),
      raw: {'overflow-wrap': 'anywhere'},
    ),
    css('.hermuse-upcoming-heart').styles(color: .variable('--primary-ink')),
    css('.hermuse-upcoming-facts').styles(
      margin: .zero,
      display: .grid,
      gap: .all(YsSpace.xs.px),
      raw: {'grid-template-columns': 'max-content 1fr', 'column-gap': '16px'},
    ),
    css('.hermuse-upcoming-facts dt').styles(
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-upcoming-facts dd').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 18.px,
      color: .variable('--content'),
      raw: {'overflow-wrap': 'anywhere'},
    ),
    css('.hermuse-upcoming-failed').styles(color: .variable('--error')),
    css('.hermuse-upcoming-history-head').styles(
      margin: .only(top: YsSpace.sm.px),
      fontSize: YsType.label.size.px,
      lineHeight: YsType.label.lineHeight.px,
      fontWeight: .w500,
    ),
    css('.hermuse-upcoming-runs').styles(
      margin: .zero,
      padding: .zero,
      display: .flex,
      flexDirection: .column,
      gap: .all(YsSpace.sm.px),
      listStyle: .none,
    ),
    css('.hermuse-upcoming-run').styles(
      padding: .all(YsSpace.sm.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(2.px),
      backgroundColor: .variable('--neutral-film'),
    ),
    css('.hermuse-upcoming-run-head').styles(
      display: .flex,
      flexDirection: .row,
      justifyContent: .spaceBetween,
      gap: .all(YsSpace.sm.px),
      fontSize: 12.px,
      lineHeight: 16.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-upcoming-run-output').styles(
      margin: .zero,
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content'),
      overflow: .hidden,
      raw: {
        'display': '-webkit-box',
        '-webkit-line-clamp': '4',
        '-webkit-box-orient': 'vertical',
        'overflow-wrap': 'anywhere',
        'white-space': 'pre-wrap',
      },
    ),
  ];
}

class _HermuseUpcomingState extends State<HermuseUpcoming> {
  /// Job whose detail is open (looked up on every build: it changes as
  /// actions land).
  String? _openId;
  Automation? _deleting;

  AutomationsProvider get _board =>
      automationsProvider(component.instanceId, profile: component.profile);

  @override
  void initState() {
    super.initState();
    // Fresh on every opening: jobs run and change on the server meanwhile.
    context.container.invalidate(_board);
  }

  void _perform(Automation automation, AutomationAction action) {
    context.container.read(_board.notifier).perform(automation, action);
    if (action == AutomationAction.runNow) {
      // The run shows in the history once it starts.
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        context.container.invalidate(
          automationRunsProvider(
            component.instanceId,
            automation.id,
            profile: component.profile,
          ),
        );
      });
    }
  }

  @override
  Component build(BuildContext context) => HermuseWatch(
    provider: _board,
    builder: (context, async) {
      final board = async.value;
      if (board == null) {
        if (async.error case final error?) {
          return div(classes: 'hermuse-upcoming', [
            p(classes: 'hermuse-upcoming-error', [
              .text('Could not load upcoming: ${hermuseErrorText(error)}'),
            ]),
            div([
              YsButton.neutral(
                label: 'Retry',
                onPressed: () => context.container.invalidate(_board),
              ),
            ]),
          ]);
        }
        return p(
          classes: 'hermuse-upcoming-note',
          attributes: {'role': 'status'},
          [.text('Loading upcoming…')],
        );
      }
      final open = _openId == null
          ? null
          : board.automations.where((job) => job.id == _openId).firstOrNull;
      return div(classes: 'hermuse-upcoming', [
        if (board.error case final error?)
          p(
            classes: 'hermuse-upcoming-error',
            attributes: {'role': 'alert'},
            [.text(error)],
          ),
        if (board.schedulerStopped)
          p(classes: 'hermuse-upcoming-note', [
            .text(
              "The scheduler isn't running on this server: scheduled items "
              'only run when started here until the Hermes gateway runs.',
            ),
          ]),
        if (board.sections.isEmpty)
          const HermusePanelEmpty(
            PanelTab.upcoming,
            help: 'Ask your agent: "Every morning at 8, send me…"',
          )
        else
          for (final section in board.sections) ...[
            h2(classes: 'hermuse-panel-heading', [.text(section.group.label)]),
            for (final automation in section.automations)
              _row(automation, board.busy[automation.id]),
          ],
        if (open != null)
          YsDialog(
            key: ValueKey('upcoming:${open.id}'),
            title: open.name,
            onClose: () => setState(() => _openId = null),
            actions: _actions(open, board.busy[open.id]),
            child: _UpcomingDetail(
              instanceId: component.instanceId,
              profile: component.profile,
              automation: open,
              error: board.error,
            ),
          ),
        if (_deleting case final deleting?)
          YsDialog(
            title: 'Delete this item?',
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
    final heartbeat = automation.group == UpcomingGroup.heartbeat;
    return YsPressable(
      classes: 'hermuse-activity hermuse-activity-link',
      label: 'Open ${automation.name}',
      onPressed: () => setState(() => _openId = automation.id),
      builder: (context, state) => span(classes: 'hermuse-activity-row', [
        div(
          classes: heartbeat
              ? 'hermuse-activity-icon hermuse-upcoming-heart'
              : 'hermuse-activity-icon',
          [YsIconView(heartbeat ? YsIcon.heart : YsIcon.upcoming, size: 18)],
        ),
        div(classes: 'hermuse-activity-body', [
          p(classes: 'hermuse-activity-title', [.text(automation.name)]),
          p(classes: 'hermuse-activity-desc', [
            .text(_subtitle(automation, busy)),
          ]),
        ]),
      ]),
    );
  }

  List<Component> _actions(Automation automation, AutomationAction? busy) => [
    for (final action in automation.actions)
      if (action == AutomationAction.delete)
        YsButton.destructive(
          label: 'Delete',
          onPressed: busy != null
              ? null
              : () => setState(() {
                  _openId = null;
                  _deleting = automation;
                }),
        )
      else if (action == AutomationAction.runNow)
        YsButton.primary(
          label: busy == action ? 'Running…' : 'Run now',
          onPressed: busy != null ? null : () => _perform(automation, action),
        )
      else
        YsButton.neutral(
          label: switch ((action, busy == action)) {
            (AutomationAction.pause, true) => 'Pausing…',
            (AutomationAction.pause, false) => 'Pause',
            (_, true) => 'Resuming…',
            _ => 'Resume',
          },
          onPressed: busy != null ? null : () => _perform(automation, action),
        ),
  ];
}

/// The row's line: what is happening to it, else when it runs.
String _subtitle(Automation automation, AutomationAction? busy) {
  final when = automation.group == UpcomingGroup.reminders
      ? switch (automation.nextRunAt) {
          final next? => formatUpcomingDate(next),
          null => automation.schedule,
        }
      : automation.schedule;
  return switch (busy) {
    AutomationAction.pause => 'Pausing…',
    AutomationAction.resume => 'Resuming…',
    AutomationAction.runNow => 'Running…',
    AutomationAction.delete => 'Deleting…',
    null when automation.paused => '$when · Paused',
    null => when,
  };
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct 4, 9:15 AM" (local time): when a one-shot reminder fires.
String formatUpcomingDate(DateTime at) {
  final local = at.toLocal();
  return '${_months[local.month - 1]} ${local.day}, '
      '${formatChatTime(local)}';
}

/// The detail dialog's body: schedule, next/last run and run history.
class _UpcomingDetail extends StatelessComponent {
  const _UpcomingDetail({
    required this.instanceId,
    required this.profile,
    required this.automation,
    required this.error,
  });

  final String instanceId;
  final String profile;
  final Automation automation;

  /// The last action's refusal (also shown above the list).
  final String? error;

  @override
  Component build(BuildContext context) {
    final next = automation.nextRunAt;
    final failed = automation.lastOutcome == AutomationOutcome.failed;
    return .fragment([
      if (error case final error?)
        p(
          classes: 'hermuse-upcoming-error',
          attributes: {'role': 'alert'},
          [.text(error)],
        ),
      dl(classes: 'hermuse-upcoming-facts', [
        dt([.text('Schedule')]),
        dd([.text(automation.schedule)]),
        dt([.text('Next run')]),
        dd([
          .text(switch (next) {
            _ when automation.paused => 'Paused',
            final next? => formatAutomationTime(next),
            null => 'Not scheduled',
          }),
        ]),
        if (failed && automation.lastError.isNotEmpty) ...[
          dt([.text('Last error')]),
          dd(classes: 'hermuse-upcoming-failed', [.text(automation.lastError)]),
        ],
        if (automation.lastDeliveryError.isNotEmpty) ...[
          dt([.text('Not delivered')]),
          dd(classes: 'hermuse-upcoming-failed', [
            .text(automation.lastDeliveryError),
          ]),
        ],
      ]),
      h3(classes: 'hermuse-upcoming-history-head', [.text('Run history')]),
      HermuseWatch(
        provider: automationRunsProvider(
          instanceId,
          automation.id,
          profile: profile,
        ),
        builder: (context, runs) {
          final list = runs.value;
          if (list == null) {
            return p(
              classes: runs.hasError
                  ? 'hermuse-upcoming-error'
                  : 'hermuse-upcoming-note',
              attributes: {'role': 'status'},
              [
                .text(
                  runs.hasError
                      ? 'Could not load the run history: ${hermuseErrorText(runs.error!)}'
                      : 'Loading run history…',
                ),
              ],
            );
          }
          if (list.isEmpty) {
            return p(classes: 'hermuse-upcoming-note', [
              .text('Has not run yet'),
            ]);
          }
          return ul(classes: 'hermuse-upcoming-runs', [
            for (final run in list)
              li(classes: 'hermuse-upcoming-run', [
                div(classes: 'hermuse-upcoming-run-head', [
                  span([.text(formatAutomationTime(run.startedAt))]),
                  span(
                    classes: run.status == AutomationRunStatus.failed
                        ? 'hermuse-upcoming-failed'
                        : null,
                    [
                      .text(switch (run.status) {
                        AutomationRunStatus.running => 'Running',
                        AutomationRunStatus.ok => 'Done',
                        AutomationRunStatus.failed => 'Failed',
                      }),
                    ],
                  ),
                ]),
                if (run.output.isNotEmpty)
                  p(classes: 'hermuse-upcoming-run-output', [
                    .text(run.output),
                  ]),
              ]),
          ]);
        },
      ),
    ]);
  }
}
