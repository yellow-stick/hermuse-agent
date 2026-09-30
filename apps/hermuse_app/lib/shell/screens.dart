import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import 'mascot.dart';

/// Shared dialog card: paper surface, r22 bubble radius, 32/28 padding,
/// 16 gaps — the same spec as the web `.hermuse-card`.
final class YsDialogCard extends StatelessWidget {
  const YsDialogCard({required this.children, this.narrow = false, super.key});

  final List<Widget> children;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: narrow ? YsLayout.dialogNarrow : YsLayout.dialogWidth,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paperColor,
            borderRadius: BorderRadius.circular(YsRadius.bubble),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card illustration: [art] draws in when the card shows, plays again under
/// the pointer and loops while [busy] (work under way). Web parity:
/// `HermuseCardArt`.
final class YsDialogArt extends StatelessWidget {
  const YsDialogArt(this.art, {this.busy = false, super.key});

  final YsArt art;
  final bool busy;

  @override
  Widget build(BuildContext context) => Center(
    child: YsHover(
      builder: (context, hovered) =>
          YsArtView(art, size: YsLayout.artStep, active: hovered, busy: busy),
    ),
  );
}

/// Full-screen wait: [art] loops in the middle of the canvas until what
/// the screen waits for arrives; [label] is announced.
final class LoadingScreen extends StatelessWidget {
  const LoadingScreen({required this.art, required this.label, super.key});

  final YsArt art;
  final String label;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: YsTheme.of(context).canvasColor,
    child: Center(
      child: Semantics(
        label: label,
        liveRegion: true,
        child: YsDialogArt(art, busy: true),
      ),
    ),
  );
}

/// Full-width primary call to action, 40 high (web `.hermuse-card-cta`).
final class YsDialogCta extends StatelessWidget {
  const YsDialogCta({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: YsPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: state.hovered ? palette.primary2Color : palette.primaryColor,
            borderRadius: BorderRadius.circular(YsRadius.pill),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: YsType.label.flutter.copyWith(
              color: palette.primaryContentColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary actions as quiet text links separated by dots
/// (web `.hermuse-card-links`).
final class YsDialogLinks extends StatelessWidget {
  const YsDialogLinks(this.links, {super.key});

  final List<(String label, VoidCallback onPressed)> links;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0)
            Text(
              '·',
              style: YsType.label.flutter.copyWith(
                color: palette.contentSubtleColor,
              ),
            ),
          YsPressable(
            onPressed: links[i].$2,
            semanticLabel: links[i].$1,
            builder: (context, state) => Text(
              links[i].$1,
              maxLines: 1,
              style: YsType.label.flutter.copyWith(
                color: state.hovered
                    ? palette.contentColor
                    : palette.contentMutedColor,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Card title: 22/28/500 centered.
final class YsDialogTitle extends StatelessWidget {
  const YsDialogTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      text,
      style: YsType.title.flutter.copyWith(color: palette.contentColor),
      textAlign: TextAlign.center,
    );
  }
}

/// Card body: 16/22 muted centered.
final class YsDialogBody extends StatelessWidget {
  const YsDialogBody(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Text(
      text,
      style: YsType.body.flutter.copyWith(color: palette.contentMutedColor),
      textAlign: TextAlign.center,
    );
  }
}

/// First-run screen: the registry is empty, so there is no chat yet. The
/// mascot says hello above one big card per way to start.
final class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({required this.onConnect, this.onInstall, super.key});

  final VoidCallback onConnect;

  /// Desktop only: install (or adopt) Hermes on this computer.
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = YsTheme.of(context);
    final cards = [
      YsChoiceCard(
        art: YsArt.remote,
        title: 'Connect to a Hermes',
        body: 'A Hermes already running on a server or another computer.',
        onPressed: onConnect,
      ),
      if (onInstall case final install?)
        YsChoiceCard(
          art: YsArt.local,
          title: 'Install Hermes on this computer',
          body: 'Hermuse installs it here and keeps it running for you.',
          onPressed: install,
        ),
    ];
    return YsEntrance(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(YsSpace.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: YsLayout.listWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HermuseMascot(),
                const SizedBox(height: YsSpace.xl),
                Text(
                  "Hi, I'm Hermuse",
                  textAlign: TextAlign.center,
                  style: YsType.title.flutter.copyWith(
                    color: palette.contentColor,
                  ),
                ),
                const SizedBox(height: YsSpace.sm),
                Text(
                  'I run on your own Hermes Agent. How do you want to start?',
                  textAlign: TextAlign.center,
                  style: YsType.body.flutter.copyWith(
                    color: palette.contentMutedColor,
                  ),
                ),
                const SizedBox(height: YsSpace.xxl),
                LayoutBuilder(
                  builder: (context, constraints) =>
                      cards.length > 1 &&
                          constraints.maxWidth >=
                              YsLayout.choiceMin * cards.length +
                                  YsSpace.lg * (cards.length - 1)
                      ? IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, card) in cards.indexed) ...[
                                if (i > 0) const SizedBox(width: YsSpace.lg),
                                Expanded(child: card),
                              ],
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (i, card) in cards.indexed) ...[
                              if (i > 0) const SizedBox(height: YsSpace.md),
                              card,
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Blocking screen shown when the platform keystore is unavailable (macOS,
/// Windows; Linux repairs it in its setup assistant instead).
final class KeystoreErrorScreen extends StatelessWidget {
  const KeystoreErrorScreen({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => YsEntrance(
    child: YsDialogCard(
      children: [
        YsDialogArt(YsArt.unreachable),
        const YsDialogTitle('Secure storage unavailable'),
        YsDialogBody(
          'Hermuse keeps your Hermes credentials in the system keyring, '
          'which could not be reached. Nothing was stored in plain text.\n\n'
          'Unlock the system keyring, then restart Hermuse.\n\n$error',
        ),
      ],
    ),
  );
}

/// Something went wrong loading the chat: registry, connection or resume.
final class ChatErrorScreen extends StatelessWidget {
  const ChatErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onManageInstances,
    super.key,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onManageInstances;

  @override
  Widget build(BuildContext context) {
    return YsEntrance(
      child: YsDialogCard(
        children: [
          YsDialogArt(YsArt.unreachable),
          const YsDialogTitle('Could not open the chat'),
          YsDialogBody(describeError(error)),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              YsButton.primary(label: 'Retry', onPressed: onRetry),
              const SizedBox(width: 12),
              YsButton.neutral(
                label: 'Instances',
                onPressed: onManageInstances,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// User-facing sentence of a failure (server message, not a stack dump).
String describeError(Object error) => switch (error) {
  HermesException(:final message) => message,
  StateError(:final message) => message,
  _ => '$error',
};
