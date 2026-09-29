import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'ys_icon_widget.dart';
import 'ys_pressable.dart';
import 'ys_theme.dart';
import 'ys_tooltip.dart';

/// Buttons built on [YsPressable]: `pill`, `icon`, `primary`, `neutral`,
/// `destructive`.
final class YsButton extends StatelessWidget {
  const YsButton._({
    super.key,
    required this.kind,
    this.label,
    this.icon,
    this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.autofocus = false,
    this.focusNode,
    this.textStyle = YsType.label,
    this.padding = EdgeInsets.zero,
    this.size = 36,
    this.iconSize = 18,
    this.iconColor,
    this.background,
    this.hoverBackground,
  });

  /// Floating pill (Chats, Invite, New side chat): paperClear bg, h36.
  const YsButton.pill({
    required String label,
    required YsIcon icon,
    required VoidCallback? onPressed,
    Key? key,
    String? semanticLabel,
    String? tooltip,
    bool autofocus = false,
    FocusNode? focusNode,
    YsTextStyle textStyle = YsType.heading,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(12, 0, 14, 0),
  }) : this._(
         key: key,
         kind: YsButtonKind.pill,
         label: label,
         icon: icon,
         onPressed: onPressed,
         semanticLabel: semanticLabel ?? label,
         tooltip: tooltip,
         autofocus: autofocus,
         focusNode: focusNode,
         textStyle: textStyle,
         padding: padding,
         size: YsLayout.pillHeight,
         iconSize: 18,
       );

  /// Circular icon button; [size] 27/32/36 with a muted icon.
  const YsButton.icon({
    required YsIcon icon,
    required VoidCallback? onPressed,
    required String semanticLabel,
    Key? key,
    double size = 32,
    double iconSize = 18,
    String? tooltip,
    bool autofocus = false,
    FocusNode? focusNode,
    Color? iconColor,
    Color? background,
    Color? hoverBackground,
  }) : this._(
         key: key,
         kind: YsButtonKind.icon,
         icon: icon,
         onPressed: onPressed,
         semanticLabel: semanticLabel,
         tooltip: tooltip,
         autofocus: autofocus,
         focusNode: focusNode,
         size: size,
         iconSize: iconSize,
         iconColor: iconColor,
         background: background,
         hoverBackground: hoverBackground,
       );

  /// Accent button: primary bg, primaryContent fg, hover primary2.
  const YsButton.primary({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
    YsIcon? icon,
    String? semanticLabel,
    String? tooltip,
    bool autofocus = false,
    FocusNode? focusNode,
  }) : this._(
         key: key,
         kind: YsButtonKind.primary,
         label: label,
         icon: icon,
         onPressed: onPressed,
         semanticLabel: semanticLabel ?? label,
         tooltip: tooltip,
         autofocus: autofocus,
         focusNode: focusNode,
         padding: const EdgeInsets.symmetric(horizontal: 14),
         size: YsLayout.pillHeight,
       );

