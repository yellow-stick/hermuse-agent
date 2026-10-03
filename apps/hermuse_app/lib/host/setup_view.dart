import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

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

/// A bounded operation surface with independent content and log scrolling.
///
/// The caller supplies a scrollable [content]. Header and footer remain
/// outside that scroller; on very short windows they can scroll independently.
final class SetupOperationFrame extends StatelessWidget {
  const SetupOperationFrame({
    required this.header,
    required this.content,
    this.footer,
    this.log = const [],
    this.busy = false,
    super.key,
  });

  final Widget header;
  final Widget content;
  final Widget? footer;
  final List<String> log;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return LayoutBuilder(
      builder: (context, viewport) {
        final spacing = viewport.maxHeight < YsLayout.operationComfortHeight
            ? YsSpace.sm
            : YsSpace.xl;
        return Padding(
          padding: EdgeInsets.all(spacing),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: YsLayout.operationMaxWidth,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.paperColor,
                  borderRadius: BorderRadius.circular(YsRadius.bubble),
                ),
                child: Padding(
                  padding: EdgeInsets.all(spacing),
                  child: LayoutBuilder(
                    builder: (context, card) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                card.maxHeight *
                                YsLayout.operationHeaderFraction,
                          ),
                          child: SingleChildScrollView(
                            primary: false,
                            child: header,
                          ),
                        ),
                        const SizedBox(height: YsSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 3, child: content),
                              if (log.isNotEmpty) ...[
                                const SizedBox(height: YsSpace.sm),
                                Expanded(
                                  flex: 2,
                                  child: InstallLogBox(log: log),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (footer case final footer?) ...[
                          const SizedBox(height: YsSpace.sm),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight:
                                  card.maxHeight *
                                  YsLayout.operationFooterFraction,
                            ),
                            child: SingleChildScrollView(
                              primary: false,
                              child: footer,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shared install checklist with compact progress, bounded logs and actions.
final class SetupCard extends StatelessWidget {
  const SetupCard({
    required this.title,
    required this.status,
    required this.items,
    this.art,
    this.busy = false,
    this.notices = const [],
    this.log = const [],
    this.actions = const [],
    this.onReady,
    super.key,
  });

  final String title;

  /// What happens now, under the title.
  final String status;

  /// An optional compact illustration beside the heading.
  final YsArt? art;

  /// Work under way: [art] loops.
  final bool busy;

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
    return SetupOperationFrame(
      busy: busy,
      header: Row(
        children: [
          Expanded(
            child: _Header(
              title: title,
              status: status,
              progress: progress,
              label: items.length > 1 ? '$settled/${items.length}' : null,
              onReady: onReady,
            ),
          ),
          if (art case final art?) ...[
            const SizedBox(width: YsSpace.sm),
            YsArtView(art, size: YsLayout.progressRing, busy: busy),
          ],
        ],
      ),
      content: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final notice in notices)
            Padding(
              padding: const EdgeInsets.only(
                left: YsSpace.sm,
                right: YsSpace.sm,
                bottom: YsSpace.sm,
              ),
              child: _Notice(notice),
            ),
          YsChecklist(items: items),
        ],
      ),
      log: log,
      footer: actions.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: YsSpace.sm,
              children: actions,
            ),
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

/// Selectable technical output with a visible scrollbar and a copy action.
///
/// Live output follows the tail only until the reader scrolls away from it.
final class InstallLogBox extends StatefulWidget {
  const InstallLogBox({required this.log, this.follow = true, super.key});

  final List<String> log;
  final bool follow;

  @override
  State<InstallLogBox> createState() => _InstallLogBoxState();
}

final class _InstallLogBoxState extends State<InstallLogBox> {
  final _scroll = ScrollController();
  bool _following = true;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _following = widget.follow;
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(InstallLogBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.follow) {
      _following = false;
    } else if (!oldWidget.follow) {
      _following = true;
    }
    _scheduleFollow();
  }

  void _scheduleFollow() {
    if (!widget.follow || !_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _following && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.log.join('\n')));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final output = widget.log.join('\n');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvasColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: YsLayout.logMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                primary: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: YsSpace.md,
                    vertical: YsSpace.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Activity log',
                          style: YsType.caption.flutter.copyWith(
                            color: palette.contentMutedColor,
                          ),
                        ),
                      ),
                      YsButton.icon(
                        icon: _copied ? YsIcon.check : YsIcon.copy,
                        semanticLabel: _copied ? 'Copied' : 'Copy log',
                        tooltip: _copied ? 'Copied' : 'Copy log',
                        onPressed: widget.log.isEmpty ? null : _copy,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Flexible(
              flex: 3,
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0) {
                    _following =
                        widget.follow &&
                        notification.metrics.extentAfter <=
                            YsLayout.logTailTolerance;
                  }
                  return false;
                },
                child: RawScrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  interactive: true,
                  thumbColor: palette.contentMutedColor,
                  radius: const Radius.circular(YsRadius.row),
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(YsSpace.md),
                    child: SizedBox(
                      width: double.infinity,
                      child: SelectableText(
                        output,
                        // WidgetsApp has no Material localization delegates.
                        // Selection and keyboard copy remain available.
                        contextMenuBuilder: null,
                        style: YsType.code.flutter.copyWith(
                          fontFamily: YsType.monoFamily,
                          color: palette.contentMutedColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
