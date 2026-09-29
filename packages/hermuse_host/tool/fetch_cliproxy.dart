/// Downloads the pinned CLIProxyAPI release assets, verifies them, extracts
/// the sidecar binary per platform, and writes `cliproxy.lock`.
///
/// Usage:
/// ```sh
/// # all six desktop platforms (default): verify against the release
/// # checksums.txt, then (re)write cliproxy.lock
/// dart run tool/fetch_cliproxy.dart
/// # one platform only (faster iteration)
/// dart run tool/fetch_cliproxy.dart --platform linux-amd64
/// # verify the existing tree against the lock without downloading
/// dart run tool/fetch_cliproxy.dart --check
/// # release gate: verify the downloaded archive AND the extracted binary
/// # against the committed lock, which is never written
/// dart run tool/fetch_cliproxy.dart --platform linux-amd64 --frozen-lockfile
/// ```
///
/// Layout: `build/cliproxy/<os>-<arch>/cliproxy[.exe]` (gitignored).
/// `cliproxy.lock` (committed): `{version, platforms: {key: {asset,
/// archive_sha256, binary, binary_sha256}}}`.
///
/// `--frozen-lockfile` requires a lock at [cliproxyVersion] with an entry
/// per requested platform, removes any previous binary first, exits
/// non-zero on the first mismatch, and prints one sha256sum-style line per
/// verified binary on stdout — `<sha256>  <absolute path>` — with progress
/// on stderr, for the release build to consume.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
// Only the lock model: the release gate must not depend on the rest of the
// package compiling.
import 'package:hermuse_host/src/cliproxy_binary.dart'
    show CliproxyLock, cliproxyVersion;
import 'package:hermuse_host/src/errors.dart' show CliproxyVerificationFailed;

const _owner = 'router-for-me';
const _repo = 'CLIProxyAPI';

/// Lock keys → release asset names (verified against the v7.3.18 release).
const platforms = {
  'linux-amd64': 'CLIProxyAPI_7.3.18_linux_amd64.tar.gz',
  'linux-arm64': 'CLIProxyAPI_7.3.18_linux_aarch64.tar.gz',
  'macos-amd64': 'CLIProxyAPI_7.3.18_darwin_amd64.tar.gz',
  'macos-arm64': 'CLIProxyAPI_7.3.18_darwin_aarch64.tar.gz',
  'windows-amd64': 'CLIProxyAPI_7.3.18_windows_amd64.zip',
  'windows-arm64': 'CLIProxyAPI_7.3.18_windows_aarch64.zip',
};

const _usage =
    'usage: dart run tool/fetch_cliproxy.dart '
    '[--platform <key>] [--check | --frozen-lockfile]';

/// A failure reported on stderr with exit code 1.
final class _Failure implements Exception {
  const _Failure(this.message);
  final String message;
}

Future<void> main(List<String> args) async {
  var checkOnly = false;
  var frozen = false;
  String? platformOnly;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--check') {
      checkOnly = true;
    } else if (arg == '--frozen-lockfile') {
      frozen = true;
    } else if (arg == '--platform' && i + 1 < args.length) {
      platformOnly = args[++i];
    } else if (arg.startsWith('--platform=')) {
      platformOnly = arg.substring('--platform='.length);
    } else {
      stderr
        ..writeln('unknown argument: $arg')
        ..writeln(_usage);
      exitCode = 64;
      return;
    }
  }
  if (checkOnly && frozen) {
    stderr
      ..writeln('--check and --frozen-lockfile are exclusive')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  if (platformOnly != null && !platforms.containsKey(platformOnly)) {
    stderr.writeln(
      'unknown platform $platformOnly; one of ${platforms.keys.join(', ')}',
    );
    exitCode = 64;
    return;
  }

  final packageRoot = _packageRoot().path;
  final buildDir = Directory(
    '$packageRoot${Platform.pathSeparator}build${Platform.pathSeparator}cliproxy',
  );
  final lockFile = File('$packageRoot${Platform.pathSeparator}cliproxy.lock');

  final wanted = {
    for (final e in platforms.entries)
      if (platformOnly == null || e.key == platformOnly) e.key: e.value,
  };

  try {
    if (checkOnly) {
      await _check(lockFile, buildDir, wanted);
    } else if (frozen) {
      await _fetchFrozen(lockFile, buildDir, wanted);
    } else {
      await _fetchAndLock(lockFile, buildDir, wanted);
    }
  } on _Failure catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } on CliproxyVerificationFailed catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  }
}

