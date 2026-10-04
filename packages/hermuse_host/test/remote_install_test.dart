import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteHostKeyTrust', () {
    const key = RemoteHostKey(
      host: 'server',
      port: 22,
      type: 'ssh-ed25519',
      fingerprint: 'SHA256:accepted',
    );
    test(
      'should require confirmation and reject a changed key on reconnect',
      () async {
        final trust = RemoteHostKeyTrust();
        var confirmations = 0;
        Future<bool> confirm(RemoteHostKey _) async {
          confirmations++;
          return true;
        }

        expect(await trust.verify(key, confirm), isTrue);
        expect(await trust.verify(key, confirm), isTrue);
        expect(confirmations, 1);
        await expectLater(
          trust.verify(
            const RemoteHostKey(
              host: 'server',
              port: 22,
              type: 'ssh-ed25519',
              fingerprint: 'SHA256:other',
            ),
            confirm,
          ),
          throwsA(isA<RemoteHostKeyChanged>()),
        );
        expect(confirmations, 1);
      },
    );

    test('should not remember a declined identity', () async {
      final trust = RemoteHostKeyTrust();
      await expectLater(
        trust.verify(key, (_) async => false),
        throwsA(isA<RemoteHostKeyRejected>()),
      );
      var asked = false;
      await trust.verify(key, (_) async {
        asked = true;
        return true;
      });
      expect(asked, isTrue);
    });
  });

  group('RemoteInstaller', () {
    late _Server server;
    setUp(() {
      server = _Server();
    });

    test(
      'should withhold SSH authentication until host-key acceptance',
      () async {
        final decision = Completer<bool>();
        final installer = server.installer();
        final installed = server
            .install(installer, confirm: (_) => decision.future)
            .toList();
        await server.keyPresented.future;
        expect(server.authenticated, 0);
        decision.complete(false);
        await expectLater(installed, throwsA(isA<RemoteHostKeyRejected>()));
        expect(server.authenticated, 0);
        expect(server.writes, isEmpty);
      },
    );

    test('should cancel a pending confirmation without authenticating or installing', () async {
      final decision = Completer<bool>();
      final installer = server.installer();
      final installed = server
          .install(installer, confirm: (_) => decision.future)
          .toList();
      final cancelled = expectLater(
        installed,
        throwsA(isA<RemoteInstallCancelled>()),
      );
      await server.keyPresented.future;
      installer.cancel();
      await cancelled;
      expect(server.authenticated, 0);
      expect(server.commands, isEmpty);
      decision.complete(true);
    });

    test(
      'should restore the firewall when fresh key authentication fails',
      () async {
        server.freshFailure = const RemoteAuthFailed.key();
        await expectLater(
          server.install(server.installer(), password: '').toList(),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (e) => e.step,
              'step',
              'firewall',
            ),
          ),
        );
        expect(server.firewallRestored, isTrue);
        expect(server.firewallCommitted, isFalse);
        expect(server.hermesStarted, isFalse);
      },
    );

    test(
      'should pin fresh firewall validation to the accepted identity',
      () async {
        server.freshFingerprint = 'SHA256:changed';
        await expectLater(
          server.install(server.installer(), password: '').toList(),
          throwsA(isA<RemoteHostKeyChanged>()),
        );
        expect(server.authenticated, 1);
        expect(server.firewallRestored, isTrue);
        expect(server.hermesStarted, isFalse);
      },
    );

    test(
      'should stop on a failing installer frame even with exit zero',
      () async {
        server.stageFrame = '{"ok":false,"stage":"repository","skipped":false,"reason":"clone failed"}';
        final events = <RemoteInstallProgress>[];
        await expectLater(
          server.install(server.installer()).forEach(events.add),
          throwsA(
            isA<RemoteInstallFailed>().having((e) => e.step, 'step', 'hermes'),
          ),
        );
        expect(
          events.whereType<RemoteInstallStepStarted>().map((e) => e.step),
          isNot(contains(RemoteInstallStep.plugin)),
        );
        expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
      },
    );

    test(
      'should reject an unrelated stage frame or a nonzero successful frame',
      () async {
        server.stageFrame = '{"ok":true,"stage":"wrong-stage","skipped":false}';
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
        server.stageFrame = '{"ok":true,"stage":"repository","skipped":false}';
        server.stageExitCode = 9;
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
        expect(server.writes, isEmpty);
      },
    );

    for (final (state, exitCode) in [
      ('docker_missing', 3),
      ('daemon_down', 4),
      ('error', 1),
    ]) {
      test('should not finish when the computer reports $state', () async {
        server.computerStates = [
          RemoteResult(
            stdout: jsonEncode({'state': state, 'detail': 'not ready'}),
            stderr: '',
            exitCode: exitCode,
          ),
        ];
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (e) => e.step,
              'step',
              'computer',
            ),
          ),
        );
        expect(server.dashboardPassword, isNull);
        expect(server.verified, isFalse);
      });
    }

    test('should wait for the image and running computer before returning verified credentials', () async {
      server.computerStates = [
        _ok('{"state":"building","detail":"Downloading image"}'),
        _ok('{"state":"stopped"}'),
        _ok('{"state":"running"}'),
      ];
      final events = await server.install(server.installer()).toList();
      final outcome = events.whereType<RemoteInstallCompleted>().single.outcome;
      expect(server.computerStates, isEmpty);
      expect(server.computerStarted, isTrue);
      expect(outcome.baseUrl, 'https://hermuse.8-8-4-4.sslip.io');
      expect(outcome.username, 'admin');
      expect(outcome.password, server.dashboardPassword);
      expect(server.verifiedPassword, outcome.password);
      expect(server.caddyCommitted, isTrue);
      expect(server.caddyRestored, isFalse);
      expect(
        server.commands.any((command) => command.contains(outcome.password)),
        isFalse,
      );
      expect(
        events.whereType<RemoteInstallLog>().any(
          (event) =>
              event.line.contains(outcome.password) ||
              event.line.contains('ssh-secret'),
        ),
        isFalse,
      );
    });

    test('should restore the previous Caddy configuration on client-side verification failure', () async {
      server.verifyFailure = const RemoteInstallFailed(
        'verify',
        'TLS not ready',
      );
      await expectLater(
        server.install(server.installer()).toList(),
        throwsA(
          isA<RemoteInstallFailed>().having(
            (e) => e.message,
            'remedy',
            contains('provider firewall'),
          ),
        ),
      );
      expect(server.caddyRestored, isTrue);
      expect(server.caddyCommitted, isFalse);
    });

    test(
      'should reject traversal in the plugin bundle before opening SSH',
      () async {
        final installer = server.installer();
        await expectLater(
          installer
              .run(
                host: 'server',
                password: 'ssh-secret',
                onHostKey: (_) async => true,
                pluginBundle: {..._bundle, '../outside': Uint8List(0)},
              )
              .toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
        expect(server.authenticated, 0);
        expect(server.writes, isEmpty);
      },
    );

    test('should stop polling and close transport when cancelled while image builds', () async {
      server.computerStates = [_ok('{"state":"building"}')];
      final waiting = Completer<void>();
      final installer = server.installer(
        sleep: (_) {
          waiting.complete();
          return Completer<void>().future;
        },
      );
      final events = <RemoteInstallProgress>[];
      final installation = server.install(installer).forEach(events.add);
      final cancelled = expectLater(
        installation,
        throwsA(isA<RemoteInstallCancelled>()),
      );
      await waiting.future;
      installer.cancel();
      await cancelled;
      expect(server.closed, isTrue);
      expect(
        events.whereType<RemoteInstallStepStarted>().map((e) => e.step),
        isNot(contains(RemoteInstallStep.dashboard)),
      );
    });
  });

  group('Existing local connection', () {
    test('connects an unmanaged plugin without running provisioning or installer verification', () async {
      final server = _Server()..foreignPath = true;
      final events = await server
          .installer()
          .connectLocal(shell: _LocalServerConnection(server))
          .toList();
      final outcome = events.whereType<RemoteInstallCompleted>().single.outcome;
      expect(outcome.baseUrl, 'http://127.0.0.1:9119');
      expect(outcome.sessionToken, server.loopbackToken);
      expect(
        events.whereType<RemoteInstallStepStarted>().map((event) => event.step),
        [
          RemoteInstallStep.connect,
          RemoteInstallStep.dashboard,
          RemoteInstallStep.verify,
        ],
      );
      expect(server.packageInstalls, 0);
      expect(server.manifestRequests, 0);
      expect(server.hermesStarted, isFalse);
      expect(server.computerStarted, isFalse);
      expect(server.passwordChanges, 0);
      expect(server.publicUrlChanges, 0);
      expect(server.migrationCalls, 0);
      expect(server.writes, isEmpty);
      expect(server.verified, isFalse);
    });

    test('a refused connection returns no credential and never falls back to install', () async {
      final server = _Server()..connectionRefused = true;
      final events = <RemoteInstallProgress>[];
      await expectLater(
        server
            .installer()
            .connectLocal(shell: _LocalServerConnection(server))
            .forEach(events.add),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
      expect(server.packageInstalls, 0);
      expect(server.manifestRequests, 0);
      expect(server.hermesStarted, isFalse);
      expect(server.computerStarted, isFalse);
      expect(server.writes, isEmpty);
    });
    test(
      'connection retains exclusivity and cancellation withholds completion',
      () async {
        final server = _Server()..connectionGate = Completer<RemoteResult>();
        final installer = server.installer();
        final events = <RemoteInstallProgress>[];
        final stopped = expectLater(
          installer
              .connectLocal(shell: _LocalServerConnection(server))
              .forEach(events.add),
          throwsA(isA<RemoteInstallCancelled>()),
        );
        await server.connectionObserved.future;
        expect(
          () => installer.runLocal(
            shell: _LocalServerConnection(server),
            pluginBundle: _bundle,
          ),
          throwsStateError,
        );
        await installer.cancel();
        await stopped;
        server.connectionGate!.complete(_ok(server.loopbackToken));
        expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
        expect(server.packageInstalls, 0);
        expect(server.computerStarted, isFalse);
      },
    );
  });

  group('Canonical local provisioning', () {
    test(
      'shares canonical runtime, plugin, computer and service stages with SSH',
      () async {
        final remote = _Server();
        final local = _Server();
        final remoteEvents = await remote.install(remote.installer()).toList();
        final localEvents = await local
            .installer()
            .runLocal(
              shell: _LocalServerConnection(local),
              pluginBundle: _bundle,
              legacyHome: '/home/desktop/.hermes',
            )
            .toList();
        const core = {
          RemoteInstallStep.hermesUser,
          RemoteInstallStep.hermes,
          RemoteInstallStep.plugin,
          RemoteInstallStep.computer,
          RemoteInstallStep.dashboard,
          RemoteInstallStep.verify,
        };
        List<RemoteInstallStep> stages(List<RemoteInstallProgress> events) =>
            events
                .whereType<RemoteInstallStepFinished>()
                .map((event) => event.step)
                .where(core.contains)
                .toList();
        expect(stages(localEvents), stages(remoteEvents));
        expect(local.forcedRepin, isTrue);
        expect(local.computerPrepared, isTrue);
        expect(local.computerStarted, isTrue);
        expect(
          local.writes.values.map(utf8.decode),
          remote.writes.values.map(utf8.decode),
        );
        final outcome = localEvents
            .whereType<RemoteInstallCompleted>()
            .single
            .outcome;
        expect(outcome.baseUrl, 'http://127.0.0.1:9119');
        expect(outcome.sessionToken, local.loopbackToken);
        expect(outcome.username, isEmpty);
        expect(outcome.password, isEmpty);
        expect(outcome.webUrl, isNull);
        expect(local.connections, 0);
        expect(local.passwordChanges, 0);
        expect(local.publicUrlChanges, 0);
        expect(local.publicAddressLookups, 0);
        expect(local.caddyConfigurations, isEmpty);
        expect(local.webDeploys, 0);
        expect(local.firewallCommitted, isFalse);
        expect(
          localEvents.whereType<RemoteInstallStepStarted>().map(
            (event) => event.step,
          ),
          isNot(
            anyOf(
              contains(RemoteInstallStep.firewall),
              contains(RemoteInstallStep.https),
              contains(RemoteInstallStep.web),
            ),
          ),
        );
      },
    );

    test(
      'leaves separate legacy data untouched when reusing canonical service',
      () async {
        final server = _Server()..seedHealthy();
        server.legacyInventory = {
          'sourceHome': '/home/desktop/.hermes',
          'revision': 'legacy-revision',
          'summary': 'Separate installation must be preserved.',
        };
        await server
            .installer()
            .runLocal(
              shell: _LocalServerConnection(server),
              pluginBundle: _bundle,
              legacyHome: '/home/desktop/.hermes',
            )
            .toList();
        expect(server.migrationCalls, 0);
        expect(server.migrationApplied, isFalse);
        expect(server.passwordChanges, 0);
        expect(server.writes, isEmpty);
      },
    );

    test(
      'reuses canonical setup without rotating remote login or local token',
      () async {
        final server = _Server()..seedHealthy();
        server.webState = 'ready';
        final installer = server.installer();
        Future<RemoteInstallOutcome> install() async {
          final events = await installer
              .runLocal(
                shell: _LocalServerConnection(server),
                pluginBundle: _bundle,
              )
              .toList();
          return events.whereType<RemoteInstallCompleted>().single.outcome;
        }

        final first = await install();
        final second = await install();
        expect(first.sessionToken, second.sessionToken);
        expect(server.passwordChanges, 0);
        expect(server.packageInstalls, 0);
        expect(server.manifestRequests, 0);
        expect(server.writes, isEmpty);
        expect(server.publicUrlChanges, 0);
        expect(server.publicAddressLookups, 0);
        expect(server.webDeploys, 0);
        expect(server.webState, 'ready');
        expect(server.caddyConfigurations, isEmpty);
      },
    );

    for (final revision in [null, 'stale-revision']) {
      test(
        'refuses legacy data before install mutations with revision $revision',
        () async {
          final server = _Server()
            ..legacyInventory = {
              'sourceHome': '/home/desktop/.hermes',
              'revision': 'current-revision',
              'summary': 'Existing sessions and credentials; verified backup required.',
            };
          await expectLater(
            server
                .installer()
                .runLocal(
                  shell: _LocalServerConnection(server),
                  pluginBundle: _bundle,
                  legacyHome: '/home/desktop/.hermes',
                  migrationRevision: revision,
                )
                .toList(),
            throwsA(
              isA<RemoteInstallFailed>().having(
                (e) => e.step,
                'step',
                'preflight',
              ),
            ),
          );
          expect(server.packageInstalls, 0);
          expect(server.hermesStarted, isFalse);
          expect(server.writes, isEmpty);
          expect(server.migrationApplied, isFalse);
        },
      );
    }

    test(
      'confirmed local migration runs before the shared runtime stage',
      () async {
        final server = _Server()
          ..legacyInventory = {
            'sourceHome': '/home/desktop/.hermes',
            'revision': 'current-revision',
            'summary': 'Verified backup of existing data.',
          };
        await server
            .installer()
            .runLocal(
              shell: _LocalServerConnection(server),
              pluginBundle: _bundle,
              legacyHome: '/home/desktop/.hermes',
              migrationRevision: 'current-revision',
            )
            .toList();
        expect(server.migrationApplied, isTrue);
        expect(server.migrationBeforeRuntime, isTrue);
        expect(server.connections, 0);
      },
    );

    test(
      'SSH requires migration approval before any installation mutation',
      () async {
        final server = _Server()
          ..legacyInventory = {
            'sourceHome': '/root/.hermes',
            'revision': 'current-revision',
            'summary':
                'Existing sessions and credentials; verified backup required.',
          };
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
        expect(server.packageInstalls, 0);
        expect(server.hermesStarted, isFalse);
        expect(server.migrationApplied, isFalse);
      },
    );

    test('confirmed SSH migration precedes runtime installation', () async {
      final server = _Server()
        ..legacyInventory = {
          'sourceHome': '/root/.hermes',
          'revision': 'current-revision',
          'summary': 'Verified backup of existing data.',
        };
      var approved = false;
      await server
          .installer()
          .run(
            host: 'server',
            pluginBundle: _bundle,
            onHostKey: (_) async => true,
            onMigration: (inventory) async {
              expect(server.packageInstalls, 0);
              expect(server.hermesStarted, isFalse);
              expect(inventory.revision, 'current-revision');
              return approved = true;
            },
          )
          .toList();
      expect(approved, isTrue);
      expect(server.migrationApplied, isTrue);
      expect(server.migrationBeforeRuntime, isTrue);
    });
  });

  group('Remote installation inventory', () {
    test(
      'fresh setup repairs each stage once and hands off the verified password',
      () async {
        final server = _Server();
        final events = await server.install(server.installer()).toList();
        final finished = events.whereType<RemoteInstallStepFinished>().toList();
        expect(
          finished.map((event) => event.step),
          RemoteInstallStep.values.where(
            (step) => step != RemoteInstallStep.web,
          ),
        );
        expect(finished.where((event) => event.previouslyCompleted), isEmpty);
        expect(server.packageInstalls, 1);
        expect(server.passwordChanges, 1);
        expect(server.firewallCommitted, isTrue);
        expect(server.verifiedPassword, server.dashboardPassword);
      },
    );

    test('fully healthy restart prechecks all proven stages before repairs without reinstalling', () async {
      final server = _Server()..seedHealthy();
      final events = await server.install(server.installer()).toList();
      final found = events
          .whereType<RemoteInstallStepFinished>()
          .where((event) => event.previouslyCompleted)
          .map((event) => event.step)
          .toList();
      expect(found, [
        RemoteInstallStep.firewall,
        RemoteInstallStep.hermesUser,
        RemoteInstallStep.hermes,
        RemoteInstallStep.plugin,
        RemoteInstallStep.computer,
        RemoteInstallStep.scheduler,
        RemoteInstallStep.https,
      ]);
      expect(
        events.whereType<RemoteInstallStepStarted>().map((event) => event.step),
        [
          RemoteInstallStep.connect,
          RemoteInstallStep.preflight,
          RemoteInstallStep.dashboard,
          RemoteInstallStep.verify,
        ],
      );
      expect(
        events
            .whereType<RemoteInstallStepFinished>()
            .map((event) => event.step)
            .toSet(),
        RemoteInstallStep.values.toSet()..remove(RemoteInstallStep.web),
      );
      expect(server.packageInstalls, 0);
      expect(server.hermesStarted, isFalse);
      expect(server.writes, isEmpty);
      expect(server.schedulerConfigurations, 0);
      expect(server.computerStarted, isFalse);
      expect(server.computerPrepared, isFalse);
      expect(server.firewallCommitted, isFalse);
      expect(server.caddyCommitted, isFalse);
      expect(server.caddyRestored, isFalse);
      expect(
        server.passwordChanges,
        1,
      ); // Hash-only account still needs handoff.
      expect(server.verified, isTrue);
      final firstRepair = events.indexWhere(
        (event) =>
            event is RemoteInstallStepStarted &&
            event.step == RemoteInstallStep.dashboard,
      );
      expect(
        events
            .take(firstRepair)
            .whereType<RemoteInstallStepFinished>()
            .where((event) => event.previouslyCompleted)
            .map((event) => event.step),
        found,
      );
    });

    test(
      'a missing scheduler on a healthy server is reported and repaired alone',
      () async {
        final server = _Server()..seedHealthy();
        server.health[RemoteInstallStep.scheduler] = false;
        final events = await server.install(server.installer()).toList();
        expect(
          events
              .whereType<RemoteInstallStepFinished>()
              .where((event) => event.previouslyCompleted)
              .map((event) => event.step),
          isNot(contains(RemoteInstallStep.scheduler)),
        );
        expect(
          events.whereType<RemoteInstallStepStarted>().map(
            (event) => event.step,
          ),
          [
            RemoteInstallStep.connect,
            RemoteInstallStep.preflight,
            RemoteInstallStep.dashboard,
            RemoteInstallStep.scheduler,
            RemoteInstallStep.verify,
          ],
        );
        expect(server.schedulerConfigurations, 1);
        expect(server.packageInstalls, 0);
        expect(server.hermesStarted, isFalse);
        expect(server.computerPrepared, isFalse);
        expect(server.writes, isEmpty);
        final configure = server.commands.indexWhere(
          (command) =>
              command.contains('systemctl restart hermuse-gateway.service'),
        );
        expect(
          server.commands
              .skip(configure + 1)
              .any((command) => command.contains('ticker_heartbeat')),
          isTrue,
          reason: 'the repaired scheduler must be proven healthy',
        );
      },
    );

    test('a failed scheduler repair stops setup before verification', () async {
      final server = _Server()
        ..seedHealthy()
        ..failedRepair = RemoteInstallStep.scheduler;
      server.health[RemoteInstallStep.scheduler] = false;
      final events = <RemoteInstallProgress>[];
      await expectLater(
        server.install(server.installer()).forEach(events.add),
        throwsA(
          isA<RemoteInstallFailed>().having(
            (error) => error.step,
            'step',
            'scheduler',
          ),
        ),
      );
      expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
      expect(server.verified, isFalse);
    });

    test('a repaired plugin restarts an otherwise healthy scheduler', () async {
      final server = _Server()..seedHealthy();
      server.health[RemoteInstallStep.plugin] = false;
      final events = await server.install(server.installer()).toList();
      expect(
        events.whereType<RemoteInstallStepStarted>().map((event) => event.step),
        contains(RemoteInstallStep.scheduler),
      );
      expect(server.schedulerConfigurations, 1);
    });

    test(
      'stale plugin repairs its bundle without rebuilding a healthy computer',
      () async {
        final server = _Server()..seedHealthy();
        server.health[RemoteInstallStep.plugin] = false;
        final events = await server.install(server.installer()).toList();
        expect(
          server.writes.keys.map((path) => path.split('/').last).toSet(),
          _bundle.keys.toSet(),
        );
        expect(server.hermesStarted, isFalse);
        expect(server.computerPrepared, isFalse);
        expect(server.computerStarted, isFalse);
        expect(
          events
              .whereType<RemoteInstallStepFinished>()
              .singleWhere((event) => event.step == RemoteInstallStep.plugin)
              .previouslyCompleted,
          isFalse,
        );
        expect(
          events
              .whereType<RemoteInstallStepFinished>()
              .singleWhere((event) => event.step == RemoteInstallStep.computer)
              .previouslyCompleted,
          isFalse,
        );
      },
    );

    test(
      'owned stale source is force-repinned without replacing a current plugin',
      () async {
        final server = _Server()..seedHealthy();
        server.health[RemoteInstallStep.hermes] = false;
        final events = await server.install(server.installer()).toList();
        expect(server.hermesStarted, isTrue);
        expect(server.forcedRepin, isTrue);
        expect(server.writes, isEmpty);
        expect(server.computerPrepared, isFalse);
        expect(
          events.whereType<RemoteInstallCompleted>().single.outcome.password,
          server.verifiedPassword,
        );
      },
    );

    test('incomplete computer repairs only computer preparation and current-session readiness', () async {
      final server = _Server()..seedHealthy();
      server.health[RemoteInstallStep.computer] = false;
      await server.install(server.installer()).drain<void>();
      expect(server.computerPrepared, isTrue);
      expect(server.computerStarted, isTrue);
      expect(server.hermesStarted, isFalse);
      expect(server.writes, isEmpty);
      expect(server.packageInstalls, 0);
    });

    test(
      'an unrelated target route blocks before the first mutating operation',
      () async {
        final server = _Server()..seedHealthy();
        server.caddyConflict = true;
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (error) => error.step,
              'step',
              'https',
            ),
          ),
        );
        expect(server.packageInstalls, 0);
        expect(server.passwordChanges, 0);
        expect(server.hermesStarted, isFalse);
        expect(server.writes, isEmpty);
        expect(server.caddyCommitted, isFalse);
        expect(server.caddyRestored, isFalse);
      },
    );

    test(
      'unowned managed paths stop before prerequisites or account replacement',
      () async {
        final server = _Server()..foreignPath = true;
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(isA<RemoteInstallFailed>()),
        );
        expect(server.packageInstalls, 0);
        expect(server.hermesStarted, isFalse);
        expect(server.passwordChanges, 0);
        expect(server.writes, isEmpty);
      },
    );

    test(
      'malformed inventory is not permission to reinstall blindly',
      () async {
        final server = _Server()..malformedInventory = true;
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (error) => error.step,
              'step',
              'preflight',
            ),
          ),
        );
        expect(server.packageInstalls, 0);
        expect(server.passwordChanges, 0);
        expect(server.writes, isEmpty);
      },
    );

    test(
      'a zero-exit repair with unhealthy postconditions cannot finish',
      () async {
        final server = _Server()..failedRepair = RemoteInstallStep.plugin;
        final events = <RemoteInstallProgress>[];
        await expectLater(
          server.install(server.installer()).forEach(events.add),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (error) => error.step,
              'step',
              'plugin',
            ),
          ),
        );
        expect(
          events.whereType<RemoteInstallStepFinished>().map(
            (event) => event.step,
          ),
          isNot(contains(RemoteInstallStep.plugin)),
        );
        expect(server.passwordChanges, 0);
      },
    );

    test(
      'firewall repair cannot commit rules that fail the post-reconnect check',
      () async {
        final server = _Server()..firewallRepairIncomplete = true;
        await expectLater(
          server.install(server.installer()).toList(),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (error) => error.step,
              'step',
              'firewall',
            ),
          ),
        );
        expect(server.connections, 2);
        expect(server.firewallCommitted, isFalse);
        expect(server.firewallRestored, isTrue);
      },
    );
    test('reopening a completed fresh setup discovers remote state without repeating installers', () async {
      final server = _Server();
      final installer = server.installer();
      final first = await server.install(installer).toList();
      final firstPassword = first
          .whereType<RemoteInstallCompleted>()
          .single
          .outcome
          .password;
      final uploaded = server.writes.keys.toSet();
      final second = await server.install(installer).toList();
      expect(server.packageInstalls, 1);
      expect(server.manifestRequests, 1);
      expect(server.writes.keys.toSet(), uploaded);
      expect(server.passwordChanges, 2);
      expect(
        second.whereType<RemoteInstallStepStarted>().map((event) => event.step),
        [
          RemoteInstallStep.connect,
          RemoteInstallStep.preflight,
          RemoteInstallStep.dashboard,
          RemoteInstallStep.verify,
        ],
      );
      expect(
        second.whereType<RemoteInstallCompleted>().single.outcome.password,
        isNot(firstPassword),
      );
      expect(server.verifiedPassword, server.dashboardPassword);
    });

    test('cancelling read-only inventory prevents repairs and ignores its late result', () async {
      final server = _Server()..inventoryGate = Completer<RemoteResult>();
      final installer = server.installer();
      final events = <RemoteInstallProgress>[];
      final attempt = server.install(installer).forEach(events.add);
      final cancelled = expectLater(
        attempt,
        throwsA(isA<RemoteInstallCancelled>()),
      );
      await server.inventoryObserved.future;
      await installer.cancel();
      await cancelled;
      server.inventoryGate!.complete(_ok('HERMUSE_HEALTH_V1:ready'));
      expect(server.closed, isTrue);
      expect(server.packageInstalls, 0);
      expect(server.passwordChanges, 0);
      expect(server.writes, isEmpty);
      expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
      expect(
        events.whereType<RemoteInstallStepFinished>().map(
          (event) => event.step,
        ),
        [RemoteInstallStep.connect],
      );
    });
  });

  group('Remote web app publishing', () {
    test('selected on a fresh server deploys the version-matched image between dashboard and HTTPS', () async {
      final server = _Server();
      final events = await server
          .install(server.installer(), webApp: true)
          .toList();
      final started = events
          .whereType<RemoteInstallStepStarted>()
          .map((event) => event.step)
          .toList();
      expect(
        started.indexOf(RemoteInstallStep.web),
        started.indexOf(RemoteInstallStep.scheduler) + 1,
      );
      expect(
        started.indexOf(RemoteInstallStep.scheduler),
        started.indexOf(RemoteInstallStep.dashboard) + 1,
      );
      expect(
        started.indexOf(RemoteInstallStep.https),
        started.indexOf(RemoteInstallStep.web) + 1,
      );
      final outcome = events.whereType<RemoteInstallCompleted>().single.outcome;
      expect(outcome.webUrl, _webUrl);
      expect(server.verifiedWebUrl, _webUrl);
      expect(server.webPulls, 1);
      expect(server.webDeploys, 1);
      expect(
        server.commands.where((command) => command.contains('docker pull')),
        everyElement(contains('ghcr.io/yellow-stick/hermuse-web:0.3.0')),
      );
      expect(
        server.caddyConfigurations.single,
        allOf(
          contains('app.hermuse.8-8-4-4.sslip.io {'),
          contains('reverse_proxy 127.0.0.1:9120'),
        ),
      );
      final token = server.webToken!;
      expect(token.length, greaterThanOrEqualTo(24));
      expect(
        server.commands.any((command) => command.contains(token)),
        isFalse,
      );
      expect(
        events.whereType<RemoteInstallLog>().any(
          (event) => event.line.contains(token),
        ),
        isFalse,
      );
    });

    test(
      'not selected on a fresh server adds no container, route or address',
      () async {
        final server = _Server();
        final events = await server.install(server.installer()).toList();
        expect(
          events.whereType<RemoteInstallStepStarted>().map(
            (event) => event.step,
          ),
          isNot(contains(RemoteInstallStep.web)),
        );
        expect(
          events.whereType<RemoteInstallStepFinished>().map(
            (event) => event.step,
          ),
          isNot(contains(RemoteInstallStep.web)),
        );
        expect(server.webPulls, 0);
        expect(server.webDeploys, 0);
        expect(
          server.caddyConfigurations.single,
          isNot(contains('reverse_proxy 127.0.0.1:9120')),
        );
        expect(
          events.whereType<RemoteInstallCompleted>().single.outcome.webUrl,
          isNull,
        );
      },
    );

    test('not selected keeps and reports an owned healthy deployment without touching it', () async {
      final server = _Server()
        ..seedHealthy()
        ..webState = 'ready';
      final events = await server.install(server.installer()).toList();
      expect(
        events
            .whereType<RemoteInstallStepFinished>()
            .singleWhere((event) => event.step == RemoteInstallStep.web)
            .previouslyCompleted,
        isTrue,
      );
      expect(
        events.whereType<RemoteInstallStepStarted>().map((event) => event.step),
        isNot(contains(RemoteInstallStep.web)),
      );
      expect(server.webPulls, 0);
      expect(server.webDeploys, 0);
      expect(server.caddyConfigurations, isEmpty);
      expect(
        server.caddyHealthChecks,
        everyElement(contains('reverse_proxy 127.0.0.1:9120')),
      );
      expect(
        events.whereType<RemoteInstallCompleted>().single.outcome.webUrl,
        _webUrl,
      );
    });

    test('not selected leaves an unhealthy owned deployment and its route unchanged and unreported', () async {
      final server = _Server()..webState = 'repair';
      final events = await server.install(server.installer()).toList();
      expect(server.webDeploys, 0);
      expect(
        server.caddyConfigurations.single,
        contains('reverse_proxy 127.0.0.1:9120'),
      );
      expect(
        events.whereType<RemoteInstallCompleted>().single.outcome.webUrl,
        isNull,
      );
    });

    test(
      'selected with a foreign hermuse-web container fails before any mutation',
      () async {
        final server = _Server()..webForeign = true;
        await expectLater(
          server.install(server.installer(), webApp: true).toList(),
          throwsA(
            isA<RemoteInstallFailed>().having((e) => e.step, 'step', 'web'),
          ),
        );
        expect(server.packageInstalls, 0);
        expect(server.hermesStarted, isFalse);
        expect(server.passwordChanges, 0);
        expect(server.writes, isEmpty);
        expect(server.webPulls, 0);
        expect(server.webDeploys, 0);
      },
    );

    test(
      'selected with an unreachable registry stops before replacing anything',
      () async {
        final server = _Server()..webPullFails = true;
        await expectLater(
          server.install(server.installer(), webApp: true).toList(),
          throwsA(
            isA<RemoteInstallFailed>()
                .having((e) => e.step, 'step', 'web')
                .having(
                  (e) => e.message,
                  'message',
                  contains('ghcr.io/yellow-stick/hermuse-web:0.3.0'),
                ),
          ),
        );
        expect(server.webDeploys, 0);
        expect(server.caddyConfigurations, isEmpty);
      },
    );

    test(
      'selected without a bundled plugin version fails before SSH',
      () async {
        final server = _Server();
        await expectLater(
          server
              .install(server.installer(), webApp: true, bundle: _bundle)
              .toList(),
          throwsA(
            isA<RemoteInstallFailed>().having((e) => e.step, 'step', 'web'),
          ),
        );
        expect(server.authenticated, 0);
      },
    );
  });

  group('UFW additive rule detection', () {
    test('should preserve unrelated rules when both address families already allow required ports', () {
      expect(ufwAllowsPorts(_activeFirewall, {22, 80, 443}), isTrue);
      expect(ufwAllowsPorts(_activeFirewall, {2222, 80, 443}), isFalse);
    });
    test('should not mistake outbound or source-restricted access for a public inbound rule', () {
      expect(
        ufwAllowsPorts(
          _activeFirewall.replaceAll(
            'ALLOW IN    Anywhere',
            'ALLOW OUT   Anywhere',
          ),
          {22},
        ),
        isFalse,
      );
      expect(
        ufwAllowsPorts(
          _activeFirewall.replaceAll(
            'ALLOW IN    Anywhere',
            'ALLOW IN    10.0.0.0/8',
          ),
          {22},
        ),
        isFalse,
      );
    });
    test('should not skip a disabled firewall or an earlier deny', () {
      expect(
        ufwAllowsPorts(
          _activeFirewall.replaceFirst('Status: active', 'Status: inactive'),
          {22},
        ),
        isFalse,
      );
      expect(
        ufwAllowsPorts(
          _activeFirewall.replaceFirst(
            '22/tcp',
            '22/tcp     DENY IN     Anywhere\n22/tcp',
          ),
          {22},
        ),
        isFalse,
      );
    });
  });

  group('sslipDomain', () {
    test('should derive DNS for a public IPv4 address', () {
      expect(sslipDomain('8.8.4.4'), 'hermuse.8-8-4-4.sslip.io');
    });
    test('should reject private, malformed and shell-injected addresses', () {
      for (final value in [
        '127.0.0.1',
        '10.0.0.1',
        '172.16.0.2',
        '192.168.1.1',
        '100.64.1.1',
        '1.2.3.256',
        '01.2.3.4',
        '1.2.3.4;id',
        '::1',
      ]) {
        expect(
          () => sslipDomain(value),
          throwsA(isA<RemoteInstallFailed>()),
          reason: value,
        );
      }
    });
  });

  group('verifyRemoteDashboard', () {
    const outcome = RemoteInstallOutcome(
      baseUrl: 'https://hermuse.8-8-4-4.sslip.io',
      username: 'admin',
      password: 'dashboard-secret',
    );
    test('should reject an unprotected public dashboard before sending the password', () async {
      var loginAttempted = false;
      final client = MockClient((request) async {
        if (request.url.path == '/auth/password-login') loginAttempted = true;
        return http.Response('{"version":"0.21.5","auth_required":false}', 200);
      });
      await expectLater(
        verifyRemoteDashboard(outcome, RemoteCancellation(), client: client),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(loginAttempted, isFalse);
    });

    test('should require a login cookie, registered jobs and running computer over HTTPS', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return _dashboardResponse(request);
      });
      await verifyRemoteDashboard(
        outcome,
        RemoteCancellation(),
        client: client,
      );
      final login = requests.singleWhere(
        (request) => request.url.path == '/auth/password-login',
      );
      expect(jsonDecode(login.body), {
        'provider': 'basic',
        'username': 'admin',
        'password': 'dashboard-secret',
      });
      expect(
        requests.last.headers['cookie'],
        contains('hermes_session=verified'),
      );
      expect(
        requests.every(
          (request) =>
              request.url.scheme == 'https' && !request.followRedirects,
        ),
        isTrue,
      );
    });

    test(
      'authenticates private loopback with token without password login',
      () async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/api/plugins/hermuse/files' &&
              request.headers['x-hermes-session-token'] == 'local-token') {
            return http.Response('{"files":[]}', 200);
          }
          return _dashboardResponse(request);
        });
        await verifyRemoteDashboard(
          const RemoteInstallOutcome(
            baseUrl: 'http://127.0.0.1:9119',
            username: '',
            password: '',
            sessionToken: 'local-token',
          ),
          RemoteCancellation(),
          client: client,
        );
        expect(
          requests.any((r) => r.url.path == '/auth/password-login'),
          isFalse,
        );
        expect(requests.last.headers['x-hermes-session-token'], 'local-token');
        expect(
          requests.every(
            (r) => r.url.host == '127.0.0.1' && !r.followRedirects,
          ),
          isTrue,
        );
      },
    );

    test('never sends local token to noncanonical HTTP origin', () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return _dashboardResponse(request);
      });
      await expectLater(
        verifyRemoteDashboard(
          const RemoteInstallOutcome(
            baseUrl: 'http://example.com:9119',
            username: '',
            password: '',
            sessionToken: 'local-token',
          ),
          RemoteCancellation(),
          client: client,
        ),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(requests, 0);
    });

    test('should not accept a login response without a cookie', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/auth/password-login') {
          return http.Response('{}', 200);
        }
        return _dashboardResponse(request);
      });
      await expectLater(
        verifyRemoteDashboard(outcome, RemoteCancellation(), client: client),
        throwsA(
          isA<RemoteInstallFailed>().having(
            (e) => e.message,
            'error',
            contains('session'),
          ),
        ),
      );
    });

    test(
      'should reject a partial computer setup through the authenticated API',
      () async {
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/computer/status')) {
            return http.Response('{"state":"building"}', 200);
          }
          return _dashboardResponse(request);
        });
        await expectLater(
          verifyRemoteDashboard(outcome, RemoteCancellation(), client: client),
          throwsA(
            isA<RemoteInstallFailed>().having(
              (e) => e.message,
              'error',
              contains('computer'),
            ),
          ),
        );
      },
    );

    const published = RemoteInstallOutcome(
      baseUrl: 'https://hermuse.8-8-4-4.sslip.io',
      username: 'admin',
      password: 'dashboard-secret',
      webUrl: _webUrl,
    );

    test('should prove the web app relay reaches the dashboard without its credential', () async {
      final web = <http.Request>[];
      final client = MockClient((request) async {
        if (request.url.host != 'app.hermuse.8-8-4-4.sslip.io') {
          return _dashboardResponse(request);
        }
        web.add(request);
        return _webResponse(request);
      });
      await verifyRemoteDashboard(
        published,
        RemoteCancellation(),
        client: client,
      );
      expect(web.map((request) => request.url.path), [
        '/relay/health',
        '/relay/resolve',
        '/hermes/up-1/api/status',
      ]);
      expect(
        web[1].url.queryParameters['url'],
        'https://hermuse.8-8-4-4.sslip.io',
      );
      for (final request in web) {
        expect(request.url.scheme, 'https');
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('cookie'), isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(request.body, isNot(contains('dashboard-secret')));
      }
    });

    for (final (path, status) in [
      ('/relay/resolve', 404),
      ('/hermes/up-1/api/status', 502),
    ]) {
      test(
        'should fail naming the web address when $path answers $status',
        () async {
          final client = MockClient((request) async {
            if (request.url.host != 'app.hermuse.8-8-4-4.sslip.io') {
              return _dashboardResponse(request);
            }
            if (request.url.path == path) {
              return http.Response('{"error":"not registered"}', status);
            }
            return _webResponse(request);
          });
          await expectLater(
            verifyRemoteDashboard(
              published,
              RemoteCancellation(),
              client: client,
            ),
            throwsA(
              isA<RemoteInstallFailed>().having(
                (e) => e.message,
                'message',
                contains(_webUrl),
              ),
            ),
          );
        },
      );
    }
  });
}

