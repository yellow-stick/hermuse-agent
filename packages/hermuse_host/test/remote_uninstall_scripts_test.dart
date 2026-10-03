import 'dart:convert';
import 'dart:io';

import 'package:hermuse_host/src/installer.dart';
import 'package:hermuse_host/src/remote_scripts.dart';
import 'package:hermuse_host/src/remote_uninstall_scripts.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Remote uninstall recipes',
    () {
      late _Machine machine;
      setUp(() async => machine = await _Machine.create());
      tearDown(() async => machine.root.delete(recursive: true));

      test(
        'removes the journaled loopback credential during keep-data removal',
        () async {
          await machine.install();
          await machine.put(
            'usr/lib/systemd/system/user@.service',
            '[Service]\nUser=%i\nExecStart=/usr/lib/systemd/systemd --user\n',
          );
          await machine.checked(
            remoteOwnershipMutationScript({dashboardTokenFile}),
          );
          await machine.put(
            'var/lib/hermuse-provision/dashboard.env',
            'HERMES_DASHBOARD_SESSION_TOKEN=private-loopback-token\n',
          );
          await Process.run('chmod', [
            '0600',
            machine.file('var/lib/hermuse-provision/dashboard.env').path,
          ]);
          await machine.checked(remoteOwnershipCheckpointScript);
          final outcome = await machine.remove(
            await machine.inventory(),
            purge: false,
          );
          expect(outcome['complete'], isTrue, reason: jsonEncode(outcome));
          expect(
            await machine
                .file('var/lib/hermuse-provision/dashboard.env')
                .exists(),
            isFalse,
          );
          expect(
            await machine
                .file('home/hermes/.hermes/hermuse/feed.md')
                .readAsString(),
            'retained feed',
          );
          expect(
            await machine
                .file('var/lib/hermuse-provision/ownership.json')
                .readAsString(),
            isNot(contains('private-loopback-token')),
          );
        },
      );

      test('connection-only provenance revokes its token without adopting legacy runtime or jobs', () async {
        await machine.install();
        await machine.checked(
          remoteOwnershipMutationScript({dashboardTokenFile}),
        );
        await machine.put(
          'var/lib/hermuse-provision/dashboard.env',
          'HERMES_DASHBOARD_SESSION_TOKEN=${'t' * 64}\n',
        );
        await Process.run('chmod', [
          '0600',
          machine.file('var/lib/hermuse-provision/dashboard.env').path,
        ]);
        await machine.checked(remoteOwnershipCheckpointScript);
        final journalFile = machine.file(
          'var/lib/hermuse-provision/ownership.json',
        );
        final previous = jsonDecode(await journalFile.readAsString()) as Map;
        final tokenPath = machine
            .file('var/lib/hermuse-provision/dashboard.env')
            .path;
        await journalFile.writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'legacy': false,
            'connectionOnly': true,
            'user': {
              'created': false,
              'identity': null,
              'defaults': <String, Object?>{},
            },
            'paths': {tokenPath: (previous['paths'] as Map)[tokenPath]},
            'caddy': <String, Object?>{},
          }),
        );
        final jobsFile = machine.file('home/hermes/.hermes/cron/jobs.json');
        final jobs = await jobsFile.readAsString();
        final configFile = machine.file('home/hermes/.hermes/config.yaml');
        final config = await configFile.readAsString();
        final inventory = await machine.inventory();
        final token = (inventory['resources'] as List).cast<Map>().singleWhere(
          (resource) => resource['id'] == tokenPath,
        );
        expect(token['removable'], isTrue);
        await machine.remove(inventory, purge: false);
        expect(await File(tokenPath).exists(), isFalse);
        expect(
          await Directory(machine.file('home/hermes/.hermes/hermes-agent').path)
              .exists(),
          isTrue,
        );
        expect(
          await Directory(
            machine.file('home/hermes/.hermes/plugins/hermuse').path,
          ).exists(),
          isTrue,
        );
        expect(await jobsFile.readAsString(), jobs);
        expect(await configFile.readAsString(), config);
      });

      test('preserves an unjournaled credential rather than claiming its ownership', () async {
        await machine.install();
        await machine.put(
          'var/lib/hermuse-provision/dashboard.env',
          'unrelated credential',
        );
        final inventory = await machine.inventory();
        final resources = inventory['resources'] as List;
        final token = resources.cast<Map>().singleWhere(
          (resource) => '${resource['id']}'.endsWith('/dashboard.env'),
        );
        expect(token['removable'], isFalse);
        await machine.remove(inventory, purge: false);
        expect(
          await machine
              .file('var/lib/hermuse-provision/dashboard.env')
              .readAsString(),
          'unrelated credential',
        );
      });

      test('should remove owned runtime and jobs while retaining data and unrelated resources', () async {
        await machine.install();
        final before = await machine.inventory();
        expect(before['transactionActive'], isFalse);
        final outcome = await machine.remove(before, purge: false);
        expect(outcome['complete'], isTrue, reason: jsonEncode(outcome));
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isFalse,
        );
        expect(
          await machine.file('home/hermes/.hermes/config.yaml').exists(),
          isTrue,
        );
        final config = jsonDecode(
          await machine.file('home/hermes/.hermes/config.yaml').readAsString(),
        ) as Map;
        expect((config['plugins'] as Map)['enabled'], ['unrelated']);
        expect(config['api_key'], 'private-user-data');
        expect((config['browser'] as Map)['custom'], 'keep');
        expect(
          (config['browser'] as Map).containsKey('cloud_provider'),
          isFalse,
        );
        final jobs = jsonDecode(
          await machine
              .file('home/hermes/.hermes/cron/jobs.json')
              .readAsString(),
        ) as Map;
        expect((jobs['jobs'] as List).single, {
          'id': 'unrelated',
          'origin': {'source': 'someone-else'},
        });
        expect(
          await machine
              .file('home/hermes/.hermes/hermuse/feed.md')
              .readAsString(),
          'retained feed',
        );
        expect(
          await machine.file('home/hermes/.cache/uv/cache').exists(),
          isTrue,
        );
        expect(await machine.file('state/account.json').exists(), isTrue);
        expect((await machine.dockerState())['volume'], isNotNull);
        expect((await machine.dockerState())['unrelated'], 'never touched');
        expect(
          await machine.file('etc/caddy/unrelated.caddy').readAsString(),
          'untouched site',
        );
        expect(
          await machine.file('state/packages').readAsString(),
          contains('caddy'),
        );
        final ufw = await machine.firewallState();
        expect(ufw['active'], isFalse);
        expect(ufw['rules'], ["ufw deny 25/tcp"]);
        final repeat = await machine.remove(
          await machine.inventory(),
          purge: false,
        );
        expect(repeat['complete'], isTrue);
        expect(repeat['removed'], isEmpty);
      });

      test('should purge proven data cache volume and unused dedicated account after keep-data uninstall', () async {
        await machine.install();
        await machine.remove(await machine.inventory(), purge: false);
        final result = await machine.remove(
          await machine.inventory(),
          purge: true,
        );
        expect(result['complete'], isTrue, reason: jsonEncode(result));
        expect(
          await Directory('${machine.root.path}/home/hermes').exists(),
          isFalse,
        );
        expect(await machine.file('state/account.json').exists(), isFalse);
        expect((await machine.dockerState())['volume'], isNull);
        expect((await machine.dockerState())['unrelated'], 'never touched');
        expect(
          await machine
              .file('var/lib/hermuse-provision/ownership.json')
              .exists(),
          isTrue,
        );
        final repeat = await machine.remove(
          await machine.inventory(),
          purge: true,
        );
        expect(repeat['complete'], isTrue);
        expect(repeat['removed'], isEmpty);
      });

      test('should preserve a shared volume and an account used by another service during purge', () async {
        await machine.install();
        await machine.put(
          'etc/systemd/system/unrelated.service',
          '[Service]\nUser=hermes\nExecStart=/usr/bin/unrelated\n',
        );
        final docker = await machine.dockerState();
        docker['references'] = ['owned-container-id', 'other-container-id'];
        await machine.put('state/docker.json', jsonEncode(docker));
        final outcome = await machine.remove(
          await machine.inventory(),
          purge: true,
        );
        expect(outcome['complete'], isFalse);
        expect((await machine.dockerState())['volume'], isNotNull);
        expect(await machine.file('state/account.json').exists(), isTrue);
        expect(
          await machine
              .file('etc/systemd/system/unrelated.service')
              .readAsString(),
          contains('/usr/bin/unrelated'),
        );
        expect(
          (outcome['preserved'] as List).any(
            (item) => (item as Map)['id'] == 'computer-home',
          ),
          isTrue,
        );
      });

      test('should not follow a planted runtime symlink or a symlink inside an owned tree', () async {
        await machine.install();
        await machine.put('outside/private', 'unrelated data');
        final runtime = Directory(
          '${machine.root.path}/home/hermes/.hermes/node',
        );
        await runtime.delete(recursive: true);
        await Link(runtime.path).create('${machine.root.path}/outside');
        await Link(
          '${machine.root.path}/home/hermes/.hermes/hermes-agent/external',
        ).create('${machine.root.path}/outside');
        final outcome = await machine.remove(
          await machine.inventory(),
          purge: false,
        );
        expect(outcome['complete'], isFalse);
        expect(
          await machine.file('outside/private').readAsString(),
          'unrelated data',
        );
        expect(await Link(runtime.path).exists(), isTrue);
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isFalse,
        );
      });

      test('should refuse stale confirmation before stopping services or removing files', () async {
        await machine.install();
        final inventory = await machine.inventory();
        await machine.put(
          'etc/caddy/Caddyfile',
          'new.example.com { respond "keep" }\nimport /etc/caddy/hermuse-remote.caddy\n',
        );
        final result = await machine.run(
          remoteUninstallScript(inventory['revision'] as String, purge: true),
        );
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('inventory changed'));
        expect(
          await machine
              .file('etc/systemd/system/hermuse-dashboard.service')
              .exists(),
          isTrue,
        );
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isTrue,
        );
      });

      test('should report held setup lock and refuse removal until its process exits', () async {
        await machine.install();
        final lock = machine.file('var/lib/hermuse-provision/operation.lock');
        await machine.put('var/lib/hermuse-provision/operation.lock', '');
        final holder = await Process.start('flock', [
          lock.path,
          'bash',
          '-c',
          'echo ready; read release',
        ]);
        final ready = await holder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        expect(ready, 'ready');
        final inventory = await machine.inventory();
        expect(inventory['transactionActive'], isTrue);
        final result = await machine.run(
          remoteUninstallScript(inventory['revision'] as String, purge: false),
        );
        expect(result.exitCode, isNot(0));
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isTrue,
        );
        holder.stdin.writeln('release');
        await holder.stdin.close();
        await holder.exitCode;
        expect((await machine.inventory())['transactionActive'], isFalse);
      });

      test('should preserve legacy firewall runtime origins and Caddy routes without inventing provenance', () async {
        await machine.install();
        await machine.file('var/lib/hermuse-provision/ownership.json').delete();
        final inventory = await machine.inventory();
        final result = await machine.remove(inventory, purge: true);
        expect(result['complete'], isFalse);
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/plugins/hermuse',
          ).exists(),
          isFalse,
        );
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isFalse,
        );
        expect(
          await Directory('${machine.root.path}/home/hermes/.hermes/node')
              .exists(),
          isTrue,
        );
        expect(
          await machine.file('home/hermes/.hermes/config.yaml').exists(),
          isTrue,
        );
        expect(
          await machine.file('etc/caddy/hermuse-remote.caddy').exists(),
          isTrue,
        );
        expect((await machine.firewallState())['active'], isTrue);
        expect(
          (result['preserved'] as List).any(
            (item) => (item as Map)['id'] == 'legacy-firewall',
          ),
          isTrue,
        );
      });

      test('should restore Caddy bytes permissions and group after a deleted fragment rollback', () async {
        await machine.install();
        final caddy = await machine.file('etc/caddy/Caddyfile').readAsString();
        final site = await machine
            .file('etc/caddy/hermuse-remote.caddy')
            .readAsString();
        final groups = (await Process.run('/usr/bin/id', [
          '-G',
        ])).stdout.toString().trim().split(' ');
        final gid = machine.uid == 0
            ? '42'
            : groups.firstWhere(
                (value) => value != groups.first,
                orElse: () => groups.first,
              );
        for (final path in [
          'etc/caddy/Caddyfile',
          'etc/caddy/hermuse-remote.caddy',
        ]) {
          await Process.run('chmod', ['0640', machine.file(path).path]);
          await Process.run('chgrp', [gid, machine.file(path).path]);
        }
        final metadata = (await Process.run('stat', [
          '-c',
          '%u:%g:%a',
          machine.file('etc/caddy/hermuse-remote.caddy').path,
        ])).stdout;
        await machine.put('state/caddy-invalid', '');
        final inventory = await machine.inventory();
        final result = await machine.run(
          remoteUninstallScript(inventory['revision'] as String, purge: false),
        );
        expect(result.exitCode, isNot(0));
        expect(await machine.file('etc/caddy/Caddyfile').readAsString(), caddy);
        expect(
          await machine.file('etc/caddy/hermuse-remote.caddy').readAsString(),
          site,
        );
        expect(
          await machine.file('etc/caddy/unrelated.caddy').readAsString(),
          'untouched site',
        );
        for (final path in [
          'etc/caddy/Caddyfile',
          'etc/caddy/hermuse-remote.caddy',
        ]) {
          expect(
            (await Process.run('stat', [
              '-c',
              '%u:%g:%a',
              machine.file(path).path,
            ])).stdout,
            metadata,
          );
        }
      });

      test('should preserve changed firewall activation SSH ingress and shared HTTPS rules', () async {
        await machine.install();
        final firewall = await machine.firewallState();
        (firewall['rules'] as List).add('ufw allow 8443/tcp');
        await machine.put('state/ufw.json', jsonEncode(firewall));
        await machine.put(
          'etc/ufw/user.rules',
          'changed by another administrator',
        );
        await machine.put(
          'etc/caddy/Caddyfile',
          'unrelated.example.com { respond "keep" }\nimport /etc/caddy/hermuse-remote.caddy\n',
        );
        final outcome = await machine.remove(
          await machine.inventory(),
          purge: false,
        );
        expect(outcome['complete'], isFalse);
        final finalFirewall = await machine.firewallState();
        expect(finalFirewall['active'], isTrue);
        expect(finalFirewall['rules'], contains('ufw allow 8443/tcp'));
        expect(
          finalFirewall['rules'],
          contains("ufw allow 22/tcp comment 'Hermuse remote setup'"),
        );
        expect(
          finalFirewall['rules'],
          contains("ufw allow 443/tcp comment 'Hermuse remote setup'"),
        );
        expect(
          await machine.file('etc/caddy/Caddyfile').readAsString(),
          'unrelated.example.com { respond "keep" }\n',
        );
      });

      test('should remove a checkpointed partial runtime without needing Hermes to start', () async {
        await machine.install(partial: true);
        await machine.put(
          'home/hermes/.hermes/config.yaml',
          'user-setting: retained\n',
        );
        final retained = await machine.remove(
          await machine.inventory(),
          purge: false,
        );
        expect(retained['complete'], isTrue, reason: jsonEncode(retained));
        expect(
          await machine.file('home/hermes/.hermes/config.yaml').readAsString(),
          'user-setting: retained\n',
        );
        final outcome = await machine.remove(
          await machine.inventory(),
          purge: true,
        );
        expect(outcome['complete'], isTrue, reason: jsonEncode(outcome));
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isFalse,
        );
        expect(
          await Directory('${machine.root.path}/home/hermes').exists(),
          isFalse,
        );
        expect(
          await machine.file('etc/caddy/unrelated.caddy').readAsString(),
          'untouched site',
        );
      });
      test('should preserve a replaced runtime directory and its data ancestor during purge', () async {
        await machine.install();
        await machine.put(
          'outside/replacement/foreign.txt',
          'keep replacement data',
        );
        await Directory('${machine.root.path}/home/hermes/.hermes/node')
            .delete(recursive: true);
        await Directory('${machine.root.path}/outside/replacement')
            .rename('${machine.root.path}/home/hermes/.hermes/node');
        final inventory = await machine.inventory();
        expect(
          _resource(inventory, '$remoteHermesHome/node', machine)['removable'],
          isFalse,
        );
        expect(
          _resource(inventory, remoteHermesHome, machine)['removable'],
          isFalse,
        );
        final outcome = await machine.remove(inventory, purge: true);
        expect(outcome['complete'], isFalse);
        expect(
          await machine
              .file('home/hermes/.hermes/node/foreign.txt')
              .readAsString(),
          'keep replacement data',
        );
        expect(
          await machine.file('home/hermes/.hermes/config.yaml').exists(),
          isTrue,
        );
        expect(await machine.file('state/account.json').exists(), isTrue);
      });

      test('should not let a status checkpoint adopt replaced runtime cache or Docker identities', () async {
        await machine.install();
        for (final path in ['.hermes/node', '.cache/uv']) {
          await machine.put('outside/$path/foreign.txt', 'keep $path');
          await Directory('${machine.root.path}/home/hermes/$path')
              .delete(recursive: true);
          await Directory('${machine.root.path}/outside/$path')
              .rename('${machine.root.path}/home/hermes/$path');
        }
        final docker = await machine.dockerState();
        (docker['container'] as Map)['Id'] = 'foreign-replacement';
        docker['references'] = ['foreign-replacement'];
        await machine.put('state/docker.json', jsonEncode(docker));
        await machine.checked(remoteOwnershipCheckpointScript);
        final inventory = await machine.inventory();
        expect(
          _resource(inventory, '$remoteHermesHome/node', machine)['removable'],
          isFalse,
        );
        expect(
          _resource(inventory, '$remoteHome/.cache/uv', machine)['removable'],
          isFalse,
        );
        expect(_resource(inventory, 'computer', machine)['removable'], isFalse);
        expect(
          _resource(inventory, 'computer-home', machine)['removable'],
          isFalse,
        );
        await machine.remove(inventory, purge: true);
        expect(
          await machine
              .file('home/hermes/.hermes/node/foreign.txt')
              .readAsString(),
          'keep .hermes/node',
        );
        expect(
          await machine
              .file('home/hermes/.cache/uv/foreign.txt')
              .readAsString(),
          'keep .cache/uv',
        );
        expect((await machine.dockerState())['container'], isNotNull);
        expect((await machine.dockerState())['volume'], isNotNull);
      });

      test('should discard cancelled attempt intent rather than adopting later unrelated resources', () async {
        await machine.install(partial: true);
        await machine.checked(
          remoteOwnershipMutationScript({
            '$remoteHermesHome/node',
            '$remoteHome/.cache/uv',
          }, computer: true),
        );
        await machine.put(
          'home/hermes/.hermes/node/foreign.txt',
          'foreign runtime',
        );
        await machine.put('home/hermes/.cache/uv/foreign.txt', 'foreign cache');
        final docker = await machine.dockerState();
        docker['container'] = {
          'Id': 'foreign-container',
          'Config': {'Image': 'hermuse-computer:foreign'},
          'Mounts': [
            {
              'Type': 'volume',
              'Name': 'hermuse-computer-hermes-home',
              'Destination': '/home/hermuse',
            },
          ],
        };
        docker['volume'] = {
          'Name': 'hermuse-computer-hermes-home',
          'CreatedAt': 'foreign',
          'Mountpoint': '/foreign',
          'Driver': 'local',
          'Scope': 'local',
        };
        docker['images'] = {
          'hermuse-computer:foreign': {
            'Id': 'foreign-image',
            'RepoTags': ['hermuse-computer:foreign'],
          },
        };
        docker['references'] = ['foreign-container'];
        await machine.put('state/docker.json', jsonEncode(docker));
        await machine.setAttempt('2-2');
        await machine.checked(remoteOwnershipCheckpointScript);
        final rejected = await machine.run(
          remoteOwnershipMutationScript({'$remoteHermesHome/node'}),
          admitted: true,
        );
        expect(rejected.exitCode, isNot(0));
        final inventory = await machine.inventory();
        expect(
          _resource(inventory, '$remoteHermesHome/node', machine)['removable'],
          isFalse,
        );
        expect(
          _resource(inventory, '$remoteHome/.cache/uv', machine)['removable'],
          isFalse,
        );
        expect(_resource(inventory, 'computer', machine)['removable'], isFalse);
        expect(
          _resource(inventory, 'computer-home', machine)['removable'],
          isFalse,
        );
        await machine.remove(inventory, purge: true);
        expect(
          await machine
              .file('home/hermes/.hermes/node/foreign.txt')
              .readAsString(),
          'foreign runtime',
        );
        expect(
          await machine
              .file('home/hermes/.cache/uv/foreign.txt')
              .readAsString(),
          'foreign cache',
        );
        expect((await machine.dockerState())['container'], docker['container']);
        expect((await machine.dockerState())['volume'], docker['volume']);
        expect((await machine.dockerState())['images'], docker['images']);
      });

      test('should reject copied bootstrap markers on foreign source without recording or changing it', () async {
        await machine.install();
        await machine.file('var/lib/hermuse-provision/ownership.json').delete();
        await machine.put(
          'home/hermes/.hermes/hermes-agent/.git/config',
          '[core]\nrepositoryformatversion = 0\n[remote "origin"]\nurl = https://example.com/unrelated.git\n',
        );
        await machine.put(
          'home/hermes/.hermes/hermes-agent/personal.txt',
          'foreign source data',
        );
        final rejected = await machine.run(remoteOwnershipPreflightScript);
        expect(rejected.exitCode, isNot(0));
        expect(
          await machine
              .file('home/hermes/.hermes/hermes-agent/personal.txt')
              .readAsString(),
          'foreign source data',
        );
        expect(
          await machine
              .file('var/lib/hermuse-provision/ownership.json')
              .exists(),
          isFalse,
        );
        await machine.put(
          'home/hermes/.hermes/hermes-agent/.git/config',
          '[core]\nrepositoryformatversion = 0\n[remote "origin"]\nurl = https://github.com/NousResearch/hermes-agent.git\n',
        );
        await machine.checked(remoteOwnershipPreflightScript, admitted: false);
        expect(
          await machine
              .file('var/lib/hermuse-provision/ownership.json')
              .exists(),
          isFalse,
        );
      });

      test('should report preserved recorded assets when Docker or UFW inventory is unavailable', () async {
        await machine.install();
        final docker = await machine.dockerState();
        final firewall = await machine.firewallState();
        await machine.file('bin/docker').delete();
        await machine.file('bin/ufw').delete();
        final inventory = await machine.inventory();
        expect(
          _resource(inventory, 'docker-unavailable', machine)['removable'],
          isFalse,
        );
        expect(
          _resource(inventory, 'firewall-unavailable', machine)['removable'],
          isFalse,
        );
        final outcome = await machine.remove(inventory, purge: false);
        expect(outcome['complete'], isFalse);
        expect(await machine.dockerState(), docker);
        expect(await machine.firewallState(), firewall);
      });

      test('should acquire no Docker resources from an unavailable baseline or existing store', () async {
        final docker = await machine.dockerState();
        docker['container'] = {
          'Id': 'preexisting',
          'Config': {'Image': 'hermuse-computer:preexisting'},
          'Mounts': [],
        };
        docker['volume'] = {
          'Name': 'hermuse-computer-hermes-home',
          'CreatedAt': 'preexisting',
          'Mountpoint': '/preexisting',
          'Driver': 'local',
          'Scope': 'local',
        };
        docker['images'] = {
          'hermuse-computer:preexisting': {
            'Id': 'preexisting-image',
            'RepoTags': ['hermuse-computer:preexisting'],
          },
        };
        await machine.put('state/docker.json', jsonEncode(docker));
        await machine.put('state/docker-unavailable', '');
        await machine.checked(remoteOwnershipCaptureScript);
        final unavailable = await machine.run(
          recordRemoteDockerBaselineScript,
          admitted: true,
        );
        expect(unavailable.exitCode, isNot(0));
        await machine.file('state/docker-unavailable').delete();
        await machine.checked(recordRemoteDockerBaselineScript);
        await machine.checked(
          remoteOwnershipMutationScript({}, computer: true),
        );
        await machine.checked(remoteOwnershipCheckpointScript);
        final inventory = await machine.inventory();
        expect(_resource(inventory, 'computer', machine)['removable'], isFalse);
        expect(
          _resource(inventory, 'computer-home', machine)['removable'],
          isFalse,
        );
        await machine.remove(inventory, purge: true);
        expect(await machine.dockerState(), docker);
      });

      for (final source in [
        'vendor',
        'linked',
        'drop-in',
        'template',
        'loaded',
      ]) {
        test(
          'should preserve runtime and account used by an effective stopped $source unit',
          () async {
            await machine.install();
            if (source == 'vendor') {
              await machine.put(
                'usr/lib/systemd/system/shared.service',
                '[Service]\nUser=hermes\nExecStart=/usr/bin/true\n',
              );
            } else if (source == 'linked') {
              await machine.put(
                'state/shared.service',
                '[Service]\nUser=hermes\nExecStart=/usr/bin/true\n',
              );
              await Link(
                '${machine.root.path}/etc/systemd/system/shared.service',
              ).create(machine.file('state/shared.service').path);
            } else if (source == 'template') {
              await machine.put(
                'usr/lib/systemd/system/shared@.service',
                '[Service]\nUser=hermes\nExecStart=/usr/bin/true\n',
              );
            } else if (source == 'loaded') {
              await machine.put(
                'run/systemd/system/shared@session.service',
                '[Service]\nUser=hermes\nExecStart=/usr/bin/true\n',
              );
              await machine.put(
                'state/loaded-units',
                'shared@session.service loaded inactive dead Shared service\n',
              );
            } else {
              await machine.put(
                'usr/lib/systemd/system/shared.service',
                '[Service]\nUser=root\nExecStart=/usr/bin/true\n',
              );
              await machine.put(
                'etc/systemd/system/shared.service.d/user.conf',
                '[Service]\nUser=hermes\n',
              );
            }
            final outcome = await machine.remove(
              await machine.inventory(),
              purge: true,
            );
            expect(outcome['complete'], isFalse);
            expect(
              await Directory(
                '${machine.root.path}/home/hermes/.hermes/hermes-agent',
              ).exists(),
              isTrue,
            );
            expect(await machine.file('state/account.json').exists(), isTrue);
            if (source == 'vendor') {
              expect(
                await machine
                    .file('usr/lib/systemd/system/shared.service')
                    .exists(),
                isTrue,
              );
            } else if (source == 'linked') {
              expect(
                await Link(
                  '${machine.root.path}/etc/systemd/system/shared.service',
                ).exists(),
                isTrue,
              );
            } else if (source == 'template' || source == 'loaded') {
              expect(
                await machine
                    .file(
                      source == 'template'
                          ? 'usr/lib/systemd/system/shared@.service'
                          : 'run/systemd/system/shared@session.service',
                    )
                    .exists(),
                isTrue,
              );
            } else {
              expect(
                await machine
                    .file('etc/systemd/system/shared.service.d/user.conf')
                    .exists(),
                isTrue,
              );
            }
          },
        );
      }

      test('should recheck a Caddy fragment replaced after earlier runtime removal', () async {
        await machine.install();
        const foreign = 'other.example.com { respond "foreign site" }\n';
        await machine.put('state/change-caddy-on-rm', foreign);
        final inventory = await machine.inventory();
        final result = await machine.run(
          remoteUninstallScript(inventory['revision'] as String, purge: false),
        );
        expect(result.exitCode, isNot(0));
        expect(
          await machine.file('etc/caddy/hermuse-remote.caddy').readAsString(),
          foreign,
        );
        expect(
          await machine.file('etc/caddy/unrelated.caddy').readAsString(),
          'untouched site',
        );
        expect(
          await Directory(
            '${machine.root.path}/home/hermes/.hermes/hermes-agent',
          ).exists(),
          isFalse,
        );
      });

      test('should remove the owned web app container, its new image tag and both routes with keep-data uninstall', () async {
        await machine.install(web: true);
        final journal = await machine
            .file('var/lib/hermuse-provision/ownership.json')
            .readAsString();
        expect(journal, isNot(contains('never-journal-this')));
        final inventory = await machine.inventory();
        expect(_resource(inventory, 'web', machine)['removable'], isTrue);
        expect(_resource(inventory, 'web', machine)['purgeOnly'], isFalse);
        final image = 'image:$webImageRepository:0.3.0';
        expect(_resource(inventory, image, machine)['removable'], isTrue);
        expect(
          _resource(inventory, 'caddy-route', machine)['removable'],
          isTrue,
        );
        final outcome = await machine.remove(inventory, purge: false);
        expect(outcome['complete'], isTrue, reason: jsonEncode(outcome));
        expect(outcome['removed'], containsAll(['web', image, 'caddy-route']));
        final docker = await machine.dockerState();
        expect(docker['web'], isNull);
        expect(
          docker['images'] as Map,
          isNot(contains('$webImageRepository:0.3.0')),
        );
        expect(docker['unrelated'], 'never touched');
        expect(
          await machine.file('etc/caddy/hermuse-remote.caddy').exists(),
          isFalse,
        );
        expect(
          await machine.file('etc/caddy/unrelated.caddy').readAsString(),
          'untouched site',
        );
      });

      test('should preserve an unrecorded hermuse-web container and preexisting web image even when labelled', () async {
        final docker = await machine.dockerState();
        final foreign = {
          'Id': 'foreign-web-id',
          'Name': '/hermuse-web',
          'Image': 'foreign-web-image',
          'Config': {
            'Image': '$webImageRepository:0.3.0',
            'Labels': {'org.hermuse.remote-installer': 'web-v1'},
          },
          'Mounts': [],
          'HostConfig': {'PortBindings': {}},
        };
        docker['web'] = foreign;
        docker['images'] = {
          '$webImageRepository:0.3.0': {
            'Id': 'foreign-web-image',
            'RepoTags': ['$webImageRepository:0.3.0'],
          },
        };
        await machine.put('state/docker.json', jsonEncode(docker));
        await machine.install(web: true);
        // install(web:) replaced the fixture container with the owned identity;
        // restore the preexisting one so only its name and label remain.
        final current = await machine.dockerState();
        current['web'] = foreign;
        (current['images'] as Map)['$webImageRepository:0.3.0'] = {
          'Id': 'foreign-web-image',
          'RepoTags': ['$webImageRepository:0.3.0'],
        };
        await machine.put('state/docker.json', jsonEncode(current));
        final inventory = await machine.inventory();
        expect(_resource(inventory, 'web', machine)['removable'], isFalse);
        expect(
          _resource(
            inventory,
            'image:$webImageRepository:0.3.0',
            machine,
          )['removable'],
          isFalse,
        );
        final outcome = await machine.remove(inventory, purge: true);
        final after = await machine.dockerState();
        expect(after['web'], foreign);
        expect(after['images'] as Map, contains('$webImageRepository:0.3.0'));
        expect(outcome['removed'], isNot(contains('web')));
      });
    },
    // These shell integration scenarios launch hundreds of fixture commands
    // across setup, inventory, removal and repeated purge. Bound the whole
    // scenario without changing the production commands' individual limits.
    timeout: const Timeout(Duration(seconds: 90)),
    skip: Platform.isLinux ? false : 'Linux shell fixture',
  );
}

