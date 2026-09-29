import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'errors.dart';

/// Pinned CLIProxyAPI release this package embeds and supervises.
const cliproxyVersion = 'v7.3.18';

/// One platform entry of `cliproxy.lock`: the release asset plus the hashes
/// of both the archive and the binary extracted from it.
final class CliproxyLockEntry {
  const CliproxyLockEntry({
    required this.asset,
    required this.archiveSha256,
    required this.binary,
    required this.binarySha256,
  });

  factory CliproxyLockEntry.fromJson(Map<String, Object?> json) {
    String field(String name) {
      final value = json[name];
      if (value is! String || value.isEmpty) {
        throw CliproxyVerificationFailed('cliproxy.lock entry misses $name');
      }
      return value;
    }

    return CliproxyLockEntry(
      asset: field('asset'),
      archiveSha256: field('archive_sha256'),
      binary: field('binary'),
      binarySha256: field('binary_sha256'),
    );
  }

  Map<String, Object?> toJson() => {
    'asset': asset,
    'archive_sha256': archiveSha256,
    'binary': binary,
    'binary_sha256': binarySha256,
  };

  /// Release asset filename, e.g. `CLIProxyAPI_7.3.18_linux_amd64.tar.gz`.
  final String asset;

  /// Lowercase hex sha256 of the downloaded archive.
  final String archiveSha256;

  /// Binary filename inside the archive (`cli-proxy-api[.exe]`).
  final String binary;

  /// Lowercase hex sha256 of the extracted binary.
  final String binarySha256;
}

/// Parsed `cliproxy.lock`: `{version, platforms: {<os>-<arch>: entry}}`.
final class CliproxyLock {
  const CliproxyLock({required this.version, required this.platforms});

  factory CliproxyLock.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    final platforms = json['platforms'];
    if (version is! String || platforms is! Map) {
      throw const CliproxyVerificationFailed(
        'cliproxy.lock misses version/platforms',
      );
    }
    return CliproxyLock(
      version: version,
      platforms: {
        for (final e in platforms.entries)
          '${e.key}': e.value is Map<String, Object?>
              ? CliproxyLockEntry.fromJson(e.value)
              : (throw CliproxyVerificationFailed(
                  'cliproxy.lock platform ${e.key} is not an object',
                )),
      },
    );
  }

  factory CliproxyLock.parse(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw const CliproxyVerificationFailed('cliproxy.lock is not an object');
    }
    return CliproxyLock.fromJson(decoded);
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'platforms': {for (final e in platforms.entries) e.key: e.value.toJson()},
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  final String version;

  /// Keyed by `<os>-<arch>` with os in {linux, macos→`darwin` asset,
  /// windows} — see [currentPlatformKey].
  final Map<String, CliproxyLockEntry> platforms;

  CliproxyLockEntry entryFor(String platformKey) {
    final entry = platforms[platformKey];
    if (entry == null) {
      throw CliproxyVerificationFailed(
        'cliproxy.lock has no $platformKey entry (version $version)',
      );
    }
    return entry;
  }
}

/// `<os>-<arch>` lock key for the current VM: `linux-amd64`,
/// `macos-arm64`, `windows-amd64`, … `Platform.version` cpu names (`x64`,
/// `arm64`, `arm`, `ia32`) map to the Go asset arch (`amd64`, `arm64`, …).
String currentPlatformKey() {
  final os = Platform.isWindows
      ? 'windows'
      : Platform.isMacOS
      ? 'macos'
      : Platform.isLinux
      ? 'linux'
      : null;
  if (os == null) {
    throw CliproxyVerificationFailed(
      'unsupported OS for the CLIProxyAPI sidecar: ${Platform.operatingSystem}',
    );
  }
  // `Platform.version` ends with `on "<os>_<cpu>"`, e.g. `on "linux_x64"`.
  final on = Platform.version.split(' ').lastOrNull?.replaceAll('"', '') ?? '';
  final cpu = on.contains('_') ? on.split('_').last : on;
  final arch = switch (cpu) {
    'x64' => 'amd64',
    'arm64' => 'arm64',
    'arm' => 'arm',
    'ia32' => '386',
    _ => null,
  };
  if (arch == null) {
    throw CliproxyVerificationFailed('unsupported CPU for the sidecar: $cpu');
  }
  return '$os-$arch';
}

/// Asset OS segment for a lock key (`macos-amd64` → `darwin`).
String assetOsFor(String platformKey) {
  final os = platformKey.split('-').first;
  return os == 'macos' ? 'darwin' : os;
}

/// Locates the CLIProxyAPI sidecar binary and verifies it before the first
/// launch.
///
/// A distributed build is compiled with `--dart-define` metadata of the
/// binary it bundles: `HERMUSE_CLIPROXY_SHA256` (lowercase hex digest) and
/// `HERMUSE_CLIPROXY_PLATFORM` (lock key, e.g. `linux-amd64`). With either
/// set, [locate] only accepts the bundle slot — Linux `<exe dir>/lib/cliproxy`,
/// macOS `Contents/MacOS/cliproxy` next to the executable, Windows
/// `<exe dir>\cliproxy.exe` — holding exactly that digest for this machine's
/// platform, and fails otherwise: no fallback to the working directory,
/// `PATH` or a development tree.
///
/// A development build (both empty) verifies
/// `build/cliproxy/<os>-<arch>/cliproxy[.exe]` against `cliproxy.lock`
/// under an explicit package root. The app gets it from the
/// `HERMUSE_CLIPROXY_DEV_ROOT` define, the absolute path of
/// `packages/hermuse_host` after `dart run tool/fetch_cliproxy.dart`:
/// `flutter run -d linux
/// --dart-define=HERMUSE_CLIPROXY_DEV_ROOT=$PWD/../../packages/hermuse_host`
/// from `apps/hermuse_app`.
final class CliproxyBinary {
  /// A sidecar binary. Prefer [locate], which verifies the digest; direct
  /// construction is for tests and callers that verified out of band.
  const CliproxyBinary({required this.path, required this.sha256});

