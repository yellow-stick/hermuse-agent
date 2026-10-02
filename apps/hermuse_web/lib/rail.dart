import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'package:hermes_client/hermes_client.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

/// Left icon rail (72 wide): destinations, then the instance switcher, then
/// app/settings at the bottom.
///
/// Instances render as letter discs under the destinations; the active one
/// is highlighted. The trailing `+` opens the add-instance screen.
/// Product destinations of the rail (chat + plugin surfaces).
enum HermuseDestination { chat, feed, ideas, goals, library }

class HermuseRail extends StatelessComponent {
  const HermuseRail({
    required this.instances,
    required this.activeInstanceId,
    required this.onSelectInstance,
    this.onAddInstance,
    this.onOpenInstances,
    required this.destination,
    required this.onDestination,
    required this.chatsPanelOpen,
    required this.onToggleChatsPanel,
    super.key,
  });

  final List<HermesInstance> instances;
  final String? activeInstanceId;
  final ValueChanged<String> onSelectInstance;

  /// Null hides the entry (the read-only demo manages no instances).
  final VoidCallback? onAddInstance;
  final VoidCallback? onOpenInstances;

  /// Currently shown product surface.
  final HermuseDestination destination;
  final ValueChanged<HermuseDestination> onDestination;

  /// On the chat, the Chat item toggles the chats panel and
  /// reports it as `aria-expanded`.
  final bool chatsPanelOpen;
  final VoidCallback onToggleChatsPanel;

  static const _destinations = [
    (YsIcon.chat, 'Chat', HermuseDestination.chat),
    (YsIcon.feed, 'Feed', HermuseDestination.feed),
    (YsIcon.ideas, 'Ideas', HermuseDestination.ideas),
    (YsIcon.goals, 'Goals', HermuseDestination.goals),
    (YsIcon.library, 'Library', HermuseDestination.library),
  ];

  @override
  Component build(BuildContext context) => nav(
    classes: 'hermuse-rail',
    attributes: {'aria-label': 'Primary'},
    [
      div(classes: 'hermuse-rail-destinations', [
        // The marker slides along the rail's edge to the current
        // destination.
        div(classes: 'hermuse-rail-dests', [
          for (final (icon, label, target) in _destinations)
            _item(
              label: label,
              classes: target == destination ? 'hermuse-rail-current' : null,
              attributes:
                  target == HermuseDestination.chat &&
                      destination == HermuseDestination.chat
                  ? {'aria-expanded': '$chatsPanelOpen'}
                  : null,
              onPressed: target != destination
                  ? () => onDestination(target)
                  : target == HermuseDestination.chat
                  ? onToggleChatsPanel
                  : () {},
              builder: (state) => YsMotionIconView(
                icon,
                size: YsLayout.railIconSize,
                strokeWidth: YsLayout.railIconStroke,
                hovered: state.hovered,
              ),
            ),
          span(
            classes: 'hermuse-rail-marker',
            styles: Styles(
              transform: .translate(
                y:
                    (destination.index * YsLayout.railItemHeight +
                            (YsLayout.railItemHeight -
                                    YsLayout.railMarkerHeight) /
                                2)
                        .px,
              ),
            ),
            attributes: {'aria-hidden': 'true'},
            [],
          ),
        ]),
        if (instances.isNotEmpty) div(classes: 'hermuse-rail-divider', []),
        for (final instance in instances)
          _item(
            label: instance.label,
            pressLabel: 'Open ${instance.label}',
            classes: instance.id == activeInstanceId
                ? 'hermuse-rail-instance hermuse-rail-active'
                : 'hermuse-rail-instance',
            onPressed: () => onSelectInstance(instance.id),
            builder: (state) => span(classes: 'hermuse-rail-letter', [
              .text(_letter(instance.label)),
            ]),
          ),
        if (onAddInstance case final onAdd?)
          _item(
            label: 'Add a Hermes',
            classes: 'hermuse-rail-add',
            onPressed: onAdd,
            builder: (state) => YsIconView(
              YsIcon.plus,
              size: 20,
              strokeWidth: YsLayout.railIconStroke * YsLayout.railIconSize / 20,
            ),
          ),
      ]),
      div(classes: 'hermuse-rail-bottom', [
        if (onOpenInstances case final onOpen?)
          _item(
            label: 'Instances',
            onPressed: onOpen,
            builder: (state) => YsIconView(
              YsIcon.menu,
              size: YsLayout.railIconSize,
              strokeWidth: YsLayout.railIconStroke,
            ),
          ),
      ]),
    ],
  );

