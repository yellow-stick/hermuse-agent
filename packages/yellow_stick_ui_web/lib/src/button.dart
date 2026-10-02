import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'icon.dart';
import 'pressable.dart';

/// Button variants on top of [YsPressable].
abstract final class YsButton {
  /// Pill with a [paperClear] background: floating "Chats"/"Invite" pills,
  /// "New side chat".
  static Component pill({
    YsIcon? icon,
    required String label,
    VoidCallback? onPressed,
    String? tooltip,
    bool small = false,
    Key? key,
  }) => YsPillButton(
    icon: icon,
    label: label,
    onPressed: onPressed,
    tooltip: tooltip,
    small: small,
    key: key,
  );

  /// Circular icon button; [size] is the hit circle diameter. [attributes]
  /// add ARIA state (e.g. `aria-haspopup` / `aria-expanded` on a menu
  /// trigger).
  static Component icon({
    required YsIcon icon,
    required String label,
    VoidCallback? onPressed,
    double size = 36,
    double iconSize = 18,
    Map<String, String>? attributes,
    Key? key,
  }) => YsIconButton(
    icon: icon,
    label: label,
    onPressed: onPressed,
    size: size,
    iconSize: iconSize,
    attributes: attributes,
    key: key,
  );

  /// Brand accent filled button (primary bg, primaryContent fg).
  static Component primary({
    required String label,
    VoidCallback? onPressed,
    Key? key,
  }) => YsFilledButton(
    label: label,
    onPressed: onPressed,
    tone: YsFilledTone.primary,
    key: key,
  );

  /// Neutral filled button (neutralAmbient).
  static Component neutral({
    required String label,
    VoidCallback? onPressed,
    Key? key,
  }) => YsFilledButton(
    label: label,
    onPressed: onPressed,
    tone: YsFilledTone.neutral,
    key: key,
  );

  /// Error filled button confirming a destructive action (Delete).
  static Component destructive({
    required String label,
    VoidCallback? onPressed,
    Key? key,
  }) => YsFilledButton(
    label: label,
    onPressed: onPressed,
    tone: YsFilledTone.destructive,
    key: key,
  );
}

class YsPillButton extends StatelessComponent {
  const YsPillButton({
    this.icon,
    required this.label,
    this.onPressed,
    this.tooltip,
    this.small = false,
    super.key,
  });

  final YsIcon? icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool small;

  @override
  Component build(BuildContext context) {
    final icon = this.icon;
    return YsPressable(
      onPressed: onPressed,
      label: tooltip == null ? null : label,
      classes: small ? 'ys-btn-pill ys-btn-pill-sm' : 'ys-btn-pill',
      builder: (context, state) => .fragment([
        if (icon != null) YsIconView(icon, size: 18),
        span(classes: 'ys-btn-pill-label', [.text(label)]),
        if (tooltip != null)
          span(classes: 'ys-tooltip ys-tooltip-below', [.text(tooltip!)]),
      ]),
    );
  }

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-btn-pill', [
      css('&').styles(
        height: YsLayout.pillHeight.px,
        padding: .symmetric(horizontal: 14.px),
        radius: .circular(YsRadius.pill.px),
        display: .inlineFlex,
        flexDirection: .row,
        justifyContent: .center,
        alignItems: .center,
        gap: .all(8.px),
        color: .variable('--content'),
        backgroundColor: .variable('--paper-clear'),
        cursor: .pointer,
        border: .none,
        position: .relative(),
        raw: {'backdrop-filter': 'blur(12px)', 'box-shadow': 'var(--raised)'},
      ),
      css('&:hover').styles(backgroundColor: .variable('--neutral-film')),
      css('&:disabled').styles(cursor: .defaultCursor, opacity: 0.6),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.ys-btn-pill-label')
          .styles(fontSize: 16.px, lineHeight: 22.px, fontWeight: .w500),
      css('&.ys-btn-pill-sm').styles(
        height: 28.px,
        padding: .symmetric(horizontal: 12.px),
      ),
      css('&.ys-btn-pill-sm .ys-btn-pill-label')
          .styles(fontSize: 12.px, lineHeight: 16.px, fontWeight: .w500),
    ]),
  ];
}

