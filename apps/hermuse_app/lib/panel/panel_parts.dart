import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// "Today", "Now", "Daily", … heading over a group of panel rows.
final class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: YsSpace.sm),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: YsType.heading.flutter.copyWith(
          color: YsTheme.of(context).contentColor,
        ),
      ),
    ),
  );
}

/// Rounded tile with a muted icon, at the start of every panel row.
final class PanelRowTile extends StatelessWidget {
  const PanelRowTile(this.icon, {super.key});

  final YsIcon icon;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.neutralAmbientColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: SizedBox(
        width: YsLayout.activityTileSize,
        height: YsLayout.activityTileSize,
        child: Center(
          child: YsIconWidget(icon, size: 18, color: palette.contentMutedColor),
        ),
      ),
    );
  }
}

/// A panel row: tile, [body], then an optional [trailing] control;
/// pressable (hover fill) only with [onPressed].
final class PanelRow extends StatelessWidget {
  const PanelRow({
    required this.icon,
    required this.body,
    this.trailing,
    this.onPressed,
    this.semanticLabel,
    super.key,
  });

  final YsIcon icon;
  final Widget body;
  final Widget? trailing;
  final VoidCallback? onPressed;

  /// Spoken before the row's own text ("Open approval in …").
  final String? semanticLabel;

  Widget _row(Color fill, Widget body) => AnimatedContainer(
    duration: const Duration(milliseconds: YsMotion.fast),
    padding: const EdgeInsets.all(YsSpace.sm),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(YsRadius.row),
    ),
    child: body,
  );

  Widget _content(Widget tileAndBody) {
    final trailing = this.trailing;
    if (trailing == null) return tileAndBody;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: tileAndBody),
        const SizedBox(width: YsSpace.xs),
        trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    const clear = Color(0x00000000);
    final tileAndBody = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelRowTile(icon),
        const SizedBox(width: YsSpace.sm),
        Expanded(child: body),
      ],
    );
    final onPressed = this.onPressed;
    if (onPressed == null) {
      return _row(clear, _content(MergeSemantics(child: tileAndBody)));
    }
    // The trailing control stays its own button, outside the pressable.
    return YsHover(
      builder: (context, hovered) => _row(
        hovered ? palette.neutralWashColor : clear,
        _content(
          YsPressable(
            onPressed: onPressed,
            semanticLabel: semanticLabel,
            builder: (context, state) => tileAndBody,
          ),
        ),
      ),
    );
  }
}

/// Title, optional muted [summary] (two lines at most) and [time] of a panel
/// row.
final class PanelRowText extends StatelessWidget {
  const PanelRowText({
    required this.title,
    this.summary = '',
    this.time = '',
    this.summaryStyle,
    super.key,
  });

  final String title;
  final String summary;
  final String time;

  /// Overrides the summary's style (code output in monospace).
  final TextStyle? summaryStyle;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: YsType.label.flutter.copyWith(color: palette.contentColor),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: YsSpace.xxs),
          Text(
            summary,
            style:
                summaryStyle ??
                YsType.small.flutter.copyWith(color: palette.contentMutedColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (time.isNotEmpty) ...[
          const SizedBox(height: YsSpace.xxs),
          Text(
            time,
            style: YsType.caption.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
        ],
      ],
    );
  }
}

/// Illustrated empty state of a panel tab.
final class PanelEmptyState extends StatelessWidget {
  const PanelEmptyState({required this.tab, this.help, super.key});

  final PanelTab tab;

  /// A hint under the empty text (how to fill the tab).
  final String? help;

  static YsArt _artFor(PanelTab tab) => switch (tab) {
    PanelTab.activity => YsArt.activity,
    PanelTab.approvals => YsArt.approvals,
    PanelTab.upcoming => YsArt.upcoming,
    PanelTab.identity => YsArt.plugin,
  };

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final help = this.help;
    final small = YsType.small.flutter.copyWith(
      color: palette.contentMutedColor,
    );
    return YsHover(
      builder: (context, hovered) => Column(
        children: [
          const SizedBox(height: YsSpace.xl),
          YsArtView(_artFor(tab), size: YsLayout.artCompact, active: hovered),
          const SizedBox(height: YsSpace.sm),
          Text(
            tab.label,
            style: YsType.label.flutter.copyWith(color: palette.contentColor),
          ),
          const SizedBox(height: YsSpace.xs),
          Text(tab.emptyText, style: small),
          if (help != null) ...[
            const SizedBox(height: YsSpace.xs),
            Text(help, style: small, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A one-shot date, local: "Oct 4, 9:15 AM".
String formatShortDate(DateTime at) {
  final local = at.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${formatChatTime(local)}';
}

/// A last-updated stamp, local: "10.03.26".
String formatDotDate(DateTime at) {
  final local = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.month)}.${two(local.day)}.${two(local.year % 100)}';
}
