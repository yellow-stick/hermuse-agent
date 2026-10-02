import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'version.dart';

/// The canonical releases feed (GitHub API, JSON list). Fork builds check
/// here too: the published bytes are the canonical project's.
const updateReleasesUrl =
    'https://api.github.com/repos/yellow-stick/hermuse-agent/releases'
    '?per_page=100';

/// How long a feed fetch may take before the check fails.
const updateCheckTimeout = Duration(seconds: 15);

/// The feed answered wrongly or is unreadable; the caller shows "check
/// failed" and tries again later, never an update prompt.
final class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Newest release (by version) carrying an install artifact for [platform];
/// null when none does. Drafts and non-`hermuse/v*` tags never qualify (they
/// never reach [AppRelease]).
AppRelease? newestReleaseWithAsset(
  Iterable<AppRelease> releases,
  AppPlatform platform,
) {
  AppRelease? best;
  for (final release in releases) {
    if (release.assetFor(platform) == null) continue;
    if (best == null || release.version.compareTo(best.version) > 0) {
      best = release;
    }
  }
  return best;
}

/// Parses one `GET .../releases` page body, skipping drafts and anything
/// outside `hermuse/v*`; throws [UpdateCheckException] on a non-list body.
List<AppRelease> parseReleases(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const UpdateCheckException('releases feed is not a list');
  }
  final out = <AppRelease>[];
  for (final entry in decoded) {
    if (entry is! Map<String, Object?>) continue;
    if (entry['draft'] == true) continue;
    final tag = entry['tag_name'] as String?;
    final version = tag == null ? null : AppVersion.parse(tag);
    if (tag == null || version == null) continue;
    final assets = <ReleaseAsset>[];
    for (final raw in (entry['assets'] as List?) ?? const []) {
      if (raw is! Map<String, Object?>) continue;
      final name = raw['name'] as String?;
      final url = raw['browser_download_url'] as String?;
      if (name == null || name.isEmpty || url == null || url.isEmpty) {
        continue;
      }
      final size = raw['size'];
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: size is num ? size.toInt() : 0,
        ),
      );
    }
    out.add(
      AppRelease(
        version: version,
        tag: tag,
        htmlUrl: (entry['html_url'] as String?) ?? '',
        notes: (entry['body'] as String?) ?? '',
        prerelease: entry['prerelease'] == true,
        assets: assets,
      ),
    );
  }
  return out;
}

/// Full check: feed, newest release with a [platform] artifact, comparison
/// with [currentVersion], SHA-256 from that release's `VERSION.json` when
/// readable. Throws [UpdateCheckException] on any failure.
///
/// Prereleases are included: our pipeline publishes every release with
/// `latest=false`, so excluding them finds nothing.
Future<UpdateCheck> checkForUpdate({
  required http.Client client,
  required String currentVersion,
  required AppPlatform platform,
  bool includePrereleases = true,
  Duration timeout = updateCheckTimeout,
}) async {
  final current = AppVersion.parse(currentVersion);
  if (current == null) {
    throw UpdateCheckException(
      'cannot parse current version "$currentVersion"',
    );
  }
  late final http.Response feed;
  try {
    feed = await client
        .get(
          Uri.parse(updateReleasesUrl),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'Hermuse-Agent-Update-Check',
          },
        )
        .timeout(timeout);
  } on TimeoutException {
    throw const UpdateCheckException('releases feed timed out');
  } on http.ClientException catch (e) {
    throw UpdateCheckException('releases feed unreachable: ${e.message}');
  }
  if (feed.statusCode != 200) {
    throw UpdateCheckException('releases feed answered ${feed.statusCode}');
  }
  final releases = parseReleases(feed.body)
      .where((r) => includePrereleases || !r.prerelease);
  final release = newestReleaseWithAsset(releases, platform);
  final asset = release?.assetFor(platform);
  if (release == null || asset == null) {
    return UpdateCheck(current: current, release: null, asset: null);
  }
  final sha = await _artifactSha256(client, release, asset.name, timeout);
  return UpdateCheck(
    current: current,
    release: release,
    asset: sha == null ? asset : asset.withSha256(sha),
  );
}

/// Expected SHA-256 of [assetName] from the release's `VERSION.json`
/// (`artifacts[].{name, sha256}`); null when the fragment is missing or
/// unreadable (best effort: the download URL stays valid without it).
Future<String?> _artifactSha256(
  http.Client client,
  AppRelease release,
  String assetName,
  Duration timeout,
) async {
  try {
    final manifest = release.assets
        .where((a) => a.name == 'VERSION.json')
        .firstOrNull;
    if (manifest == null) return null;
    final response = await client
        .get(Uri.parse(manifest.downloadUrl))
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, Object?>) return null;
    final artifacts = <Map<String, Object?>>[
      for (final a in (decoded['artifacts'] as List?) ?? const [])
        if (a is Map<String, Object?>) a,
      for (final p in ((decoded['platforms'] as Map?)?.values ?? const []))
        if (p is Map)
          for (final a in (p['artifacts'] as List?) ?? const [])
            if (a is Map<String, Object?>) a,
    ];
    for (final artifact in artifacts) {
      if (artifact['name'] == assetName) {
        final sha = artifact['sha256'] as String?;
        if (sha != null && sha.isNotEmpty) return sha;
      }
    }
    return null;
  } on Object {
    return null;
  }
}
