import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'feed.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Goals: Tracking checklist + "Create a goal" categories + detail dialog
/// with summary and dated activity timeline.
class HermuseGoals extends StatefulComponent {
  const HermuseGoals({required this.instance, super.key});

  final HermesInstance instance;

  @override
  State<HermuseGoals> createState() => _HermuseGoalsState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-goals-tracking').styles(color: .variable('--success')),
    css('.hermuse-goals-left').styles(textAlign: .left),
    css('.hermuse-goals-row').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(12.px),
    ),
    css('.hermuse-goals-check').styles(
      width: 36.px,
      height: 36.px,
      padding: .zero,
      display: .flex,
      justifyContent: .center,
      alignItems: .center,
      color: .variable('--content-muted'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-goals-box').styles(
      width: 20.px,
      height: 20.px,
      radius: .circular(6.px),
      border: .all(
        style: .solid,
        color: .variable('--content-subtle'),
        width: 1.2.px,
      ),
    ),
    css('.hermuse-goals-body').styles(
      flex: .grow(1),
      display: .flex,
      flexDirection: .column,
      gap: .all(2.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      padding: .zero,
      textAlign: .left,
      raw: {'min-width': '0'},
    ),
    css('.hermuse-goals-title')
        .styles(fontSize: 15.px, lineHeight: 20.px, fontWeight: .w600),
    css('.hermuse-goals-why').styles(
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--content-muted'),
      overflow: .hidden,
      textOverflow: .ellipsis,
      raw: {
        'display': '-webkit-box',
        '-webkit-line-clamp': '2',
        '-webkit-box-orient': 'vertical',
      },
    ),
    css('.hermuse-goals-category').styles(
      width: 100.percent,
      padding: .symmetric(vertical: 12.px, horizontal: 4.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(12.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      fontSize: 15.px,
      lineHeight: 22.px,
    ),
    css('.hermuse-goals-category:hover')
        .styles(backgroundColor: .variable('--neutral-film')),
    css('.hermuse-goals-category-label').styles(flex: .grow(1)),
    css('.hermuse-goals-timeline')
        .styles(display: .flex, flexDirection: .column, gap: .all(12.px)),
    css('.hermuse-goals-event')
        .styles(display: .flex, flexDirection: .column, gap: .all(2.px)),
    css('.hermuse-goals-event-note').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      fontWeight: .w500,
    ),
    css('.hermuse-goals-event-at').styles(
      margin: .zero,
      fontSize: 12.px,
      lineHeight: 16.px,
      color: .variable('--content-subtle'),
    ),
    css('.hermuse-ob-row').styles(
      width: 100.percent,
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(8.px),
    ),
    css('.hermuse-ob-grow').styles(flex: .grow(1)),
  ];
}

class _HermuseGoalsState extends State<HermuseGoals> {
  String? _detailId;
  String? _createCategory;

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: component.instance,
    title: 'Goals',
    child: HermuseWatch(
      provider: goalsProvider(component.instance.id),
      builder: (context, goals) => _body(context, goals),
    ),
  );

  Component _body(BuildContext context, AsyncValue<List<Goal>> goals) {
    final all = goals.value ?? const <Goal>[];
    final tracking = [
      for (final goal in all)
        if (goal.status == GoalStatus.tracking) goal,
    ];
    final detail = _detailId == null
        ? null
        : all.where((goal) => goal.id == _detailId).firstOrNull;
    return div(classes: 'hermuse-route', [
      div(classes: 'hermuse-route-column', [
        div(classes: 'hermuse-route-head', [
          h1(classes: 'hermuse-route-title', [.text('Goals')]),
        ]),
        if (goals.isLoading && goals.value == null)
          p(classes: 'hermuse-route-sub', [.text('Loading goals…')])
        else if (goals.hasError && goals.value == null)
          p(classes: 'hermuse-route-error', [
            .text('Goals failed: ${goals.error}'),
          ])
        else ...[
          div(classes: 'hermuse-route-section', [
            h2(classes: 'hermuse-route-section-head hermuse-goals-tracking', [
              .text('Tracking'),
            ]),
            if (tracking.isEmpty)
              p(classes: 'hermuse-route-sub', [
                .text('Nothing tracked yet. Create your first goal below.'),
              ])
            else
              for (final goal in tracking)
                _TrackingRow(
                  key: ValueKey(goal.id),
                  instanceId: component.instance.id,
                  goal: goal,
                  onOpen: () => setState(() => _detailId = goal.id),
                ),
          ]),
          div(classes: 'hermuse-route-section', [
            h2(classes: 'hermuse-route-section-head', [.text('Create a goal')]),
            for (final category in hermuseGoalCategories)
              YsPressable(
                onPressed: () => setState(() => _createCategory = category),
                label: 'Create a ${_goalLabel(category)} goal',
                classes: 'hermuse-goals-category',
                builder: (context, press) => .fragment([
                  span(classes: 'hermuse-goals-category-label', [
                    .text(_goalLabel(category)),
                  ]),
                  YsIconView(YsIcon.chevronDown, size: 18),
                ]),
              ),
          ]),
        ],
      ]),
      if (detail != null)
        YsDialog(
          title: detail.title,
          onClose: () => setState(() => _detailId = null),
          child: _GoalDetail(
            instanceId: component.instance.id,
            goal: detail,
            onChanged: () => setState(() {}),
          ),
        ),
      if (_createCategory case final category?)
        YsDialog(
          title: 'New ${_goalLabel(category).toLowerCase()} goal',
          onClose: () => setState(() => _createCategory = null),
          child: _GoalCreate(
            instanceId: component.instance.id,
            category: category,
            onCreated: () => setState(() => _createCategory = null),
          ),
        ),
    ]);
  }

  static String _goalLabel(String category) => switch (category) {
    'health' => 'Health',
    'relationships' => 'Relationships',
    'finance' => 'Finance',
    'career' => 'Career',
    'interests' => 'Interests',
    'productivity' => 'Productivity',
    _ => 'Something else',
  };
}

