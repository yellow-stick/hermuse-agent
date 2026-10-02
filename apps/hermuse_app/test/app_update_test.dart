import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermuse_app/shell/app_update.dart';
import 'package:hermuse_app/shell/app_update_dialog.dart';
import 'package:hermuse_update/hermuse_update.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

Widget _screen(WidgetTester tester, Widget child) => MediaQuery(
  data: MediaQueryData.fromView(tester.view),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: YsTheme(
      palette: YsPalette.dark,
      child: Overlay.wrap(child: child),
    ),
  ),
);

UpdateCheck _check(String current, String tag, String asset) => UpdateCheck(
  current: AppVersion.parse(current)!,
  release: AppRelease(
    version: AppVersion.parse(tag)!,
    tag: tag,
    htmlUrl: 'https://example/releases/$tag',
    notes: 'Highlights.',
    prerelease: true,
    assets: [
      ReleaseAsset(
        name: asset,
        downloadUrl: 'https://example/$asset',
        sizeBytes: 42 * 1024 * 1024,
        sha256: 'abc123',
      ),
    ],
  ),
  asset: ReleaseAsset(
    name: asset,
    downloadUrl: 'https://example/$asset',
    sizeBytes: 42 * 1024 * 1024,
    sha256: 'abc123',
  ),
);

void main() {
  group('currentAppPlatform', () {
    test('resolves the running OS without throwing', () {
      expect(currentAppPlatform, returnsNormally);
      expect(currentAppPlatform(isDebInstall: true), AppPlatform.linuxDeb);
      expect(
        currentAppPlatform(isDebInstall: false),
        AppPlatform.linuxAppImage,
      );
    });
  });

  group('currentAppVersion', () {
    test('dev builds fall back below any release', () {
      // No HERMUSE_APP_VERSION define in tests.
      expect(currentAppVersion(), '0.0.0+0');
      expect(currentAppVersion(fallback: '9.9.9+9'), '9.9.9+9');
    });
  });

  group('dailyCheckDue', () {
    test('never checked is due; recent is not', () {
      expect(dailyCheckDue(null), isTrue);
      final now = DateTime(2026, 10, 2, 12);
      expect(
        dailyCheckDue(
          now.subtract(const Duration(hours: 21)).millisecondsSinceEpoch,
          now: now,
        ),
        isTrue,
      );
      expect(
        dailyCheckDue(
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('AppUpdateDialog', () {
    Future<void> pump(
      WidgetTester tester,
      AppPlatform platform,
      UpdateCheck check,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        ProviderScope(
          child: _screen(
            tester,
            AppUpdateDialog(
              check: check,
              platform: platform,
              onClose: () {},
              onDismissVersion: () => dismissed = true,
            ),
          ),
        ),
      );
      expect(dismissed, isFalse);
    }

    testWidgets('deb prompt names the artifact, install and checksum', (
      tester,
    ) async {
      const asset = 'hermuse-agent_0.2.0-1_amd64.deb';
      await pump(
        tester,
        AppPlatform.linuxDeb,
        _check('0.1.0+1', 'hermuse/v0.2.0', asset),
      );
      expect(
        find.textContaining('Hermuse Agent 0.2.0 available'),
        findsOneWidget,
      );
      expect(find.textContaining(asset), findsOneWidget);
      expect(find.textContaining('sudo apt-get install'), findsOneWidget);
      expect(find.textContaining('SHA-256: abc123'), findsOneWidget);
      expect(find.text('Skip this version'), findsOneWidget);
    });

    testWidgets('windows prompt tells the Inno Setup run', (tester) async {
      const asset = 'Hermuse-Agent-0.2.0-windows-x64-Setup.exe';
      await pump(
        tester,
        AppPlatform.windows,
        _check('0.1.0+1', 'hermuse/v0.2.0', asset),
      );
      expect(find.textContaining('Run the Setup.exe'), findsOneWidget);
    });

    testWidgets('mobile prompt points at the store', (tester) async {
      await pump(
        tester,
        AppPlatform.android,
        _check('0.1.0+1', 'hermuse/v0.2.0', 'hermuse-0.2.0.apk'),
      );
      expect(find.textContaining('store listing'), findsOneWidget);
    });
  });
}
