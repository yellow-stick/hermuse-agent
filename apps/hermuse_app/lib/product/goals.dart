import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart' show formatTimestamp;
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/agents.dart' show nativeAgentProfileProvider;
import 'plugin_gate.dart';
import 'route.dart';
import 'widgets.dart';

/// Goals: "Tracking" (goals the agent set itself) and "Goals" (the user's),
/// each a checklist with its subgoals nested under it and a "…" menu
/// (Complete, Add subgoal, Rename, Delete); "Create a goal" categories; a
/// detail dialog with the summary and dated timeline.
final class GoalsScreen extends StatelessWidget {
  const GoalsScreen({required this.instance, super.key});

  final HermesInstance instance;

  @override
  Widget build(BuildContext context) => PluginGate(
    instance: instance,
    title: 'Goals',
    child: _Goals(instanceId: instance.id),
  );
}

String goalCategoryLabel(String category) => switch (category) {
  'health' => 'Health',
  'relationships' => 'Relationships',
  'finance' => 'Finance',
  'career' => 'Career',
  'interests' => 'Interests',
  'productivity' => 'Productivity',
  _ => 'Something else',
};

/// The dialog open over the Goals page.
sealed class _GoalDialog {
  const _GoalDialog();
}

final class _DetailDialog extends _GoalDialog {
  const _DetailDialog(this.goalId);

  final String goalId;
}

final class _CreateDialog extends _GoalDialog {
  const _CreateDialog(this.category);

  final String category;
}

final class _SubgoalDialog extends _GoalDialog {
  const _SubgoalDialog(this.parent);

  final Goal parent;
}

final class _RenameDialog extends _GoalDialog {
  const _RenameDialog(this.goal);

  final Goal goal;
}

final class _DeleteDialog extends _GoalDialog {
  const _DeleteDialog(this.goal);

  final Goal goal;
}

