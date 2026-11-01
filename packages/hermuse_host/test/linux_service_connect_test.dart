@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:hermuse_host/src/remote_scripts.dart';
import 'package:test/test.dart';

void main() {
  late _ConnectionMachine machine;
  setUp(() async => machine = await _ConnectionMachine.create());
  tearDown(() => machine.dispose());

  test(
    'authorizes legacy unmanaged plugin without adopting or changing data',
    () async {
      final before = await machine.preserved();
      final result = await machine.connect();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final token = '${result.stdout}'.trim();
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{64}$')));
      expect(await machine.preserved(), before);
      expect(await machine.file('unit').readAsString(), machine.currentUnit);
      expect(await machine.file('restarts').readAsString(), '1');
      expect(
        (await machine.file('provision/dashboard.env').stat()).mode & 0x1ff,
        0x180,
      );
      final journal = jsonDecode(
        await machine.file('provision/ownership.json').readAsString(),
      ) as Map;
      final change = journal['desktopConnection'] as Map;
      expect(change['credentialCreated'], isTrue);
      expect(change['unitUpdated'], isTrue);
      expect(change['state'], 'complete');
      expect(jsonEncode(journal), isNot(contains(token)));
      expect((journal['paths'] as Map).keys, [
        '${machine.root.path}/provision/dashboard.env',
      ]);
      expect((journal['user'] as Map)['created'], isFalse);
      expect(
        await machine
            .file('home/.hermes/plugins/hermuse/.hermuse-remote-managed')
            .exists(),
        isFalse,
      );
      final verified = await machine.verify(token);
      expect(verified.exitCode, 0, reason: '${verified.stderr}');
      expect(verified.stdout, isEmpty);
    },
  );

  test(
    'recognizes only trailing blank-line differences in a legacy unit',
    () async {
      final unit = machine.file('unit');
      await unit.writeAsString('${await unit.readAsString()}\n\n');
      final result = await machine.connect();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(await unit.readAsString(), machine.currentUnit);
    },
  );

  test(
    'adds only token provenance while preserving an existing ownership journal',
    () async {
      final existing = {
        'schemaVersion': 1,
        'user': {
          'created': false,
          'identity': null,
          'defaults': <String, Object?>{},
        },
        'paths': {
          'unrelated': {'created': false, 'identity': null},
        },
        'audit': 'retain existing metadata',
      };
      final journalFile = machine.file('provision/ownership.json');
      await journalFile.writeAsString(jsonEncode(existing));
      await Process.run('chmod', ['0600', journalFile.path]);
      final result = await machine.connect();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final journal = jsonDecode(await journalFile.readAsString()) as Map;
      expect(journal['user'], existing['user']);
      expect(journal['audit'], existing['audit']);
      expect(
        (journal['paths'] as Map)['unrelated'],
        (existing['paths'] as Map)['unrelated'],
      );
      expect((journal['paths'] as Map).length, 2);
    },
  );

  test(
    'reuses authenticated credential without restart or journal rewrite',
    () async {
      final first = await machine.connect();
      expect(first.exitCode, 0, reason: '${first.stderr}');
      final journal = await machine
          .file('provision/ownership.json')
          .readAsString();
      final unit = await machine.file('unit').readAsString();
      final credential = await machine
          .file('provision/dashboard.env')
          .readAsString();
      final second = await machine.connect();
      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(second.stdout, first.stdout);
      expect(await machine.file('restarts').readAsString(), '1');
      expect(await machine.file('unit').readAsString(), unit);
      expect(
        await machine.file('provision/dashboard.env').readAsString(),
        credential,
      );
      expect(
        await machine.file('provision/ownership.json').readAsString(),
        journal,
      );
    },
  );

  for (final refusal in [
    'unknown unit',
    'drop-in',
    'stale loaded unit',
    'inactive',
    'wrong account',
  ]) {
    test('refuses $refusal before any credential or unit mutation', () async {
      switch (refusal) {
        case 'unknown unit':
          await machine.file('unit').writeAsString('# unrelated service\n');
        case 'drop-in':
          machine.properties['DropInPaths'] =
              '/etc/systemd/system/hermuse-dashboard.service.d/custom.conf';
        case 'stale loaded unit':
          machine.properties['NeedDaemonReload'] = 'yes';
        case 'inactive':
          machine.properties['ActiveState'] = 'inactive';
        case 'wrong account':
          machine.properties['User'] = 'root';
      }
      final before = await machine.file('unit').readAsString();
      final preserved = await machine.preserved();
      final result = await machine.connect();
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
      expect('${result.stderr}'.trim(), 'HERMUSE_CONNECT_REFUSED_V1');
      expect(await machine.file('unit').readAsString(), before);
      expect(await machine.preserved(), preserved);
      expect(await machine.file('provision/dashboard.env').exists(), isFalse);
      expect(await machine.file('provision/ownership.json').exists(), isFalse);
      expect(await machine.file('restarts').exists(), isFalse);
    });
  }

  test('does not restart or provision when an existing credential fails authentication', () async {
    await machine.seedCurrent();
    await machine.file('loaded-token').writeAsString('different credential');
    final result = await machine.connect();
    expect(result.exitCode, isNot(0));
    expect(result.stdout, isEmpty);
    expect(await machine.file('restarts').exists(), isFalse);
    expect(await machine.file('provision/ownership.json').exists(), isFalse);
    expect(await machine.file('unit').readAsString(), machine.currentUnit);
  });

  test(
    'gated dashboards use normal login without credential or service mutation',
    () async {
      machine.authRequired = true;
      final unit = await machine.file('unit').readAsString();
      final preserved = await machine.preserved();
      final status = await machine.connect(
        script: inspectDashboardAuthenticationScript,
      );
      expect('${status.stdout}'.trim(), 'HERMUSE_DASHBOARD_LOGIN_V1');
      final result = await machine.connect();
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
      expect(await machine.file('unit').readAsString(), unit);
      expect(await machine.preserved(), preserved);
      expect(await machine.file('provision/dashboard.env').exists(), isFalse);
      expect(await machine.file('provision/ownership.json').exists(), isFalse);
      expect(await machine.file('restarts').exists(), isFalse);
    },
  );

  test('does not forward credentials to redirects or proxy servers', () async {
    await machine.seedCurrent();
    machine.redirect = true;
    final result = await machine.connect();
    expect(result.exitCode, isNot(0));
    expect(result.stdout, isEmpty);
    expect(machine.redirectRequests, 0);
    expect(await machine.file('restarts').exists(), isFalse);
  });

  test('refuses an unsafe credential without overwriting it', () async {
    await machine.seedCurrent();
    final credential = machine.file('provision/dashboard.env');
    final before = await credential.readAsString();
    await Process.run('chmod', ['0644', credential.path]);
    final result = await machine.connect();
    expect(result.exitCode, isNot(0));
    expect(await credential.readAsString(), before);
    expect(await machine.file('restarts').exists(), isFalse);
  });
}