http.Response _webResponse(http.Request request) => switch (request.url.path) {
  '/relay/health' => http.Response('{"ok":true}', 200),
  '/relay/resolve' => http.Response('{"id":"up-1","label":null}', 200),
  '/hermes/up-1/api/status' => http.Response(
    '{"version":"0.21.5","auth_required":true}',
    200,
  ),
  _ => throw StateError('Unexpected web app request: ${request.url}'),
};

final _bundle = <String, Uint8List>{
  'plugin.yaml': Uint8List.fromList(utf8.encode('name: hermuse\n')),
  '__init__.py': Uint8List.fromList(utf8.encode('# bundled plugin\n')),
};

final _versionedBundle = <String, Uint8List>{
  ..._bundle,
  'plugin.yaml': Uint8List.fromList(
    utf8.encode('name: hermuse\nversion: "0.3.0"\n'),
  ),
};

const _webUrl = 'https://app.hermuse.8-8-4-4.sslip.io';

RemoteResult _ok([String stdout = '']) =>
    RemoteResult(stdout: stdout, stderr: '', exitCode: 0);

const _activeFirewall = '''Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), disabled (routed)
To                         Action      From
--                         ------      ----
22/tcp                     ALLOW IN    Anywhere
80/tcp                     ALLOW IN    Anywhere
443/tcp                    ALLOW IN    Anywhere
8443/tcp                   ALLOW IN    10.0.0.0/8
22/tcp (v6)                ALLOW IN    Anywhere (v6)
80/tcp (v6)                ALLOW IN    Anywhere (v6)
443/tcp (v6)               ALLOW IN    Anywhere (v6)
''';

