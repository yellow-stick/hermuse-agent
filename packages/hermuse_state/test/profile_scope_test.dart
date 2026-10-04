import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

final class _DelayedCreate implements HermesTransport {
  _DelayedCreate(this.fake);
  final FakeHermesTransport fake;
  final creating = Completer<void>();
  final release = Completer<void>();

  @override
  Future<R> call<P extends JsonObject, R extends Object>(
    HermesMethod<P, R> method,
    P params,
  ) async {
    if (method.name == 'session.create') {
      if (!creating.isCompleted) creating.complete();
      await release.future;
    }
    return fake.call(method, params);
  }

  @override
  ConnectionState get currentState => fake.currentState;
  @override
  Stream<ConnectionState> get state => fake.state;
  @override
  Object? get lastError => fake.lastError;
  @override
  Stream<HermesEvent> get events => fake.events;
  @override
  void onServerRequest(ServerRequestHandler handler) =>
      fake.onServerRequest(handler);
  @override
  void redeliverServerRequest(
    String id,
    String method,
    Map<String, Object?> params,
  ) => fake.redeliverServerRequest(id, method, params);
  @override
  Future<void> close() => fake.close();
}

void main() {
  group('Profile-scoped conversations', () {
    late HermuseDatabase db;
    late ProviderContainer container;
    late Map<String, FakeHermesTransport> transports;
    late Map<String, HermesTransport> overrides;
    late List<HermesInstance> opened;
    final secrets = MemorySecretStore();

    ProviderContainer launch() => ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(secrets),
        transportFactoryProvider.overrideWithValue((instance) async {
          opened.add(instance);
          final profile = instance.profile!;
          final fake = transports.putIfAbsent(profile, () {
            final fake = FakeHermesTransport();
            fake
              ..on('profiles.list', (_) => {'profiles': []})
              ..on(
                'session.resume',
                (p) => {
                  'session_id': 'live-${p['session_id']}',
                  'message_count': 1,
                  'info': const <String, Object?>{},
                  'messages': [
                    {
                      'role': 'user',
                      'text': '$profile private history',
                      'row_id': 1,
                    },
                  ],
                },
              )
              ..on(
                'session.create',
                (_) => {
                  'session_id': 'live-created',
                  'stored_session_id': 'created',
                  'message_count': 0,
                  'info': const <String, Object?>{},
                  'messages': const [],
                },
              )
              ..on('prompt.submit', (_) => const <String, Object?>{});
            return fake;
          });
          return overrides[profile] ?? fake;
        }),
      ],
    );

    setUp(() async {
      db = openMemoryDatabase();
      transports = {};
      overrides = {};
      opened = [];
      await db.saveInstances([
        HermesInstance(
          id: 'server',
          label: 'Server',
          kind: InstanceKind.remote,
          baseUrl: Uri.parse('https://server.example'),
          auth: AuthMethod.password,
        ),
      ]);
      container = launch();
    });
    tearDown(() async {
      container.dispose();
      await pumpEventQueue();
      await db.close();
    });

    test(
      'equal session ids keep history, cache and approval callbacks separate',
      () async {
        const a = ThreadRef(
          instanceId: 'server',
          profile: 'aya',
          sessionId: 'same',
        );
        const b = ThreadRef(
          instanceId: 'server',
          profile: 'noah',
          sessionId: 'same',
        );
        expect(a, isNot(b));
        final chatA = await container.read(chatSessionProvider(a).future);
        final chatB = await container.read(chatSessionProvider(b).future);
        await Future.wait([chatA.ready, chatB.ready]);
        await pumpEventQueue();
        expect(
          chatA.state.activeThread.messages.single.plainText,
          'aya private history',
        );
        expect(
          chatB.state.activeThread.messages.single.plainText,
          'noah private history',
        );
        expect(
          (await chatSearch(db, chatA, 'aya')).single.text,
          'aya private history',
        );
        expect(await chatSearch(db, chatB, 'aya'), isEmpty);
        expect(opened.every((i) => i.id == 'server'), isTrue);
        expect(opened.where((i) => i.profile == 'aya'), hasLength(1));
        expect(opened.where((i) => i.profile == 'noah'), hasLength(1));
        for (final profile in ['aya', 'noah']) {
          transports[profile]!.emitRequest('same-request', 'approval', {
            'session_id': 'live-same',
            'request_id': 'same-approval',
            'command': '$profile command',
            'allow_permanent': false,
          });
        }
        await pumpEventQueue();
        expect(chatA.state.approvals.single.command, 'aya command');
        expect(chatB.state.approvals.single.command, 'noah command');
        chatA.choose(chatA.state.approvals.single.messageId, 'Allow once');
        await pumpEventQueue();
        expect(transports['aya']!.replies['same-request']?['result'], {
          'choice': 'once',
        });
        expect(transports['noah']!.replies, isNot(contains('same-request')));
        expect(chatB.state.approvals, hasLength(1));
      },
    );

    test('last switch wins, restores per-profile main and side chats after relaunch', () async {
      await db.writeSetting('main_session:server', 'original');
      await db.writeSetting('main_session:server:profile:aya', 'same');
      await db.writeSetting('main_session:server:profile:noah', 'same');
      for (final profile in ['aya', 'noah']) {
        await db.upsertSession(
          SessionRow(
            instanceId: 'server',
            profile: profile,
            sessionId: 'side',
            title: '$profile side',
            parentId: 'same',
            updatedAt: 1,
            archived: false,
          ),
        );
      }
      await db.writeSetting('open_thread:server:profile:aya', 'side');
      final active = container.read(activeThreadProvider.notifier);
      expect(
        (await container.read(activeThreadProvider.future))!.sessionId,
        'original',
      );
      await Future.wait([
        active.openAgent('server', 'aya'),
        active.openAgent('server', 'noah'),
      ]);
      expect(container.read(activeThreadProvider).value!.profile, 'noah');
      expect(
        jsonDecode((await db.readSetting('active_thread'))!)['profile'],
        'noah',
      );
      await active.openAgent('server', 'aya');
      final aya = container.read(activeThreadProvider).requireValue!;
      final chat = await container.read(chatSessionProvider(aya).future);
      await chat.ready;
      expect(chat.state.activeThreadId, 'side');
      await active.openAgent('server', 'noah');
      await active.openInstance('server');
      expect(container.read(activeThreadProvider).value!.profile, 'noah');
      await active.openAgent('server', 'aya');
      expect(await container.read(chatSessionProvider(aya).future), same(chat));
      container.dispose();
      await pumpEventQueue();
      transports = {};
      container = launch();
      final restored = await container.read(activeThreadProvider.future);
      expect(restored, aya);
      final reopened = await container.read(
        chatSessionProvider(restored!).future,
      );
      await reopened.ready;
      expect(reopened.state.activeThreadId, 'side');
      await container
          .read(activeThreadProvider.notifier)
          .openAgent('server', 'default');
      expect(container.read(activeThreadProvider).value!.sessionId, 'original');
      expect(await db.readSetting('main_session:server'), 'original');
    });

    test('persists a cached draft before publishing selection', () async {
      await container.read(activeThreadProvider.future);
      final active = container.read(activeThreadProvider.notifier);
      await active.openAgent('server', 'aya');
      await active.openAgent('server', 'default');
      final held = Completer<void>();
      final release = Completer<void>();
      final blocker = db.transaction(() async {
        await db.customSelect('SELECT 1').get();
        held.complete();
        await release.future;
      });
      await held.future;
      final switching = active.openAgent('server', 'aya');
      try {
        await pumpEventQueue();
        expect(container.read(activeThreadProvider).value!.profile, 'default');
      } finally {
        release.complete();
        await blocker;
        await switching;
      }
      expect(container.read(activeThreadProvider).value!.profile, 'aya');
      expect(container.read(activeThreadProvider).value!.isNew, isTrue);
      container.dispose();
      await pumpEventQueue();
      container = launch();
      final restored = await container.read(activeThreadProvider.future);
      expect(restored!.profile, 'aya');
      expect(restored.isNew, isTrue);
    });

    test(
      'late session creation stays in the background and reuses its controller',
      () async {
        await container.read(activeThreadProvider.future);
        final active = container.read(activeThreadProvider.notifier);
        await active.openAgent('server', 'aya');
        final aya = container.read(activeThreadProvider).requireValue!;
        final fake = FakeHermesTransport()
          ..on(
            'session.create',
            (_) => {
              'session_id': 'live-created',
              'stored_session_id': 'created',
              'message_count': 0,
              'info': const <String, Object?>{},
              'messages': const [],
            },
          )
          ..on('prompt.submit', (_) => const <String, Object?>{});
        final delayed = _DelayedCreate(fake);
        overrides['aya'] = delayed;
        final chat = await container.read(chatSessionProvider(aya).future);
        await chat.ready;
        final sending = chat.send('keep working');
        await delayed.creating.future;
        await active.openAgent('server', 'noah');
        delayed.release.complete();
        await sending;
        await pumpEventQueue();
        expect(container.read(activeThreadProvider).value!.profile, 'noah');
        expect(
          jsonDecode((await db.readSetting('active_thread'))!)['profile'],
          'noah',
        );
        expect(
          await db.readSetting('main_session:server:profile:aya'),
          'created',
        );
        expect(
          chat.ref,
          const ThreadRef(
            instanceId: 'server',
            profile: 'aya',
            sessionId: 'created',
          ),
        );
        await active.openAgent('server', 'aya');
        final returning = container.read(activeThreadProvider).requireValue!;
        expect(returning, aya, reason: 'keep the original draft provider key');
        expect(
          await container.read(chatSessionProvider(returning).future),
          same(chat),
        );
        expect(fake.closed, isFalse);
      },
    );
  });
}
