import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermuse_app/host/remote_install.dart';
import 'package:hermuse_app/host/setup_view.dart';
import 'package:hermuse_app/platform/plugin_bundle.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

const _key = RemoteHostKey(
  host: '203.0.113.10',
  port: 22,
  type: 'ssh-ed25519',
  fingerprint: 'SHA256:separate-trusted-console-fingerprint',
);
const _outcome = RemoteInstallOutcome(
  baseUrl: 'https://hermuse.203-0-113-10.sslip.io',
  username: 'admin',
  password: 'generated-dashboard-secret',
);

const _removableService = RemoteUninstallResource(
  id: 'dashboard',
  label: 'Hermes dashboard service',
  kind: 'service',
  removable: true,
  purgeOnly: false,
  reason: 'Installer-owned service.',
);
const _keptData = RemoteUninstallResource(
  id: 'data',
  label: 'Hermes data and cache',
  kind: 'data',
  removable: true,
  purgeOnly: true,
  reason: 'Kept unless purge is confirmed.',
);
const _sharedDocker = RemoteUninstallResource(
  id: 'docker',
  label: 'Shared Docker package',
  kind: 'package',
  removable: false,
  purgeOnly: false,
  reason: 'Shared dependency, not owned by this installation.',
  managed: false,
);
const _removalInventory = RemoteUninstallInventory(
  host: '203.0.113.10',
  resources: [_removableService, _keptData, _sharedDocker],
  revision: 'inspected-server-revision',
);

RemoteUninstallOutcome _removed({bool purge = false, bool complete = true}) =>
    RemoteUninstallOutcome(
      purged: purge,
      removed: ['dashboard', if (purge) 'data'],
      preserved: [if (!purge) _keptData, _sharedDocker],
      warnings: complete
          ? const []
          : const ['Managed network ownership needs review.'],
      complete: complete,
    );

/// The transport waits for the UI's trust decision before authenticating.
final class _Installer extends RemoteInstaller {
  final trust = RemoteHostKeyTrust();
  final attempts = <StreamController<RemoteInstallProgress>>[];
  bool connected = false;
  bool authenticated = false;
  bool? accepted;
  Completer<void>? stopRelease;

  @override
  Stream<RemoteInstallProgress> run({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required Map<String, Uint8List> pluginBundle,
    required Future<bool> Function(RemoteHostKey) onHostKey,
  }) {
    late final StreamController<RemoteInstallProgress> events;
    events = StreamController<RemoteInstallProgress>(
      onListen: () async {
        connected = true;
        authenticated = false;
        events.add(const RemoteInstallStepStarted(RemoteInstallStep.connect));
        try {
          await trust.verify(_key, (key) async {
            accepted = await onHostKey(key);
            return accepted!;
          });
          if (!connected) return;
          authenticated = true;
          events.add(
            const RemoteInstallStepFinished(RemoteInstallStep.connect),
          );
          events.add(
            const RemoteInstallStepStarted(RemoteInstallStep.preflight),
          );
        } on Object catch (error, stack) {
          // A cancelled handshake must settle without an unobserved producer
          // error, like the real transport's cancelled task.
          if (connected && !events.isClosed) events.addError(error, stack);
        }
      },
      onCancel: () => connected = false,
    );
    attempts.add(events);
    return events.stream;
  }

  @override
  Future<void> cancel() {
    connected = false;
    return stopRelease?.future ?? Future.value();
  }

  Future<void> dispose() async {
    for (final attempt in attempts) {
      // A declined attempt never listened to its event stream.
      if (!attempt.hasListener) {
        unawaited(attempt.close());
      } else {
        await attempt.close();
      }
    }
  }
}

final class _Uninstaller extends RemoteUninstaller {
  final trust = RemoteHostKeyTrust();
  final attempts = <StreamController<RemoteUninstallProgress>>[];
  final purges = <bool>[];
  RemoteUninstallInventory inventory = _removalInventory;
  Completer<void>? inspectionRelease;
  Completer<void>? stopRelease;
  var inspections = 0;
  var connected = false;
  var authenticated = false;

  @override
  Future<RemoteUninstallInventory> inspect({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required Future<bool> Function(RemoteHostKey) onHostKey,
  }) async {
    inspections++;
    connected = true;
    authenticated = false;
    try {
      await trust.verify(_key, onHostKey);
      authenticated = true;
      await inspectionRelease?.future;
      return inventory;
    } finally {
      connected = false;
    }
  }

