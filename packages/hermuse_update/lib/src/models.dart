import 'version.dart';

/// A platform the app runs on, selected by the app layer (`dart:io` is
/// unavailable here so this package stays web-compatible).
enum AppPlatform {
  /// Google Play / sideloaded `.apk` (matched when the pipeline publishes one).
  android,

  /// App Store / TestFlight `.ipa` (matched when the pipeline publishes one).
  ios,

  /// Debian/Ubuntu `.deb` installed with APT.
  linuxDeb,

  /// Portable `Hermuse-Agent-*-linux-x86_64.AppImage`.
  linuxAppImage,

  /// `Hermuse-Agent-*-macos-arm64.dmg`.
  macos,

  /// `Hermuse-Agent-*-windows-x64-Setup.exe` (current-user Inno Setup).
  windows;

  /// Human label for the update dialog.
  String get label => switch (this) {
    AppPlatform.android => 'Android',
    AppPlatform.ios => 'iOS',
    AppPlatform.linuxDeb => 'Linux (.deb)',
    AppPlatform.linuxAppImage => 'Linux (AppImage)',
    AppPlatform.macos => 'macOS',
    AppPlatform.windows => 'Windows',
  };

  /// True when [fileName] is the install artifact for this platform.
  bool matchesArtifact(String fileName) => switch (this) {
    AppPlatform.android => fileName.endsWith('.apk'),
    AppPlatform.ios => fileName.endsWith('.ipa'),
    AppPlatform.linuxDeb => fileName.endsWith('.deb'),
    AppPlatform.linuxAppImage => fileName.endsWith('.AppImage'),
    AppPlatform.macos => fileName.endsWith('.dmg'),
    AppPlatform.windows => fileName.endsWith('Setup.exe'),
  };
}

/// One file attached to a GitHub release.
final class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
  });

  final String name;

  /// `browser_download_url`: the public download, never replaced afterwards.
  final String downloadUrl;
  final int sizeBytes;

  /// Expected SHA-256 from the release's `VERSION.json`, null when the
  /// fragment could not be read (best effort, the download URL stays valid).
  final String? sha256;

  ReleaseAsset withSha256(String sha256) => ReleaseAsset(
    name: name,
    downloadUrl: downloadUrl,
    sizeBytes: sizeBytes,
    sha256: sha256,
  );
}

/// One published Hermuse release (`hermuse/v*` tag, drafts excluded).
final class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.htmlUrl,
    required this.notes,
    required this.prerelease,
    required this.assets,
  });

  final AppVersion version;

  /// The `hermuse/vX.Y.Z[-rc.N]` tag; also the skip-version key.
  final String tag;

  /// The release page (fallback when no platform artifact matches).
  final String htmlUrl;

  /// Release notes body (may be empty).
  final String notes;

  /// Our releases publish as pre-releases (`latest=false`), so a checker
  /// that skips them finds nothing: callers include them by default.
  final bool prerelease;
  final List<ReleaseAsset> assets;

  /// The install artifact for [platform], null when this release ships
  /// nothing for it (e.g. no mobile builds yet).
  ReleaseAsset? assetFor(AppPlatform platform) =>
      assets.where((a) => platform.matchesArtifact(a.name)).firstOrNull;
}

/// The outcome of one release-feed check.
final class UpdateCheck {
  const UpdateCheck({
    required this.current,
    required this.release,
    required this.asset,
  });

  /// The running app's version.
  final AppVersion current;

  /// Newest release carrying an artifact for the platform, null when the
  /// feed has none (network already succeeded: nothing published yet).
  final AppRelease? release;

  /// That release's artifact for the platform (null with [release]).
  final ReleaseAsset? asset;

  /// A newer release with a platform artifact exists.
  bool get updateAvailable =>
      release != null &&
      asset != null &&
      release!.version.compareTo(current) > 0;
}
