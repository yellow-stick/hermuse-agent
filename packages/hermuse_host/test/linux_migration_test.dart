import 'dart:convert';
import 'dart:io';

import 'package:hermuse_host/src/linux_migration.dart';
import 'package:test/test.dart';

const _atomicCutover =
    "            os.rename(current['revision'], os.path.basename(DEST), "
    'src_dir_fd=staging_parent, dst_dir_fd=target_parent)';

void main() {
  group('Legacy Hermes migration', () {
    late _Fixture fixture;

    setUp(() async => fixture = await _Fixture.create());
    tearDown(() async => fixture.root.delete(recursive: true));

    test('absent and runtime-only homes have no migration inventory', () async {
      expect(await fixture.inspect(), isNull);
      await fixture.put('hermes-agent/venv/bin/python', 'runtime');
      expect(await fixture.inspect(), isNull);
    });

    test(
      'skips executable trees but preserves model caches and credentials',
      () async {
        await fixture.put('hermes-agent/venv/bin/python', 'old runtime');
        await fixture.put('models/cache/model.bin', 'model weights');
        await fixture.put('models/credentials.json', '{"api_key":"keep"}');
        final inventory = (await fixture.inspect())!;
        await fixture.put(
          'hermes-agent/venv/bin/python',
          'replacement runtime',
        );
        expect((await fixture.inspect())!.revision, inventory.revision);
        final result = await fixture.migrate(inventory);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        final backup =
            (jsonDecode(result.stdout as String) as Map)['backup'] as String;
        expect(
          await File('$backup/models/cache/model.bin').readAsString(),
          'model weights',
        );
        expect(
          await File('${fixture.destination}/models/credentials.json')
              .readAsString(),
          '{"api_key":"keep"}',
        );
        expect(await Directory('$backup/hermes-agent').exists(), isFalse);
      },
    );

    test('inventory serializes and binds content and file identity', () async {
      await fixture.put('config.yaml', 'model: private-model\n');
      final first = (await fixture.inspect())!;
      expect(
        LegacyHermesMigration.fromJson(first.toJson()).toJson(),
        first.toJson(),
      );
      expect(first.summary, isNot(contains('private-model')));
      await fixture.put('config.yaml', 'model: changed-model\n');
      expect((await fixture.inspect())!.revision, isNot(first.revision));
      final denied = await fixture.migrate(first);
      expect(denied.exitCode, isNot(0));
      expect(denied.stderr, contains('explicitly confirm'));
      expect(await Directory(fixture.destination).exists(), isFalse);
    });

    test(
      'preserves source, verified backup, profiles, secrets and schedules',
      () async {
        await fixture.put(
          'config.yaml',
          'workspace: ${fixture.source}/workspace\n',
        );
        await fixture.put('.env', 'MODEL_API_KEY=private-secret\n');
        await fixture.put('profiles/research/SOUL.md', 'Research carefully.');
        await fixture.put('cron/jobs.json', '{"jobs":[{"id":"mine"}]}');
        await fixture.put(
          'sessions/session.json',
          '{"message":"keep conversation"}',
        );
        final database = await Process.run('/usr/bin/python3', [
          '-I',
          '-c',
          'import sqlite3,sys; db=sqlite3.connect(sys.argv[1]); '
              'db.execute("CREATE TABLE sessions (id TEXT, message TEXT)"); '
              'db.execute("INSERT INTO sessions VALUES (?, ?)", ("thread", "preserved")); '
              'db.commit(); db.close()',
          '${fixture.source}/state.db',
        ]);
        expect(database.exitCode, 0, reason: database.stderr.toString());
        await fixture.put('hermes-agent/venv/bin/python', 'never execute this');
        await fixture.put(
          'plugins/hermuse/plugin.py',
          'raise RuntimeError("must not import")',
        );
        await Directory('${fixture.source}/workspace').create();
        await Link('${fixture.source}/profiles/research/.env')
            .create('../../.env');
        final inventory = (await fixture.inspect())!;
        final result = await fixture.migrate(inventory);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        final outcome = jsonDecode(result.stdout as String) as Map;
        final backup = outcome['backup'] as String;
        expect(
          await File('$backup/.env').readAsString(),
          'MODEL_API_KEY=private-secret\n',
        );
        expect(
          await File('${fixture.source}/config.yaml').readAsString(),
          contains(fixture.source),
        );
        expect(
          await File('${fixture.destination}/config.yaml').readAsString(),
          contains(fixture.destination),
        );
        expect(
          await File('${fixture.destination}/profiles/research/.env')
              .readAsString(),
          'MODEL_API_KEY=private-secret\n',
        );
        expect(
          await File('${fixture.destination}/state.db').readAsBytes(),
          await File('${fixture.source}/state.db').readAsBytes(),
        );
        expect(
          await File('${fixture.destination}/cron/jobs.json').readAsString(),
          '{"jobs":[{"id":"mine"}]}',
        );
        expect(
          await Directory('${fixture.destination}/hermes-agent').exists(),
          isFalse,
        );
        expect(await Directory('$backup/hermes-agent').exists(), isFalse);
        expect(
          await File('${fixture.source}/hermes-agent/venv/bin/python')
              .readAsString(),
          'never execute this',
        );
        expect(
          (await File('${fixture.destination}/.env').stat()).mode & 0x1ff,
          0x180,
        );
        expect(result.stdout, isNot(contains('private-secret')));
        await File('${fixture.destination}/config.yaml')
            .writeAsString('updated by installer');
        final retry = await fixture.migrate(inventory);
        expect(retry.exitCode, 0, reason: retry.stderr.toString());
        expect((jsonDecode(retry.stdout as String) as Map)['reused'], isTrue);
        expect(
          await File('${fixture.destination}/config.yaml').readAsString(),
          'updated by installer',
        );
      },
    );

    test(
      'refuses meaningful destination without merging or making a backup',
      () async {
        await fixture.put('config.yaml', 'model: legacy');
        await Directory(fixture.destination).create();
        await File('${fixture.destination}/keep').writeAsString('canonical');
        final result = await fixture.migrate((await fixture.inspect())!);
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('never merges'));
        expect(
          await File('${fixture.destination}/keep').readAsString(),
          'canonical',
        );
      },
    );

    for (final canonical in [false, true]) {
      test('refuses ${canonical ? 'canonical' : 'source'} sibling-prefix configuration', () async {
        final path =
            '${canonical ? fixture.destination : fixture.source}-workspace/project';
        await fixture.put('config.yaml', 'workspace: "$path"\n');
        final inventory = (await fixture.inspect())!;
        final result = await fixture.migrate(inventory);
        expect(result.exitCode, isNot(0));
        expect(result.stderr, contains('external user paths'));
        expect(await Directory(fixture.destination).exists(), isFalse);
        expect(
          await File('${fixture.source}/config.yaml').readAsString(),
          'workspace: "$path"\n',
        );
        expect(
          await File(
            '${fixture.root.path}/state/migration-${inventory.revision}/backup/config.yaml',
          ).readAsString(),
          'workspace: "$path"\n',
        );
      });
    }

    test('relocates exact home values and descendants only', () async {
      await fixture.put(
        'settings.json',
        jsonEncode({
          'home': fixture.source,
          'workspace': '${fixture.source}/workspace',
        }),
      );
      final result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        jsonDecode(
          await File('${fixture.destination}/settings.json').readAsString(),
        ),
        {
          'home': fixture.destination,
          'workspace': '${fixture.destination}/workspace',
        },
      );
    });

    test('refuses a replaceable private staging ancestor', () async {
      await fixture.put('config.yaml', 'model: legacy');
      final staging = Directory('${fixture.root.path}/.hermuse-migrations');
      await staging.create();
      await Process.run('/bin/chmod', ['777', staging.path]);
      final result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('staging must be private'));
      expect(await Directory(fixture.destination).exists(), isFalse);
      expect(await staging.list().toList(), isEmpty);
      expect(
        await File('${fixture.source}/config.yaml').readAsString(),
        'model: legacy',
      );
    });

    test(
      'service account cannot replace staging during privileged copy',
      () async {
        final uid = await Process.run('/usr/bin/id', ['-u']);
        if ((uid.stdout as String).trim() != '0') {
          markTestSkipped(
            'Requires root to exercise a distinct attacking service uid.',
          );
          return;
        }
        await fixture.put('config.yaml', 'model: legacy');
        final external = Directory('${fixture.root.path}/unrelated');
        await external.create();
        await File('${external.path}/sentinel').writeAsString('untouched');
        await Process.run('/bin/chmod', ['711', fixture.root.path]);
        await Process.run('/bin/chown', [
          '65534:65534',
          '${fixture.root.path}/canonical',
        ]);
        final status = '${fixture.root.path}/attack-status';
        final result = await fixture.migrate(
          (await fixture.inspect())!,
          transform: (script) => script
              .replaceFirst('pwd.getpwuid(os.geteuid())', 'pwd.getpwuid(65534)')
              .replaceFirst(
                '            snapshot(backup, copy_to=stage, expected_uid=ROOT_UID)',
                '''
            attacker = os.fork()
            if attacker == 0:
                os.setgroups([])
                os.setgid(65534)
                os.setuid(65534)
                try:
                    os.rename(stage, stage + '-stolen')
                    os.symlink(${jsonEncode(external.path)}, stage)
                except PermissionError:
                    os._exit(0)
                os._exit(12)
            _, status = os.waitpid(attacker, 0)
            with open(${jsonEncode(status)}, 'w') as stream:
                stream.write(str(os.waitstatus_to_exitcode(status)))
            snapshot(backup, copy_to=stage, expected_uid=ROOT_UID)''',
              ),
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(await File(status).readAsString(), '0');
        expect(
          await File('${external.path}/sentinel').readAsString(),
          'untouched',
        );
        expect(await File('${external.path}/config.yaml').exists(), isFalse);
        expect(
          await File('${fixture.destination}/config.yaml').readAsString(),
          'model: legacy',
        );
        expect(
          await File('${fixture.source}/config.yaml').readAsString(),
          'model: legacy',
        );
        final backup =
            (jsonDecode(result.stdout as String) as Map)['backup'] as String;
        expect(
          await File('$backup/config.yaml').readAsString(),
          'model: legacy',
        );
        expect((await Directory(backup).parent.stat()).mode & 0x3f, 0);
      },
    );

    for (final entry in ['canonical', '.hermuse-migrations']) {
      test('refuses a symlinked $entry without external writes', () async {
        await fixture.put('config.yaml', 'model: legacy');
        final external = Directory('${fixture.root.path}/unrelated');
        await external.create();
        await File('${external.path}/sentinel').writeAsString('untouched');
        final replaced = Directory('${fixture.root.path}/$entry');
        if (await replaced.exists()) await replaced.delete();
        await Link(replaced.path).create(external.path);
        final result = await fixture.migrate((await fixture.inspect())!);
        expect(result.exitCode, isNot(0));
        expect(
          await File('${external.path}/sentinel').readAsString(),
          'untouched',
        );
        expect(await external.list().length, 1);
        expect(
          await File('${fixture.source}/config.yaml').readAsString(),
          'model: legacy',
        );
      });
    }

    test('refuses escaping symlink and symlinked source ancestors', () async {
      await fixture.put('config.yaml', 'model: legacy');
      await Link('${fixture.source}/secret').create('/etc/passwd');
      final result = await fixture.run(
        inspectLegacyHermesScript(fixture.source),
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('escapes'));
      await Link('${fixture.source}/secret').delete();
      await Directory(fixture.source).rename('${fixture.source}-original');
      await Link(fixture.source).create('${fixture.source}-original');
      expect(
        (await fixture.run(inspectLegacyHermesScript(fixture.source))).exitCode,
        isNot(0),
      );
    });

    test('refuses a process with the source home open', () async {
      await fixture.put('config.yaml', 'model: legacy');
      final process = Directory('${fixture.proc}/424242');
      await Directory('${process.path}/fd').create(recursive: true);
      await Link('${process.path}/cwd').create(fixture.source);
      final result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Stop processes'));
      expect(await Directory(fixture.destination).exists(), isFalse);
    });

    test(
      'rejects world-writable files and mismatched authenticated owner',
      () async {
        await fixture.put('config.yaml', 'model: legacy');
        final inventory = (await fixture.inspect())!;
        final mismatch = await fixture.migrate(
          inventory,
          transform: (script) => script.replaceFirst(
            "caller = os.environ.get('PKEXEC_UID')",
            "caller = str(os.getuid() + 1)",
          ),
        );
        expect(mismatch.exitCode, isNot(0));
        expect(mismatch.stderr, contains('authenticated calling account'));
        await Process.run('/bin/chmod', [
          '666',
          '${fixture.source}/config.yaml',
        ]);
        final writable = await fixture.run(
          inspectLegacyHermesScript(fixture.source),
        );
        expect(writable.exitCode, isNot(0));
        expect(writable.stderr, contains('Group/world-writable'));
      },
    );

    test('rejects a late destination symlink without writing through it', () async {
      await fixture.put('config.yaml', 'model: legacy');
      final other = Directory('${fixture.root.path}/unrelated');
      await other.create();
      await File('${other.path}/sentinel').writeAsString('untouched');
      final result = await fixture.migrate(
        (await fixture.inspect())!,
        transform: (script) => script.replaceFirst(
          _atomicCutover,
          '            os.symlink(${jsonEncode(other.path)}, DEST)\n$_atomicCutover',
        ),
      );
      expect(result.exitCode, isNot(0));
      expect(await File('${other.path}/sentinel').readAsString(), 'untouched');
      expect(await File('${other.path}/config.yaml').exists(), isFalse);
    });

    test(
      'recovers interrupted atomic cutover and rejects tampered backup',
      () async {
        await fixture.put('config.yaml', 'model: legacy');
        final inventory = (await fixture.inspect())!;
        final interrupted = await fixture.migrate(
          inventory,
          transform: (script) => script.replaceFirst(
            _atomicCutover,
            '$_atomicCutover\n            os._exit(91)',
          ),
        );
        expect(interrupted.exitCode, 91);
        var retry = await fixture.migrate(inventory);
        expect(retry.exitCode, 0, reason: retry.stderr.toString());
        final backup =
            (jsonDecode(retry.stdout as String) as Map)['backup'] as String;
        await File('$backup/config.yaml').writeAsString('tampered');
        retry = await fixture.migrate(inventory);
        expect(retry.exitCode, isNot(0));
        expect(retry.stderr, contains('backup no longer matches'));
        expect(
          await File('${fixture.destination}/config.yaml').readAsString(),
          'model: legacy',
        );
      },
    );

    test(
      'rechecks consent after copy and rolls back a failed cutover',
      () async {
        await fixture.put('config.yaml', 'model: legacy');
        final inventory = (await fixture.inspect())!;
        final raced = await fixture.migrate(
          inventory,
          transform: (script) => script.replaceFirst(
            '            prepare(stage)\n',
            "            prepare(stage)\n            with open(os.path.join(SOURCE, 'changed'), 'w') as stream:\n                stream.write('race')\n",
          ),
        );
        expect(raced.exitCode, isNot(0));
        expect(raced.stderr, contains('changed during migration'));
        expect(await Directory(fixture.destination).exists(), isFalse);
        final fresh = (await fixture.inspect())!;
        final failed = await fixture.migrate(
          fresh,
          transform: (script) => script.replaceFirst(
            _atomicCutover,
            "            raise OSError('injected cutover failure')",
          ),
        );
        expect(failed.exitCode, isNot(0));
        expect(
          await File('${fixture.source}/config.yaml').readAsString(),
          'model: legacy',
        );
        expect(await Directory(fixture.destination).exists(), isFalse);
        final retry = await fixture.migrate(fresh);
        expect(retry.exitCode, 0, reason: retry.stderr.toString());
      },
    );

    test('converts desktop subscription auth without exposing or replacing API credentials', () async {
      await fixture.put(
        'config.yaml',
        'base_url: http://127.0.0.1:45678/v1\napi_key: desktop-api\n',
      );
      await fixture.put('cliproxy/config.yaml', '''host: "127.0.0.1"
port: 45678
auth-dir: ${jsonEncode('${fixture.source}/cliproxy/auth')}
api-keys:
  - "desktop-api"
remote-management:
  allow-remote: false
  secret-key: "\$2a\$bcrypt-not-plaintext"
  disable-control-panel: true
discovery:
  enabled: false
''');
      await fixture.put(
        'cliproxy/auth/account.json',
        '{"refresh_token":"oauth-secret"}',
      );
      final result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bridge = '${fixture.destination}/hermuse/bridge';
      final keys =
          jsonDecode(await File('$bridge/keys.json').readAsString()) as Map;
      expect(keys['port'], 45678);
      expect(keys['api_key'], 'desktop-api');
      expect(keys['management_key'], isNot(contains('bcrypt')));
      expect(
        await File('$bridge/auth/account.json').readAsString(),
        '{"refresh_token":"oauth-secret"}',
      );
      expect(
        await File('$bridge/config.yaml').readAsString(),
        contains('$bridge/auth'),
      );
      expect(result.stdout, isNot(contains('desktop-api')));
      expect(result.stderr, isNot(contains('oauth-secret')));
    });

    test('refuses missing bridge configuration and preserves computer prerequisites', () async {
      await fixture.put('cliproxy/auth/account.json', '{"token":"keep"}');
      var result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('no complete configuration'));
      await Directory('${fixture.source}/cliproxy').delete(recursive: true);
      await fixture.put(
        'hermuse/computer/runtime.json',
        '{"backend":"docker","container":"legacy-owned"}',
      );
      result = await fixture.migrate((await fixture.inspect())!);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('Docker data is untouched'));
      expect(
        await File('${fixture.source}/hermuse/computer/runtime.json').exists(),
        isTrue,
      );
      expect(await Directory(fixture.destination).exists(), isFalse);
    });
  }, skip: Platform.isLinux ? false : 'Linux filesystem migration recipes');
}