  @override
  Stream<RemoteUninstallProgress> run({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required RemoteUninstallInventory inventory,
    bool purge = false,
    required Future<bool> Function(RemoteHostKey) onHostKey,
  }) {
    purges.add(purge);
    late final StreamController<RemoteUninstallProgress> events;
    events = StreamController<RemoteUninstallProgress>(
      onListen: () async {
        connected = true;
        events.add(
          const RemoteUninstallStepStarted(RemoteUninstallStep.connect),
        );
        try {
          await trust.verify(_key, onHostKey);
          if (!connected) return;
          events
            ..add(
              const RemoteUninstallStepFinished(RemoteUninstallStep.connect),
            )
            ..add(
              const RemoteUninstallStepStarted(RemoteUninstallStep.inspect),
            );
        } on Object catch (error, stack) {
          if (connected && !events.isClosed) events.addError(error, stack);
        }
      },
      onCancel: () => connected = false,
    );
    attempts.add(events);
    return events.stream;
  }

  @override
  Future<void> cancel() {
    connected = false;
    return stopRelease?.future ?? Future.value();
  }

  Future<void> dispose() async {
    for (final attempt in attempts) {
      if (!attempt.hasListener) {
        unawaited(attempt.close());
      } else {
        await attempt.close();
      }
    }
  }
}

final class _PluginAssets extends CachingAssetBundle {
  Completer<void>? release;

  @override
  Future<ByteData> load(String key) async {
    await release?.future;
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        '${pluginAssetPrefix}__init__.py': [
          {'asset': '${pluginAssetPrefix}__init__.py'},
        ],
      })!;
    }
    return ByteData.sublistView(
      Uint8List.fromList([35, 32, 112, 108, 117, 103, 105, 110]),
    );
  }
}

Finder _button(String text) => find.widgetWithText(YsButton, text);

Finder _input(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is YsInputBox && widget.semanticLabel == label,
  ),
  matching: find.byType(EditableText),
);

YsChecklistItem _step(WidgetTester tester, RemoteInstallStep step) => tester
    .widget<YsChecklist>(find.byType(YsChecklist))
    .items
    .singleWhere((item) => item.id == step);

