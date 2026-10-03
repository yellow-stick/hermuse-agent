import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart';
import 'product.dart' show hermesReason;

part 'automations.g.dart';

/// Hermes' cron API on the dashboard (`hermes_cli/web_routers/cron.py`).
const hermesCronRoute = '/api/cron/jobs';

/// Who created an automation: the Hermuse plugin (its feed, ideas, goals
/// and reflection jobs, `origin.source == 'hermuse'`) or the user, asking
/// their agent.
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

/// One Hermes cron job. Shape: `{id, name, schedule: {kind, expr?, minutes?,
/// run_at?, display}, enabled, state, next_run_at, last_run_at,
/// last_status, last_error, origin: {source, key}?}`.
final class Automation {
  const Automation({
    required this.id,
    required this.name,
    required this.schedule,
    required this.owner,
    required this.paused,
    this.nextRunAt,
    this.lastRunAt,
    this.lastOutcome,
    this.lastError = '',
  });

  factory Automation.fromJson(Map<String, Object?> json) {
    final origin = json['origin'];
    final state = json['state'] as String? ?? '';
    final lastStatus = json['last_status'] as String?;
    return Automation(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : json['id'] as String,
      schedule: describeSchedule(
        (json['schedule'] as Map?)?.cast<String, Object?>() ?? const {},
      ),
      owner: origin is Map && origin['source'] == 'hermuse'
          ? AutomationOwner.hermuse
          : AutomationOwner.user,
      paused: state == 'paused' || json['enabled'] == false,
      nextRunAt: _parseTime(json['next_run_at']),
      lastRunAt: _parseTime(json['last_run_at']),
      lastOutcome: switch (lastStatus) {
        null || '' => null,
        'ok' => AutomationOutcome.ok,
        'delivery_failed' => AutomationOutcome.deliveryFailed,
        _ => AutomationOutcome.failed,
      },
      lastError: json['last_error'] as String? ?? '',
    );
  }

  final String id;
  final String name;

  /// How often it runs, in words ("Every day at 8:00 AM").
  final String schedule;
  final AutomationOwner owner;
  final bool paused;

  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final AutomationOutcome? lastOutcome;
  final String lastError;

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

/// The Automations tab of one instance.
final class AutomationBoard {
  const AutomationBoard({
    required this.automations,
    this.schedulerStopped = false,
    this.busy = const {},
    this.error,
  });

  /// Sorted by next run ([sortAutomations]).
  final List<Automation> automations;

  /// No Hermes scheduler ticks for these jobs: they only run when started
  /// by hand until the Hermes gateway runs on the server.
  final bool schedulerStopped;

  /// Automations with an action in flight, and which.
  final Map<String, AutomationAction> busy;

  /// Why the last action failed, in the server's words.
  final String? error;

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

/// Hermes' cron jobs of [instanceId] (the Hermuse plugin's and the user's),
/// with pause/resume, run now and delete.
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
        for (final row in rows) Automation.fromJson(row),
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
