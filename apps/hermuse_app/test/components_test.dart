import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_app/onboarding/components.dart';
import 'package:hermuse_app/shell/screens.dart';
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

/// A Hermes 0.21.5 dashboard answering like Hermes and the Hermuse plugin
/// do; the plugin routes answer once it is installed.
final class _Hermes {
  String? plugin;
  var mounted = false;
  var registered = 0;
  var failCron = false;
  var computer = <String, Object?>{
    'state': 'image_missing',
    'detail': 'hermuse-computer:0.2.0 is not here',
  };

  /// The plugin install waits for it, when set.
  Completer<void>? installing;

  http.Response _json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<http.Response> handle(http.Request request) async {
    const routes = '/api/plugins/hermuse';
    switch ('${request.method} ${request.url.path}') {
      case 'GET /api/status':
        return _json({'version': '0.21.5', 'auth_required': false});
      case 'GET /api/dashboard/plugins/hub':
        return _json({
          'plugins': [
            if (plugin case final version?)
              {
                'name': 'hermuse',
                'version': version,
                'runtime_status': 'enabled',
              },
          ],
        });
      case 'GET /api/config':
        return _json({'browser': <String, Object?>{}});
      case 'POST /api/dashboard/agent-plugins/hermuse/enable':
        return _json({
          'detail': "Plugin 'hermuse' is not installed or bundled.",
        }, 400);
      case 'POST /api/dashboard/agent-plugins/install':
        await installing?.future;
        plugin = hermusePluginVersion;
        mounted = true;
        return _json({'ok': true, 'restart_required': true});
      case final route when !mounted || !route.contains(routes):
        return _json({'detail': 'Not Found'}, 404);
      case 'GET $routes/files':
        return _json({'files': <String>[]});
      case 'GET $routes/cron':
        return _json({
          'jobs': [
            for (var i = 0; i < 4; i++)
              {'key': 'job$i', 'registered': i < registered, 'enabled': true},
          ],
        });
      case 'POST $routes/cron/enable':
        if (failCron) {
          return _json({'detail': 'cron backend unavailable: boom'}, 500);
        }
        registered = 4;
        return _json({'jobs': <Object>[]});
      case 'GET $routes/computer/status' || 'POST $routes/computer/setup':
        return _json(computer);
    }
    return _json({'detail': 'Not Found'}, 404);
  }
}

