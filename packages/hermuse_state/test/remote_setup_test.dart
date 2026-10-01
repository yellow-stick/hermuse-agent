import 'dart:async';
import 'dart:convert';

import 'package:hermes_client/hermes_client.dart';
import 'package:hermes_client/testing.dart';
import 'package:hermuse_data/hermuse_data.dart';
import 'package:hermuse_data/native.dart';
import 'package:hermuse_state/hermuse_state.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:test/test.dart';

/// A Hermes dashboard with or without the Hermuse plugin, answering the way
/// Hermes 0.21.5 and the plugin do.
final class _Server {
  var version = '0.21.5';

  /// Nothing answers: the connection is refused.
  var down = false;

  /// Installed plugin version; null when Hermes does not know it.
  String? plugin;
  var enabled = true;

  /// The plugin routes answer.
  var mounted = false;

  /// Installs without `force` answer Hermes' "caution" scan verdict.
  var caution = true;

  /// The routes mount when the plugin is installed or turned on.
  var mountsLive = true;

  var registered = 0;
  var pointed = false;
  var failCron = false;

  /// `/computer/status` answers, the last one repeating.
  var computer = <Map<String, Object?>>[
    {'state': 'image_missing', 'detail': 'hermuse-computer:0.2.0 is not here'},
  ];

  /// What `POST /computer/setup` does to [computer].
  List<Map<String, Object?>>? afterSetup;

  final calls = <String>[];
  final bodies = <String, Object?>{};

  http.Response _json(Object? payload, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(payload)),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response _notFound() => _json({'detail': 'Not Found'}, 404);

  Map<String, Object?> _computerNow() =>
      computer.length > 1 ? computer.removeAt(0) : computer.first;

  Future<http.Response> handle(http.Request request) async {
    if (down) throw http.ClientException('Connection refused');
    // Relay-style base: every route keeps the `/hermes/<id>` prefix.
    final path = request.url.path.replaceFirst(RegExp('^/hermes/[^/]+'), '');
    final key = '${request.method} $path';
    calls.add(key);
    if (request.body.isNotEmpty) bodies[key] = jsonDecode(request.body);
    const plugins = '/api/dashboard/agent-plugins';
    const routes = '/api/plugins/hermuse';
    switch (key) {
      case 'GET /api/status':
        return _json({'version': version, 'auth_required': false});
      case 'GET /api/dashboard/plugins/hub':
        return _json({
          'plugins': [
            {'name': 'basic', 'version': '1.0.0', 'runtime_status': 'enabled'},
            if (plugin case final version?)
              {
                'name': 'hermuse',
                'version': version,
                'runtime_status': enabled ? 'enabled' : 'inactive',
              },
          ],
        });
      case 'GET /api/config':
        return _json({
          'browser': {if (pointed) 'cloud_provider': 'hermuse'},
        });
      case 'POST $plugins/hermuse/enable':
        if (plugin == null) {
          return _json({
            'detail': "Plugin 'hermuse' is not installed or bundled.",
          }, 400);
        }
        enabled = true;
        mounted = mountsLive;
        return _json({'ok': true});
      case 'POST $plugins/install':
        final force = (jsonDecode(request.body) as Map)['force'] == true;
        if (plugin != null && !force) {
          return _json({'detail': "Plugin 'hermuse' already exists."}, 400);
        }
        if (caution && !force) {
          return _json({
            'detail':
                'Security scan blocked plugin install: Requires '
                'confirmation (caution verdict, 45 findings)',
          }, 400);
        }
        plugin = hermusePluginVersion;
        enabled = true;
        mounted = mounted || mountsLive;
        return _json({'ok': true, 'restart_required': true});
    }
    if (!mounted) return _notFound();
    switch (key) {
      case 'GET $routes/files':
        return _json({'files': <String>[]});
      case 'GET $routes/cron':
        return _json({
          'jobs': [
            for (var i = 0; i < 4; i++)
              {'key': 'job$i', 'registered': i < registered, 'enabled': true},
          ],
        });
      case 'POST $routes/cron/enable':
        if (failCron) {
          return _json({'detail': 'cron backend unavailable: boom'}, 500);
        }
        registered = 4;
        return _json({'jobs': <Object>[]});
      case 'GET $routes/computer/status':
        return _json(_computerNow());
      case 'POST $routes/computer/setup':
        pointed = true;
        if (afterSetup case final next?) computer = [...next];
        return _json(_computerNow());
    }
    return _notFound();
  }
}

