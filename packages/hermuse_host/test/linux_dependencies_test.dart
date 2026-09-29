@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

const _rootful = 'unix:///var/run/docker.sock';
const _rootless = 'unix:///run/user/1000/docker.sock';

const _desktop = LinuxSession(
  sessionBus: true,
  graphical: true,
  pkexec: true,
  systemd: true,
  userManager: true,
);

const _noble = LinuxSystemProbe(
  os: LinuxOsSupport.supported,
  base: 'noble',
  secretProviderInstalled: true,
);

const _keyringUnlocked = SecretServiceStatus(
  SecretServiceState.running,
  locked: false,
);

const _defaultContext = DockerContext(name: 'default', host: _rootful);

DockerEngineStatus _engine(
  String host, {
  DockerAccess access = DockerAccess.notProbed,
  bool loaded = false,
  bool active = false,
  String detail = '',
}) => DockerEngineStatus(
  host: host,
  access: access,
  serviceLoaded: loaded,
  serviceActive: active,
  detail: detail,
);

DockerStatus _docker({
  String? cli = '/usr/bin/docker',
  DockerContext? context = _defaultContext,
  String contextError = '',
  DockerEngineStatus? rootful,
  DockerEngineStatus? rootless,
  bool groupExists = true,
  bool userInGroup = true,
  bool sessionInGroup = true,
}) => DockerStatus(
  cli: cli,
  context: context,
  contextError: contextError,
  rootful: rootful ?? _engine(_rootful),
  rootless: rootless ?? _engine(_rootless),
  userName: 'ada',
  groupExists: groupExists,
  userInGroup: userInGroup,
  sessionInGroup: sessionInGroup,
);

final _dockerRunning = _docker(
  rootful: _engine(
    _rootful,
    access: DockerAccess.answers,
    loaded: true,
    active: true,
  ),
);

/// A fresh desktop: no keyring provider, build tools and Docker missing.
final _fresh = LinuxDependencyInspection(
  system: const LinuxSystemProbe(
    os: LinuxOsSupport.supported,
    base: 'noble',
    missingPackages: {
      LinuxHelperCategory.hermesTools: ['build-essential', 'ripgrep'],
      LinuxHelperCategory.secretService: ['gnome-keyring', 'libsecret-1-0'],
      LinuxHelperCategory.dockerInstall: ['docker.io'],
    },
  ),
  session: _desktop,
  secretService: const SecretServiceStatus(SecretServiceState.absent),
  docker: _docker(
    cli: null,
    context: null,
    groupExists: false,
    userInGroup: false,
    sessionInGroup: false,
  ),
);

LinuxDependencyInspection _inspection({
  LinuxSystemProbe? system = _noble,
  String systemError = '',
  LinuxSession session = _desktop,
  SecretServiceStatus secretService = _keyringUnlocked,
  DockerStatus? docker,
}) => LinuxDependencyInspection(
  system: system,
  systemError: systemError,
  session: session,
  secretService: secretService,
  docker: docker ?? _dockerRunning,
);

LinuxDependencyPlan _plan(
  LinuxDependencyInspection inspection, [
  Set<LinuxTarget> targets = const {LinuxTarget.core, LinuxTarget.local},
  bool useLocalDockerEngine = false,
]) => LinuxDependencyPlan.compute(
  inspection,
  targets,
  useLocalDockerEngine: useLocalDockerEngine,
);

List<LinuxDependencyStep> _steps(LinuxDependencyPlan plan) => [
  for (final s in plan.steps) s.step,
];

List<LinuxBlockerKind> _blockers(LinuxDependencyPlan plan) => [
  for (final b in plan.blockers) b.kind,
];

