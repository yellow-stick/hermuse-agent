import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hermuse_update/hermuse_update.dart';
import 'package:http/http.dart' as http;

/// The platform the running app installs on, resolved from `dart:io` (never
/// sent anywhere; only selects the release artifact). iOS and Android have
/// no published artifacts yet: they resolve like the desktop ones and find
/// nothing until the pipeline ships them.
AppPlatform currentAppPlatform({bool? isDebInstall}) {
  if (kIsWeb) return AppPlatform.linuxAppImage;
  if (Platform.isAndroid) return AppPlatform.android;
  if (Platform.isIOS) return AppPlatform.ios;
  if (Platform.isMacOS) return AppPlatform.macos;
  if (Platform.isWindows) return AppPlatform.windows;
  if (Platform.isLinux) {
    return isDebInstall ?? _looksLikeDebInstall()
        ? AppPlatform.linuxDeb
        : AppPlatform.linuxAppImage;
  }
  return AppPlatform.linuxAppImage;
}

/// The `.deb` lands under `/opt` with a `/usr/bin` launcher; anything else
/// on Linux is the portable bundle. Reads the process path, never the FS.
bool _looksLikeDebInstall() {
  final exe = Platform.resolvedExecutable.toLowerCase();
  return exe.startsWith('/opt/') || exe.startsWith('/usr/');
}

/// The running app's version: the `HERMUSE_APP_VERSION` define baked at
/// release time (`0.1.0+1`, the app pubspec), or [fallback] in dev builds
/// (kept wrong on purpose: a dev build must never claim it is up to date,
/// it just skips the prompt). Mobile reads the same value: Gradle and Xcode
/// already take `versionName`/`FLUTTER_BUILD_NAME` from that pubspec.
const appVersionBuildDefine = String.fromEnvironment(
  'HERMUSE_APP_VERSION',
  defaultValue: '',
);

String currentAppVersion({String? fallback}) => appVersionBuildDefine.isNotEmpty
    ? appVersionBuildDefine
    : (fallback ?? '0.0.0+0');

/// One release-feed check against our releases with a sane default client.
/// Throws [UpdateCheckException]; callers catch it into "check failed".
Future<UpdateCheck> checkAppUpdate({
  http.Client? client,
  String? currentVersion,
  AppPlatform? platform,
}) {
  final owned = client == null;
  final httpClient = client ?? http.Client();
  try {
    return checkForUpdate(
      client: httpClient,
      currentVersion: currentVersion ?? currentAppVersion(),
      platform: platform ?? currentAppPlatform(),
    );
  } finally {
    if (owned) httpClient.close();
  }
}

/// Per-version skip: the user dismissed the prompt for this tag.
String skipKey(String tag) => 'update_dismissed:$tag';

/// How often the shell re-checks (once a day): last check timestamp holder.
String get lastCheckKey => 'update_last_check_ms';

/// True when a daily re-check is due (never checked counts as due).
bool dailyCheckDue(int? lastCheckMs, {DateTime? now}) {
  if (lastCheckMs == null) return true;
  final at = DateTime.fromMillisecondsSinceEpoch(lastCheckMs);
  return (now ?? DateTime.now()).difference(at) >= const Duration(hours: 20);
}