/// Runs the production recipes against disposable files and fake system/Docker
/// boundaries. Only root UID, paths and the passwd database are relocated.
final class _Machine {
  _Machine(this.root, this.uid);
  final Directory root;
  final int uid;
  File file(String path) => File('${root.path}/$path');

  static Future<_Machine> create() async {
    final uid = int.parse(
      (await Process.run('/usr/bin/id', ['-u'])).stdout.toString().trim(),
    );
    final machine = _Machine(
      await Directory.systemTemp.createTemp('hermuse-uninstall-'),
      uid,
    );
    for (final path in [
      'bin',
      'state',
      'etc/systemd/system',
      'etc/caddy',
      'etc/ufw',
      'etc/default',
      'var/lib',
      'home',
    ]) {
      await Directory('${machine.root.path}/$path').create(recursive: true);
      await Process.run('chmod', ['0755', '${machine.root.path}/$path']);
    }
    await Process.run('chmod', ['0755', '${machine.root.path}/var']);
    await Process.run('install', [
      '-d',
      '-m',
      '0711',
      '${machine.root.path}/var/lib/hermuse-provision',
    ]);
    await machine.setAttempt('1-1');
    for (final binary in [
      'bash',
      'python3',
      'git',
      'flock',
      'setsid',
      'timeout',
      'chmod',
      'stat',
      'cut',
      'sleep',
      'install',
      'cat',
      'rm',
      'true',
    ]) {
      await Link('${machine.root.path}/bin/$binary').create('/usr/bin/$binary');
    }
    await machine.executable('systemctl', _systemctl);
    await machine.executable('docker', _docker);
    await machine.executable('ufw', _ufw);
    await machine.executable('caddy', _caddy);
    await machine.executable('dpkg-query', _packages);
    await machine.executable('ps', r'''if "-u" in sys.argv: raise SystemExit(1)
os.execv("/usr/bin/ps", ["/usr/bin/ps", *sys.argv[1:]])''');
    await machine.executable('id', 'print("hermes docker")');
    await machine.executable(
      'userdel',
      'assert sys.argv[1:] == ["hermes"]; (root / "state/account.json").unlink()',
    );
    await machine.executable('runuser', _runuser);
    await machine.put('state/packages', 'python3\ncaddy\ndocker.io\nufw\n');
    await machine.put(
      'state/docker.json',
      jsonEncode({
        'container': null,
        'volume': null,
        'images': {},
        'references': [],
        'unrelated': 'never touched',
      }),
    );
    await machine.put(
      'state/ufw.json',
      jsonEncode({
        'active': false,
        'rules': ['ufw deny 25/tcp'],
      }),
    );
    await machine.put('etc/ufw/user.rules', 'preexisting deny rule');
    await machine.put('etc/ufw/user6.rules', 'preexisting IPv6 deny rule');
    await machine.put('etc/default/ufw', 'untouched default policy');
    await machine.put('etc/ufw/ufw.conf', 'ENABLED=no');
    await machine.put(
      'etc/caddy/Caddyfile',
      '# preexisting empty shared configuration\n',
    );
    await machine.put('etc/caddy/unrelated.caddy', 'untouched site');
    return machine;
  }