void main() {
  group('plan', () {
    test('a fresh desktop gets everything under one authorization', () {
      final plan = _plan(_fresh);
      expect(_steps(plan), [
        LinuxDependencyStep.hermesTools,
        LinuxDependencyStep.secretService,
        LinuxDependencyStep.dockerInstall,
        LinuxDependencyStep.dockerStart,
        LinuxDependencyStep.dockerGroup,
        LinuxDependencyStep.activateSecretService,
      ]);
      expect(plan.blockers, isEmpty);
      expect(plan.needsAuthorization, isTrue);
      expect(plan.steps.first.packages, ['build-essential', 'ripgrep']);
      final group = plan.steps.firstWhere(
        (s) => s.step == LinuxDependencyStep.dockerGroup,
      );
      expect(group.warning, contains('root-equivalent'));
      expect(plan.dockerState, LinuxDockerState.absent);
      expect(plan.dockerEndpoint?.host, _rootful);
      expect(plan.dockerEndpoint?.explicit, isFalse);
    });

    test('a remote connection only prepares the keyring', () {
      final plan = _plan(_fresh, {LinuxTarget.core});
      expect(_steps(plan), [
        LinuxDependencyStep.secretService,
        LinuxDependencyStep.activateSecretService,
      ]);
      expect(plan.dockerEndpoint, isNull);
    });

    test('a working system needs nothing', () {
      final plan = _plan(_inspection());
      expect(plan.isSatisfied, isTrue);
      expect(plan.needsAuthorization, isFalse);
    });

    test('a locked keyring is kept: no second provider is planned', () {
      final plan = _plan(
        _inspection(
          secretService: const SecretServiceStatus(
            SecretServiceState.running,
            locked: true,
          ),
        ),
        {LinuxTarget.core},
      );
      expect(plan.isSatisfied, isTrue);
    });

    test('an activatable or installed provider is only started', () {
      for (final inspection in [
        _inspection(
          secretService: const SecretServiceStatus(
            SecretServiceState.activatable,
          ),
        ),
        // KWallet (or a just-installed keyring) the bus does not list yet.
        _inspection(
          secretService: const SecretServiceStatus(SecretServiceState.absent),
        ),
      ]) {
        final plan = _plan(inspection, {LinuxTarget.core});
        expect(_steps(plan), [LinuxDependencyStep.activateSecretService]);
        expect(plan.needsAuthorization, isFalse);
      }
    });

    test('without a session bus no keyring can work', () {
      final plan = _plan(
        _inspection(
          secretService: const SecretServiceStatus(
            SecretServiceState.unavailable,
          ),
        ),
        {LinuxTarget.core},
      );
      expect(plan.steps, isEmpty);
      expect(_blockers(plan), [LinuxBlockerKind.sessionBusMissing]);
    });

    test('an unsupported system is reported, never repaired', () {
      final plan = _plan(
        LinuxDependencyInspection(
          system: const LinuxSystemProbe(
            os: LinuxOsSupport.unsupportedDistribution,
          ),
          session: _desktop,
          secretService: const SecretServiceStatus(SecretServiceState.absent),
          docker: _fresh.docker,
        ),
      );
      expect(plan.steps, isEmpty);
      expect(_blockers(plan), [LinuxBlockerKind.unsupportedOs]);
    });

    test('without pkexec or a graphical session nothing is elevated', () {
      for (final session in [
        const LinuxSession(
          sessionBus: true,
          graphical: true,
          pkexec: false,
          systemd: true,
          userManager: true,
        ),
        const LinuxSession(
          sessionBus: true,
          graphical: false,
          pkexec: true,
          systemd: true,
          userManager: true,
        ),
      ]) {
        final plan = _plan(
          LinuxDependencyInspection(
            system: _fresh.system,
            session: session,
            secretService: _fresh.secretService,
            docker: _fresh.docker,
          ),
        );
        expect(plan.needsAuthorization, isFalse);
        expect(plan.steps, isEmpty);
        expect(_blockers(plan), [LinuxBlockerKind.authorizationUnavailable]);
        expect(
          plan.blockers.single.details.join(' '),
          allOf(contains('ripgrep'), contains('gnome-keyring')),
        );
      }
    });

    test('a missing helper blocks the local preparation', () {
      final plan = _plan(
        _inspection(system: null, systemError: 'the setup helper is missing'),
        {LinuxTarget.local},
      );
      expect(plan.steps, isEmpty);
      expect(_blockers(plan), [LinuxBlockerKind.helperUnavailable]);
    });
  });

  group('plan Docker', () {
    LinuxDependencyPlan local(DockerStatus docker, {bool choice = false}) =>
        _plan(_inspection(docker: docker), {LinuxTarget.local}, choice);

    test('a stopped system engine is started, never reinstalled', () {
      final plan = local(_docker(rootful: _engine(_rootful, loaded: true)));
      expect(_steps(plan), [LinuxDependencyStep.dockerStart]);
      expect(plan.dockerState, LinuxDockerState.stopped);
      expect(plan.dockerEndpoint?.host, _rootful);
    });

    test('a running engine the user cannot reach needs the docker group', () {
      final plan = local(
        _docker(
          rootful: _engine(
            _rootful,
            access: DockerAccess.permissionDenied,
            loaded: true,
            active: true,
          ),
          userInGroup: false,
          sessionInGroup: false,
        ),
      );
      expect(_steps(plan), [LinuxDependencyStep.dockerGroup]);
      expect(plan.dockerState, LinuxDockerState.noAccess);
      expect(plan.steps.single.warning, contains('root-equivalent'));
    });

    test('a group granted after login is used through the plugin', () {
      final plan = local(
        _docker(
          rootful: _engine(
            _rootful,
            access: DockerAccess.permissionDenied,
            loaded: true,
            active: true,
          ),
          sessionInGroup: false,
        ),
      );
      expect(plan.isSatisfied, isTrue);
      expect(plan.dockerEndpoint?.host, _rootful);
      expect(plan.dockerState, LinuxDockerState.usable);
    });

    test('a usable rootless engine needs no privilege at all', () {
      final plan = local(
        _docker(
          context: const DockerContext(name: 'rootless', host: _rootless),
          rootless: _engine(
            _rootless,
            access: DockerAccess.answers,
            loaded: true,
            active: true,
          ),
          userInGroup: false,
          sessionInGroup: false,
        ),
      );
      expect(plan.isSatisfied, isTrue);
      expect(plan.dockerEndpoint?.host, _rootless);
      expect(plan.dockerEndpoint?.explicit, isFalse);
    });

    test('a stopped rootless engine is started as the user', () {
      final plan = local(
        _docker(
          context: const DockerContext(name: 'rootless', host: _rootless),
          rootful: _engine(_rootful, loaded: true),
          rootless: _engine(_rootless, loaded: true),
          userInGroup: false,
        ),
      );
      expect(_steps(plan), [LinuxDependencyStep.startRootlessDocker]);
      expect(plan.dockerState, LinuxDockerState.rootlessStopped);
      expect(plan.needsAuthorization, isFalse);
      expect(plan.dockerEndpoint?.host, _rootless);
    });

    test('an engine other than the context gets an explicit DOCKER_HOST', () {
      final plan = local(
        _docker(
          rootful: _engine(_rootful, loaded: true),
          rootless: _engine(
            _rootless,
            access: DockerAccess.answers,
            loaded: true,
            active: true,
          ),
        ),
      );
      expect(plan.isSatisfied, isTrue);
      expect(plan.dockerEndpoint?.host, _rootless);
      expect(plan.dockerEndpoint?.explicit, isTrue);
    });

    test('an existing but broken Docker is left alone', () {
      for (final docker in [
        // CLI without a service (a stopped snap, a manual install…).
        _docker(
          rootful: _engine(
            _rootful,
            access: DockerAccess.noAnswer,
            detail: 'Cannot connect to the Docker daemon',
          ),
        ),
        // A service that runs but does not answer.
        _docker(
          rootful: _engine(
            _rootful,
            access: DockerAccess.noAnswer,
            loaded: true,
            active: true,
          ),
        ),
      ]) {
        final plan = local(docker);
        expect(plan.steps, isEmpty);
        expect(_blockers(plan), [LinuxBlockerKind.dockerUnusable]);
        expect(plan.dockerState, LinuxDockerState.unusable);
      }
    });

    test('leftover Docker data blocks a fresh docker.io install', () {
      final plan = _plan(
        LinuxDependencyInspection(
          system: const LinuxSystemProbe(
            os: LinuxOsSupport.supported,
            base: 'bookworm',
            dockerFootprint: {DockerFootprint.data, DockerFootprint.config},
          ),
          session: _desktop,
          secretService: _keyringUnlocked,
          docker: _fresh.docker,
        ),
        {LinuxTarget.local},
      );
      expect(_steps(plan), isNot(contains(LinuxDependencyStep.dockerInstall)));
      expect(_blockers(plan), [LinuxBlockerKind.dockerUnusable]);
    });

    test('a remote context needs the explicit local choice', () {
      final remote = _docker(
        context: const DockerContext(
          name: 'build-farm',
          host: 'ssh://ada@farm.example',
        ),
        rootful: _engine(
          _rootful,
          access: DockerAccess.answers,
          loaded: true,
          active: true,
        ),
      );
      final blocked = local(remote);
      expect(blocked.steps, isEmpty);
      expect(blocked.dockerEndpoint, isNull);
      expect(_blockers(blocked), [LinuxBlockerKind.dockerRemoteContext]);
      expect(blocked.dockerState, LinuxDockerState.remoteContext);
      expect(blocked.blockers.single.offersLocalDockerEngine, isTrue);

      final chosen = local(remote, choice: true);
      expect(chosen.isSatisfied, isTrue);
      expect(chosen.dockerEndpoint?.host, _rootful);
      expect(chosen.dockerEndpoint?.explicit, isTrue);
    });

    test('a local custom context that answers is used as is', () {
      final plan = local(
        _docker(
          context: const DockerContext(
            name: 'desktop-linux',
            host: 'unix:///home/ada/.docker/desktop/docker.sock',
            access: DockerAccess.answers,
          ),
        ),
      );
      expect(plan.isSatisfied, isTrue);
      expect(plan.dockerEndpoint?.explicit, isFalse);
    });

    test('a context Docker cannot resolve needs the explicit choice', () {
      final broken = _docker(
        context: null,
        contextError: 'context "gone": context not found',
        rootful: _engine(
          _rootful,
          access: DockerAccess.answers,
          loaded: true,
          active: true,
        ),
      );
      expect(_blockers(local(broken)), [
        LinuxBlockerKind.dockerContextUnavailable,
      ]);
      expect(local(broken, choice: true).dockerEndpoint?.explicit, isTrue);
    });

    test('without systemd Docker is not installed', () {
      final plan = _plan(
        LinuxDependencyInspection(
          system: _fresh.system,
          session: const LinuxSession(
            sessionBus: true,
            graphical: true,
            pkexec: true,
            systemd: false,
            userManager: false,
          ),
          secretService: _keyringUnlocked,
          docker: _fresh.docker,
        ),
        {LinuxTarget.local},
      );
      expect(_steps(plan), [LinuxDependencyStep.hermesTools]);
      expect(_blockers(plan), [LinuxBlockerKind.systemdMissing]);
    });
  });

  group('DockerEndpoint', () {
    const inherited = {
      'PATH': '/usr/bin',
      'DOCKER_CONTEXT': 'build-farm',
      'DOCKER_HOST': 'tcp://10.0.0.1:2375',
    };

    test('an explicit endpoint replaces the inherited context', () {
      final env = const DockerEndpoint(
        _rootful,
        explicit: true,
      ).applyTo(inherited);
      expect(env['DOCKER_HOST'], _rootful);
      expect(env, isNot(contains('DOCKER_CONTEXT')));
      expect(env['PATH'], '/usr/bin');
      expect(inherited['DOCKER_CONTEXT'], 'build-farm', reason: 'copied');
    });

    test('an inherited endpoint leaves the environment alone', () {
      expect(
        const DockerEndpoint(_rootful, explicit: false).applyTo(inherited),
        inherited,
      );
    });
  });

  group('LinuxSystemProbe.parse', () {
    List<String> lines(List<Map<String, Object?>> events, String result) => [
      for (final event in events) jsonEncode(event),
      result,
    ];
    const ok = '{"result":{"ok":true,"code":"ok","applied":[],"exit":0}}';

    test('reads a supported plan', () {
      final probe = LinuxSystemProbe.parse(
        lines([
          {'event': 'os', 'code': 'supported', 'base': 'trixie'},
          {'event': 'missing', 'category': 'hermes-tools', 'package': 'ffmpeg'},
          {'event': 'docker-footprint', 'code': 'snap'},
          {'event': 'secret-provider', 'code': 'absent'},
        ], ok),
        0,
      );
      expect(probe.os, LinuxOsSupport.supported);
      expect(probe.base, 'trixie');
      expect(probe.missing(LinuxHelperCategory.hermesTools), ['ffmpeg']);
      expect(probe.dockerFootprint, {DockerFootprint.snap});
      expect(probe.secretProviderInstalled, isFalse);
    });

    test('reads an unsupported verdict', () {
      final probe = LinuxSystemProbe.parse(
        lines(
          [
            {'event': 'os', 'code': 'unsupported-release'},
          ],
          '{"result":{"ok":false,"code":"unsupported-os","applied":[],"exit":4}}',
        ),
        4,
      );
      expect(probe.os, LinuxOsSupport.unsupportedRelease);
    });

    test('rejects refusals, gaps and apply-only events', () {
      for (final (output, exit) in [
        (
          [
            '{"result":{"ok":false,"code":"caller-invalid","applied":[],"exit":3}}',
          ],
          3,
        ),
        (lines([], ok), 0),
        (
          lines([
            {'event': 'os', 'code': 'supported', 'base': 'noble'},
          ], ok),
          0,
        ),
        (
          lines([
            {'event': 'os', 'code': 'supported', 'base': 'noble'},
            {'event': 'secret-provider', 'code': 'absent'},
            {'event': 'begin', 'category': 'hermes-tools'},
          ], ok),
          0,
        ),
        (
          lines([
            {'event': 'os', 'code': 'supported', 'base': 'noble'},
            {
              'event': 'missing',
              'category': 'docker-group',
              'package': 'docker',
            },
            {'event': 'secret-provider', 'code': 'absent'},
          ], ok),
          0,
        ),
      ]) {
        expect(
          () => LinuxSystemProbe.parse(output, exit),
          throwsFormatException,
          reason: '$output',
        );
      }
    });
  });

  group('LinuxDependencyService', () {
    late _Machine machine;
    late List<List<String>> pkexecRuns;
    late String privilegedSnippet;
    late void Function() onPrivileged;

    LinuxDependencyService service() {
      final helper = LinuxSetupHelper.bundled(
        executableDir: '/opt/hermuse-agent',
        compiledSha256: 'a' * 64,
      );
      return LinuxDependencyService(
        helper: helper,
        privilege: LinuxPrivilegeRunner(
          helper: helper,
          environment: _Machine.environment,
          startProcess: (executable, arguments, environment) async {
            pkexecRuns.add(arguments.sublist(arguments.indexOf('apply') + 1));
            final process = await Process.start('/usr/bin/sh', [
              '-c',
              privilegedSnippet,
            ]);
            // The helper's effect lands once it exits, like a real APT run.
            process.exitCode.then((_) => onPrivileged());
            return process;
          },
        ),
        environment: _Machine.environment,
        runCommand: machine.run,
        pathExists: machine.exists,
      );
    }

    Future<List<LinuxDependencyEvent>> applyAll(
      Set<LinuxTarget> targets, {
      LinuxApplyCancellation? cancellation,
      void Function(LinuxDependencyEvent)? onEvent,
    }) async {
      final dependencies = service();
      final plan = await dependencies.plan(targets);
      return dependencies.apply(plan, cancellation: cancellation).map((event) {
        onEvent?.call(event);
        return event;
      }).toList();
    }

    String helperSays(List<Map<String, Object?>> events, String result) {
      final lines = [for (final e in events) jsonEncode(e), result];
      return "printf '%s\\n' ${lines.map((l) => "'$l'").join(' ')}";
    }

    List<Map<String, Object?>> applied(List<String> categories) => [
      for (final category in categories) ...[
        {'event': 'begin', 'category': category},
        {'event': 'done', 'category': category},
      ],
    ];

    String okResult(List<String> categories) => jsonEncode({
      'result': {'ok': true, 'code': 'ok', 'applied': categories, 'exit': 0},
    });

    const everything = [
      'hermes-tools',
      'secret-service',
      'docker-install',
      'docker-start',
      'docker-group',
    ];

    setUp(() {
      machine = _Machine();
      pkexecRuns = [];
      onPrivileged = () {};
      privilegedSnippet = 'exit 126';
    });

    test('inspect reads the system and changes nothing', () async {
      final inspection = await service().inspect();

      expect(inspection.system?.os, LinuxOsSupport.supported);
      expect(inspection.system?.missing(LinuxHelperCategory.hermesTools), [
        'ripgrep',
      ]);
      expect(inspection.session.sessionBus, isTrue);
      expect(inspection.secretService.state, SecretServiceState.absent);
      expect(inspection.docker.cli, isNull);
      expect(machine.mutations, isEmpty);
      expect(pkexecRuns, isEmpty);
    });

    test(
      'a socket this session may not open is not a stopped engine',
      () async {
        machine
          ..dockerInstalled = true
          ..dockerActive = true
          ..userInDockerGroup = false;
        final docker = (await service().inspect()).docker;

        expect(docker.rootful.access, DockerAccess.permissionDenied);
        expect(docker.rootful.serviceActive, isTrue);
        expect(docker.userInGroup, isFalse);
        expect(docker.context?.host, _rootful);
      },
    );

    test('a fresh desktop is ready after one authorization', () async {
      privilegedSnippet = helperSays(applied(everything), okResult(everything));
      onPrivileged = () => machine
        ..missingTools = []
        ..keyringInstalled = true
        ..dockerInstalled = true
        ..dockerActive = true
        ..userInDockerGroup = true;

      final events = await applyAll({LinuxTarget.core, LinuxTarget.local});

      expect(pkexecRuns, [everything]);
      final result = events.last as LinuxDependencyResult;
      expect(result.outcome, LinuxApplyOutcome.ready);
      expect(result.plan.isSatisfied, isTrue);
      expect(events.whereType<LinuxDependencyResult>(), hasLength(1));
      expect(events.whereType<LinuxDependencyFinished>().map((e) => e.step), [
        LinuxDependencyStep.authorization,
        LinuxDependencyStep.hermesTools,
        LinuxDependencyStep.secretService,
        LinuxDependencyStep.dockerInstall,
        LinuxDependencyStep.dockerStart,
        LinuxDependencyStep.dockerGroup,
        LinuxDependencyStep.activateSecretService,
      ]);
      // The group reaches new logins only; the plugin bridges with `sg`.
      expect(result.inspection.docker.sessionInGroup, isFalse);
      expect(result.plan.dockerEndpoint?.host, _rootful);
    });

    test('a dismissed dialog never progresses to ready', () async {
      privilegedSnippet = 'exit 126';
      final events = await applyAll({LinuxTarget.core, LinuxTarget.local});

      final result = events.last as LinuxDependencyResult;
      expect(result.outcome, LinuxApplyOutcome.dismissed);
      expect(result.plan.isSatisfied, isFalse);
      expect(
        events.whereType<LinuxDependencyFinished>().single.outcome,
        LinuxStepOutcome.dismissed,
      );
      expect(machine.mutations, isEmpty, reason: 'no user step after refusal');
    });

    test('a refused authorization never progresses to ready', () async {
      privilegedSnippet =
          'echo "Error executing command as another user: '
          'No authentication agent found." >&2; exit 127';
      final events = await applyAll({LinuxTarget.core});

      final result = events.last as LinuxDependencyResult;
      expect(result.outcome, LinuxApplyOutcome.denied);
      expect(result.detail, contains('No authentication agent found'));
      expect(machine.mutations, isEmpty);
    });

    test('an inconsistent helper answer is a failure', () async {
      privilegedSnippet =
          "printf '%s\\n' '${okResult(['secret-service'])}'; exit 5";
      final events = await applyAll({LinuxTarget.core});

      final result = events.last as LinuxDependencyResult;
      expect(result.outcome, LinuxApplyOutcome.failed);
      expect(result.helper, isA<LinuxHelperFailed>());
      expect(machine.mutations, isEmpty);
    });

    test('a failed APT install is reported on its step', () async {
      privilegedSnippet = helperSays([
        {'event': 'begin', 'category': 'hermes-tools'},
        {'event': 'fail', 'category': 'hermes-tools', 'code': 'apt-failed'},
      ], '{"result":{"ok":false,"code":"apt-failed","applied":[],"exit":5}}');
      privilegedSnippet = '$privilegedSnippet; exit 5';
      machine.keyringRunning = true;
      final events = await applyAll({LinuxTarget.local});

      final failed = events.whereType<LinuxDependencyFinished>().last;
      expect(failed.step, LinuxDependencyStep.hermesTools);
      expect(failed.outcome, LinuxStepOutcome.failed);
      expect(
        (events.last as LinuxDependencyResult).outcome,
        LinuxApplyOutcome.failed,
      );
    });

    test(
      'a helper success the system does not confirm is incomplete',
      () async {
        machine
          ..keyringRunning = true
          ..dockerInstalled = true
          ..dockerActive = true
          ..userInDockerGroup = true;
        privilegedSnippet = helperSays(
          applied(['hermes-tools']),
          okResult(['hermes-tools']),
        );
        final events = await applyAll({LinuxTarget.local});

        final result = events.last as LinuxDependencyResult;
        expect(result.outcome, LinuxApplyOutcome.incomplete);
        expect(_steps(result.plan), [LinuxDependencyStep.hermesTools]);
      },
    );

    test('cancelling waits for the running step, then stops', () async {
      final done = File(
        '${Directory.systemTemp.path}/hermuse-cancel-${DateTime.now().microsecondsSinceEpoch}',
      );
      addTearDown(() => done.exists().then((e) => e ? done.delete() : null));
      privilegedSnippet =
          'sleep 0.3; touch "${done.path}"; '
          '${helperSays(applied(['secret-service']), okResult(['secret-service']))}';
      onPrivileged = () => machine.keyringInstalled = true;
      final cancellation = LinuxApplyCancellation();

      final events = await applyAll(
        {LinuxTarget.core},
        cancellation: cancellation,
        onEvent: (event) {
          if (event is LinuxDependencyStarted &&
              event.step == LinuxDependencyStep.authorization) {
            cancellation.cancel();
          }
        },
      );

      expect(done.existsSync(), isTrue, reason: 'the running step completed');
      final result = events.last as LinuxDependencyResult;
      expect(result.outcome, LinuxApplyOutcome.cancelled);
      expect(machine.mutations, isEmpty, reason: 'no step after the cancel');
      expect(_steps(result.plan), [LinuxDependencyStep.activateSecretService]);
    });
  });
}

