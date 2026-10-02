import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'saved_sign_in.g.dart';

/// The dashboard account this app holds for a password instance.
final class SavedSignIn {
  const SavedSignIn({required this.username, required this.password});

  final String username;
  final String password;

  /// Never the password: this value may end up in an error or a log.
  @override
  String toString() => 'SavedSignIn($username, ••••••••)';
}

/// The dashboard account saved for [instanceId], so its owner can read it
/// again (to sign in from another computer or the web app). Null when the
/// instance does not sign in with a password or this app holds none (the
/// web app keeps secrets for the tab only). Read from the [SecretStore] on
/// demand and dropped once nothing shows it.
@riverpod
Future<SavedSignIn?> savedSignIn(Ref ref, String instanceId) async {
  final registry = await ref.watch(registryProvider.future);
  if (registry.byId(instanceId)?.auth != AuthMethod.password) return null;
  final secrets = ref.watch(secretStoreProvider);
  final username = await secrets.read(instanceId, SecretKeys.username);
  final password = await secrets.read(instanceId, SecretKeys.password);
  if (username == null || password == null || password.isEmpty) return null;
  return SavedSignIn(username: username, password: password);
}
