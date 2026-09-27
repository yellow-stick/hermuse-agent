/// Downloads the pinned CLIProxyAPI release assets, verifies them against the
/// release `checksums.txt`, extracts the sidecar binary per platform, and
/// writes `cliproxy.lock`.
///
/// Usage:
/// ```sh
/// # all six desktop platforms (default)
/// dart run tool/fetch_cliproxy.dart
/// # one platform only (faster iteration)
/// dart run tool/fetch_cliproxy.dart --platform linux-amd64
/// # verify the existing tree against the lock without downloading
/// dart run tool/fetch_cliproxy.dart --check
/// ```
///
/// Layout: `build/cliproxy/<os>-<arch>/cliproxy[.exe]` (gitignored).
/// `cliproxy.lock` (committed): `{version, platforms: {key: {asset,
/// archive_sha256, binary, binary_sha256}}}`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const version = 'v7.3.18';
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

Future<void> main(List<String> args) async {
  final checkOnly = args.contains('--check');
  final platformFlag = args
      .where((a) => a.startsWith('--platform=') || a.startsWith('--platform '))
      .map((a) => a.split(RegExp(r'[= ]'))[1])
      .firstOrNull;
  final platformIndex = args.indexOf('--platform');
  final platformOnly =
      platformFlag ??
      (platformIndex >= 0 && platformIndex + 1 < args.length
          ? args[platformIndex + 1]
          : null);
  if (platformOnly != null && !platforms.containsKey(platformOnly)) {
    stderr.writeln(
      'unknown platform $platformOnly; one of ${platforms.keys.join(', ')}',
    );
    exitCode = 2;
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

  if (checkOnly) {
    await _check(lockFile, buildDir, wanted);
    return;
  }

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
        stderr.writeln('checksums.txt has no entry for $asset');
        exitCode = 1;
        return;
      }
      final outDir = Directory('${buildDir.path}${Platform.pathSeparator}$key');
      await outDir.create(recursive: true);
      final archivePath = '${outDir.path}${Platform.pathSeparator}$asset';
      stdout.writeln('[$key] downloading $asset …');
      await _download(client, _releaseUri(asset), archivePath);
      final archiveBytes = await File(archivePath).readAsBytes();
      final archiveDigest = sha256.convert(archiveBytes).toString();
      if (archiveDigest != expectedArchive) {
        stderr.writeln(
          '[$key] archive hash mismatch: expected $expectedArchive, got $archiveDigest',
        );
        exitCode = 1;
        return;
      }
      final binaryName = key.startsWith('windows-')
          ? 'cli-proxy-api.exe'
          : 'cli-proxy-api';
      final binaryBytes = _extractBinary(archivePath, binaryName);
      final sidecarName = key.startsWith('windows-')
          ? 'cliproxy.exe'
          : 'cliproxy';
      final sidecarPath = '${outDir.path}${Platform.pathSeparator}$sidecarName';
      await File(sidecarPath).writeAsBytes(binaryBytes);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['755', sidecarPath]);
      }
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

  final payload = {'version': version, 'platforms': updated};
  await lockFile.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
  );
  stdout.writeln('wrote ${lockFile.path}');
}

Directory _packageRoot() {
  // tool/ sits directly under the package root.
  return File(Platform.script.toFilePath()).parent.parent;
}

Uri _releaseUri(String asset) => Uri.parse(
  'https://github.com/$_owner/$_repo/releases/download/$version/$asset',
);

Future<Map<String, String>> _fetchChecksums() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(_releaseUri('checksums.txt'));
    final response = await request.close();
    if (response.statusCode != 200) {
      stderr.writeln('cannot fetch checksums.txt: HTTP ${response.statusCode}');
      exit(1);
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
  if (decoded['version'] != version) {
    stdout.writeln(
      'existing lock pins ${decoded['version']}, rebuilding for $version',
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

Future<void> _download(HttpClient client, Uri uri, String dest) async {
  final request = await client.getUrl(uri);
  final response = await request.close();
  if (response.statusCode != 200) {
    stderr.writeln('cannot download $uri: HTTP ${response.statusCode}');
    exit(1);
  }
  final file = File(dest).openWrite();
  var bytes = 0;
  await for (final chunk in response) {
    bytes += chunk.length;
    file.add(chunk);
  }
  await file.close();
  stdout.writeln('  ${_formatBytes(bytes)} bytes');
}

String _formatBytes(int bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MiB'
    : '${(bytes / 1024).toStringAsFixed(0)} KiB';

List<int> _extractBinary(String archivePath, String binaryName) {
  final bytes = File(archivePath).readAsBytesSync();
  if (archivePath.endsWith('.zip')) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (file.name == binaryName && file.isFile) {
        return file.content as List<int>;
      }
    }
  } else {
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);
    for (final file in archive.files) {
      if (file.name == binaryName && file.isFile) {
        return file.content as List<int>;
      }
    }
  }
  stderr.writeln('$archivePath contains no $binaryName');
  exit(1);
}

Future<void> _check(
  File lockFile,
  Directory buildDir,
  Map<String, String> wanted,
) async {
  if (!await lockFile.exists()) {
    stderr.writeln('missing ${lockFile.path}; run without --check first');
    exitCode = 1;
    return;
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
    final digest = sha256.convert(await sidecar.readAsBytes()).toString();
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