/// A scripted desktop: answers the probes the service runs and records the
/// commands that would change something.
final class _Machine {
  static const environment = {
    'PATH': '/usr/local/bin:/usr/bin:/bin',
    'DISPLAY': ':0',
    'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
    'XDG_RUNTIME_DIR': '/run/user/1000',
  };

  List<String> missingTools = ['ripgrep'];
  bool keyringInstalled = false;
  bool keyringRunning = false;
  bool dockerInstalled = false;
  bool dockerActive = false;
  bool userInDockerGroup = false;
  final mutations = <String>[];

  Future<bool> exists(String path) async => switch (path) {
    '/opt/hermuse-agent/libexec/hermuse-linux-setup' ||
    '/usr/bin/pkexec' ||
    '/run/systemd/system' => true,
    '/usr/bin/docker' || '/var/run/docker.sock' => dockerInstalled,
    _ => false,
  };

  List<String> _plan() => [
    '{"event":"os","code":"supported","base":"noble"}',
    for (final package in missingTools)
      '{"event":"missing","category":"hermes-tools","package":"$package"}',
    if (!keyringInstalled) ...[
      '{"event":"missing","category":"secret-service","package":"gnome-keyring"}',
    ],
    if (dockerInstalled)
      '{"event":"docker-footprint","code":"package"}'
    else
      '{"event":"missing","category":"docker-install","package":"docker.io"}',
    '{"event":"secret-provider","code":"${keyringInstalled ? 'present' : 'absent'}"}',
    '{"result":{"ok":true,"code":"ok","applied":[],"exit":0}}',
  ];