class YsIconButton extends StatelessComponent {
  const YsIconButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.size = 36,
    this.iconSize = 18,
    this.attributes,
    super.key,
  });

  final YsIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Map<String, String>? attributes;

  @override
  Component build(BuildContext context) => YsPressable(
    onPressed: onPressed,
    label: label,
    classes: 'ys-btn-icon',
    styles: Styles(width: size.px, height: size.px),
    attributes: attributes,
    builder: (context, state) => YsIconView(icon, size: iconSize),
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-btn-icon', [
      css('&').styles(
        padding: .zero,
        radius: .circular(YsRadius.pill.px),
        display: .inlineFlex,
        justifyContent: .center,
        alignItems: .center,
        color: .variable('--content-muted'),
        backgroundColor: Colors.transparent,
        cursor: .pointer,
        border: .none,
        // Always a circle: a stretching flex parent must not turn it into a
        // tall pill.
        raw: {'flex-shrink': '0', 'align-self': 'center'},
      ),
      css('&:hover').styles(
        backgroundColor: .variable('--neutral-film'),
        color: .variable('--content'),
      ),
      css('&:disabled').styles(cursor: .defaultCursor, opacity: 0.4),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
    ]),
  ];
}

/// Fill of a [YsFilledButton].
enum YsFilledTone { primary, neutral, destructive }

class YsFilledButton extends StatelessComponent {
  const YsFilledButton({
    required this.label,
    this.onPressed,
    required this.tone,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final YsFilledTone tone;

  @override
  Component build(BuildContext context) => YsPressable(
    onPressed: onPressed,
    classes: 'ys-btn-filled ys-btn-${tone.name}',
    builder: (context, state) =>
        span(classes: 'ys-btn-filled-label', [.text(label)]),
  );

  @css
  // ignore: unused_element
  static List<StyleRule> get styles => [
    css('.ys-btn-filled', [
      css('&').styles(
        height: 36.px,
        padding: .symmetric(horizontal: 16.px),
        radius: .circular(YsRadius.pill.px),
        display: .inlineFlex,
        justifyContent: .center,
        alignItems: .center,
        cursor: .pointer,
        border: .none,
        // A button label is one line; rows of buttons wrap as a whole.
        flex: .shrink(0),
        raw: {'white-space': 'nowrap'},
      ),
      css('&:disabled').styles(cursor: .defaultCursor, opacity: 0.5),
      css('&:focus-visible').styles(
        outline: Outline(
          style: OutlineStyle.solid,
          color: .variable('--primary-ink'),
          width: OutlineWidth(2.px),
        ),
      ),
      css('.ys-btn-filled-label')
          .styles(fontSize: 14.px, lineHeight: 20.px, fontWeight: .w500),
    ]),
    css('.ys-btn-primary', [
      css('&').styles(
        color: .variable('--primary-content'),
        backgroundColor: .variable('--primary'),
      ),
      css('&:hover').styles(backgroundColor: .variable('--primary-2')),
    ]),
    css('.ys-btn-neutral', [
      css('&').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--neutral-ambient'),
      ),
      // Dark buttons: lighten on hover, darken while pressed.
      css('&:hover:enabled').styles(raw: {'filter': 'brightness(1.15)'}),
      css('&:active:enabled').styles(raw: {'filter': 'brightness(0.9)'}),
    ]),
    css('.ys-btn-destructive', [
      css('&').styles(
        color: .variable('--content'),
        backgroundColor: .variable('--error'),
      ),
      css('&:hover:enabled').styles(raw: {'filter': 'brightness(1.1)'}),
      css('&:active:enabled').styles(raw: {'filter': 'brightness(0.9)'}),
    ]),
  ];
}
