import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'activity.g.dart';

/// Tools the agent finished on [instanceId], newest first, as kept on this
/// device across launches.
@riverpod
Stream<List<ActivityItem>> activity(Ref ref, String instanceId) => ref
    .watch(hermuseDatabaseProvider)
    .watchActivity(instanceId)
    .map(
      (rows) => [
        for (final row in rows)
          ActivityItem(
            tool: row.tool,
            summary: row.summary,
            at: DateTime.fromMillisecondsSinceEpoch(row.at),
            sessionId: row.sessionId,
          ),
      ],
    );

/// One day of the Activity tab: "Today", "Yesterday", "Monday" within a
/// week, else "Sep 26" (with the year when not this one).
final class ActivityDay {
  const ActivityDay(this.label, this.items);
  final String label;
  final List<ActivityItem> items;
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

/// [items] (newest first) grouped by local day, newest day first.
List<ActivityDay> activityDays(List<ActivityItem> items, DateTime now) {
  final today = _dayOf(now);
  final days = <ActivityDay>[];
  DateTime? current;
  for (final item in items) {
    final day = _dayOf(item.at);
    if (day != current) {
      current = day;
      days.add(ActivityDay(_label(day, today), []));
    }
    days.last.items.add(item);
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
