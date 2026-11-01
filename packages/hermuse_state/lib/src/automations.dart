import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart';
import 'product.dart' show hermesReason;

part 'automations.g.dart';

/// Hermes' cron API on the dashboard (`hermes_cli/web_routers/cron.py`).
const hermesCronRoute = '/api/cron/jobs';

/// Who created an automation: the Hermuse plugin (its maintenance jobs and
/// the heartbeat, `origin.source == 'hermuse'`) or the user, asking their
/// agent.
enum AutomationOwner { hermuse, user }

/// Outcome of an automation's last run (`last_status`).
enum AutomationOutcome {
  ok,
  failed,

  /// The agent ran but its result could not be delivered.
  deliveryFailed,
}

/// A user action on one automation.
enum AutomationAction { pause, resume, runNow, delete }

/// Sections of the profile panel's Upcoming tab, in order.
enum UpcomingGroup {
  /// One-shot jobs (`schedule.kind == 'once'`).
  reminders('Reminders'),
  daily('Daily'),
  weekly('Weekly'),
  other('Other recurring'),

  /// The Hermuse heartbeat (`origin.key == 'heartbeat'`).
  heartbeat('Heartbeat');

  const UpcomingGroup(this.label);
  final String label;
}

/// Origin key of the Hermuse heartbeat job; every other Hermuse job is
/// maintenance (feed, ideas, goals check-in, reflection), hidden.
const hermuseHeartbeatKey = 'heartbeat';

/// One Hermes cron job. Shape: `{id, name, schedule: {kind, expr?, minutes?,
/// run_at?, display}, enabled, state, next_run_at, last_run_at,
/// last_status, last_error, last_output, last_delivery_error,
/// origin: {source, key}?, hidden?}`.
final class Automation {
  const Automation({
    required this.id,
    required this.name,
    required this.schedule,
    required this.owner,
    required this.paused,
    this.group = UpcomingGroup.other,
    this.hidden = false,
    this.nextRunAt,
    this.lastRunAt,
    this.lastOutcome,
    this.lastError = '',
    this.lastOutput = '',
    this.lastDeliveryError = '',
  });

  factory Automation.fromJson(Map<String, Object?> json) {
    final origin = json['origin'];
    final hermuse = origin is Map && origin['source'] == 'hermuse';
    final heartbeat = hermuse && origin['key'] == hermuseHeartbeatKey;
    final state = json['state'] as String? ?? '';
    final lastStatus = json['last_status'] as String?;
    final schedule =
        (json['schedule'] as Map?)?.cast<String, Object?>() ?? const {};
    return Automation(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : json['id'] as String,
      schedule: describeSchedule(schedule),
      owner: hermuse ? AutomationOwner.hermuse : AutomationOwner.user,
      paused: state == 'paused' || json['enabled'] == false,
      group: heartbeat ? UpcomingGroup.heartbeat : upcomingGroupOf(schedule),
      // A fired one-shot reminder is done, not upcoming (Hermes keeps it
      // disabled with state `completed`).
      hidden:
          json['hidden'] == true ||
          (hermuse && !heartbeat) ||
          state == 'completed',
      nextRunAt: _parseTime(json['next_run_at']),
      lastRunAt: _parseTime(json['last_run_at']),
      lastOutcome: switch (lastStatus) {
        null || '' => null,
        'ok' => AutomationOutcome.ok,
        'delivery_failed' => AutomationOutcome.deliveryFailed,
        _ => AutomationOutcome.failed,
      },
      lastError: json['last_error'] as String? ?? '',
      lastOutput: json['last_output'] as String? ?? '',
      lastDeliveryError: json['last_delivery_error'] as String? ?? '',
    );
  }

  final String id;
  final String name;

  /// How often it runs, in words ("Every day at 8:00 AM").
  final String schedule;
  final AutomationOwner owner;
  final bool paused;

  /// Its section of the Upcoming tab.
  final UpcomingGroup group;

  /// A Hermuse maintenance job (or one the server marks `hidden`): not
  /// listed.
  final bool hidden;

  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final AutomationOutcome? lastOutcome;
  final String lastError;

  /// What the last run answered (Hermes' `last_output`).
  final String lastOutput;

  /// Why the last result could not be delivered.
  final String lastDeliveryError;

  /// Only the user's own automations can be deleted: the plugin registers
  /// its jobs again whenever its schedule is turned on (pausing sticks).
  bool get deletable => owner == AutomationOwner.user;

