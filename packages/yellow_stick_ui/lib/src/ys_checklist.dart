import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_resize.dart';
import 'ys_step_badge.dart';
import 'ys_theme.dart';

/// How a [YsChecklistNote] reads.
enum YsNoteTone {
  /// Explanations.
  muted,

  /// Warnings and errors.
  alert,
}

/// A line under a checklist row that needs the user or failed: what a
/// change does, a warning, an error.
@immutable
final class YsChecklistNote {
  const YsChecklistNote(
    this.text, {
    this.caption,
    this.tone = YsNoteTone.muted,
  });

  final String text;

  /// Short heading above [text] ("Root access").
  final String? caption;
  final YsNoteTone tone;
}

/// One row of a [YsChecklist].
@immutable
final class YsChecklistItem {
  const YsChecklistItem({
    required this.id,
    required this.icon,
    required this.title,
    required this.state,
    this.status = '',
    this.progress,
    this.trailing,
    this.notes = const [],
    this.actions = const [],
  });

  /// Stable identity across rebuilds: the row keeps its animations.
  final Object id;
  final YsIcon icon;
  final String title;
  final YsStepState state;

  /// One line under the title.
  final String status;

  /// Share done of a [YsStepState.working] row, 0..1; null when unknown.
  final double? progress;

  /// A short caption at the end of the title line (`4/10`).
  final String? trailing;

  /// Lines under the status of a row that needs the user or failed.
  final List<YsChecklistNote> notes;

  /// Buttons of a row that needs the user or failed, one per line under its
  /// notes.
  final List<Widget> actions;

  /// Whether the row shows its [notes] and [actions].
  bool get expanded =>
      state == YsStepState.needsAction || state == YsStepState.failed;
}

/// A vertical checklist of setup steps: each row an animated
/// [YsStepBadge], a title and a one-line status. A row that needs the user
/// takes an accent wash, a failed one an error wash; both unfold their
/// notes and actions. Rows enter one after the other; state changes
/// crossfade and heights ease.
///
/// With animations disabled (`MediaQuery.disableAnimations`) rows appear
/// and change at once.
final class YsChecklist extends StatefulWidget {
  const YsChecklist({required this.items, super.key});

  final List<YsChecklistItem> items;

  @override
  State<YsChecklist> createState() => _YsChecklistState();
}

final class _YsChecklistState extends State<YsChecklist> {
  /// Entrance delay of each row, staggered among the rows that appeared
  /// together.
  final _delays = <Object, Duration>{};

  @override
  void initState() {
    super.initState();
    _stagger(const {});
  }

  @override
  void didUpdateWidget(YsChecklist old) {
    super.didUpdateWidget(old);
    _stagger({for (final item in old.items) item.id});
  }

  void _stagger(Set<Object> shown) {
    final ids = {for (final item in widget.items) item.id};
    _delays.removeWhere((id, _) => !ids.contains(id));
    var fresh = 0;
    for (final id in ids) {
      if (shown.contains(id)) continue;
      _delays[id] = Duration(milliseconds: YsStepMotion.stagger * fresh++);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    // Apart, two washed rows in a row stay two rows.
    spacing: YsSpace.xs,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final item in widget.items)
        _Row(
          key: ValueKey(item.id),
          item: item,
          delay: _delays[item.id] ?? Duration.zero,
        ),
    ],
  );
}

final class _Row extends StatefulWidget {
  const _Row({required this.item, required this.delay, super.key});

  final YsChecklistItem item;

  /// When the entrance starts, once, after the row is first built.
  final Duration delay;

  @override
  State<_Row> createState() => _RowState();
}

final class _RowState extends State<_Row> with SingleTickerProviderStateMixin {
  late final _enter = AnimationController(vsync: this);
  late final Animation<double> _shown;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delay = widget.delay.inMilliseconds;
    final total = delay + YsStepMotion.enter;
    _enter.duration = Duration(milliseconds: total);
    _shown = CurvedAnimation(
      parent: _enter,
      curve: Interval(delay / total, 1, curve: YsEase.settle.curve),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
    } else {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final palette = YsTheme.of(context);
    final still = MediaQuery.disableAnimationsOf(context);
    final swap = Duration(milliseconds: still ? 0 : YsStepMotion.swap);
    final standard = YsEase.standard.curve;
    final wash = switch (item.state) {
      YsStepState.needsAction => palette.primaryWashColor,
      YsStepState.failed => palette.errorWashColor,
      _ => palette.primaryWashColor.withValues(alpha: 0),
    };
    final titleColor = switch (item.state) {
      YsStepState.pending => palette.contentMutedColor,
      YsStepState.skipped => palette.contentSubtleColor,
      _ => palette.contentColor,
    };
    final statusColor = switch (item.state) {
      YsStepState.needsAction => palette.primaryColor,
      YsStepState.failed => palette.errorColor,
      YsStepState.pending || YsStepState.skipped => palette.contentSubtleColor,
      _ => palette.contentMutedColor,
    };
    final trailing = item.trailing;
    final unfolded =
        item.expanded && (item.notes.isNotEmpty || item.actions.isNotEmpty);

    final row = AnimatedContainer(
      duration: swap,
      curve: standard,
      padding: const EdgeInsets.all(YsSpace.sm),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YsStepBadge(
            state: item.state,
            icon: item.icon,
            progress: item.progress,
          ),
          const SizedBox(width: YsSpace.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MergeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: AnimatedDefaultTextStyle(
                              duration: swap,
                              style: YsType.label.flutter.copyWith(
                                color: titleColor,
                              ),
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (trailing != null) ...[
                            const SizedBox(width: YsSpace.sm),
                            Text(
                              trailing,
                              style: YsType.caption.flutter.copyWith(
                                color: palette.contentSubtleColor,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      AnimatedSwitcher(
                        duration: swap,
                        switchInCurve: standard,
                        switchOutCurve: standard,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: AlignmentDirectional.topStart,
                          children: [...previous, ?current],
                        ),
                        child: Text(
                          item.status,
                          key: ValueKey((item.state, item.status)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: YsType.small.flutter.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                YsResize(
                  child: unfolded
                      ? _Unfolded(item: item)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _shown,
      builder: (context, child) => Opacity(
        opacity: _shown.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _shown.value) * YsStepMotion.rise),
          child: child,
        ),
      ),
      child: AnimatedOpacity(
        duration: swap,
        opacity: item.state == YsStepState.skipped ? 0.7 : 1,
        child: row,
      ),
    );
  }
}

/// The notes and actions of a row that needs the user or failed.
final class _Unfolded extends StatelessWidget {
  const _Unfolded({required this.item});

  final YsChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final note in item.notes)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.sm),
            child: _Note(note: note, palette: palette),
          ),
        // One button per line: each label stays alone on its line.
        for (final action in item.actions)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: action,
            ),
          ),
      ],
    );
  }
}

final class _Note extends StatelessWidget {
  const _Note({required this.note, required this.palette});

  final YsChecklistNote note;
  final YsPalette palette;

  @override
  Widget build(BuildContext context) {
    final color = switch (note.tone) {
      YsNoteTone.muted => palette.contentMutedColor,
      YsNoteTone.alert => palette.errorColor,
    };
    final caption = note.caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caption != null)
          Text(caption, style: YsType.caption.flutter.copyWith(color: color)),
        Text(note.text, style: YsType.small.flutter.copyWith(color: color)),
      ],
    );
  }
}
