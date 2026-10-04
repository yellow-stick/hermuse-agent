import 'dart:async';

import 'package:hermes_client/hermes_client.dart';

import 'content.dart';

/// Message every refused call carries: the demo never changes anything.
const demoReadOnlyMessage =
    'This demo is read-only: its conversations are fictional.';

/// A [HermesTransport] answering from [DemoInstance] instead of a socket:
/// Session and profile reads use fictional data; mutations are refused
/// with [demoReadOnlyMessage].
final class DemoTransport implements HermesTransport {
  DemoTransport(this.instance, {DateTime? now}) : _now = now ?? DateTime.now();

  final DemoInstance instance;

  /// Page load time; chat ages count back from it.
  final DateTime _now;
  final _states = StreamController<ConnectionState>.broadcast();
  final _events = StreamController<HermesEvent>.broadcast();

  @override
  ConnectionState get currentState => ConnectionState.ready;

  @override
  Stream<ConnectionState> get state => _states.stream;

  @override
  Object? get lastError => null;

  @override
  Stream<HermesEvent> get events => _events.stream;

  @override
  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  ) async {
    if (method.name == HermesMethods.profilesList.name) {
      return ProfilesListResult(
        profiles: [
          ProfileRow(
            name: 'default',
            path: '/demo',
            isDefault: true,
            displayName: instance.label,
            uiMeta: {
              'hermuse': {
                'display_name': instance.label,
                'avatar_id': 'hermuse',
              },
            },
          ),
        ],
      ) as R;
    }
    if (method.name == HermesMethods.profilesDescribe.name) {
      return ProfilesDescribeResult(
        name: 'default',
        soul: instance.soul,
        model: const ProfileModelPin(),
      ) as R;
    }
    // Settings → Permissions reads Hermes' default approval policy.
    if (params is ConfigGetParams && params.key == 'approvals.mode') {
      return const ConfigGetResult(value: 'smart') as R;
    }
    if (params is SessionResumeParams) {
      final chat = instance.chats
          .where((c) => c.id == params.sessionId)
          .firstOrNull;
      if (chat != null) return _resume(chat) as R;
    }
    throw HermesRpcError(method.name, 4003, demoReadOnlyMessage);
  }

  SessionResumeResult _resume(DemoChat chat) {
    // Rows 40 s apart, the last one about [DemoChat.age] before page load;
    // a row with its own [DemoRow.age] (an earlier turn) sits there.
    final at = List<double>.filled(chat.rows.length, 0);
    var next = _now.subtract(chat.age);
    for (var i = chat.rows.length - 1; i >= 0; i--) {
      final age = chat.rows[i].age;
      next = age == null
          ? next.subtract(const Duration(seconds: 40))
          : _now.subtract(age);
      at[i] = next.millisecondsSinceEpoch / 1000;
    }
    final start = at.firstOrNull ?? _now.millisecondsSinceEpoch / 1000;
    final base = demoRowBase(instance, chat);
    return SessionResumeResult(
      sessionId: chat.id,
      messageCount: chat.rows.length,
      startedAt: start,
      running: false,
      messages: [
        for (final (i, row) in chat.rows.indexed)
          TranscriptMessage(
            role: row.role,
            text: row.role == 'tool' ? null : row.text,
            reasoning: row.reasoning,
            name: row.tool,
            context: row.role == 'tool' ? row.text : null,
            args: row.role == 'tool' && row.args.isNotEmpty ? row.args : null,
            toolCallId: row.role == 'tool' ? '${chat.id}-tool-$i' : null,
            timestamp: at[i],
            rowId: base + i,
          ),
      ],
      info: SessionLiveInfo(
        title: chat.title,
        model: instance.model,
        provider: instance.provider,
        storedSessionId: chat.id,
      ),
    );
  }

  @override
  void onServerRequest(ServerRequestHandler handler) {}

  @override
  void redeliverServerRequest(
    String id,
    String method,
    Map<String, Object?> params,
  ) {}

  @override
  Future<void> close() async {
    await _states.close();
    await _events.close();
  }
}

/// First transcript row id of [chat]: unique across the demo, so the
/// search cache keys (`row-<id>`) never collide between chats.
int demoRowBase(DemoInstance instance, DemoChat chat) =>
    (demoInstances.indexOf(instance) * 100 +
            instance.chats.toList().indexOf(chat)) *
        1000 +
    1;
