import 'dart:convert';
import 'dart:typed_data';

import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'computer_frames.dart';
import 'content.dart';
import 'transport.dart';

/// Fake computer of a demo instance: the plugin status it reports, the JPEG
/// frame per snapshot id (a browser tool call) and the fallback thumbnail.
final class DemoComputer {
  const DemoComputer({
    this.thumbnail = 'energy',
    this.snapshots = const {},
    this.tabs = const [],
  });

  /// Frame served as the live thumbnail.
  final String thumbnail;

  /// `snapshot(toolId)` answers, keyed by transcript tool-call index.
  final Map<int, String> snapshots;

  /// Chromium tabs the live stream reports.
  final List<Map<String, Object?>> tabs;
}

/// An HTTP client answering the Hermuse plugin routes of [instance] from the
/// demo content: GETs return its feed, ideas, goals, tasks, memory, library,
/// reflections and system files, Hermes' cron jobs (`GET /api/cron/jobs`,
/// `/{id}`, `/{id}/runs`) and the messages of their run sessions, an
/// unconfigured image service (`/media/config`, `/media/status`) and no
/// generated avatar (`/avatar`); every
/// write is refused with 405 [demoReadOnlyMessage] (not 401/403, which the
/// app reads as a sign-in problem).
http.Client demoPluginClient(
  DemoInstance instance, {
  DateTime? now,
  DemoComputer computer = const DemoComputer(),
}) {
  final loaded = now ?? DateTime.now();
  return MockClient((request) async {
    final path = request.url.path;
    final cron =
        path == hermesCronRoute || path.startsWith('$hermesCronRoute/');
    final session = path.startsWith(_sessionsRoute);
    if (!cron && !session && !path.startsWith(hermusePluginRoute)) {
      return _json(404, _notFound);
    }
    final route = cron || session
        ? ''
        : path.substring(hermusePluginRoute.length);
    // The fake computer: status + stills read like the plugin; the ticket
    // opens the replayed stream (see `demoComputerConnector`). Everything
    // else still refuses writes with 405.
    if (route == '/computer/status' && request.method == 'GET') {
      return _json(200, {
        'state': 'running',
        'detail': '',
        'control': 'agent',
        'mode': 'browser',
      });
    }
    if (route == '/computer/thumbnail' && request.method == 'GET') {
      return _bytes(demoComputerFrame(computer.thumbnail));
    }
    const snapshotsPrefix = '/computer/snapshots/';
    if (route.startsWith(snapshotsPrefix) && request.method == 'GET') {
      final frame = _snapshotFrame(instance, computer, route);
      return frame == null ? _json(404, _notFound) : _bytes(frame);
    }
    if (route == '/computer/ticket' && request.method == 'POST') {
      return _json(200, {'ticket': 'demo-ticket'});
    }
    if (request.method != 'GET') {
      return _json(405, {'detail': demoReadOnlyMessage});
    }
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '');
    if (cron) return _cron(instance, path, loaded, limit);
    if (session) return _sessionMessages(instance, path, loaded);
    final body = _get(instance, route, loaded, limit);
    return body == null ? _json(404, _notFound) : _json(200, body);
  });
}

const _sessionsRoute = '/api/sessions/';

/// Every cron job of [instance]: the plugin's and the user's.
List<DemoJob> _allJobs(DemoInstance instance) => [
  ...demoHermuseJobs,
  ...?demoUserJobs[instance.id],
];

/// `GET /api/cron/jobs`, `/{id}` and `/{id}/runs`.
http.Response _cron(
  DemoInstance instance,
  String path,
  DateTime now,
  int? limit,
) {
  if (path == hermesCronRoute) {
    return _json(200, {
      'data': [for (final job in _allJobs(instance)) _job(job, now)],
    });
  }
  final parts = path.substring(hermesCronRoute.length + 1).split('/');
  final id = Uri.decodeComponent(parts.first);
  final job = _allJobs(instance).where((j) => j.id == id).firstOrNull;
  if (job == null) return _json(404, _notFound);
  if (parts.length == 1) return _json(200, _job(job, now));
  if (parts.length != 2 || parts[1] != 'runs') return _json(404, _notFound);
  return _json(200, {
    'runs': [
      for (final (i, run) in job.runs.take(limit ?? 10).indexed)
        {
          'id': _runSession(job, i),
          'source': 'cron',
          'title': job.name,
          'started_at': _slot(job, now, i).millisecondsSinceEpoch / 1000,
          'ended_at': _slot(job, now, i).millisecondsSinceEpoch / 1000 + 90,
          'end_reason': run.ok ? 'cron_complete' : 'error',
          'is_active': false,
        },
    ],
  });
}

