import 'dart:convert';

import 'package:hermuse_update/hermuse_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _deb = 'hermuse-agent_0.2.0-1_amd64.deb';
const _dmg = 'Hermuse-Agent-0.2.0-macos-arm64.dmg';

String _feed(List<Map<String, Object?>> releases) => jsonEncode(releases);

Map<String, Object?> _release({
  required String tag,
  bool draft = false,
  bool prerelease = true,
  List<Map<String, Object?>>? assets,
  String? body,
}) => {
  'tag_name': tag,
  'draft': draft,
  'prerelease': prerelease,
  'html_url': 'https://example/releases/$tag',
  'body': body ?? '',
  'assets':
      assets ??
      [
        {
          'name': _deb,
          'browser_download_url': 'https://example/$_deb',
          'size': 42,
        },
        {
          'name': 'VERSION.json',
          'browser_download_url': 'https://example/VERSION.json',
          'size': 7,
        },
      ],
};

MockClient _feedClient(String body, {int status = 200}) =>
    MockClient((request) async {
      if (request.url.host == 'example') {
        return http.Response('{"artifacts":[]}', 200);
      }
      return http.Response(body, status);
    });

void main() {
  group('parseReleases', () {
    test('skips drafts and non-hermuse tags', () {
      final releases = parseReleases(
        _feed([
          _release(tag: 'hermuse/v0.2.0'),
          _release(tag: 'hermuse/v0.3.0', draft: true),
          _release(tag: 'other/v0.9.0'),
        ]),
      );
      expect(releases.map((r) => r.tag), ['hermuse/v0.2.0']);
      expect(releases.single.assets.map((a) => a.name), contains(_deb));
    });

    test('throws on a non-list body', () {
      expect(() => parseReleases('{}'), throwsA(isA<UpdateCheckException>()));
    });
  });

  group('newestReleaseWithAsset', () {
    AppRelease release(String tag, String asset) => AppRelease(
      version: AppVersion.parse(tag)!,
      tag: tag,
      htmlUrl: '',
      notes: '',
      prerelease: true,
      assets: [
        ReleaseAsset(
          name: asset,
          downloadUrl: 'https://example/$asset',
          sizeBytes: 1,
        ),
      ],
    );

    test('picks the newest release carrying a platform artifact', () {
      final releases = [
        release('hermuse/v0.1.0', _deb),
        release('hermuse/v9.9.0', _dmg),
        release('hermuse/v0.2.0', _deb),
      ];
      expect(
        newestReleaseWithAsset(releases, AppPlatform.linuxDeb)?.tag,
        'hermuse/v0.2.0',
      );
      expect(
        newestReleaseWithAsset(releases, AppPlatform.macos)?.tag,
        'hermuse/v9.9.0',
      );
    });

    test('returns null when no release ships the platform', () {
      final releases = [release('hermuse/v0.2.0', _dmg)];
      expect(newestReleaseWithAsset(releases, AppPlatform.windows), isNull);
    });
  });

  group('checkForUpdate', () {
    test('update available on a newer release with artifact', () async {
      final check = await checkForUpdate(
        client: _feedClient(_feed([_release(tag: 'hermuse/v0.2.0')])),
        currentVersion: '0.1.0+1',
        platform: AppPlatform.linuxDeb,
      );
      expect(check.updateAvailable, isTrue);
      expect(check.release?.tag, 'hermuse/v0.2.0');
      expect(check.asset?.name, _deb);
    });

    test('no update when running the newest', () async {
      final check = await checkForUpdate(
        client: _feedClient(_feed([_release(tag: 'hermuse/v0.2.0')])),
        currentVersion: '0.2.0+3',
        platform: AppPlatform.linuxDeb,
      );
      expect(check.updateAvailable, isFalse);
      expect(check.release?.tag, 'hermuse/v0.2.0');
    });

    test('no release when the platform has no artifact', () async {
      final check = await checkForUpdate(
        client: _feedClient(
          _feed([
            _release(
              tag: 'hermuse/v0.2.0',
              assets: [
                {
                  'name': _dmg,
                  'browser_download_url': 'https://example/$_dmg',
                  'size': 9,
                },
              ],
            ),
          ]),
        ),
        currentVersion: '0.1.0+1',
        platform: AppPlatform.windows,
      );
      expect(check.updateAvailable, isFalse);
      expect(check.release, isNull);
      expect(check.asset, isNull);
    });

    test('an excluded prerelease leaves no release', () async {
      final check = await checkForUpdate(
        client: _feedClient(_feed([_release(tag: 'hermuse/v0.2.0')])),
        currentVersion: '0.1.0+1',
        platform: AppPlatform.linuxDeb,
        includePrereleases: false,
      );
      expect(check.release, isNull);
    });

    test('feed error throws UpdateCheckException', () async {
      expect(
        checkForUpdate(
          client: _feedClient('boom', status: 500),
          currentVersion: '0.1.0+1',
          platform: AppPlatform.linuxDeb,
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('unparseable current version throws', () async {
      expect(
        checkForUpdate(
          client: _feedClient(_feed([_release(tag: 'hermuse/v0.2.0')])),
          currentVersion: 'dev',
          platform: AppPlatform.linuxDeb,
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('attaches the VERSION.json sha256 when readable', () async {
      const sha = 'abc123';
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(_feed([_release(tag: 'hermuse/v0.2.0')]), 200);
        }
        return http.Response(
          jsonEncode({
            'artifacts': [
              {'name': _deb, 'sha256': sha, 'size': 42},
            ],
          }),
          200,
        );
      });
      final check = await checkForUpdate(
        client: client,
        currentVersion: '0.1.0+1',
        platform: AppPlatform.linuxDeb,
      );
      expect(check.asset?.sha256, sha);
    });

    test('missing VERSION.json leaves the download usable', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            _feed([
              _release(
                tag: 'hermuse/v0.2.0',
                assets: [
                  {
                    'name': _deb,
                    'browser_download_url': 'https://example/$_deb',
                    'size': 42,
                  },
                ],
              ),
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final check = await checkForUpdate(
        client: client,
        currentVersion: '0.1.0+1',
        platform: AppPlatform.linuxDeb,
      );
      expect(check.updateAvailable, isTrue);
      expect(check.asset?.sha256, isNull);
    });
  });
}
