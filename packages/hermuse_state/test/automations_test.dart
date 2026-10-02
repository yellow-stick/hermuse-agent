import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
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
  Object? heartbeat,
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
  'origin': origin == null ? null : {'source': origin, 'key': 'feed'},
  'deliver': 'local',
  'profile': 'default',
  'scheduler_heartbeat_age_s': heartbeat,
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

    test('lists soonest next run first, paused last', () async {
      final b = await board();
      expect(b.automations.map((a) => a.id), ['recap', 'feed', 'paused']);
      expect(b.automations.first.schedule, 'Every day at 6:00 PM');
    });

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
        ('feed', false),
        ('recap', true),
        ('paused', true),
      ]);

      routes['POST /api/cron/jobs/recap/resume'] = (_) => json(
        job('recap', 'Evening recap', next: '2026-10-02T18:00:00+02:00'),
      );
      await notifier.perform(b.automations[1], AutomationAction.resume);
      b = container.read(automationsProvider('vps')).value!;
      expect(b.automations.map((a) => a.id), ['recap', 'feed', 'paused']);

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
        ['feed', 'paused'],
      );

      final feed = b.automations.firstWhere((a) => a.id == 'feed');
      expect(
        () => notifier.perform(feed, AutomationAction.delete),
        throwsStateError,
      );
      expect(calls, isNot(contains('DELETE /api/cron/jobs/feed')));
    });

    test('a refused action keeps the job and says why', () async {
      final notifier = container.read(automationsProvider('vps').notifier);
      final b = await board();
      routes['POST /api/cron/jobs/recap/trigger'] = (_) => json({
        'detail': 'Job is already running or was claimed by another scheduler',
      }, 409);
      await notifier.perform(b.automations.first, AutomationAction.runNow);
      final after = container.read(automationsProvider('vps')).value!;
      expect(after.automations.map((a) => a.id), ['recap', 'feed', 'paused']);
      expect(after.error, contains('already running'));
      expect(after.busy, isEmpty);
    });
  });

  test('activity groups by local day, newest first', () {
    final now = DateTime(2026, 10, 2, 9);
    ActivityItem at(DateTime when) =>
        ActivityItem(tool: 'web_search', summary: '', at: when);
    final days = activityDays([
      at(DateTime(2026, 10, 2, 8, 30)),
      at(DateTime(2026, 10, 2, 0, 5)),
      at(DateTime(2026, 10, 1, 23, 59)),
      at(DateTime(2026, 9, 28, 12)),
      at(DateTime(2026, 9, 20, 12)),
      at(DateTime(2025, 12, 31, 12)),
    ], now);
    expect(
      [for (final d in days) (d.label, d.items.length)],
      [
        ('Today', 2),
        ('Yesterday', 1),
        ('Monday', 1),
        ('Sep 20', 1),
        ('Dec 31, 2025', 1),
      ],
    );
  });
}
