import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'onboarding.dart';
import 'product.dart';
import 'providers.dart';

part 'activity.g.dart';

/// How a recorded task ended.
enum TaskStatus { completed, failed, interrupted }

/// What started a task: a message in a chat, a scheduled job, the
/// heartbeat, or another surface.
enum TaskSource { chat, cron, heartbeat, other }

/// One task the agent ran on the server (one user request or one scheduled
/// run), titled and summarised by the Hermuse plugin: a row of the profile
/// panel's Activity tab. Shape (`GET /tasks`): `{id, session_id, turn_id,
/// title, summary, status, source, started_at, finished_at, tools[]}`.
final class Task {
  const Task({
    required this.id,
    required this.sessionId,
    required this.turnId,
    required this.title,
    required this.summary,
    required this.status,
    required this.source,
    required this.startedAt,
    required this.finishedAt,
    required this.tools,
  });

  factory Task.fromJson(Map<String, Object?> json) {
    final started =
        _time(json['started_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return Task(
      id: '${json['id'] ?? ''}',
      sessionId: json['session_id'] as String? ?? '',
      turnId: '${json['turn_id'] ?? ''}',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      status: switch (json['status']) {
        'failed' => TaskStatus.failed,
        'interrupted' => TaskStatus.interrupted,
        _ => TaskStatus.completed,
      },
      source: switch (json['source']) {
        'chat' => TaskSource.chat,
        'cron' => TaskSource.cron,
        'heartbeat' => TaskSource.heartbeat,
        _ => TaskSource.other,
      },
      startedAt: started,
      finishedAt: _time(json['finished_at']) ?? started,
      tools: [
        for (final tool in (json['tools'] as List?) ?? const [])
          if (tool is String && tool.isNotEmpty) tool,
      ],
    );
  }

  final String id;

  /// Session it ran in: the chat to open from the row.
  final String sessionId;
  final String turnId;

  /// "Set daily 8am briefing".
  final String title;

  /// One line of result: "Scheduled daily 8:00 AM Nantes briefing".
  final String summary;
  final TaskStatus status;
  final TaskSource source;
  final DateTime startedAt;
  final DateTime finishedAt;

  /// Hermes tools it used, in order (`web_search`, `terminal`, …).
  final List<String> tools;

  /// The row's icon: the kind of its first telling tool, else
  /// [ToolKind.other].
  ToolKind get kind => tools
      .map(toolKindOf)
      .firstWhere((k) => k != ToolKind.other, orElse: () => ToolKind.other);
}

DateTime? _time(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;

/// Plugin route of the recorded tasks.
const hermuseTasksRoute = '$hermusePluginRoute/tasks';

/// How long `sessions.changed` stays quiet before the tasks reload.
const _tasksDebounce = Duration(seconds: 2);

/// About how long the plugin takes to title and summarise a finished turn
/// (an auxiliary model call, off the agent's thread).
const taskSummaryDelay = Duration(seconds: 8);

/// Tasks the agent ran on [instanceId] for [profile], newest first, across
/// every surface (`GET /api/plugins/hermuse/tasks`). Reloads when a chat
/// turn ends ([turnEnded], from the chat) and when Hermes reports sessions
/// written elsewhere (`sessions.changed`: scheduled runs, other clients).
@riverpod
class Tasks extends _$Tasks {
  @override
  Future<List<Task>> build(
    String instanceId, {
    String profile = 'default',
  }) async {
    _followSessions();
    if (await ref.watch(pluginStatusProvider(instanceId).future) !=
        PluginPresence.installed) {
      throw StateError('the Hermuse plugin is not installed on this instance');
    }
    final rest = await ref.watch(
      restClientProvider(instanceId, profile: profile).future,
    );
    final body = await rest.getJson(hermuseTasksRoute, {'limit': '100'});
    return [
      for (final e in (body['tasks'] as List?) ?? const [])
        if (e is Map) Task.fromJson(e.cast<String, Object?>()),
    ];
  }

  /// Reloads the list (keeps showing the current one meanwhile).
  void refresh() => ref.invalidateSelf();

  /// A chat turn ended: its row exists once the plugin summarised it, so
  /// the list reloads now and once more after [taskSummaryDelay].
  void turnEnded() {
    refresh();
    Timer(taskSummaryDelay, () {
      if (ref.mounted) refresh();
    });
  }

  /// Debounced reload on the profile connection's `sessions.changed`.
  void _followSessions() {
    StreamSubscription<HermesEvent>? events;
    Timer? debounce;
    ref.onDispose(() {
      debounce?.cancel();
      unawaited(events?.cancel());
    });
    ref.listen(connectionProvider(instanceId, profile: profile), (_, next) {
      final connection = next.value;
      if (connection == null) return;
      unawaited(events?.cancel());
      events = connection.transport.events
          .where((e) => e is SessionsChangedEvent)
          .listen((_) {
            debounce?.cancel();
            debounce = Timer(_tasksDebounce, () {
              if (ref.mounted) ref.invalidateSelf();
            });
          });
    }, fireImmediately: true);
  }
}

/// One day of the Activity tab: "Today", "Yesterday", "Monday" within a
/// week, else "Sep 26" (with the year when not this one).
final class ActivityDay {
  const ActivityDay(this.label, this.items);
  final String label;
  final List<Task> items;
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// [tasks] (newest first) grouped by the local day they finished, newest
/// day first.
List<ActivityDay> activityDays(List<Task> tasks, DateTime now) {
  final today = _dayOf(now);
  final days = <ActivityDay>[];
  DateTime? current;
  for (final task in tasks) {
    final day = _dayOf(task.finishedAt);
    if (day != current) {
      current = day;
      days.add(ActivityDay(_label(day, today), []));
    }
    days.last.items.add(task);
  }
  return days;
}

String _label(DateTime day, DateTime today) {
  final ago = today.difference(day).inHours ~/ 24;
  if (ago == 0) return 'Today';
  if (ago == 1) return 'Yesterday';
  if (ago > 1 && ago < 7) return _weekdays[day.weekday - 1];
  final date = '${_months[day.month - 1]} ${day.day}';
  return day.year == today.year ? date : '$date, ${day.year}';
}

/// Local calendar day of [at], as a UTC date so DST never skews the count.
DateTime _dayOf(DateTime at) {
  final local = at.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}