final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  String get source => '${root.path}/caller/.hermes';
  String get destination => '${root.path}/canonical/.hermes';
  String get proc => '${root.path}/proc';

  static Future<_Fixture> create() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('hermuse-migration-'),
    );
    await Directory('${fixture.root.path}/caller').create();
    await Directory('${fixture.root.path}/canonical').create();
    await Directory(fixture.proc).create();
    return fixture;
  }

  Future<void> put(String relative, String contents) async {
    final file = File('$source/$relative');
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
    await Process.run('/bin/chmod', ['600', file.path]);
  }

  Future<LegacyHermesMigration?> inspect() async {
    final result = await run(inspectLegacyHermesScript(source));
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final json = jsonDecode(result.stdout as String);
    return json == null
        ? null
        : LegacyHermesMigration.fromJson(json as Map<String, dynamic>);
  }

  Future<ProcessResult> migrate(
    LegacyHermesMigration inventory, {
    String Function(String)? transform,
  }) => run(migrateLegacyHermesScript(inventory), transform: transform);

  Future<ProcessResult> run(
    String script, {
    String Function(String)? transform,
  }) async {
    script = script
        .replaceFirst(
          "DEST = '/home/hermes/.hermes'",
          'DEST = ${jsonEncode(destination)}',
        )
        .replaceFirst(
          "STATE = '/var/lib/hermuse-provision'",
          'STATE = ${jsonEncode('${root.path}/state')}',
        )
        .replaceFirst("PROC = '/proc'", 'PROC = ${jsonEncode(proc)}')
        .replaceFirst('ROOT_UID = 0', 'ROOT_UID = os.geteuid()')
        .replaceFirst('pwd.getpwnam(ACCOUNT)', 'pwd.getpwuid(os.geteuid())');
    if (transform != null) script = transform(script);
    return Process.run('/bin/bash', ['-c', script]);
  }
}
