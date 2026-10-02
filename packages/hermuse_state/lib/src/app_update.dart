import 'package:hermuse_update/hermuse_update.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'app_update.g.dart';

/// How often the shell re-checks the releases feed.
const appUpdateRecheckInterval = Duration(hours: 20);

/// Outcome of one app-update check: the feed comparison, or the failure.
sealed class AppUpdateStatus {
  const AppUpdateStatus();
}

/// Nothing newer published (or no artifact for this platform yet).
final class AppUpdateCurrent extends AppUpdateStatus {
  const AppUpdateCurrent(this.check);
  final UpdateCheck check;
}

/// A newer release with an install artifact for this platform.
final class AppUpdateAvailable extends AppUpdateStatus {
  const AppUpdateAvailable(this.check);
  final UpdateCheck check;
}

/// The check failed (offline, rate-limited, feed unreadable): silent, retry
/// on the next cadence. The message is for tests/logs, never a user prompt.
final class AppUpdateFailed extends AppUpdateStatus {
  const AppUpdateFailed(this.message);
  final String message;
}

/// App-update check state: one cached feed result plus its persistence.
///
/// Network through [httpClientProvider]; persistence in the settings table
/// (per-version skip, last-check timestamp), so both apps share it. The
/// running version and platform are injected for tests; production passes
/// the real ones from `app_update.dart` of each app.
@riverpod
class AppUpdate extends _$AppUpdate {
  static const _skipPrefix = 'update_dismissed:';
  static const _lastCheckKey = 'update_last_check_ms';

  @override
  Future<AppUpdateStatus?> build({
    String? currentVersion,
    AppPlatform? platform,
  }) async {
    final db = ref.watch(hermuseDatabaseProvider);
    final client = ref.watch(httpClientProvider);
    final version = currentVersion ?? '0.0.0+0';
    final target = platform ?? AppPlatform.linuxAppImage;
    final lastRaw = await db.readSetting(_lastCheckKey);
    final lastMs = int.tryParse(lastRaw ?? '');
    final now = DateTime.now();
    if (lastMs != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)) <
            appUpdateRecheckInterval) {
      return null;
    }
    await db.writeSetting(_lastCheckKey, '${now.millisecondsSinceEpoch}');
    try {
      final check = await checkForUpdate(
        client: client,
        currentVersion: version,
        platform: target,
      );
      if (!check.updateAvailable) {
        return AppUpdateCurrent(check);
      }
      final skipped = await db.readSetting('$_skipPrefix${check.release!.tag}');
      if (skipped == 'true') return AppUpdateCurrent(check);
      return AppUpdateAvailable(check);
    } on UpdateCheckException catch (e) {
      return AppUpdateFailed(e.message);
    }
  }

  /// The user dismissed the prompt for this tag: never shown again.
  Future<void> dismiss(String tag) async {
    await ref
        .read(hermuseDatabaseProvider)
        .writeSetting('$_skipPrefix$tag', 'true');
    final status = state.value;
    if (status is AppUpdateAvailable && status.check.release?.tag == tag) {
      state = AsyncData(AppUpdateCurrent(status.check));
    }
  }

  /// Recheck now, ignoring the cadence (settings "Check for updates").
  Future<void> recheck() async {
    await ref.read(hermuseDatabaseProvider).writeSetting(_lastCheckKey, '0');
    ref.invalidateSelf();
  }
}
