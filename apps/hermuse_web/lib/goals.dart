import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show formatTimestamp;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'feed.dart';
import 'route.dart';
import 'route_styles.dart';
import 'scope.dart';
import 'screens.dart';

/// Goals: "Tracking" (goals the agent set itself) above "Goals" (set by the
/// user), subgoals nested under their parent, each row with a done box, its
/// live status line and a "…" menu (Complete, Add subgoal, Rename, Delete);
/// then "Create a goal" categories. A row opens the detail dialog with the
/// summary and dated activity timeline.
class HermuseGoals extends StatefulComponent {
  const HermuseGoals({
    required this.instance,
    required this.profile,
    super.key,
  });

  final HermesInstance instance;
  final String profile;

  @override
  State<HermuseGoals> createState() => _HermuseGoalsState();

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    ...hermuseRouteStyles,
    css('.hermuse-goals-left').styles(textAlign: .left),
    // "Tracking" carries the accent dot of the agent's own work.
    css('.hermuse-goals-head').styles(
      display: .flex,
      flexDirection: .row,
      alignItems: .center,
      gap: .all(YsSpace.sm.px),
    ),
    css('.hermuse-goals-dot').styles(
      width: YsLayout.statusDot.px,
      height: YsLayout.statusDot.px,
      radius: .circular(YsRadius.pill.px),
      backgroundColor: .variable('--primary'),
      raw: {'flex-shrink': '0'},
    ),
    css('.hermuse-goals-note').styles(
      margin: .zero,
      fontSize: 14.px,
      lineHeight: 20.px,
      color: .variable('--content-muted'),
    ),
    css('.hermuse-goals-item')
        .styles(display: .flex, flexDirection: .column, gap: .all(4.px)),
    // A goal: a paper row that lifts under the pointer.
    css('.hermuse-goals-row').styles(
      width: 100.percent,
      padding: .all(YsSpace.sm.px),
      radius: .circular(YsRadius.row.px),
      display: .flex,
      flexDirection: .row,
      alignItems: .start,
      gap: .all(YsSpace.xs.px),
      backgroundColor: .variable('--paper'),
      // Done rows have no `ys-lift`, so they carry the elevation themselves.
      raw: {'box-shadow': 'var(--raised)', '--ys-lift-rest': 'var(--raised)'},
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
    css('.hermuse-goals-body').styles(
      flex: .grow(1),
      padding: .only(top: YsSpace.sm.px),
      display: .flex,
      flexDirection: .column,
      gap: .all(2.px),
      color: .variable('--content'),
      backgroundColor: Colors.transparent,
      cursor: .pointer,
      border: .none,
      textAlign: .left,
      raw: {'min-width': '0'},
    ),
    css('.hermuse-goals-more').styles(
      display: .inlineFlex,
      color: .variable('--content-muted'),
      raw: {'flex-shrink': '0'},
    ),
    css('[data-done] .hermuse-goals-title').styles(
      color: .variable('--content-muted'),
      raw: {'text-decoration': 'line-through'},
    ),
    css('.hermuse-goals-title')
        .styles(fontSize: 15.px, lineHeight: 20.px, fontWeight: .w600),
    css('.hermuse-goals-status').styles(
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
    css('.hermuse-goals-error').styles(
      margin: .zero,
      padding: .symmetric(horizontal: YsSpace.sm.px),
      fontSize: 13.px,
      lineHeight: 18.px,
      color: .variable('--error'),
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
    css('.hermuse-goals-category.ys-lift').styles(
      raw: {
        'transition':
            'background-color ${YsMotion.fast}ms linear, $ysLiftTransition',
      },
    ),
    css('.hermuse-goals-category:hover')
        .styles(backgroundColor: .variable('--neutral-film')),
    css('.hermuse-goals-category:hover .ys-icon')
        .styles(color: .variable('--primary-ink')),
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

/// A title asked in a small dialog: "Add subgoal" or "Rename".
typedef _TitlePrompt = ({
  String key,
  String title,
  String action,
  String initial,
  Future<void> Function(String title) submit,
});

class _HermuseGoalsState extends State<HermuseGoals> {
  String? _detailId;
  String? _createCategory;

  /// The open "…" menu: the goal it acts on and where it opens.
  ({Goal goal, YsMenuAnchor at})? _menu;

  /// The open title dialog (Add subgoal, Rename).
  _TitlePrompt? _prompt;

  /// The goal whose deletion waits for confirmation.
  Goal? _deleting;

  /// Done state shown while a Complete / reopen waits for the server.
  final _pending = <String, bool>{};

  /// Failed done-box / menu actions, by goal id, shown under its row.
  final _errors = <String, String>{};

  Goals get _goals => context.container.read(
    goalsProvider(component.instance.id, profile: component.profile).notifier,
  );

  @override
  Component build(BuildContext context) => HermusePluginGate(
    instance: component.instance,
    title: 'Goals',
    child: HermuseWatch(
      provider: goalsProvider(
        component.instance.id,
        profile: component.profile,
      ),
      builder: (context, goals) => _body(context, goals),
    ),
  );

  Component _body(BuildContext context, AsyncValue<List<Goal>> goals) {
    final all = goals.value ?? const <Goal>[];
    final sections = goalSections(all);
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
            h2(classes: 'hermuse-route-section-head hermuse-goals-head', [
              span(classes: 'hermuse-goals-dot', const []),
              .text('Tracking'),
            ]),
            if (sections.tracking.isEmpty)
              p(classes: 'hermuse-goals-note', [
                .text(
                  'Nothing tracked right now. Commitments I take on, like a '
                  'trip or a weekly briefing, show up here.',
                ),
              ])
            else
              for (final goal in sections.tracking) ..._rows(sections, goal, 0),
          ]),
          div(classes: 'hermuse-route-section', [
            h2(classes: 'hermuse-route-section-head', [.text('Goals')]),
            if (sections.goals.isEmpty)
              HermuseRouteEmpty(
                art: YsArt.goals,
                size: YsLayout.artCompact,
                top: 0,
                title: 'No goals yet',
                body: 'Pick a category below to set your first goal.',
              )
            else
              for (final goal in sections.goals) ..._rows(sections, goal, 0),
          ]),
          div(classes: 'hermuse-route-section', [
            h2(classes: 'hermuse-route-section-head', [.text('Create a goal')]),
            for (final category in hermuseGoalCategories)
              YsPressable(
                onPressed: () => setState(() => _createCategory = category),
                label: 'Create a ${_goalLabel(category)} goal',
                classes: 'hermuse-goals-category ys-lift ys-press',
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
      if (_menu case (:final goal, :final at)) _goalMenu(goal, at),
      if (detail != null)
        YsDialog(
          title: detail.title,
          onClose: () => setState(() => _detailId = null),
          child: _GoalDetail(
            instanceId: component.instance.id,
            profile: component.profile,
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
            profile: component.profile,
            category: category,
            onCreated: () => setState(() => _createCategory = null),
          ),
        ),
      if (_prompt case final prompt?)
        _TitleDialog(
          key: ValueKey(prompt.key),
          prompt: prompt,
          onClose: () => setState(() => _prompt = null),
        ),
      if (_deleting case final goal?)
        _DeleteDialog(
          key: ValueKey('delete:${goal.id}'),
          onConfirm: () => _goals.delete(goal.id),
          onClose: () => setState(() => _deleting = null),
        ),
    ]);
  }

  /// [goal]'s row, then its subgoals indented one level deeper.
  Iterable<Component> _rows(GoalSections sections, Goal goal, int depth) sync* {
    final done = _pending[goal.id] ?? goal.done;
    yield _GoalRow(
      key: ValueKey(goal.id),
      goal: goal,
      done: done,
      depth: depth,
      busy: _pending.containsKey(goal.id),
      menuOpen: _menu?.goal.id == goal.id,
      error: _errors[goal.id],
      onToggle: () => unawaited(_setDone(goal, !done)),
      onOpen: () => setState(() => _detailId = goal.id),
      onMenu: (at) => setState(() => _menu = (goal: goal, at: at)),
    );
    for (final sub in sections.subgoalsOf(goal)) {
      yield* _rows(sections, sub, depth + 1);
    }
  }

  Component _goalMenu(Goal goal, YsMenuAnchor at) {
    final done = _pending[goal.id] ?? goal.done;
    return YsMenu(
      label: 'Actions for ${goal.title}',
      anchor: at,
      onClose: () => setState(() => _menu = null),
      items: [
        YsMenuItem(
          label: done ? 'Mark not done' : 'Complete',
          icon: YsIcon.checkCircle,
          onSelected: () => unawaited(_setDone(goal, !done)),
        ),
        YsMenuItem(
          label: 'Add subgoal',
          icon: YsIcon.plus,
          onSelected: () => setState(
            () => _prompt = (
              key: 'subgoal:${goal.id}',
              title: 'Add a subgoal',
              action: 'Add',
              initial: '',
              submit: (title) => _goals.addSubgoal(parent: goal, title: title),
            ),
          ),
        ),
        YsMenuItem(
          label: 'Rename',
          icon: YsIcon.pencil,
          onSelected: () => setState(
            () => _prompt = (
              key: 'rename:${goal.id}',
              title: 'Rename goal',
              action: 'Save',
              initial: goal.title,
              submit: (title) => _goals.rename(goal.id, title),
            ),
          ),
        ),
        YsMenuItem(
          label: 'Delete',
          icon: YsIcon.trash,
          destructive: true,
          onSelected: () => setState(() => _deleting = goal),
        ),
      ],
    );
  }

  /// Completes (or reopens) [goal]: the box shows [done] at once, the
  /// server's answer settles it; a failure is told under the row.
  Future<void> _setDone(Goal goal, bool done) async {
    if (_pending.containsKey(goal.id)) return;
    setState(() {
      _pending[goal.id] = done;
      _errors.remove(goal.id);
    });
    try {
      await _goals.complete(goal.id, done: done);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _errors[goal.id] =
              'Could not ${done ? 'complete' : 'reopen'} this goal: ${hermuseErrorText(e)}',
        );
      }
    }
    if (mounted) setState(() => _pending.remove(goal.id));
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

/// One goal row: the box marks the goal done (it fills, its tick draws and
/// sparks fly out), the body opens the detail dialog, "…" opens the
/// goal's menu. Subgoals sit [depth] steps in.
class _GoalRow extends StatefulComponent {
  const _GoalRow({
    required this.goal,
    required this.done,
    required this.depth,
    required this.busy,
    required this.menuOpen,
    required this.error,
    required this.onToggle,
    required this.onOpen,
    required this.onMenu,
    super.key,
  });

  final Goal goal;
  final bool done;
  final int depth;
  final bool busy;
  final bool menuOpen;
  final String? error;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final ValueChanged<YsMenuAnchor> onMenu;

  @override
  State<_GoalRow> createState() => _GoalRowState();
}

class _GoalRowState extends State<_GoalRow> {
  final _more = GlobalNodeKey<web.HTMLElement>();

  void _openMenu() {
    final trigger = _more.currentNode;
    if (trigger != null) component.onMenu(YsMenuAnchor.of(trigger));
  }

  @override
  Component build(BuildContext context) {
    final goal = component.goal;
    final done = component.done;
    return div(
      classes: 'hermuse-goals-item',
      styles: component.depth == 0
          ? null
          : Styles(padding: .only(left: (YsSpace.xl * component.depth).px)),
      [
        div(
          classes: done ? 'hermuse-goals-row' : 'hermuse-goals-row ys-lift',
          attributes: {if (done) 'data-done': ''},
          [
            YsPressable(
              onPressed: component.busy ? null : component.onToggle,
              label: done
                  ? 'Mark ${goal.title} not done'
                  : 'Mark ${goal.title} complete',
              classes: 'hermuse-goals-check',
              builder: (context, press) =>
                  YsDoneBox(done: done, hovered: press.hovered),
            ),
            YsPressable(
              onPressed: component.onOpen,
              label: 'Open ${goal.title}',
              classes: 'hermuse-goals-body',
              builder: (context, press) => .fragment([
                span(classes: 'hermuse-goals-title', [.text(goal.title)]),
                if (goal.statusLine.isNotEmpty)
                  span(classes: 'hermuse-goals-status', [
                    .text(goal.statusLine),
                  ]),
              ]),
            ),
            span(key: _more, classes: 'hermuse-goals-more', [
              YsButton.icon(
                icon: YsIcon.more,
                label: 'More actions for ${goal.title}',
                onPressed: _openMenu,
                attributes: {
                  'aria-haspopup': 'menu',
                  'aria-expanded': '${component.menuOpen}',
                },
              ),
            ]),
          ],
        ),
        if (component.error case final error?)
          p(classes: 'hermuse-goals-error', [.text(error)]),
      ],
    );
  }
}

/// "Add subgoal" / "Rename": one title field; the dialog stays open with
/// the server's refusal until it succeeds or is cancelled.
class _TitleDialog extends StatefulComponent {
  const _TitleDialog({required this.prompt, required this.onClose, super.key});

  final _TitlePrompt prompt;
  final VoidCallback onClose;

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

class _TitleDialogState extends State<_TitleDialog> {
  late var _title = component.prompt.initial;
  var _busy = false;
  String? _error;

  bool get _ready => !_busy && _title.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await component.prompt.submit(_title.trim());
      if (mounted) component.onClose();
      return;
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Component build(BuildContext context) => YsDialog(
    title: component.prompt.title,
    onClose: component.onClose,
    actions: [
      YsButton.neutral(label: 'Cancel', onPressed: component.onClose),
      YsButton.primary(
        label: _busy ? 'Saving…' : component.prompt.action,
        onPressed: _ready ? () => unawaited(_submit()) : null,
      ),
    ],
    child: div([
      div(classes: 'hermuse-ob-row', [
        div(classes: 'hermuse-ob-grow', [
          YsInputBox(
            value: _title,
            onChanged: (v) => setState(() => _title = v),
            onSubmitted: () => unawaited(_submit()),
            placeholder: 'Goal title',
            name: 'goal-title-${component.prompt.key}',
            label: 'Goal title',
            autocomplete: 'off',
          ),
        ]),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
    ]),
  );
}

/// Asks before deleting a goal (and its subgoals); a refusal stays in the
/// dialog.
class _DeleteDialog extends StatefulComponent {
  const _DeleteDialog({
    required this.onConfirm,
    required this.onClose,
    super.key,
  });

  final Future<void> Function() onConfirm;
  final VoidCallback onClose;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  var _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await component.onConfirm();
      if (mounted) component.onClose();
      return;
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Component build(BuildContext context) => YsDialog(
    title: 'Delete this goal?',
    onClose: component.onClose,
    actions: [
      YsButton.neutral(label: 'Cancel', onPressed: component.onClose),
      YsButton.destructive(
        label: _busy ? 'Deleting…' : 'Delete',
        onPressed: _busy ? null : () => unawaited(_delete()),
      ),
    ],
    child: div([
      p(classes: 'hermuse-card-body hermuse-goals-left', [
        .text(
          "This can't be undone. The goal and its history will be removed.",
        ),
      ]),
      if (_error case final error?)
        p(classes: 'hermuse-card-error', [.text(error)]),
    ]),
  );
}

/// Goal detail: summary + dated timeline + append-note row.
class _GoalDetail extends StatefulComponent {
  const _GoalDetail({
    required this.instanceId,
    required this.profile,
    required this.goal,
    required this.onChanged,
  });

  final String instanceId;
  final String profile;
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
      if (goal.statusLine.isNotEmpty)
        p(classes: 'hermuse-goals-note', [.text(goal.statusLine)]),
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
                  formatTimestamp(event.at, DateTime.now()),
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
          .read(
            goalsProvider(
              component.instanceId,
              profile: component.profile,
            ).notifier,
          )
          .updateGoal(goalId: component.goal.id, note: note);
      if (mounted) {
        setState(() => _note = '');
        component.onChanged();
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = hermuseErrorText(e));
    }
    if (mounted) setState(() => _busy = false);
  }
}

/// Create form for one category.
class _GoalCreate extends StatefulComponent {
  const _GoalCreate({
    required this.instanceId,
    required this.profile,
    required this.category,
    required this.onCreated,
  });

  final String instanceId;
  final String profile;
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
                      .read(
                        goalsProvider(
                          component.instanceId,
                          profile: component.profile,
                        ).notifier,
                      )
                      .create(
                        title: _title.trim(),
                        category: component.category,
                        why: _why.trim(),
                        targetDate: _targetDate.trim(),
                      );
                  if (mounted) component.onCreated();
                } on Object catch (e) {
                  if (mounted) setState(() => _error = hermuseErrorText(e));
                }
                if (mounted) setState(() => _busy = false);
              },
      ),
    ]),
  ]);
}
