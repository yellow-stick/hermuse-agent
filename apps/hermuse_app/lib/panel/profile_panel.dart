import 'package:flutter/widgets.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../shell/brand.dart';

/// Profile panel: avatar, name, status, tabs, activity or empty states.
final class ProfilePanel extends StatefulWidget {
  const ProfilePanel({
    required this.agentName,
    required this.activity,
    required this.approvals,
    required this.onOpenApproval,
    required this.onClose,
    super.key,
  });

  final String agentName;
  final List<ActivityItem> activity;

  /// Pending approval cards of the active conversation.
  final List<PendingApprovalCard> approvals;
  final ValueChanged<PendingApprovalCard> onOpenApproval;
  final VoidCallback onClose;

  @override
  State<ProfilePanel> createState() => ProfilePanelState();
}

/// One unanswered approval card, anywhere in the active chat.
final class PendingApprovalCard {
  const PendingApprovalCard({
    required this.threadId,
    required this.threadTitle,
    required this.messageId,
    required this.prompt,
  });

  final String threadId;
  final String threadTitle;
  final String messageId;
  final String prompt;
}

final class ProfilePanelState extends State<ProfilePanel> {
  PanelTab _tab = PanelTab.activity;

  static YsIcon _iconFor(PanelTab tab) => switch (tab) {
    PanelTab.activity => YsIcon.activity,
    PanelTab.approvals => YsIcon.approvals,
    PanelTab.upcoming => YsIcon.upcoming,
    PanelTab.identity => YsIcon.identity,
  };

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ColoredBox(
      color: palette.canvasColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 70, 16, 44),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: YsButton.icon(
                icon: YsIcon.close,
                onPressed: widget.onClose,
                semanticLabel: 'Close panel',
                tooltip: 'Close panel',
                size: 36,
                iconSize: 18,
              ),
            ),
            const SizedBox(height: 18),
            YsAvatar(
              hermuseAvatar,
              size: 100,
              semanticLabel: 'Hermuse avatar',
              badgeIcon: YsIcon.pencil,
              onBadgePressed: () {},
              badgeSemanticLabel: 'Edit avatar and name',
            ),
            const SizedBox(height: 8),
            Text(
              widget.agentName,
              style: YsType.title.flutter.copyWith(color: palette.contentColor),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                YsIconWidget.raw(ysConnectedSvg(palette.success.css), size: 16),
                const SizedBox(width: 5),
                Text(
                  'Connected',
                  style: YsType.status.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 44),
            SizedBox(
              width: 327,
              child: YsSegmentedTabs(
                semanticLabel: 'Profile sections',
                segments: [
                  for (final tab in PanelTab.values)
                    YsSegment(icon: _iconFor(tab), label: tab.label),
                ],
                selectedIndex: _tab.index,
                onSelected: (index) =>
                    setState(() => _tab = PanelTab.values[index]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _tabBody()),
          ],
        ),
      ),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case PanelTab.activity:
        return _ActivityList(items: widget.activity);
      case PanelTab.approvals:
        return widget.approvals.isEmpty
            ? _TabEmptyState(tab: _tab)
            : _ApprovalsList(
                approvals: widget.approvals,
                onOpen: widget.onOpenApproval,
              );
      case PanelTab.upcoming:
      case PanelTab.identity:
        return _TabEmptyState(tab: _tab);
    }
  }
}

final class _ActivityList extends StatelessWidget {
  const _ActivityList({required this.items});

  final List<ActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Today',
            style: YsType.heading.flutter.copyWith(color: palette.contentColor),
          ),
        ),
        for (final item in items) _ActivityRow(item: item),
      ],
    );
  }
}

final class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: () {},
      semanticLabel: item.title,
      builder: (context, state) => AnimatedContainer(
        duration: const Duration(milliseconds: YsMotion.fast),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: state.hovered
              ? palette.neutralFilmColor.withValues(alpha: 0.5)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(YsRadius.row),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: palette.neutralAmbientColor,
                borderRadius: BorderRadius.circular(YsRadius.row),
              ),
              child: SizedBox(
                width: YsLayout.activityTileSize,
                height: YsLayout.activityTileSize,
                child: Center(
                  child: YsIconWidget(
                    item.kind == ActivityKind.webSearch
                        ? YsIcon.webSearch
                        : YsIcon.checkCircle,
                    size: 18,
                    color: palette.contentMutedColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: YsType.label.flutter.copyWith(
                      color: palette.contentColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.description,
                    style: YsType.small.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.time,
                    style: YsType.caption.flutter.copyWith(
                      color: palette.contentMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _TabEmptyState extends StatelessWidget {
  const _TabEmptyState({required this.tab});

  final PanelTab tab;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      children: [
        const SizedBox(height: 32),
        YsIconWidget(
          ProfilePanelState._iconFor(tab),
          size: 26,
          color: palette.contentMutedColor,
        ),
        const SizedBox(height: 8),
        Text(
          tab.label,
          style: YsType.label.flutter.copyWith(color: palette.contentColor),
        ),
        const SizedBox(height: 4),
        Text(
          tab.emptyText,
          style: YsType.small.flutter.copyWith(
            color: palette.contentMutedColor,
          ),
        ),
      ],
    );
  }
}

final class _ApprovalsList extends StatelessWidget {
  const _ApprovalsList({required this.approvals, required this.onOpen});

  final List<PendingApprovalCard> approvals;
  final ValueChanged<PendingApprovalCard> onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Pending',
            style: YsType.heading.flutter.copyWith(color: palette.contentColor),
          ),
        ),
        for (final card in approvals)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: YsPressable(
              onPressed: () => onOpen(card),
              semanticLabel: 'Open approval in ${card.threadTitle}',
              builder: (context, state) => AnimatedContainer(
                duration: const Duration(milliseconds: YsMotion.fast),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: state.hovered
                      ? palette.neutralFilmColor.withValues(alpha: 0.5)
                      : const Color(0x00000000),
                  borderRadius: BorderRadius.circular(YsRadius.row),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.neutralAmbientColor,
                        borderRadius: BorderRadius.circular(YsRadius.row),
                      ),
                      child: SizedBox(
                        width: YsLayout.activityTileSize,
                        height: YsLayout.activityTileSize,
                        child: Center(
                          child: YsIconWidget(
                            YsIcon.approvals,
                            size: 18,
                            color: palette.contentMutedColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.prompt.split('\n').first,
                            style: YsType.label.flutter.copyWith(
                              color: palette.contentColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.threadTitle,
                            style: YsType.caption.flutter.copyWith(
                              color: palette.contentMutedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
