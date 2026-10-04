import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart';
import 'product.dart';

part 'identity.g.dart';

/// The agent's two memory files under `HERMES_HOME/memories/`.
enum MemoryTarget {
  /// What the agent keeps for itself (`MEMORY.md`).
  memory('MEMORY.md'),

  /// What it knows about the user (`USER.md`).
  user('USER.md');

  const MemoryTarget(this.fileName);
  final String fileName;
}

/// One memory file as entries. Shape (`GET /memory/{target}`): `{target,
/// entries: [str], updated_at}`.
final class AgentMemory {
  const AgentMemory({
    required this.target,
    required this.entries,
    this.updatedAt,
  });

  factory AgentMemory.fromJson(
    MemoryTarget target,
    Map<String, Object?> json,
  ) => AgentMemory(
    target: target,
    entries: [
      for (final e in (json['entries'] as List?) ?? const [])
        if (e is String) e,
    ],
    updatedAt: switch (json['updated_at']) {
      final String at when at.isNotEmpty => DateTime.tryParse(at),
      _ => null,
    },
  );

  final MemoryTarget target;
  final List<String> entries;

  /// Last write; null for a file never written.
  final DateTime? updatedAt;
}

/// [target]'s entries for [profile] on [instanceId] (the Identity tab's
/// memory editor), over the Hermuse plugin's `/memory/{target}`: Hermes
/// keeps them in the memory file, separated by `§` lines, written under its
/// memory lock.
@Riverpod(name: 'agentMemoryProvider')
class AgentMemoryState extends _$AgentMemoryState {
  @override
  Future<AgentMemory> build(
    String instanceId,
    MemoryTarget target, {
    String profile = 'default',
  }) async {
    if (await ref.watch(pluginStatusProvider(instanceId).future) !=
        PluginPresence.installed) {
      throw StateError('the Hermuse plugin is not installed on this instance');
    }
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    return AgentMemory.fromJson(target, await rest.getJson(_route));
  }

  /// Replaces the file's entries (trimmed, empty ones dropped).
  Future<void> save(List<String> entries) async {
    final kept = [
      for (final e in entries)
        if (e.trim().isNotEmpty) e.trim(),
    ];
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    await rest.putJson(_route, {'entries': kept});
    if (ref.mounted) {
      state = AsyncData(
        AgentMemory(target: target, entries: kept, updatedAt: DateTime.now()),
      );
    }
  }

  String get _route => '$hermusePluginRoute/memory/${target.name}';
}