  /// The actions offered for this automation.
  List<AutomationAction> get actions => [
    paused ? AutomationAction.resume : AutomationAction.pause,
    AutomationAction.runNow,
    if (deletable) AutomationAction.delete,
  ];
}

/// [UpcomingGroup] of a Hermes [schedule] (heartbeat aside): one-shot jobs
/// are reminders; a job at fixed times every day is daily, on some weekdays
/// weekly (an interval of exactly a day or a week too); anything else is
/// other recurring.
UpcomingGroup upcomingGroupOf(Map<String, Object?> schedule) {
  switch (schedule['kind']) {
    case 'once':
      return UpcomingGroup.reminders;
    case 'interval':
      return switch ((schedule['minutes'] as num?)?.toInt()) {
        1440 => UpcomingGroup.daily,
        10080 => UpcomingGroup.weekly,
        _ => UpcomingGroup.other,
      };
    case 'cron':
      final f = '${schedule['expr'] ?? ''}'.trim().split(RegExp(r'\s+'));
      if (f.length != 5) return UpcomingGroup.other;
      final [minute, hour, dayOfMonth, month, dayOfWeek] = f;
      final fixedTime =
          int.tryParse(minute) != null &&
          hour.split(',').every((h) => int.tryParse(h) != null);
      if (!fixedTime || month != '*' || dayOfMonth != '*') {
        return UpcomingGroup.other;
      }
      return dayOfWeek == '*' ? UpcomingGroup.daily : UpcomingGroup.weekly;
  }
  return UpcomingGroup.other;
}

/// One section of the Upcoming tab.
final class UpcomingSection {
  const UpcomingSection(this.group, this.automations);
  final UpcomingGroup group;

  /// Sorted by next run ([sortAutomations]).
  final List<Automation> automations;
}

/// The Upcoming tab of one agent.
final class AutomationBoard {
  const AutomationBoard({
    required this.automations,
    this.schedulerStopped = false,
    this.busy = const {},
    this.error,
  });

  /// The listed jobs (hidden ones left out), sorted by next run
  /// ([sortAutomations]).
  final List<Automation> automations;

  /// No Hermes scheduler ticks for these jobs: they only run when started
  /// by hand until the Hermes gateway runs on the server.
  final bool schedulerStopped;

  /// Automations with an action in flight, and which.
  final Map<String, AutomationAction> busy;

  /// Why the last action failed, in the server's words.
  final String? error;

  /// [automations] by [UpcomingGroup], in tab order; empty groups left out.
  List<UpcomingSection> get sections => [
    for (final group in UpcomingGroup.values)
      if (automations.where((a) => a.group == group).toList() case final items
          when items.isNotEmpty)
        UpcomingSection(group, items),
  ];

  AutomationBoard copyWith({
    List<Automation>? automations,
    Map<String, AutomationAction>? busy,
    String? Function()? error,
  }) => AutomationBoard(
    automations: automations ?? this.automations,
    schedulerStopped: schedulerStopped,
    busy: busy ?? this.busy,
    error: error == null ? this.error : error(),
  );
}

/// A scheduler heartbeat older than this means its ticker stopped.
const _schedulerStale = 300;

/// Hermes' cron jobs of [instanceId] for [profile] (the user's and the
/// heartbeat; Hermuse maintenance jobs are left out), with pause/resume,
/// run now and delete.
@riverpod
class Automations extends _$Automations {
  bool _refreshPending = false;

  @override
  Future<AutomationBoard> build(
    String instanceId, {
    String profile = 'default',
  }) async {
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    final body = await rest.getJson(hermesCronRoute);
    final rows = [
      for (final e in (body['data'] as List?) ?? const [])
        (e as Map).cast<String, Object?>(),
    ];
    return AutomationBoard(
      automations: sortAutomations([
        for (final row in rows)
          if (Automation.fromJson(row) case final job when !job.hidden) job,
      ]),
      schedulerStopped:
          rows.isNotEmpty &&
          !rows.any(
            (row) => switch (row['scheduler_heartbeat_age_s']) {
              final num age => age < _schedulerStale,
              _ => false,
            },
          ),
    );
  }

  /// Reloads jobs created or changed in chat, without interrupting a button
  /// action or clearing its busy state before the server responds.
  void refreshFromChat() {
    if (state.value?.busy.isNotEmpty ?? false) {
      _refreshPending = true;
    } else {
      ref.invalidateSelf();
    }
  }

