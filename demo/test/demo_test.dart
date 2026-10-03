import 'dart:typed_data';

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
      // Yesterday's Evening recap brief: a notice line, then the reply.
      final brief = chat.state.mainThread.messages.first;
      expect(brief.author, Author.agent);
      expect(brief.plainText, 'Scheduled: Evening recap');
      expect(
        chat.state.mainThread.messages[1].plainText,
        startsWith('Quick evening recap'),
      );
      expect(chat.state.sideThreads.map((t) => t.title), [
        'Weekend in Annecy',
        'Night pass — emails + code',
        'Nightly to-do list',
        'Autumn half-marathon',
      ], reason: 'pinned first, then by recency');
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
    expect(posts.first.title, 'Your day — 4 things');
    expect(posts.first.createdAt, '2026-09-30 08:30');
    expect(
      (await container.read(goalsProvider(ava.id).future)).first.timeline,
      hasLength(3),
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
    // The fake computer: running, stills per browser step, ticket allowed.
    final computer = await container.read(
      computerClientProvider(ava.id).future,
    );
    final status = await computer.status();
    expect(status.state, ComputerState.running);
    final shot = await computer.snapshot('${ava.main.id}-tool-4');
    expect(shot, isNotEmpty);
    expect(shot!.first, 0xFF);
    expect(await computer.thumbnail(), isNotEmpty);
    final session = await computer.open();
    final views = <ComputerViewState>[];
    final frames = <Uint8List>[];
    session.states.listen(views.add);
    session.frames.listen(frames.add);
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(views, isNotEmpty);
    expect(frames, isNotEmpty);
    expect(frames.first.first, 0xFF);
    // Take control answers but hands over nothing; mode flips the frame.
    session.take();
    await pumpEventQueue();
    expect(views.last.inControl, isFalse);
    session.setMode(ComputerMode.desktop);
    await pumpEventQueue();
    expect(views.last.mode, ComputerMode.desktop);
    await session.close();
    await expectLater(
      rest.postJson('$hermusePluginRoute/feed/feed-ava-0/react', {
        'reaction': 'love',
      }),
      throwsA(
        isA<HermesHttpError>()
            .having((e) => e.statusCode, 'status', 405)
            .having((e) => e.message, 'message', contains(demoReadOnlyMessage)),
      ),
    );
  });

  test('upcoming lists the visible demo jobs; actions are refused', () async {
    final board = await container.read(automationsProvider(ava.id).future);
    expect(board.schedulerStopped, isFalse);
    expect(board.automations.map((a) => a.id), [
      'hermuse-heartbeat',
      'ava-train-fares',
      'ava-evening-recap',
      'ava-nightly-review',
      'ava-school-form',
      'ava-half-marathon-checkin',
    ], reason: 'maintenance jobs hidden, soonest first');
    final heartbeat = board.automations.first;
    expect(heartbeat.group, UpcomingGroup.heartbeat);
    expect(heartbeat.nextRunAt, DateTime(2026, 9, 30, 9, 50));
    expect(heartbeat.lastOutput, 'Nothing needed you.');
    expect(board.sections.map((s) => s.group), [
      UpcomingGroup.reminders,
      UpcomingGroup.daily,
      UpcomingGroup.weekly,
      UpcomingGroup.other,
      UpcomingGroup.heartbeat,
    ]);
    final recap = board.automations[2];
    expect(recap.owner, AutomationOwner.user);
    expect(recap.nextRunAt, DateTime(2026, 9, 30, 18));
    expect(recap.lastRunAt, DateTime(2026, 9, 29, 18));
    expect(recap.lastOutcome, AutomationOutcome.ok);
    expect(recap.lastOutput, startsWith('Done today'));
    final reminder = board.automations[4];
    expect(reminder.nextRunAt, DateTime(2026, 10, 1, 8));
    expect(reminder.lastRunAt, isNull);
    expect(
      (await container.read(automationsProvider(demoInstances[1].id).future))
          .automations
          .map((a) => a.id),
      ['hermuse-heartbeat'],
    );

    await container
        .read(automationsProvider(ava.id).notifier)
        .perform(recap, AutomationAction.pause);
    final after = container.read(automationsProvider(ava.id)).value!;
    expect(after.error, contains(demoReadOnlyMessage));
    expect(after.automations[2].paused, isFalse);
  });

  test('automation runs carry their outputs', () async {
    final runs = await container.read(
      automationRunsProvider(ava.id, 'ava-nightly-review').future,
    );
    expect(runs.map((r) => r.status), [
      AutomationRunStatus.ok,
      AutomationRunStatus.failed,
      AutomationRunStatus.ok,
    ]);
    expect(runs.first.startedAt, DateTime(2026, 9, 30, 2));
    expect(runs.first.output, startsWith('18 emails read'));
    expect(
      await container.read(
        automationRunsProvider(ava.id, 'ava-school-form').future,
      ),
      isEmpty,
    );
  });

  test('activity, identity and approvals read the demo data', () async {
    final tasks = await container.read(tasksProvider(ava.id).future);
    expect(tasks, hasLength(ava.tasks.length));
    expect(tasks.first.finishedAt, DateTime(2026, 9, 30, 9, 18));
    expect(tasks.map((t) => t.source).toSet(), {
      TaskSource.chat,
      TaskSource.cron,
      TaskSource.heartbeat,
    });
    expect(activityDays(tasks, now).map((d) => d.label), [
      'Today',
      'Yesterday',
      'Monday',
    ]);
    final threads = {for (final chat in ava.chats) chat.id};
    expect(
      tasks.where((t) => threads.contains(t.sessionId)),
      hasLength(tasks.length - 1),
    );

    final memory = await container.read(
      agentMemoryProvider(ava.id, MemoryTarget.memory).future,
    );
    expect(memory.entries, ava.memory);
    expect(memory.updatedAt, isNotNull);
    expect(
      (await container.read(
        agentMemoryProvider(ava.id, MemoryTarget.user).future,
      )).entries,
      ava.userMemory,
    );
    await expectLater(
      container
          .read(agentMemoryProvider(ava.id, MemoryTarget.user).notifier)
          .save(['x']),
      throwsA(isA<HermesHttpError>()),
    );

    expect(
      (await container.read(agentDetailsProvider(ava.id, 'default').future))
          .prompt,
      ava.soul,
    );
    expect(
      await container.read(approvalsModeProvider(ava.id).future),
      ApprovalsMode.smart,
    );
    await expectLater(
      container
          .read(approvalsModeProvider(ava.id).notifier)
          .set(ApprovalsMode.off),
      throwsA(isA<HermesRpcError>()),
    );
  });

  test('goals, feed and ideas carry the proactive fields', () async {
    final goals = await container.read(goalsProvider(ava.id).future);
    final sections = goalSections(goals);
    expect(sections.tracking.map((g) => g.id), contains('goal-ava-3'));
    expect(sections.goals.map((g) => g.id), contains('goal-ava-1'));
    final marathon = goals.firstWhere((g) => g.id == 'goal-ava-1');
    expect(sections.subgoalsOf(marathon), hasLength(2));
    expect(marathon.cronJobId, 'ava-half-marathon-checkin');
    expect(marathon.statusLine, isNotEmpty);

    final posts = await container.read(feedProvider(ava.id).future);
    expect(posts.where((p) => p.why.isNotEmpty), hasLength(posts.length - 1));

    final ideas = await container.read(ideasProvider(ava.id).future);
    expect(ideas.take(2).map((i) => i.seeded), [false, false]);
    final seeds = ideas.where((i) => i.seeded).toList();
    expect(seeds, hasLength(10));
    expect(seeds.every((i) => i.id.startsWith('seed-')), isTrue);
    expect(seeds.every((i) => i.icon.isNotEmpty && i.file.isEmpty), isTrue);
  });

  test('seeding again replaces an earlier demo', () async {
    await db.upsertSession(
      SessionRow(
        instanceId: ava.id,
        profile: 'default',
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
