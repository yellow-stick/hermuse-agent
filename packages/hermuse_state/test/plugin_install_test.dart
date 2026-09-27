import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  // Relay-style base: every route keeps the `/hermes/<id>` prefix.
  const prefix = '/hermes/vps';
  const install = 'POST $prefix/api/dashboard/agent-plugins/install';
  const enable = 'POST $prefix/api/dashboard/agent-plugins/hermuse/enable';
  const files = 'GET $prefix/api/plugins/hermuse/files';
  const cron = 'POST $prefix/api/plugins/hermuse/cron/enable';
  const setup = 'POST $prefix/api/plugins/hermuse/computer/setup';

  late Map<String, http.Response Function(http.Request)> routes;
  late List<String> calls;
  late HermesRestClient rest;

  http.Response json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  Future<PluginInstallResult> run({bool force = false}) => installHermusePlugin(
    rest,
    force: force,
    mountTimeout: const Duration(milliseconds: 60),
    pollInterval: const Duration(milliseconds: 10),
  );

  setUp(() {
    calls = [];
    routes = {};
    rest = HermesRestClient(
      MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        calls.add(key);
        final handler = routes[key];
        return handler == null
            ? json({'detail': 'Not Found'}, 404)
            : handler(request);
      }),
      baseUrl: Uri.parse('https://relay.example$prefix'),
    );
    // By default Hermes does not know the plugin.
    routes[enable] = (_) =>
        json({'detail': "Plugin 'hermuse' is not installed or bundled."}, 400);
  });

  void mountAfter(int probes) {
    var n = 0;
    routes[files] = (_) => ++n <= probes
        ? json({'detail': 'Not Found'}, 404)
        : json({'files': []});
  }

  void finishOk() {
    routes[cron] = (_) => json({'ok': true});
    routes[setup] = (_) => json({'state': 'building', 'detail': ''});
  }

  test('routes already mounted: only the schedule and the computer', () async {
    mountAfter(0);
    routes[cron] = (_) => json({'ok': true});
    routes[setup] = (_) => json({
      'state': 'docker_missing',
      'detail':
          'curl -fsSL https://get.docker.com | sudo sh && '
          'sudo usermod -aG docker admin',
    });

    final result = await run();

    expect(calls, [files, cron, setup]);
    final computer = (result as PluginInstalled).computer;
    expect(computer.state, ComputerState.dockerMissing);
    expect(computer.detail, endsWith('usermod -aG docker admin'));
  });

  test('an installed but disabled plugin is enabled, then its routes '
      'awaited', () async {
    mountAfter(2);
    routes[enable] = (_) => json({'ok': true});
    finishOk();

    final result = await run();

    expect(calls, [files, enable, files, files, cron, setup]);
    expect((result as PluginInstalled).computer.state, ComputerState.building);
  });

  test('an unknown plugin is installed, then its routes awaited', () async {
    mountAfter(1);
    Map<String, Object?>? installBody;
    routes[install] = (request) {
      installBody = jsonDecode(request.body) as Map<String, Object?>;
      return json({'ok': true, 'plugin_name': 'hermuse', 'enabled': true});
    };
    finishOk();

    final result = await run();

    expect(installBody, {
      'identifier': 'yellow-stick/hermuse-agent/hermes-plugin/hermuse',
      'enable': true,
      'force': false,
    });
    expect(calls, [files, enable, install, files, cron, setup]);
    expect(result, isA<PluginInstalled>());
  });

  test('a caution verdict asks for consent; allowing installs with force '
      'directly', () async {
    mountAfter(1);
    const caution =
        'Security scan blocked plugin install: Requires confirmation '
        '(caution verdict, 2 findings)\n\nhermuse/computer/bootstrap.py: sudo';
    final forces = <Object?>[];
    routes[install] = (request) {
      final force = (jsonDecode(request.body) as Map)['force'];
      forces.add(force);
      return force == true
          ? json({'ok': true, 'plugin_name': 'hermuse'})
          : json({'detail': caution}, 400);
    };
    finishOk();

    final first = await run();
    expect(calls, [files, enable, install]);
    expect((first as PluginNeedsConsent).detail, caution);

    calls.clear();
    final second = await run(force: true);
    expect(forces, [false, true]);
    expect(calls, [install, files, cron, setup]);
    expect(second, isA<PluginInstalled>());
  });

  test('a dangerous verdict fails even when forced', () async {
    mountAfter(1 << 30);
    const dangerous =
        'Security scan blocked plugin install: Blocked (dangerous verdict, '
        'exec). --force does not override a dangerous verdict.';
    routes[install] = (_) => json({'detail': dangerous}, 400);

    expect(((await run()) as PluginInstallFailed).message, dangerous);
    expect(
      ((await run(force: true)) as PluginInstallFailed).message,
      dangerous,
    );
  });

  test('a scan answer with findings reports them', () async {
    mountAfter(1 << 30);
    routes[install] = (_) => json({
      'ok': false,
      'error': 'Security scan blocked hermuse',
      'scan_blocked': true,
      'scan_verdict': 'dangerous',
      'scan_findings': [
        {
          'pattern_id': 'exec',
          'severity': 'high',
          'category': 'execution',
          'file': 'hooks.py',
          'line': 12,
          'description': 'Runs a subprocess',
        },
      ],
    });

    final failed = (await run()) as PluginInstallFailed;

    expect(failed.message, 'Security scan blocked hermuse');
    expect(failed.findings.map((f) => '$f'), [
      'high: hooks.py:12 — Runs a subprocess',
    ]);
  });

  test('an install error stops the sequence with the server reason', () async {
    mountAfter(1 << 30);
    routes[install] = (_) =>
        json({'detail': 'git clone failed: repository not found'}, 400);

    final result = await run();

    expect(calls, [files, enable, install]);
    expect(
      (result as PluginInstallFailed).message,
      'git clone failed: repository not found',
    );
  });

  test('any other enable error is reported', () async {
    mountAfter(1 << 30);
    routes[enable] = (_) => json({'detail': 'Enable failed.'}, 400);

    final result = await run();

    expect(calls, [files, enable]);
    expect((result as PluginInstallFailed).message, 'Enable failed.');
  });

  test('routes that never mount ask for a dashboard restart', () async {
    mountAfter(1 << 30);
    routes[install] = (_) => json({'ok': true});

    final result = await run();

    expect(result, isA<PluginNeedsDashboardRestart>());
    expect(calls.take(3), [files, enable, install]);
    expect(calls.skip(3), everyElement(files));
    expect(calls.length, greaterThan(4));
  });

  test('a failing schedule step fails the install', () async {
    mountAfter(0);
    routes[cron] = (_) => json({'detail': 'hermes cron is unavailable'}, 500);

    final result = await run();

    expect(calls, [files, cron]);
    expect(
      (result as PluginInstallFailed).message,
      'Hermuse is installed but its schedule could not be enabled: '
      'hermes cron is unavailable',
    );
  });

  test('a failing computer setup still reports the plugin installed', () async {
    mountAfter(0);
    routes[cron] = (_) => json({'ok': true});
    routes[setup] = (_) => json({'detail': 'config: 1'}, 500);

    final computer = ((await run()) as PluginInstalled).computer;

    expect(
      (computer.state, computer.detail),
      (ComputerState.error, 'config: 1'),
    );
  });
}
