import 'dart:convert';
import 'dart:io';
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
/// by code signature instead. The login keychain cannot enumerate items
/// with their values (`readAll` fails with errSecParam), so each instance
/// keeps the list of its keys in an index item, `hermes/<instanceId>/.keys`,
/// and [delete] removes exactly those.
final class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage, bool? enumerable])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(
              accountName: 'com.yellowstick.hermuseApp',
              usesDataProtectionKeychain: false,
            ),
          ),
      _enumerable = enumerable ?? !Platform.isMacOS;

  final FlutterSecureStorage _storage;

  /// Whether the keystore can list its items. On Linux and Windows [delete]
  /// also sweeps items written before the index existed.
  final bool _enumerable;

  static String _key(String instanceId, String key) =>
      'hermes/$instanceId/$key';

  static String _indexKey(String instanceId) => 'hermes/$instanceId/.keys';

  Future<Set<String>> _index(String instanceId) async {
    final raw = await _storage.read(key: _indexKey(instanceId));
    if (raw == null || raw.isEmpty) return {};
    return {for (final key in (jsonDecode(raw) as List)) key as String};
  }

  @override
  Future<String?> read(String instanceId, String key) =>
      _storage.read(key: _key(instanceId, key));

  @override
  Future<void> write(String instanceId, String key, String value) async {
    final index = await _index(instanceId);
    if (index.add(key)) {
      await _storage.write(
        key: _indexKey(instanceId),
        value: jsonEncode(index.toList()..sort()),
      );
    }
    await _storage.write(key: _key(instanceId, key), value: value);
  }

  @override
  Future<void> delete(String instanceId) async {
    for (final key in await _index(instanceId)) {
      await _storage.delete(key: _key(instanceId, key));
    }
    await _storage.delete(key: _indexKey(instanceId));
    if (!_enumerable) return;
    final prefix = 'hermes/$instanceId/';
    for (final key in (await _storage.readAll()).keys.toList()) {
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