  Future<ProcessResult> run(
    String executable,
    List<String> arguments,
    Map<String, String> env,
    Duration timeout,
  ) async {
    ProcessResult ok([String stdout = '']) => ProcessResult(1, 0, stdout, '');
    ProcessResult fail(String stderr, [int code = 1]) =>
        ProcessResult(1, code, '', stderr);
    final command = [executable, ...arguments].join(' ');
    if (executable == '/usr/bin/sh' && arguments.last == 'plan') {
      return ok('${_plan().join('\n')}\n');
    }
    if (executable == '/usr/bin/busctl') {
      final method = arguments.contains('get-property')
          ? 'Locked'
          : arguments[5];
      switch (method) {
        case 'NameHasOwner':
          return ok(keyringRunning ? 'b true\n' : 'b false\n');
        case 'Locked':
          return ok('b false\n');
        case 'ListActivatableNames':
          return ok(
            keyringInstalled
                ? 'as 2 "org.freedesktop.DBus" "org.freedesktop.secrets"\n'
                : 'as 1 "org.freedesktop.DBus"\n',
          );
        case 'ReloadConfig':
          mutations.add(command);
          return ok();
        case 'StartServiceByName':
          mutations.add(command);
          if (!keyringInstalled) {
            return fail('Call failed: The name is not activatable');
          }
          keyringRunning = true;
          return ok('u 1\n');
      }
    }
    if (executable == '/usr/bin/systemctl') {
      if (arguments.contains('start')) {
        mutations.add(command);
        return fail('Failed to start docker.service: Unit not found.', 5);
      }
      if (arguments.contains('--property=Version')) return ok('Version=255\n');
      final system = !arguments.contains('--user');
      final loaded = system && dockerInstalled;
      final active = system && dockerActive;
      return ok(
        'LoadState=${loaded ? 'loaded' : 'not-found'}\n'
        'ActiveState=${active ? 'active' : 'inactive'}\n',
      );
    }
    if (executable == '/usr/bin/id') {
      return switch (arguments) {
        ['-un'] => ok('ada\n'),
        ['-Gn'] => ok('ada sudo\n'),
        ['-Gn', 'ada'] => ok('ada sudo${userInDockerGroup ? ' docker' : ''}\n'),
        _ => fail('id: unexpected'),
      };
    }
    if (executable == '/usr/bin/getent') {
      return dockerInstalled ? ok('docker:x:999:\n') : fail('', 2);
    }
    if (executable == '/usr/bin/docker') {
      if (arguments.first == 'context') return ok('default|$_rootful\n');
      if (arguments.first == 'version') {
        if (!dockerActive) return fail('Cannot connect to the Docker daemon');
        return fail(
          'permission denied while trying to connect to the Docker daemon '
          'socket at $_rootful',
        );
      }
    }
    return fail('unexpected command: $command', 127);
  }
}
