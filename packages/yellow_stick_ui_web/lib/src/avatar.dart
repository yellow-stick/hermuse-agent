import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'icon.dart';
import 'pressable.dart';

/// Circular avatar image on an `--avatar-surface` disc, with an optional
/// edit badge button (pencil). Transparent artwork is drawn over the disc.
class YsAvatar extends StatelessComponent {
  const YsAvatar({
    required this.src,
    this.alt = '',
    this.size = 100,
    this.onEdit,
    this.editLabel = 'Edit',
    super.key,
  });

  /// Image URL.
  final String src;

  /// Accessible description; empty marks the image decorative (the default,
  /// for avatars inside labelled buttons).
  final String alt;
  final double size;
  final VoidCallback? onEdit;
  final String editLabel;

  @override
  Component build(BuildContext context) => div(
    classes: 'ys-avatar',
    styles: Styles(width: size.px, height: size.px),
    [
      img(
        classes: 'ys-avatar-img',
        src: src,
        alt: alt,
        width: size.round(),
        height: size.round(),
        attributes: {'decoding': 'async'},
      ),
      if (onEdit != null)
        YsPressable(
          onPressed: onEdit,
          label: editLabel,
          classes: 'ys-avatar-badge',
          builder: (context, state) => YsIconView(YsIcon.pencil, size: 14),
        ),
    ],
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-avatar', [
      css('&').styles(position: .relative(), raw: {'flex-shrink': '0'}),
      css('.ys-avatar-img').styles(
        display: .block,
        width: 100.percent,
        height: 100.percent,
        radius: .circular(YsRadius.pill.px),
        backgroundColor: .variable('--avatar-surface'),
        raw: {'object-fit': 'cover'},
      ),
      css('.ys-avatar-badge').styles(
        position: .absolute(right: (-2).px, bottom: (-2).px),
        width: 32.px,
        height: 32.px,
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .flex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-ambient'),
        cursor: .pointer,
        border: .all(style: .solid, color: .variable('--canvas'), width: 2.px),
      ),
      css('.ys-avatar-badge:hover')
          .styles(backgroundColor: .variable('--neutral-film')),
      css('.ys-avatar-badge:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
  ];
}