final class _ConnectionMachine {
  _ConnectionMachine(this.root, this.server, this.uid);
  final Directory root;
  final HttpServer server;
  final int uid;
  final properties = <String, String>{};
  bool redirect = false;
  bool authRequired = false;
  int redirectRequests = 0;

  File file(String name) => File('${root.path}/$name');

  String rewrite(String script) => script
      .replaceAll('/var/lib/hermuse-provision', '${root.path}/provision')
      .replaceAll(
        '/etc/systemd/system/hermuse-dashboard.service',
        '${root.path}/unit',
      )
      .replaceAll('/home/hermes', '${root.path}/home')
      .replaceAll(
        'trusted_directory("/home")',
        'trusted_directory(${jsonEncode(root.path)})',
      )
      // Keep real descriptor/type/mode checks inside the isolated fixture tree.
      .replaceAll('current = "/"', 'current = ${jsonEncode(root.path)}')
      .replaceAll(
        'path.strip("/").split("/")',
        'os.path.relpath(path, ${jsonEncode(root.path)}).split("/")',
      )
      .replaceAll('info.st_uid != 0', 'info.st_uid != $uid')
      .replaceAll(
        'user = pwd.getpwnam("hermes")',
        'user = pwd.struct_passwd(("hermes", "x", $uid, $uid, "", ${jsonEncode('${root.path}/home')}, "/bin/bash"))',
      )
      .replaceAll('user.pw_uid <= 0', 'user.pw_uid < 0')
      .replaceAll('http://127.0.0.1:9119', 'http://127.0.0.1:${server.port}');

  String get currentUnit => rewrite('$dashboardService\n');