Future<void> _pump(
  WidgetTester tester,
  _Installer installer, {
  ValueChanged<RemoteInstallOutcome>? onDone,
  VoidCallback? onCancel,
  _PluginAssets? assets,
  _Uninstaller? uninstaller,
  bool remove = false,
}) async {
  tester.view
    ..physicalSize = const Size(900, 1500)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(installer.dispose);
  if (uninstaller != null) addTearDown(uninstaller.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view)
          .copyWith(disableAnimations: true),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: YsTheme(
          palette: YsPalette.dark,
          child: Overlay.wrap(
            child: RemoteInstallScreen(
              installer: installer,
              uninstaller: uninstaller,
              remove: remove,
              bundle: assets ?? _PluginAssets(),
              onDone: onDone ?? (_) {},
              onCancel: onCancel ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _review(
  WidgetTester tester, {
  String password = 'ssh-secret',
}) async {
  await tester.enterText(_input('Host or IP address'), _key.host);
  await tester.enterText(_input('SSH password (optional)'), password);
  await tester.tap(_button('Review setup'));
  await tester.pumpAndSettle();
}

Future<void> _connect(WidgetTester tester) async {
  await _review(tester);
  await tester.tap(_button('Agree and connect'));
  await tester.pumpAndSettle();
}

Future<void> _inspectRemoval(WidgetTester tester) async {
  await tester.enterText(_input('Host or IP address'), _key.host);
  await tester.enterText(_input('SSH password (optional)'), 'ssh-secret');
  await tester.tap(_button('Review inspection'));
  await tester.pumpAndSettle();
  await tester.tap(_button('Agree and inspect'));
  await tester.pumpAndSettle();
  if (_button('Accept fingerprint').evaluate().isNotEmpty) {
    await tester.tap(_button('Accept fingerprint'));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadInter);

  group('RemoteInstallScreen', () {
    testWidgets(
      'should reject an empty host and an invalid port before consent',
      (tester) async {
        final installer = _Installer();
        await _pump(tester, installer);
        await tester.tap(_button('Review setup'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Enter a host name'), findsOneWidget);
        expect(_button('Agree and connect'), findsNothing);

        await tester.enterText(_input('Host or IP address'), _key.host);
        await tester.enterText(_input('SSH port'), '65536');
        await tester.tap(_button('Review setup'));
        await tester.pumpAndSettle();
        expect(find.textContaining('between 1 and 65535'), findsOneWidget);
        expect(installer.connected, isFalse);
      },
    );

    testWidgets(
      'should allow a blank password but still require consent and host trust',
      (tester) async {
        final installer = _Installer();
        await _pump(tester, installer);
        await _review(tester, password: '');
        expect(_button('Agree and connect'), findsOneWidget);
        expect(installer.connected, isFalse);
        await tester.tap(_button('Agree and connect'));
        await tester.pumpAndSettle();
        expect(find.text(_key.fingerprint), findsOneWidget);
        expect(installer.authenticated, isFalse);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        expect(installer.authenticated, isTrue);
        expect(
          tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items
              .singleWhere((item) => item.id == RemoteInstallStep.preflight)
              .state,
          YsStepState.working,
        );
      },
    );

    testWidgets(
      'should precheck healthy stages without hiding active checks or pending repairs',
      (tester) async {
        final installer = _Installer();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(tester, installer, onDone: outcomes.add);
        await _connect(tester);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        final attempt = installer.attempts.single;
        attempt.add(const RemoteInstallLog('Checking existing server setup…'));
        const healthy = [
          RemoteInstallStep.firewall,
          RemoteInstallStep.hermesUser,
          RemoteInstallStep.hermes,
          RemoteInstallStep.plugin,
          RemoteInstallStep.computer,
        ];
        for (final step in healthy) {
          attempt.add(
            RemoteInstallStepFinished(step, previouslyCompleted: true),
          );
        }
        await tester.pumpAndSettle();

        expect(
          _step(tester, RemoteInstallStep.preflight).state,
          YsStepState.working,
        );
        expect(
          tester.widget<SetupCard>(find.byType(SetupCard)).status,
          'Checking existing server setup…',
        );
        for (final step in healthy) {
          expect(_step(tester, step).state, YsStepState.found);
        }
        for (final step in const [
          RemoteInstallStep.dashboard,
          RemoteInstallStep.https,
          RemoteInstallStep.verify,
        ]) {
          expect(_step(tester, step).state, YsStepState.pending);
        }
        expect(outcomes, isEmpty);

        attempt
          ..add(const RemoteInstallLog('Existing server setup checked.'))
          ..add(const RemoteInstallStepFinished(RemoteInstallStep.preflight))
          ..add(const RemoteInstallStepStarted(RemoteInstallStep.dashboard))
          ..add(const RemoteInstallStepFinished(RemoteInstallStep.dashboard))
          ..add(const RemoteInstallStepStarted(RemoteInstallStep.https));
        await tester.pumpAndSettle();
        expect(
          _step(tester, RemoteInstallStep.https).state,
          YsStepState.working,
        );
        expect(
          _step(tester, RemoteInstallStep.preflight).state,
          YsStepState.done,
        );
        for (final step in healthy) {
          expect(_step(tester, step).state, YsStepState.found);
        }
        expect(
          _step(tester, RemoteInstallStep.verify).state,
          YsStepState.pending,
        );
        expect(outcomes, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'should rebuild partial retry readiness from fresh inspection, not the failed attempt',
      (tester) async {
        final installer = _Installer();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(tester, installer, onDone: outcomes.add);
        await _connect(tester);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        final first = installer.attempts.single;
        first
          ..add(
            const RemoteInstallStepFinished(
              RemoteInstallStep.plugin,
              previouslyCompleted: true,
            ),
          )
          ..add(const RemoteInstallStepStarted(RemoteInstallStep.https))
          ..addError(const RemoteInstallFailed('https', 'HTTPS setup failed.'));
        await tester.pumpAndSettle();
        expect(
          _step(tester, RemoteInstallStep.plugin).state,
          YsStepState.found,
        );
        expect(
          _step(tester, RemoteInstallStep.https).state,
          YsStepState.failed,
        );
        await tester.ensureVisible(_button('Try again'));
        await tester.tap(_button('Try again'));
        await tester.pumpAndSettle();
        await _connect(tester);

        // The accepted key remains pinned, but every attempt reauthenticates.
        expect(installer.authenticated, isTrue);
        expect(
          _step(tester, RemoteInstallStep.plugin).state,
          YsStepState.pending,
        );
        expect(
          _step(tester, RemoteInstallStep.https).state,
          YsStepState.pending,
        );
        final retry = installer.attempts.last;
        retry
          ..add(const RemoteInstallLog('Checking existing server setup…'))
          ..add(
            const RemoteInstallStepFinished(
              RemoteInstallStep.hermes,
              previouslyCompleted: true,
            ),
          )
          ..add(
            const RemoteInstallStepFinished(
              RemoteInstallStep.computer,
              previouslyCompleted: true,
            ),
          )
          ..add(const RemoteInstallLog('Existing server setup checked.'))
          ..add(const RemoteInstallStepFinished(RemoteInstallStep.preflight))
          ..add(const RemoteInstallStepStarted(RemoteInstallStep.plugin));
        await tester.pumpAndSettle();
        expect(
          _step(tester, RemoteInstallStep.hermes).state,
          YsStepState.found,
        );
        expect(
          _step(tester, RemoteInstallStep.computer).state,
          YsStepState.found,
        );
        expect(
          _step(tester, RemoteInstallStep.plugin).state,
          YsStepState.working,
        );
        expect(
          _step(tester, RemoteInstallStep.dashboard).state,
          YsStepState.pending,
        );
        expect(
          _step(tester, RemoteInstallStep.verify).state,
          YsStepState.pending,
        );
        expect(outcomes, isEmpty);
        first.add(const RemoteInstallCompleted(_outcome));
        await tester.pumpAndSettle();
        expect(outcomes, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'should require consent and explicit fingerprint acceptance before authentication',
      (tester) async {
        final installer = _Installer();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(tester, installer, onDone: outcomes.add);
        final password = tester
            .widget<EditableText>(_input('SSH password (optional)'))
            .controller;
        await _review(tester);
        expect(installer.connected, isFalse);
        await tester.tap(_button('Agree and connect'));
        await tester.pumpAndSettle();

        expect(find.text(_key.fingerprint), findsOneWidget);
        expect(installer.authenticated, isFalse);
        expect(password.text, isEmpty);
        expect(outcomes, isEmpty);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        expect(installer.authenticated, isTrue);
        expect(
          tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items
              .singleWhere((item) => item.id == RemoteInstallStep.preflight)
              .state,
          YsStepState.working,
        );
        expect(
          outcomes,
          isEmpty,
          reason: 'Authentication alone is not readiness.',
        );

        await tester.pumpWidget(const SizedBox());
        expect(installer.connected, isFalse);
      },
    );

    testWidgets(
      'should close a declined host and allow a key-only retry without retaining the password',
      (tester) async {
        final installer = _Installer();
        await _pump(tester, installer);
        await _connect(tester);
        await tester.tap(_button('Decline'));
        await tester.pumpAndSettle();

        expect(installer.accepted, isFalse);
        expect(installer.authenticated, isFalse);
        expect(installer.connected, isFalse);
        await tester.ensureVisible(_button('Try again'));
        await tester.tap(_button('Try again'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(_input('SSH password (optional)'))
              .controller
              .text,
          isEmpty,
        );
        await tester.tap(_button('Review setup'));
        await tester.pumpAndSettle();
        expect(_button('Agree and connect'), findsOneWidget);
        await tester.tap(_button('Agree and connect'));
        await tester.pumpAndSettle();
        expect(find.text(_key.fingerprint), findsOneWidget);
        expect(installer.authenticated, isFalse);
      },
    );

    testWidgets('should resolve an outstanding trust decision when disposed', (
      tester,
    ) async {
      final installer = _Installer();
      final outcomes = <RemoteInstallOutcome>[];
      await _pump(tester, installer, onDone: outcomes.add);
      await _connect(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(installer.accepted, isFalse);
      expect(installer.authenticated, isFalse);
      expect(installer.connected, isFalse);
      expect(outcomes, isEmpty);
    });

    testWidgets('should cancel before late asset loading can start SSH', (
      tester,
    ) async {
      final installer = _Installer();
      final assets = _PluginAssets()..release = Completer<void>();
      final outcomes = <RemoteInstallOutcome>[];
      var cancelled = false;
      await _pump(
        tester,
        installer,
        assets: assets,
        onDone: outcomes.add,
        onCancel: () => cancelled = true,
      );
      await _review(tester);
      await tester.tap(_button('Agree and connect'));
      await tester.pump();
      await tester.ensureVisible(_button('Cancel'));
      await tester.tap(_button('Cancel'));
      await tester.pumpWidget(const SizedBox());
      assets.release!.complete();
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(installer.connected, isFalse);
      expect(installer.attempts, isEmpty);
      expect(outcomes, isEmpty);
    });

    testWidgets(
      'should not finish after a failed or cancelled attempt emits a late result',
      (tester) async {
        final installer = _Installer();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(tester, installer, onDone: outcomes.add);
        await _connect(tester);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        final attempt = installer.attempts.single;
        attempt.add(const RemoteInstallStepStarted(RemoteInstallStep.computer));
        attempt.addError(
          const RemoteInstallFailed(
            'computer',
            'Computer image is unavailable.',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Computer image is unavailable.'), findsOneWidget);
        expect(
          tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items
              .singleWhere((item) => item.id == RemoteInstallStep.computer)
              .state,
          YsStepState.failed,
        );
        expect(installer.connected, isFalse);
        expect(outcomes, isEmpty);
        attempt.add(const RemoteInstallCompleted(_outcome));
        await tester.pumpAndSettle();
        expect(outcomes, isEmpty);
        await tester.ensureVisible(_button('Cancel'));
        await tester.tap(_button('Cancel'));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'should wait for transport cleanup before reconnecting on retry',
      (tester) async {
        final installer = _Installer();
        await _pump(tester, installer);
        await _connect(tester);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        installer.stopRelease = Completer<void>();
        installer.attempts.single.addError(
          const RemoteInstallFailed('preflight', 'Temporary server failure.'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(_button('Try again'));
        await tester.tap(_button('Try again'));
        await tester.pumpAndSettle();
        await _connect(tester);
        expect(installer.connected, isFalse);
        expect(find.text('Temporary server failure.'), findsNothing);

        installer.stopRelease!.complete();
        await tester.pumpAndSettle();
        expect(installer.connected, isTrue);
        expect(installer.authenticated, isTrue);
        expect(
          tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items
              .singleWhere((item) => item.id == RemoteInstallStep.preflight)
              .state,
          YsStepState.working,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
    for (final purge in [false, true]) {
      testWidgets(
        'should inspect and require explicit ${purge ? 'purge' : 'keep-data'} confirmation before removing a partial server installation',
        (tester) async {
          final installer = _Installer();
          final uninstaller = _Uninstaller();
          final outcomes = <RemoteInstallOutcome>[];
          await _pump(
            tester,
            installer,
            uninstaller: uninstaller,
            onDone: outcomes.add,
          );
          await tester.tap(_button('Remove from server'));
          await tester.pumpAndSettle();
          await tester.enterText(_input('Host or IP address'), _key.host);
          await tester.enterText(
            _input('SSH password (optional)'),
            'ssh-secret',
          );
          final password = tester
              .widget<EditableText>(_input('SSH password (optional)'))
              .controller;
          await tester.tap(_button('Review inspection'));
          await tester.pumpAndSettle();
          expect(uninstaller.inspections, 0);
          await tester.tap(_button('Agree and inspect'));
          await tester.pumpAndSettle();
          expect(find.text(_key.fingerprint), findsOneWidget);
          expect(uninstaller.authenticated, isFalse);
          expect(password.text, isEmpty);
          expect(uninstaller.purges, isEmpty);
          await tester.tap(_button('Accept fingerprint'));
          await tester.pumpAndSettle();
          expect(uninstaller.authenticated, isTrue);
          expect(uninstaller.purges, isEmpty);
          expect(installer.attempts, isEmpty);
          expect(_button('Uninstall and keep data'), findsOneWidget);
          expect(_button('Uninstall and purge data'), findsOneWidget);
          await tester.ensureVisible(
            _button(
              purge ? 'Uninstall and purge data' : 'Uninstall and keep data',
            ),
          );
          await tester.tap(
            _button(
              purge ? 'Uninstall and purge data' : 'Uninstall and keep data',
            ),
          );
          await tester.pumpAndSettle();
          expect(uninstaller.purges, [purge]);
          expect(_button('Done'), findsNothing);
          expect(outcomes, isEmpty);
          final rows = tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items;
          expect(
            rows
                .singleWhere((row) => row.id == RemoteUninstallStep.inspect)
                .state,
            YsStepState.working,
          );
          expect(
            rows
                .singleWhere((row) => row.id == RemoteUninstallStep.verify)
                .state,
            YsStepState.pending,
          );
          uninstaller.attempts.single
            ..add(
              const RemoteUninstallStepFinished(RemoteUninstallStep.inspect),
            )
            ..add(const RemoteUninstallStepStarted(RemoteUninstallStep.purge));
          await tester.pumpAndSettle();
          final checkpoint = tester
              .widget<YsChecklist>(find.byType(YsChecklist))
              .items
              .singleWhere((row) => row.id == RemoteUninstallStep.purge);
          expect(checkpoint.state, YsStepState.working);
          expect(checkpoint.title.toLowerCase().contains('purge'), purge);
          expect(
            tester
                .widget<SetupCard>(find.byType(SetupCard))
                .status
                .toLowerCase()
                .contains('purge'),
            purge,
          );
          uninstaller.attempts.single.add(
            RemoteUninstallCompleted(_removed(purge: purge)),
          );
          await tester.pumpAndSettle();
          expect(_button('Done'), findsOneWidget);
          expect(
            find.textContaining('Kept Shared Docker package:'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Kept Hermes data and cache:'),
            purge ? findsNothing : findsOneWidget,
          );
          expect(
            outcomes,
            isEmpty,
            reason: 'Removal never enters instance registration.',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'should forbid removal while inspection reports an active setup transaction',
      (tester) async {
        final uninstaller = _Uninstaller()
          ..inventory = const RemoteUninstallInventory(
            resources: [_removableService],
            revision: 'active-install',
            transactionActive: true,
          );
        await _pump(
          tester,
          _Installer(),
          uninstaller: uninstaller,
          remove: true,
        );
        await _inspectRemoval(tester);
        expect(_button('Uninstall and keep data'), findsNothing);
        expect(_button('Uninstall and purge data'), findsNothing);
        expect(uninstaller.purges, isEmpty);
        uninstaller.inventory = _removalInventory;
        await tester.ensureVisible(_button('Inspect again'));
        await tester.tap(_button('Inspect again'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(_input('SSH password (optional)'))
              .controller
              .text,
          isEmpty,
        );
        await _inspectRemoval(tester);
        expect(uninstaller.inspections, 2);
        expect(_button('Uninstall and keep data'), findsOneWidget);
        expect(uninstaller.purges, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'should ignore late inventory after cancelling a read-only inspection',
      (tester) async {
        final uninstaller = _Uninstaller()
          ..inspectionRelease = Completer<void>();
        var cancelled = false;
        await _pump(
          tester,
          _Installer(),
          uninstaller: uninstaller,
          remove: true,
          onCancel: () => cancelled = true,
        );
        await _inspectRemoval(tester);
        expect(uninstaller.authenticated, isTrue);
        expect(_button('Uninstall and purge data'), findsNothing);
        await tester.ensureVisible(_button('Cancel'));
        await tester.tap(_button('Cancel'));
        await tester.pumpWidget(const SizedBox());
        uninstaller.inspectionRelease!.complete();
        await tester.pumpAndSettle();
        expect(cancelled, isTrue);
        expect(uninstaller.connected, isFalse);
        expect(uninstaller.purges, isEmpty);
        expect(_button('Uninstall and keep data'), findsNothing);
      },
    );

    testWidgets(
      'should re-inspect after partial removal rather than register or claim complete removal',
      (tester) async {
        final uninstaller = _Uninstaller();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(
          tester,
          _Installer(),
          uninstaller: uninstaller,
          remove: true,
          onDone: outcomes.add,
        );
        await _inspectRemoval(tester);
        await tester.ensureVisible(_button('Uninstall and keep data'));
        await tester.tap(_button('Uninstall and keep data'));
        await tester.pumpAndSettle();
        uninstaller.attempts.single.add(
          RemoteUninstallCompleted(_removed(complete: false)),
        );
        await tester.pumpAndSettle();
        expect(_button('Inspect remaining resources'), findsOneWidget);
        expect(outcomes, isEmpty);
        await tester.ensureVisible(_button('Inspect remaining resources'));
        await tester.tap(_button('Inspect remaining resources'));
        await tester.pumpAndSettle();
        await _inspectRemoval(tester);
        expect(uninstaller.inspections, 2);
        expect(uninstaller.purges, [false]);
        expect(_button('Uninstall and keep data'), findsOneWidget);
        expect(outcomes, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'should require a fresh inspection after removal fails and reject the failed stream’s late success',
      (tester) async {
        final uninstaller = _Uninstaller();
        final outcomes = <RemoteInstallOutcome>[];
        await _pump(
          tester,
          _Installer(),
          uninstaller: uninstaller,
          remove: true,
          onDone: outcomes.add,
        );
        await _inspectRemoval(tester);
        await tester.ensureVisible(_button('Uninstall and keep data'));
        await tester.tap(_button('Uninstall and keep data'));
        await tester.pumpAndSettle();
        final attempt = uninstaller.attempts.single;
        attempt
          ..add(const RemoteUninstallStepFinished(RemoteUninstallStep.services))
          ..add(const RemoteUninstallStepStarted(RemoteUninstallStep.runtime))
          ..addError(
            const RemoteInstallFailed('runtime', 'Runtime removal failed.'),
          );
        await tester.pumpAndSettle();
        final rows = tester.widget<YsChecklist>(find.byType(YsChecklist)).items;
        expect(
          rows
              .singleWhere((row) => row.id == RemoteUninstallStep.services)
              .state,
          YsStepState.done,
        );
        expect(
          rows
              .singleWhere((row) => row.id == RemoteUninstallStep.runtime)
              .state,
          YsStepState.failed,
        );
        attempt.add(RemoteUninstallCompleted(_removed()));
        await tester.pumpAndSettle();
        expect(_button('Done'), findsNothing);
        await tester.ensureVisible(_button('Try again'));
        await tester.tap(_button('Try again'));
        await tester.pumpAndSettle();
        await _inspectRemoval(tester);
        expect(uninstaller.inspections, 2);
        expect(uninstaller.purges, [false]);
        expect(_button('Uninstall and keep data'), findsOneWidget);
        expect(outcomes, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('should revoke a reviewed removal plan when cancelled', (
      tester,
    ) async {
      final uninstaller = _Uninstaller();
      var cancelled = false;
      await _pump(
        tester,
        _Installer(),
        uninstaller: uninstaller,
        remove: true,
        onCancel: () => cancelled = true,
      );
      await _inspectRemoval(tester);
      final staleConfirmation = tester
          .widget<YsButton>(_button('Uninstall and purge data'))
          .onPressed!;
      await tester.ensureVisible(_button('Cancel'));
      await tester.tap(_button('Cancel'));
      await tester.pumpAndSettle();
      staleConfirmation();
      await tester.pumpAndSettle();
      expect(cancelled, isTrue);
      expect(uninstaller.purges, isEmpty);
      expect(_button('Uninstall and purge data'), findsNothing);
      expect(_button('Review inspection'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'should preserve transport cleanup when switching between installation and removal',
      (tester) async {
        final installer = _Installer();
        final uninstaller = _Uninstaller();
        await _pump(tester, installer, uninstaller: uninstaller);
        await _connect(tester);
        await tester.tap(_button('Accept fingerprint'));
        await tester.pumpAndSettle();
        installer.stopRelease = Completer<void>();
        installer.attempts.single.addError(
          const RemoteInstallFailed('preflight', 'Server operation stopped.'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(_button('Remove from server'));
        await tester.tap(_button('Remove from server'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(_button('Install instead'));
        await tester.tap(_button('Install instead'));
        await tester.pumpAndSettle();
        await _connect(tester);
        expect(installer.attempts, hasLength(1));
        expect(installer.connected, isFalse);
        expect(uninstaller.inspections, 0);
        installer.stopRelease!.complete();
        await tester.pumpAndSettle();
        expect(installer.attempts, hasLength(2));
        expect(installer.authenticated, isTrue);
        expect(
          _step(tester, RemoteInstallStep.preflight).state,
          YsStepState.working,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}

Future<void> _loadInter() async {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/packages/yellow_stick_ui/fonts')
      .existsSync()) {
    if (dir.parent.path == dir.path) throw StateError('no workspace fonts');
    dir = dir.parent;
  }
  final loader = FontLoader('packages/yellow_stick_ui/Inter');
  for (final name in const [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
  ]) {
    loader.addFont(
      File('${dir.path}/packages/yellow_stick_ui/fonts/$name')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await loader.load();
}
