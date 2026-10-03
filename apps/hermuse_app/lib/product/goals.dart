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

/// Goals: Tracking checklist + "Create a goal" categories + a detail dialog
/// with the summary and dated timeline.
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

final class _Goals extends ConsumerStatefulWidget {
  const _Goals({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_Goals> createState() => _GoalsState();
}

final class _GoalsState extends ConsumerState<_Goals> {
  String? _detailId;
  String? _createCategory;

  /// Goals marked done here, still on screen while their row celebrates.
  final _leaving = <String>{};

  /// The goal dialogs open in the app overlay: their scrim covers the whole
  /// window (rail, panel, side-by-side chat), like the other dialogs.
  final _dialog = OverlayPortalController();

  void _open(VoidCallback pick) {
    setState(pick);
    _dialog.show();
  }

  void _close() {
    _dialog.hide();
    setState(() {
      _detailId = null;
      _createCategory = null;
    });
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
    final tracking = [
      for (final goal in all)
        if (goal.status == GoalStatus.tracking || _leaving.contains(goal.id))
          goal,
    ];
    final detail = all.where((goal) => goal.id == _detailId).firstOrNull;
    final create = _createCategory;
    return OverlayPortal(
      controller: _dialog,
      overlayChildBuilder: (context) => detail != null
          ? YsDialog(
              title: detail.title,
              onClose: _close,
              child: _GoalDetail(instanceId: widget.instanceId, goal: detail),
            )
          : create != null
          ? YsDialog(
              title: 'New ${goalCategoryLabel(create).toLowerCase()} goal',
              onClose: _close,
              child: _GoalCreate(
                instanceId: widget.instanceId,
                category: create,
                onCreated: _close,
              ),
            )
          : const SizedBox.shrink(),
      child: HermuseRoute(
        title: 'Goals',
        children: [
          if (goals.isLoading && goals.value == null)
            const HermuseRouteSub('Loading goals…')
          else if (goals.hasError && goals.value == null)
            HermuseRouteError('Goals failed: ${goals.error}')
          else ...[
            HermuseRouteSection(
              head: 'Tracking',
              children: [
                if (tracking.isEmpty)
                  HermuseRouteEmpty(
                    art: YsArt.goals,
                    size: YsLayout.artCompact,
                    top: 0,
                    title: 'Nothing tracked yet',
                    body: 'Pick a category below to set your first goal.',
                  )
                else
                  for (final goal in tracking)
                    _TrackingRow(
                      key: ValueKey(goal.id),
                      instanceId: widget.instanceId,
                      goal: goal,
                      onOpen: () => _open(() => _detailId = goal.id),
                      onLeaving: (leaving) => setState(
                        () => leaving
                            ? _leaving.add(goal.id)
                            : _leaving.remove(goal.id),
                      ),
                    ),
              ],
            ),
            HermuseRouteSection(
              head: 'Create a goal',
              children: [
                for (final category in hermuseGoalCategories)
                  _CategoryRow(
                    label: goalCategoryLabel(category),
                    onPressed: () => _open(() => _createCategory = category),
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

/// Tracking row: the box marks the goal done, the body opens the detail.
///
/// Marked done, the box fills, its tick draws and sparks fly out; the row
/// holds a moment ([YsDoneMotion.hold]), then folds away. [onLeaving] keeps
/// the row listed meanwhile, although the goal is no longer tracked.
final class _TrackingRow extends ConsumerStatefulWidget {
  const _TrackingRow({
    required this.instanceId,
    required this.goal,
    required this.onOpen,
    required this.onLeaving,
    super.key,
  });

  final String instanceId;
  final Goal goal;
  final VoidCallback onOpen;
  final ValueChanged<bool> onLeaving;

  @override
  ConsumerState<_TrackingRow> createState() => _TrackingRowState();
}

final class _TrackingRowState extends ConsumerState<_TrackingRow>
    with TickerProviderStateMixin {
  var _busy = false;
  var _done = false;
  String? _error;

  /// The box's tick drawing, then the hold before the row folds.
  late final _hold = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: YsStepMark.tick.durationMs + YsDoneMotion.hold,
    ),
  );

  /// The row's height, folding to nothing once it has celebrated.
  late final _fold = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: YsDoneMotion.fold),
  );

  @override
  void dispose() {
    _hold.dispose();
    _fold.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    final still = MediaQuery.disableAnimationsOf(context);
    widget.onLeaving(true);
    setState(() {
      _busy = true;
      _done = true;
      _error = null;
    });
    try {
      await Future.wait<void>([
        ref
            .read(
              goalsProvider(
                widget.instanceId,
                profile: ref.read(nativeAgentProfileProvider),
              ).notifier,
            )
            .updateGoal(
              goalId: widget.goal.id,
              note: 'Marked complete.',
              status: GoalStatus.done,
            ),
        if (!still) _hold.forward(from: 0),
      ]);
      if (!still && mounted) await _fold.reverse();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _done = false;
          _error = '$e';
        });
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onLeaving(false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final goal = widget.goal;
    return SizeTransition(
      sizeFactor: _fold,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: _fold,
        child: YsHover(
          builder: (context, hovered) => YsLift(
            lifted: hovered && !_done,
            radius: YsRadius.row,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.paperColor,
                borderRadius: BorderRadius.circular(YsRadius.row),
                // At rest only: hovered, the lift's own shadow takes over.
                boxShadow: hovered && !_done ? const [] : palette.raisedShadows,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: YsSpace.lg,
                  vertical: YsSpace.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        YsPressable(
                          onPressed: _busy
                              ? null
                              : () => unawaited(_complete()),
                          semanticLabel: 'Mark ${goal.title} complete',
                          builder: (context, state) => Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: YsDoneBox(
                              done: _done,
                              hovered: state.hovered,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                                    color: _done
                                        ? palette.contentMutedColor
                                        : palette.contentColor,
                                  ),
                                ),
                                if (goal.why.isNotEmpty)
                                  Text(
                                    goal.why,
                                    style: YsType.small.flutter.copyWith(
                                      color: palette.contentMutedColor,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error case final error?) HermuseRouteError(error),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