  static Future<_ConnectionMachine> create() async {
    final root = await Directory.systemTemp.createTemp('hermuse-connect-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final identity = await Process.run('id', ['-u']);
    final machine = _ConnectionMachine(
      root,
      server,
      int.parse('${identity.stdout}'.trim()),
    );
    await Directory('${root.path}/provision').create();
    await Directory('${root.path}/bin').create();
    await Directory('${root.path}/home/.hermes/plugins/hermuse')
        .create(recursive: true);
    await machine
        .file('home/.hermes/plugins/hermuse/__init__.py')
        .writeAsString('unmanaged existing plugin bytes');
    await machine
        .file('home/.hermes/config.yaml')
        .writeAsString(
          'dashboard:\n  public_url: https://existing.example\n  password_hash: existing-hash\n',
        );
    await machine
        .file('home/.hermes/conversations.db')
        .writeAsString('existing user data');
    await machine
        .file('unit')
        .writeAsString(
          machine.currentUnit.replaceAll(
            'EnvironmentFile=-${root.path}/provision/dashboard.env\n',
            '',
          ),
        );
    machine.properties.addAll({
      'FragmentPath': '${root.path}/unit',
      'DropInPaths': '',
      'LoadState': 'loaded',
      'ActiveState': 'active',
      'SubState': 'running',
      'NeedDaemonReload': 'no',
      'Transient': 'no',
      'User': 'hermes',
      'Group': 'hermes',
      'WorkingDirectory': '${root.path}/home/.hermes',
      'MainPID': '$pid',
    });
    await machine.file('bin/systemctl').writeAsString('''#!/usr/bin/python3
import json, pathlib, sys
root = pathlib.Path(${jsonEncode(root.path)})
if sys.argv[1] == 'show':
    for key, value in json.loads((root / 'properties').read_text()).items():
        print(key + '=' + value)
elif sys.argv[1] == 'restart':
    count = root / 'restarts'
    count.write_text(str(int(count.read_text()) + 1) if count.exists() else '1')
    (root / 'loaded-token').write_text((root / 'provision/dashboard.env').read_text().split('=', 1)[1].strip())
elif sys.argv[1] != 'daemon-reload':
    sys.exit(99)
''');
    await Process.run('chmod', ['0755', '${root.path}/bin/systemctl']);
    server.listen((request) async {
      if (request.uri.path == '/steal') {
        machine.redirectRequests++;
        request.response.statusCode = 200;
      } else if (request.uri.path == '/api/status') {
        request.response.write(
          jsonEncode({
            'version': '0.13.0',
            'auth_required': machine.authRequired,
          }),
        );
      } else if (request.uri.path == '/api/plugins/hermuse/files') {
        final header = request.headers.value('x-hermes-session-token');
        final loaded = await machine.file('loaded-token').exists()
            ? await machine.file('loaded-token').readAsString()
            : null;
        if (header == null || header != loaded) {
          request.response.statusCode = 401;
        } else if (machine.redirect) {
          request.response.statusCode = 302;
          request.response.headers.set('location', '/steal');
        } else {
          request.response.write('{"files":[]}');
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    return machine;
  }

  Future<void> seedCurrent() async {
    await file('unit').writeAsString(currentUnit);
    await file('provision/dashboard.env')
        .writeAsString('HERMES_DASHBOARD_SESSION_TOKEN=${'t' * 64}\n');
    await Process.run('chmod', ['0600', file('provision/dashboard.env').path]);
    await file('loaded-token').writeAsString('t' * 64);
  }

  Future<Map<String, String>> preserved() async => {
    for (final path in [
      'home/.hermes/plugins/hermuse/__init__.py',
      'home/.hermes/config.yaml',
      'home/.hermes/conversations.db',
    ])
      path: await file(path).readAsString(),
  };

  Future<ProcessResult> connect({String? script}) async {
    await file('properties').writeAsString(jsonEncode(properties));
    return Process.run(
      '/bin/bash',
      ['-euo', 'pipefail', '-c', rewrite(script ?? connectDashboardScript)],
      environment: {
        'PATH': '${root.path}/bin:/usr/bin:/bin',
        'HTTP_PROXY': 'http://127.0.0.1:1',
        'http_proxy': 'http://127.0.0.1:1',
        'NO_PROXY': '',
        'no_proxy': '',
      },
    );
  }

  Future<ProcessResult> verify(String token) async {
    final process = await Process.start(
      '/bin/bash',
      ['-euo', 'pipefail', '-c', rewrite(verifyConnectedDashboardScript)],
      environment: {'PATH': '${root.path}/bin:/usr/bin:/bin'},
    );
    process.stdin.write(token);
    await process.stdin.close();
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    return ProcessResult(
      process.pid,
      await process.exitCode,
      await stdout,
      await stderr,
    );
  }

  Future<void> dispose() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  }
}
