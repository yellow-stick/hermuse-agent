import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_app/host/local_uninstall.dart';
import 'package:hermuse_host/hermuse_host.dart';

void main() {
  group('LocalUninstallController', () {
    late List<String> calls;
    late RemoteUninstallInventory inventory;
    late RemoteUninstallOutcome outcome;
    late LocalUninstallController controller;
    Completer<void>? removalGate;
    var failRegistration = false;

    setUp(() {
      calls = [];
      removalGate = null;
      failRegistration = false;
      inventory = _inventory();
      outcome = const RemoteUninstallOutcome(
        removed: ['Owned checkout'],
        preserved: [],
        warnings: [],
        purged: false,
        complete: true,
      );
      controller = LocalUninstallController(
        inspectInstallation: () async {
          calls.add('inspect');
          return inventory;
        },
        prepare: () async => calls.add('prepare'),
        removeInstallation: (review, {required purge, onLog}) async {
          calls.add('remove:$purge');
          onLog?.call('Reverting owned checkout');
          await removalGate?.future;
          return outcome;
        },
        forgetRegistration: (purge) async {
          calls.add('forget:$purge');
          if (failRegistration) throw StateError('keyring locked');
        },
        release: () => calls.add('release'),
      );
    });

    test('should inspect without stopping or forgetting anything', () async {
      await controller.inspect();
      expect(controller.state, isA<LocalRemovalReview>());
      expect(calls, ['inspect']);
      controller.dispose();
      expect(calls, ['inspect']);
    });

    test(
      'should stop, recheck, remove and forget only on completion',
      () async {
        await controller.inspect();
        await controller.uninstall(purge: false);
        expect(calls, [
          'inspect',
          'prepare',
          'inspect',
          'remove:false',
          'forget:false',
        ]);
        final result = controller.state as LocalRemovalFinished;
        expect(result.registrationError, isNull);
        expect(calls, isNot(contains('release')));
        controller.dispose();
        expect(calls.last, 'release');
      },
    );

    test('should keep registration when selected removal is partial', () async {
      outcome = const RemoteUninstallOutcome(
        removed: ['Owned plugin'],
        preserved: [],
        warnings: ['Changed checkout: preserved'],
        purged: false,
        complete: false,
      );
      await controller.inspect();
      await controller.uninstall(purge: false);
      expect(controller.state, isA<LocalRemovalFinished>());
      expect(calls.where((call) => call.startsWith('forget:')), isEmpty);
      controller.dispose();
    });

    test(
      'should require a fresh confirmation after shutdown changes inventory',
      () async {
        await controller.inspect();
        inventory = _inventory(revision: 'changed-after-flush');
        await controller.uninstall(purge: false);
        final review = controller.state as LocalRemovalReview;
        expect(review.inventory.revision, 'changed-after-flush');
        expect(calls, ['inspect', 'prepare', 'inspect']);
        await controller.uninstall(purge: false);
        expect(calls, contains('remove:false'));
        controller.dispose();
      },
    );

    test(
      'should re-confirm when a concurrent service transaction starts',
      () async {
        await controller.inspect();
        inventory = _inventory(transactionActive: true);
        await controller.uninstall(purge: true);
        expect(controller.state, isA<LocalRemovalReview>());
        expect(calls, isNot(contains('remove:true')));
        controller.dispose();
      },
    );

    test(
      'should never apply an inventory without eligible ownership',
      () async {
        inventory = _inventory(removable: false);
        await controller.inspect();
        await controller.uninstall(purge: true);
        expect(calls, ['inspect']);
        controller.dispose();
      },
    );

    test('should preserve purge-only data for keep-data removal', () async {
      inventory = _inventory(purgeOnly: true);
      await controller.inspect();
      await controller.uninstall(purge: false);
      expect(calls, ['inspect']);
      await controller.uninstall(purge: true);
      expect(calls, contains('remove:true'));
      controller.dispose();
    });

    test(
      'should show credential cleanup failure without losing removal results',
      () async {
        failRegistration = true;
        await controller.inspect();
        await controller.uninstall(purge: false);
        final result = controller.state as LocalRemovalFinished;
        expect(result.registrationError, contains('keyring locked'));
        controller.dispose();
      },
    );

    test('should reject duplicate apply and defer release if disposed while busy', () async {
      removalGate = Completer<void>();
      await controller.inspect();
      final running = controller.uninstall(purge: false);
      // Cross the injected asynchronous preparation and inspection boundaries.
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      await controller.uninstall(purge: true);
      expect(calls.where((call) => call.startsWith('remove:')), [
        'remove:false',
      ]);
      controller.dispose();
      expect(calls, isNot(contains('release')));
      removalGate!.complete();
      await running;
      expect(calls.last, 'release');
    });
  });

  group('Local installation credential ownership', () {
    for (final withRemote in [false, true]) {
      test('should preserve shared bridge keys after purge '
          '${withRemote ? 'with' : 'without'} a remote registration', () async {
        final secrets = MemorySecretStore();
        final registry = HermesRegistry(MemoryInstanceStore(), secrets);
        await registry.load();
        await registry.add(
          HermesInstance(
            id: localInstanceId,
            label: 'Local target',
            kind: InstanceKind.local,
            baseUrl: Uri.parse('http://127.0.0.1:9119'),
            auth: AuthMethod.loopbackToken,
          ),
        );
        if (withRemote) {
          await registry.add(
            HermesInstance(
              id: 'remote',
              label: 'Remote target',
              kind: InstanceKind.remote,
              baseUrl: Uri.parse('https://remote.example.com'),
              auth: AuthMethod.password,
            ),
          );
          await secrets.write('remote', SecretKeys.password, 'remote-secret');
        }
        await secrets.write(
          localInstanceId,
          SecretKeys.sessionToken,
          'local-token',
        );
        await secrets.write(
          cliproxyInstanceId,
          CliproxySecretKeys.apiKey,
          'shared-api-key',
        );
        await secrets.write(
          cliproxyInstanceId,
          CliproxySecretKeys.managementKey,
          'shared-management-key',
        );
        final controller = LocalUninstallController(
          inspectInstallation: () async => _inventory(),
          prepare: () async {},
          removeInstallation: (_, {required purge, onLog}) async =>
              RemoteUninstallOutcome(
                removed: ['Owned checkout'],
                preserved: const [],
                warnings: const [],
                purged: purge,
                complete: true,
              ),
          forgetRegistration: (_) =>
              forgetLocalInstallationRegistration(registry),
          release: () {},
        );
        addTearDown(controller.dispose);
        await controller.inspect();
        await controller.uninstall(purge: true);
        expect(controller.state, isA<LocalRemovalFinished>());
        expect(registry.byId(localInstanceId), isNull);
        expect(
          await secrets.read(localInstanceId, SecretKeys.sessionToken),
          isNull,
        );
        expect(
          await secrets.read(cliproxyInstanceId, CliproxySecretKeys.apiKey),
          'shared-api-key',
        );
        expect(
          await secrets.read(
            cliproxyInstanceId,
            CliproxySecretKeys.managementKey,
          ),
          'shared-management-key',
        );
        if (withRemote) {
          expect(registry.byId('remote'), isNotNull);
          expect(
            await secrets.read('remote', SecretKeys.password),
            'remote-secret',
          );
        } else {
          expect(registry.instances, isEmpty);
        }
      });
    }

    test(
      'should refuse a remote registration using the reserved local id',
      () async {
        final secrets = MemorySecretStore();
        final registry = HermesRegistry(MemoryInstanceStore(), secrets);
        await registry.load();
        await registry.add(
          HermesInstance(
            id: localInstanceId,
            label: 'Remote target',
            kind: InstanceKind.remote,
            baseUrl: Uri.parse('https://remote.example.com'),
            auth: AuthMethod.password,
          ),
        );
        await secrets.write(
          localInstanceId,
          SecretKeys.password,
          'remote-secret',
        );
        await expectLater(
          forgetLocalInstallationRegistration(registry),
          throwsStateError,
        );
        expect(registry.byId(localInstanceId), isNotNull);
        expect(
          await secrets.read(localInstanceId, SecretKeys.password),
          'remote-secret',
        );
      },
    );
  });
}

RemoteUninstallInventory _inventory({
  String revision = 'reviewed',
  bool removable = true,
  bool purgeOnly = false,
  bool transactionActive = false,
}) => RemoteUninstallInventory(
  revision: revision,
  transactionActive: transactionActive,
  resources: [
    RemoteUninstallResource(
      id: 'checkout',
      label: 'Owned checkout',
      kind: 'directory',
      reason: removable ? 'Owned installation' : 'No provenance',
      removable: removable,
      purgeOnly: purgeOnly,
    ),
  ],
);
