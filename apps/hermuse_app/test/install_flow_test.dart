import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/host/install_flow.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  testWidgets('should open the Command Line Tools installer on macOS, then '
      'go on once they are installed', (tester) async {
    const tools = '/Library/Developer/CommandLineTools';
    var installed = false;
    var requests = 0;
    final planRead = Completer<void>();
    final installer = HermesInstaller(
      hermesHome: '/h',
      installDir: '/h/hermes-agent',
      isWindows: false,
      isMacOS: true,
      source: const InstallerSource(
        isWindows: false,
        localScript: '/fake/install.sh',
      ),
      environment: const {'PATH': '/usr/bin'},
      // The /usr/bin/git stub is there with or without the tools.
      which: (name) async => '/usr/bin/$name',
      fileExists: (path) async =>
          path == '/fake/install.sh' ||
          (installed && path == '$tools/usr/bin/git'),
      runScript: (executable, args, {environment, onLine}) {
        if (executable == '/usr/bin/xcode-select') {
          if (args.contains('--install')) {
            requests++;
            return Future.value(ProcessResult(0, 0, '', ''));
          }
          return Future.value(
            installed
                ? ProcessResult(0, 0, '$tools\n', '')
                : ProcessResult(0, 2, '', 'no active developer directory'),
          );
        }
        // `--manifest`: the flow went past the prerequisites.
        if (!planRead.isCompleted) planRead.complete();
        return Completer<ProcessResult>().future;
      },
    );
    final host = LocalHermesHost.test(
      detector: HermesDetector(
        isWindows: false,
        environment: const {'HERMES_HOME': '/h'},
        homeDirectory: '/nowhere',
        fileExists: (_) async => false,
        runVersion: (_, _) async => ProcessResult(0, 1, '', ''),
        which: (_) async => null,
      ),
      secrets: MemorySecretStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: YsTheme(
              palette: YsPalette.dark,
              child: Overlay.wrap(
                child: InstallFlowScreen(
                  host: host,
                  detected: null,
                  installer: installer,
                  onDone: (_) {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Missing tools: ${HermesInstaller.commandLineTools}.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(YsButton, 'Install'));
    await tester.pump();

    expect(requests, 1);
    expect(
      find.text(
        'Finish the installation in the dialog that opened, then check again.',
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(YsButton, 'Install'), findsNothing);

    // Still missing: the flow stays on the prerequisites.
    await tester.tap(find.widgetWithText(YsButton, 'Check again'));
    await tester.pump();
    await tester.pump();
    expect(planRead.isCompleted, isFalse);

    installed = true;
    await tester.tap(find.widgetWithText(YsButton, 'Check again'));
    await tester.pump();
    await tester.pump();
    expect(planRead.isCompleted, isTrue);
    expect(find.text('Reading install plan…'), findsOneWidget);
  });

  group('after the install', () {
    setUpAll(_loadInter);

    testWidgets('should open the chat of the Hermes it starts, although '
        'registering it replaces the install screen', (tester) async {
      final db = openMemoryDatabase();
      addTearDown(db.close);
      final secrets = _KeychainLikeStore();
      const hermes = DetectedHermes(
        executable: '/nowhere/.local/bin/hermes',
        version: 'Hermes Agent v0.21.5 (2026.9.24)',
        home: '/nowhere/.hermes',
      );
      // Stands in for `hermes serve`: announces a port, then idles.
      final supervisor = HermesSupervisor(
        hermes: hermes,
        supervisorFactory: () => Supervisor(
          executable: '/bin/sh',
          arguments: const [
            '-c',
            'echo HERMES_BACKEND_READY port=1; exec sleep 60',
          ],
          environment: const {'HERMES_DASHBOARD_SESSION_TOKEN': 'token'},
          readiness: parseBackendReadyPort,
        ),
      );
      final host = LocalHermesHost.test(
        detector: HermesDetector(
          isWindows: false,
          environment: const {'HERMES_HOME': '/nowhere/.hermes'},
          homeDirectory: '/nowhere',
          fileExists: (path) async => path == hermes.executable,
          runVersion: (_, _) async =>
              ProcessResult(0, 0, '${hermes.version}\n', ''),
          which: (_) async => null,
        ),
        secrets: secrets,
        supervisor: supervisor,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermuseDatabaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(secrets),
            localHostProvider.overrideWithValue(host),
            bridgeHostProvider.overrideWithValue(host.bridgeHost),
            transportFactoryProvider.overrideWithValue(
              (_) async => throw const HermesUnreachable('test: no server'),
            ),
          ],
          child: const HermuseApp(),
        ),
      );
      await _settle(tester);
      await tester.tap(
        find.widgetWithText(YsButton, 'Install Hermes on this computer'),
      );
      await _settle(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HermuseApp)),
      );
      final opened = container.read(activeThreadProvider).value?.instanceId;
      final deadEnd = find.text('No conversation open').evaluate().isNotEmpty;
      // The stand-in backend was spawned from the test's fake zone: its exit
      // is only observed while pumping.
      var disposed = false;
      unawaited(supervisor.dispose().whenComplete(() => disposed = true));
      for (var i = 0; i < 100 && !disposed; i++) {
        await _settle(tester, rounds: 1);
      }
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);

      expect(opened, localInstanceId);
      expect(deadEnd, isFalse);
    });
  });
}

/// A platform keychain answers asynchronously: frames render meanwhile.
final class _KeychainLikeStore implements SecretStore {
  final _values = MemorySecretStore();

  @override
  Future<String?> read(String instanceId, String key) =>
      _values.read(instanceId, key);

  @override
  Future<void> write(String instanceId, String key, String value) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _values.write(instanceId, key, value);
  }

  @override
  Future<void> delete(String instanceId) => _values.delete(instanceId);
}

/// Pumps while real I/O (the stand-in backend, the database) completes.
Future<void> _settle(WidgetTester tester, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Loads Inter, the font the app ships: the test font's square glyphs would
/// overflow the Welcome buttons.
Future<void> _loadInter() async {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/packages/yellow_stick_ui/fonts')
      .existsSync()) {
    if (dir.parent.path == dir.path) throw StateError('no workspace fonts');
    dir = dir.parent;
  }
  final fonts = '${dir.path}/packages/yellow_stick_ui/fonts';
  final loader = FontLoader('packages/yellow_stick_ui/Inter');
  for (final name in const [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
  ]) {
    loader.addFont(
      File('$fonts/$name').readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
}