  /// Runs [action] on [automation]; the board shows it busy meanwhile, then
  /// the job as Hermes returns it (or without it, once deleted). A refusal
  /// lands in [AutomationBoard.error].
  Future<void> perform(Automation automation, AutomationAction action) async {
    final current = state.value;
    if (current == null || current.busy.containsKey(automation.id)) return;
    if (!automation.actions.contains(action)) {
      throw StateError('${action.name} is not offered for ${automation.id}');
    }
    state = AsyncData(
      current.copyWith(
        busy: {...current.busy, automation.id: action},
        error: () => null,
      ),
    );
    final rest = await ref.read(
      restClientProvider(instanceId, profile: profile).future,
    );
    final path = '$hermesCronRoute/${Uri.encodeComponent(automation.id)}';
    Automation? updated;
    String? error;
    try {
      final Map<String, Object?> job;
      switch (action) {
        case AutomationAction.pause:
          job = await rest.postJson('$path/pause', {});
        case AutomationAction.resume:
          job = await rest.postJson('$path/resume', {});
        case AutomationAction.runNow:
          job = await rest.postJson('$path/trigger', {});
        case AutomationAction.delete:
          job = await rest.delete(path);
      }
      // A deleted job, or a one-shot that removed itself once run.
      if (action != AutomationAction.delete && job['state'] != 'completed') {
        updated = Automation.fromJson(job);
      }
    } on HermesException catch (e) {
      error = hermesReason(e);
    }
    final latest = state.value ?? current;
    final kept = [
      for (final a in latest.automations)
        if (a.id != automation.id) a else if (error != null) a else ?updated,
    ];
    state = AsyncData(
      latest.copyWith(
        automations: sortAutomations(kept),
        busy: {...latest.busy}..remove(automation.id),
        error: () => error,
      ),
    );
    if (_refreshPending && state.value!.busy.isEmpty) {
      _refreshPending = false;
      ref.invalidateSelf();
    }
  }
}

/// How one run of an automation went.
enum AutomationRunStatus { running, ok, failed }