void main() {
  const id = 'vps';
  late HermuseDatabase db;
  late FakeHermesTransport fake;
  late ProviderContainer container;
  late _Server server;

  setUp(() async {
    db = openMemoryDatabase();
    fake = FakeHermesTransport();
    server = _Server();
    container = ProviderContainer(
      overrides: [
        hermuseDatabaseProvider.overrideWithValue(db),
        secretStoreProvider.overrideWithValue(MemorySecretStore()),
        transportFactoryProvider.overrideWithValue((_) async => fake),
        restClientProvider(id).overrideWith(
          (ref) => HermesRestClient(
            MockClient(server.handle),
            baseUrl: Uri.parse('https://relay.example/hermes/$id'),
          ),
        ),
        remoteSetupTimingProvider.overrideWithValue(
          const RemoteSetupTiming(
            poll: Duration(milliseconds: 5),
            mountTimeout: Duration(milliseconds: 40),
            mountPoll: Duration(milliseconds: 5),
          ),
        ),
      ],
    );
    final registry = await container.read(registryProvider.future);
    await registry.add(
      HermesInstance(
        id: id,
        label: 'VPS',
        kind: InstanceKind.remote,
        baseUrl: Uri.parse('https://relay.example/hermes/$id'),
        auth: AuthMethod.loopbackToken,
      ),
    );
    // No model provider yet.
    fake
      ..on(
        'setup.status',
        (_) => {
          'provider_configured': false,
          'ready': true,
          'free_tier': false,
          'other_providers': false,
          'inference_provider': '',
        },
      )
      ..on(
        'setup.runtime_check',
        (_) => {'ok': false, 'error': 'No Hermes provider is configured.'},
      )
      ..on('free_tier.status', (_) => throw const FakeRpcError(-32601, 'no'));
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  RemoteSetup notifier() => container.read(remoteSetupProvider(id).notifier);

  /// The checklist once [done] holds.
  Future<RemoteSetupState> until(bool Function(RemoteSetupState) done) async {
    final completer = Completer<RemoteSetupState>();
    final sub = container.listen(remoteSetupProvider(id), (_, next) {
      if (done(next) && !completer.isCompleted) completer.complete(next);
    }, fireImmediately: true);
    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      sub.close();
    }
  }

  /// The checklist once its first look is over. It stays alive for the
  /// rest of the test, as it does while its screen shows.
  Future<RemoteSetupState> looked() {
    container.listen(remoteSetupProvider(id), (_, _) {});
    return until((s) => s.phase != RemoteSetupPhase.checking);
  }

  RemotePartStatus status(RemoteSetupState s, RemotePart part) =>
      s[part].status;

  test('a Hermes without the plugin: only the plugin can be installed, the '
      'parts it serves wait for it', () async {
    final s = await looked();

    expect(status(s, RemotePart.hermes), RemotePartStatus.present);
    expect(
      s[RemotePart.hermes].summary,
      startsWith('Already installed · Version '),
    );
    expect(s[RemotePart.plugin].status, RemotePartStatus.missing);
    expect(s[RemotePart.plugin].action, RemoteAction.install);
    for (final part in [RemotePart.jobs, RemotePart.computer]) {
      expect(status(s, part), RemotePartStatus.blocked, reason: '$part');
      expect(s[part].enabled, isFalse, reason: '$part');
    }
    expect(status(s, RemotePart.docker), RemotePartStatus.blocked);
    expect(s[RemotePart.model].status, RemotePartStatus.needsUser);
    expect(s[RemotePart.model].action, RemoteAction.setUpModel);
    expect(s.phase, RemoteSetupPhase.needsInstall);
    expect(s.installable, [RemotePart.plugin]);
    // Nothing was installed by looking.
    expect(server.calls.where((c) => c.startsWith('POST')), isEmpty);
  });

  test('a Hermes older than the plugin supports blocks its install with the '
      'reason', () async {
    server.version = '0.21.4';

    final s = await looked();

    expect(status(s, RemotePart.hermes), RemotePartStatus.needsUser);
    expect(status(s, RemotePart.plugin), RemotePartStatus.blocked);
    expect(s[RemotePart.plugin].enabled, isFalse);
    expect(s.installable, isEmpty);
  });

  test('the plugin install asks for the consent Hermes wants, then unblocks '
      'the parts it serves', () async {
    await looked();

    await notifier().run(RemotePart.plugin);
    var s = container.read(remoteSetupProvider(id));
    expect(status(s, RemotePart.plugin), RemotePartStatus.needsUser);
    expect(s[RemotePart.plugin].action, RemoteAction.allowInstall);
    // Hermes' scan report comes apart from what the user reads first.
    expect(s[RemotePart.plugin].report, contains('caution verdict'));
    expect(
      s[RemotePart.plugin].notes,
      everyElement(isNot(contains('caution verdict'))),
    );
    expect(server.plugin, isNull);

    await notifier().run(RemotePart.plugin);
    s = container.read(remoteSetupProvider(id));
    expect(server.bodies['POST /api/dashboard/agent-plugins/install'], {
      'identifier': hermusePluginIdentifier,
      'enable': true,
      'force': true,
    });
    expect(status(s, RemotePart.plugin), RemotePartStatus.installed);
    expect(s[RemotePart.jobs].status, RemotePartStatus.missing);
    expect(s[RemotePart.jobs].enabled, isTrue);
    // The image is not there yet: Docker answers, the computer can go on.
    expect(status(s, RemotePart.docker), RemotePartStatus.present);
    expect(status(s, RemotePart.computer), RemotePartStatus.missing);
    expect(s.installable, [RemotePart.jobs, RemotePart.computer]);
  });

  test('an install that went through shows its part being looked at until '
      'Hermes answers again, never as it was before', () async {
    server.caution = false;
    await looked();
    final seen = <RemotePartStatus>[];
    container.listen(remoteSetupProvider(id), (_, next) {
      final now = next[RemotePart.plugin].status;
      if (seen.isEmpty || seen.last != now) seen.add(now);
    });

    await notifier().run(RemotePart.plugin);

    expect(seen, [
      RemotePartStatus.installing,
      RemotePartStatus.checking,
      RemotePartStatus.installed,
    ]);
  });

  test('routes that never mount ask for a dashboard restart', () async {
    server
      ..caution = false
      ..mountsLive = false;
    await looked();

    await notifier().run(RemotePart.plugin);

    final row = container.read(remoteSetupProvider(id))[RemotePart.plugin];
    expect(row.status, RemotePartStatus.needsUser);
    expect(row.command, isNotNull);
    expect(row.action, RemoteAction.checkAgain);

    // Restarted: the routes answer on the next look.
    server.mounted = true;
    await notifier().checkAgain();
    expect(
      status(container.read(remoteSetupProvider(id)), RemotePart.plugin),
      RemotePartStatus.installed,
    );
  });

  test('a plugin turned off is turned on, an older one is updated and asks '
      'for a dashboard restart', () async {
    server
      ..plugin = hermusePluginVersion
      ..enabled = false;
    var s = await looked();
    expect(s[RemotePart.plugin].action, RemoteAction.turnOn);

    await notifier().run(RemotePart.plugin);
    s = container.read(remoteSetupProvider(id));
    expect(
      server.calls,
      contains('POST /api/dashboard/agent-plugins/hermuse/enable'),
    );
    expect(status(s, RemotePart.plugin), RemotePartStatus.installed);

    server.plugin = '0.1.0';
    s = await notifier().checkAgain().then(
      (_) => container.read(remoteSetupProvider(id)),
    );
    expect(status(s, RemotePart.plugin), RemotePartStatus.missing);
    expect(s[RemotePart.plugin].action, RemoteAction.update);

    await notifier().run(RemotePart.plugin);
    s = container.read(remoteSetupProvider(id));
    expect(server.plugin, hermusePluginVersion);
    expect(
      server.bodies['POST /api/dashboard/agent-plugins/install'],
      containsPair('force', true),
    );
    // The dashboard still serves the version it loaded.
    expect(status(s, RemotePart.plugin), RemotePartStatus.needsUser);
    expect(s[RemotePart.plugin].command, isNotNull);
  });

  test('a failed install says why and its retry installs', () async {
    server
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..failCron = true;
    await looked();

    await notifier().run(RemotePart.jobs);
    var row = container.read(remoteSetupProvider(id))[RemotePart.jobs];
    expect(row.status, RemotePartStatus.failed);
    expect(row.notes.single, contains('cron backend unavailable'));
    expect(row.action, RemoteAction.retry);

    server.failCron = false;
    await notifier().run(RemotePart.jobs);
    row = container.read(remoteSetupProvider(id))[RemotePart.jobs];
    expect(row.status, RemotePartStatus.installed);
    expect(server.registered, 4);
  });

  test('Docker the server cannot install gives the command to run there, '
      'and the computer waits for it', () async {
    const command =
        'curl -fsSL https://get.docker.com | sudo sh && '
        'sudo usermod -aG docker hermes';
    server
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..computer = [
        {'state': 'docker_missing', 'detail': command},
      ];
    var s = await looked();
    expect(status(s, RemotePart.docker), RemotePartStatus.missing);
    expect(s[RemotePart.docker].command, isNull);
    expect(status(s, RemotePart.computer), RemotePartStatus.blocked);
    expect(s[RemotePart.computer].enabled, isFalse);

    // No passwordless sudo: the setup leaves Docker missing.
    await notifier().run(RemotePart.docker);
    s = container.read(remoteSetupProvider(id));
    expect(server.calls, contains('POST /api/plugins/hermuse/computer/setup'));
    expect(status(s, RemotePart.docker), RemotePartStatus.needsUser);
    expect(s[RemotePart.docker].command, command);
    expect(s[RemotePart.docker].action, RemoteAction.checkAgain);
  });

  test('Docker installed through the server bootstrap, then the image: '
      'each part follows its real state until ready', () async {
    server
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..computer = [
        {'state': 'docker_missing', 'detail': 'curl … | sudo sh'},
      ]
      ..afterSetup = [
        {'state': 'building', 'detail': 'Installing Docker…'},
        {'state': 'building', 'detail': 'Installing Docker…'},
        {'state': 'building', 'detail': 'Downloading the computer image…'},
        {'state': 'stopped', 'detail': 'hermuse-computer-vps'},
      ];
    await looked();

    final seen = <(RemotePartStatus, RemotePartStatus)>{};
    final sub = container.listen(remoteSetupProvider(id), (_, next) {
      seen.add((
        status(next, RemotePart.docker),
        status(next, RemotePart.computer),
      ));
    });
    await notifier().run(RemotePart.docker);
    final s = await until(
      (s) => status(s, RemotePart.computer) == RemotePartStatus.installed,
    );
    sub.close();

    expect(
      seen,
      containsAll([
        (RemotePartStatus.installing, RemotePartStatus.blocked),
        (RemotePartStatus.installed, RemotePartStatus.installing),
      ]),
    );
    expect(status(s, RemotePart.docker), RemotePartStatus.installed);
    expect(s[RemotePart.docker].summary, 'Installed now · Running');
    expect(s[RemotePart.computer].summary, 'Installed now · Ready');
  });

  test(
    'a Docker that does not answer names the command that fixes it',
    () async {
      server
        ..plugin = hermusePluginVersion
        ..mounted = true
        ..computer = [
          {
            'state': 'daemon_down',
            'detail':
                'permission denied while trying to connect to the Docker '
                'daemon socket at unix:///var/run/docker.sock',
          },
        ];
      var s = await looked();
      expect(status(s, RemotePart.docker), RemotePartStatus.needsUser);
      expect(s[RemotePart.docker].command, contains('usermod -aG docker'));

      server.computer = [
        {
          'state': 'daemon_down',
          'detail': 'Cannot connect to the Docker daemon',
        },
      ];
      s = await notifier().checkAgain().then(
        (_) => container.read(remoteSetupProvider(id)),
      );
      expect(s[RemotePart.docker].command, 'sudo systemctl start docker');
      expect(status(s, RemotePart.computer), RemotePartStatus.blocked);
    },
  );

  test(
    'a failed image build fails the computer; its retry sets it up again',
    () async {
      server
        ..plugin = hermusePluginVersion
        ..mounted = true
        ..pointed = true
        ..computer = [
          {'state': 'error', 'detail': 'Computer image build failed: no space'},
        ]
        ..afterSetup = [
          {'state': 'building', 'detail': 'Downloading the computer image…'},
          {'state': 'stopped', 'detail': 'hermuse-computer-vps'},
        ];
      var s = await looked();
      expect(status(s, RemotePart.computer), RemotePartStatus.failed);
      expect(s[RemotePart.computer].action, RemoteAction.retry);
      expect(status(s, RemotePart.docker), RemotePartStatus.present);

      await notifier().run(RemotePart.computer);
      s = await until(
        (s) => status(s, RemotePart.computer) == RemotePartStatus.installed,
      );
      expect(status(s, RemotePart.docker), RemotePartStatus.present);
    },
  );

  test('an image in place still needs Hermes pointed at it', () async {
    server
      ..plugin = hermusePluginVersion
      ..mounted = true
      ..registered = 4
      ..computer = [
        {'state': 'stopped', 'detail': 'hermuse-computer-vps'},
      ];
    var s = await looked();
    expect(status(s, RemotePart.computer), RemotePartStatus.missing);

    await notifier().run(RemotePart.computer);
    s = container.read(remoteSetupProvider(id));
    expect(server.pointed, isTrue);
    expect(status(s, RemotePart.computer), RemotePartStatus.installed);
    expect(status(s, RemotePart.jobs), RemotePartStatus.present);
  });

  test(
    'install everything goes in order and stops at what needs the user',
    () async {
      server.afterSetup = [
        {'state': 'stopped', 'detail': 'hermuse-computer-vps'},
      ];
      await looked();

      await notifier().installEverything();
      var s = container.read(remoteSetupProvider(id));
      // Hermes' consent comes first: nothing else ran.
      expect(status(s, RemotePart.plugin), RemotePartStatus.needsUser);
      expect(
        server.calls,
        isNot(contains('POST /api/plugins/hermuse/cron/enable')),
      );

      server.caution = false;
      await notifier().checkAgain();
      await notifier().installEverything();
      s = container.read(remoteSetupProvider(id));
      expect(server.calls.where((c) => c.startsWith('POST')), [
        'POST /api/dashboard/agent-plugins/hermuse/enable',
        'POST /api/dashboard/agent-plugins/install',
        'POST /api/dashboard/agent-plugins/hermuse/enable',
        'POST /api/dashboard/agent-plugins/install',
        'POST /api/plugins/hermuse/cron/enable',
        'POST /api/plugins/hermuse/computer/setup',
      ]);
      for (final part in [
        RemotePart.plugin,
        RemotePart.jobs,
        RemotePart.computer,
      ]) {
        expect(status(s, part), RemotePartStatus.installed, reason: '$part');
      }
      // The model is the user's to connect.
      expect(s.phase, RemoteSetupPhase.needsUser);
      expect(s.busy, isFalse);
    },
  );

  test('while one install runs the other actions wait', () async {
    server
      ..plugin = hermusePluginVersion
      ..mounted = true;
    await looked();
    final busy = Completer<void>();
    final states = <RemoteSetupState>[];
    final sub = container.listen(remoteSetupProvider(id), (_, next) {
      states.add(next);
      if (next.busy && !busy.isCompleted) busy.complete();
    });

    final jobs = notifier().run(RemotePart.jobs);
    await busy.future;
    final during = states.last;
    expect(status(during, RemotePart.jobs), RemotePartStatus.installing);
    expect(during[RemotePart.computer].enabled, isFalse);
    // Asked meanwhile, the computer setup does not run.
    await notifier().run(RemotePart.computer);
    await jobs;
    sub.close();
    expect(
      server.calls,
      isNot(contains('POST /api/plugins/hermuse/computer/setup')),
    );
    expect(
      container.read(remoteSetupProvider(id))[RemotePart.computer].enabled,
      isTrue,
    );
  });

  test(
    'an unreachable Hermes says so and shows its parts once it answers',
    () async {
      server.down = true;

      var s = await looked();
      expect(s.phase, RemoteSetupPhase.unreachable);
      expect(s.unreachable, contains('Connection refused'));

      server.down = false;
      await notifier().checkAgain();
      s = container.read(remoteSetupProvider(id));
      expect(s.unreachable, isNull);
      expect(status(s, RemotePart.plugin), RemotePartStatus.missing);
    },
  );

  test(
    'the model row follows the onboarding: connected now once it answers',
    () async {
      var s = await looked();
      expect(status(s, RemotePart.model), RemotePartStatus.needsUser);

      fake
        ..on(
          'setup.status',
          (_) => {
            'provider_configured': true,
            'ready': true,
            'free_tier': false,
            'other_providers': true,
            'inference_provider': 'anthropic',
          },
        )
        ..on(
          'setup.runtime_check',
          (_) => {'ok': true, 'provider': 'anthropic', 'model': 'claude'},
        );
      await notifier().checkAgain();
      s = await until(
        (s) => status(s, RemotePart.model) == RemotePartStatus.installed,
      );
      expect(s[RemotePart.model].summary, 'Connected now');
      expect(s[RemotePart.model].action, isNull);
    },
  );
}
