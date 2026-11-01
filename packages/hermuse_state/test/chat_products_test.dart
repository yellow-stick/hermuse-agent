import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

void main() {
  late HermuseDatabase db;
  late ProviderContainer container;
  late FakeHermesTransport transport;
  late ChatController chat;
  late List<Map<String, Object?>> posts;
  late List<Map<String, Object?>> jobs;
  late Map<String, int> requests;
  late Completer<http.Response> pauseResponse;
  final feed = feedProvider('server', profile: 'aya');
  final automations = automationsProvider('server', profile: 'aya');

  setUp(() async {
    db = openMemoryDatabase();
    posts = [];
    jobs = [];
    requests = {};
    pauseResponse = Completer<http.Response>();
    transport = FakeHermesTransport()
      ..on('profiles.list', (_) => {'profiles': []})
      ..on(
        'session.resume',
        (_) => {
          'session_id': 'live',
          'message_count': 0,
          'info': <String, Object?>{},
          'messages': <Object?>[],
        },
      )
      ..on('prompt.submit', (_) => <String, Object?>{});
    final httpClient = MockClient((request) async {
      final key = '${request.url.host}${request.url.path}';
      requests.update(key, (count) => count + 1, ifAbsent: () => 1);
      if (request.url.path.endsWith('/pause')) return pauseResponse.future;
      return http.Response(
        jsonEncode(switch (request.url.path) {
          '/api/plugins/hermuse/feed' => {'posts': posts},
          '/api/cron/jobs' => {'data': jobs},
          _ => <String, Object?>{},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => transport),
        pluginStatusProvider('server')
            .overrideWith((_) => PluginPresence.installed),
        for (final profile in ['aya', 'noah'])
          restClientProvider('server', profile: profile).overrideWith(
            (_) => HermesRestClient(
              httpClient,
              baseUrl: Uri.parse('https://$profile.example'),
            ),
          ),
      ],
    );
    await db.saveInstances([
      HermesInstance(
        id: 'server',
        label: 'Server',
        kind: InstanceKind.remote,
        baseUrl: Uri.parse('https://server.example'),
        auth: AuthMethod.password,
      ),
    ]);
    for (final profile in ['aya', 'noah']) {
      container.listen(feedProvider('server', profile: profile), (_, _) {});
      container.listen(
        automationsProvider('server', profile: profile),
        (_, _) {},
      );
      await container.read(feedProvider('server', profile: profile).future);
      await container.read(
        automationsProvider('server', profile: profile).future,
      );
    }
    chat = await container.read(
      chatSessionProvider(
        const ThreadRef(
          instanceId: 'server',
          profile: 'aya',
          sessionId: 'main',
        ),
      ).future,
    );
    await chat.ready;
    await chat.send(
      'Keep useful research in my feed and schedule a daily recap.',
    );
  });

  tearDown(() async {
    container.dispose();
    await pumpEventQueue();
    await db.close();
  });

  void publish() {
    posts = [
      {
        'id': 'research',
        'title': 'Research worth keeping',
        'body': 'The findings.',
      },
    ];
    jobs = [
      {
        'id': 'recap',
        'name': 'Daily recap',
        'enabled': true,
        'state': 'scheduled',
        'schedule': {'kind': 'cron', 'expr': '0 18 * * *'},
      },
    ];
  }

  test('tool completions update open feed and automation views only for their agent', () async {
    expect(await container.read(feed.future), isEmpty);
    expect((await container.read(automations.future)).automations, isEmpty);
    publish();
    transport.emitEvent(
      'tool.complete',
      sessionId: 'live',
      payload: {
        'tool_id': 'feed-call',
        'name': 'feed_post',
        'summary': 'Published',
      },
    );
    await pumpEventQueue();
    expect(
      (await container.read(feed.future)).single.title,
      'Research worth keeping',
    );
    expect((await container.read(automations.future)).automations, isEmpty);
    transport.emitEvent(
      'tool.complete',
      sessionId: 'live',
      payload: {
        'tool_id': 'cron-call',
        'name': 'cronjob_manage',
        'summary': 'Scheduled',
      },
    );
    await pumpEventQueue();
    expect(
      (await container.read(automations.future)).automations.single.name,
      'Daily recap',
    );
    expect(requests['noah.example/api/plugins/hermuse/feed'], 1);
    expect(requests['noah.example/api/cron/jobs'], 1);
    expect(
      await container.read(feedProvider('server', profile: 'noah').future),
      isEmpty,
    );
    expect(
      (await container.read(
        automationsProvider('server', profile: 'noah').future,
      )).automations,
      isEmpty,
    );
  });

  test(
    'turn completion reconciles changes made without product tool events',
    () async {
      publish();
      transport.emitEvent(
        'message.complete',
        sessionId: 'live',
        payload: {'text': 'Saved and scheduled.', 'status': 'complete'},
      );
      await pumpEventQueue();
      expect((await container.read(feed.future)).single.id, 'research');
      expect(
        (await container.read(automations.future)).automations.single.id,
        'recap',
      );
    },
  );

  test(
    'chat refresh waits for a pending automation action before reconciling',
    () async {
      publish();
      container.invalidate(automations);
      final notifier = container.read(automations.notifier);
      final board = await container.read(automations.future);
      final pausing = notifier.perform(
        board.automations.single,
        AutomationAction.pause,
      );
      await pumpEventQueue();
      jobs = [
        {...jobs.single, 'state': 'paused', 'enabled': false},
        {
          'id': 'new',
          'name': 'New reminder',
          'schedule': {'kind': 'interval', 'minutes': 30},
        },
      ];
      transport.emitEvent(
        'tool.complete',
        sessionId: 'live',
        payload: {
          'tool_id': 'cron-call',
          'name': 'cronjob_manage',
          'summary': 'Scheduled',
        },
      );
      await pumpEventQueue();
      expect(container.read(automations).value!.busy, {
        'recap': AutomationAction.pause,
      });
      pauseResponse.complete(http.Response(jsonEncode(jobs.first), 200));
      await pausing;
      await pumpEventQueue();
      final refreshed = await container.read(automations.future);
      expect(refreshed.busy, isEmpty);
      expect(
        refreshed.automations.map((job) => job.id),
        containsAll(['new', 'recap']),
      );
      expect(
        refreshed.automations.singleWhere((job) => job.id == 'recap').paused,
        isTrue,
      );
    },
  );
}
