import 'dart:io';

import 'package:hermuse_host/src/remote_scripts.dart';
import 'package:test/test.dart';

void main() {
  group('Canonical dashboard service', () {
    late _Machine machine;
    setUp(() async {
      machine = await _Machine.create();
      await Directory('${machine.root.path}/provision').create();
      await Directory('${machine.root.path}/etc/systemd/system')
          .create(recursive: true);
      await machine._executable('curl', 'exit 0\n');
    });
    tearDown(() => machine.root.delete(recursive: true));

    Future<ProcessResult> token() => machine.run(
      ensureDashboardTokenScript.replaceAll(
        'info.st_uid != 0',
        'info.st_uid != os.getuid()',
      ),
    );

    test('creates a private token once and preserves it across service maintenance', () async {
      final first = await token();
      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect('${first.stdout}'.trim(), matches(RegExp(r'^[A-Za-z0-9_-]{64}$')));
      final credential = machine.file('provision/dashboard.env');
      final initial = await credential.readAsString();
      expect((await credential.stat()).mode & 0x1ff, 0x180);
      for (var retry = 0; retry < 2; retry++) {
        final configure = await machine.run(configureDashboardScript());
        expect(configure.exitCode, 0, reason: '${configure.stderr}');
        final reused = await token();
        expect(reused.exitCode, 0, reason: '${reused.stderr}');
        expect(reused.stdout, first.stdout);
        expect(await credential.readAsString(), initial);
      }
      final unit = await machine
          .file('etc/systemd/system/hermuse-dashboard.service')
          .readAsLines();
      final settings = <String, String>{
        for (final line in unit)
          if (line.contains('='))
            line.split('=').first: line.substring(line.indexOf('=') + 1),
      };
      expect(settings['User'], 'hermes');
      expect(settings['Group'], 'hermes');
      expect(settings['ExecStart'], contains('--host 127.0.0.1'));
      expect(settings['ExecStart'], contains('--port 9119'));
      expect(settings['EnvironmentFile'], '-${credential.path}');
      expect(
        await machine.file('state/hermuse-dashboard.service.enabled').exists(),
        isTrue,
      );
      expect(
        await machine.file('state/hermuse-dashboard.service.active').exists(),
        isTrue,
      );
    });

    test(
      'refuses an exposed existing credential without rewriting it',
      () async {
        final credential = machine.file('provision/dashboard.env');
        const existing = 'untrusted existing credential\n';
        await credential.writeAsString(existing);
        await Process.run('chmod', ['0644', credential.path]);
        final result = await token();
        expect(result.exitCode, isNot(0));
        expect(await credential.readAsString(), existing);
      },
    );

    test('refuses a credential symlink without touching its target', () async {
      final other = machine.file('other-secret');
      await other.writeAsString('keep this secret');
      await Link(machine.file('provision/dashboard.env').path)
          .create(other.path);
      final result = await token();
      expect(result.exitCode, isNot(0));
      expect(await other.readAsString(), 'keep this secret');
    });
  }, skip: Platform.isLinux ? false : 'Linux canonical service recipes');

  group('Remote plugin staging', () {
    late _Machine machine;
    setUp(() async {
      machine = await _Machine.create();
    });
    tearDown(() async {
      await machine.root.delete(recursive: true);
    });

    test(
      'should refuse an existing directory without modifying its contents',
      () async {
        final staging = Directory('${machine.root.path}/upload');
        await staging.create();
        final unrelated = File('${staging.path}/__init__.py');
        await unrelated.writeAsString('unrelated content');
        final result = await machine.run(
          createPluginStagingScript(staging.path),
        );
        expect(result.exitCode, isNot(0));
        expect(await unrelated.readAsString(), 'unrelated content');
      },
    );

    test(
      'should refuse a symlink rather than upload into its target',
      () async {
        final target = Directory('${machine.root.path}/other-user');
        await target.create();
        final staging = Link('${machine.root.path}/upload');
        await staging.create(target.path);
        final result = await machine.run(
          createPluginStagingScript(staging.path),
        );
        expect(result.exitCode, isNot(0));
        expect(await staging.target(), target.path);
        expect(await target.list().toList(), isEmpty);
      },
    );
  }, skip: Platform.isLinux ? false : 'Linux remote shell recipes');

  group('Remote firewall transaction', () {
    late _Machine machine;
    setUp(() async {
      machine = await _Machine.create();
    });
    tearDown(() async {
      await machine.root.delete(recursive: true);
    });

    for (final active in [true, false]) {
      test(
        'should preserve existing rules and restore previously ${active ? 'active' : 'inactive'} state',
        () async {
          await machine.seedFirewall(active: active);
          final rules = await machine.file('etc/ufw/user.rules').readAsString();
          final defaults = await machine.file('etc/default/ufw').readAsString();
          final transaction = '${machine.root.path}/transaction';
          final configure = await machine.run(
            firewallConfigureScript(transaction, {2222, 80, 443}),
          );
          expect(
            configure.exitCode,
            0,
            reason: '${configure.stdout}\n${configure.stderr}',
          );
          expect(
            await machine.file('etc/ufw/user.rules').readAsString(),
            contains('8443/tcp ALLOW from 10.0.0.0/8'),
          );
          expect(
            await machine
                .file('state/hermuse-firewall-rollback.timer')
                .exists(),
            isTrue,
          );
          final rollback = await machine.run(
            restoreRollbackScript(transaction, 'hermuse-firewall-rollback'),
          );
          expect(rollback.exitCode, 0, reason: '${rollback.stderr}');
          expect(
            await machine.file('etc/ufw/user.rules').readAsString(),
            rules,
          );
          expect(
            await machine.file('etc/default/ufw').readAsString(),
            defaults,
          );
        },
      );
    }

    test('should not let a second attempt stop or restore another attempt transaction', () async {
      await machine.seedFirewall(active: true);
      final first = '${machine.root.path}/first';
      final second = '${machine.root.path}/second';
      expect(
        (await machine.run(firewallConfigureScript(first, {22, 80, 443})))
            .exitCode,
        0,
      );
      final configured = await machine
          .file('etc/ufw/user.rules')
          .readAsString();
      expect(
        (await machine.run(firewallConfigureScript(second, {2222, 80, 443})))
            .exitCode,
        isNot(0),
      );
      expect(
        (await machine.run(
          restoreRollbackScript(second, 'hermuse-firewall-rollback'),
        )).exitCode,
        0,
      );
      expect(
        await machine.file('state/hermuse-firewall-rollback.timer').exists(),
        isTrue,
      );
      expect(
        await machine.file('etc/ufw/user.rules').readAsString(),
        configured,
      );
      expect(
        (await machine.run(
          commitRollbackScript(first, 'hermuse-firewall-rollback'),
        )).exitCode,
        0,
      );
    });

    test('should finish timer cleanup if disconnect happened after commit was recorded', () async {
      await machine.seedFirewall(active: true);
      final transaction = '${machine.root.path}/transaction';
      expect(
        (await machine.run(firewallConfigureScript(transaction, {22, 80, 443})))
            .exitCode,
        0,
      );
      final configured = await machine
          .file('etc/ufw/user.rules')
          .readAsString();
      await File('$transaction/committed').writeAsString('');
      expect(
        (await machine.run('bash ${shellQuote('$transaction/rollback.sh')}'))
            .exitCode,
        0,
      );
      expect(
        await machine.file('etc/ufw/user.rules').readAsString(),
        configured,
      );
      expect(
        await machine.file('state/hermuse-firewall-rollback.timer').exists(),
        isFalse,
      );
    });

    test('should not restore over rules already committed after fresh SSH validation', () async {
      await machine.seedFirewall(active: true);
      final transaction = '${machine.root.path}/transaction';
      expect(
        (await machine.run(firewallConfigureScript(transaction, {22, 80, 443})))
            .exitCode,
        0,
      );
      final configured = await machine
          .file('etc/ufw/user.rules')
          .readAsString();
      expect(
        (await machine.run(
          commitRollbackScript(transaction, 'hermuse-firewall-rollback'),
        )).exitCode,
        0,
      );
      expect(
        (await machine.run('bash ${shellQuote('$transaction/rollback.sh')}'))
            .exitCode,
        0,
      );
      expect(
        await machine.file('etc/ufw/user.rules').readAsString(),
        configured,
      );
    });

    test('should refuse committing if the safety timer already restored the firewall', () async {
      await machine.seedFirewall(active: true);
      final transaction = '${machine.root.path}/transaction';
      expect(
        (await machine.run(firewallConfigureScript(transaction, {22, 80, 443})))
            .exitCode,
        0,
      );
      expect(
        (await machine.run('bash ${shellQuote('$transaction/rollback.sh')}'))
            .exitCode,
        0,
      );
      expect(
        await machine.file('state/hermuse-firewall-rollback.timer').exists(),
        isFalse,
      );
      // The timer's script, without connected orchestration, leaves retries
      // possible and is safe if a concurrent failure handler invokes it again.
      expect(
        (await machine.run('bash ${shellQuote('$transaction/rollback.sh')}'))
            .exitCode,
        0,
      );
      expect(
        (await machine.run(
          commitRollbackScript(transaction, 'hermuse-firewall-rollback'),
        )).exitCode,
        isNot(0),
      );
    });
  }, skip: Platform.isLinux ? false : 'Linux remote shell recipes');

  group('Remote Caddy transaction', () {
    late _Machine machine;
    setUp(() async {
      machine = await _Machine.create();
    });
    tearDown(() async {
      await machine.root.delete(recursive: true);
    });

    test('should not append another import when a wildcard already includes the site', () async {
      await machine.seedCaddy();
      final main = machine.file('etc/caddy/Caddyfile');
      final original = 'import ${machine.root.path}/etc/caddy/*.caddy\n';
      await main.writeAsString(original);
      await main.copy(machine.file('state/original-caddy').path);
      final result = await machine.run(
        caddyConfigureScript(
          '${machine.root.path}/transaction',
          'hermuse.8-8-4-4.sslip.io',
        ),
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(await main.readAsString(), original);
    });

    test('should retain existing sites and restore their exact configuration after a failure', () async {
      await machine.seedCaddy();
      final original = await machine.file('etc/caddy/Caddyfile').readAsString();
      final unrelated = await machine
          .file('etc/caddy/legacy.caddy')
          .readAsString();
      final transaction = '${machine.root.path}/transaction';
      final configured = await machine.run(
        caddyConfigureScript(transaction, 'hermuse.8-8-4-4.sslip.io'),
      );
      expect(configured.exitCode, 0, reason: '${configured.stderr}');
      expect(
        await machine.file('etc/caddy/Caddyfile').readAsString(),
        startsWith(original),
      );
      expect(
        await machine.file('etc/caddy/legacy.caddy').readAsString(),
        unrelated,
      );
      final restored = await machine.run(
        restoreRollbackScript(transaction, 'hermuse-caddy-rollback'),
      );
      expect(restored.exitCode, 0, reason: '${restored.stderr}');
      expect(
        await machine.file('etc/caddy/Caddyfile').readAsString(),
        original,
      );
      expect(
        await machine.file('etc/caddy/legacy.caddy').readAsString(),
        unrelated,
      );
      expect(
        await machine.file('etc/caddy/hermuse-remote.caddy').exists(),
        isFalse,
      );
      expect(await machine.file('state/caddy.active').exists(), isTrue);
    });

    test(
      'should not overwrite an unrelated file in the intended site path',
      () async {
        await machine.seedCaddy();
        final site = machine.file('etc/caddy/hermuse-remote.caddy');
        await site.writeAsString(
          'another.example.com { respond "not Hermuse" }\n',
        );
        final original = await site.readAsString();
        final configured = await machine.run(
          caddyConfigureScript(
            '${machine.root.path}/transaction',
            'hermuse.8-8-4-4.sslip.io',
          ),
        );
        expect(configured.exitCode, isNot(0));
        expect(await site.readAsString(), original);
        expect(
          await machine.file('state/hermuse-caddy-rollback.timer').exists(),
          isFalse,
        );
      },
    );
  }, skip: Platform.isLinux ? false : 'Linux remote shell recipes');

  group('Remote read-only Caddy inventory', () {
    late _Machine machine;
    setUp(() async => machine = await _Machine.create());
    tearDown(() async => machine.root.delete(recursive: true));

    test('a broker on the bare hostname survives dedicated-site setup and repeated runs', () async {
      await machine.seedCaddy();
      final main = machine.file('etc/caddy/Caddyfile');
      await Directory('${machine.root.path}/etc/caddy/sites').create();
      final broker = machine.file('etc/caddy/sites/omp-broker.caddy');
      const bare = '217-76-55-191.sslip.io';
      const domain = 'hermuse.217-76-55-191.sslip.io';
      const brokerBytes = '$bare {\n  reverse_proxy 127.0.0.1:8765\n}\n';
      await broker.writeAsString(brokerBytes);
      final original = 'import ${machine.root.path}/etc/caddy/sites/*.caddy\n';
      await main.writeAsString(original);
      await main.copy(machine.file('state/original-caddy').path);
      final before = await machine.run(caddyHealthScript(domain));
      expect(before.exitCode, 0, reason: '${before.stderr}');
      expect('${before.stdout}'.trim(), 'HERMUSE_HEALTH_V1:repair');
      for (final attempt in ['one', 'two']) {
        await main.copy(machine.file('state/original-caddy').path);
        final directory = '${machine.root.path}/$attempt';
        final configured = await machine.run(
          caddyConfigureScript(directory, domain),
        );
        expect(configured.exitCode, 0, reason: '${configured.stderr}');
        final committed = await machine.run(
          commitRollbackScript(directory, 'hermuse-caddy-rollback'),
        );
        expect(committed.exitCode, 0, reason: '${committed.stderr}');
        final healthy = await machine.run(caddyHealthScript(domain));
        expect(healthy.exitCode, 0, reason: '${healthy.stderr}');
        expect('${healthy.stdout}'.trim(), 'HERMUSE_HEALTH_V1:ready');
        expect(await broker.readAsString(), brokerBytes);
        expect(
          await main.readAsString(),
          '$original\nimport ${machine.root.path}/etc/caddy/hermuse-remote.caddy\n',
        );
      }
    });

    test('a shared managed fragment cannot lose its unrelated broker during repair', () async {
      await machine.seedCaddy();
      const domain = 'hermuse.217-76-55-191.sslip.io';
      final main = machine.file('etc/caddy/Caddyfile');
      final site = machine.file('etc/caddy/hermuse-remote.caddy');
      final original =
          '${caddySite(domain)}'
          '217-76-55-191.sslip.io {\n  reverse_proxy 127.0.0.1:8765\n}\n';
      await site.writeAsString(original);
      await Process.run('chmod', ['0644', site.path]);
      final imported = 'import ${site.path}\n';
      await main.writeAsString(imported);
      await main.copy(machine.file('state/original-caddy').path);
      final configured = await machine.run(
        caddyConfigureScript('${machine.root.path}/shared', domain),
      );
      expect(await site.readAsString(), original);
      expect(configured.exitCode, isNot(0));
      expect(await main.readAsString(), imported);
      expect(await machine.file('state/caddy.active').exists(), isTrue);
      expect(
        await machine.file('state/hermuse-caddy-rollback.timer').exists(),
        isFalse,
      );
      expect(
        await machine.file('provision/hermuse-caddy-rollback.owner').exists(),
        isFalse,
      );
    });

    test('dedicated owned routing drift repairs without rewriting the root imports', () async {
      await machine.seedCaddy();
      const domain = 'hermuse.217-76-55-191.sslip.io';
      final main = machine.file('etc/caddy/Caddyfile');
      final site = machine.file('etc/caddy/hermuse-remote.caddy');
      await site.writeAsString(
        caddySite(domain).replaceFirst('127.0.0.1:9119', '127.0.0.1:9120'),
      );
      await Process.run('chmod', ['0644', site.path]);
      final imported = '${await main.readAsString()}\nimport ${site.path}\n';
      await main.writeAsString(imported);
      await main.copy(machine.file('state/original-caddy').path);
      final before = await machine.run(caddyHealthScript(domain));
      expect(before.exitCode, 0, reason: '${before.stderr}');
      expect('${before.stdout}'.trim(), 'HERMUSE_HEALTH_V1:repair');
      final directory = '${machine.root.path}/drift';
      final configured = await machine.run(
        caddyConfigureScript(directory, domain),
      );
      expect(configured.exitCode, 0, reason: '${configured.stderr}');
      expect(await site.readAsString(), caddySite(domain));
      final committed = await machine.run(
        commitRollbackScript(directory, 'hermuse-caddy-rollback'),
      );
      expect(committed.exitCode, 0, reason: '${committed.stderr}');
      final healthy = await machine.run(caddyHealthScript(domain));
      expect(healthy.exitCode, 0, reason: '${healthy.stderr}');
      expect('${healthy.stdout}'.trim(), 'HERMUSE_HEALTH_V1:ready');
      expect(await main.readAsString(), imported);
    });

    for (final upstream in ['127.0.0.1:8765', '127.0.0.1:9119']) {
      test(
        'refuses an unrelated target route to $upstream before any transaction',
        () async {
          await machine.seedCaddy();
          final main = machine.file('etc/caddy/Caddyfile');
          const domain = 'hermuse.217-76-55-191.sslip.io';
          final original = '$domain {\n  reverse_proxy $upstream\n}\n';
          await main.writeAsString(original);
          final health = await machine.run(caddyHealthScript(domain));
          expect(health.exitCode, isNot(0));
          final repair = await machine.run(
            caddyConfigureScript('${machine.root.path}/blocked', domain),
          );
          expect(repair.exitCode, isNot(0));
          expect(await main.readAsString(), original);
          expect(
            await machine.file('state/hermuse-caddy-rollback.timer').exists(),
            isFalse,
          );
          expect(
            await machine
                .file('provision/hermuse-caddy-rollback.owner')
                .exists(),
            isFalse,
          );
        },
      );
    }
    test('an orphan owned fragment cannot adopt an unrelated identical target upstream', () async {
      await machine.seedCaddy();
      const domain = 'hermuse.217-76-55-191.sslip.io';
      final main = machine.file('etc/caddy/Caddyfile');
      final original = '$domain {\n  reverse_proxy 127.0.0.1:9119\n}\n';
      await main.writeAsString(original);
      await machine
          .file('etc/caddy/hermuse-remote.caddy')
          .writeAsString(caddySite(domain));
      await Process.run('chmod', [
        '0644',
        machine.file('etc/caddy/hermuse-remote.caddy').path,
      ]);
      final inspected = await machine.run(caddyHealthScript(domain));
      expect(inspected.exitCode, isNot(0));
      expect(await main.readAsString(), original);
      expect(
        await machine.file('state/hermuse-caddy-rollback.timer').exists(),
        isFalse,
      );
    });

    test('an owned dashboard fragment gains the web app site and is classified ready with both routes', () async {
      await machine.seedCaddy();
      const domain = 'hermuse.217-76-55-191.sslip.io';
      final web = webAppDomain(domain);
      final main = machine.file('etc/caddy/Caddyfile');
      final site = machine.file('etc/caddy/hermuse-remote.caddy');
      final first = '${machine.root.path}/first';
      expect(
        (await machine.run(caddyConfigureScript(first, domain))).exitCode,
        0,
      );
      await machine.run(commitRollbackScript(first, 'hermuse-caddy-rollback'));
      final imported = await main.readAsString();
      await main.copy(machine.file('state/original-caddy').path);
      final before = await machine.run(
        caddyHealthScript(domain, webDomain: web),
      );
      expect(before.exitCode, 0, reason: '${before.stderr}');
      expect('${before.stdout}'.trim(), 'HERMUSE_HEALTH_V1:repair');
      final directory = '${machine.root.path}/web';
      final configured = await machine.run(
        caddyConfigureScript(directory, domain, webDomain: web),
      );
      expect(configured.exitCode, 0, reason: '${configured.stderr}');
      expect(await site.readAsString(), caddySite(domain, webDomain: web));
      expect(await main.readAsString(), imported);
      await machine.run(
        commitRollbackScript(directory, 'hermuse-caddy-rollback'),
      );
      final healthy = await machine.run(
        caddyHealthScript(domain, webDomain: web),
      );
      expect(healthy.exitCode, 0, reason: '${healthy.stderr}');
      expect('${healthy.stdout}'.trim(), 'HERMUSE_HEALTH_V1:ready');
      // The owned web block is recognized, not foreign, when it is not wanted.
      final dashboardOnly = await machine.run(caddyHealthScript(domain));
      expect(dashboardOnly.exitCode, 0, reason: '${dashboardOnly.stderr}');
      expect('${dashboardOnly.stdout}'.trim(), 'HERMUSE_HEALTH_V1:repair');
    });

    test(
      'refuses a foreign route on the web app host before any transaction',
      () async {
        await machine.seedCaddy();
        const domain = 'hermuse.217-76-55-191.sslip.io';
        final web = webAppDomain(domain);
        final main = machine.file('etc/caddy/Caddyfile');
        final original = '$web {\n  reverse_proxy 127.0.0.1:9120\n}\n';
        await main.writeAsString(original);
        await main.copy(machine.file('state/original-caddy').path);
        expect(
          (await machine.run(caddyHealthScript(domain, webDomain: web)))
              .exitCode,
          isNot(0),
        );
        final repair = await machine.run(
          caddyConfigureScript(
            '${machine.root.path}/blocked',
            domain,
            webDomain: web,
          ),
        );
        expect(repair.exitCode, isNot(0));
        expect(await main.readAsString(), original);
        expect(
          await machine.file('etc/caddy/hermuse-remote.caddy').exists(),
          isFalse,
        );
        expect(
          await machine.file('state/hermuse-caddy-rollback.timer').exists(),
          isFalse,
        );
        // Without the web app, that host is irrelevant to the dashboard route.
        final dashboard = await machine.run(
          caddyConfigureScript('${machine.root.path}/dashboard', domain),
        );
        expect(dashboard.exitCode, 0, reason: '${dashboard.stderr}');
      },
    );

    test(
      'a managed fragment with an extra unrelated host is foreign',
      () async {
        await machine.seedCaddy();
        const domain = 'hermuse.217-76-55-191.sslip.io';
        final site = machine.file('etc/caddy/hermuse-remote.caddy');
        final original = caddySite(
          domain,
          webDomain: 'other.217-76-55-191.sslip.io',
        );
        await site.writeAsString(original);
        await Process.run('chmod', ['0644', site.path]);
        final configured = await machine.run(
          caddyConfigureScript(
            '${machine.root.path}/extra',
            domain,
            webDomain: webAppDomain(domain),
          ),
        );
        expect(configured.exitCode, isNot(0));
        expect(await site.readAsString(), original);
      },
    );
  }, skip: Platform.isLinux ? false : 'Linux remote shell recipes');
}

/// Executes the actual shell recipes against isolated files and fake privileged
/// commands. The timer fake refuses arming if any protected bytes changed first.
final class _Machine {
  _Machine(this.root);
  final Directory root;
  File file(String path) => File('${root.path}/$path');

  static Future<_Machine> create() async {
    final machine = _Machine(
      await Directory.systemTemp.createTemp('hermuse-remote-scripts-'),
    );
    for (final directory in [
      'bin',
      'state',
      'etc/ufw',
      'etc/default',
      'etc/caddy',
    ]) {
      await Directory('${machine.root.path}/$directory')
          .create(recursive: true);
    }
    await machine._executable('systemd-run', r'''
unit=
for arg in "$@"; do case "$arg" in --unit=*) unit=${arg#--unit=};; esac; done
case "$unit" in
  hermuse-firewall-rollback)
    cmp "$FAKE_ROOT/etc/ufw/user.rules" "$FAKE_ROOT/state/original-rules"
    cmp "$FAKE_ROOT/etc/default/ufw" "$FAKE_ROOT/state/original-defaults" ;;
  hermuse-caddy-rollback)
    cmp "$FAKE_ROOT/etc/caddy/Caddyfile" "$FAKE_ROOT/state/original-caddy" ;;
  *) exit 41 ;;
esac
touch "$FAKE_ROOT/state/$unit.timer"
''');
    await machine._executable('systemctl', r'''
action=$1
unit=${@: -1}
case "$action" in
  reset-failed) ;;
  is-active) test -e "$FAKE_ROOT/state/$unit.active" || test -e "$FAKE_ROOT/state/$unit" ;;
  is-enabled) test -e "$FAKE_ROOT/state/$unit.enabled" ;;
  enable) touch "$FAKE_ROOT/state/$unit.enabled" ;;
  disable) rm -f "$FAKE_ROOT/state/$unit.enabled" ;;
  stop) rm -f "$FAKE_ROOT/state/$unit" "$FAKE_ROOT/state/$unit.active" ;;
  reload-or-restart) touch "$FAKE_ROOT/state/$unit.active" ;;
  restart) touch "$FAKE_ROOT/state/$unit.active" ;;
  daemon-reload) ;;
  show) printf '%s\n' "caddy run --config $FAKE_ROOT/etc/caddy/Caddyfile" ;;
  *) exit 42 ;;
esac
''');
    await machine._executable('ufw', r'''
if [ "$1" = status ]; then
  if grep -q '^ENABLED=yes$' "$FAKE_ROOT/etc/default/ufw"; then echo 'Status: active'; else echo 'Status: inactive'; fi
  exit 0
fi
[ -f "$FAKE_ROOT/state/hermuse-firewall-rollback.timer" ] || { echo 'Mutation before rollback was armed' >&2; exit 43; }
case "$1:$2" in
  insert:1) printf '%s\n' "$4 ALLOW from Anywhere" >> "$FAKE_ROOT/etc/ufw/user.rules" ;;
  --force:enable) printf 'ENABLED=yes\nPOLICY=preserved\n' > "$FAKE_ROOT/etc/default/ufw" ;;
  --force:disable) printf 'ENABLED=no\nPOLICY=preserved\n' > "$FAKE_ROOT/etc/default/ufw" ;;
  *) echo 'Unsupported/destructive firewall operation' >&2; exit 44 ;;
esac
''');
    await machine._executable('caddy', r'''
if [ -n "${HERMUSE_TEST_CADDY:-}" ]; then exec "$HERMUSE_TEST_CADDY" "$@"; fi
case "$1" in
  adapt)
    shift
    python3 -B -c '
import glob, json, re, sys
from pathlib import Path
path = sys.argv[sys.argv.index("--config") + 1]
seen = set()
routes = []
def include(path):
    text = Path(path).read_text()
    for imported in re.findall(r"^\s*import\s+([^\s]+)", text, re.M):
        for child in glob.glob(imported):
            include(child)
    for domain, marker, upstream in re.findall(r"([^\s{]+)\s*\{\s*(vars hermuse_remote_installer v1\s*)?reverse_proxy\s+([^\s}]+)\s*\}", text):
        if domain in seen:
            raise SystemExit("ambiguous site definition: " + domain)
        seen.add(domain)
        chain = [{"handler": "vars", "hermuse_remote_installer": "v1"}] if marker else []
        chain.append({"handler": "reverse_proxy", "upstreams": [{"dial": upstream}]})
        routes.append({"match": [{"host": [domain]}], "handle": chain})
include(path)
print(json.dumps({"apps": {"http": {"servers": {"srv0": {"routes": routes}}}}}))
' "$@" ;;
  validate) ;;
  *) exit 45 ;;
esac
''');
    await machine._executable('stat', r'''
if [ "$1:$2" = '-c:%u' ]; then printf '0\n'; else exec /usr/bin/stat "$@"; fi
''');
    return machine;
  }

  Future<void> _executable(String name, String script) async {
    final executable = file('bin/$name');
    await executable.writeAsString('#!/bin/bash\nset -euo pipefail\n$script');
    final result = await Process.run('chmod', ['0700', executable.path]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
  }

  Future<void> seedFirewall({required bool active}) async {
    await file('etc/ufw/user.rules').writeAsString(
      '8443/tcp ALLOW from 10.0.0.0/8\n25/tcp DENY from Anywhere\n',
    );
    await file('etc/default/ufw')
        .writeAsString('ENABLED=${active ? 'yes' : 'no'}\nPOLICY=preserved\n');
    await file('etc/ufw/user.rules').copy(file('state/original-rules').path);
    await file('etc/default/ufw').copy(file('state/original-defaults').path);
  }

  Future<void> seedCaddy() async {
    await file('etc/caddy/Caddyfile').writeAsString(
      'legacy.example.com {\n  reverse_proxy 127.0.0.1:8080\n}\n',
    );
    await file('etc/caddy/legacy.caddy')
        .writeAsString('# independently managed site\n');
    await file('etc/caddy/Caddyfile').copy(file('state/original-caddy').path);
    await file('state/caddy.active').writeAsString('');
    await file('state/caddy.enabled').writeAsString('');
    await Process.run('chmod', [
      '0644',
      file('etc/caddy/Caddyfile').path,
      file('etc/caddy/legacy.caddy').path,
    ]);
  }

  Future<ProcessResult> run(String script) => Process.run(
    'bash',
    [
      '-euo',
      'pipefail',
      '-c',
      script
          .replaceAll('/etc/caddy', '${root.path}/etc/caddy')
          .replaceAll('/etc/systemd/system', '${root.path}/etc/systemd/system')
          .replaceAll(provisionRoot, '${root.path}/provision')
          .replaceAll('tar -C / ', 'tar -C ${shellQuote(root.path)} '),
    ],
    environment: {
      'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
      'FAKE_ROOT': root.path,
      'HOME': root.path,
      'XDG_DATA_HOME': '${root.path}/data',
      'XDG_CONFIG_HOME': '${root.path}/config',
    },
  );
}