/// Shows the checklist of [hermes], rows unfolded at once (reduced motion),
/// once its first look is over.
Future<void> _pump(WidgetTester tester, _Hermes hermes) async {
  // Tall enough for every row and its buttons.
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = openMemoryDatabase();
  addTearDown(db.close);
  await db.saveInstances([_instance], primaryId: _instance.id);
  // No model provider yet.
  final fake = FakeHermesTransport()
    ..on(
      'setup.status',
      (_) => {
        'provider_configured': false,
        'ready': true,
        'free_tier': false,
        'other_providers': false,
        'inference_provider': '',
      },
    )
    ..on(
      'setup.runtime_check',
      (_) => {'ok': false, 'error': 'No Hermes provider is configured.'},
    )
    ..on('free_tier.status', (_) => throw const FakeRpcError(-32601, 'no'));
  addTearDown(fake.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider(_instance.id).overrideWith(
          (ref) => HermesRestClient(
            MockClient(hermes.handle),
            baseUrl: _instance.baseUrl,
          ),
        ),
      ],
      child: MediaQuery(
        data: MediaQueryData.fromView(tester.view)
            .copyWith(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: YsTheme(
            palette: YsPalette.dark,
            child: Overlay.wrap(
              child: ComponentsScreen(
                instance: _instance,
                onChat: () {},
                onSetUpModel: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rowOf(RemotePart part) => find.byKey(ValueKey<Object>(part));

YsStepState _state(WidgetTester tester, RemotePart part) => tester
    .widget<YsChecklist>(find.byType(YsChecklist))
    .items
    .singleWhere((item) => item.id == part)
    .state;

Finder _button(RemotePart part, String label) => find.descendant(
  of: _rowOf(part),
  matching: find.widgetWithText(YsButton, label),
);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<YsButton>(button).onPressed != null;

final _continue = find.widgetWithText(YsButton, 'Continue');

void main() {
  testWidgets('installing the plugin shows it working, then done, and frees '
      'the parts that wait for it', (tester) async {
    final hermes = _Hermes()..installing = Completer<void>();
    await _pump(tester, hermes);

    expect(_state(tester, RemotePart.plugin), YsStepState.needsAction);
    // The jobs wait for the plugin: their Install shows, disabled.
    expect(_state(tester, RemotePart.jobs), YsStepState.pending);
    expect(_enabled(tester, _button(RemotePart.jobs, 'Install')), isFalse);
    expect(
      find.widgetWithText(YsButton, 'Install everything missing'),
      findsNothing,
    );

    await tester.tap(_button(RemotePart.plugin, 'Install'));
    await tester.pump();
    await tester.pump();
    expect(_state(tester, RemotePart.plugin), YsStepState.working);
    expect(find.text('Hermuse plugin: Installing…'), findsOneWidget);
    // Nothing leaves the checklist while the install runs.
    expect(_enabled(tester, _continue), isFalse);

    hermes.installing!.complete();
    await tester.pumpAndSettle();
    expect(_state(tester, RemotePart.plugin), YsStepState.done);
    expect(_state(tester, RemotePart.jobs), YsStepState.needsAction);
    expect(_enabled(tester, _button(RemotePart.jobs, 'Install')), isTrue);
    // The jobs and the computer can go now, together.
    expect(
      find.widgetWithText(YsButton, 'Install everything missing'),
      findsOneWidget,
    );
    expect(_enabled(tester, _continue), isTrue);
  });

  testWidgets('a failed install says why and its Try again installs', (
    tester,
  ) async {
    final hermes = _Hermes()
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..failCron = true;
    await _pump(tester, hermes);

    await tester.tap(_button(RemotePart.jobs, 'Install'));
    await tester.pumpAndSettle();
    expect(_state(tester, RemotePart.jobs), YsStepState.failed);
    expect(
      find.descendant(
        of: _rowOf(RemotePart.jobs),
        matching: find.textContaining('cron backend unavailable'),
      ),
      findsOneWidget,
    );

    hermes.failCron = false;
    await tester.tap(_button(RemotePart.jobs, 'Try again'));
    await tester.pumpAndSettle();
    expect(_state(tester, RemotePart.jobs), YsStepState.done);
    expect(hermes.registered, 4);
  });

  testWidgets('Docker the server cannot install gives the command to run '
      'there; Check again sees it installed', (tester) async {
    const command = 'curl -fsSL https://get.docker.com | sudo sh';
    final hermes = _Hermes()
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..computer = {'state': 'docker_missing', 'detail': command};
    await _pump(tester, hermes);
    // The computer waits for Docker.
    expect(_enabled(tester, _button(RemotePart.computer, 'Install')), isFalse);

    await tester.tap(_button(RemotePart.docker, 'Install'));
    await tester.pumpAndSettle();
    expect(_state(tester, RemotePart.docker), YsStepState.needsAction);
    final box = find.descendant(
      of: _rowOf(RemotePart.docker),
      matching: find.byType(CommandBox),
    );
    expect(tester.widget<CommandBox>(box).command, command);

    // The user ran it on the server.
    hermes.computer = {
      'state': 'image_missing',
      'detail': 'hermuse-computer:0.2.0 is not here',
    };
    await tester.tap(_button(RemotePart.docker, 'Check again'));
    await tester.pumpAndSettle();
    expect(_state(tester, RemotePart.docker).settled, isTrue);
    expect(_enabled(tester, _button(RemotePart.computer, 'Install')), isTrue);
  });
}