  /// Resolves and verifies the binary for this machine.
  ///
  /// [bundleSha256], [bundlePlatform] and [packageRoot] default to the
  /// compile-time defines described on [CliproxyBinary]; [platformKey]
  /// defaults to [currentPlatformKey] and [executableDir] to the directory
  /// of [Platform.resolvedExecutable]. Throws [CliproxyVerificationFailed]
  /// when the metadata is incomplete, the binary is absent, or its sha256
  /// differs.
  static Future<CliproxyBinary> locate({
    String bundleSha256 = const String.fromEnvironment(
      'HERMUSE_CLIPROXY_SHA256',
    ),
    String bundlePlatform = const String.fromEnvironment(
      'HERMUSE_CLIPROXY_PLATFORM',
    ),
    String packageRoot = const String.fromEnvironment(
      'HERMUSE_CLIPROXY_DEV_ROOT',
    ),
    String? platformKey,
    String? executableDir,
    Future<String> Function(String path)? readText,
    Stream<List<int>> Function(String path)? openRead,
    Future<bool> Function(String path)? fileExists,
  }) async {
    final key = platformKey ?? currentPlatformKey();
    final exists = fileExists ?? ((path) => File(path).exists());
    final read = openRead ?? ((path) => File(path).openRead());
    Future<String> digestOf(String path) async =>
        '${await crypto.sha256.bind(read(path)).first}';
    final sep = Platform.pathSeparator;

    if (bundleSha256.isNotEmpty || bundlePlatform.isNotEmpty) {
      if (bundleSha256.isEmpty || bundlePlatform.isEmpty) {
        throw CliproxyVerificationFailed(
          'incomplete CLIProxyAPI bundle metadata: this build needs both '
          'HERMUSE_CLIPROXY_SHA256 (got "$bundleSha256") and '
          'HERMUSE_CLIPROXY_PLATFORM (got "$bundlePlatform")',
        );
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(bundleSha256)) {
        throw CliproxyVerificationFailed(
          'HERMUSE_CLIPROXY_SHA256 is not a lowercase hex sha256: '
          '"$bundleSha256"',
        );
      }
      if (bundlePlatform != key) {
        throw CliproxyVerificationFailed(
          'this build bundles the $bundlePlatform CLIProxyAPI binary; '
          'this machine is $key',
        );
      }
      final dir =
          executableDir ?? File(Platform.resolvedExecutable).parent.path;
      final bundled = switch (key.split('-').first) {
        'windows' => '$dir${sep}cliproxy.exe',
        // Contents/MacOS, next to the executable inside the .app.
        'macos' => '$dir${sep}cliproxy',
        _ => '$dir${sep}lib${sep}cliproxy',
      };
      if (!await exists(bundled)) {
        throw CliproxyVerificationFailed(
          'the bundled CLIProxyAPI binary is missing: $bundled',
        );
      }
      final digest = await digestOf(bundled);
      if (digest != bundleSha256) {
        throw CliproxyVerificationFailed(
          'bundled CLIProxyAPI hash mismatch for $bundled: expected '
          '$bundleSha256, got $digest',
        );
      }
      return CliproxyBinary(path: bundled, sha256: digest);
    }

    if (packageRoot.isEmpty) {
      throw const CliproxyVerificationFailed(
        'development build without CLIProxyAPI metadata: run '
        'tool/fetch_cliproxy.dart in packages/hermuse_host, then build with '
        '--dart-define=HERMUSE_CLIPROXY_DEV_ROOT=<absolute path of '
        'packages/hermuse_host>',
      );
    }
    final lockPath = '$packageRoot${sep}cliproxy.lock';
    if (!await exists(lockPath)) {
      throw CliproxyVerificationFailed(
        '$lockPath is missing; run tool/fetch_cliproxy.dart',
      );
    }
    final lock = CliproxyLock.parse(
      await (readText ?? ((path) => File(path).readAsString()))(lockPath),
    );
    if (lock.version != cliproxyVersion) {
      throw CliproxyVerificationFailed(
        'cliproxy.lock pins ${lock.version}, this build expects $cliproxyVersion',
      );
    }
    final expected = lock.entryFor(key).binarySha256.toLowerCase();
    final devName = key.startsWith('windows-') ? 'cliproxy.exe' : 'cliproxy';
    final dev = '$packageRoot${sep}build${sep}cliproxy$sep$key$sep$devName';
    if (!await exists(dev)) {
      throw CliproxyVerificationFailed(
        'CLIProxyAPI binary not found at $dev; run tool/fetch_cliproxy.dart',
      );
    }
    final digest = await digestOf(dev);
    if (digest != expected) {
      throw CliproxyVerificationFailed(
        'sidecar hash mismatch for $dev: expected $expected, got $digest',
      );
    }
    return CliproxyBinary(path: dev, sha256: digest);
  }

  /// Absolute path of the verified binary.
  final String path;

  /// Lowercase hex sha256 the binary was verified against.
  final String sha256;
}