  Future<void> put(String path, String data) async {
    final target = file(path);
    await target.parent.create(recursive: true);
    final content =
        path == 'etc/systemd/system/hermuse-dashboard.service' ||
            path == 'etc/caddy/Caddyfile'
        ? data
              .replaceAll('/home/hermes', '${root.path}/home/hermes')
              .replaceAll('/etc/caddy/', '${root.path}/etc/caddy/')
              .replaceAll(
                '/var/lib/hermuse-provision',
                '${root.path}/var/lib/hermuse-provision',
              )
        : data;
    await target.writeAsString(content);
    await Process.run('chmod', ['0644', target.path]);
  }

  Future<void> executable(String name, String body) async {
    await put(
      'bin/$name',
      '#!/usr/bin/env python3\nimport json, os, sys, subprocess\nfrom pathlib import Path\nroot = Path(os.environ["FAKE_ROOT"])\n$body\n',
    );
    await Process.run('chmod', ['0755', file('bin/$name').path]);
  }

  Future<void> install({bool partial = false, bool web = false}) async {
    await checked(remoteOwnershipCaptureScript);
    await checked(
      remoteOwnershipMutationScript({remoteHermesHome}, account: true),
    );
    final accountUid = uid == 0 ? 1001 : uid;
    await put(
      'state/account.json',
      jsonEncode({
        'uid': accountUid,
        'gid': accountUid,
        'home': '${root.path}/home/hermes',
        'shell': '/bin/bash',
      }),
    );
    await put('var/lib/hermuse-provision/owns-hermes', '');
    for (final name in ['.bashrc', '.profile', '.bash_logout']) {
      await put('home/hermes/$name', 'default $name');
    }
    await Directory('${root.path}/home/hermes/.hermes').create();
    await checked(remoteOwnershipCheckpointScript);
    await checked(recordRemoteDockerBaselineScript);
    await checked(
      remoteOwnershipMutationScript(
        {
          remoteCheckout,
          '$remoteHermesHome/bin',
          '$remoteHermesHome/node',
          '$remoteHermesHome/runtime',
          '$remoteHome/.local/share/uv',
          remoteHermes,
          '$remoteHome/.local/bin/node',
          '$remoteHome/.local/bin/npm',
          '$remoteHome/.local/bin/npx',
          '$remoteHome/.local/bin/hermes-agent',
          '$remoteHome/.local/bin/hermes-acp',
          '$remoteHermesHome/plugins/hermuse',
          '$remoteHome/.cache/uv',
        },
        computer: !partial,
        caddy: !partial,
      ),
    );
    await put('home/hermes/.hermes/hermes-agent/partial-runtime', 'runtime');
    await put(
      'home/hermes/.hermes/hermes-agent/.git/HEAD',
      'ref: refs/heads/main\n',
    );
    await put('home/hermes/.hermes/hermes-agent/.git/objects/.keep', '');
    await put('home/hermes/.hermes/hermes-agent/.git/refs/heads/.keep', '');
    await put(
      'home/hermes/.hermes/hermes-agent/.git/config',
      '[core]\n\trepositoryformatversion = 0\n[remote "origin"]\n\turl = https://github.com/NousResearch/hermes-agent.git\n',
    );
    for (final relative in [
      'hermes_cli/main.py',
      'run_agent.py',
      'pyproject.toml',
    ]) {
      await put(
        'home/hermes/.hermes/hermes-agent/$relative',
        '# source fixture',
      );
    }
    if (partial) {
      await checked(remoteOwnershipCheckpointScript);
      return;
    }
    await put(
      'home/hermes/.hermes/hermes-agent/.hermes-bootstrap-complete',
      jsonEncode({'schemaVersion': 1, 'pinnedCommit': hermesReleaseCommit}),
    );
    await put(
      'home/hermes/.hermes/hermes-agent/venv/bin/python',
      'fixture Python path identity',
    );
    await put(
      'home/hermes/.local/bin/hermes',
      '#!/bin/bash\n${root.path}/home/hermes/.hermes/hermes-agent/venv/bin/python hermes_cli/main.py\n',
    );
    await put(
      'home/hermes/.local/bin/hermes-agent',
      '#!/bin/sh\nexec ${root.path}/home/hermes/.hermes/hermes-agent/venv/bin/python ${root.path}/home/hermes/.hermes/hermes-agent/run_agent.py',
    );
    await put(
      'home/hermes/.local/bin/hermes-acp',
      '#!/bin/sh\nexec ${root.path}/home/hermes/.hermes/hermes-agent/venv/bin/hermes acp',
    );
    await put('home/hermes/.hermes/node/bin/node', 'runtime');
    await put('home/hermes/.hermes/bin/uv', 'runtime');
    await put(
      'home/hermes/.hermes/plugins/hermuse/.hermuse-remote-managed',
      '',
    );
    await put(
      'home/hermes/.hermes/plugins/hermuse/plugin.yaml',
      'managed plugin',
    );
    await put(
      'home/hermes/.hermes/cron/jobs.json',
      jsonEncode({
        'jobs': [
          {
            'id': 'owned',
            'origin': {'source': 'hermuse', 'key': 'feed'},
          },
          {
            'id': 'unrelated',
            'origin': {'source': 'someone-else'},
          },
        ],
      }),
    );
    await put(
      'home/hermes/.hermes/config.yaml',
      jsonEncode({
        'plugins': {
          'enabled': ['hermuse', 'unrelated'],
          'disabled': [],
        },
        'browser': {
          'cloud_provider': 'hermuse',
          'auto_local_for_private_urls': false,
          'backend': 'off',
          'custom': 'keep',
        },
        'api_key': 'private-user-data',
      }),
    );
    await put('home/hermes/.hermes/hermuse/feed.md', 'retained feed');
    await put('home/hermes/.cache/uv/cache', 'retained cache');
    await put(
      'etc/systemd/system/hermuse-dashboard.service',
      '$dashboardService\n',
    );
    await put('state/hermuse-dashboard.service.active', '');
    await put('state/caddy.active', '');
    await put(
      'etc/caddy/hermuse-remote.caddy',
      caddySite(
        '8-8-4-4.sslip.io',
        webDomain: web ? webAppDomain('8-8-4-4.sslip.io') : null,
      ),
    );
    await put(
      'etc/caddy/Caddyfile',
      '# preexisting empty shared configuration\nimport /etc/caddy/hermuse-remote.caddy\n',
    );
    final docker = await dockerState();
    docker['container'] = {
      'Id': 'owned-container-id',
      'Name': '/hermuse-computer-hermes',
      'Image': 'owned-image-id',
      'Config': {
        'Image': 'hermuse-computer:0.2.0',
        'Env': ['SCREEND_TOKEN=never-journal-this'],
      },
      'Mounts': [
        {
          'Type': 'volume',
          'Name': 'hermuse-computer-hermes-home',
          'Destination': '/home/hermuse',
        },
      ],
      'HostConfig': {'PortBindings': {}},
    };
    docker['volume'] = {
      'Name': 'hermuse-computer-hermes-home',
      'CreatedAt': '2026-10-01',
      'Labels': null,
    };
    docker['images'] = {
      'hermuse-computer:0.2.0': {
        'Id': 'owned-image-id',
        'RepoTags': ['hermuse-computer:0.2.0'],
      },
    };
    docker['references'] = ['owned-container-id'];
    await put('state/docker.json', jsonEncode(docker));
    if (web) {
      await checked(remoteOwnershipMutationScript({}, web: true));
      final withWeb = await dockerState();
      withWeb['web'] = {
        'Id': 'owned-web-id',
        'Name': '/hermuse-web',
        'Image': 'owned-web-image-id',
        'Config': {
          'Image': '$webImageRepository:0.3.0',
          'Labels': {'org.hermuse.remote-installer': 'web-v1'},
          'Env': ['HERMUSE_RELAY_ADMIN_TOKEN=never-journal-this'],
        },
        'Mounts': [],
        'HostConfig': {'PortBindings': {}},
      };
      (withWeb['images'] as Map)['$webImageRepository:0.3.0'] = {
        'Id': 'owned-web-image-id',
        'RepoTags': ['$webImageRepository:0.3.0'],
      };
      await put('state/docker.json', jsonEncode(withWeb));
    }
    final ufw = await firewallState();
    ufw['active'] = true;
    (ufw['rules'] as List).addAll([
      for (final port in [22, 80, 443])
        "ufw allow $port/tcp comment 'Hermuse remote setup'",
    ]);
    await put('state/ufw.json', jsonEncode(ufw));
    await put('etc/ufw/ufw.conf', 'ENABLED=yes');
    await checked(recordRemoteFirewallOwnershipScript({22}));
    await checked(remoteOwnershipCheckpointScript);
    final journal = await file('var/lib/hermuse-provision/ownership.json')
        .readAsString();
    expect(journal, isNot(contains('never-journal-this')));
    expect(journal, isNot(contains('private-user-data')));
  }

