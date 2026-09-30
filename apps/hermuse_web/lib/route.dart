import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';
import 'package:yellow_stick_ui_web/yellow_stick_ui_web.dart';

/// Empty state of a product page: its line illustration drawing in above a
/// title and a friendly line. Pointing at it plays the illustration once
/// more.
class HermuseRouteEmpty extends StatelessComponent {
  const HermuseRouteEmpty({
    required this.art,
    required this.title,
    required this.body,
    this.size = YsLayout.artEmpty,
    this.top = 48,
    super.key,
  });

  final YsArt art;
  final String title;
  final String body;
  final double size;

  /// Space above the illustration.
  final double top;

  @override
  Component build(BuildContext context) => YsHover(
    builder: (context, hovered) => div(
      classes: 'hermuse-route-empty',
      styles: Styles(padding: .only(top: top.px)),
      [
        YsArtView(art, size: size, active: hovered),
        p(classes: 'hermuse-route-empty-title', [.text(title)]),
        p(classes: 'hermuse-route-empty-body', [.text(body)]),
      ],
    ),
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-route-empty', [
      css('&').styles(
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        color: .variable('--content-muted'),
        textAlign: .center,
      ),
      css('.hermuse-route-empty-title').styles(
        margin: .fromLTRB(.zero, YsSpace.md.px, .zero, .zero),
        color: .variable('--content'),
        fontSize: 16.px,
        fontWeight: .w500,
        lineHeight: 22.px,
      ),
      css('.hermuse-route-empty-body').styles(
        margin: .fromLTRB(.zero, (YsSpace.xs + YsSpace.xxs).px, .zero, .zero),
        fontSize: 14.px,
        lineHeight: 20.px,
      ),
    ]),
  ];
}

/// Loading placeholder of a product list: [count] paper cards whose lines
/// shimmer where the content will be. Announces [label] ("Loading feed…").
class HermuseRouteSkeleton extends StatelessComponent {
  const HermuseRouteSkeleton({required this.label, this.count = 2, super.key});

  final String label;
  final int count;

  @override
  Component build(BuildContext context) => div(
    classes: 'hermuse-route-skeleton',
    attributes: {'role': 'status'},
    [
      span(classes: 'hermuse-route-skeleton-label', [.text(label)]),
      for (var i = 0; i < count; i++)
        div(classes: 'hermuse-route-skeleton-card', [
          YsSkeleton(
            children: [
              YsSkeletonBox(height: 20, width: 55.percent),
              YsSkeletonBox(height: 12, width: 25.percent, top: YsSpace.md),
              YsSkeletonBox(height: 14, top: YsSpace.lg),
              YsSkeletonBox(height: 14, width: 80.percent, top: YsSpace.sm),
            ],
          ),
        ]),
    ],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.hermuse-route-skeleton', [
      css('&').styles(
        position: .relative(),
        display: .flex,
        flexDirection: .column,
        gap: .all(YsSpace.md.px),
      ),
      // Announced, not shown: the cards show the loading.
      css('.hermuse-route-skeleton-label').styles(
        position: .absolute(),
        width: 1.px,
        height: 1.px,
        overflow: .hidden,
        raw: {'clip-path': 'inset(50%)', 'white-space': 'nowrap'},
      ),
      css('.hermuse-route-skeleton-card').styles(
        padding: .all(20.px),
        radius: .circular(YsRadius.bubble.px),
        backgroundColor: .variable('--paper'),
      ),
    ]),
  ];
}