/// Default mode: verifies against the release `checksums.txt` and records
/// the verified hashes in the lock.
Future<void> _fetchAndLock(
  File lockFile,
  Directory buildDir,
  Map<String, String> wanted,
) async {
  final checksums = await _fetchChecksums();
  final lock = await _readLock(lockFile);
  final updated = Map<String, Map<String, String>>.from(lock);

  final client = HttpClient();
  try {
    for (final entry in wanted.entries) {
      final key = entry.key;
      final asset = entry.value;
      final expectedArchive = checksums[asset];
      if (expectedArchive == null) {
        throw _Failure('checksums.txt has no entry for $asset');
      }
      final outDir = Directory('${buildDir.path}${Platform.pathSeparator}$key');
      await outDir.create(recursive: true);
      final archivePath = '${outDir.path}${Platform.pathSeparator}$asset';
      stdout.writeln('[$key] downloading $asset …');
      await _download(client, _releaseUri(asset), archivePath, stdout);
      final archiveDigest = await _digest(archivePath);
      if (archiveDigest != expectedArchive) {
        throw _Failure(
          '[$key] archive hash mismatch: expected $expectedArchive, got $archiveDigest',
        );
      }
      final binaryName = _archiveBinaryName(key);
      final binaryBytes = _extractBinary(archivePath, binaryName);
      final sidecarName = _sidecarName(key);
      final sidecarPath = '${outDir.path}${Platform.pathSeparator}$sidecarName';
      await _writeExecutable(sidecarPath, binaryBytes);
      final binaryDigest = sha256.convert(binaryBytes).toString();
      stdout.writeln('[$key] verified archive $archiveDigest');
      stdout.writeln('[$key] binary $binaryName → $sidecarName $binaryDigest');
      updated[key] = {
        'asset': asset,
        'archive_sha256': archiveDigest,
        'binary': sidecarName,
        'binary_sha256': binaryDigest,
      };
    }
  } finally {
    client.close();
  }

  final payload = {'version': cliproxyVersion, 'platforms': updated};
  await lockFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
  stdout.writeln('wrote ${lockFile.path}');
}

/// `--frozen-lockfile`: the committed lock is the only source of truth.
Future<void> _fetchFrozen(
  File lockFile,
  Directory buildDir,
  Map<String, String> wanted,
) async {
  if (!await lockFile.exists()) {
    throw _Failure('missing ${lockFile.path}; --frozen-lockfile needs it');
  }
  final lock = CliproxyLock.parse(await lockFile.readAsString());
  if (lock.version != cliproxyVersion) {
    throw _Failure(
      '${lockFile.path} pins ${lock.version}, this build expects '
      '$cliproxyVersion',
    );
  }
  final client = HttpClient();
  try {
    for (final MapEntry(key: key, value: asset) in wanted.entries) {
      final entry = lock.platforms[key];
      if (entry == null) throw _Failure('[$key] no lock entry');
      if (entry.asset != asset) {
        throw _Failure(
          '[$key] the lock names asset ${entry.asset}, this tool pins $asset',
        );
      }
      final sidecarName = _sidecarName(key);
      if (entry.binary != sidecarName) {
        throw _Failure(
          '[$key] the lock names binary ${entry.binary}, expected $sidecarName',
        );
      }
      final outDir = Directory('${buildDir.path}${Platform.pathSeparator}$key');
      await outDir.create(recursive: true);
      final sidecar = File(
        '${outDir.path}${Platform.pathSeparator}$sidecarName',
      );
      // A failure below must never leave an older binary in the slot.
      if (await sidecar.exists()) await sidecar.delete();

      final archivePath = '${outDir.path}${Platform.pathSeparator}$asset';
      stderr.writeln('[$key] downloading $asset …');
      await _download(client, _releaseUri(asset), archivePath, stderr);
      final archiveDigest = await _digest(archivePath);
      if (archiveDigest != entry.archiveSha256.toLowerCase()) {
        throw _Failure(
          '[$key] archive hash mismatch: the lock pins '
          '${entry.archiveSha256}, got $archiveDigest',
        );
      }
      final binaryBytes = _extractBinary(archivePath, _archiveBinaryName(key));
      final binaryDigest = sha256.convert(binaryBytes).toString();
      if (binaryDigest != entry.binarySha256.toLowerCase()) {
        throw _Failure(
          '[$key] binary hash mismatch: the lock pins '
          '${entry.binarySha256}, got $binaryDigest',
        );
      }
      await _writeExecutable(sidecar.path, binaryBytes);
      final written = await _digest(sidecar.path);
      if (written != binaryDigest) {
        await sidecar.delete();
        throw _Failure(
          '[$key] ${sidecar.path} reads back as $written after writing',
        );
      }
      stderr.writeln('[$key] archive and binary match ${lockFile.path}');
      stdout.writeln('$binaryDigest  ${sidecar.absolute.path}');
    }
  } finally {
    client.close();
  }
}