  Future<Map<String, Object?>> dockerState() async => Map<String, Object?>.from(
    jsonDecode(await file('state/docker.json').readAsString()) as Map,
  );
  Future<Map<String, Object?>> firewallState() async =>
      Map<String, Object?>.from(
        jsonDecode(await file('state/ufw.json').readAsString()) as Map,
      );
  Future<void> setAttempt(String nonce) async {
    final process = await File('/proc/$pid/stat').readAsString();
    final started = process
        .substring(process.lastIndexOf(') ') + 2)
        .split(' ')[19];
    await put(
      'var/lib/hermuse-provision/operation.owner',
      '$nonce $pid $started\n',
    );
    await put('var/lib/hermuse-provision/operation.lock', '');
  }

  Future<ProcessResult> run(
    String script, {
    bool admitted = false,
    Map<String, String> environment = const {},
  }) async {
    final relocated = script
        .replaceAll('/home/hermes', '${root.path}/home/hermes')
        .replaceAll('/var', '${root.path}/var')
        .replaceAll('/etc/', '${root.path}/etc/')
        .replaceAllMapped(
          RegExp(r'(\$\(stat -c %u "[^"]+"\)" = )0'),
          (match) => '${match[1]}$uid',
        )
        .replaceAll('ROOT_UID = 0', 'ROOT_UID = os.getuid()')
        .replaceAll(
          '"uid": value.st_uid,',
          '"uid": (1001 if path == HOME or path.startswith(HOME + "/") else value.st_uid) if os.getuid() == 0 else value.st_uid,',
        )
        .replaceAll(
          'open("/proc/self/mountinfo")',
          'open(os.environ.get("FAKE_MOUNTINFO", "/proc/self/mountinfo"))',
        )
        .replaceAll(
          'REQUEST = json.loads(sys.argv[1])',
          '''REQUEST = json.loads(sys.argv[1])
import types
def fixture_passwd(name):
    path = os.environ["FAKE_ROOT"] + "/state/account.json"
    if not os.path.exists(path):
        raise KeyError(name)
    with open(path) as handle:
        value = json.load(handle)
    return types.SimpleNamespace(pw_uid=value["uid"], pw_gid=value["gid"], pw_dir=value["home"], pw_shell=value["shell"])
pwd.getpwnam = fixture_passwd''',
        );
    final command = admitted
        ? 'exec 7<>${root.path}/var/lib/hermuse-provision/operation.lock\nflock -s 7\n$relocated'
        : relocated;
    return Process.run(
      'bash',
      ['-euo', 'pipefail', '-c', command],
      environment: {
        'PATH': '${root.path}/bin',
        'FAKE_ROOT': root.path,
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': '/dev/null',
        ...environment,
      },
    );
  }

