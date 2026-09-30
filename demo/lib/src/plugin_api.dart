import 'dart:convert';

import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'content.dart';
import 'transport.dart';

/// An HTTP client answering the Hermuse plugin routes of [instance] from the
/// demo content: GETs return its feed, ideas, goals, library, reflections
/// and system files; every write is refused with 405 [demoReadOnlyMessage]
/// (not 401/403, which the app reads as a sign-in problem).
http.Client demoPluginClient(DemoInstance instance, {DateTime? now}) {
  final loaded = now ?? DateTime.now();
  return MockClient((request) async {
    final path = request.url.path;
    if (!path.startsWith(hermusePluginRoute)) return _json(404, _notFound);
    if (request.method != 'GET') {
      return _json(405, {'detail': demoReadOnlyMessage});
    }
    final body = _get(
      instance,
      path.substring(hermusePluginRoute.length),
      loaded,
    );
    return body == null ? _json(404, _notFound) : _json(200, body);
  });
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
