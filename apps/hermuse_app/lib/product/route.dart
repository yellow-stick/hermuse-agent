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

/// Hero drawing of a route that cannot show its content yet (the plugin to
/// turn on, the plugin out of reach), at the start of the column: it plays
/// again under the pointer and loops while [busy] (web
/// `.hermuse-card-art` parity).
final class HermuseRouteArt extends StatelessWidget {
  const HermuseRouteArt(this.art, {this.busy = false, super.key});

  final YsArt art;
  final bool busy;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: YsHover(
      builder: (context, hovered) =>
          YsArtView.hero(art, active: hovered, busy: busy),
    ),
  );
}

/// Section group: 14/20/500 head + 12 gaps. [accent] puts a small primary
/// ink dot before the head (the agent's own "Tracking" goals).
final class HermuseRouteSection extends StatelessWidget {
  const HermuseRouteSection({
    required this.head,
    required this.children,
    this.accent = false,
    super.key,
  });

  final String head;
  final List<Widget> children;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final text = Text(
      head,
      style: YsType.label.flutter.copyWith(color: palette.contentColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accent)
          Row(
            children: [
              Container(
                width: YsLayout.statusDot,
                height: YsLayout.statusDot,
                decoration: BoxDecoration(
                  color: palette.primaryInkColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: YsSpace.sm),
              Expanded(child: text),
            ],
          )
        else
          text,
        const SizedBox(height: 12),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

/// Empty state: its line illustration drawing in above a 16/22/500 title,
/// a 14/20 friendly line and an optional [action]. Pointing at it plays the
/// illustration once more.
final class HermuseRouteEmpty extends StatelessWidget {
  const HermuseRouteEmpty({
    required this.art,
    required this.title,
    required this.body,
    this.action,
    this.size = YsLayout.artEmpty,
    this.top = 48,
    super.key,
  });

  final YsArt art;
  final String title;
  final String body;
  final Widget? action;
  final double size;

  /// Space above the illustration.
  final double top;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final action = this.action;
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: YsHover(
        builder: (context, hovered) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YsArtView(art, size: size, active: hovered),
            const SizedBox(height: YsSpace.md),
            Text(
              title,
              style: YsType.heading.flutter.copyWith(
                color: palette.contentColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: YsSpace.xs + YsSpace.xxs),
            Text(
              body,
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: YsSpace.md), action],
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder of a product list: [count] paper cards whose lines
/// shimmer where the content will be (web `.hermuse-skeleton` parity).
final class HermuseRouteSkeleton extends StatelessWidget {
  const HermuseRouteSkeleton({required this.label, this.count = 2, super.key});

  /// Announced while it shows ("Loading feed").
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: YsSpace.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.paperColor,
                  borderRadius: BorderRadius.circular(YsRadius.bubble),
                  boxShadow: palette.raisedShadows,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: YsSkeleton(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.55,
                          child: YsSkeletonBox(height: 20),
                        ),
                        SizedBox(height: YsSpace.md),
                        FractionallySizedBox(
                          widthFactor: 0.25,
                          child: YsSkeletonBox(height: 12),
                        ),
                        SizedBox(height: YsSpace.lg),
                        YsSkeletonBox(height: 14),
                        SizedBox(height: YsSpace.sm),
                        FractionallySizedBox(
                          widthFactor: 0.8,
                          child: YsSkeletonBox(height: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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
