import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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

/// Locates the CLIProxyAPI sidecar binary and verifies it against
/// `cliproxy.lock` before the first launch.
///
/// Bundle layout (checked first): Linux `<exe dir>/lib/cliproxy`,
/// macOS `Contents/MacOS/cliproxy` (next to the executable inside the .app),
/// Windows `<exe dir>\cliproxy.exe`. Dev fallback:
/// `build/cliproxy/<os>-<arch>/cliproxy[.exe]` under the package root.
/// `packageRoot` defaults to the current working directory; the shipped app
/// finds the binary in the bundle slot first, dev tooling passes the package
/// root explicitly.
final class CliproxyBinary {
  /// A sidecar binary. Prefer [locate], which verifies the lock hash; direct
  /// construction is for tests and callers that verified out of band.
  const CliproxyBinary({required this.path, required this.entry});

  /// Resolves and verifies the binary for [platformKey] (defaults to the
  /// current VM). Throws [CliproxyVerificationFailed] when the binary is
  /// missing or its sha256 differs from the lock.
  static Future<CliproxyBinary> locate({
    String? platformKey,
    String? executableDir,
    String? packageRoot,
    Future<String> Function(String path)? readText,
    Future<List<int>> Function(String path)? readBytes,
    Future<bool> Function(String path)? fileExists,
  }) async {
    final key = platformKey ?? currentPlatformKey();
    final exists = fileExists ?? ((path) => File(path).exists());
    final read = readText ?? ((path) => File(path).readAsString());
    final readBin = readBytes ?? ((path) => File(path).readAsBytes());

    final root = packageRoot ?? Directory.current.path;
    final sep = Platform.pathSeparator;
    final lockPath = '$root${sep}cliproxy.lock';
    if (!await exists(lockPath)) {
      throw const CliproxyVerificationFailed(
        'cliproxy.lock is missing; run tool/fetch_cliproxy.dart',
      );
    }
    final lock = CliproxyLock.parse(await read(lockPath));
    if (lock.version != cliproxyVersion) {
      throw CliproxyVerificationFailed(
        'cliproxy.lock pins ${lock.version}, this build expects $cliproxyVersion',
      );
    }
    final entry = lock.entryFor(key);

    final dir = executableDir ?? File(Platform.resolvedExecutable).parent.path;
    final bundled = Platform.isWindows
        ? '$dir${sep}cliproxy.exe'
        : '$dir${sep}lib${sep}cliproxy';
    // macOS: the executable lives in Contents/MacOS next to the binary.
    final macApp = '$dir${sep}cliproxy';

    final devName = key.startsWith('windows-') ? 'cliproxy.exe' : 'cliproxy';
    final dev = '$root${sep}build${sep}cliproxy$sep$key$sep$devName';

    final candidates = [if (Platform.isMacOS) macApp, bundled, dev];
    for (final candidate in candidates) {
      if (!await exists(candidate)) continue;
      final digest = sha256.convert(await readBin(candidate)).toString();
      if (digest != entry.binarySha256.toLowerCase()) {
        throw CliproxyVerificationFailed(
          'sidecar hash mismatch for $candidate: expected '
          '${entry.binarySha256}, got $digest',
        );
      }
      return CliproxyBinary(path: candidate, entry: entry);
    }
    throw CliproxyVerificationFailed(
      'CLIProxyAPI binary not found; checked ${candidates.join(', ')}',
    );
  }

  final String path;
  final CliproxyLockEntry entry;
}
