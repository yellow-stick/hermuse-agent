import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:riverpod/misc.dart';

import 'content.dart';
import 'plugin_api.dart';
import 'transport.dart';

/// Riverpod overrides running the app on the demo: chats come from
/// [DemoTransport], plugin routes from [demoPluginClient]. Ages of chats and
/// records count back from [now] (page load by default).
List<Override> demoOverrides({DateTime? now}) {
  final loaded = now ?? DateTime.now();
  return [
    transportFactoryProvider.overrideWithValue(
      (instance) async => DemoTransport(_byId(instance.id), now: loaded),
    ),
    for (final instance in demoInstances)
      restClientProvider(instance.id).overrideWith((ref) async {
        final client = demoPluginClient(instance, now: loaded);
        ref.onDispose(client.close);
        return HermesRestClient(client, baseUrl: Uri.parse(instance.baseUrl));
      }),
  ];
}

DemoInstance _byId(String id) => demoInstances.firstWhere((i) => i.id == id);

/// Replaces everything in [db] with the demo instances, their chat index
/// and the search cache of their transcripts, the main chat of the primary
/// instance on screen.
Future<void> seedDemo(HermuseDatabase db, {DateTime? now}) async {
  final loaded = now ?? DateTime.now();
  // Removing the instances cascades to their sessions and cached messages,
  // so chats of an earlier demo version never linger.
  await db.saveInstances(const []);
  await db.saveInstances([
    for (final instance in demoInstances)
      HermesInstance(
        id: instance.id,
        label: instance.label,
        kind: InstanceKind.remote,
        baseUrl: Uri.parse(instance.baseUrl),
        auth: AuthMethod.password,
      ),
  ], primaryId: demoInstances.first.id);
  for (final instance in demoInstances) {
    // Settings keys of `ActiveThread` (hermuse_state providers.dart).
    await db.writeSetting('main_session:${instance.id}', instance.main.id);
    await db.writeSetting('open_thread:${instance.id}', instance.main.id);
    for (final chat in instance.chats) {
      final updated = loaded.subtract(chat.age).millisecondsSinceEpoch;
      await db.upsertSession(
        SessionRow(
          instanceId: instance.id,
          sessionId: chat.id,
          title: chat.title,
          parentId: identical(chat, instance.main) ? null : instance.main.id,
          updatedAt: updated,
          archived: chat.archived,
          pinnedAt: chat.pinned ? updated : null,
        ),
      );
      await db.cacheTranscript(
        instance.id,
        chat.id,
        _searchRows(instance, chat),
      );
    }
  }
  await db.writeSetting(
    'active_thread',
    jsonEncode({'instance_id': demoInstances.first.id}),
  );
}

/// Search cache rows of [chat], keyed like the chat controller keys its
/// messages: a user row is a message, consecutive agent rows (tool calls
/// included) are one message carrying the id of its last assistant row.
List<CachedMessage> _searchRows(DemoInstance instance, DemoChat chat) {
  final base = demoRowBase(instance, chat);
  final out = <CachedMessage>[];
  CachedMessage row(int index, String author, String text) => CachedMessage(
    instanceId: instance.id,
    sessionId: chat.id,
    messageId: 'row-${base + index}',
    author: author,
    bodyText: text,
    createdAt: base + index,
  );
  int? turnId;
  final turn = <String>[];
  void endTurn() {
    if (turnId != null) out.add(row(turnId!, 'agent', turn.join('\n\n')));
    turnId = null;
    turn.clear();
  }

  for (final (i, r) in chat.rows.indexed) {
    switch (r.role) {
      case 'user':
        endTurn();
        out.add(row(i, 'user', r.text));
      case 'assistant':
        turnId = i;
        turn.add(r.text);
      default:
        // Tool rows join the turn but are not part of its searchable text.
        turnId ??= i;
    }
  }
  endTurn();
  return out;
}