  Future<ProcessResult> checked(String script, {bool admitted = true}) async {
    final result = await run(script, admitted: admitted);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return result;
  }

  Future<Map<String, Object?>> inventory() async => _frame(
    (await checked(
      remoteUninstallInventoryScript,
      admitted: false,
    )).stdout.toString(),
    'HERMUSE_UNINSTALL_INVENTORY_V1:',
  );
  Future<Map<String, Object?>> remove(
    Map<String, Object?> inventory, {
    required bool purge,
  }) async => _frame(
    (await checked(
      remoteUninstallScript(inventory['revision'] as String, purge: purge),
      admitted: false,
    )).stdout.toString(),
    'HERMUSE_UNINSTALL_OUTCOME_V1:',
  );
}

Map<String, Object?> _frame(String output, String prefix) =>
    Map<String, Object?>.from(
      jsonDecode(
        const LineSplitter()
            .convert(output)
            .singleWhere((line) => line.startsWith(prefix))
            .substring(prefix.length),
      ) as Map,
    );
Map<String, Object?> _resource(
  Map<String, Object?> inventory,
  String id,
  _Machine machine,
) {
  final relocated = id.replaceAll(
    '/home/hermes',
    '${machine.root.path}/home/hermes',
  );
  return Map<String, Object?>.from(
    (inventory['resources'] as List).cast<Map>().singleWhere(
      (entry) => entry['id'] == relocated,
    ),
  );
}

