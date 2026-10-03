import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import 'providers.dart';

export 'package:hermuse_chat/hermuse_chat.dart'
    show AgentAvatar, agentAvatarAsset;

part 'agents.g.dart';

/// A real Hermes profile. Its UI identity is stored alongside its SOUL.md.
final class AgentProfile {
  const AgentProfile({
    required this.profile,
    required this.displayName,
    required this.avatarId,
    this.isDefault = false,
    this.metadata = const {},
    this.metadataRevision = 0,
  });

  factory AgentProfile.fromRow(ProfileRow row) {
    final raw = row.uiMeta?['hermuse'];
    final metadata = raw is Map<String, Object?> ? raw : <String, Object?>{};
    final name = metadata['display_name'];
    final avatarId = metadata['avatar_id'];
    return AgentProfile(
      profile: row.name,
      displayName: name is String && name.trim().isNotEmpty
          ? name
          : row.displayName.isNotEmpty
          ? row.displayName
          : row.name == 'default'
          ? 'Hermuse'
          : row.name,
      avatarId: AgentAvatar.byId(avatarId is String ? avatarId : null).id,
      isDefault: row.isDefault,
      metadata: metadata,
      metadataRevision: row.uiMetaRevisions?['hermuse'] ?? 0,
    );
  }

  final String profile;
  final String displayName;
  final String avatarId;
  final bool isDefault;
  final Map<String, Object?> metadata;
  final int metadataRevision;

  AgentAvatar get avatar => AgentAvatar.byId(avatarId);
}

final class AgentDetails {
  const AgentDetails({required this.prompt});
  final String prompt;
}

/// A profile may have been created even if a later section failed to save.
/// Editors retain [createdAgent] as their target instead of creating duplicates.
final class AgentWriteException implements Exception {
  const AgentWriteException(this.message, {this.createdAgent});
  final String message;
  final AgentProfile? createdAgent;

  @override
  String toString() => message;
}

Duration? _noRetry(int retryCount, Object error) => null;

@Riverpod(retry: _noRetry)
class AgentProfiles extends _$AgentProfiles {
  @override
  Future<List<AgentProfile>> build(String instanceId) async {
    final connection = await ref.watch(connectionProvider(instanceId).future);
    return _list(connection);
  }

  Future<List<AgentProfile>> _list(HermesConnection connection) async {
    final result = await connection.transport.call(
      HermesMethods.profilesList,
      const ProfilesListParams(),
    );
    return [
      for (final row in result.profiles ?? const <ProfileRow>[])
        AgentProfile.fromRow(row),
    ];
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      final connection = await ref.read(connectionProvider(instanceId).future);
      return _list(connection);
    });
  }

  Future<AgentProfile> create({
    required String name,
    required String avatarId,
    required String prompt,
  }) async {
    _validate(name, avatarId, prompt);
    final link = ref.keepAlive();
    AgentProfile? created;
    try {
      await future;
      final connection = await ref.read(connectionProvider(instanceId).future);
      final result = await connection.transport.call(
        HermesMethods.profilesCreate,
        ProfilesCreateParams(
          name: 'hermuse-${const Uuid().v4()}',
          soul: prompt,
          shareAuth: true,
          mirrorCredentials: true,
          noAlias: true,
        ),
      );
      if (!result.ok) {
        throw const AgentWriteException('Hermes did not create the agent.');
      }
      created = AgentProfile(
        profile: result.name,
        displayName: name.trim(),
        avatarId: avatarId,
      );
      if (!result.soulWritten) {
        throw const AgentWriteException(
          'The agent was created, but its prompt '
          'was not saved. Save this agent again to finish setup.',
        );
      }
      await _configure(connection, created, name, avatarId, null);
      await reload();
      return _loaded(created.profile) ?? created;
    } catch (error) {
      await reload();
      if (created != null) {
        throw AgentWriteException(
          'The agent already exists. $error',
          createdAgent: _loaded(created.profile) ?? created,
        );
      }
      rethrow;
    } finally {
      link.close();
    }
  }

  Future<void> saveAgent({
    required AgentProfile agent,
    required String name,
    required String avatarId,
    required String prompt,
  }) async {
    _validate(name, avatarId, prompt);
    final link = ref.keepAlive();
    try {
      await future;
      final connection = await ref.read(connectionProvider(instanceId).future);
      await _configure(connection, agent, name, avatarId, prompt);
    } finally {
      ref.invalidate(agentDetailsProvider(instanceId, agent.profile));
      await reload();
      link.close();
    }
  }

  /// Saves [profile]'s SOUL.md (the Identity tab's SOUL editor; read it
  /// with [agentDetailsProvider], which reloads afterwards).
  Future<void> saveSoul(String profile, String soul) async {
    if (soul.trim().isEmpty) {
      throw ArgumentError('Enter a prompt for this agent.');
    }
    final link = ref.keepAlive();
    try {
      final connection = await ref.read(connectionProvider(instanceId).future);
      final result = await connection.transport.call(
        HermesMethods.profilesConfigure,
        ProfilesConfigureParams(name: profile, soul: soul),
      );
      if (!result.ok || result.applied.soul != true) {
        throw const AgentWriteException('Could not save the SOUL.');
      }
    } finally {
      ref.invalidate(agentDetailsProvider(instanceId, profile));
      link.close();
    }
  }

  AgentProfile? _loaded(String profile) =>
      state.value?.where((agent) => agent.profile == profile).firstOrNull;

  Future<void> _configure(
    HermesConnection connection,
    AgentProfile agent,
    String name,
    String avatarId,
    String? prompt,
  ) async {
    final result = await connection.transport.call(
      HermesMethods.profilesConfigure,
      ProfilesConfigureParams(
        name: agent.profile,
        soul: prompt,
        uiMeta: {
          'hermuse': {
            ...agent.metadata,
            'display_name': name.trim(),
            'avatar_id': avatarId,
          },
        },
        uiMetaExpectedRevisions: {'hermuse': agent.metadataRevision},
      ),
    );
    final applied = result.applied;
    if (!result.ok ||
        (prompt != null && applied.soul != true) ||
        applied.uiMeta != true) {
      final failures = <String>[
        if (prompt != null && applied.soul != true) 'prompt',
        if (applied.uiMeta != true) 'name and avatar',
      ];
      final conflict = applied.uiMetaConflicts?.isNotEmpty ?? false;
      throw AgentWriteException(
        'Could not save ${failures.isEmpty ? 'all changes' : failures.join(' and ')}. '
        '${conflict ? 'This agent was edited elsewhere. Reopen the editor. ' : ''}'
        'Other sections may already have been saved.',
      );
    }
  }
}

void _validate(String name, String avatarId, String prompt) {
  if (name.trim().isEmpty) throw ArgumentError('Enter an agent name.');
  if (prompt.trim().isEmpty) {
    throw ArgumentError('Enter a prompt for this agent.');
  }
  if (!AgentAvatar.available.any((avatar) => avatar.id == avatarId)) {
    throw ArgumentError('Choose an available avatar.');
  }
}

@Riverpod(retry: _noRetry)
Future<AgentDetails> agentDetails(
  Ref ref,
  String instanceId,
  String profile,
) async {
  final connection = await ref.watch(connectionProvider(instanceId).future);
  final result = await connection.transport.call(
    HermesMethods.profilesDescribe,
    ProfileNameParams(name: profile),
  );
  return AgentDetails(prompt: result.soul);
}

@riverpod
AgentProfile? agentProfile(Ref ref, String instanceId, String profile) => ref
    .watch(agentProfilesProvider(instanceId))
    .value
    ?.where((agent) => agent.profile == profile)
    .firstOrNull;
