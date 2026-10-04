import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'permissions.g.dart';

/// Hermes' config key of the approval policy for risky commands.
const approvalsModeKey = 'approvals.mode';

/// When the agent asks before a risky command (Settings → Permissions).
enum ApprovalsMode {
  /// Hermes judges which commands need the user (its default).
  smart('Ask only when needed'),
  manual('Always ask for risky commands'),
  off('Never ask');

  const ApprovalsMode(this.label);
  final String label;

  /// The mode Hermes reports; an unset or unknown value is Hermes' default,
  /// [smart].
  static ApprovalsMode fromValue(Object? value) => switch (value) {
    'manual' => manual,
    'off' => off,
    _ => smart,
  };
}

/// The approval policy of [profile] on [instanceId] (`config.get` /
/// `config.set` of [approvalsModeKey] on that profile's connection).
@Riverpod(name: 'approvalsModeProvider')
class ApprovalsModeSetting extends _$ApprovalsModeSetting {
  @override
  Future<ApprovalsMode> build(
    String instanceId, {
    String profile = 'default',
  }) async {
    final connection = await ref.watch(
      connectionProvider(instanceId, profile: profile).future,
    );
    final result = await connection.transport.call(
      HermesMethods.configGet,
      const ConfigGetParams(key: approvalsModeKey),
    );
    return ApprovalsMode.fromValue(result.value);
  }

  /// Writes [mode]; throws the server's refusal (the shown mode is kept).
  Future<void> set(ApprovalsMode mode) async {
    final connection = await ref.read(
      connectionProvider(instanceId, profile: profile).future,
    );
    await connection.transport.call(
      HermesMethods.configSet,
      ConfigSetParams(key: approvalsModeKey, value: mode.name),
    );
    if (ref.mounted) state = AsyncData(mode);
  }
}
