import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/product/feed.dart';
import 'package:hermuse_app/product/goals.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

final _instance = HermesInstance(
  id: 'vps',
  label: 'VPS',
  kind: InstanceKind.remote,
  baseUrl: Uri.parse('https://vps.example'),
  auth: AuthMethod.password,
);

const _post = {
  'id': 'p1',
  'title': 'Oslo in May',
  'topic': 'travel',
  'body': 'Fjords are thawing.',
  'sources': <String>[],
  'file': 'feed/p1.md',
  'created_at': '2026-09-27',
  'reactions': <String, String>{},
};

/// Pumps [child] with a memory DB and plugin REST answered by [routes]
/// (`'METHOD /path'`); unknown routes answer 404 like a missing plugin.
Future<List<http.Request>> _pump(
  WidgetTester tester,
  Widget child,
  Map<String, Object? Function(http.Request)> routes,
) async {
  final db = openMemoryDatabase();
  addTearDown(db.close);
  await db.saveInstances([_instance], primaryId: 'vps');
  final fake = FakeHermesTransport();
  addTearDown(fake.close);
  final calls = <http.Request>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider('vps').overrideWith(
          (ref) => HermesRestClient(
            MockClient((request) async {
              calls.add(request);
              final route = routes['${request.method} ${request.url.path}'];
              if (route == null) {
                return http.Response('{"detail":"Not Found"}', 404);
              }
              return http.Response(jsonEncode(route(request)), 200);
            }),
            baseUrl: _instance.baseUrl,
          ),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData.fromView(tester.view),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: YsTheme(
            palette: YsPalette.dark,
            child: Overlay.wrap(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('missing plugin shows the enable instructions', (tester) async {
    await _pump(tester, FeedScreen(instance: _instance, onDiscuss: (_) {}), {});
    expect(find.text('Enable the Hermuse plugin'), findsOneWidget);
    expect(
      find.textContaining('hermes plugins enable hermuse'),
      findsOneWidget,
    );
  });

  testWidgets('feed: Love reacts; Discuss reacts then seeds a chat', (
    tester,
  ) async {
    String? seed;
    var post = Map<String, Object?>.of(_post);
    final calls = await _pump(
      tester,
      FeedScreen(instance: _instance, onDiscuss: (s) => seed = s),
      {
        'GET /api/plugins/hermuse/files': (_) => {'files': []},
        'GET /api/plugins/hermuse/files/FEED_PROMPT.md': (_) => {
          'name': 'FEED_PROMPT.md',
          'content': 'Travel and fjords.',
        },
        'GET /api/plugins/hermuse/feed': (_) => {
          'posts': [post],
        },
        'POST /api/plugins/hermuse/feed/p1/react': (request) {
          final reaction =
              (jsonDecode(request.body) as Map<String, Object?>)['reaction']
                  as String;
          post = {
            ...post,
            'reactions': {
              ...(post['reactions']! as Map<String, String>),
              reaction: 'now',
            },
          };
          return post;
        },
      },
    );
    expect(find.text('Travel and fjords.'), findsOneWidget);
    expect(find.text('Oslo in May'), findsOneWidget);

    await tester.tap(find.text('Love'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discuss'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final c in calls)
          if (c.method == 'POST') jsonDecode(c.body),
      ],
      [
        {'reaction': 'love'},
        {'reaction': 'discuss'},
      ],
    );
    expect(seed, "Let's discuss: Oslo in May\n\nFjords are thawing.");
  });

  testWidgets('goals: the box marks a tracked goal done', (tester) async {
    var goal = <String, Object?>{
      'id': 'g1',
      'title': 'Run 10k',
      'category': 'health',
      'why': 'Energy',
      'target_date': '',
      'status': 'tracking',
      'file': 'goals/g1.md',
      'created_at': '',
      'timeline': <Object?>[],
    };
    final calls = await _pump(tester, GoalsScreen(instance: _instance), {
      'GET /api/plugins/hermuse/files': (_) => {'files': []},
      'GET /api/plugins/hermuse/goals': (_) => {
        'goals': [goal],
      },
      'POST /api/plugins/hermuse/goals/g1/update': (request) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        goal = {...goal, 'status': body['status'] ?? goal['status']};
        return goal;
      },
    });
    expect(find.text('Run 10k'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Mark Run 10k complete'));
    await tester.pumpAndSettle();
    final update = calls.singleWhere((c) => c.method == 'POST');
    expect(jsonDecode(update.body), containsPair('status', 'done'));
    expect(find.text('Run 10k'), findsNothing);
  });
}