final class _Goals extends ConsumerStatefulWidget {
  const _Goals({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_Goals> createState() => _GoalsState();
}

final class _GoalsState extends ConsumerState<_Goals> {
  _GoalDialog? _shown;

  /// The goal dialogs open in the app overlay: their scrim covers the whole
  /// window (rail, panel, side-by-side chat), like the other dialogs.
  final _dialog = OverlayPortalController();

  Goals get _goals => ref.read(
    goalsProvider(
      widget.instanceId,
      profile: ref.read(nativeAgentProfileProvider),
    ).notifier,
  );

  void _open(_GoalDialog dialog) {
    setState(() => _shown = dialog);
    _dialog.show();
  }

  void _close() {
    _dialog.hide();
    setState(() => _shown = null);
  }

  Widget _overlay(List<Goal> all) => switch (_shown) {
    null => const SizedBox.shrink(),
    _DetailDialog(:final goalId) => switch (all
        .where((goal) => goal.id == goalId)
        .firstOrNull) {
      final goal? => YsDialog(
        title: goal.title,
        onClose: _close,
        child: _GoalDetail(instanceId: widget.instanceId, goal: goal),
      ),
      null => const SizedBox.shrink(),
    },
    _CreateDialog(:final category) => YsDialog(
      title: 'New ${goalCategoryLabel(category).toLowerCase()} goal',
      onClose: _close,
      child: _GoalCreate(
        instanceId: widget.instanceId,
        category: category,
        onCreated: _close,
      ),
    ),
    _SubgoalDialog(:final parent) => YsDialog(
      title: 'Add subgoal',
      onClose: _close,
      child: _GoalPrompt(
        placeholder: 'Subgoal title',
        action: 'Add',
        busyAction: 'Adding…',
        onCancel: _close,
        onSubmit: (title) async {
          await _goals.addSubgoal(parent: parent, title: title);
          if (mounted) _close();
        },
      ),
    ),
    _RenameDialog(:final goal) => YsDialog(
      title: 'Rename goal',
      onClose: _close,
      child: _GoalPrompt(
        initial: goal.title,
        placeholder: 'Goal title',
        action: 'Rename',
        busyAction: 'Renaming…',
        onCancel: _close,
        onSubmit: (title) async {
          await _goals.rename(goal.id, title);
          if (mounted) _close();
        },
      ),
    ),
    _DeleteDialog(:final goal) => YsDialog(
      title: 'Delete this goal?',
      onClose: _close,
      child: _GoalDelete(
        onCancel: _close,
        onDelete: () async {
          await _goals.delete(goal.id);
          if (mounted) _close();
        },
      ),
    ),
  };

  /// [goal]'s row, then its subgoals' rows (indented one step deeper).
  Iterable<Widget> _tree(Goal goal, GoalSections sections, int depth) sync* {
    yield Padding(
      key: ValueKey(goal.id),
      padding: EdgeInsets.only(left: depth * YsSpace.xl),
      child: _GoalRow(
        instanceId: widget.instanceId,
        goal: goal,
        onOpen: () => _open(_DetailDialog(goal.id)),
        onAddSubgoal: () => _open(_SubgoalDialog(goal)),
        onRename: () => _open(_RenameDialog(goal)),
        onDelete: () => _open(_DeleteDialog(goal)),
      ),
    );
    for (final sub in sections.subgoalsOf(goal)) {
      yield* _tree(sub, sections, depth + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(
      goalsProvider(
        widget.instanceId,
        profile: ref.watch(nativeAgentProfileProvider),
      ),
    );
    final all = goals.value ?? const <Goal>[];
    final sections = goalSections(all);
    return OverlayPortal(
      controller: _dialog,
      overlayChildBuilder: (context) => _overlay(all),
      child: HermuseRoute(
        title: 'Goals',
        children: [
          if (goals.isLoading && goals.value == null)
            const HermuseRouteSub('Loading goals…')
          else if (goals.hasError && goals.value == null)
            HermuseRouteError('Goals failed: ${goals.error}')
          else ...[
            if (sections.tracking.isNotEmpty)
              HermuseRouteSection(
                head: 'Tracking',
                accent: true,
                children: [
                  for (final goal in sections.tracking)
                    ..._tree(goal, sections, 0),
                ],
              ),
            HermuseRouteSection(
              head: 'Goals',
              children: [
                if (sections.goals.isEmpty)
                  HermuseRouteEmpty(
                    art: YsArt.goals,
                    size: YsLayout.artCompact,
                    top: 0,
                    title: 'No goals yet',
                    body: 'Pick a category below to set your first goal.',
                  )
                else
                  for (final goal in sections.goals)
                    ..._tree(goal, sections, 0),
              ],
            ),
            HermuseRouteSection(
              head: 'Create a goal',
              children: [
                for (final category in hermuseGoalCategories)
                  _CategoryRow(
                    label: goalCategoryLabel(category),
                    onPressed: () => _open(_CreateDialog(category)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

final class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: 'Create a $label goal',
      builder: (context, state) => YsLift(
        lifted: state.hovered,
        pressed: state.pressed,
        radius: YsRadius.row,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: YsMotion.fast),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: state.hovered || state.pressed
                ? palette.neutralFilmColor
                : palette.paperColor,
            borderRadius: BorderRadius.circular(YsRadius.row),
            // At rest only: hovered, the lift's own shadow takes over.
            boxShadow: state.hovered || state.pressed
                ? const []
                : palette.raisedShadows,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: YsType.navRow.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                ),
              ),
              YsIconWidget(
                YsIcon.chevronDown,
                size: 18,
                color: state.hovered
                    ? palette.primaryInkColor
                    : palette.contentMutedColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Goal row: the box completes (or reopens) the goal, the body opens the
/// detail, "…" holds Complete, Add subgoal, Rename and Delete.
///
/// Marked done, the box fills, its tick draws and sparks fly out
/// ([YsDoneBox]); the row stays, ticked, its title muted.
final class _GoalRow extends ConsumerStatefulWidget {
  const _GoalRow({
    required this.instanceId,
    required this.goal,
    required this.onOpen,
    required this.onAddSubgoal,
    required this.onRename,
    required this.onDelete,
  });

  final String instanceId;
  final Goal goal;
  final VoidCallback onOpen;
  final VoidCallback onAddSubgoal;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  ConsumerState<_GoalRow> createState() => _GoalRowState();
}

final class _GoalRowState extends ConsumerState<_GoalRow> {
  /// The done state asked for, shown until the server answers.
  bool? _pending;
  var _menuOpen = false;
  String? _error;

  Future<void> _toggle() async {
    final done = !widget.goal.done;
    setState(() {
      _pending = done;
      _error = null;
    });
    try {
      await ref
          .read(
            goalsProvider(
              widget.instanceId,
              profile: ref.read(nativeAgentProfileProvider),
            ).notifier,
          )
          .complete(widget.goal.id, done: done);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _pending = null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final goal = widget.goal;
    final done = _pending ?? goal.done;
    final busy = _pending != null;
    return YsHover(
      builder: (context, hovered) {
        final lifted = (hovered || _menuOpen) && !done;
        return YsLift(
          lifted: lifted,
          radius: YsRadius.row,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.paperColor,
              borderRadius: BorderRadius.circular(YsRadius.row),
              // At rest only: hovered, the lift's own shadow takes over.
              boxShadow: lifted ? const [] : palette.raisedShadows,
            ),
            child: Padding(
              padding: const EdgeInsets.only(
                left: YsSpace.lg,
                right: YsSpace.sm,
                top: YsSpace.md,
                bottom: YsSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      YsPressable(
                        onPressed: busy ? null : () => unawaited(_toggle()),
                        semanticLabel: done
                            ? 'Mark ${goal.title} not done'
                            : 'Mark ${goal.title} complete',
                        builder: (context, state) => Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: YsDoneBox(done: done, hovered: state.hovered),
                        ),
                      ),
                      const SizedBox(width: YsSpace.md),
                      Expanded(
                        child: YsPressable(
                          onPressed: widget.onOpen,
                          semanticLabel: 'Open ${goal.title}',
                          builder: (context, state) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal.title,
                                style: YsType.navRow.flutter.copyWith(
                                  color: done
                                      ? palette.contentMutedColor
                                      : palette.contentColor,
                                ),
                              ),
                              if (goal.statusLine.isNotEmpty)
                                Text(
                                  goal.statusLine,
                                  style: YsType.small.flutter.copyWith(
                                    color: palette.contentMutedColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: YsSpace.sm),
                      YsMenuAnchor(
                        semanticLabel: 'Goal actions',
                        onOpenChanged: (open) =>
                            setState(() => _menuOpen = open),
                        items: [
                          YsMenuItem(
                            label: done ? 'Mark not done' : 'Complete',
                            icon: YsIcon.check,
                            onSelected: () => unawaited(_toggle()),
                          ),
                          YsMenuItem(
                            label: 'Add subgoal',
                            icon: YsIcon.plus,
                            onSelected: widget.onAddSubgoal,
                          ),
                          YsMenuItem(
                            label: 'Rename',
                            icon: YsIcon.pencil,
                            onSelected: widget.onRename,
                          ),
                          YsMenuItem(
                            label: 'Delete',
                            icon: YsIcon.trash,
                            destructive: true,
                            onSelected: widget.onDelete,
                          ),
                        ],
                        builder: (context, menu) => YsButton.icon(
                          icon: YsIcon.more,
                          onPressed: busy ? null : () => menu.open(),
                          semanticLabel: 'More actions for ${goal.title}',
                          tooltip: 'More',
                          iconSize: YsLayout.inlineIcon,
                        ),
                      ),
                    ],
                  ),
                  if (_error case final error?) HermuseRouteError(error),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Add subgoal" / "Rename": one title field, Cancel and [action]. A failed
/// call keeps the dialog open with its error.
final class _GoalPrompt extends StatefulWidget {
  const _GoalPrompt({
    required this.placeholder,
    required this.action,
    required this.busyAction,
    required this.onCancel,
    required this.onSubmit,
    this.initial = '',
  });

  final String initial;
  final String placeholder;
  final String action;
  final String busyAction;
  final VoidCallback onCancel;
  final Future<void> Function(String title) onSubmit;

  @override
  State<_GoalPrompt> createState() => _GoalPromptState();
}

final class _GoalPromptState extends State<_GoalPrompt> {
  late final _title = TextEditingController(text: widget.initial);
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_busy &&
      _title.text.trim().isNotEmpty &&
      _title.text.trim() != widget.initial.trim();

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_title.text.trim());
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _title,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsInputBox(
          controller: _title,
          placeholder: widget.placeholder,
          semanticLabel: widget.placeholder,
          autofocus: true,
          onSubmitted: (_) => unawaited(_submit()),
        ),
        if (_error case final error?) HermuseRouteError(error),
        const SizedBox(height: YsSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            YsButton.neutral(
              label: 'Cancel',
              onPressed: _busy ? null : widget.onCancel,
            ),
            const SizedBox(width: YsSpace.md),
            YsButton.primary(
              label: _busy ? widget.busyAction : widget.action,
              onPressed: _ready ? () => unawaited(_submit()) : null,
            ),
          ],
        ),
      ],
    ),
  );
}

/// "Delete this goal?" body: the warning, Cancel and Delete.
final class _GoalDelete extends StatefulWidget {
  const _GoalDelete({required this.onCancel, required this.onDelete});

  final VoidCallback onCancel;
  final Future<void> Function() onDelete;

  @override
  State<_GoalDelete> createState() => _GoalDeleteState();
}

final class _GoalDeleteState extends State<_GoalDelete> {
  var _busy = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          "This can't be undone. The goal and its history will be removed.",
          style: YsType.small.flutter.copyWith(color: palette.contentColor),
        ),
        if (_error case final error?) HermuseRouteError(error),
        const SizedBox(height: YsSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            YsButton.neutral(
              label: 'Cancel',
              onPressed: _busy ? null : widget.onCancel,
            ),
            const SizedBox(width: YsSpace.md),
            YsButton.destructive(
              label: _busy ? 'Deleting…' : 'Delete',
              onPressed: _busy ? null : () => unawaited(_delete()),
            ),
          ],
        ),
      ],
    );
  }
}

/// Summary, dated timeline and the append-update row.
final class _GoalDetail extends ConsumerStatefulWidget {
  const _GoalDetail({required this.instanceId, required this.goal});

  final String instanceId;
  final Goal goal;

  @override
  ConsumerState<_GoalDetail> createState() => _GoalDetailState();
}

final class _GoalDetailState extends ConsumerState<_GoalDetail> {
  final _note = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _append() async {
    final note = _note.text.trim();
    if (note.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(
            goalsProvider(
              widget.instanceId,
              profile: ref.read(nativeAgentProfileProvider),
            ).notifier,
          )
          .updateGoal(goalId: widget.goal.id, note: note);
      if (mounted) setState(_note.clear);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final goal = widget.goal;
    final subtle = YsType.caption.flutter.copyWith(
      color: palette.contentSubtleColor,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (goal.why.isNotEmpty)
          Text(
            goal.why,
            style: YsType.body.flutter.copyWith(color: palette.contentColor),
          ),
        if (goal.targetDate.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Target: ${goal.targetDate}', style: subtle),
        ],
        for (final event in goal.timeline) ...[
          const SizedBox(height: 12),
          Text(
            event.note,
            style: YsType.small.flutter.copyWith(color: palette.contentColor),
          ),
          Text(
            [
              formatTimestamp(event.at, DateTime.now()),
              if (event.progress.isNotEmpty) event.progress,
            ].join(' · '),
            style: subtle,
          ),
        ],
        const SizedBox(height: 16),
        ProductInputRow(
          controller: _note,
          placeholder: 'Add an update…',
          action: 'Add',
          busy: _busy,
          onSubmit: () => unawaited(_append()),
        ),
        if (_error case final error?) HermuseRouteError(error),
      ],
    );
  }
}

final class _GoalCreate extends ConsumerStatefulWidget {
  const _GoalCreate({
    required this.instanceId,
    required this.category,
    required this.onCreated,
  });

  final String instanceId;
  final String category;
  final VoidCallback onCreated;

  @override
  ConsumerState<_GoalCreate> createState() => _GoalCreateState();
}

final class _GoalCreateState extends ConsumerState<_GoalCreate> {
  final _title = TextEditingController();
  final _why = TextEditingController();
  final _target = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _why.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(
            goalsProvider(
              widget.instanceId,
              profile: ref.read(nativeAgentProfileProvider),
            ).notifier,
          )
          .create(
            title: _title.text.trim(),
            category: widget.category,
            why: _why.text.trim(),
            targetDate: _target.text.trim(),
          );
      if (mounted) widget.onCreated();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_title, _why]),
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        YsField(
          label: 'Title',
          child: YsInputBox(
            controller: _title,
            placeholder: 'What do you want to track?',
            semanticLabel: 'Goal title',
          ),
        ),
        const SizedBox(height: 12),
        YsField(
          label: 'Why',
          child: YsTextBox(
            controller: _why,
            placeholder: 'Why does it matter?',
            semanticLabel: 'Goal why',
            minHeight: 80,
            maxHeight: 200,
          ),
        ),
        const SizedBox(height: 12),
        YsField(
          label: 'Target date (optional)',
          child: YsInputBox(
            controller: _target,
            placeholder: '2026-12-31',
            semanticLabel: 'Goal target date',
          ),
        ),
        if (_error case final error?) HermuseRouteError(error),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: YsButton.primary(
            label: _busy ? 'Creating…' : 'Create goal',
            onPressed:
                _busy || _title.text.trim().isEmpty || _why.text.trim().isEmpty
                ? null
                : () => unawaited(_create()),
          ),
        ),
      ],
    ),
  );
}
