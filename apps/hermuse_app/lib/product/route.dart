import 'package:flutter/widgets.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

/// Shared route page: centered column (768, 1152 when [wide]), 72/24/48
/// padding, 24 gaps, 34/40/600 display header (web `route_styles.dart` parity).
///
/// Under a [RouteChatToggle] (wide shell) the top-left of the route area
/// holds the side-by-side chat button.
final class HermuseRoute extends StatelessWidget {
  const HermuseRoute({
    required this.title,
    required this.children,
    this.wide = false,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> children;
  final bool wide;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final compact = MediaQuery.sizeOf(context).width < YsLayout.compactMax;
    final page = ColoredBox(
      color: palette.canvasColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: wide ? 1152 : YsLayout.threadMaxWidth,
          ),
          child: ListView(
            padding: EdgeInsets.only(
              top: compact ? 16 : 72,
              left: compact
                  ? YsLayout.threadGutterPhone
                  : YsLayout.threadGutter,
              right: compact
                  ? YsLayout.threadGutterPhone
                  : YsLayout.threadGutter,
              bottom: compact ? YsLayout.threadBottomPad : 48,
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: YsType.display.flutter.copyWith(
                        color: palette.contentColor,
                      ),
                    ),
                  ),
                  for (final action in actions) ...[
                    const SizedBox(width: 12),
                    action,
                  ],
                ],
              ),
              for (final child in children) ...[
                const SizedBox(height: 24),
                child,
              ],
            ],
          ),
        ),
      ),
    );
    final toggle = RouteChatToggle.maybeOf(context);
    if (toggle == null) return page;
    final label = toggle.open ? 'Maximize' : 'Open side-by-side chat';
    return Stack(
      children: [
        Positioned.fill(child: page),
        Positioned(
          left: 12,
          top: 12,
          child: YsButton.icon(
            icon: toggle.open ? YsIcon.maximize : YsIcon.panelLeft,
            onPressed: toggle.onToggle,
            semanticLabel: label,
            tooltip: label,
            size: 36,
            iconSize: 20,
          ),
        ),
      ],
    );
  }
}

/// Side-by-side chat of the wide shell: routes show "Open
/// side-by-side chat" at their top-left, or "Maximize" while the chat is
/// docked beside them ([open]).
final class RouteChatToggle extends InheritedWidget {
  const RouteChatToggle({
    required this.open,
    required this.onToggle,
    required super.child,
    super.key,
  });

  final bool open;
  final VoidCallback onToggle;

  static RouteChatToggle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RouteChatToggle>();

  @override
  bool updateShouldNotify(RouteChatToggle oldWidget) =>
      open != oldWidget.open || onToggle != oldWidget.onToggle;
}

/// Muted 16/22 route subtitle.
final class HermuseRouteSub extends StatelessWidget {
  const HermuseRouteSub(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      text,
      style: YsType.body.flutter.copyWith(color: palette.contentMutedColor),
    );
  }
}

/// 14/20 error line (primary-2, like web).
final class HermuseRouteError extends StatelessWidget {
  const HermuseRouteError(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      text,
      style: YsType.label.flutter.copyWith(color: palette.primary2Color),
    );
  }
}

/// Section group: 14/20/500 head + 12 gaps.
final class HermuseRouteSection extends StatelessWidget {
  const HermuseRouteSection({
    required this.head,
    required this.children,
    super.key,
  });

  final String head;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          head,
          style: YsType.label.flutter.copyWith(color: palette.contentColor),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

/// Empty state: 26 icon + 16/22/500 title + 14/20 body, top pad 48.
final class HermuseRouteEmpty extends StatelessWidget {
  const HermuseRouteEmpty({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final YsIcon icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          YsIconWidget(icon, size: 26, color: palette.contentMutedColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: YsType.heading.flutter.copyWith(color: palette.contentColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Monospace command block (plugin-missing screen).
final class HermuseCodeBlock extends StatelessWidget {
  const HermuseCodeBlock(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.canvasColor,
        borderRadius: BorderRadius.circular(YsRadius.row),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 20 / 13,
              ).copyWith(color: palette.contentColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// Text link in primary-2 (web `.hermuse-ob-link` parity).
final class HermuseLink extends StatelessWidget {
  const HermuseLink({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Text(
        label,
        style: YsType.label.flutter.copyWith(color: palette.primary2Color),
      ),
    );
  }
}
