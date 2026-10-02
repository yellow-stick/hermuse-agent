import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hermuse_update/hermuse_update.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/open_url.dart';

/// Update prompt over the releases feed: what is new, which file to fetch,
/// how to install it on this platform. Download-only, never auto-install:
/// Linux `.deb` needs APT, the AppImage a file swap, macOS a `.dmg` drag,
/// Windows an Inno Setup run, mobile the store listing.
final class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({
    required this.check,
    required this.platform,
    required this.onClose,
    required this.onDismissVersion,
    super.key,
  });

  final UpdateCheck check;
  final AppPlatform platform;
  final VoidCallback onClose;

  /// "Skip this version": persisted per tag, never shown again.
  final VoidCallback onDismissVersion;

  String get _installHint => switch (platform) {
    AppPlatform.android => 'Install it from the store listing.',
    AppPlatform.ios => 'Install it from the App Store listing.',
    AppPlatform.linuxDeb => 'Install the newer .deb the same way (`sudo apt-get install ./file.deb`).',
    AppPlatform.linuxAppImage =>
      'Replace the AppImage file with the newer one.',
    AppPlatform.macos =>
      'Open the .dmg and drag Hermuse Agent to Applications.',
    AppPlatform.windows =>
      'Run the Setup.exe; it installs for the current user.',
  };

  String get _size {
    final bytes = check.asset?.sizeBytes ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final palette = YsTheme.of(context);
    final release = check.release!;
    final asset = check.asset!;
    final size = _size;
    return YsDialog(
      title: 'Hermuse Agent ${release.version} available',
      onClose: onClose,
      actions: [
        YsButton.neutral(label: 'Later', onPressed: onClose),
        YsButton.primary(
          label: 'Download',
          onPressed: () => unawaited(openExternalUrl(asset.downloadUrl)),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'You run ${check.current} on ${platform.label}; '
            '${asset.name}${size.isEmpty ? '' : ' ($size)'} is ready.',
            style: YsType.small.flutter.copyWith(color: palette.contentColor),
          ),
          const SizedBox(height: 8),
          Text(
            _installHint,
            style: YsType.small.flutter.copyWith(
              color: palette.contentMutedColor,
            ),
          ),
          if (asset.sha256 != null) ...[
            const SizedBox(height: 8),
            Text(
              'SHA-256: ${asset.sha256}',
              style: YsType.caption.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
          if (release.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              release.notes.trim(),
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
              ),
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              onDismissVersion();
              onClose();
            },
            child: Text(
              'Skip this version',
              style: YsType.small.flutter.copyWith(
                color: palette.contentMutedColor,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
