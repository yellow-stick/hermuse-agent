import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/host/install_flow.dart';
import 'package:hermuse_app/host/linux_setup.dart';
import 'package:hermuse_app/host/linux_setup_gate.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_app/shell/app.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LinuxSetupController', () {
    late Directory root;
    late _Setup setup;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermuse_linux_setup');
      setup = _Setup(root.path);
    });

    tearDown(() async {
      await setup.dispose();
      await root.delete(recursive: true);
    });

    for (final (outcome, step) in [
      (LinuxApplyOutcome.dismissed, LinuxStepOutcome.dismissed),
      (LinuxApplyOutcome.denied, LinuxStepOutcome.denied),
    ]) {
      test(
        'should stay incomplete when the authorization is ${outcome.name}',
        () async {
          setup.inspections.add(_inspection(missingTools: ['ripgrep']));
          setup.apply = _refused(outcome, step);
          setup.detect = () async => _compatible(setup.script.hermesHome);
          final container = setup.container();
          final controller = container.read(linuxSetupProvider.notifier);

          await controller.prepare(LinuxSetupGoal.local);
          expect(
            container.read(linuxSetupProvider).phase,
            isA<SetupReview>().having((r) => r.steps, 'steps', isNotEmpty),
          );
          await controller.authorize();

          expect(
            container.read(linuxSetupProvider).phase,
            isA<SetupReview>()
                .having((r) => r.lastRun?.outcome, 'last run', outcome)
                .having((r) => r.lastRun?.completed, 'completed', isEmpty)
                // Prepare stays offered for the same steps.
                .having((r) => r.steps, 'steps', isNotEmpty),
          );
          expect(setup.backendStarts, isEmpty);
          expect(
            (await container.read(registryProvider.future)).instances,
            isEmpty,
          );
        },
      );
    }

    test('should store nothing while the keyring stays locked, then go on '
        'once it is unlocked', () async {
      setup.inspections.add(_inspection(locked: true));
      setup.detect = () async => _compatible(setup.script.hermesHome);
      setup.serveComputer();
      final keyring = _Keyring();
      final container = setup.container(secrets: keyring);
      final controller = container.read(linuxSetupProvider.notifier);

      await controller.prepare(LinuxSetupGoal.local);

      expect(
        container.read(linuxSetupProvider),
        isA<LinuxSetupState>()
            .having((s) => s.keystoreVerified, 'verified', isFalse)
            .having(
              (s) => s.phase,
              'phase',
              isA<SetupReview>().having(
                (r) => r.keyring?.locked,
                'locked',
                isTrue,
              ),
            ),
      );
      expect(setup.backendStarts, isEmpty);
      expect(keyring.values, isEmpty);

      keyring.locked = false;
      await controller.checkAgain();

      expect(container.read(linuxSetupProvider).phase, isA<SetupFinished>());
      expect(setup.backendStarts, hasLength(1));
      // The probe secret did not outlive the check.
      expect(keyring.values, isEmpty);
    });

    test('should resume an unfinished install without rerunning its '
        'completed stages', () async {
      final script = setup.script;
      await InstallJournal(
        hermesHome: script.hermesHome,
        installDir: script.installDir,
        runtimeHome: ManagedRuntime(script.hermesHome).home,
        commit: hermesReleaseCommit,
        startedAt: DateTime.utc(2026, 9, 29),
        completedStages: const ['prerequisites', 'repository', 'venv'],
        currentStage: 'python-deps',
      ).write(script.journalPath);
      await script.checkout();
      setup.inspections.add(_inspection());
      setup.serveComputer();
      final container = setup.container();

      await container.read(linuxSetupProvider.notifier).start();

      expect(script.stagesRun, [
        'python-deps',
        'node-deps',
        'path',
        'config',
        'complete',
      ]);
      expect((await InstallJournal.read(script.journalPath))!.finished, isTrue);
      expect(
        container.read(linuxSetupProvider),
        isA<LinuxSetupState>()
            .having((s) => s.phase, 'phase', isA<SetupFinished>())
            // Installed by this session, not found in place.
            .having(
              (s) => s.parts[SetupPart.hermes],
              'Hermes Agent',
              SetupPartReadiness.prepared,
            ),
      );
      expect(setup.backendStarts.single.executable, script.launcher);
    });

    test(
      'should tell the parts found in place from those it prepared',
      () async {
        setup.inspections.add(_inspection(missingTools: ['ripgrep']));
        setup.detect = () async => _compatible(setup.script.hermesHome);
        setup.serveComputer();
        final container = setup.container();
        final controller = container.read(linuxSetupProvider.notifier);

        await controller.prepare(LinuxSetupGoal.local);
        await controller.authorize();

        expect(
          container.read(linuxSetupProvider),
          isA<LinuxSetupState>()
              .having((s) => s.phase, 'phase', isA<SetupFinished>())
              .having((s) => s.parts, 'parts', {
                SetupPart.systemPackages: SetupPartReadiness.prepared,
                SetupPart.keyring: SetupPartReadiness.found,
                SetupPart.docker: SetupPartReadiness.found,
                SetupPart.hermes: SetupPartReadiness.found,
                SetupPart.plugin: SetupPartReadiness.prepared,
                SetupPart.bridge: SetupPartReadiness.found,
                SetupPart.computer: SetupPartReadiness.found,
              })
              .having((s) => s.hermesVersion, 'Hermes version', '0.21.5'),
        );
      },
    );

    test('should keep an incompatible Hermes as it is', () async {
      setup.inspections.add(_inspection());
      setup.detect = () async => DetectedHermes(
        executable: '${root.path}/home/.local/bin/hermes',
        version: 'Hermes Agent v0.20.0',
        home: setup.script.hermesHome,
      );
      final container = setup.container();

      await container
          .read(linuxSetupProvider.notifier)
          .prepare(LinuxSetupGoal.local);

      expect(container.read(linuxSetupProvider).phase, isA<SetupHermesKept>());
      expect(setup.script.manifestReads, 0);
      expect(setup.script.stagesRun, isEmpty);
      expect(File(setup.script.journalPath).existsSync(), isFalse);
      expect(setup.backendStarts, isEmpty);
      expect(setup.pluginInstalls, 0);
    });

    test('should go back to the system review when the computer asks for '
        'the desktop Docker setup', () async {
      setup.inspections
        ..add(_inspection())
        ..add(_inspection(docker: false));
      setup.detect = () async => _compatible(setup.script.hermesHome);
      setup.rest['POST /api/plugins/hermuse/computer/setup'] = (_) => {
        'state': 'docker_missing',
        'detail': 'Open the Hermuse Agent setup to install Docker.',
        'hint': 'desktop_setup',
      };
      final container = setup.container();

      await container
          .read(linuxSetupProvider.notifier)
          .prepare(LinuxSetupGoal.local);

      expect(
        container.read(linuxSetupProvider).phase,
        isA<SetupReview>().having(
          (r) => r.steps.map((s) => s.step),
          'steps',
          containsAll([
            LinuxDependencyStep.dockerInstall,
            LinuxDependencyStep.dockerGroup,
          ]),
        ),
      );
      expect(setup.doctors, 0);
    });

    test('should wait for a running privileged step on stop and start no '
        'other', () async {
      setup.inspections.add(_inspection(missingTools: ['ripgrep']));
      setup.detect = () async => _compatible(setup.script.hermesHome);
      final release = Completer<void>();
      LinuxApplyCancellation? passed;
      setup.apply = (plan, {cancellation}) async* {
        passed = cancellation;
        yield const LinuxDependencyStarted(LinuxDependencyStep.hermesTools);
        await release.future;
        yield const LinuxDependencyFinished(
          LinuxDependencyStep.hermesTools,
          LinuxStepOutcome.done,
        );
        final after = _inspection();
        yield LinuxDependencyResult(
          cancellation!.isCancelled
              ? LinuxApplyOutcome.cancelled
              : LinuxApplyOutcome.ready,
          after,
          LinuxDependencyPlan.compute(after, plan.targets),
        );
      };
      final container = setup.container();
      final controller = container.read(linuxSetupProvider.notifier);
      await controller.prepare(LinuxSetupGoal.local);
      unawaited(controller.authorize());
      await pumpEventQueue();

      var stopped = false;
      unawaited(controller.stopAndWait().then((_) => stopped = true));
      await pumpEventQueue();
      expect(passed?.isCancelled, isTrue);
      expect(stopped, isFalse, reason: 'the running step is never cut');

      release.complete();
      await pumpEventQueue();
      expect(stopped, isTrue);
      expect(
        container.read(linuxSetupProvider).phase,
        isNot(isA<SetupFinished>()),
      );
      expect(setup.backendStarts, isEmpty);
    });
  });

  group('LinuxSetupGate', () {
    // The test font's square glyphs would overflow the Welcome buttons.
    setUpAll(_loadInter);

    testWidgets('should connect no instance until the locked keyring opens', (
      tester,
    ) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('hermuse_linux_gate'),
      ))!;
      addTearDown(() => root.deleteSync(recursive: true));
      final setup = _Setup(root.path);
      addTearDown(() => tester.runAsync(setup.dispose));
      await setup.db.saveInstances([
        HermesInstance(
          id: 'vps',
          label: 'VPS',
          kind: InstanceKind.remote,
          baseUrl: Uri.parse('https://vps.example'),
          auth: AuthMethod.password,
        ),
      ], primaryId: 'vps');
      setup.inspections.add(_inspection(locked: true));
      final keyring = _Keyring();
      var connections = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...setup.overrides(secrets: keyring),
            transportFactoryProvider.overrideWithValue((_) async {
              connections++;
              throw const HermesUnreachable('test: no server');
            }),
          ],
          child: const HermuseApp(),
        ),
      );
      await _settle(tester);

      expect(find.byType(LinuxSetupGate), findsOneWidget);
      expect(find.widgetWithText(YsButton, 'Check again'), findsOneWidget);
      expect(connections, 0);
      expect(keyring.values, isEmpty);

      keyring.locked = false;
      await tester.tap(find.widgetWithText(YsButton, 'Check again'));
      await _settle(tester);

      expect(find.byType(LinuxSetupGate), findsNothing);
      expect(connections, greaterThan(0));
    });

    testWidgets('should leave other platforms on their own install flow', (
      tester,
    ) async {
      final db = openMemoryDatabase();
      addTearDown(db.close);
      final secrets = MemorySecretStore();
      final host = LocalHermesHost.test(
        detector: HermesDetector(
          isWindows: false,
          environment: const {'HERMES_HOME': '/nowhere/.hermes'},
          homeDirectory: '/nowhere',
          fileExists: (_) async => false,
          runVersion: (_, _) async => ProcessResult(0, 1, '', ''),
          which: (_) async => null,
        ),
        secrets: secrets,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hermuseDatabaseProvider.overrideWithValue(db),
            secretStoreProvider.overrideWithValue(secrets),
            ...localHostOverrides(host),
          ],
          child: const HermuseApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(YsChoiceCard, 'Install Hermes on this computer'),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(InstallFlowScreen), findsOneWidget);
      expect(find.byType(LinuxSetupGate), findsNothing);
    });

    testWidgets('should show a part found in place as checked, never as '
        'being installed', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(linuxSetupProvider.notifier);
      Future<YsStepState> hermesRow(
        SetupPhase phase,
        SetupPartReadiness readiness,
      ) async {
        await tester.pumpWidget(
          _screen(
            LinuxSetupView(
              setup: LinuxSetupState(
                goal: LinuxSetupGoal.local,
                phase: phase,
                parts: {SetupPart.hermes: readiness},
                hermesVersion: '0.21.5',
              ),
              controller: controller,
              canLeave: true,
            ),
            reduceMotion: true,
          ),
        );
        return tester
            .widget<YsChecklist>(find.byType(YsChecklist))
            .items
            .singleWhere((item) => item.id == SetupPart.hermes)
            .state;
      }

      const starting = SetupWorking(SetupActivity.startingHermes);
      expect(
        await hermesRow(starting, SetupPartReadiness.found),
        YsStepState.checking,
      );
      expect(
        await hermesRow(starting, SetupPartReadiness.prepared),
        YsStepState.working,
      );
      // Ready: a calm check for the one found, the drawn tick for the one
      // installed now.
      expect(
        await hermesRow(const SetupFinished(), SetupPartReadiness.found),
        YsStepState.found,
      );
      expect(
        await hermesRow(const SetupFinished(), SetupPartReadiness.prepared),
        YsStepState.done,
      );
    });

    testWidgets('should retry a failed install stage from its row, then go '
        'on with the next ones', (tester) async {
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('hermuse_linux_retry'),
      ))!;
      addTearDown(() => root.deleteSync(recursive: true));
      final setup = _Setup(root.path);
      addTearDown(() => tester.runAsync(setup.dispose));
      setup.inspections.add(_inspection());
      setup.serveComputer();
      setup.script.failing.add('python-deps');
      final container = setup.container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          // Rows unfold at once: the tap lands on the button they show.
          child: _screen(
            const LinuxSetupGate(canLeave: true),
            reduceMotion: true,
          ),
        ),
      );

      unawaited(
        container
            .read(linuxSetupProvider.notifier)
            .prepare(LinuxSetupGoal.local),
      );
      await _settle(
        tester,
        until: () =>
            container.read(linuxSetupProvider).phase is SetupInstallFailed,
      );
      final retry = find.descendant(
        // Rows are keyed by their item id, an Object.
        of: find.byKey(const ValueKey<Object>(SetupPart.hermes)),
        matching: find.widgetWithText(YsButton, 'Retry this stage'),
      );
      expect(retry, findsOneWidget);
      // The failed run releases the install lock (real I/O) before a new
      // operation may start.
      await _settle(tester);

      await tester.tap(retry);
      await _settle(
        tester,
        until: () => setup.script.stagesRun.contains('node-deps'),
      );

      expect(
        setup.script.stagesRun.where((stage) => stage == 'python-deps'),
        hasLength(2),
      );
      expect(
        container.read(linuxSetupProvider).phase,
        isNot(isA<SetupInstallFailed>()),
      );
    });

    for (final reduceMotion in [false, true]) {
      testWidgets(
        reduceMotion
            ? 'should go on at once once ready when motion is reduced'
            : 'should hold its ready moment, then go on',
        (tester) async {
          final root = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('hermuse_linux_ready'),
          ))!;
          addTearDown(() => root.deleteSync(recursive: true));
          final setup = _Setup(root.path);
          addTearDown(() => tester.runAsync(setup.dispose));
          setup.inspections.add(_inspection());
          setup.detect = () async => _compatible(setup.script.hermesHome);
          setup.serveComputer();
          final container = setup.container();
          await tester.runAsync(
            () => container
                .read(linuxSetupProvider.notifier)
                .prepare(LinuxSetupGoal.local),
          );
          expect(container.read(linuxSetupProvider).showsReady, isTrue);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: _screen(
                const LinuxSetupGate(canLeave: true),
                reduceMotion: reduceMotion,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 16));

          expect(
            container.read(linuxSetupProvider).phase,
            reduceMotion ? isA<SetupIdle>() : isA<SetupFinished>(),
          );
          await tester.pump(const Duration(seconds: 2));
          await tester.pump();
          expect(container.read(linuxSetupProvider).phase, isA<SetupIdle>());
        },
      );
    }
  });
}