/// Hermes session id of [job]'s [index]-th latest run.
String _runSession(DemoJob job, int index) => 'cron_${job.id}_$index';

/// `GET /api/sessions/{id}/messages` of a cron run session: the job's
/// prompt and the run's answer.
http.Response _sessionMessages(
  DemoInstance instance,
  String path,
  DateTime now,
) {
  final parts = path.substring(_sessionsRoute.length).split('/');
  if (parts.length != 2 || parts[1] != 'messages') {
    return _json(404, _notFound);
  }
  final id = Uri.decodeComponent(parts.first);
  for (final job in _allJobs(instance)) {
    for (final (i, run) in job.runs.indexed) {
      if (_runSession(job, i) != id) continue;
      final at = _slot(job, now, i).millisecondsSinceEpoch / 1000;
      return _json(200, {
        'messages': [
          {'role': 'user', 'content': job.name, 'timestamp': at},
          {'role': 'assistant', 'content': run.output, 'timestamp': at + 90},
        ],
      });
    }
  }
  return _json(404, _notFound);
}

/// Hermes' cron row of [job]: last run at its previous slot before [now]
/// (none for a one-shot), next at the following one.
Map<String, Object?> _job(DemoJob job, DateTime now) {
  final next = _nextRun(job, now);
  final last = job.onceInDays == null ? job.runs.firstOrNull : null;
  final ran = job.onceInDays == null;
  final Map<String, Object?> schedule;
  if (job.everyMinutes case final minutes?) {
    schedule = {
      'kind': 'interval',
      'minutes': minutes,
      'display': 'every ${minutes}m',
    };
  } else if (job.onceInDays != null) {
    schedule = {
      'kind': 'once',
      'run_at': next.toIso8601String(),
      'display': 'once at ${next.toIso8601String()}',
    };
  } else {
    schedule = {'kind': 'cron', 'expr': job.cron, 'display': job.cron};
  }
  final failed = last != null && !last.ok;
  return {
    'id': job.id,
    'name': job.name,
    'prompt': job.name,
    'schedule': schedule,
    'schedule_display': schedule['display'],
    'enabled': true,
    'state': 'scheduled',
    'next_run_at': next.toIso8601String(),
    'last_run_at': ran ? _slot(job, now, 0).toIso8601String() : null,
    'last_status': ran ? (failed ? 'error' : 'ok') : null,
    'last_error': failed ? last.output : null,
    'last_output': last != null && last.ok ? last.output : null,
    'origin': job.hermuseKey == null
        ? null
        : {'source': 'hermuse', 'key': job.hermuseKey},
    'deliver': 'local',
    'profile': 'default',
    'scheduler_heartbeat_age_s': 5,
  };
}

/// When [job] runs next after [now].
DateTime _nextRun(DemoJob job, DateTime now) {
  final local = now.toLocal();
  if (job.onceInDays case final days?) {
    return DateTime(local.year, local.month, local.day + days, job.hour);
  }
  if (job.everyMinutes case final minutes?) {
    return _slot(job, now, 0).add(Duration(minutes: minutes));
  }
  return _next(job, now);
}

/// Start of [job]'s [index]-th latest run before [now]: interval jobs last
/// ran a third of their interval ago; scheduled ones at their slots.
DateTime _slot(DemoJob job, DateTime now, int index) {
  if (job.everyMinutes case final minutes?) {
    final last = now.toLocal().subtract(Duration(minutes: minutes ~/ 3));
    return last.subtract(Duration(minutes: minutes * index));
  }
  final next = _next(job, now);
  final days = (job.weekday == null ? 1 : 7) * (index + 1);
  return DateTime(next.year, next.month, next.day - days, next.hour);
}

/// The first slot of [job] after [after] (local time).
DateTime _next(DemoJob job, DateTime after) {
  final local = after.toLocal();
  var at = DateTime(local.year, local.month, local.day, job.hour);
  while (!at.isAfter(local) ||
      (job.weekday != null && at.weekday != job.weekday)) {
    at = DateTime(at.year, at.month, at.day + 1, job.hour);
  }
  return at;
}

const _notFound = {'detail': 'Not Found'};

