import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermuse_app/platform/secure_secret_store.dart';

/// The macOS login keychain: items are readable one by one, but listing
/// them with their values fails.
final class _LoginKeychain extends TestFlutterSecureStoragePlatform {
  _LoginKeychain(super.data);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => throw PlatformException(
    code: 'Unexpected security result code',
    message: 'Code: -50',
  );
}

void main() {
  test('delete clears every secret of the instance without listing the '
      'keychain', () async {
    final data = <String, String>{'hermes/other/token': 'keep'};
    FlutterSecureStoragePlatform.instance = _LoginKeychain(data);
    final store = SecureSecretStore(const FlutterSecureStorage(), false);

    await store.write('a', 'username', 'u');
    await store.write('a', 'password', 'p');
    await store.write('a', 'password', 'p2');
    await store.delete('a');

    expect(await store.read('a', 'username'), isNull);
    expect(await store.read('a', 'password'), isNull);
    expect(data, {'hermes/other/token': 'keep'});
  });

  test('verifySecretStore passes on the login keychain', () async {
    final data = <String, String>{};
    FlutterSecureStoragePlatform.instance = _LoginKeychain(data);
    await verifySecretStore(
      SecureSecretStore(const FlutterSecureStorage(), false),
    );
    expect(data, isEmpty);
  });

  test('delete also removes secrets stored before the key index where the '
      'keystore can list them', () async {
    final data = <String, String>{
      'hermes/a/session_token': 'legacy',
      'hermes/b/session_token': 'keep',
    };
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureSecretStore(const FlutterSecureStorage(), true);
    await store.delete('a');
    expect(data, {'hermes/b/session_token': 'keep'});
  });

  test('Linux values carry no character a plaintext keyring breaks on, and '
      'values stored before still read', () async {
    final data = <String, String>{'hermes/a/session_token': 'legacy'};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      data,
    );
    final store = SecureSecretStore(const FlutterSecureStorage(), true, true);
    await store.write('a', 'password', r'p"w\d');
    await store.write('a', 'username', 'admin');

    for (final stored in data.values) {
      expect(stored, isNot(matches(r'["\\]')));
    }
    expect(await store.read('a', 'password'), r'p"w\d');
    expect(await store.read('a', 'username'), 'admin');
    expect(await store.read('a', 'session_token'), 'legacy');
    await store.delete('a');
    expect(data, isEmpty);
  });
}
