import 'package:hermuse_update/hermuse_update.dart';
import 'package:test/test.dart';

void main() {
  group('AppVersion.parse', () {
    test('parses tags, bare versions and pubspec versions', () {
      expect(AppVersion.parse('hermuse/v0.1.0')?.toString(), '0.1.0');
      expect(AppVersion.parse('hermuse/v0.2.0-rc.3')?.toString(), '0.2.0-rc.3');
      expect(AppVersion.parse('0.1.0')?.toString(), '0.1.0');
      expect(AppVersion.parse('0.1.0+1')?.toString(), '0.1.0');
      expect(AppVersion.parse('0.1.0-rc.1+4')?.toString(), '0.1.0-rc.1');
    });

    test('rejects anything outside the tag scheme', () {
      expect(AppVersion.parse('dev'), isNull);
      expect(AppVersion.parse('v0.1.0'), isNull);
      expect(AppVersion.parse('hermuse/0.1.0'), isNull);
      expect(AppVersion.parse('0.1'), isNull);
      expect(AppVersion.parse(''), isNull);
    });
  });

  group('AppVersion.compareTo', () {
    test('compares numerically, not lexicographically', () {
      final v010 = AppVersion.parse('hermuse/v0.10.0')!;
      final v020 = AppVersion.parse('hermuse/v0.2.0')!;
      expect(v010.compareTo(v020), greaterThan(0));
      expect(v020.compareTo(v010), lessThan(0));
      expect(v020.compareTo(v020), 0);
    });

    test('a final beats its own release candidates', () {
      final rc = AppVersion.parse('hermuse/v0.2.0-rc.2')!;
      final final_ = AppVersion.parse('hermuse/v0.2.0')!;
      expect(final_.compareTo(rc), greaterThan(0));
      expect(rc.compareTo(final_), lessThan(0));
    });

    test('release candidates order by number', () {
      final rc1 = AppVersion.parse('hermuse/v0.2.0-rc.1')!;
      final rc2 = AppVersion.parse('hermuse/v0.2.0-rc.2')!;
      expect(rc1.compareTo(rc2), lessThan(0));
    });

    test('build metadata never decides', () {
      final a = AppVersion.parse('0.1.0+1')!;
      final b = AppVersion.parse('0.1.0+9')!;
      expect(a.compareTo(b), 0);
      expect(a, b);
    });
  });

  group('AppPlatform.matchesArtifact', () {
    test('matches the pipeline file names', () {
      expect(
        AppPlatform.linuxDeb.matchesArtifact('hermuse-agent_0.1.0-1_amd64.deb'),
        isTrue,
      );
      expect(
        AppPlatform.linuxAppImage.matchesArtifact(
          'Hermuse-Agent-0.1.0-linux-x86_64.AppImage',
        ),
        isTrue,
      );
      expect(
        AppPlatform.macos.matchesArtifact(
          'Hermuse-Agent-0.1.0-macos-arm64.dmg',
        ),
        isTrue,
      );
      expect(
        AppPlatform.windows.matchesArtifact(
          'Hermuse-Agent-0.1.0-windows-x64-Setup.exe',
        ),
        isTrue,
      );
      expect(AppPlatform.windows.matchesArtifact('VERSION.json'), isFalse);
      expect(
        AppPlatform.linuxDeb.matchesArtifact(
          'Hermuse-Agent-0.1.0-linux-x86_64.AppImage',
        ),
        isFalse,
      );
    });
  });
  group('AppRelease.assetFor', () {
    final release = AppRelease(
      version: AppVersion.parse('0.2.0')!,
      tag: 'hermuse/v0.2.0',
      htmlUrl: 'https://example/releases/v',
      notes: '',
      prerelease: true,
      assets: const [
        ReleaseAsset(
          name: 'a.deb',
          downloadUrl: 'https://example/a.deb',
          sizeBytes: 1,
        ),
      ],
    );

    test('finds the platform artifact, null otherwise', () {
      expect(release.assetFor(AppPlatform.linuxDeb)?.name, 'a.deb');
      expect(release.assetFor(AppPlatform.macos), isNull);
    });
  });
}