Map<String, Object?>? _get(
  DemoInstance instance,
  String route,
  DateTime now,
  int? limit,
) {
  List<Map<String, Object?>> dated(List<Map<String, Object?>> rows) => [
    for (final row in rows) _dated(row, now),
  ];
  switch (route) {
    case '/files':
      return {'files': hermuseManagedFiles};
    case '/preferences':
      return {
        'name': preferencesFileName,
        'content': instance.files[preferencesFileName] ?? '',
      };
    case '/feed':
      return {'posts': dated(instance.feed)};
    case '/ideas':
      return {
        'ideas': [
          ...dated(instance.ideas),
          for (final seed in demoSeedIdeas)
            {
              ...seed,
              'seeded': true,
              'file': null,
              'created_at': null,
              'feedback': <Object?>[],
            },
        ],
      };
    case '/tasks':
      return {
        'tasks': [
          for (final task in instance.tasks.take(limit ?? 50)) _task(task, now),
        ],
      };
    case '/memory/memory':
      return _memory('memory', instance.memory, now);
    case '/memory/user':
      return _memory('user', instance.userMemory, now);
    case '/goals':
      return {'goals': dated(instance.goals)};
    case '/artifacts':
      return {'artifacts': dated(instance.artifacts)};
    case '/reflections':
      return {'reflections': dated(instance.reflections)};
    // No image service in the demo: the agent editor's Generate view and
    // Settings → Image generation show their not-configured state.
    case '/media/config':
      return {
        'provider': 'contentflow',
        'endpoint': '',
        'has_token': false,
        'image_model': '',
        'video_model': '',
        'feed_fallback': false,
        'from_env': false,
      };
    case '/media/status':
      return {
        'configured': false,
        'reachable': false,
        'credits': null,
        'video_cost': null,
        'error': null,
      };
    case '/avatar':
      return {
        'portrait_url': null,
        'states': <String, Object?>{},
        'job': null,
        'updated_at': null,
      };
  }
  const filesPrefix = '/files/';
  if (route.startsWith(filesPrefix)) {
    final name = Uri.decodeComponent(route.substring(filesPrefix.length));
    final content = instance.files[name];
    return content == null ? null : {'name': name, 'content': content};
  }
  return null;
}

/// A recorded task with its `age`/`took` turned into `started_at` and
/// `finished_at`.
Map<String, Object?> _task(Map<String, Object?> task, DateTime now) {
  final finished = now.subtract(task['age']! as Duration);
  final started = finished.subtract(task['took']! as Duration);
  return {
    for (final MapEntry(:key, :value) in task.entries)
      if (key != 'age' && key != 'took') key: value,
    'started_at': started.toIso8601String(),
    'finished_at': finished.toIso8601String(),
  };
}

/// A memory file as the plugin returns it, last written this morning.
Map<String, Object?> _memory(
  String target,
  List<String> entries,
  DateTime now,
) => {
  'target': target,
  'entries': entries,
  'updated_at': now.subtract(const Duration(hours: 3)).toIso8601String(),
};

/// [row] with its `age` turned into the plugin's time fields, nested
/// timeline/feedback entries included.
Map<String, Object?> _dated(Map<String, Object?> row, DateTime now) {
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in row.entries) {
    switch ((key, value)) {
      case ('age', final Duration age):
        final at = now.subtract(age);
        out['created_at'] = _stamp(at);
        out['written_at'] = _stamp(at);
        out['at'] = _stamp(at);
        out['date'] = _stamp(at).substring(0, 10);
      case (_, final List<Object?> list):
        out[key] = [
          for (final item in list)
            item is Map<String, Object?> ? _dated(item, now) : item,
        ];
      default:
        out[key] = value;
    }
  }
  return out;
}

/// `YYYY-MM-DD HH:MM`, local time.
String _stamp(DateTime at) {
  String two(int n) => n.toString().padLeft(2, '0');
  final local = at.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

http.Response _json(int status, Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _bytes(Uint8List body) =>
    http.Response.bytes(body, 200, headers: {'content-type': 'image/jpeg'});

/// Frame for a snapshot request: the mapped frame of the transcript tool
/// call the id points at. The Annecy booking steps always show the stay
/// page; electricity steps use the per-index map, else the thumbnail.
Uint8List? _snapshotFrame(
  DemoInstance instance,
  DemoComputer computer,
  String route,
) {
  const prefix = '/computer/snapshots/';
  final id = Uri.decodeComponent(route.substring(prefix.length));
  for (final chat in instance.chats) {
    for (final (i, row) in chat.rows.indexed) {
      if (row.role == 'tool' && '${chat.id}-tool-$i' == id) {
        if (chat.title == 'Weekend in Annecy') {
          return demoComputerFrame('annecy');
        }
        final frame = computer.snapshots[i];
        if (frame != null) return demoComputerFrame(frame);
        return demoComputerFrame(computer.thumbnail);
      }
    }
  }
  return null;
}
