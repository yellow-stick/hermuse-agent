import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

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

/// Card icon: 56 primary disc (web `.hermuse-card-icon`).
final class YsDialogIcon extends StatelessWidget {
  const YsDialogIcon(this.icon, {super.key});

  final YsIcon icon;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return Center(
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.primaryColor,
          shape: BoxShape.circle,
        ),
        child: YsIconWidget(icon, size: 28, color: palette.primaryContentColor),
      ),
    );
  }
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

/// First-run screen: the registry is empty, so there is no chat yet.
final class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({required this.onConnect, this.onInstall, super.key});

  final VoidCallback onConnect;

  /// Desktop only: install (or adopt) Hermes on this computer.
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return YsDialogCard(
      narrow: true,
      children: [
        const YsDialogTitle('Connect to a Hermes'),
        const YsDialogBody(
          'Hermuse talks to your own Hermes instances. '
          'Add one to start chatting.',
        ),
        Center(
          child: YsButton.primary(
            label: 'Connect to a Hermes',
            icon: YsIcon.plus,
            onPressed: onConnect,
          ),
        ),
        if (onInstall case final install?)
          Center(
            child: YsButton.neutral(
              label: 'Install Hermes on this computer',
              onPressed: install,
            ),
          ),
      ],
    );
  }
}

/// Blocking screen shown when the platform keystore is unavailable.
final class KeystoreErrorScreen extends StatelessWidget {
  const KeystoreErrorScreen({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    return YsDialogCard(
      children: [
        Center(
          child: YsIconWidget(
            YsIcon.approvals,
            size: 32,
            color: palette.errorColor,
          ),
        ),
        const YsDialogTitle('Secure storage unavailable'),
        YsDialogBody(
          'Hermuse keeps your Hermes credentials in the system keyring, '
          'which could not be reached. Nothing was stored in plain text.\n\n'
          'On Linux this usually means libsecret is missing or the '
          'keyring is locked: install gnome-keyring and unlock it, '
          'then restart Hermuse.\n\n$error',
        ),
      ],
    );
  }
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
    return YsDialogCard(
      children: [
        const YsDialogTitle('Could not open the chat'),
        YsDialogBody(describeError(error)),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            YsButton.primary(label: 'Retry', onPressed: onRetry),
            const SizedBox(width: 12),
            YsButton.neutral(label: 'Instances', onPressed: onManageInstances),
          ],
        ),
      ],
    );
  }
}

/// User-facing sentence of a failure (server message, not a stack dump).
String describeError(Object error) => switch (error) {
  HermesException(:final message) => message,
  StateError(:final message) => message,
  _ => '$error',
};