/// Pumps while real I/O (journal, lock file) completes; with [until], until
/// it holds and shows (at most 200 rounds).
Future<void> _settle(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < (until == null ? 20 : 200); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until != null && until()) break;
  }
  await tester.pump();
  if (until != null) expect(until(), isTrue, reason: 'never settled');
}

/// [child] as the app shows it, with [reduceMotion] as the system asks.
Widget _screen(Widget child, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(800, 1400),
    disableAnimations: reduceMotion,
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: YsTheme(palette: YsPalette.dark, child: child),
  ),
);

/// Loads Inter, the font the app ships, from the workspace.
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

const _rootful = 'unix:///var/run/docker.sock';

/// A supported Ubuntu with a running keyring ([locked] when it is locked),
/// the Hermes build tools except [missingTools], and a usable rootful Docker
/// — or none at all without [docker].
LinuxDependencyInspection _inspection({
  List<String> missingTools = const [],
  bool locked = false,
  bool docker = true,
}) => LinuxDependencyInspection(
  system: LinuxSystemProbe(
    os: LinuxOsSupport.supported,
    base: 'noble',
    missingPackages: {
      if (missingTools.isNotEmpty)
        LinuxHelperCategory.hermesTools: missingTools,
      if (!docker) LinuxHelperCategory.dockerInstall: const ['docker.io'],
    },
    dockerFootprint: docker ? const {DockerFootprint.package} : const {},
    secretProviderInstalled: true,
  ),
  session: const LinuxSession(
    sessionBus: true,
    graphical: true,
    pkexec: true,
    systemd: true,
    userManager: true,
  ),
  secretService: SecretServiceStatus(
    SecretServiceState.running,
    locked: locked,
  ),
  docker: docker
      ? const DockerStatus(
          cli: '/usr/bin/docker',
          context: DockerContext(name: 'default', host: _rootful),
          rootful: DockerEngineStatus(
            host: _rootful,
            access: DockerAccess.answers,
            serviceLoaded: true,
            serviceActive: true,
          ),
          userName: 'tester',
          groupExists: true,
          userInGroup: true,
          sessionInGroup: true,
        )
      : const DockerStatus(
          rootful: DockerEngineStatus(
            host: _rootful,
            access: DockerAccess.notProbed,
          ),
          userName: 'tester',
        ),
);

