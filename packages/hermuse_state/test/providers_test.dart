import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

void main() {
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ProviderContainer container;
  var opened = 0;

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    opened = 0;
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async {
          opened++;
          return fake;
        }),
      ],
    );
    final registry = await container.read(registryProvider.future);
    await registry.add(
      HermesInstance(
        id: 'vps',
        label: 'VPS',
        kind: InstanceKind.remote,
        baseUrl: Uri.parse('https://vps.example'),
        auth: AuthMethod.password,
      ),
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('the legacy open conversation becomes the main chat', () async {
    await db.writeSetting(
      'active_thread',
      '{"instance_id":"vps","session_id":"old-conv"}',
    );
    expect(
      await container.read(activeThreadProvider.future),
      const ThreadRef(instanceId: 'vps', sessionId: 'old-conv'),
    );
    await db.writeSetting('active_thread', '{"instance_id":"vps"}');
    container.invalidate(activeThreadProvider);
    expect(
      (await container.read(activeThreadProvider.future))!.sessionId,
      'old-conv',
      reason: 'remembered as main_session',
    );
  });

  test(
    'setup chat is the main chat, or a side chat of an existing one',
    () async {
      final active = container.read(activeThreadProvider.notifier);
      await container.read(activeThreadProvider.future);
      await active.openSetup(
        const ThreadRef(instanceId: 'vps', sessionId: 'w1'),
      );
      expect(container.read(activeThreadProvider).value!.sessionId, 'w1');

      await active.openSetup(
        const ThreadRef(instanceId: 'vps', sessionId: 'w2'),
      );
      expect(container.read(activeThreadProvider).value!.sessionId, 'w1');
      final side = (await db.loadSideChats('vps', 'w1')).single;
      expect((side.sessionId, side.title), ('w2', setupChatTitle));
      fake.on(
        'session.resume',
        (p) => {
          'session_id': 'live-${p['session_id']}',
          'message_count': 0,
          'info': const <String, Object?>{},
          'messages': const [],
        },
      );
      const main = ThreadRef(instanceId: 'vps', sessionId: 'w1');
      final sub = container.listen(chatSessionProvider(main), (_, _) {});
      addTearDown(sub.close);
      final chat = await container.read(chatSessionProvider(main).future);
      expect(
        chat.state.activeThreadId,
        'w2',
        reason: 'opens on the setup chat',
      );
    },
  );

  test('side chat list: drafts first, then pinned, then recent', () async {
    SessionRow row(String id, int at, {int? pinned}) => SessionRow(
      instanceId: 'vps',
      sessionId: id,
      title: 'db $id',
      parentId: 'm',
      updatedAt: at,
      archived: false,
      pinnedAt: pinned,
    );
    final state = ChatState(
      agentName: 'VPS',
      threads: const [
        Thread(id: 'm', title: 'Chat', startedAt: '', messages: []),
        Thread(id: 'a', title: '', startedAt: '', messages: []),
        Thread(id: 'b', title: 'Live b', startedAt: '', messages: []),
        Thread(id: 'draft-1', title: '', startedAt: '', messages: []),
      ],
      activeThreadId: 'm',
    );
    final entries = sideChatEntries(state, [
      row('b', 5, pinned: 1),
      row('a', 9),
    ]);
    expect(entries.map((e) => (e.threadId, e.title, e.pinned)), [
      ('draft-1', '', false),
      ('b', 'Live b', true),
      ('a', 'db a', false),
    ]);
  });

  test(
    'a chat reuses one connection and caches settled turns for search',
    () async {
      fake
        ..on(
          'session.resume',
          (_) => {
            'session_id': 'live',
            'message_count': 1,
            'info': const <String, Object?>{},
            'messages': [
              {'role': 'user', 'text': 'weather in Oslo', 'row_id': 7},
            ],
          },
        )
        ..on('prompt.submit', (_) => const <String, Object?>{});
      const ref = ThreadRef(instanceId: 'vps', sessionId: 'main');
      final sub = container.listen(chatSessionProvider(ref), (_, _) {});
      addTearDown(sub.close);
      final chat = await container.read(chatSessionProvider(ref).future);
      await chat.ready;
      await chat.send('and Bergen?');
      fake.emitEvent(
        'message.complete',
        sessionId: 'live',
        payload: {
          'text': 'Rainy in Bergen',
          'status': 'complete',
          'persisted_turn': {
            'row_ids': [8, 9],
            'complete': true,
            'user_row_id': 8,
            'final_assistant_row_id': 9,
          },
        },
      );
      await pumpEventQueue();
      expect(opened, 1);
      expect(chat.state.agentName, 'VPS');
      final hits = await chatSearch(db, chat, 'bergen');
      expect(hits.map((h) => (h.threadId, h.threadTitle, h.isTitle)), [
        ('main', 'Main chat', false),
        ('main', 'Main chat', false),
      ]);
      expect(
        (await chatSearch(db, chat, 'oslo')).single.text,
        'weather in Oslo',
      );
    },
  );

  test('disposing the container closes the transport', () async {
    await container.read(connectionProvider('vps').future);
    container.dispose();
    expect(fake.closed, isTrue);
  });
}
