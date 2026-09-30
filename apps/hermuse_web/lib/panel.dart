import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

import 'brand.dart';

/// Profile panel (360 wide): avatar, name, status, tabs, activity list.
class HermusePanel extends StatelessComponent {
  const HermusePanel({
    required this.agentName,
    required this.activity,
    required this.tab,
    required this.onTab,
    required this.onClose,
    this.onOpenComputer,
    super.key,
  });

  final String agentName;
  final List<ActivityItem> activity;
  final PanelTab tab;
  final ValueChanged<PanelTab> onTab;
  final VoidCallback onClose;

  /// Shows the agent's computer (its browser and desktop) at will; null
  /// hides the button (the read-only demo has no computer).
  final VoidCallback? onOpenComputer;

  @override
  Component build(BuildContext context) => aside(
    classes: 'hermuse-panel',
    attributes: {'aria-label': 'Profile'},
    [
      div(classes: 'hermuse-panel-close', [
        YsButton.icon(
          icon: YsIcon.close,
          label: 'Close panel',
          onPressed: onClose,
        ),
      ]),
      div(classes: 'hermuse-panel-avatar', [
        YsAvatar(
          src: hermuseAvatarUrl,
          alt: '$agentName avatar',
          size: 100,
          onEdit: () {},
          editLabel: 'Edit avatar',
        ),
      ]),
      h1(classes: 'hermuse-panel-name', [.text(agentName)]),
      div(classes: 'hermuse-panel-status', [
        span(classes: 'hermuse-panel-status-icon', [
          YsPing(
            live: true,
            color: YsTheme.success,
            child: RawText(ysConnectedSvg(YsPalette.dark.success.css)),
          ),
        ]),
        span(classes: 'hermuse-panel-status-text', [.text('Connected')]),
      ]),
      if (onOpenComputer case final onOpen?)
        div(classes: 'hermuse-panel-computer', [
          YsButton.neutral(label: 'Open computer', onPressed: onOpen),
        ]),
      div(classes: 'hermuse-panel-tabs', [
        YsSegmentedTabs<PanelTab>(
          segments: const [
            YsSegment(
              value: PanelTab.activity,
              icon: YsIcon.activity,
              label: 'Activity',
            ),
            YsSegment(
              value: PanelTab.approvals,
              icon: YsIcon.approvals,
              label: 'Approvals',
            ),
            YsSegment(
              value: PanelTab.upcoming,
              icon: YsIcon.upcoming,
              label: 'Upcoming',
            ),
            YsSegment(
              value: PanelTab.identity,
              icon: YsIcon.identity,
              label: 'Identity',
            ),
          ],
          selected: tab,
          onSelected: onTab,
        ),
      ]),
      if (tab == PanelTab.activity)
        div(classes: 'hermuse-panel-section', [
          h2(classes: 'hermuse-panel-heading', [.text('Today')]),
          for (final item in activity)
            div(classes: 'hermuse-activity', [
              div(classes: 'hermuse-activity-icon', [
                YsIconView(
                  item.kind == ActivityKind.webSearch
                      ? YsIcon.webSearch
                      : YsIcon.checkCircle,
                  size: 18,
                ),
              ]),
              div(classes: 'hermuse-activity-body', [
                p(classes: 'hermuse-activity-title', [.text(item.title)]),
                p(classes: 'hermuse-activity-desc', [.text(item.description)]),
                p(classes: 'hermuse-activity-time', [.text(item.time)]),
              ]),
            ]),
        ])
      else
        YsHover(
          builder: (context, hovered) => div(classes: 'hermuse-panel-empty', [
            YsArtView(
              switch (tab) {
                PanelTab.activity => YsArt.activity,
                PanelTab.approvals => YsArt.approvals,
                PanelTab.upcoming => YsArt.upcoming,
                PanelTab.identity => YsArt.identity,
              },
              size: YsLayout.artCompact,
              active: hovered,
            ),
            p(classes: 'hermuse-panel-empty-title', [.text(tab.label)]),
            p(classes: 'hermuse-panel-empty-body', [.text(tab.emptyText)]),
          ]),
        ),
    ],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-panel', [
      css('&').styles(
        width: YsLayout.panelWidth.px,
        height: 100.percent,
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        padding: .only(top: 70.px, left: 16.px, right: 16.px, bottom: 44.px),
        backgroundColor: .variable('--canvas'),
        border: .only(
          left: .solid(color: .variable('--line'), width: 1.2.px),
        ),
        overflow: .only(y: .auto, x: .hidden),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-panel-close').styles(
        width: 100.percent,
        display: .flex,
        justifyContent: .end,
        raw: {'margin-top': '-54px', 'margin-bottom': '18px'},
      ),
      css('.hermuse-panel-name').styles(
        margin: .only(top: 8.px),
        fontSize: 22.px,
        lineHeight: 28.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-panel-status').styles(
        display: .flex,
        flexDirection: .row,
        alignItems: .center,
        gap: .all(5.px),
        margin: .only(top: 2.px),
      ),
      css('.hermuse-panel-status-icon').styles(display: .inlineFlex),
      css('.hermuse-panel-status-text').styles(
        fontSize: 17.px,
        lineHeight: 22.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-panel-computer').styles(margin: .only(top: 16.px)),
      css('.hermuse-panel-tabs').styles(
        width: 327.px,
        margin: .only(top: 44.px),
      ),
      css('.hermuse-panel-section').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        gap: .all(1.px),
      ),
      css('.hermuse-panel-heading').styles(
        margin: .only(top: 8.px, bottom: 0.px),
        fontSize: 16.px,
        lineHeight: 22.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-activity').styles(
        padding: .all(8.px),
        radius: .circular(YsRadius.row.px),
        display: .flex,
        flexDirection: .row,
        gap: .all(8.px),
      ),
      css('.hermuse-activity:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.hermuse-activity-icon').styles(
        width: YsLayout.activityTileSize.px,
        height: YsLayout.activityTileSize.px,
        radius: .circular(YsRadius.row.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content-muted'),
        backgroundColor: .variable('--neutral-ambient'),
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-activity-body')
          .styles(display: .flex, flexDirection: .column, gap: .all(2.px)),
      css('.hermuse-activity-title').styles(
        margin: .zero,
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-activity-desc').styles(
        margin: .zero,
        fontSize: 13.px,
        lineHeight: 18.px,
        color: .variable('--content-muted'),
      ),
      css('.hermuse-activity-time').styles(
        margin: .zero,
        fontSize: 12.px,
        lineHeight: 16.px,
        color: .variable('--content-subtle'),
      ),
      css('.hermuse-panel-empty').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        padding: .only(top: YsSpace.xl.px),
        color: .variable('--content-muted'),
        textAlign: .center,
      ),
      css('.hermuse-panel-empty-title').styles(
        margin: .fromLTRB(.zero, YsSpace.sm.px, .zero, .zero),
        fontSize: 14.px,
        lineHeight: 20.px,
        fontWeight: .w500,
        color: .variable('--content'),
      ),
      css('.hermuse-panel-empty-body').styles(
        margin: .fromLTRB(.zero, YsSpace.xs.px, .zero, .zero),
        fontSize: 13.px,
        lineHeight: 18.px,
      ),
    ]),
  ];
}