/// One Tracking row: checkbox flips to done, body opens the detail dialog.
class _TrackingRow extends StatefulComponent {
  const _TrackingRow({
    required this.instanceId,
    required this.goal,
    required this.onOpen,
    super.key,
  });

  final String instanceId;
  final Goal goal;
  final VoidCallback onOpen;

  @override
  State<_TrackingRow> createState() => _TrackingRowState();
}

class _TrackingRowState extends State<_TrackingRow> {
  var _busy = false;

  @override
  Component build(BuildContext context) => div(classes: 'hermuse-goals-row', [
    YsPressable(
      onPressed: _busy ? null : () => unawaited(_complete(context)),
      label: 'Mark ${component.goal.title} complete',
      classes: 'hermuse-goals-check',
      builder: (context, press) => div(classes: 'hermuse-goals-box', []),
    ),
    YsPressable(
      onPressed: component.onOpen,
      label: 'Open ${component.goal.title}',
      classes: 'hermuse-goals-body',
      builder: (context, press) => .fragment([
        span(classes: 'hermuse-goals-title', [.text(component.goal.title)]),
        if (component.goal.why.isNotEmpty)
          span(classes: 'hermuse-goals-why', [.text(component.goal.why)]),
      ]),
    ),
  ]);

  Future<void> _complete(BuildContext context) async {
    setState(() => _busy = true);
    try {
      await context.container
          .read(goalsProvider(component.instanceId).notifier)
          .updateGoal(
            goalId: component.goal.id,
            note: 'Marked complete.',
            status: GoalStatus.done,
          );
    } on Object catch (_) {
      // The list refresh shows the truth.
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Goal detail: summary + dated timeline + append-note row.
class _GoalDetail extends StatefulComponent {
  const _GoalDetail({
    required this.instanceId,
    required this.goal,
    required this.onChanged,
  });

  final String instanceId;
  final Goal goal;
  final VoidCallback onChanged;

  @override
  State<_GoalDetail> createState() => _GoalDetailState();
}

class _GoalDetailState extends State<_GoalDetail> {
  var _note = '';
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) {
    final goal = component.goal;
    return .fragment([
      if (goal.why.isNotEmpty)
        p(classes: 'hermuse-card-body hermuse-goals-left', [.text(goal.why)]),
      if (goal.targetDate.isNotEmpty)
        p(classes: 'hermuse-goals-event-at', [
          .text('Target: ${goal.targetDate}'),
        ]),
      div(classes: 'hermuse-goals-timeline', [
        for (final event in goal.timeline)
          div(classes: 'hermuse-goals-event', [
            p(classes: 'hermuse-goals-event-note', [.text(event.note)]),
            p(classes: 'hermuse-goals-event-at', [
              .text(
                [
                  event.at,
                  if (event.progress.isNotEmpty) event.progress,
                ].join(' · '),
              ),
            ]),
          ]),
      ]),
      div(classes: 'hermuse-ob-row', [
        div(classes: 'hermuse-ob-grow', [
          YsInputBox(
            value: _note,
            onChanged: (v) => setState(() => _note = v),
            onSubmitted: () => unawaited(_append(context)),
            placeholder: 'Add an update…',
            name: 'goal-note-${goal.id}',
            label: 'Goal update',
          ),
        ]),
        YsButton.primary(
          label: _busy ? '…' : 'Add',
          onPressed: _busy || _note.trim().isEmpty
              ? null
              : () => unawaited(_append(context)),
        ),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
    ]);
  }

  Future<void> _append(BuildContext context) async {
    final note = _note.trim();
    if (note.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.container
          .read(goalsProvider(component.instanceId).notifier)
          .updateGoal(goalId: component.goal.id, note: note);
      if (mounted) setState(() => _note = '');
      component.onChanged();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Create form for one category.
class _GoalCreate extends StatefulComponent {
  const _GoalCreate({
    required this.instanceId,
    required this.category,
    required this.onCreated,
  });

  final String instanceId;
  final String category;
  final VoidCallback onCreated;

  @override
  State<_GoalCreate> createState() => _GoalCreateState();
}

class _GoalCreateState extends State<_GoalCreate> {
  var _title = '';
  var _why = '';
  var _targetDate = '';
  var _busy = false;
  String? _error;

  @override
  Component build(BuildContext context) => .fragment([
    YsField(
      label: 'Title',
      child: YsInputBox(
        value: _title,
        onChanged: (v) => setState(() => _title = v),
        placeholder: 'What do you want to track?',
        name: 'goal-title',
        label: 'Goal title',
      ),
    ),
    YsField(
      label: 'Why',
      child: YsTextBox(
        value: _why,
        onChanged: (v) => setState(() => _why = v),
        placeholder: 'Why does it matter?',
        name: 'goal-why',
        label: 'Goal why',
        minHeight: 80,
        maxHeight: 200,
      ),
    ),
    YsField(
      label: 'Target date (optional)',
      child: YsInputBox(
        value: _targetDate,
        onChanged: (v) => setState(() => _targetDate = v),
        placeholder: '2026-12-31',
        name: 'goal-date',
        label: 'Goal target date',
        autocomplete: 'off',
      ),
    ),
    if (_error case final error?)
      p(classes: 'hermuse-card-error', [.text(error)]),
    div(classes: 'hermuse-ob-row', [
      div(classes: 'hermuse-ob-grow', []),
      YsButton.primary(
        label: _busy ? 'Creating…' : 'Create goal',
        onPressed: _busy || _title.trim().isEmpty || _why.trim().isEmpty
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                try {
                  await context.container
                      .read(goalsProvider(component.instanceId).notifier)
                      .create(
                        title: _title.trim(),
                        category: component.category,
                        why: _why.trim(),
                        targetDate: _targetDate.trim(),
                      );
                  if (mounted) component.onCreated();
                } on Object catch (e) {
                  if (mounted) setState(() => _error = '$e');
                }
                if (mounted) setState(() => _busy = false);
              },
      ),
    ]),
  ]);
}