  /// One rail row: the whole 72x56 row is the hit target (hover plays the
  /// icon animation), the 44 px disc behind the glyph shows hover/current.
  static Component _item({
    required String label,
    String? pressLabel,
    String? classes,
    Map<String, String>? attributes,
    required VoidCallback onPressed,
    required Component Function(YsPressState state) builder,
  }) => div(classes: 'hermuse-rail-row', [
    YsTooltip(
      side: YsTooltipSide.right,
      label: label,
      child: YsPressable(
        onPressed: onPressed,
        label: pressLabel ?? label,
        classes: ['hermuse-rail-item', ?classes].join(' '),
        attributes: attributes,
        builder: (context, state) =>
            span(classes: 'hermuse-rail-disc', [builder(state)]),
      ),
    ),
  ]);

  static String _letter(String label) {
    final trimmed = label.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-rail', [
      css('&').styles(
        width: YsLayout.railWidth.px,
        height: 100.percent,
        display: .flex,
        flexDirection: .column,
        justifyContent: .center,
        alignItems: .center,
        raw: {'flex-shrink': '0'},
      ),
      css('.hermuse-rail-destinations').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        justifyContent: .center,
        alignItems: .center,
        flex: .grow(1),
      ),
      css('.hermuse-rail-row').styles(
        width: 100.percent,
        height: YsLayout.railItemHeight.px,
        display: .flex,
      ),
      css('.hermuse-rail-dests').styles(
        position: .relative(),
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
      ),
      css('.hermuse-rail-marker').styles(
        position: .absolute(top: .zero, left: .zero),
        width: YsLayout.railMarkerWidth.px,
        height: YsLayout.railMarkerHeight.px,
        radius: .only(
          topRight: .circular(YsRadius.pill.px),
          bottomRight: .circular(YsRadius.pill.px),
        ),
        pointerEvents: .none,
        backgroundColor: .variable('--primary'),
        raw: {
          'transition':
              'transform ${YsRailMotion.slide}ms ${YsEase.settle.css}',
        },
      ),
      css('.hermuse-rail-row > .ys-has-tooltip')
          .styles(width: 100.percent, height: 100.percent),
      css('.hermuse-rail-item').styles(
        width: 100.percent,
        height: 100.percent,
        padding: .zero,
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        raw: {'outline': 'none'},
      ),
      css('.hermuse-rail-disc').styles(
        width: 44.px,
        height: 44.px,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        backgroundColor: Colors.transparent,
        raw: {
          'flex-shrink': '0',
          'transition':
              'background-color ${YsMotion.base}ms ${YsEase.standard.css}',
        },
      ),
      // The same solid disc marks hover, focus and the current destination.
      css(
        '.hermuse-rail-item:hover .hermuse-rail-disc, '
        '.hermuse-rail-item:focus-visible .hermuse-rail-disc, '
        '.hermuse-rail-current .hermuse-rail-disc',
      ).styles(backgroundColor: .variable('--neutral-ambient')),
      css('.hermuse-rail-item:focus-visible .hermuse-rail-disc').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.hermuse-rail-divider').styles(
        width: 24.px,
        height: 1.2.px,
        margin: .symmetric(vertical: 4.px),
        backgroundColor: .variable('--line'),
      ),
      css('.hermuse-rail-instance .hermuse-rail-disc')
          .styles(backgroundColor: .variable('--neutral-ambient')),
      css('.hermuse-rail-letter')
          .styles(fontSize: 17.px, lineHeight: 22.px, fontWeight: .w600),
      css('.hermuse-rail-add .hermuse-rail-disc').styles(
        border: .all(style: .dashed, color: .variable('--line'), width: 1.2.px),
        color: .variable('--content-muted'),
      ),
      css('.hermuse-rail-bottom').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
      ),
    ]),
    css.media(MediaQuery.raw(ysReducedMotionQuery), [
      css('.hermuse-rail-marker').styles(raw: {'transition': 'none'}),
    ]),
  ];
}
