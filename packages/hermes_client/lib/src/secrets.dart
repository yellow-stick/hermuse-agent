/// Well-known secret keys stored per instance.
abstract final class SecretKeys {
  /// Dashboard username for [AuthMethod.password] instances.
  static const username = 'username';

  /// Dashboard password for [AuthMethod.password] instances.
  static const password = 'password';

  /// `HERMES_DASHBOARD_SESSION_TOKEN` of a loopback backend.
  static const sessionToken = 'session_token';
}

/// Per-instance secret storage. Implementations MUST keep values out of any
/// database, log or persisted state; a platform keystore failure is thrown,
/// never downgraded to plaintext.
abstract interface class SecretStore {
  Future<String?> read(String instanceId, String key);
  Future<void> write(String instanceId, String key, String value);

  /// Removes every secret of [instanceId].
  Future<void> delete(String instanceId);
}

/// Process-memory store: tests, the web app (secrets live for the tab only),
/// and ephemeral loopback tokens.
final class MemorySecretStore implements SecretStore {
  final Map<String, Map<String, String>> _values = {};

  @override
  Future<String?> read(String instanceId, String key) async =>
      _values[instanceId]?[key];

  @override
  Future<void> write(String instanceId, String key, String value) async {
    (_values[instanceId] ??= {})[key] = value;
  }

  @override
  Future<void> delete(String instanceId) async {
    _values.remove(instanceId);
  }
}
