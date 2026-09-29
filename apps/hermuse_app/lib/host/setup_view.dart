import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/screens.dart';

/// A line above a setup checklist that concerns no single row: how the
/// last run ended, what holds the whole system back, a stop in progress.
@immutable
final class SetupNotice {
  const SetupNotice(this.text, {this.details = const [], this.alert = false});

  final String text;

  /// What it concerns, one line each.
  final List<String> details;

  /// Whether it reports a problem (error colour) rather than a state.
  final bool alert;
}

/// The card of the desktop setup flows, the Linux assistant and the macOS
/// and Windows install alike: the overall progress ring with the title and
/// what happens now, notices, the checklist of components, the technical log
/// behind "Show details", and the actions that concern no single row.
final class SetupCard extends StatelessWidget {
  const SetupCard({
    required this.title,
    required this.status,
    required this.items,
    this.notices = const [],
    this.log = const [],
    this.actions = const [],
    this.onReady,
    super.key,
  });

  final String title;

  /// What happens now, under the title.
  final String status;
  final List<YsChecklistItem> items;
  final List<SetupNotice> notices;

  /// The last lines of technical output, streamed as they come.
  final List<String> log;

  /// Full-width buttons under everything, one per line.
  final List<Widget> actions;

  /// Non-null once every row is ready: the ring plays the ready moment,
  /// then this fires, once.
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final settled = items.where((item) => item.state.settled).length;
    final progress = items.isEmpty
        ? 0.0
        : items.fold<double>(
                0,
                (sum, item) =>
                    sum +
                    switch (item.state) {
                      _ when item.state.settled => 1,
                      YsStepState.working => item.progress ?? 0,
                      _ => 0,
                    },
              ) /
              items.length;
    // Sections come and go with their spacing, easing the card's height.
    Widget section(bool shown, Widget child) => YsResize(
      child: shown
          ? Padding(
              padding: const EdgeInsets.only(top: YsSpace.lg),
              child: child,
            )
          : const SizedBox(width: double.infinity),
    );
    // Headings, notices and the log line up with the rows' badges.
    const inset = EdgeInsets.symmetric(horizontal: YsSpace.sm);
    return YsDialogCard(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: inset,
              child: _Header(
                title: title,
                status: status,
                progress: progress,
                label: items.length > 1 ? '$settled/${items.length}' : null,
                onReady: onReady,
              ),
            ),
            section(
              notices.isNotEmpty,
              Padding(
                padding: inset,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: YsSpace.sm,
                  children: [for (final notice in notices) _Notice(notice)],
                ),
              ),
            ),
            const SizedBox(height: YsSpace.lg),
            YsChecklist(items: items),
            section(
              log.isNotEmpty,
              Padding(
                padding: inset,
                child: YsDisclosure(
                  label: 'Show details',
                  openLabel: 'Hide details',
                  child: InstallLogBox(log: log),
                ),
              ),
            ),
            section(
              actions.isNotEmpty,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: YsSpace.sm,
                children: actions,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

final class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.status,
    required this.progress,
    required this.label,
    required this.onReady,
  });

  final String title;
  final String status;
  final double progress;
  final String? label;
  final VoidCallback? onReady;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final swap = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context)
          ? 0
          : YsStepMotion.swap,
    );
    Widget fade(String text, TextStyle style) => AnimatedSwitcher(
      duration: swap,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
    return Row(
      children: [
        YsProgressRing(
          value: progress,
          label: label,
          complete: onReady != null,
          onCompleted: onReady,
        ),
        const SizedBox(width: YsSpace.lg),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: fade(
                  title,
                  YsType.title.flutter.copyWith(color: palette.contentColor),
                ),
              ),
              // Announced as it changes: what the assistant does now.
              Semantics(
                liveRegion: true,
                child: fade(
                  status,
                  YsType.small.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _Notice extends StatelessWidget {
  const _Notice(this.notice);

  final SetupNotice notice;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          notice.text,
          style: YsType.small.flutter.copyWith(
            color: notice.alert
                ? palette.errorColor
                : palette.contentMutedColor,
          ),
        ),
        for (final detail in notice.details)
          Padding(
            padding: const EdgeInsets.only(top: YsSpace.xs),
            child: Text(
              detail,
              style: YsType.caption.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ),
      ],
    );
  }
}

/// Last output lines, scrolled to the newest.
final class InstallLogBox extends StatefulWidget {
  const InstallLogBox({required this.log, super.key});

  final List<String> log;

  @override
  State<InstallLogBox> createState() => _InstallLogBoxState();
}

final class _InstallLogBoxState extends State<InstallLogBox> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvasColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: YsLayout.logMaxHeight),
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.all(YsSpace.md),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              widget.log.join('\n'),
              style: YsType.code.flutter.copyWith(
                fontFamily: YsType.monoFamily,
                color: palette.contentMutedColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
