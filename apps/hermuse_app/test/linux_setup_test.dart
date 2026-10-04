import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/host/linux_setup.dart';
import 'package:hermuse_app/host/linux_setup_gate.dart';
import 'package:hermuse_app/platform/local_host.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

const _legacy = LegacyHermesMigration(
  sourceHome: '/home/desktop/.hermes',
  revision: 'reviewed-revision',
  summary: 'Settings and conversations; original retained.',
);
const _outcome = RemoteInstallOutcome(
  baseUrl: 'http://127.0.0.1:9119',
  username: '',
  password: '',
  sessionToken: 'private-token',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LinuxSetupController canonical service', () {
    test(
      'should block service setup until the desktop keyring really works',
      () async {
        final secrets = _LockableSecrets();
        final fixture = _Fixture(secretStore: secrets);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        expect(fixture.state.phase, isA<SetupKeyringReview>());
        expect(fixture.state.keystoreVerified, isFalse);
        expect(fixture.installs, isEmpty);
        secrets.locked = false;
        await fixture.controller.checkAgain();
        expect(fixture.state.phase, isA<SetupReview>());
        expect(fixture.state.keystoreVerified, isTrue);
        expect(fixture.installs, isEmpty);
      },
    );

    test('should not mutate or migrate before explicit approval', () async {
      final fixture = _Fixture(legacy: _legacy);
      final controller = fixture.controller;
      await controller.prepare(LinuxSetupGoal.local);
      expect(fixture.state.phase, isA<SetupReview>());
      expect(fixture.installs, isEmpty);
      expect(fixture.state.keystoreVerified, isTrue);
      controller.cancel();
      expect(fixture.state.phase, isA<SetupIdle>());
      expect(fixture.installs, isEmpty);
    });

    test(
      'should hand the exact approved revision to the shared installer',
      () async {
        final fixture = _Fixture(legacy: _legacy);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await fixture.controller.authorize();
        expect(fixture.installs, [_legacy]);
        expect(fixture.connects, 0);
        expect(fixture.state.purpose, LinuxSetupPurpose.provision);
        expect(fixture.state.phase, isA<SetupFinished>());
        final registry = await fixture.container.read(registryProvider.future);
        await registry.load();
        final local = registry.byId(localInstanceId)!;
        expect(local.kind, InstanceKind.system);
        expect(local.baseUrl.toString(), _outcome.baseUrl);
        expect(bridgeOnServer(local), isTrue);
        expect(
          await fixture.secrets.read(localInstanceId, SecretKeys.sessionToken),
          'private-token',
        );
        expect(fixture.host.supervisor, isNull);
      },
    );

    test(
      'should reuse canonical service without merging legacy data',
      () async {
        final fixture = _Fixture(canonical: true, legacy: _legacy);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await fixture.controller.authorize();
        expect(fixture.installs, isEmpty);
        expect(fixture.connects, 1);
        expect(fixture.state.purpose, LinuxSetupPurpose.connect);
        expect(fixture.state.phase, isA<SetupFinished>());
        final registry = await fixture.container.read(registryProvider.future);
        await registry.load();
        expect(registry.byId(localInstanceId)?.kind, InstanceKind.system);
        expect(
          registry.byId(localInstanceId)?.baseUrl.toString(),
          _outcome.baseUrl,
        );
        expect(
          await fixture.secrets.read(localInstanceId, SecretKeys.sessionToken),
          'private-token',
        );
      },
    );

    test('should never fall back to installation when connect fails', () async {
      final fixture = _Fixture(canonical: true)
        ..connectError = StateError('Unrecognized service override');
      await fixture.controller.prepare(LinuxSetupGoal.local);
      await fixture.controller.authorize();
      expect(fixture.connects, 1);
      expect(fixture.installs, isEmpty);
      expect(fixture.state.phase, isA<SetupFailed>());
      expect(
        (await fixture.container.read(registryProvider.future)).instances,
        isEmpty,
      );
      await fixture.controller.checkAgain();
      expect(fixture.state.purpose, LinuxSetupPurpose.connect);
      expect(fixture.installs, isEmpty);
    });

    test('should provision for explicit computer setup', () async {
      final fixture = _Fixture(canonical: true, legacy: _legacy);
      await fixture.controller.prepare(LinuxSetupGoal.computer);
      await fixture.controller.authorize();
      expect(fixture.state.purpose, LinuxSetupPurpose.provision);
      expect(fixture.installs, [null]);
      expect(fixture.connects, 0);
      expect(fixture.state.phase, isA<SetupFinished>());
    });

    test('should review connection on discovery before authorizing', () async {
      final fixture = _Fixture(canonical: true);
      await fixture.controller.start();
      expect(fixture.state.phase, isA<SetupReview>());
      expect(fixture.state.purpose, LinuxSetupPurpose.connect);
      expect(fixture.connects, 0);
      expect(fixture.installs, isEmpty);
      fixture.controller.cancel();
      expect(fixture.state.phase, isA<SetupIdle>());
      expect(fixture.connects, 0);
    });

    test('should require completion proof when connecting', () async {
      final fixture = _Fixture(canonical: true)..finish = false;
      await fixture.controller.prepare(LinuxSetupGoal.local);
      await fixture.controller.authorize();
      expect(fixture.state.phase, isA<SetupFailed>());
      expect(fixture.installs, isEmpty);
      expect(
        (await fixture.container.read(registryProvider.future)).instances,
        isEmpty,
      );
    });

    test('should reuse saved registration and token across launches without spawning', () async {
      final fixture = _Fixture(canonical: true);
      final registry = await fixture.container.read(registryProvider.future);
      await fixture.host.registerService(registry, _outcome);
      await fixture.controller.start();
      expect(fixture.state.phase, isA<SetupFinished>());
      expect(fixture.installs, isEmpty);
      expect(fixture.connects, 0);
      expect((await fixture.host.boot(registry))?.kind, InstanceKind.system);
      await fixture.host.shutdown();
      expect(
        await fixture.secrets.read(localInstanceId, SecretKeys.sessionToken),
        'private-token',
      );
      expect(fixture.host.supervisor, isNull);
    });

    test(
      'should ask to sign in again when the keyring lost the saved password',
      () async {
        final fixture = _Fixture(canonical: true, authRequired: true);
        final registry = await fixture.container.read(registryProvider.future);
        await registry.add(
          HermesInstance(
            id: localInstanceId,
            label: 'This computer',
            kind: InstanceKind.system,
            baseUrl: Uri.parse('http://127.0.0.1:9119'),
            auth: AuthMethod.password,
          ),
        );
        await fixture.controller.start();
        expect(fixture.state.goal, LinuxSetupGoal.local);
        expect(fixture.state.phase, isA<SetupDashboardLogin>());

        // A password without its username cannot sign in either.
        await fixture.secrets.write(localInstanceId, SecretKeys.password, 'pw');
        expect(await fixture.host.serviceAccessMissing(registry), isTrue);
        await fixture.secrets.write(localInstanceId, SecretKeys.username, 'u');
        final reopened = _Fixture(
          canonical: true,
          authRequired: true,
          secretStore: fixture.secrets,
        );
        await (await reopened.container.read(registryProvider.future))
            .add(registry.byId(localInstanceId)!);
        await reopened.controller.start();
        expect(reopened.state.phase, isA<SetupFinished>());
        expect(reopened.state.goal, LinuxSetupGoal.reopen);
      },
    );

    test('should authorize again when the keyring lost the token', () async {
      final fixture = _Fixture(canonical: true, authRequired: false);
      final registry = await fixture.container.read(registryProvider.future);
      await fixture.host.registerService(registry, _outcome);
      await fixture.secrets.delete(localInstanceId);
      await fixture.controller.start();
      expect(fixture.state.phase, isA<SetupReview>());
      expect(fixture.state.purpose, LinuxSetupPurpose.connect);
      await fixture.controller.authorize();
      expect(fixture.connects, 1);
      expect(fixture.installs, isEmpty);
      expect(fixture.state.phase, isA<SetupFinished>());
      expect(
        await fixture.secrets.read(localInstanceId, SecretKeys.sessionToken),
        'private-token',
      );
    });

    test(
      'should never report ready when the helper returns without completion',
      () async {
        final fixture = _Fixture()..finish = false;
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await fixture.controller.authorize();
        expect(fixture.state.phase, isA<SetupFailed>());
        expect(
          (await fixture.container.read(registryProvider.future)).instances,
          isEmpty,
        );
        expect(fixture.state.completed, contains(RemoteInstallStep.preflight));
        await fixture.controller.checkAgain();
        expect(fixture.state.phase, isA<SetupReview>());
      },
    );

    test('should surface an actionable refusal before any mutation', () async {
      final fixture = _Fixture()
        ..inspectionError = StateError(
          'Stop the Hermes process owned by another session and retry.',
        );
      await fixture.controller.prepare(LinuxSetupGoal.local);
      expect(
        fixture.state.phase,
        isA<SetupFailed>().having(
          (s) => s.message,
          'refusal',
          contains('another session'),
        ),
      );
      expect(fixture.installs, isEmpty);
    });

    testWidgets(
      'should show informed migration review and leave data untouched on cancel',
      (tester) async {
        final fixture = _Fixture(legacy: _legacy);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await _pumpSetup(tester, fixture);
        await _capture(tester, 'linux-service-migration.png');
        expect(find.text('Review legacy migration'), findsOneWidget);
        expect(find.textContaining('/home/desktop/.hermes'), findsOneWidget);
        expect(
          find.textContaining('never merged or overwritten'),
          findsOneWidget,
        );
        expect(find.text('Host or IP address'), findsNothing);
        expect(fixture.installs, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        expect(fixture.installs, isEmpty);
        expect(fixture.state.phase, isA<SetupIdle>());
      },
    );

    testWidgets(
      'should authorize reuse without migration after showing legacy preservation',
      (tester) async {
        final fixture = _Fixture(canonical: true, legacy: _legacy);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await _pumpSetup(tester, fixture);
        await _capture(tester, 'linux-service-reuse.png');
        expect(find.text('Approve backed-up migration'), findsNothing);
        expect(
          find.textContaining('leaves that data untouched'),
          findsOneWidget,
        );
        expect(
          find.textContaining('may restart the dashboard once'),
          findsOneWidget,
        );
        expect(find.text('System requirements'), findsNothing);
        expect(find.text('Hermuse plugin and jobs'), findsNothing);
        expect(find.text('Docker and agent’s computer'), findsNothing);
        await tester.tap(find.text('Authorize service access'));
        await tester.pumpAndSettle();
        expect(fixture.installs, isEmpty);
        expect(fixture.connects, 1);
        expect(find.text('Desktop access is ready'), findsOneWidget);
        expect(find.text('System requirements'), findsNothing);
        expect(find.text('Pinned Hermes Agent'), findsNothing);
        expect(find.text('Hermuse plugin and jobs'), findsNothing);
        expect(find.text('Docker and agent’s computer'), findsNothing);
        expect(find.text('Authenticated desktop access'), findsOneWidget);
      },
    );
    test(
      'should probe unknown authentication through unprivileged login',
      () async {
        final fixture = _Fixture(canonical: true, authRequired: null);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        expect(fixture.state.phase, isA<SetupDashboardLogin>());
        await fixture.controller.authorize();
        expect(fixture.connects, 0);
        expect(fixture.installs, isEmpty);
      },
    );

    test('should route gated canonical service to dashboard login', () async {
      final fixture = _Fixture(canonical: true, authRequired: true);
      await fixture.controller.prepare(LinuxSetupGoal.local);
      expect(fixture.state.phase, isA<SetupDashboardLogin>());
      expect(fixture.state.purpose, LinuxSetupPurpose.dashboardLogin);
      await fixture.controller.authorize();
      expect(fixture.connects, 0);
      expect(fixture.installs, isEmpty);
      fixture.controller.cancel();
      expect(fixture.state.phase, isA<SetupIdle>());
    });

    test(
      'should finish only after dashboard login saved local service',
      () async {
        final fixture = _Fixture(canonical: true, authRequired: true);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        final registry = await fixture.container.read(registryProvider.future);
        await registry.add(
          HermesInstance(
            id: localInstanceId,
            label: 'This computer',
            kind: InstanceKind.system,
            baseUrl: Uri.parse(_outcome.baseUrl),
            auth: AuthMethod.password,
          ),
        );
        await fixture.secrets.write(
          localInstanceId,
          SecretKeys.password,
          'existing-dashboard-password',
        );
        await fixture.controller.dashboardLoginCompleted(localInstanceId);
        expect(fixture.state.phase, isA<SetupFinished>());
        expect(fixture.state.completed, {RemoteInstallStep.verify});
        expect(fixture.connects, 0);
        expect(fixture.installs, isEmpty);
        await registry.load();
        expect(registry.byId(localInstanceId)?.kind, InstanceKind.system);
        expect(registry.byId(localInstanceId)?.auth, AuthMethod.password);
        expect(
          await fixture.secrets.read(localInstanceId, SecretKeys.password),
          'existing-dashboard-password',
        );
      },
    );

    test(
      'should reject dashboard completion without local registration',
      () async {
        final fixture = _Fixture(canonical: true, authRequired: true);
        await fixture.controller.prepare(LinuxSetupGoal.local);
        await fixture.controller.dashboardLoginCompleted(localInstanceId);
        expect(fixture.state.phase, isA<SetupFailed>());
        expect(fixture.connects, 0);
        expect(fixture.installs, isEmpty);
      },
    );

    test(
      'should review a broken scheduler before the dashboard login',
      () async {
        final fixture = _Fixture(
          canonical: true,
          authRequired: true,
          schedulerReady: false,
        );
        await fixture.controller.prepare(LinuxSetupGoal.local);
        expect(fixture.state.phase, isA<SetupReview>());
        expect(fixture.state.purpose, LinuxSetupPurpose.dashboardLogin);
        // A plain authorize never installs over the gated service.
        await fixture.controller.authorize();
        expect(fixture.installs, isEmpty);
        expect(fixture.connects, 0);
        fixture.controller.skipSchedulerRepair();
        expect(fixture.state.phase, isA<SetupDashboardLogin>());
      },
    );

    testWidgets('should repair a broken scheduler with the installer', (
      tester,
    ) async {
      final fixture = _Fixture(canonical: true, schedulerReady: false);
      await fixture.controller.prepare(LinuxSetupGoal.local);
      await _pumpSetup(tester, fixture);
      expect(find.text('Scheduler — needs repair'), findsOneWidget);
      expect(find.text('Authorize service access'), findsOneWidget);
      await _capture(tester, 'linux-service-scheduler-repair.png');
      await tester.tap(find.text('Repair scheduler'));
      await tester.pumpAndSettle();
      expect(fixture.installs, [null]);
      expect(fixture.connects, 0);
      expect(fixture.state.phase, isA<SetupFinished>());
      expect(find.text('Scheduler — needs repair'), findsNothing);
    });
  });
}