final class _Server implements RemoteShell {
  final keyPresented = Completer<void>();
  final commands = <String>[];
  final writes = <String, Uint8List>{};
  Object? freshFailure;
  Object? verifyFailure;
  String? freshFingerprint;
  String stageFrame = '{"ok":true,"stage":"repository","skipped":false}';
  int stageExitCode = 0;
  int authenticated = 0;
  int connections = 0;
  bool firewallRestored = false;
  bool firewallCommitted = false;
  bool caddyRestored = false;
  bool caddyCommitted = false;
  bool hermesStarted = false;
  bool computerStarted = false;
  bool verified = false;
  bool computerPrepared = false;
  bool forcedRepin = false;
  bool caddyConflict = false;
  bool foreignPath = false;
  bool connectionRefused = false;
  Completer<RemoteResult>? connectionGate;
  final connectionObserved = Completer<void>();
  bool malformedInventory = false;
  bool firewallRepairIncomplete = false;
  bool firewallActive = false;
  bool prerequisitesReady = false;
  int packageInstalls = 0;
  int passwordChanges = 0;
  int manifestRequests = 0;
  int publicUrlChanges = 0;
  int publicAddressLookups = 0;
  int schedulerConfigurations = 0;
  final loopbackToken = List.filled(64, 't').join();
  Map<String, Object?>? legacyInventory;
  int migrationCalls = 0;
  bool migrationApplied = false;
  bool migrationBeforeRuntime = false;
  Completer<RemoteResult>? inventoryGate;
  final inventoryObserved = Completer<void>();
  RemoteInstallStep? failedRepair;
  final health = <RemoteInstallStep, bool>{};