DetectedHermes _compatible(String hermesHome) => DetectedHermes(
  executable: '$hermesHome/bin/hermes',
  version: 'Hermes Agent v0.21.5 (2026.9.24)',
  home: hermesHome,
);

typedef _Apply = Stream<LinuxDependencyEvent> Function(
  LinuxDependencyPlan plan, {
  LinuxApplyCancellation? cancellation,
});

/// pkexec ends with [step] (126 dismissed, 127 denied): nothing ran.
_Apply _refused(LinuxApplyOutcome outcome, LinuxStepOutcome step) =>
    (plan, {cancellation}) async* {
      yield const LinuxDependencyStarted(LinuxDependencyStep.authorization);
      yield LinuxDependencyFinished(LinuxDependencyStep.authorization, step);
      final after = _inspection(missingTools: ['ripgrep']);
      yield LinuxDependencyResult(
        outcome,
        after,
        LinuxDependencyPlan.compute(after, plan.targets),
        detail: 'The administrator authorization was ${outcome.name}.',
      );
    };

/// Every planned step runs; the fresh inspection finds nothing left.
Stream<LinuxDependencyEvent> _prepared(
  LinuxDependencyPlan plan, {
  LinuxApplyCancellation? cancellation,
}) async* {
  for (final planned in plan.steps) {
    yield LinuxDependencyStarted(planned.step);
    yield LinuxDependencyFinished(planned.step, LinuxStepOutcome.done);
  }
  final after = _inspection();
  yield LinuxDependencyResult(
    LinuxApplyOutcome.ready,
    after,
    LinuxDependencyPlan.compute(after, plan.targets),
  );
}

