import 'dart:convert';

import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:hermuse_update/hermuse_update.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

const _deb = 'hermuse-agent_0.2.0-1_amd64.deb';

String _feed(String tag) => jsonEncode([
  {
    'tag_name': tag,
    'draft': false,
    'prerelease': true,
    'html_url': 'https://example/releases/$tag',
    'body': 'notes',
    'assets': [
      {
        'name': _deb,
        'browser_download_url': 'https://example/$_deb',
        'size': 42,
      },
    ],
  },
]);

HermuseDatabase _db() {
  final db = openMemoryDatabase();
  addTearDown(db.close);
  return db;
}

ProviderContainer _container(HermuseDatabase db, http.Client client) =>
    ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        httpClientProvider.overrideWithValue(client),
      ],
    );

void main() {
  group('appUpdateProvider', () {
    test('newer release with artifact is available', () async {
      final client = MockClient(
        (_) async => http.Response(_feed('hermuse/v0.2.0'), 200),
      );
      final container = _container(_db(), client);
      addTearDown(container.dispose);
      final status = await container.read(
        appUpdateProvider(
          currentVersion: '0.1.0+1',
          platform: AppPlatform.linuxDeb,
        ).future,
      );
      expect(status, isA<AppUpdateAvailable>());
      final check = (status as AppUpdateAvailable).check;
      expect(check.release?.tag, 'hermuse/v0.2.0');
      expect(check.asset?.name, _deb);
    });

    test('same version is current', () async {
      final client = MockClient(
        (_) async => http.Response(_feed('hermuse/v0.2.0'), 200),
      );
      final container = _container(_db(), client);
      addTearDown(container.dispose);
      final status = await container.read(
        appUpdateProvider(
          currentVersion: '0.2.0+3',
          platform: AppPlatform.linuxDeb,
        ).future,
      );
      expect(status, isA<AppUpdateCurrent>());
    });

    test('dismiss hides the prompt; recheck brings it back', () async {
      final client = MockClient(
        (_) async => http.Response(_feed('hermuse/v0.2.0'), 200),
      );
      final db = _db();
      final container = _container(db, client);
      addTearDown(container.dispose);
      final args = (currentVersion: '0.1.0+1', platform: AppPlatform.linuxDeb);
      var status = await container.read(
        appUpdateProvider(
          currentVersion: args.currentVersion,
          platform: args.platform,
        ).future,
      );
      expect(status, isA<AppUpdateAvailable>());

      await container
          .read(
            appUpdateProvider(
              currentVersion: args.currentVersion,
              platform: args.platform,
            ).notifier,
          )
          .dismiss('hermuse/v0.2.0');
      status = await container.read(
        appUpdateProvider(
          currentVersion: args.currentVersion,
          platform: args.platform,
        ).future,
      );
      // Dismiss only hides the prompt on the next check: the cached state is
      // already current.
      expect(status, isA<AppUpdateCurrent>());
      expect(await db.readSetting('update_dismissed:hermuse/v0.2.0'), 'true');

      await container
          .read(
            appUpdateProvider(
              currentVersion: args.currentVersion,
              platform: args.platform,
            ).notifier,
          )
          .recheck();
      await container.read(
        appUpdateProvider(
          currentVersion: args.currentVersion,
          platform: args.platform,
        ).future,
      );
      // Still dismissed: recheck re-reads the feed but honors the skip.
      final again = await container.read(
        appUpdateProvider(
          currentVersion: args.currentVersion,
          platform: args.platform,
        ).future,
      );
      expect(again, isA<AppUpdateCurrent>());
    });

    test('feed error is a silent failure, not a prompt', () async {
      final client = MockClient((_) async => http.Response('boom', 500));
      final container = _container(_db(), client);
      addTearDown(container.dispose);
      final status = await container.read(
        appUpdateProvider(
          currentVersion: '0.1.0+1',
          platform: AppPlatform.linuxDeb,
        ).future,
      );
      expect(status, isA<AppUpdateFailed>());
    });

    test('second read within the cadence returns no check', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(_feed('hermuse/v0.2.0'), 200);
      });
      final db = _db();
      final container = _container(db, client);
      addTearDown(container.dispose);
      final provider = appUpdateProvider(
        currentVersion: '0.1.0+1',
        platform: AppPlatform.linuxDeb,
      );
      expect(await container.read(provider.future), isA<AppUpdateAvailable>());
      // A fresh container re-reads the persisted timestamp and stays quiet.
      final second = ProviderContainer(
        overrides: [
          hermuseDatabaseProvider.overrideWithValue(db),
          httpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(second.dispose);
      expect(await second.read(provider.future), isNull);
      expect(calls, 1);
    });
  });
}