  /// Inventory frame of the web app container: absent, repair or ready.
  String webState = 'absent';
  bool webForeign = false;
  bool webPullFails = false;
  int webPulls = 0;
  int webDeploys = 0;
  String? webToken;
  String? verifiedWebUrl;
  final caddyHealthChecks = <String>[];
  final caddyConfigurations = <String>[];

  void seedHealthy() {
    prerequisitesReady = true;
    firewallActive = true;
    for (final step in RemoteInstallStep.values) {
      health[step] = true;
    }
  }

  final _shells = <_ServerConnection>[];
  bool get closed => _shells.every((shell) => shell.closed);
  String? dashboardPassword;
  String? verifiedPassword;
  List<RemoteResult> computerStates = [
    _ok('{"state":"stopped"}'),
    _ok('{"state":"running"}'),
  ];

  RemoteInstaller installer({Future<void> Function(Duration)? sleep}) =>
      RemoteInstaller(
        connect: connect,
        verifyDashboard: (outcome, cancellation) async {
          if (verifyFailure case final failure?) throw failure;
          verified = true;
          verifiedPassword = outcome.password;
          verifiedWebUrl = outcome.webUrl;
        },
        sleep: sleep ?? (_) async {},
      );

  Stream<RemoteInstallProgress> install(
    RemoteInstaller installer, {
    Future<bool> Function(RemoteHostKey)? confirm,
    String password = 'ssh-secret',
    bool webApp = false,
    Map<String, Uint8List>? bundle,
  }) => installer.run(
    host: 'server',
    password: password,
    pluginBundle: bundle ?? (webApp ? _versionedBundle : _bundle),
    onHostKey: confirm ?? (_) async => true,
    webApp: webApp,
  );

