import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hermuse_host/src/installer.dart';
import 'package:hermuse_host/src/remote_scripts.dart';
import 'package:test/test.dart';

void main() {
  group('Read-only remote inventory recipes', () {
    late _Fixture fixture;
    setUp(() async => fixture = await _Fixture.create());
    tearDown(() async => fixture.root.delete(recursive: true));

    test('owned account repair restores directory ownership and private mode without replacing the user', () async {
      await Directory('${fixture.root.path}/provision').create();
      await fixture.file('provision/owns-hermes').writeAsString('owned');
      await fixture.file('home-owner').writeAsString('root');
      await fixture.executable(
        'bin/getent',
        'printf "%s\\n" "hermes:x:1001:1001::${fixture.root.path}/home/hermes:/bin/bash"',
      );
      await fixture.executable('bin/stat', '''
if [ "\$1:\$2" = '-c:%U' ]; then
  cat ${fixture.root.path}/home-owner
else
  exec /usr/bin/stat "\$@"
fi
''');
      await fixture.executable(
        'bin/chown',
        'printf hermes > ${fixture.root.path}/home-owner',
      );
      await fixture.executable(
        'bin/useradd',
        'touch ${fixture.root.path}/replacement-user; exit 1',
      );
      await fixture.executable('bin/install', r'''
args=()
while [ "$#" -gt 0 ]; do
  case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac
done
exec /usr/bin/install "${args[@]}"
''');
      expect(
        '${(await fixture.run(hermesUserHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      final repaired = await fixture.run(createHermesUserScript);
      expect(repaired.exitCode, 0, reason: '${repaired.stderr}');
      expect(
        '${(await fixture.run(hermesUserHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:ready',
      );
      expect(await fixture.file('replacement-user').exists(), isFalse);
      expect(
        await fixture.file('provision/owns-hermes').readAsString(),
        'owned',
      );
    });

    test('missing prerequisites are installed once; healthy packages cause no APT work', () async {
      final before = await fixture.run(prerequisitesHealthScript);
      expect('${before.stdout}'.trim(), 'HERMUSE_HEALTH_V1:repair');
      final repair = await fixture.run(installPrerequisitesScript);
      expect(repair.exitCode, 0, reason: '${repair.stderr}');
      final healthy = await fixture.run(prerequisitesHealthScript);
      expect('${healthy.stdout}'.trim(), 'HERMUSE_HEALTH_V1:ready');
      final first = await fixture.file('apt-calls').readAsString();
      await fixture.run(installPrerequisitesScript);
      expect(await fixture.file('apt-calls').readAsString(), first);
      await fixture.file('packages/libffi-dev').writeAsString('unpacked');
      expect(
        '${(await fixture.run(prerequisitesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
    });

    test('Hermes inspection proves pinned source, marker and launcher without starting mutable CLI paths', () async {
      await fixture.seedHermes();
      final snapshot = await fixture.snapshot();
      expect(
        '${(await fixture.run(hermesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:ready',
      );
      expect(await fixture.snapshot(), snapshot);
      await fixture.file('head').writeAsString('old-commit');
      expect(
        '${(await fixture.run(hermesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      await fixture.file('head').writeAsString(hermesReleaseCommit);
      await fixture
          .file('home/hermes/.hermes/hermes-agent/.hermes-bootstrap-complete')
          .writeAsString('{"schemaVersion":1,"pinnedCommit":"old"}');
      expect(
        '${(await fixture.run(hermesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      await fixture.seedHermes();
      await fixture.executable('home/hermes/.local/bin/hermes', 'exit 9');
      expect(
        '${(await fixture.run(hermesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      await fixture.seedHermes();
      await fixture
          .file('home/hermes/.hermes/hermes-agent/hermes_cli/__init__.py')
          .writeAsString(
            'from pathlib import Path\n'
            'Path("${fixture.file('unexpected-import').path}").touch()\n'
            '__version__ = "0.21.5"\n',
          );
      final drifted = await fixture.snapshot();
      expect(
        '${(await fixture.run(hermesHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      expect(await fixture.snapshot(), drifted);
    });

    test(
      'a plugin marker cannot hide a stale bundle or stale registered job',
      () async {
        await fixture.seedHermes();
        final hashes = await fixture.seedPlugin();
        final before = await fixture.snapshot();
        expect(
          '${(await fixture.run(pluginHealthScript(hashes))).stdout}'.trim(),
          'HERMUSE_HEALTH_V1:ready',
        );
        expect(await fixture.snapshot(), before);
        final source = fixture.file(
          'home/hermes/.hermes/plugins/hermuse/__init__.py',
        );
        await source.writeAsString('# stale app bundle');
        expect(
          '${(await fixture.run(pluginHealthScript(hashes))).stdout}'.trim(),
          'HERMUSE_HEALTH_V1:repair',
        );
        await fixture.seedPlugin();
        final jobsFile = fixture.file('home/hermes/.hermes/cron/jobs.json');
        final jobs =
            jsonDecode(await jobsFile.readAsString()) as Map<String, dynamic>;
        (jobs['jobs'] as List).first['prompt'] = 'stale prompt';
        await jobsFile.writeAsString(jsonEncode(jobs));
        expect(
          '${(await fixture.run(pluginHealthScript(hashes))).stdout}'.trim(),
          'HERMUSE_HEALTH_V1:repair',
        );
        await fixture.seedPlugin();
        final config = fixture.file('home/hermes/.hermes/config.yaml');
        await config.writeAsString(
          '{"plugins":{"enabled":["hermuse"],"disabled":["hermuse"]}}',
        );
        expect(
          '${(await fixture.run(pluginHealthScript(hashes))).stdout}'.trim(),
          'HERMUSE_HEALTH_V1:repair',
        );
      },
    );

    test('computer health checks current image, loopback ports, runtime token and real CDP without writes', () async {
      await fixture.seedHermes();
      await fixture.seedPlugin();
      final cdp = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = cdp.listen((request) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"webSocketDebuggerUrl":"ws://127.0.0.1/devtools/browser/test"}',
        );
        request.response.close();
      });
      addTearDown(() async {
        await cdp.close(force: true);
        await listener.cancel();
      });
      await fixture.seedComputer(cdp.port);
      final before = await fixture.snapshot();
      expect(
        '${(await fixture.run(computerHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:ready',
      );
      expect(await fixture.snapshot(), before);
      final containerFile = fixture.file('container.json');
      final container =
          (jsonDecode(await containerFile.readAsString()) as List).single
              as Map<String, dynamic>;
      container['Image'] = 'sha256:old-image';
      await containerFile.writeAsString(jsonEncode([container]));
      expect(
        '${(await fixture.run(computerHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
      await fixture.seedComputer(cdp.port);
      final runtime = fixture.file(
        'home/hermes/.hermes/hermuse/computer/runtime.json',
      );
      final state =
          jsonDecode(await runtime.readAsString()) as Map<String, dynamic>;
      state['token'] = 'stale-token';
      await runtime.writeAsString(jsonEncode(state));
      expect(
        '${(await fixture.run(computerHealthScript)).stdout}'.trim(),
        'HERMUSE_HEALTH_V1:repair',
      );
    });

    test('foreign plugin paths and computer containers are blocked before replacement', () async {
      await fixture.seedHermes();
      await fixture
          .file('home/hermes/.hermes/plugins/hermuse/plugin.yaml')
          .writeAsString('name: foreign');
      final before = await fixture.snapshot();
      expect(
        (await fixture.run(managedPathsPreflightScript)).exitCode,
        isNot(0),
      );
      expect(await fixture.snapshot(), before);
      await fixture
          .file('container.json')
          .writeAsString('[{"Config":{"Image":"unrelated-service:latest"}}]');
      expect((await fixture.run(computerOwnershipScript)).exitCode, isNot(0));
      expect(
        await fixture.file('container.json').readAsString(),
        '[{"Config":{"Image":"unrelated-service:latest"}}]',
      );
    });
    test('stale managed container repair preserves the named home and leaves a healthy stopped container intact', () async {
      await fixture.seedHermes();
      await fixture.seedPlugin();
      await fixture.seedComputer(12346);
      await fixture.file('volume-data').writeAsString('saved browser login');
      final containerFile = fixture.file('container.json');
      final container =
          (jsonDecode(await containerFile.readAsString()) as List).single
              as Map<String, dynamic>;
      container['State'] = {'Running': false};
      container['NetworkSettings'] = {'Ports': {}};
      await containerFile.writeAsString(jsonEncode([container]));
      final repair = asHermes(
        '$remotePython -B -c ${shellQuote(repairComputerContainerScript)}',
      );
      final unchanged = await fixture.run(repair);
      expect(unchanged.exitCode, 0, reason: '${unchanged.stderr}');
      expect(await containerFile.exists(), isTrue);
      expect(await fixture.file('docker-mutations').exists(), isFalse);
      container['Image'] = 'sha256:stale-image';
      await containerFile.writeAsString(jsonEncode([container]));
      final repaired = await fixture.run(repair);
      expect(repaired.exitCode, 0, reason: '${repaired.stderr}');
      expect(await containerFile.exists(), isFalse);
      expect(
        await fixture.file('docker-mutations').readAsString(),
        'rm -f hermuse-computer-hermes\n',
      );
      expect(
        await fixture.file('volume-data').readAsString(),
        'saved browser login',
      );
    });
  }, skip: Platform.isLinux ? false : 'Linux remote shell recipes');
}

final class _Fixture {
  _Fixture(this.root);
  final Directory root;
  File file(String path) => File('${root.path}/$path');

  static Future<_Fixture> create() async {
    final fixture = _Fixture(
      await Directory.systemTemp.createTemp('hermuse-inventory-'),
    );
    for (final path in [
      'bin',
      'packages',
      'python',
      'home/hermes/.hermes/plugins/hermuse',
      'home/hermes/.hermes/cron',
      'home/hermes/.hermes/hermes-agent/venv/bin',
      'home/hermes/.local/bin',
    ]) {
      await Directory('${fixture.root.path}/$path').create(recursive: true);
    }
    await fixture
        .file('python/yaml.py')
        .writeAsString(
          'import json\ndef safe_load(value): return json.loads(value)\n',
        );
    await fixture.executable('bin/runuser', 'shift 3\nexec "\$@"');
    await fixture.executable(
      'bin/python3',
      'PYTHONPATH=${fixture.root.path}/python exec /usr/bin/python3 "\$@"',
    );
    await fixture.executable(
      'home/hermes/.hermes/hermes-agent/venv/bin/python',
      'PYTHONPATH=${fixture.root.path}/python exec /usr/bin/python3 "\$@"',
    );
    await fixture.executable('bin/git', '''
if [ "\$3" = show ]; then
  cat ${shellQuote('${fixture.root.path}/pinned')}/"\${4#*:}"
else
  cat ${shellQuote(fixture.file('head').path)}
fi
''');
    await fixture.executable(
      'bin/id',
      'if [ "\$1" = -nG ]; then echo "hermes docker"; else echo 1001; fi',
    );
    await fixture.executable('bin/systemctl', 'exit 0');
    await fixture.executable(
      'bin/dpkg-query',
      'last=\${@: -1}\ncat ${fixture.root.path}/packages/"\$last" 2>/dev/null',
    );
    await fixture.executable('bin/apt-get', '''
printf '%s\\n' "\$*" >> ${fixture.root.path}/apt-calls
installing=no
for arg in "\$@"; do
  if [ "\$arg" = install ]; then installing=yes; continue; fi
  if [ "\$installing" = yes ] && [[ "\$arg" != -* ]]; then
    printf installed > ${fixture.root.path}/packages/"\$arg"
  fi
done
''');
    await fixture.executable('bin/docker', '''
if [ "\$1" = rm ]; then
  printf '%s\\n' "\$*" >> ${fixture.root.path}/docker-mutations
  rm -f ${fixture.root.path}/container.json
elif [ "\$1" = image ]; then cat ${fixture.root.path}/image.json
elif [ -f ${fixture.root.path}/container.json ]; then cat ${fixture.root.path}/container.json
else echo 'No such container' >&2; exit 1
fi
''');
    return fixture;
  }

  Future<void> executable(String path, String body) async {
    await file(path).parent.create(recursive: true);
    await file(path).writeAsString('#!/bin/bash\nset -euo pipefail\n$body\n');
    final chmod = await Process.run('chmod', ['0700', file(path).path]);
    if (chmod.exitCode != 0) throw StateError('${chmod.stderr}');
  }

  Future<void> seedHermes() async {
    await file('head').writeAsString(hermesReleaseCommit);
    await file('home/hermes/.hermes/hermes-agent/.hermes-bootstrap-complete')
        .writeAsString(
          jsonEncode({'schemaVersion': 1, 'pinnedCommit': hermesReleaseCommit}),
        );
    final sources = {
      'hermes':
          'from pathlib import Path\n'
          'Path("${file('cli-version-started').path}").touch()\n'
          'print("Hermes 0.21.5")\n',
      'hermes_cli/__init__.py': '__version__ = "0.21.5"\n',
    };
    for (final entry in sources.entries) {
      final source = file('home/hermes/.hermes/hermes-agent/${entry.key}');
      final pinned = file('pinned/${entry.key}');
      await source.parent.create(recursive: true);
      await pinned.parent.create(recursive: true);
      await source.writeAsString(entry.value);
      await pinned.writeAsString(entry.value);
    }
    final launcher = file('home/hermes/.local/bin/hermes');
    await launcher.writeAsString(
      '#!/usr/bin/env bash\nunset PYTHONPATH\nunset PYTHONHOME\n'
      'exec "${root.path}/home/hermes/.hermes/hermes-agent/venv/bin/python" '
      '"${root.path}/home/hermes/.hermes/hermes-agent/hermes" "\$@"\n',
    );
    final mode = await Process.run('chmod', ['0700', launcher.path]);
    if (mode.exitCode != 0) throw StateError('${mode.stderr}');
  }

  Future<Map<String, String>> seedPlugin() async {
    final bundle = {
      '__init__.py': '# fixture plugin\n',
      'plugin.yaml': 'name: hermuse\n',
      'cron_specs.py': '''
from types import SimpleNamespace
SPECS = tuple(SimpleNamespace(key=key, name="Hermuse " + key, prompt="Current " + key,
    schedule="0 8 * * *", skill_ref="hermuse:hermuse")
    for key in ("feed", "ideas", "goals", "reflection"))
''',
    };
    for (final entry in bundle.entries) {
      await file('home/hermes/.hermes/plugins/hermuse/${entry.key}')
          .writeAsString(entry.value);
    }
    await file('home/hermes/.hermes/plugins/hermuse/.hermuse-remote-managed')
        .writeAsString('');
    await file('home/hermes/.hermes/config.yaml')
        .writeAsString('{"plugins":{"enabled":["hermuse"],"disabled":[]}}');
    await file('home/hermes/.hermes/cron/jobs.json').writeAsString(
      jsonEncode({
        'jobs': [
          for (final key in ['feed', 'ideas', 'goals', 'reflection'])
            {
              'id': key,
              'name': 'Hermuse $key',
              'prompt': 'Current $key',
              'origin': {'source': 'hermuse', 'key': key},
              'schedule': {'kind': 'cron', 'expr': '0 8 * * *'},
              'skills': ['hermuse:hermuse'],
              'deliver': 'local',
              'enabled': false,
            },
        ],
      }),
    );
    return {
      for (final entry in bundle.entries)
        entry.key: sha256.convert(utf8.encode(entry.value)).toString(),
    };
  }

  Future<void> seedComputer(int cdpPort) async {
    final directory = Directory(
      '${root.path}/home/hermes/.hermes/plugins/hermuse/computer',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/__init__.py').writeAsString('');
    await File('${directory.path}/runtime.py').writeAsString('''
import urllib.request
IMAGE = "hermuse-computer:0.2.0"
CDP_PORT = 9223
SCREEN_PORT = 8765
def container_name(home): return "hermuse-computer-hermes"
def volume_name(home): return "hermuse-computer-hermes-home"
def loopback_request(url, timeout):
    return urllib.request.build_opener(urllib.request.ProxyHandler({})).open(url, timeout=timeout).read()
''');
    await File('${directory.path}/state.py').writeAsString('''
import json
def read_runtime(home): return json.loads((home / "hermuse/computer/runtime.json").read_text())
''');
    await file('image.json').writeAsString('[{"Id":"sha256:current-image"}]');
    await file('container.json').writeAsString(
      jsonEncode([
        {
          'State': {'Running': true},
          'Config': {
            'Image': 'hermuse-computer:0.2.0',
            'Env': ['SCREEND_TOKEN=current-token'],
          },
          'Image': 'sha256:current-image',
          'NetworkSettings': {
            'Ports': {
              '9223/tcp': [
                {'HostIp': '127.0.0.1', 'HostPort': '$cdpPort'},
              ],
              '8765/tcp': [
                {'HostIp': '127.0.0.1', 'HostPort': '12345'},
              ],
            },
          },
          'HostConfig': {
            'PortBindings': {
              '9223/tcp': [
                {'HostIp': '127.0.0.1', 'HostPort': '$cdpPort'},
              ],
              '8765/tcp': [
                {'HostIp': '127.0.0.1', 'HostPort': '12345'},
              ],
            },
          },
          'Mounts': [
            {
              'Name': 'hermuse-computer-hermes-home',
              'Destination': '/home/hermuse',
            },
          ],
        },
      ]),
    );
    await file('home/hermes/.hermes/hermuse/computer/runtime.json').parent
        .create(recursive: true);
    await file('home/hermes/.hermes/hermuse/computer/runtime.json')
        .writeAsString(
          jsonEncode({
            'backend': 'docker',
            'container': 'hermuse-computer-hermes',
            'image': 'hermuse-computer:0.2.0',
            'cdp_port': cdpPort,
            'screen_port': 12345,
            'token': 'current-token',
          }),
        );
  }

  Future<Map<String, String>> snapshot() async {
    final contents = <String, String>{};
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File) {
        contents[item.path] = sha256
            .convert(await item.readAsBytes())
            .toString();
      }
    }
    return contents;
  }

  Future<ProcessResult> run(String script) => Process.run(
    'bash',
    [
      '-euo',
      'pipefail',
      '-c',
      script
          .replaceAll('/home/hermes', '${root.path}/home/hermes')
          .replaceAll(provisionRoot, '${root.path}/provision')
          .replaceAll('/etc/caddy', '${root.path}/etc/caddy')
          .replaceAll('/etc/systemd/system', '${root.path}/etc/systemd/system')
          .replaceAll('PATH=', 'PATH=${root.path}/bin:'),
    ],
    environment: {'PATH': '${root.path}/bin:${Platform.environment['PATH']}'},
  );
}