final class _Fixture {
  _Fixture({
    this.canonical = false,
    this.authRequired = false,
    this.legacy,
    this.schedulerReady,
    SecretStore? secretStore,
  }) : secrets = secretStore ?? MemorySecretStore() {
    addTearDown(db.close);
    addTearDown(container.dispose);
  }
  final bool canonical;
  final bool? authRequired;
  final LegacyHermesMigration? legacy;
  final bool? schedulerReady;
  final db = openMemoryDatabase();
  final SecretStore secrets;
  final installs = <LegacyHermesMigration?>[];
  int connects = 0;
  Object? connectError;
  bool finish = true;
  Object? inspectionError;
  late final host = LocalHermesHost.test(
    secrets: secrets,
    canonicalService: true,
    detector: HermesDetector(
      isWindows: false,
      environment: const {},
      homeDirectory: '/home/desktop',
      runVersion: (_, _) async =>
          throw StateError('Canonical mode must not run Hermes'),
      fileExists: (_) async =>
          throw StateError('Canonical mode must not detect legacy executables'),
      which: (_) async =>
          throw StateError('Canonical mode must not search PATH'),
    ),
  );
  late final container = ProviderContainer(
    overrides: [
      hermuseDatabaseProvider.overrideWithValue(db),
      secretStoreProvider.overrideWithValue(secrets),
      linuxSetupServicesProvider.overrideWithValue(
        LinuxSetupServices(
          inspect: () async {
            if (inspectionError case final error?) throw error;
            return LinuxServiceInspection(
              canonicalPresent: canonical,
              authRequired: authRequired,
              legacy: legacy,
              schedulerReady: schedulerReady,
            );
          },
          connect: () async* {
            connects++;
            if (connectError case final error?) throw error;
            for (final step in const [
              RemoteInstallStep.connect,
              RemoteInstallStep.dashboard,
              RemoteInstallStep.verify,
            ]) {
              yield RemoteInstallStepStarted(step);
              yield RemoteInstallStepFinished(step);
            }
            if (finish) yield const RemoteInstallCompleted(_outcome);
          },
          install: ({migration}) async* {
            installs.add(migration);
            yield const RemoteInstallStepStarted(RemoteInstallStep.preflight);
            yield const RemoteInstallStepFinished(RemoteInstallStep.preflight);
            if (finish) yield const RemoteInstallCompleted(_outcome);
          },
          cancel: () async {},
          register: host.registerService,
          quiesceOwnedLegacy: () async {},
          accessMissing: host.serviceAccessMissing,
          inspectKeyring: () async =>
              throw StateError('Unexpected keyring repair'),
          applyKeyring: (_) => const Stream.empty(),
        ),
      ),
      restClientProvider(localInstanceId).overrideWith(
        (ref) => HermesRestClient(
          MockClient((_) async => http.Response('{}', 200)),
          baseUrl: Uri.parse(_outcome.baseUrl),
          sessionToken: 'private-token',
        ),
      ),
    ],
  );
  LinuxSetupController get controller =>
      container.read(linuxSetupProvider.notifier);
  LinuxSetupState get state => container.read(linuxSetupProvider);
}

final _captureKey = GlobalKey();

Future<void> _pumpSetup(WidgetTester tester, _Fixture fixture) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(() async {
    final loader = FontLoader('packages/yellow_stick_ui/Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      loader.addFont(
        File('../../packages/yellow_stick_ui/fonts/Inter-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await loader.load();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: UncontrolledProviderScope(
        container: fixture.container,
        child: YsTheme(
          palette: YsPalette.dark,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: MediaQuery(
              data: MediaQueryData(size: Size(1200, 1000)),
              child: LinuxSetupGate(canLeave: true),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../../.artifacts/flutter/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

final class _LockableSecrets implements SecretStore {
  final _memory = MemorySecretStore();
  bool locked = true;
  @override
  Future<String?> read(String instanceId, String key) =>
      _memory.read(instanceId, key);
  @override
  Future<void> write(String instanceId, String key, String value) async {
    if (locked) throw StateError('Unlock the desktop keyring');
    await _memory.write(instanceId, key, value);
  }

  @override
  Future<void> delete(String instanceId) => _memory.delete(instanceId);
}
