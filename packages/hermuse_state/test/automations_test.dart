import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

/// A `GET /api/cron/jobs` row as Hermes 0.21.5 lists it (trimmed to the
/// fields Hermuse reads plus a few it ignores).
Map<String, Object?> job(
  String id,
  String name, {
  Map<String, Object?> schedule = const {
    'kind': 'cron',
    'expr': '0 8 * * *',
    'display': '0 8 * * *',
  },
  String? next,
  String? last,
  String? lastStatus,
  String state = 'scheduled',
  bool enabled = true,
  String? origin,
  String originKey = 'feed',
  Object? heartbeat,
  bool? hidden,
}) => {
  'id': id,
  'name': name,
  'prompt': 'do it',
  'schedule': schedule,
  'schedule_display': schedule['display'],
  'enabled': enabled,
  'state': state,
  'next_run_at': next,
  'last_run_at': last,
  'last_status': lastStatus,
  'last_error': lastStatus == 'error' ? 'model unreachable' : null,
  'origin': origin == null ? null : {'source': origin, 'key': originKey},
  'deliver': 'local',
  'profile': 'default',
  'scheduler_heartbeat_age_s': heartbeat,
  'hidden': ?hidden,
};

void main() {
  group('describeSchedule', () {
    String cron(String expr) =>
        describeSchedule({'kind': 'cron', 'expr': expr, 'display': expr});

    test('words the usual cron shapes, server hours as written', () {
      expect(cron('0 8 * * *'), 'Every day at 8:00 AM');
      expect(cron('0 18 * * *'), 'Every day at 6:00 PM');
      expect(cron('30 0 * * *'), 'Every day at 12:30 AM');
      expect(cron('0 9 * * 1'), 'Every Monday at 9:00 AM');
      expect(cron('0 9 * * 0'), 'Every Sunday at 9:00 AM');
      expect(cron('0 9 * * 7'), 'Every Sunday at 9:00 AM');
      expect(cron('0 7 * * 1-5'), 'Every weekday at 7:00 AM');
      expect(cron('0 10 * * 1,5'), 'Every Monday and Friday at 10:00 AM');
      expect(cron('0 8,18 * * *'), 'Every day at 8:00 AM and 6:00 PM');
      expect(cron('0 6 1 * *'), 'Every month on the 1st at 6:00 AM');
      expect(cron('*/15 * * * *'), 'Every 15 minutes');
      expect(cron('5 * * * *'), 'Every hour at :05');
      expect(cron('0 */2 * * *'), 'Every 2 hours');
    });

    test('shows an expression it cannot word as is', () {
      expect(cron('0 9 1 1 *'), 'Cron 0 9 1 1 *');
      expect(cron('0 9 1 * 1'), 'Cron 0 9 1 * 1');
      expect(cron('nonsense'), 'Cron nonsense');
    });

    test('intervals and one-shots', () {
      expect(
        describeSchedule({'kind': 'interval', 'minutes': 90}),
        'Every 90 minutes',
      );
      expect(
        describeSchedule({'kind': 'interval', 'minutes': 120}),
        'Every 2 hours',
      );
      expect(
        describeSchedule({'kind': 'interval', 'minutes': 1440}),
        'Every day',
      );
      final at = DateTime(2030, 3, 4, 18);
      expect(
        describeSchedule({'kind': 'once', 'run_at': at.toIso8601String()}),
        'Once, ${formatAutomationTime(at)}',
      );
    });
  });

  test('run times read relative to today', () {
    final now = DateTime(2026, 10, 2, 1, 30);
    expect(
      formatAutomationTime(DateTime(2026, 10, 2, 18), now),
      'Today at 6:00 PM',
    );
    expect(
      formatAutomationTime(DateTime(2026, 10, 3, 8), now),
      'Tomorrow at 8:00 AM',
    );
    expect(
      formatAutomationTime(DateTime(2026, 10, 1, 2), now),
      'Yesterday at 2:00 AM',
    );
    expect(
      formatAutomationTime(DateTime(2026, 10, 5, 9), now),
      'Mon at 9:00 AM',
    );
    expect(
      formatAutomationTime(DateTime(2026, 11, 20, 9), now),
      'Nov 20 at 9:00 AM',
    );
  });

  test('a job reads its owner, pause state and last outcome', () {
    final plugin = Automation.fromJson(
      job('a', 'Hermuse feed (daily)', origin: 'hermuse', lastStatus: 'ok'),
    );
    expect(plugin.owner, AutomationOwner.hermuse);
    expect(plugin.lastOutcome, AutomationOutcome.ok);
    expect(plugin.actions, [AutomationAction.pause, AutomationAction.runNow]);

    final mine = Automation.fromJson(
      job('b', 'Evening recap', state: 'paused', lastStatus: 'error'),
    );
    expect(mine.owner, AutomationOwner.user);
    expect(mine.paused, isTrue);
    expect(mine.lastOutcome, AutomationOutcome.failed);
    expect(mine.lastError, 'model unreachable');
    expect(mine.actions, [
      AutomationAction.resume,
      AutomationAction.runNow,
      AutomationAction.delete,
    ]);

    expect(
      Automation.fromJson(job('c', 'x', lastStatus: 'delivery_failed'))
          .lastOutcome,
      AutomationOutcome.deliveryFailed,
    );
    expect(Automation.fromJson(job('d', '  ')).name, 'd');
  });

  group('automationsProvider', () {
    late ProviderContainer container;
    late Map<String, http.Response Function(http.Request)> routes;
    late List<String> calls;

    http.Response json(Object? payload, [int status = 200]) =>
        http.Response.bytes(
          utf8.encode(jsonEncode(payload)),
          status,
          headers: {'content-type': 'application/json'},
        );

    setUp(() {
      calls = [];
      routes = {
        'GET /api/cron/jobs': (_) => json([
          job(
            'feed',
            'Hermuse feed (daily)',
            origin: 'hermuse',
            next: '2026-10-02T07:00:00+02:00',
          ),
          job(
            'heartbeat',
            'Hermuse heartbeat',
            origin: 'hermuse',
            originKey: 'heartbeat',
            schedule: const {'kind': 'interval', 'minutes': 30},
            next: '2026-10-03T08:00:00+02:00',
          ),
          job(
            'paused',
            'Old reminder',
            state: 'paused',
            enabled: false,
            next: '2026-10-02T09:00:00+02:00',
          ),
          job(
            'recap',
            'Evening recap',
            schedule: const {
              'kind': 'cron',
              'expr': '0 18 * * *',
              'display': '0 18 * * *',
            },
            next: '2026-10-02T18:00:00+02:00',
          ),
        ]),
      };
      final mock = MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        calls.add(key);
        final route = routes[key];
        return route == null
            ? json({'detail': 'Job not found'}, 404)
            : route(request);
      });
      container = ProviderContainer(
        overrides: [
          restClientProvider('vps').overrideWith(
            (ref) => HermesRestClient(
              mock,
              baseUrl: Uri.parse('https://vps.example'),
            ),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    Future<AutomationBoard> board() =>
        container.read(automationsProvider('vps').future);

    test(
      'lists soonest next run first, paused last; maintenance hidden',
      () async {
        final b = await board();
        expect(b.automations.map((a) => a.id), [
          'recap',
          'heartbeat',
          'paused',
        ]);
        expect(b.automations.first.schedule, 'Every day at 6:00 PM');
        expect(
          [
            for (final s in b.sections)
              '${s.group.label}: ${s.automations.map((a) => a.id).join(', ')}',
          ],
          ['Daily: recap, paused', 'Heartbeat: heartbeat'],
        );
      },
    );

    test('a scheduler that never ticked is reported', () async {
      expect((await board()).schedulerStopped, isTrue);
      routes['GET /api/cron/jobs'] = (_) =>
          json([job('a', 'A', heartbeat: 12.5)]);
      container.invalidate(automationsProvider('vps'));
      expect((await board()).schedulerStopped, isFalse);
      routes['GET /api/cron/jobs'] = (_) => json(<Object?>[]);
      container.invalidate(automationsProvider('vps'));
      expect((await board()).schedulerStopped, isFalse);
    });

    test('pause, resume and run now show the job Hermes returns', () async {
      final notifier = container.read(automationsProvider('vps').notifier);
      var b = await board();
      final recap = b.automations.first;
      routes['POST /api/cron/jobs/recap/pause'] = (_) =>
          json(job('recap', 'Evening recap', state: 'paused', enabled: false));
      final pausing = notifier.perform(recap, AutomationAction.pause);
      expect(container.read(automationsProvider('vps')).value!.busy, {
        'recap': AutomationAction.pause,
      });
      await pausing;
      b = container.read(automationsProvider('vps')).value!;
      expect(b.busy, isEmpty);
      // Paused jobs go last, by name.
      expect(b.automations.map((a) => (a.id, a.paused)), [
        ('heartbeat', false),
        ('recap', true),
        ('paused', true),
      ]);

      routes['POST /api/cron/jobs/recap/resume'] = (_) => json(
        job('recap', 'Evening recap', next: '2026-10-02T18:00:00+02:00'),
      );
      await notifier.perform(b.automations[1], AutomationAction.resume);
      b = container.read(automationsProvider('vps')).value!;
      expect(b.automations.map((a) => a.id), ['recap', 'heartbeat', 'paused']);

      routes['POST /api/cron/jobs/recap/trigger'] = (_) => json(
        job(
          'recap',
          'Evening recap',
          last: '2026-10-02T01:50:00+02:00',
          lastStatus: 'ok',
          next: '2026-10-02T18:00:00+02:00',
        ),
      );
      await notifier.perform(b.automations.first, AutomationAction.runNow);
      b = container.read(automationsProvider('vps')).value!;
      final ran = b.automations.firstWhere((a) => a.id == 'recap');
      expect(ran.lastOutcome, AutomationOutcome.ok);
      expect(ran.lastRunAt, isNotNull);
    });

    test('deleting removes the user job; Hermuse jobs cannot be', () async {
      final notifier = container.read(automationsProvider('vps').notifier);
      final b = await board();
      routes['DELETE /api/cron/jobs/recap'] = (_) => json({'ok': true});
      await notifier.perform(
        b.automations.firstWhere((a) => a.id == 'recap'),
        AutomationAction.delete,
      );
      expect(
        container
            .read(automationsProvider('vps'))
            .value!
            .automations
            .map((a) => a.id),
        ['heartbeat', 'paused'],
      );

      final heartbeat = b.automations.firstWhere((a) => a.id == 'heartbeat');
      expect(
        () => notifier.perform(heartbeat, AutomationAction.delete),
        throwsStateError,
      );
      expect(calls, isNot(contains('DELETE /api/cron/jobs/heartbeat')));
    });

    test('a refused action keeps the job and says why', () async {
      final notifier = container.read(automationsProvider('vps').notifier);
      final b = await board();
      routes['POST /api/cron/jobs/recap/trigger'] = (_) => json({
        'detail': 'Job is already running or was claimed by another scheduler',
      }, 409);
      await notifier.perform(b.automations.first, AutomationAction.runNow);
      final after = container.read(automationsProvider('vps')).value!;
      expect(after.automations.map((a) => a.id), [
        'recap',
        'heartbeat',
        'paused',
      ]);
      expect(after.error, contains('already running'));
      expect(after.busy, isEmpty);
    });
  });

  test('Upcoming groups: reminders, daily, weekly, other, heartbeat', () {
    UpcomingGroup group(Map<String, Object?> schedule) =>
        upcomingGroupOf(schedule);
    Map<String, Object?> cron(String expr) => {'kind': 'cron', 'expr': expr};
    expect(
      group({'kind': 'once', 'run_at': '2026-10-04T09:00:00Z'}),
      UpcomingGroup.reminders,
    );
    expect(group(cron('0 8 * * *')), UpcomingGroup.daily);
    expect(group(cron('0 8,18 * * *')), UpcomingGroup.daily);
    expect(group({'kind': 'interval', 'minutes': 1440}), UpcomingGroup.daily);
    expect(group(cron('0 9 * * 1')), UpcomingGroup.weekly);
    expect(group(cron('0 7 * * 1-5')), UpcomingGroup.weekly);
    expect(group({'kind': 'interval', 'minutes': 10080}), UpcomingGroup.weekly);
    expect(group(cron('*/15 * * * *')), UpcomingGroup.other);
    expect(group(cron('0 */2 * * *')), UpcomingGroup.other);
    expect(group(cron('0 6 1 * *')), UpcomingGroup.other);
    expect(group({'kind': 'interval', 'minutes': 90}), UpcomingGroup.other);

    final heartbeat = Automation.fromJson(
      job(
        'h',
        'Hermuse heartbeat',
        origin: 'hermuse',
        originKey: 'heartbeat',
        schedule: const {'kind': 'interval', 'minutes': 30},
      ),
    );
    expect(
      (heartbeat.group, heartbeat.hidden),
      (UpcomingGroup.heartbeat, false),
    );
    expect(heartbeat.actions, [
      AutomationAction.pause,
      AutomationAction.runNow,
    ]);
    for (final key in ['feed', 'ideas', 'goals', 'reflection']) {
      expect(
        Automation.fromJson(job(key, key, origin: 'hermuse', originKey: key))
            .hidden,
        isTrue,
      );
    }
    expect(Automation.fromJson(job('x', 'x', hidden: true)).hidden, isTrue);
    expect(Automation.fromJson(job('y', 'Trip check')).hidden, isFalse);
    // A one-shot reminder that already fired is no longer upcoming.
    expect(
      Automation.fromJson(
        job(
          'r',
          'Stretch',
          schedule: const {'kind': 'once', 'display': 'once in 2m'},
          state: 'completed',
          enabled: false,
        ),
      ).hidden,
      isTrue,
    );
  });

  test('run history: status, output excerpt, last_output fallback', () async {
    http.Response json(Object? payload, [int status = 200]) =>
        http.Response.bytes(
          utf8.encode(jsonEncode(payload)),
          status,
          headers: {'content-type': 'application/json'},
        );
    final asked = <String>[];
    final mock = MockClient((request) async {
      asked.add('${request.url.path}?${request.url.query}');
      return switch (request.url.path) {
        '/api/cron/jobs/j1/runs' => json({
          'runs': [
            {'id': 'cron_j1_3', 'started_at': 1790000000.0, 'is_active': true},
            {
              'id': 'cron_j1_2',
              'started_at': 1789990000.0,
              'ended_at': 1789990060.0,
              'end_reason': 'cron_complete',
              'is_active': false,
            },
            {
              'id': 'cron_j1_1',
              'started_at': 1789980000.0,
              'ended_at': 1789980060.0,
              'end_reason': 'cron_incomplete_no_output',
            },
          ],
          'limit': 10,
        }),
        '/api/cron/jobs/j1' => json(
          job('j1', 'Brief')..['last_output'] = 'Last words',
        ),
        '/api/sessions/cron_j1_2/messages' => json({
          'messages': [
            {'role': 'user', 'content': 'prompt'},
            {'role': 'assistant', 'content': 'Sunny, ${'x' * 400}'},
            {'role': 'assistant', 'content': ''},
          ],
        }),
        '/api/sessions/cron_j1_3/messages' => json({'messages': const []}),
        _ => json({'detail': 'Session not found'}, 404),
      };
    });
    final container = ProviderContainer(
      overrides: [
        restClientProvider('vps').overrideWith(
          (ref) =>
              HermesRestClient(mock, baseUrl: Uri.parse('https://vps.example')),
        ),
      ],
    );
    addTearDown(container.dispose);
    final runs = await container.read(
      automationRunsProvider('vps', 'j1').future,
    );
    expect(runs.map((r) => (r.id, r.status)), [
      ('cron_j1_3', AutomationRunStatus.running),
      ('cron_j1_2', AutomationRunStatus.ok),
      ('cron_j1_1', AutomationRunStatus.failed),
    ]);
    expect(runs[0].output, 'Last words');
    expect(runs[1].output, startsWith('Sunny, '));
    expect(runs[1].output.length, runOutputLimit);
    expect(runs[2].output, '');
    expect(
      runs[1].startedAt,
      DateTime.fromMillisecondsSinceEpoch(1789990000000),
    );
    expect(asked.first, '/api/cron/jobs/j1/runs?limit=10');
  });

  test('run history shows the delivered answer, not the narration', () async {
    final mock = MockClient((request) async {
      final payload = switch (request.url.path) {
        '/api/cron/jobs/j1/runs' => {
          'runs': [
            {
              'id': 'cron_j1_1',
              'started_at': 1789990000.0,
              'ended_at': 1789990060.0,
              'end_reason': 'cron_complete',
            },
          ],
        },
        '/api/sessions/cron_j1_1/messages' => {
          'messages': [
            {'role': 'user', 'content': 'Daily briefing'},
            {
              'role': 'assistant',
              'content': 'Checking the weather first.',
              'tool_calls': [
                {
                  'id': 'c1',
                  'function': {'name': 'web_search'},
                },
              ],
            },
            {'role': 'tool', 'content': '{"results": []}'},
            {
              'role': 'assistant',
              'content':
                  "I have enough (weather via wttr.in). Writing the briefing."
                  '\n\n## Daily briefing\n\n### Weather in Nantes\n'
                  '- 17°C, cloudy',
            },
            // A later narration that calls a tool delivers nothing.
            {
              'role': 'assistant',
              'content': 'Saving a copy.',
              'tool_calls': '[{"id": "c2"}]',
            },
          ],
        },
        _ => {'detail': 'Session not found'},
      };
      return http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final container = ProviderContainer(
      overrides: [
        restClientProvider('vps').overrideWith(
          (ref) =>
              HermesRestClient(mock, baseUrl: Uri.parse('https://vps.example')),
        ),
      ],
    );
    addTearDown(container.dispose);
    final runs = await container.read(
      automationRunsProvider('vps', 'j1').future,
    );
    expect(
      runs.single.output,
      'Daily briefing\n\nWeather in Nantes\n- 17°C, cloudy',
    );
  });
}
