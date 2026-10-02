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
/// demo content: GETs return its feed, ideas, goals, library, reflections
/// and system files, and Hermes' cron jobs (`GET /api/cron/jobs`); every
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
    if (!cron && !path.startsWith(hermusePluginRoute)) {
      return _json(404, _notFound);
    }
    final route = cron ? '' : path.substring(hermusePluginRoute.length);
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
    if (cron) {
      return path == hermesCronRoute
          ? _json(200, {'data': _jobs(instance, loaded)})
          : _json(404, _notFound);
    }
    final body = _get(instance, route, loaded);
    return body == null ? _json(404, _notFound) : _json(200, body);
  });
}

/// Hermes' cron rows of [instance]: the plugin's jobs and the user's, last
/// run at their previous slot before [now] and next at the following one.
List<Map<String, Object?>> _jobs(DemoInstance instance, DateTime now) => [
  for (final job in [...demoHermuseJobs, ...?demoUserJobs[instance.id]])
    {
      'id': job.id,
      'name': job.name,
      'prompt': job.name,
      'schedule': {'kind': 'cron', 'expr': job.cron, 'display': job.cron},
      'schedule_display': job.cron,
      'enabled': true,
      'state': 'scheduled',
      'next_run_at': _next(job, now).toIso8601String(),
      'last_run_at': _next(
        job,
        now.subtract(Duration(days: job.weekday == null ? 1 : 7)),
      ).toIso8601String(),
      'last_status': 'ok',
      'last_error': null,
      'origin': job.hermuseKey == null
          ? null
          : {'source': 'hermuse', 'key': job.hermuseKey},
      'deliver': 'local',
      'profile': 'default',
      'scheduler_heartbeat_age_s': 5,
    },
];

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

Map<String, Object?>? _get(DemoInstance instance, String route, DateTime now) {
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
      return {'ideas': dated(instance.ideas)};
    case '/goals':
      return {'goals': dated(instance.goals)};
    case '/artifacts':
      return {'artifacts': dated(instance.artifacts)};
    case '/reflections':
      return {'reflections': dated(instance.reflections)};
  }
  const filesPrefix = '/files/';
  if (route.startsWith(filesPrefix)) {
    final name = Uri.decodeComponent(route.substring(filesPrefix.length));
    final content = instance.files[name];
    return content == null ? null : {'name': name, 'content': content};
  }
  return null;
}

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