Directory _packageRoot() {
  // tool/ sits directly under the package root.
  return File(Platform.script.toFilePath()).parent.parent;
}

Uri _releaseUri(String asset) => Uri.parse(
  'https://github.com/$_owner/$_repo/releases/download/$cliproxyVersion/$asset',
);

/// Binary name inside the release archive.
String _archiveBinaryName(String key) =>
    key.startsWith('windows-') ? 'cli-proxy-api.exe' : 'cli-proxy-api';

/// Name of the extracted sidecar (`cliproxy.lock` `binary`).
String _sidecarName(String key) =>
    key.startsWith('windows-') ? 'cliproxy.exe' : 'cliproxy';

/// Lowercase hex sha256 of the file at [path], hashed while streaming.
Future<String> _digest(String path) async =>
    '${await sha256.bind(File(path).openRead()).first}';

Future<Map<String, String>> _fetchChecksums() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(_releaseUri('checksums.txt'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw _Failure('cannot fetch checksums.txt: HTTP ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    final checksums = <String, String>{};
    for (final line in const LineSplitter().convert(body)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) checksums[parts[1]] = parts[0].toLowerCase();
    }
    return checksums;
  } finally {
    client.close();
  }
}

Future<Map<String, Map<String, String>>> _readLock(File lockFile) async {
  if (!await lockFile.exists()) return {};
  final decoded = jsonDecode(await lockFile.readAsString());
  if (decoded is! Map) return {};
  if (decoded['version'] != cliproxyVersion) {
    stdout.writeln(
      'existing lock pins ${decoded['version']}, rebuilding for $cliproxyVersion',
    );
    return {};
  }
  final platforms = decoded['platforms'];
  if (platforms is! Map) return {};
  return {
    for (final e in platforms.entries)
      if (e.value is Map)
        '${e.key}': (e.value as Map).map((k, v) => MapEntry('$k', '$v')),
  };
}

Future<void> _download(
  HttpClient client,
  Uri uri,
  String dest,
  IOSink log,
) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  if (response.statusCode != 200) {
    await response.drain<void>();
    throw _Failure('cannot download $uri: HTTP ${response.statusCode}');
  }
  final file = File(dest).openWrite();
  var bytes = 0;
  await for (final chunk in response) {
    bytes += chunk.length;
    file.add(chunk);
  }
  await file.close();
  log.writeln('  ${_formatBytes(bytes)} bytes');
}

String _formatBytes(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MiB'
    : '${(bytes / 1024).toStringAsFixed(0)} KiB';

List<int> _extractBinary(String archivePath, String binaryName) {
  final bytes = File(archivePath).readAsBytesSync();
  final archive = archivePath.endsWith('.zip')
      ? ZipDecoder().decodeBytes(bytes)
      : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  for (final file in archive.files) {
    if (file.name == binaryName && file.isFile) {
      return file.content as List<int>;
    }
  }
  throw _Failure('$archivePath contains no $binaryName');
}

/// Writes [bytes] to [path] through a sibling temporary file, mode 0755.
Future<void> _writeExecutable(String path, List<int> bytes) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  if (!Platform.isWindows) {
    final chmod = await Process.run('chmod', ['755', temporary.path]);
    if (chmod.exitCode != 0) {
      throw _Failure('chmod 755 ${temporary.path} failed: ${chmod.stderr}');
    }
  }
  await temporary.rename(path);
}

Future<void> _check(
  File lockFile,
  Directory buildDir,
  Map<String, String> wanted,
) async {
  if (!await lockFile.exists()) {
    throw _Failure('missing ${lockFile.path}; run without --check first');
  }
  final lock = await _readLock(lockFile);
  var failures = 0;
  for (final key in wanted.keys) {
    final entry = lock[key];
    if (entry == null) {
      stderr.writeln('[$key] no lock entry');
      failures++;
      continue;
    }
    final sidecarName = entry['binary']!;
    final sidecar = File(
      '${buildDir.path}${Platform.pathSeparator}$key${Platform.pathSeparator}$sidecarName',
    );
    if (!await sidecar.exists()) {
      stderr.writeln('[$key] missing ${sidecar.path}');
      failures++;
      continue;
    }
    final digest = await _digest(sidecar.path);
    if (digest != entry['binary_sha256']) {
      stderr.writeln(
        '[$key] hash mismatch: expected ${entry['binary_sha256']}, got $digest',
      );
      failures++;
      continue;
    }
    stdout.writeln('[$key] ok $digest');
  }
  if (failures > 0) exitCode = 1;
}
