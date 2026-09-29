import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('CliproxyLock', () {
    test('parses a lock file', () {
      final lock = CliproxyLock.parse(
        jsonEncode({
          'version': 'v7.3.18',
          'platforms': {
            'linux-amd64': {
              'asset': 'CLIProxyAPI_7.3.18_linux_amd64.tar.gz',
              'archive_sha256': 'a' * 64,
              'binary': 'cliproxy',
              'binary_sha256': 'b' * 64,
            },
          },
        }),
      );
      expect(lock.version, 'v7.3.18');
      expect(
        lock.entryFor('linux-amd64').asset,
        'CLIProxyAPI_7.3.18_linux_amd64.tar.gz',
      );
    });

    test('rejects a non-object payload', () {
      expect(
        () => CliproxyLock.parse('[]'),
        throwsA(isA<CliproxyVerificationFailed>()),
      );
    });

    test('entryFor throws on a missing platform', () {
      const lock = CliproxyLock(version: 'v7.3.18', platforms: {});
      expect(
        () => lock.entryFor('linux-amd64'),
        throwsA(isA<CliproxyVerificationFailed>()),
      );
    });
  });

  group('CliproxyBinary.locate in a distributed build', () {
    const binaryBytes = [1, 2, 3, 4];
    late String digest;
    late Map<String, List<int>> files;

    setUp(() {
      digest = sha256.convert(binaryBytes).toString();
      files = {
        '/opt/hermuse-agent/lib/cliproxy': binaryBytes,
        // A verified binary elsewhere must never be picked up instead.
        '/work/packages/hermuse_host/build/cliproxy/linux-amd64/cliproxy':
            binaryBytes,
        '/work/packages/hermuse_host/cliproxy.lock': utf8.encode('{}'),
      };
    });

    Future<CliproxyBinary> locate({
      String? bundleSha256,
      String bundlePlatform = 'linux-amd64',
      String platformKey = 'linux-amd64',
    }) => CliproxyBinary.locate(
      bundleSha256: bundleSha256 ?? digest,
      bundlePlatform: bundlePlatform,
      packageRoot: '/work/packages/hermuse_host',
      platformKey: platformKey,
      executableDir: '/opt/hermuse-agent',
      readText: (path) async => utf8.decode(files[path]!),
      openRead: (path) => Stream.value(files[path]!),
      fileExists: (path) async => files.containsKey(path),
    );

    Matcher failsWith(String text) => throwsA(
      isA<CliproxyVerificationFailed>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('accepts the bundle slot holding the compiled digest', () async {
      final binary = await locate();
      expect(binary.path, '/opt/hermuse-agent/lib/cliproxy');
      expect(binary.sha256, digest);
    });

    test('refuses a bundled binary with another hash', () async {
      files['/opt/hermuse-agent/lib/cliproxy'] = [9, 9, 9];
      await expectLater(locate(), failsWith('hash mismatch'));
    });

    test('refuses a build made for another platform', () async {
      await expectLater(
        locate(bundlePlatform: 'linux-arm64'),
        failsWith('linux-arm64'),
      );
    });

    test('refuses incomplete metadata instead of the dev tree', () async {
      await expectLater(
        locate(bundlePlatform: ''),
        failsWith('HERMUSE_CLIPROXY_PLATFORM'),
      );
      await expectLater(locate(bundleSha256: ''), failsWith('incomplete'));
    });

    test('refuses a digest that is not lowercase hex', () async {
      await expectLater(
        locate(bundleSha256: digest.toUpperCase()),
        failsWith('lowercase hex'),
      );
    });

    test('fails when the bundle slot is empty, without fallback', () async {
      files.remove('/opt/hermuse-agent/lib/cliproxy');
      await expectLater(locate(), failsWith('missing'));
    });
  });

  group('CliproxyBinary.locate in a development build', () {
    const binaryBytes = [1, 2, 3, 4];
    late String digest;
    late Map<String, String> texts;
    late Map<String, List<int>> binaries;

    setUp(() {
      digest = sha256.convert(binaryBytes).toString();
      texts = {
        '/pkg/cliproxy.lock': jsonEncode({
          'version': 'v7.3.18',
          'platforms': {
            'linux-amd64': {
              'asset': 'CLIProxyAPI_7.3.18_linux_amd64.tar.gz',
              'archive_sha256': 'a' * 64,
              'binary': 'cliproxy',
              'binary_sha256': digest,
            },
          },
        }),
      };
      binaries = {'/pkg/build/cliproxy/linux-amd64/cliproxy': binaryBytes};
    });

    Future<CliproxyBinary> locate({String packageRoot = '/pkg'}) =>
        CliproxyBinary.locate(
          bundleSha256: '',
          bundlePlatform: '',
          packageRoot: packageRoot,
          platformKey: 'linux-amd64',
          executableDir: '/nonexistent-exe-dir',
          readText: (path) async => texts[path]!,
          openRead: (path) => Stream.value(binaries[path]!),
          fileExists: (path) async =>
              texts.containsKey(path) || binaries.containsKey(path),
        );

    test('verifies the dev tree against the lock', () async {
      final binary = await locate();
      expect(binary.path, '/pkg/build/cliproxy/linux-amd64/cliproxy');
      expect(binary.sha256, digest);
    });

    test('needs an explicit package root', () async {
      await expectLater(
        locate(packageRoot: ''),
        throwsA(
          isA<CliproxyVerificationFailed>().having(
            (e) => e.message,
            'message',
            contains('HERMUSE_CLIPROXY_DEV_ROOT'),
          ),
        ),
      );
    });

    test('fails closed on hash mismatch', () async {
      binaries['/pkg/build/cliproxy/linux-amd64/cliproxy'] = [9, 9, 9];
      await expectLater(
        locate(),
        throwsA(
          isA<CliproxyVerificationFailed>().having(
            (e) => e.message,
            'message',
            contains('hash mismatch'),
          ),
        ),
      );
    });

    test('fails closed on a version drift', () async {
      texts['/pkg/cliproxy.lock'] = jsonEncode({
        'version': 'v9.9.9',
        'platforms': {},
      });
      await expectLater(locate(), throwsA(isA<CliproxyVerificationFailed>()));
    });

    test('fails closed when the binary is absent', () async {
      binaries.clear();
      await expectLater(
        locate(),
        throwsA(
          isA<CliproxyVerificationFailed>().having(
            (e) => e.message,
            'message',
            contains('not found'),
          ),
        ),
      );
    });
  });

  group('buildCliproxyConfig', () {
    test('emits a loopback, remote-disabled config', () {
      final config = buildCliproxyConfig(
        port: 8317,
        authDir: '/h/.hermes/cliproxy/auth',
        apiKey: 'api',
        managementKey: 'mgmt',
      );
      expect(config, contains('host: "127.0.0.1"'));
      expect(config, contains('port: 8317'));
      expect(config, contains('allow-remote: false'));
      expect(config, contains('secret-key: "mgmt"'));
      expect(config, contains('- "api"'));
    });

    test('quotes values that would break YAML', () {
      final config = buildCliproxyConfig(
        port: 1,
        authDir: '/h/a: b',
        apiKey: 'k"ey',
        managementKey: 'm\ney',
      );
      expect(config, contains(r'auth-dir: "/h/a: b"'));
      expect(config, contains(r'- "k\"ey"'));
      expect(config, contains(r'secret-key: "m\ney"'));
    });
  });
}