/// The assistant's collaborators, faked at their boundary: the system half,
/// Hermes detection, the backend, the plugin install and the local
/// instance's REST API. The installer is the real one on a scripted
/// `install.sh`.
final class _Setup {
  _Setup(String root) : script = _Script(root);

  final _Script script;
  late final db = openMemoryDatabase();

  /// What each inspection returns, in order (the last one repeats).
  final inspections = <LinuxDependencyInspection>[];
  var _inspected = 0;
  _Apply apply = _prepared;
  Future<DetectedHermes?> Function()? detect;

  final backendStarts = <DetectedHermes>[];
  var pluginInstalls = 0;
  var doctors = 0;

  /// Plugin REST answers, keyed `'METHOD /path'`; others answer 404.
  final rest = <String, Object? Function(http.Request)>{
    'GET /api/plugins/hermuse/files': (_) => {'files': <String>[]},
    'POST /api/plugins/hermuse/cron/enable': (_) => {'jobs': <Object>[]},
  };

  /// The computer sets up, runs and shows a screen.
  void serveComputer() {
    rest['POST /api/plugins/hermuse/computer/setup'] = (_) => {
      'state': 'running',
    };
    rest['GET /api/plugins/hermuse/computer/thumbnail'] = (_) =>
        http.Response.bytes(const [0xFF, 0xD8, 0xFF], 200);
  }