  Future<RemoteShell> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required Future<bool> Function(RemoteHostKey) verifyHostKey,
    required RemoteCancellation cancellation,
  }) async {
    connections++;
    if (!keyPresented.isCompleted) keyPresented.complete();
    if (connections > 1 && freshFailure != null) throw freshFailure!;
    await cancellation.bind(
      verifyHostKey(
        RemoteHostKey(
          host: host,
          port: port,
          type: 'ssh-ed25519',
          fingerprint: connections > 1
              ? freshFingerprint ?? 'SHA256:accepted'
              : 'SHA256:accepted',
        ),
      ),
    );
    authenticated++;
    final shell = _ServerConnection(this);
    _shells.add(shell);
    cancellation.addListener(shell.close);
    return shell;
  }

  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  }) async {
    commands.add(command);
    if (command.contains('HERMUSE_CANONICAL_PRESENT_V1')) {
      return _ok(
        health[RemoteInstallStep.dashboard] == true
            ? 'HERMUSE_CANONICAL_PRESENT_V1'
            : 'HERMUSE_CANONICAL_ABSENT_V1',
      );
    }
    if (command.contains('getent passwd') &&
        !command.contains('HERMUSE_PREFLIGHT_OK') &&
        !command.contains('HERMUSE_HEALTH_V1') &&
        command.length < 500) {
      return _ok('/root');
    }
    if (command.contains('HERMUSE_MIGRATION_PY')) {
      migrationCalls++;
      if (migrationCalls == 1) return _ok(jsonEncode(legacyInventory));
      migrationApplied = true;
      migrationBeforeRuntime = !hermesStarted;
      return _ok();
    }
    if (command.contains('HERMUSE_CONNECT_REFUSED_V1') &&
        connectionGate != null) {
      if (!connectionObserved.isCompleted) connectionObserved.complete();
      return connectionGate!.future;
    }
    if (command.contains('HERMUSE_CONNECT_REFUSED_V1') && connectionRefused) {
      return const RemoteResult(
        stdout: '',
        stderr: 'HERMUSE_CONNECT_REFUSED_V1',
        exitCode: 1,
      );
    }
    if (command.contains('secrets.token_urlsafe(48)')) {
      return _ok(loopbackToken);
    }
    if (command.contains('systemctl restart hermuse-dashboard.service')) {
      health[RemoteInstallStep.dashboard] = true;
    }
    if (command.contains('systemctl restart hermuse-gateway.service')) {
      schedulerConfigurations++;
      health[RemoteInstallStep.scheduler] = true;
    }
    if (command.contains('config set dashboard.public_url')) publicUrlChanges++;
    // The fake models the server boundary, not an alternative provisioning
    // implementation. Decisions, stage parsing and failure handling stay real.
    if (command.contains('HERMUSE_PREFLIGHT_OK') && foreignPath) {
      return const RemoteResult(
        stdout: '',
        stderr: 'An unrelated plugin occupies the managed path.',
        exitCode: 1,
      );
    }
    if (command.contains('HERMUSE_HEALTH_V1') &&
        command.contains('org.hermuse.remote-installer')) {
      if (webForeign && command.contains(' publish\n')) {
        return const RemoteResult(
          stdout: '',
          stderr: 'A Docker container named hermuse-web exists.',
          exitCode: 1,
        );
      }
      return _ok('HERMUSE_HEALTH_V1:$webState');
    }
    if (command.contains('docker pull')) {
      webPulls++;
      if (webPullFails) {
        return const RemoteResult(stdout: '', stderr: 'denied', exitCode: 1);
      }
    }
    if (command.contains('tempfile.mkstemp') && stdin != null) {
      webDeploys++;
      webToken = stdin;
      webState = 'ready';
    }
    if (command.contains('HERMUSE_HEALTH_V1') &&
        command.contains('caddy adapt')) {
      caddyHealthChecks.add(command);
    }
    if (command.contains('systemd-run') &&
        command.contains('hermuse-caddy-rollback')) {
      caddyConfigurations.add(command);
    }
    if (command.contains('HERMUSE_HEALTH_V1')) {
      if (command.contains('dpkg-query')) {
        if (inventoryGate case final gate?) {
          if (!inventoryObserved.isCompleted) inventoryObserved.complete();
          return gate.future;
        }
        if (malformedInventory) return _ok('unknown inventory');
        return _ok(
          'HERMUSE_HEALTH_V1:${prerequisitesReady ? 'ready' : 'repair'}',
        );
      }
      final step = command.contains('ticker_heartbeat')
          ? RemoteInstallStep.scheduler
          : command.contains('hermuse_inventory_specs')
          ? RemoteInstallStep.plugin
          : command.contains('webSocketDebuggerUrl')
          ? RemoteInstallStep.computer
          : command.contains('pinnedCommit')
          ? RemoteInstallStep.hermes
          : command.contains('stat -c %U')
          ? RemoteInstallStep.hermesUser
          : command.contains('auth/password-login') ||
                command.contains('x-hermes-session-token')
          ? RemoteInstallStep.dashboard
          : RemoteInstallStep.https;
      if (step == RemoteInstallStep.https && caddyConflict) {
        return const RemoteResult(
          stdout: '',
          stderr: 'An unrelated Caddy route already owns the target.',
          exitCode: 1,
        );
      }
      return _ok(
        'HERMUSE_HEALTH_V1:${health[step] == true && failedRepair != step ? 'ready' : 'repair'}',
      );
    }
    if (command.contains('id -u') &&
        !command.contains('HERMUSE_PREFLIGHT_OK') &&
        !command.contains('useradd')) {
      return _ok('0');
    }
    if (command.contains('SSH_CONNECTION')) {
      return _ok('1.2.3.4 56789 8.8.4.4 22');
    }
    if (command.contains('LC_ALL=C ufw status verbose')) {
      return _ok(firewallActive ? _activeFirewall : 'Status: inactive');
    }
    if (command.contains('apt-get') && command.contains('missing=(')) {
      packageInstalls++;
      prerequisitesReady = true;
    }
    if (command.contains('useradd')) {
      health[RemoteInstallStep.hermesUser] = true;
    }
    if (command.contains('systemd-run') &&
        command.contains('ufw --force enable')) {
      firewallActive = !firewallRepairIncomplete;
    }
    if (command.contains('cp -a') &&
        command.contains('.hermuse-remote-managed')) {
      health[RemoteInstallStep.plugin] = true;
    }
    if (command.contains('REGISTRY_IMAGE') && command.contains('docker')) {
      computerPrepared = true;
    }
    if (command.contains('systemd-run') &&
        command.contains('hermuse-caddy-rollback')) {
      health[RemoteInstallStep.https] = true;
    }
    if (!command.contains('systemd-run')) {
      final commit = command.contains(
        'configuration transaction no longer belongs',
      );
      final restore =
          command.contains('/armed') && command.contains('rollback.sh');
      if (command.contains('hermuse-firewall-rollback')) {
        if (commit) firewallCommitted = true;
        if (restore) firewallRestored = true;
      }
      if (command.contains('hermuse-caddy-rollback')) {
        if (commit) caddyCommitted = true;
        if (restore) caddyRestored = true;
      }
    }
    if (command.contains('--manifest')) {
      manifestRequests++;
      hermesStarted = true;
      return _ok(
        '{"protocol_version":1,"stages":[{"name":"repository","title":"Repository","category":"runtime","needs_user_input":false}]}',
      );
    }
    if (command.contains('--stage')) {
      forcedRepin = command.contains('--force-commit');
      final installed = jsonDecode(stageFrame) as Map<String, dynamic>;
      if (stageExitCode == 0 &&
          installed['ok'] == true &&
          installed['stage'] == 'repository' &&
          installed['skipped'] == false) {
        health[RemoteInstallStep.hermes] = true;
      }
      return RemoteResult(
        stdout: stageFrame,
        stderr: '',
        exitCode: stageExitCode,
      );
    }
    if (command.contains('computer setup') ||
        command.contains('computer status')) {
      return computerStates.removeAt(0);
    }
    if (command.contains('computer start')) {
      computerStarted = true;
      health[RemoteInstallStep.computer] = true;
    }
    if (command.contains('api.ipify.org')) {
      publicAddressLookups++;
      return _ok('8.8.4.4');
    }
    if (stdin != null && command.contains('hash_password')) {
      dashboardPassword = stdin;
      passwordChanges++;
      health[RemoteInstallStep.dashboard] = true;
    }
    onLine?.call('completed');
    return _ok();
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) async {
    writes[path] = bytes;
  }

  @override
  void close() {
    for (final shell in _shells) {
      shell.close();
    }
  }
}