/// One run of an automation: a Hermes run session (`cron_<job>_<time>`) and
/// an excerpt of what it answered.
final class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.startedAt,
    required this.status,
    this.endedAt,
    this.output = '',
  });

  /// Session row of `GET /api/cron/jobs/{id}/runs`: `{id, started_at,
  /// ended_at, end_reason, is_active, …}` (times in epoch seconds).
  factory AutomationRun.fromJson(
    Map<String, Object?> json, {
    String output = '',
  }) {
    final ended = _parseEpoch(json['ended_at']);
    return AutomationRun(
      id: '${json['id']}',
      startedAt:
          _parseEpoch(json['started_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: ended,
      status: json['is_active'] == true
          ? AutomationRunStatus.running
          : ended != null && json['end_reason'] == 'cron_complete'
          ? AutomationRunStatus.ok
          : AutomationRunStatus.failed,
      output: output,
    );
  }

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final AutomationRunStatus status;

  /// The start of what the run delivered ([runOutputLimit] characters at
  /// most): its final answer, without the line of narration a model may
  /// open it with; '' when it answered nothing readable.
  final String output;
}

/// Longest output excerpt an [AutomationRun] keeps.
const runOutputLimit = 280;

DateTime? _parseEpoch(Object? value) => switch (value) {
  final num seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch(
    (seconds * 1000).round(),
  ),
  final String text => DateTime.tryParse(text),
  _ => null,
};

/// The last few runs of the automation [jobId], newest first, each with
/// an excerpt of what it delivered (the run session's final answer; the
/// job's `last_output` for the newest run when its transcript says
/// nothing).
@riverpod
Future<List<AutomationRun>> automationRuns(
  Ref ref,
  String instanceId,
  String jobId, {
  String profile = 'default',
  int limit = 10,
}) async {
  final rest = await ref.watch(
    restClientProvider(instanceId, profile: profile).future,
  );
  final job = '$hermesCronRoute/${Uri.encodeComponent(jobId)}';
  final body = await rest.getJson('$job/runs', {'limit': '$limit'});
  final rows = [
    for (final e in (body['runs'] as List?) ?? const [])
      if (e is Map) e.cast<String, Object?>(),
  ];
  final outputs = await Future.wait([
    for (final row in rows) _runOutput(rest, '${row['id']}'),
  ]);
  if (outputs.isNotEmpty && outputs.first.isEmpty) {
    try {
      outputs[0] = _excerpt(
        '${(await rest.getJson(job))['last_output'] ?? ''}',
      );
    } on HermesException {
      // The job is gone or unreadable: the run keeps no excerpt.
    }
  }
  return [
    for (final (i, row) in rows.indexed)
      AutomationRun.fromJson(row, output: outputs[i]),
  ];
}

/// Excerpt of the final answer of the run session [sessionId] (its last
/// assistant message that calls no tool: earlier ones narrate the work);
/// '' when there is none or it cannot be read.
Future<String> _runOutput(HermesRestClient rest, String sessionId) async {
  try {
    final body = await rest.getJson(
      '/api/sessions/${Uri.encodeComponent(sessionId)}/messages',
      {'limit': '20', 'order': 'latest'},
    );
    final messages = [
      for (final m in (body['messages'] as List?) ?? const [])
        if (m is Map && m['role'] == 'assistant' && !_callsTools(m)) m,
    ];
    for (final m in messages.reversed) {
      final text = switch (m['display_content'] ?? m['content']) {
        final String text => text.trim(),
        _ => '',
      };
      if (text.isNotEmpty) return _excerpt(_deliverable(text));
    }
  } on HermesException {
    // Unreadable run: no excerpt.
  }
  return '';
}

/// Whether the stored assistant message [m] calls tools (`tool_calls`, a
/// list or its JSON text).
bool _callsTools(Map<Object?, Object?> m) => switch (m['tool_calls']) {
  final List<Object?> calls => calls.isNotEmpty,
  final String calls => calls.trim().isNotEmpty && calls.trim() != '[]',
  _ => false,
};

/// What a run's final answer [text] delivers: a model often opens it with
/// one paragraph about its work ("I have enough. Writing the briefing.")
/// before the deliverable's first heading; that lead is dropped, and
/// heading marks are not shown in the plain-text excerpt.
String _deliverable(String text) {
  final paragraphs = text.trim().split(_blankLines);
  final body = paragraphs.length > 1 && paragraphs[1].startsWith(_headingStart)
      ? paragraphs.skip(1).join('\n\n')
      : text.trim();
  return body.replaceAll(_heading, '');
}

final _blankLines = RegExp(r'\n\s*\n');
final _heading = RegExp(r'^#{1,6}\s+', multiLine: true);
final _headingStart = RegExp(r'#{1,6}\s');

String _excerpt(String text) {
  final trimmed = text.trim();
  return trimmed.length <= runOutputLimit
      ? trimmed
      : '${trimmed.substring(0, runOutputLimit - 1)}…';
}

/// Soonest next run first; paused or finished automations (no next run)
/// last, by name.
List<Automation> sortAutomations(Iterable<Automation> automations) =>
    automations.toList()..sort((a, b) {
      final an = a.paused ? null : a.nextRunAt;
      final bn = b.paused ? null : b.nextRunAt;
      if (an != null && bn != null) {
        final byTime = an.compareTo(bn);
        if (byTime != 0) return byTime;
      } else if (an != null) {
        return -1;
      } else if (bn != null) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

DateTime? _parseTime(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

const _dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// A Hermes schedule in words: `{kind: cron, expr: '0 8 * * *'}` →
/// "Every day at 8:00 AM", `{kind: interval, minutes: 90}` → "Every 90
/// minutes", `{kind: once, run_at}` → "Once, Oct 3 at 6:00 PM". A cron
/// expression too unusual to word is shown as is. Cron hours are the
/// server's time zone, as the agent wrote them.
String describeSchedule(Map<String, Object?> schedule) {
  final display = schedule['display'] as String? ?? '';
  switch (schedule['kind']) {
    case 'interval':
      final minutes = (schedule['minutes'] as num?)?.toInt();
      if (minutes == null || minutes <= 0) return display;
      return 'Every ${_duration(minutes)}';
    case 'once':
      final at = _parseTime(schedule['run_at']);
      if (at == null) return display;
      return 'Once, ${formatAutomationTime(at)}';
    case 'cron':
      final expr = schedule['expr'] as String? ?? display;
      return describeCron(expr) ?? 'Cron $expr';
  }
  return display;
}

/// "90 minutes", "2 hours", "day", "3 days".
String _duration(int minutes) {
  if (minutes % (24 * 60) == 0) {
    final days = minutes ~/ (24 * 60);
    return days == 1 ? 'day' : '$days days';
  }
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? 'hour' : '$hours hours';
  }
  return minutes == 1 ? 'minute' : '$minutes minutes';
}

/// Words for the common 5-field cron shapes, or null.
String? describeCron(String expr) {
  final f = expr.trim().split(RegExp(r'\s+'));
  if (f.length != 5) return null;
  final [minute, hour, dayOfMonth, month, dayOfWeek] = f;
  final m = int.tryParse(minute);
  if (month != '*') return null;

  // `*/N * * * *`, `M * * * *`, `M */N * * *`.
  if (dayOfMonth == '*' && dayOfWeek == '*') {
    if (hour == '*') {
      if (minute == '*') return 'Every minute';
      final step = _step(minute);
      if (step != null) return 'Every ${_duration(step)}';
      if (m != null && m < 60) {
        return m == 0 ? 'Every hour' : 'Every hour at :${_two(m)}';
      }
      return null;
    }
    final hourStep = _step(hour);
    if (hourStep != null && m != null) {
      final every = 'Every ${_duration(hourStep * 60)}';
      return m == 0 ? every : '$every at :${_two(m)}';
    }
  }

  final times = _times(minute, hour);
  if (times == null) return null;
  if (dayOfMonth == '*' && dayOfWeek == '*') return 'Every day at $times';
  if (dayOfMonth == '*') {
    final days = _weekdays(dayOfWeek);
    return days == null ? null : '$days at $times';
  }
  if (dayOfWeek == '*') {
    final day = int.tryParse(dayOfMonth);
    if (day == null || day < 1 || day > 31) return null;
    return 'Every month on the ${_ordinal(day)} at $times';
  }
  return null;
}

/// "8:00 AM", "8:00 AM and 6:00 PM" for `0` / `8,18`, or null.
String? _times(String minute, String hour) {
  final m = int.tryParse(minute);
  if (m == null || m > 59) return null;
  final hours = [for (final h in hour.split(',')) int.tryParse(h)];
  if (hours.isEmpty || hours.any((h) => h == null || h > 23)) return null;
  final words = [for (final h in hours) _clock(h!, m)];
  return words.length == 1
      ? words.single
      : '${words.sublist(0, words.length - 1).join(', ')} and ${words.last}';
}

/// "Every Monday", "Every weekday", "Every Monday and Friday", or null.
String? _weekdays(String field) {
  if (field == '1-5') return 'Every weekday';
  if (field == '0,6' || field == '6,0') return 'Every weekend day';
  final days = <int>[];
  for (final part in field.split(',')) {
    final range = part.split('-');
    final from = int.tryParse(range.first);
    final to = int.tryParse(range.last);
    if (from == null || to == null || from > 7 || to > 7 || from > to) {
      return null;
    }
    for (var d = from; d <= to; d++) {
      days.add(d % 7);
    }
  }
  final names = [for (final d in days) _dayNames[d]];
  if (names.length == 1) return 'Every ${names.single}';
  return 'Every ${names.sublist(0, names.length - 1).join(', ')} '
      'and ${names.last}';
}

int? _step(String field) {
  if (!field.startsWith('*/')) return null;
  final n = int.tryParse(field.substring(2));
  return n == null || n <= 0 ? null : n;
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "8:00 AM" (the chat's 12-hour clock).
String _clock(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${_two(minute)} ${hour < 12 ? 'AM' : 'PM'}';
}

/// A run time, local: "Today at 6:00 PM", "Tomorrow at 8:00 AM",
/// "Yesterday at 2:00 AM", "Mon at 9:00 AM" within a week either way, else
/// "Oct 3 at 9:00 AM". [now] defaults to the wall clock.
String formatAutomationTime(DateTime at, [DateTime? now]) {
  final local = at.toLocal();
  final today = _day(now ?? DateTime.now());
  final day = _day(local);
  final days = day.difference(today).inHours ~/ 24;
  final clock = _clock(local.hour, local.minute);
  final date = switch (days) {
    0 => 'Today',
    1 => 'Tomorrow',
    -1 => 'Yesterday',
    > 1 && < 7 || < -1 && > -7 => _dayNames[local.weekday % 7].substring(0, 3),
    _ => '${_monthNames[local.month - 1]} ${local.day}',
  };
  return '$date at $clock';
}

/// Local midnight of [at] (UTC-based so DST never shifts the day count).
DateTime _day(DateTime at) {
  final local = at.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}