const _systemctl = r'''
args = sys.argv[1:]
action = args[0]
unit = args[-1]
if action == "list-unit-files":
    names = {path.name for directory in (root / "etc/systemd/system", root / "usr/lib/systemd/system") if directory.exists() for path in directory.glob("*.service")}
    for name in sorted(names):
        print(name + " disabled -")
elif action == "list-units":
    loaded = root / "state/loaded-units"
    if loaded.exists():
        print(loaded.read_text())
elif action == "cat":
    for directory in (root / "usr/lib/systemd/system", root / "etc/systemd/system"):
        path = directory / unit
        if path.exists():
            print(path.read_text())
        for dropin in sorted((directory / (unit + ".d")).glob("*.conf")):
            print(dropin.read_text())
elif action == "show":
    if "--property=ExecStart" in args:
        print(str(root / "etc/caddy/Caddyfile"))
    elif "--property=DropInPaths" in args:
        print("")
    else:
        name = args[1]
        if name.endswith("@.service"):
            raise SystemExit("A bare template has no effective properties")
        fields = {}
        for directory in (root / "usr/lib/systemd/system", root / "etc/systemd/system", root / "run/systemd/system"):
            path = directory / name
            if path.exists():
                for line in path.read_text().splitlines():
                    if "=" in line and not line.startswith("#"):
                        key, value = line.split("=", 1)
                        fields[key] = value
            for dropin in sorted((directory / (name + ".d")).glob("*.conf")):
                for line in dropin.read_text().splitlines():
                    if "=" in line:
                        key, value = line.split("=", 1)
                        fields[key] = value
        print("\n".join(key + "=" + fields.get(key, "") for key in ("User", "Group", "ExecStart", "Environment", "WorkingDirectory")))
elif action == "is-active":
    raise SystemExit(0 if (root / ("state/" + unit + ".active")).exists() else 1)
elif action == "disable":
    (root / ("state/" + unit + ".active")).unlink(missing_ok=True)
elif action in ("daemon-reload", "reload"):
    pass
else:
    raise SystemExit("unexpected/destructive systemctl action: " + action)
''';

