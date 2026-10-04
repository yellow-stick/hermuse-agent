import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/product/feed.dart';
import 'package:hermuse_app/product/goals.dart';
import 'package:hermuse_app/product/ideas.dart';
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

/// Pumps [child] with a memory DB and plugin REST answered by [routes]
/// (`'METHOD /path'`: a JSON body, or an [http.Response] as is); unknown
/// routes answer 404 like a missing plugin.
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
              return switch (route(request)) {
                final http.Response response => response,
                final body => http.Response(jsonEncode(body), 200),
              };
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

Map<String, Object?> _goal(
  String id,
  String title, {
  String source = 'user',
  String statusLine = '',
  String? parent,
}) => {
  'id': id,
  'title': title,
  'category': 'health',
  'why': '',
  'target_date': '',
  'status': 'tracking',
  'file': 'goals/$id.md',
  'created_at': '',
  'timeline': <Object?>[],
  'source': source,
  'status_line': statusLine,
  'done': false,
  'parent_id': parent,
};

Map<String, Object?> _post(String id, String title, {String why = ''}) => {
  'id': id,
  'title': title,
  'topic': '',
  'body': 'A **bold** start.',
  'sources': <String>[],
  'file': 'feed/$id.md',
  'created_at': '2026-09-27T14:05:00',
  'reactions': <String, String>{},
  'why': why,
};

Map<String, Object?> _idea(
  String id,
  String title, {
  String group = '',
  String firstStep = '',
}) => {
  'id': id,
  'title': title,
  'pitch': 'Pitch of $title',
  'group': group,
  'first_step': firstStep,
  'file': '',
  'created_at': '',
  'feedback': <Object?>[],
  'icon': 'travel',
};

const _files = 'GET /api/plugins/hermuse/files';