final class _LocalServerConnection implements RemoteOperationHolderShell {
  _LocalServerConnection(_Server server)
    : _delegate = _ServerConnection(server);
  final _ServerConnection _delegate;

  @override
  Future<RemoteResult> holdOperation(
    String command, {
    required Duration timeout,
    required void Function(String line) onLine,
  }) => _delegate.run(command, timeout: timeout, onLine: onLine);

  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  }) {
    if (command.contains('HERMUSE_OPERATION_LOCKED_V1')) {
      throw StateError(
        'The control holder must not occupy the serialized command channel.',
      );
    }
    return _delegate.run(
      command,
      stdin: stdin,
      timeout: timeout,
      onLine: onLine,
    );
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) =>
      _delegate.writeFile(path, bytes, mode: mode);

  @override
  void close() => _delegate.close();
}

final class _ServerConnection implements RemoteShell {
  _ServerConnection(this.server);
  final _Server server;
  bool closed = false;
  Completer<RemoteResult>? _lock;
  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  }) {
    if (closed) throw StateError('The SSH connection was closed.');
    if (command.contains('HERMUSE_OPERATION_LOCKED_V1')) {
      server.commands.add(command);
      _lock = Completer<RemoteResult>();
      onLine?.call('HERMUSE_OPERATION_LOCKED_V1');
      return _lock!.future;
    }
    return server.run(command, stdin: stdin, timeout: timeout, onLine: onLine);
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) =>
      server.writeFile(path, bytes, mode: mode);
  @override
  void close() {
    closed = true;
    if (_lock case final lock? when !lock.isCompleted) lock.complete(_ok());
  }
}

http.Response _dashboardResponse(http.Request request) {
  switch (request.url.path) {
    case '/api/status':
      return http.Response(
        '{"version":"0.21.5","auth_required":true,"auth_providers":["basic"]}',
        200,
      );
    case '/auth/password-login':
      return http.Response(
        '{}',
        200,
        headers: {
          'set-cookie': 'hermes_session=verified; Secure; HttpOnly; Path=/',
        },
      );
    case '/api/plugins/hermuse/files':
      return request.headers.containsKey('cookie')
          ? http.Response('{"files":["FEED_PROMPT.md"]}', 200)
          : http.Response('{}', 401);
    case '/api/plugins/hermuse/cron':
      return http.Response(
        jsonEncode({
          'jobs': [
            for (final key in ['feed', 'ideas', 'goals', 'reflection'])
              {'key': key, 'registered': true},
          ],
        }),
        200,
      );
    case '/api/plugins/hermuse/computer/status':
      return http.Response('{"state":"running"}', 200);
    default:
      throw StateError('Unexpected dashboard request: ${request.url.path}');
  }
}