const _docker = r'''
if (root / "state/docker-unavailable").exists():
    raise SystemExit("Docker daemon is unavailable")
path = root / "state/docker.json"
state = json.loads(path.read_text())
args = sys.argv[1:]
if args[:2] == ["inspect", "--type"]:
    kind, name = args[2:]
    if kind == "image":
        value = state["images"].get(name)
    elif kind == "container":
        value = state.get("web") if name == "hermuse-web" else state.get("container")
    else:
        value = state.get(kind)
    if value is None:
        print("No such " + kind, file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps([value]))
elif args[:2] == ["image", "ls"]:
    print("\n".join(state["images"]))
elif args[0] == "ps":
    for reference in state["references"]:
        print(reference)
elif args[:2] == ["rm", "-f"]:
    key = "web" if (state.get("web") or {}).get("Id") == args[2] else "container"
    assert args[2] == state[key]["Id"]
    state["references"] = [reference for reference in state["references"] if reference != args[2]]
    state[key] = None
    changed = root / "state/change-caddy-on-rm"
    if changed.exists():
        (root / "etc/caddy/hermuse-remote.caddy").write_text(changed.read_text())
elif args[:2] == ["image", "rm"]:
    state["images"].pop(args[2])
elif args[:2] == ["volume", "rm"]:
    assert not state["references"] and args[2] == "hermuse-computer-hermes-home"
    state["volume"] = None
else:
    raise SystemExit("unexpected/destructive Docker action")
path.write_text(json.dumps(state))
''';

