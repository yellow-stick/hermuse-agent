import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'art.dart';
import 'motion.dart';
import 'pressable.dart';

/// A big selectable card: [art] above [title] and [body], centred. The
/// whole card is the button: pointing at it or focusing it lifts it, tints
/// its outline and plays the art's hover motion; pressing it settles it
/// back. Enter or Space activates it (native button).
///
/// [title] stays one plain line of text.
class YsChoiceCard extends StatelessComponent {
  const YsChoiceCard({
    required this.art,
    required this.title,
    required this.onPressed,
    this.body,
    super.key,
  });

  final YsArt art;
  final String title;
  final String? body;
  final VoidCallback? onPressed;

  @override
  Component build(BuildContext context) => YsPressable(
    onPressed: onPressed,
    classes: 'ys-choice ys-lift ys-press',
    builder: (context, state) => .fragment([
      YsArtView(
        art,
        size: YsLayout.artChoice,
        active: (state.hovered || state.focused) && !state.disabled,
      ),
      span(classes: 'ys-choice-title', [.text(title)]),
      if (body case final body?) span(classes: 'ys-choice-body', [.text(body)]),
    ]),
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-choice', [
      css('&').styles(
        width: 100.percent,
        display: .flex,
        flexDirection: .column,
        alignItems: .center,
        padding: .only(
          top: YsSpace.xl.px,
          left: YsSpace.xl.px,
          right: YsSpace.xl.px,
          bottom: (YsSpace.xl - YsSpace.xs).px,
        ),
        radius: .circular(YsRadius.bubble.px),
        color: .variable('--content'),
        textAlign: .center,
        backgroundColor: .variable('--paper'),
        border: .all(
          style: .solid,
          color: .variable('--line'),
          width: ysHairline.px,
        ),
      ),
      // Its own outline tint eases with the lift.
      css('&.ys-lift').styles(
        raw: {
          'transition':
              'border-color ${YsMotion.base}ms ${YsEase.standard.css}, '
              '$ysLiftTransition',
        },
      ),
      css('&[data-hovered="true"]:enabled, &[data-focused="true"]:enabled')
          .styles(raw: {'border-color': 'var(--primary-muted)'}),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('&.ys-lift:focus-visible:not(:active)').styles(raw: ysLifted),
      css('.ys-choice-title').styles(
        margin: .only(top: YsSpace.md.px),
        fontSize: YsType.heading.size.px,
        lineHeight: YsType.heading.lineHeight.px,
        fontWeight: .w500,
        raw: {'white-space': 'nowrap'},
      ),
      css('.ys-choice-body').styles(
        margin: .only(top: YsSpace.xs.px),
        color: .variable('--content-muted'),
        fontSize: YsType.small.size.px,
        lineHeight: YsType.small.lineHeight.px,
      ),
    ]),
  ];
}