  LinuxDependencyInspection _nextInspection() {
    final index = _inspected < inspections.length
        ? _inspected
        : inspections.length - 1;
    _inspected++;
    return inspections[index];
  }

  LinuxSetupServices services() => LinuxSetupServices(
    system: LinuxSystemAccess(
      inspect: () async => _nextInspection(),
      apply: (plan, {cancellation}) => apply(plan, cancellation: cancellation),
    ),
    hermesHome: script.hermesHome,
    journalPath: script.journalPath,
    newInstaller: script.installer,
    detectHermes: detect ?? script.detector().detect,
    startBackend: (registry, hermes, endpoint) async {
      backendStarts.add(hermes);
      final instance = HermesInstance(
        id: localInstanceId,
        label: 'This computer',
        kind: InstanceKind.local,
        baseUrl: Uri.parse('http://127.0.0.1:4100'),
        auth: AuthMethod.loopbackToken,
      );
      if (registry.byId(localInstanceId) == null) {
        await registry.add(instance);
      } else {
        await registry.update(instance);
      }
      return instance;
    },
    useDockerEndpoint: (_) {},
    installPlugin: (_) async => pluginInstalls++,
    verifyBridge: () async {},
    pluginDoctor: () async => doctors++,
    pollInterval: Duration.zero,
  );