  /// Neutral pill: neutralAmbient bg.
  const YsButton.neutral({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
    YsIcon? icon,
    String? semanticLabel,
    String? tooltip,
    bool autofocus = false,
    FocusNode? focusNode,
    YsTextStyle textStyle = YsType.label,
    double height = 36,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 14),
  }) : this._(
         key: key,
         kind: YsButtonKind.neutral,
         label: label,
         icon: icon,
         onPressed: onPressed,
         semanticLabel: semanticLabel ?? label,
         tooltip: tooltip,
         autofocus: autofocus,
         focusNode: focusNode,
         textStyle: textStyle,
         padding: padding,
         size: height,
       );

  /// Destructive confirmation (Delete): error bg, content fg; lightens on
  /// hover and darkens while pressed like [YsButton.neutral].
  const YsButton.destructive({
    required String label,
    required VoidCallback? onPressed,
    Key? key,
    YsIcon? icon,
    String? semanticLabel,
    String? tooltip,
    bool autofocus = false,
    FocusNode? focusNode,
  }) : this._(
         key: key,
         kind: YsButtonKind.destructive,
         label: label,
         icon: icon,
         onPressed: onPressed,
         semanticLabel: semanticLabel ?? label,
         tooltip: tooltip,
         autofocus: autofocus,
         focusNode: focusNode,
         padding: const EdgeInsets.symmetric(horizontal: 14),
         size: YsLayout.pillHeight,
       );

  final YsButtonKind kind;
  final String? label;
  final YsIcon? icon;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;
  final bool autofocus;
  final FocusNode? focusNode;
  final YsTextStyle textStyle;
  final EdgeInsetsGeometry padding;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final Color? background;
  final Color? hoverBackground;

  @override
  Widget build(BuildContext context) {
    // One node per button, named by [semanticLabel]: the visible label would
    // repeat it, and a neighbouring field must not merge into it.
    Widget button = Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: YsPressable(
        onPressed: onPressed,
        excludeSemantics: true,
        autofocus: autofocus,
        focusNode: focusNode,
        // A disabled button neither hovers nor presses; it dims like the web
        // kit's `:disabled` rule.
        builder: (context, state) => ExcludeSemantics(
          child: Opacity(
            opacity: state.disabled ? _disabledOpacity : 1,
            child: _buildChild(
              context,
              YsTheme.of(context),
              state.disabled ? const YsPressableState(disabled: true) : state,
            ),
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    if (tooltip != null) {
      button = YsTooltip(message: tooltip, child: button);
    }
    return button;
  }

  /// Web kit `:disabled` opacities.
  double get _disabledOpacity => switch (kind) {
    YsButtonKind.icon => 0.4,
    YsButtonKind.pill => 0.6,
    _ => 0.5,
  };

  Widget _buildChild(
    BuildContext context,
    YsPalette palette,
    YsPressableState state,
  ) {
    return switch (kind) {
      YsButtonKind.pill => _PillShell(
        height: YsLayout.pillHeight,
        padding: padding,
        background: state.hovered || state.pressed
            ? palette.neutralFilmColor
            : palette.paperClearColor,
        // Floating pills hug their label, even under a max width.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YsIconWidget(icon!, size: 18, color: palette.contentColor),
            const SizedBox(width: 8),
            // Long labels (side chat titles) ellipsize within the pill.
            Flexible(
              child: Text(
                label!,
                style: textStyle.flutter.copyWith(color: palette.contentColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
      YsButtonKind.icon => _CircleShell(
        size: size,
        background: state.hovered || state.pressed || state.focused
            ? (hoverBackground ?? palette.neutralFilmColor)
            : (background ?? const Color(0x00000000)),
        child: YsIconWidget(
          icon!,
          size: iconSize,
          color: iconColor ?? palette.contentMutedColor,
        ),
      ),
      YsButtonKind.primary => _PillShell(
        height: YsLayout.pillHeight,
        padding: padding,
        background: state.hovered || state.pressed
            ? palette.primary2Color
            : palette.primaryColor,
        child: _LabelWithIcon(
          label: label!,
          icon: icon,
          style: YsType.label.flutter.copyWith(
            color: palette.primaryContentColor,
          ),
          iconColor: palette.primaryContentColor,
        ),
      ),
      YsButtonKind.neutral => _PillShell(
        height: size,
        padding: padding,
        // Dark buttons: lighten on hover, darken while pressed.
        background: _brightness(
          palette.neutralAmbientColor,
          state.pressed
              ? 0.9
              : state.hovered
              ? 1.15
              : 1,
        ),
        child: _LabelWithIcon(
          label: label!,
          icon: icon,
          style: textStyle.flutter.copyWith(color: palette.contentColor),
          iconColor: palette.contentColor,
        ),
      ),
      YsButtonKind.destructive => _PillShell(
        height: size,
        padding: padding,
        background: _brightness(
          palette.errorColor,
          state.pressed
              ? 0.9
              : state.hovered
              ? 1.15
              : 1,
        ),
        child: _LabelWithIcon(
          label: label!,
          icon: icon,
          style: YsType.label.flutter.copyWith(color: palette.contentColor),
          iconColor: palette.contentColor,
        ),
      ),
    };
  }
}

/// CSS `filter: brightness(factor)` applied to an opaque [color].
Color _brightness(Color color, double factor) => Color.from(
  alpha: color.a,
  red: (color.r * factor).clamp(0, 1),
  green: (color.g * factor).clamp(0, 1),
  blue: (color.b * factor).clamp(0, 1),
);

enum YsButtonKind { pill, icon, primary, neutral, destructive }

/// Rounded button body. It hugs its content wherever the parent leaves the
/// width loose (Align, Center, Row, Wrap) and fills a tight width (a
/// stretched column), like the web kit's inline-flex buttons.
final class _PillShell extends StatelessWidget {
  const _PillShell({
    required this.height,
    required this.padding,
    required this.background,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: YsMotion.fast),
    height: height,
    padding: padding,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(YsRadius.pill),
    ),
    child: Center(widthFactor: 1, child: child),
  );
}

final class _CircleShell extends StatelessWidget {
  const _CircleShell({
    required this.size,
    required this.background,
    required this.child,
  });

  final double size;
  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: YsMotion.fast),
    width: size,
    height: size,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Center(child: child),
  );
}

final class _LabelWithIcon extends StatelessWidget {
  const _LabelWithIcon({
    required this.label,
    required this.style,
    required this.iconColor,
    this.icon,
  });

  final String label;
  final TextStyle style;
  final Color iconColor;
  final YsIcon? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          YsIconWidget(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
        ],
        // A button label is one line; rows of buttons wrap as a whole.
        Text(label, style: style, maxLines: 1, softWrap: false),
      ],
    );
  }
}
