import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hermes_client/hermes_client.dart';

/// [SecretStore] over the platform keystore, namespaced per instance.
///
/// Keys are stored as `hermes/<instanceId>/<key>` and are never written
/// anywhere else. Keystore failures propagate to the caller: the app shows a
/// blocking error screen instead of falling back to plaintext.
///
/// On macOS the items live in the login keychain under the app's own
/// service name. The data protection keychain would need a provisioning
/// profile (`keychain-access-groups`), which neither the Developer ID
/// release nor an unsigned build carries; the login keychain grants access
/// by code signature instead.
final class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accountName: 'com.yellowstick.hermuseApp',
              usesDataProtectionKeychain: false,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _key(String instanceId, String key) =>
      'hermes/$instanceId/$key';

  @override
  Future<String?> read(String instanceId, String key) =>
      _storage.read(key: _key(instanceId, key));

  @override
  Future<void> write(String instanceId, String key, String value) =>
      _storage.write(key: _key(instanceId, key), value: value);

  @override
  Future<void> delete(String instanceId) async {
    final all = await _storage.readAll();
    final prefix = 'hermes/$instanceId/';
    for (final key in all.keys) {
      if (key.startsWith(prefix)) {
        await _storage.delete(key: key);
      }
    }
  }
}

/// Instance id of the throwaway keystore probes.
const _probeInstance = '__probe__';

/// Proves [store] works end to end: writes a throwaway secret, reads it back
/// and deletes it. Throws the store's own error (a locked or missing keyring
/// included); callers never fall back to another store.
Future<void> verifySecretStore(SecretStore store) async {
  final random = Random.secure();
  final value = base64Url.encode([
    for (var i = 0; i < 16; i++) random.nextInt(256),
  ]);
  await store.write(_probeInstance, 'probe', value);
  try {
    if (await store.read(_probeInstance, 'probe') != value) {
      throw StateError(
        'the system keyring did not return the secret it stored',
      );
    }
  } finally {
    await store.delete(_probeInstance);
  }
}

/// Whether [error] is the keyring refusing access because it stays locked
/// (its unlock prompt was dismissed).
bool isKeyringLocked(Object error) =>
    error is PlatformException && error.code == 'KeyringLocked';