  List<Override> overrides({SecretStore? secrets}) => [
    hermuseDatabaseProvider.overrideWithValue(db),
    secretStoreProvider.overrideWithValue(secrets ?? MemorySecretStore()),
    linuxSetupServicesProvider.overrideWithValue(services()),
    restClientProvider(localInstanceId).overrideWith(
      (ref) => HermesRestClient(
        MockClient((request) async {
          final route = rest['${request.method} ${request.url.path}'];
          return switch (route?.call(request)) {
            null => http.Response('{"detail":"Not Found"}', 404),
            final http.Response response => response,
            final body => http.Response(jsonEncode(body), 200),
          };
        }),
        baseUrl: Uri.parse('http://127.0.0.1:4100'),
      ),
    ),
  ];

  ProviderContainer container({SecretStore? secrets}) {
    final container = ProviderContainer(overrides: overrides(secrets: secrets));
    addTearDown(container.dispose);
    return container;
  }

  Future<void> dispose() => db.close();
}

/// Stands in for `install.sh`: answers `--manifest`, runs stages by
/// recording them and writing what validation reads (the checkout's `HEAD`,
/// the bootstrap marker), and answers `--version` for the managed launcher.
final class _Script {
  _Script(this.root);

  final String root;
  String get hermesHome => '$root/hermes-home';
  String get installDir => '$hermesHome/hermes-agent';
  String get journalPath => '$root/support/hermes-install.json';
  String get launcher => ManagedRuntime(hermesHome).launcher;

