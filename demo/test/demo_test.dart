import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_demo/hermuse_demo.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  late HermuseDatabase db;
  late ProviderContainer container;
  final now = DateTime(2026, 9, 30, 9, 30);
  final ava = demoInstances.first;

  setUp(() async {
    db = openMemoryDatabase();
    await seedDemo(db, now: now);
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        ...demoOverrides(now: now),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<ChatController> openChat() async {
    final thread = (await container.read(activeThreadProvider.future))!;
    container.listen(chatSessionProvider(thread), (_, _) {});
    final chat = await container.read(chatSessionProvider(thread).future);
    await chat.ready;
    // Let the chat's own cache writes (after `ready`) land.
    await pumpEventQueue();
    return chat;
  }

  test(
    'the app opens on the primary instance main chat, transcript loaded',
    () async {
      final chat = await openChat();
      expect(chat.instanceId, ava.id);
      expect(chat.state.connection, ChatConnection.ready);
      expect(chat.state.activeThreadId, ava.main.id);
      expect(chat.state.mainThread.messages, isNotEmpty);
      expect(chat.state.sideThreads.map((t) => t.title), [
        for (final side in ava.sideChats)
          if (!side.archived) side.title,
      ], reason: 'archived side chats stay in the archive');
    },
  );

  test('every chat of every instance resumes with its messages', () async {
    for (final instance in demoInstances) {
      final transport = DemoTransport(instance, now: now);
      for (final chat in instance.chats) {
        final result = await transport.call(
          HermesMethods.sessionResume,
          SessionResumeParams(sessionId: chat.id),
        );
        expect(result.messages, hasLength(chat.rows.length), reason: chat.id);
      }
    }
  });

  test('opening a chat caches no search row beside the seeded ones', () async {
    final seeded = await db.loadMessages(ava.id, ava.main.id);
    final chat = await openChat();
    final cached = await db.loadMessages(ava.id, ava.main.id);
    expect(
      cached.map((m) => (m.messageId, m.bodyText)),
      seeded.map((m) => (m.messageId, m.bodyText)),
    );
    expect(
      cached.map((m) => m.messageId),
      chat.state.mainThread.messages.map((m) => m.id),
    );
  });

  test('sending is refused with the read-only message', () async {
    final chat = await openChat();
    await chat.send('Hello');
    await pumpEventQueue();
    expect(
      chat.state.mainThread.messages.last.plainText,
      contains(demoReadOnlyMessage),
    );
  });

  test('plugin routes serve the demo data and refuse writes', () async {
    final rest = await container.read(restClientProvider(ava.id).future);
    expect(
      await container.read(pluginStatusProvider(ava.id).future),
      PluginPresence.installed,
    );
    final posts = await container.read(feedProvider(ava.id).future);
    expect(posts.map((p) => p.title), [
      for (final post in ava.feed) post['title'],
    ]);
    expect(posts.first.createdAt, '2026-09-30 07:30');
    expect(
      (await container.read(goalsProvider(ava.id).future)).first.timeline,
      hasLength(2),
    );
    expect(
      await container.read(
        systemFileProvider(ava.id, preferencesFileName).future,
      ),
      isA<SystemFile>().having(
        (f) => f.content,
        'content',
        ava.files[preferencesFileName],
      ),
    );
    await expectLater(
      rest.postJson('$hermusePluginRoute/feed/feed-ava-1/react', {
        'reaction': 'love',
      }),
      throwsA(
        isA<HermesHttpError>()
            .having((e) => e.statusCode, 'status', 405)
            .having((e) => e.message, 'message', contains(demoReadOnlyMessage)),
      ),
    );
  });

  test('automations list the demo jobs; actions are refused', () async {
    final board = await container.read(automationsProvider(ava.id).future);
    expect(board.schedulerStopped, isFalse);
    expect(board.automations.map((a) => a.name), [
      'Evening recap',
      'Hermuse reflection (nightly)',
      'Hermuse feed (daily)',
      'Hermuse goals check-in (weekly)',
      'Hermuse ideas (weekly)',
    ]);
    final recap = board.automations.first;
    expect(recap.owner, AutomationOwner.user);
    expect(recap.nextRunAt, DateTime(2026, 9, 30, 18));
    expect(recap.lastRunAt, DateTime(2026, 9, 29, 18));
    expect(recap.lastOutcome, AutomationOutcome.ok);
    expect(
      (await container.read(automationsProvider(demoInstances[1].id).future))
          .automations
          .where((a) => a.owner == AutomationOwner.user),
      isEmpty,
    );

    await container
        .read(automationsProvider(ava.id).notifier)
        .perform(recap, AutomationAction.pause);
    final after = container.read(automationsProvider(ava.id)).value!;
    expect(after.error, contains(demoReadOnlyMessage));
    expect(after.automations.first.paused, isFalse);
  });

  test('seeding again replaces an earlier demo', () async {
    await db.upsertSession(
      SessionRow(
        instanceId: ava.id,
        sessionId: 'stale',
        title: 'Removed chat',
        parentId: ava.main.id,
        updatedAt: 0,
        archived: false,
      ),
    );
    await seedDemo(db, now: now);
    expect(
      (await db.loadSideChats(ava.id, ava.main.id)).map((s) => s.sessionId),
      isNot(contains('stale')),
    );
  });
}