void main() {
  testWidgets('goals: agent goals under Tracking, subgoals nested, status '
      'lines shown', (tester) async {
    await _pump(tester, GoalsScreen(instance: _instance), {
      _files: (_) => {'files': []},
      'GET /api/plugins/hermuse/goals': (_) => {
        'goals': [
          _goal('g1', 'Run 10k', statusLine: '6k last Sunday'),
          _goal('g2', 'Oslo trip', source: 'agent'),
          _goal('g3', 'Run 5k first', parent: 'g1'),
        ],
      },
    });
    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text('Goals'), findsWidgets);
    expect(find.text('6k last Sunday'), findsOneWidget);
    // Tracking comes first, then the user's goal with its subgoal under it.
    final order = [
      for (final title in ['Oslo trip', 'Run 10k', 'Run 5k first'])
        tester.getTopLeft(find.text(title)),
    ];
    expect(order[0].dy, lessThan(order[1].dy));
    expect(order[1].dy, lessThan(order[2].dy));
    expect(order[2].dx, greaterThan(order[1].dx));
  });

  testWidgets('goals: Delete asks first; Cancel keeps the goal, Delete '
      'removes it and its subgoals', (tester) async {
    final calls = await _pump(tester, GoalsScreen(instance: _instance), {
      _files: (_) => {'files': []},
      'GET /api/plugins/hermuse/goals': (_) => {
        'goals': [
          _goal('g1', 'Run 10k'),
          _goal('g3', 'Run 5k first', parent: 'g1'),
        ],
      },
      'DELETE /api/plugins/hermuse/goals/g1': (_) => {'ok': true},
    });

    Future<void> openDelete() async {
      await tester.tap(find.bySemanticsLabel('More actions for Run 10k'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    await openDelete();
    expect(find.text('Delete this goal?'), findsOneWidget);
    expect(
      find.text(
        "This can't be undone. The goal and its history will be removed.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(YsButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this goal?'), findsNothing);
    expect(find.text('Run 10k'), findsOneWidget);
    expect(calls.where((c) => c.method == 'DELETE'), isEmpty);

    await openDelete();
    await tester.tap(find.widgetWithText(YsButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(
      [
        for (final c in calls)
          if (c.method == 'DELETE') c.url.path,
      ],
      ['/api/plugins/hermuse/goals/g1'],
    );
    expect(find.text('Delete this goal?'), findsNothing);
    expect(find.text('Run 10k'), findsNothing);
    expect(find.text('Run 5k first'), findsNothing);
  });

  testWidgets('goals: Add subgoal and Rename post the typed title', (
    tester,
  ) async {
    final calls = await _pump(tester, GoalsScreen(instance: _instance), {
      _files: (_) => {'files': []},
      'GET /api/plugins/hermuse/goals': (_) => {
        'goals': [_goal('g1', 'Run 10k')],
      },
      'POST /api/plugins/hermuse/goals': (_) =>
          _goal('g4', 'Buy shoes', parent: 'g1'),
      'PATCH /api/plugins/hermuse/goals/g1': (_) => _goal('g1', 'Run 21k'),
    });

    await tester.tap(find.bySemanticsLabel('More actions for Run 10k'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add subgoal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Buy shoes');
    await tester.pump();
    await tester.tap(find.widgetWithText(YsButton, 'Add'));
    await tester.pumpAndSettle();
    final create = calls.singleWhere((c) => c.method == 'POST');
    expect(jsonDecode(create.body), containsPair('parent_id', 'g1'));
    expect(jsonDecode(create.body), containsPair('title', 'Buy shoes'));
    expect(find.text('Add subgoal'), findsNothing);

    await tester.tap(find.bySemanticsLabel('More actions for Run 10k'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Run 10k'), findsWidgets); // Prefilled.
    await tester.enterText(find.byType(EditableText), 'Run 21k');
    await tester.pump();
    await tester.tap(find.widgetWithText(YsButton, 'Rename'));
    await tester.pumpAndSettle();
    final rename = calls.singleWhere((c) => c.method == 'PATCH');
    expect(jsonDecode(rename.body), {'title': 'Run 21k'});
    expect(find.text('Run 21k'), findsOneWidget);
  });

  testWidgets('feed: "Why I created this" shows the reason; absent without '
      'one; Delete removes the post', (tester) async {
    final calls = await _pump(
      tester,
      FeedScreen(instance: _instance, onDiscuss: (_) {}),
      {
        _files: (_) => {'files': []},
        'GET /api/plugins/hermuse/files/FEED_PROMPT.md': (_) => {
          'name': 'FEED_PROMPT.md',
          'content': 'Travel and fjords.',
        },
        'GET /api/plugins/hermuse/feed': (_) => {
          'posts': [
            _post('p1', 'Oslo in May', why: 'You asked about Norway.'),
            _post('p2', 'Old post'),
          ],
        },
        'DELETE /api/plugins/hermuse/feed/p2': (_) => {'ok': true},
      },
    );
    expect(find.text('YOUR FEED PROMPT'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('More actions for Oslo in May'));
    await tester.pumpAndSettle();
    expect(find.text('September 27, 2026 at 14:05'), findsOneWidget);
    await tester.tap(find.text('Why I created this'));
    await tester.pumpAndSettle();
    expect(find.text('You asked about Norway.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('You asked about Norway.'), findsNothing);

    await tester.tap(find.bySemanticsLabel('More actions for Old post'));
    await tester.pumpAndSettle();
    expect(find.text('Why I created this'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'DELETE').map((c) => c.url.path), [
      '/api/plugins/hermuse/feed/p2',
    ]);
    expect(find.text('Old post'), findsNothing);
    expect(find.text('Oslo in May'), findsOneWidget);
  });

  testWidgets('feed: Generate starts an edition; 409 says the schedule is '
      'off', (tester) async {
    var scheduled = true;
    await _pump(tester, FeedScreen(instance: _instance, onDiscuss: (_) {}), {
      _files: (_) => {'files': []},
      'GET /api/plugins/hermuse/files/FEED_PROMPT.md': (_) => {
        'name': 'FEED_PROMPT.md',
        'content': 'Travel.',
      },
      'GET /api/plugins/hermuse/feed': (_) => {'posts': <Object?>[]},
      'POST /api/plugins/hermuse/feed/generate': (_) => scheduled
          ? {'job_id': 'j1', 'started': true}
          : http.Response('{"detail":"feed job not registered"}', 409),
    });
    await tester.tap(find.widgetWithText(YsButton, 'Generate'));
    await tester.pumpAndSettle();
    expect(
      find.text('Generating… new posts appear in a few minutes'),
      findsOneWidget,
    );

    scheduled = false;
    await tester.tap(find.widgetWithText(YsButton, 'Generate'));
    await tester.pumpAndSettle();
    expect(find.text('Scheduled feed is off'), findsOneWidget);
  });

  testWidgets('ideas: grouped under their headings; Try it sends the first '
      'step; Dismiss removes the row', (tester) async {
    String? seed;
    final calls = await _pump(
      tester,
      IdeasScreen(instance: _instance, onStartInChat: (s) => seed = s),
      {
        _files: (_) => {'files': []},
        'GET /api/plugins/hermuse/ideas': (_) => {
          'ideas': [
            _idea('i1', 'Plan a weekend', group: 'Travel', firstStep: 'Go'),
            _idea('i2', 'Track spending', group: 'Money'),
            _idea('i3', 'Inbox zero'),
          ],
        },
        'POST /api/plugins/hermuse/ideas/i2/dismiss': (_) => {'ok': true},
      },
    );
    expect(
      find.text(
        "I'm always thinking about new ways to help. My favorites "
        'land here.',
      ),
      findsOneWidget,
    );
    for (final head in ['Featured', 'Travel', 'Money']) {
      expect(find.text(head), findsOneWidget);
    }
    expect(
      tester.getTopLeft(find.text('Featured')).dy,
      lessThan(tester.getTopLeft(find.text('Travel')).dy),
    );

    await tester.tap(find.bySemanticsLabel('Try it: Plan a weekend'));
    await tester.pumpAndSettle();
    expect(seed, 'Go');
    await tester.tap(find.bySemanticsLabel('Try it: Track spending'));
    await tester.pumpAndSettle();
    expect(seed, 'Track spending');

    await tester.tap(find.bySemanticsLabel('More actions for Track spending'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'POST').map((c) => c.url.path), [
      '/api/plugins/hermuse/ideas/i2/dismiss',
    ]);
    expect(find.text('Track spending'), findsNothing);
    expect(find.text('Money'), findsNothing);
  });
}