const _ufw = r'''
path = root / "state/ufw.json"
state = json.loads(path.read_text())
args = sys.argv[1:]
if args == ["show", "added"]:
    print("Added user rules (see 'ufw status' for running firewall):\n" + "\n".join(state["rules"]))
elif args == ["status"]:
    print("Status: " + ("active" if state["active"] else "inactive"))
elif args == ["--force", "disable"]:
    state["active"] = False
elif args[:3] == ["--force", "delete", "allow"]:
    assert len(args) == 6 and args[4:] == ["comment", "Hermuse remote setup"]
    state["rules"].remove("ufw allow " + args[3] + " comment 'Hermuse remote setup'")
else:
    raise SystemExit("unexpected/destructive firewall action")
path.write_text(json.dumps(state))
''';

const _caddy = r'''
assert sys.argv[1] == "validate"
if (root / "state/caddy-invalid").exists():
    raise SystemExit("fixture Caddy validation failure")
''';

const _packages = r'''
package = sys.argv[-1]
if package in (root / "state/packages").read_text().splitlines():
    print("installed")
else:
    raise SystemExit(1)
''';

const _runuser = r'''
args = sys.argv[1:]
assert args[:3] == ["-u", "hermes", "--"]
if args[3] == "git":
    os.execvp("git", args[3:])
code = args[-1].replace("import json, sys, yaml", "import json, sys; from types import SimpleNamespace; yaml = SimpleNamespace(safe_load=json.loads, safe_dump=lambda value, **kwargs: json.dumps(value))")
# JSON is valid YAML. Exercise the actual editing code against a deterministic
# parser boundary without needing the machine's PyYAML/site packages.
result = subprocess.run([sys.executable, "-I", "-B", "-c", code], input=sys.stdin.read(), text=True, capture_output=True)
sys.stdout.write(result.stdout)
sys.stderr.write(result.stderr)
raise SystemExit(result.returncode)
''';