  final stagesRun = <String>[];
  var manifestReads = 0;

  /// Stages that fail the next time they run.
  final failing = <String>{};

  static const _stages = [
    'prerequisites',
    'repository',
    'venv',
    'python-deps',
    'node-deps',
    'path',
    'config',
    'setup',
    'gateway',
    'complete',
  ];

  HermesInstaller installer() => HermesInstaller(
    hermesHome: hermesHome,
    installDir: installDir,
    journalPath: journalPath,
    source: const InstallerSource(
      isWindows: false,
      localScript: '/fake/install.sh',
    ),
    environment: const {'PATH': '/usr/bin'},
    isWindows: false,
    isMacOS: false,
    fileExists: (path) async => path == '/fake/install.sh',
    which: (_) async => '/usr/bin/tool',
    runScript: _run,
  );

  /// The real detector over this fake home: the managed launcher answers
  /// once the install completed, and the journal is honoured.
  HermesDetector detector() => HermesDetector(
    isWindows: false,
    environment: {'HERMES_HOME': hermesHome, 'PATH': ''},
    homeDirectory: '$root/home',
    fileExists: (path) async =>
        path == launcher &&
        File('$installDir/.hermes-bootstrap-complete').existsSync(),
    runVersion: (_, _) async =>
        ProcessResult(0, 0, 'Hermes Agent v0.21.5 (2026.9.24)\n', ''),
    which: (_) async => null,
    readInstallJournal: () => InstallJournal.read(journalPath),
  );

  /// The checkout the `repository` stage leaves.
  Future<void> checkout() async {
    await Directory('$installDir/.git').create(recursive: true);
    await File('$installDir/.git/HEAD').writeAsString('$hermesReleaseCommit\n');
  }

  Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String stream, String line)? onLine,
  }) async {
    if (executable == launcher) {
      return ProcessResult(0, 0, 'Hermes Agent v0.21.5 (2026.9.24)\n', '');
    }
    if (args.contains('--manifest')) {
      manifestReads++;
      return ProcessResult(
        0,
        0,
        jsonEncode({
          'protocol_version': 1,
          'stages': [
            for (final name in _stages)
              {
                'name': name,
                'title': name,
                'category': 'runtime',
                'needs_user_input': false,
              },
          ],
        }),
        '',
      );
    }
    final stage = args[args.indexOf('--stage') + 1];
    stagesRun.add(stage);
    onLine?.call('stdout', 'working on $stage');
    if (failing.remove(stage)) {
      return ProcessResult(
        0,
        1,
        '{"ok":false,"stage":"$stage","skipped":false,"reason":"exit code 1"}\n',
        '',
      );
    }
    switch (stage) {
      case 'repository':
        await checkout();
      case 'complete':
        await File('$installDir/.hermes-bootstrap-complete').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'pinnedCommit': args[args.indexOf('--commit') + 1],
          }),
        );
    }
    return ProcessResult(
      0,
      0,
      '{"ok":true,"stage":"$stage","skipped":false}\n',
      '',
    );
  }
}

/// A Secret Service keyring that refuses every access while [locked], the
/// way the platform plugin reports a dismissed unlock prompt.
final class _Keyring implements SecretStore {
  bool locked = true;
  final values = <String, String>{};

  void _check() {
    if (locked) {
      throw PlatformException(code: 'KeyringLocked', message: 'KeyringLocked');
    }
  }

  @override
  Future<String?> read(String instanceId, String key) async {
    _check();
    return values['$instanceId/$key'];
  }

  @override
  Future<void> write(String instanceId, String key, String value) async {
    _check();
    values['$instanceId/$key'] = value;
  }

  @override
  Future<void> delete(String instanceId) async {
    _check();
    values.removeWhere((key, _) => key.startsWith('$instanceId/'));
  }
}
