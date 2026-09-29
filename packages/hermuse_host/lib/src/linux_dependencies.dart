// Private fields with public constructor params need explicit initializers.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'host_environment.dart';
import 'linux_privilege.dart';

/// What the app prepares on Linux.
enum LinuxTarget {
  /// Needed by every connection: a working Secret Service keyring.
  core,

  /// Needed by a local Hermes Agent: its build tools and a Docker engine for
  /// the agent's computer. A remote instance never triggers it.
  local,
}

/// The helper's verdict on this operating system.
enum LinuxOsSupport {
  supported('supported'),
  unsupportedDistribution('unsupported-distribution'),
  unsupportedRelease('unsupported-release'),
  unsupportedArchitecture('unsupported-architecture'),
  unreadable('os-release-unreadable');

  const LinuxOsSupport(this.wire);

  /// The helper's `os` event code.
  final String wire;
}

/// A trace of an existing Docker installation, as the helper found it.
enum DockerFootprint {
  package('package'),
  binary('binary'),
  socket('socket'),
  unit('unit'),
  data('data'),
  config('config'),
  snap('snap'),
  rootless('rootless');

  const DockerFootprint(this.wire);

  /// The helper's `docker-footprint` event code.
  final String wire;
}

/// What `hermuse-linux-setup plan` reported: the same probes `apply`
/// re-checks as root.
final class LinuxSystemProbe {
  const LinuxSystemProbe({
    required this.os,
    this.base,
    this.missingPackages = const {},
    this.dockerFootprint = const {},
    this.secretProviderInstalled = false,
  });

  /// Parses the helper's `plan` stdout [lines] and exit status. Throws
  /// [FormatException] on anything but a complete, consistent plan.
  factory LinuxSystemProbe.parse(List<String> lines, int exitCode) {
    final output = parseLinuxHelperOutput(lines, exitCode);
    final result = output.result;
    if (result.applied.isNotEmpty ||
        (result.code != LinuxHelperCode.ok &&
            result.code != LinuxHelperCode.unsupportedOs)) {
      throw FormatException(
        'the setup helper refused to plan (${result.code.wire})',
      );
    }
    LinuxOsSupport? os;
    String? base;
    bool? provider;
    final missing = <LinuxHelperCategory, List<String>>{};
    final footprint = <DockerFootprint>{};
    for (final event in output.events) {
      switch (event.kind) {
        case LinuxHelperEventKind.os when os == null:
          os = LinuxOsSupport.values.firstWhere((s) => s.wire == event.code);
          base = event.base;
        case LinuxHelperEventKind.missing
            when _aptCategories.contains(event.category):
          (missing[event.category!] ??= []).add(event.package!);
        case LinuxHelperEventKind.dockerFootprint:
          footprint.add(
            DockerFootprint.values.firstWhere((f) => f.wire == event.code),
          );
        case LinuxHelperEventKind.secretProvider when provider == null:
          provider = event.code == 'present';
        default:
          throw FormatException('unexpected plan event: ${event.kind.wire}');
      }
    }
    final supported = os == LinuxOsSupport.supported;
    if (os == null ||
        supported != (result.code == LinuxHelperCode.ok) ||
        (supported && provider == null)) {
      throw const FormatException('incomplete plan from the setup helper');
    }
    return LinuxSystemProbe(
      os: os,
      base: base,
      missingPackages: missing,
      dockerFootprint: footprint,
      secretProviderInstalled: provider ?? false,
    );
  }

  static const _aptCategories = {
    LinuxHelperCategory.hermesTools,
    LinuxHelperCategory.secretService,
    LinuxHelperCategory.dockerInstall,
  };

  final LinuxOsSupport os;

  /// Base release codename (`jammy`, `noble`, `resolute`, `bookworm`,
  /// `trixie`) when [os] is supported.
  final String? base;

  /// Packages `apply` would install, per APT category.
  final Map<LinuxHelperCategory, List<String>> missingPackages;

  /// Every trace of an existing Docker; empty means none at all.
  final Set<DockerFootprint> dockerFootprint;

  /// Whether a D-Bus activation file for `org.freedesktop.secrets` is
  /// installed system-wide (any provider).
  final bool secretProviderInstalled;

  /// The packages `apply` would install for [category].
  List<String> missing(LinuxHelperCategory category) =>
      missingPackages[category] ?? const [];
}

/// The desktop session the app runs in.
final class LinuxSession {
  const LinuxSession({
    required this.sessionBus,
    required this.graphical,
    required this.pkexec,
    required this.systemd,
    required this.userManager,
  });

  /// Whether the D-Bus session bus answers.
  final bool sessionBus;

  /// Whether `DISPLAY` or `WAYLAND_DISPLAY` is set.
  final bool graphical;

  /// Whether `/usr/bin/pkexec` exists.
  final bool pkexec;

  /// Whether the system was booted with systemd.
  final bool systemd;

  /// Whether the systemd user manager answers (`systemctl --user`).
  final bool userManager;

  /// Whether an administrator can authorize a privileged step here.
  bool get canAuthorize => pkexec && graphical;
}

/// State of `org.freedesktop.secrets` on the session bus.
enum SecretServiceState {
  /// No session bus to ask.
  unavailable,

  /// Neither running nor activatable: no provider in this session.
  absent,

  /// Not running, but D-Bus can start it.
  activatable,

  /// A provider owns the name.
  running,
}

/// The Secret Service provider seen from this session.
final class SecretServiceStatus {
  const SecretServiceStatus(this.state, {this.locked});

  final SecretServiceState state;

  /// Whether the default collection is locked; null when unknown (not
  /// running, or no default collection yet). A locked keyring is unlocked
  /// through the system prompt when the app first uses it — never replaced.
  final bool? locked;
}

/// Outcome of `docker version` against one endpoint.
enum DockerAccess {
  /// The engine answered.
  answers,

  /// The socket exists but this session may not open it.
  permissionDenied,

  /// No answer (stopped, broken, timed out).
  noAnswer,

  /// Not asked: no `docker` command or no socket.
  notProbed,
}

/// One local engine: the system (rootful) one or the user's rootless one.
final class DockerEngineStatus {
  const DockerEngineStatus({
    required this.host,
    required this.access,
    this.detail = '',
    this.serviceLoaded = false,
    this.serviceActive = false,
  });

  /// Its endpoint, e.g. `unix:///var/run/docker.sock`.
  final String host;
  final DockerAccess access;

  /// First error line of the probe when it did not answer.
  final String detail;

  /// Whether its systemd unit `docker.service` exists (system manager for
  /// the rootful engine, user manager for the rootless one).
  final bool serviceLoaded;

  /// Whether that unit is active.
  final bool serviceActive;
}

/// The Docker CLI's current context.
final class DockerContext {
  const DockerContext({
    required this.name,
    required this.host,
    this.access = DockerAccess.notProbed,
    this.detail = '',
  });

  final String name;

  /// Its engine endpoint (`unix://…`, `tcp://…`, `ssh://…`).
  final String host;

  /// Probed only for endpoints other than the two local sockets.
  final DockerAccess access;
  final String detail;

  /// Whether the endpoint is not a local socket.
  bool get isRemote => !host.startsWith('unix://');
}

/// Docker as seen from this session.
final class DockerStatus {
  const DockerStatus({
    required this.rootful,
    this.cli,
    this.context,
    this.contextError = '',
    this.rootless,
    this.environmentOverride = false,
    this.userName = '',
    this.groupExists = false,
    this.userInGroup = false,
    this.sessionInGroup = false,
  });

  /// Path of the `docker` command on the host PATH, if any.
  final String? cli;

  /// The CLI's current context; null without a CLI or when it cannot be
  /// resolved ([contextError] then says why).
  final DockerContext? context;
  final String contextError;

  final DockerEngineStatus rootful;

  /// The user's rootless engine; null when `XDG_RUNTIME_DIR` is unknown.
  final DockerEngineStatus? rootless;

  /// Whether `DOCKER_HOST` or `DOCKER_CONTEXT` is set in the host
  /// environment.
  final bool environmentOverride;

  /// Login name of the session user.
  final String userName;

  /// Whether a `docker` group exists.
  final bool groupExists;

  /// Whether the account database lists the user in `docker`.
  final bool userInGroup;

  /// Whether this session already carries the `docker` group. When
  /// [userInGroup] is true but this is false (group added after login), the
  /// plugin reaches the socket through `sg docker` without a new login.
  final bool sessionInGroup;
}

/// Everything [LinuxDependencyService.inspect] found; read-only.
final class LinuxDependencyInspection {
  const LinuxDependencyInspection({
    required this.system,
    required this.session,
    required this.secretService,
    required this.docker,
    this.systemError = '',
  });

  /// The helper's `plan`; null when it could not run ([systemError]).
  final LinuxSystemProbe? system;
  final String systemError;
  final LinuxSession session;
  final SecretServiceStatus secretService;
  final DockerStatus docker;
}

/// One step of preparing the system, in execution order.
enum LinuxDependencyStep {
  /// The administrator authorization dialog (progress only, never planned).
  authorization(null),
  hermesTools(LinuxHelperCategory.hermesTools),
  secretService(LinuxHelperCategory.secretService),
  dockerInstall(LinuxHelperCategory.dockerInstall),
  dockerStart(LinuxHelperCategory.dockerStart),
  dockerGroup(LinuxHelperCategory.dockerGroup),

  /// As the user: reload the session bus and start `org.freedesktop.secrets`.
  activateSecretService(null),

  /// As the user: `systemctl --user start docker.service`.
  startRootlessDocker(null);

  const LinuxDependencyStep(this.category);

  /// The helper category of a privileged step; null for user steps.
  final LinuxHelperCategory? category;

  /// Whether the step runs as root through the helper.
  bool get privileged => category != null;

  /// The step applying helper [category].
  static LinuxDependencyStep forCategory(LinuxHelperCategory category) =>
      values.firstWhere((step) => step.category == category);
}

/// A planned step and why it is needed.
final class LinuxPlannedStep {
  const LinuxPlannedStep(
    this.step,
    this.explanation, {
    this.packages = const [],
    this.warning,
  });

  final LinuxDependencyStep step;

  /// English sentence for the consent and progress UI.
  final String explanation;

  /// Debian packages the step installs.
  final List<String> packages;

  /// What the user must know before consenting (the docker group is
  /// root-equivalent).
  final String? warning;
}

/// Why part of the preparation cannot happen automatically.
enum LinuxBlockerKind {
  /// The setup helper is missing or answered outside its protocol.
  helperUnavailable,

  /// Not a supported Debian/Ubuntu release on amd64.
  unsupportedOs,

  /// No D-Bus session bus: no keyring can work.
  sessionBusMissing,

  /// No pkexec or no graphical session to authorize a privileged step.
  authorizationUnavailable,

  /// Not booted with systemd: the Docker service cannot run.
  systemdMissing,

  /// The systemd user manager does not answer: the rootless Docker service
  /// cannot be started.
  userManagerMissing,

  /// The Docker CLI points at a remote engine; Hermuse Agent needs the
  /// user's explicit choice to use this computer's engine instead.
  dockerRemoteContext,

  /// The Docker CLI's context is broken or its local engine does not answer;
  /// the user may choose this computer's standard engine instead.
  dockerContextUnavailable,

  /// A Docker installation exists but is not usable, and it is never
  /// modified or replaced.
  dockerUnusable,
}

/// A blocker with its English explanation.
final class LinuxBlocker {
  const LinuxBlocker(this.kind, this.explanation, {this.details = const []});

  final LinuxBlockerKind kind;
  final String explanation;

  /// What would otherwise have been done (for authorizationUnavailable) or
  /// what was found.
  final List<String> details;

  /// Whether re-planning with `useLocalDockerEngine: true` addresses it.
  bool get offersLocalDockerEngine =>
      kind == LinuxBlockerKind.dockerRemoteContext ||
      kind == LinuxBlockerKind.dockerContextUnavailable;
}

/// The Docker endpoint Hermuse uses for the agent's computer.
final class DockerEndpoint {
  const DockerEndpoint(this.host, {required this.explicit});

  /// `unix:///var/run/docker.sock`, `unix:///run/user/1000/docker.sock`…
  final String host;

  /// Whether the supervised backend must receive `DOCKER_HOST` because the
  /// inherited Docker configuration resolves elsewhere. When false the
  /// backend inherits the user's configuration as is.
  final bool explicit;

  /// [environment] for the supervised Hermes backend only: with [explicit],
  /// `DOCKER_HOST` set to [host] and the inherited `DOCKER_CONTEXT` removed
  /// (the user's global Docker context is never changed).
  Map<String, String> applyTo(Map<String, String> environment) {
    final result = Map<String, String>.of(environment);
    if (explicit) {
      result
        ..remove('DOCKER_CONTEXT')
        ..['DOCKER_HOST'] = host;
    }
    return result;
  }
}

/// Docker's situation for Hermuse, as planned.
enum LinuxDockerState {
  /// A local engine answers for this user ([LinuxDependencyPlan.dockerEndpoint]
  /// says which), possibly through `sg docker` after a new group membership.
  usable,

  /// No Docker at all: the distribution's docker.io is planned.
  absent,

  /// The system engine is installed but stopped: its start is planned.
  stopped,

  /// The system engine runs but this user may not use it: the docker group
  /// is planned.
  noAccess,

  /// The user's rootless engine is installed but stopped: its start is
  /// planned.
  rootlessStopped,

  /// The Docker CLI points at a remote engine (blocker).
  remoteContext,

  /// The Docker CLI's context is broken or does not answer (blocker).
  contextUnavailable,

  /// Docker exists but is not usable, and is left alone (blocker).
  unusable,
}

/// What preparing [targets] still takes: steps in execution order (all
/// privileged ones under a single authorization, then the user ones),
/// blockers, and the Docker endpoint Hermuse will use.
final class LinuxDependencyPlan {
  const LinuxDependencyPlan._({
    required this.targets,
    required this.useLocalDockerEngine,
    required this.steps,
    required this.blockers,
    required this.dockerEndpoint,
    required this.dockerState,
  });

  /// Plans [targets] from [inspection]. With [useLocalDockerEngine] (the
  /// user's explicit choice), a remote or broken Docker context is ignored in
  /// favour of this computer's engine, for Hermuse only.
  factory LinuxDependencyPlan.compute(
    LinuxDependencyInspection inspection,
    Set<LinuxTarget> targets, {
    bool useLocalDockerEngine = false,
  }) {
    final planner = _Planner(inspection, useLocalDockerEngine);
    if (targets.contains(LinuxTarget.core)) planner.secretService();
    if (targets.contains(LinuxTarget.local)) {
      planner.hermesTools();
      planner.dockerEngine();
    }
    planner.steps.sort((a, b) => a.step.index.compareTo(b.step.index));
    return LinuxDependencyPlan._(
      targets: Set.unmodifiable(targets),
      useLocalDockerEngine: useLocalDockerEngine,
      steps: List.unmodifiable(planner.steps),
      blockers: List.unmodifiable(planner.blockers),
      dockerEndpoint: planner.endpoint,
      dockerState: planner.dockerState,
    );
  }

  final Set<LinuxTarget> targets;
  final bool useLocalDockerEngine;
  final List<LinuxPlannedStep> steps;
  final List<LinuxBlocker> blockers;

  /// The engine Hermuse uses once the steps ran; null without the local
  /// target or when Docker is blocked.
  final DockerEndpoint? dockerEndpoint;

  /// Docker's situation; null without the local target, or when the system
  /// could not be inspected well enough to tell.
  final LinuxDockerState? dockerState;

  /// The steps run as root, under one authorization.
  List<LinuxPlannedStep> get privilegedSteps => [
    for (final s in steps)
      if (s.step.privileged) s,
  ];

  /// The steps run as the user afterwards.
  List<LinuxPlannedStep> get userSteps => [
    for (final s in steps)
      if (!s.step.privileged) s,
  ];

  /// Whether applying asks for an administrator's authorization.
  bool get needsAuthorization => steps.any((s) => s.step.privileged);

  /// Whether nothing remains to do and nothing blocks.
  bool get isSatisfied => steps.isEmpty && blockers.isEmpty;
}

final class _Planner {
  _Planner(this.inspection, this.useLocalDockerEngine);

  final LinuxDependencyInspection inspection;
  final bool useLocalDockerEngine;
  final steps = <LinuxPlannedStep>[];
  final blockers = <LinuxBlocker>[];
  DockerEndpoint? endpoint;
  LinuxDockerState? dockerState;

  LinuxSystemProbe? get system => inspection.system;
  DockerStatus get docker => inspection.docker;

  void block(LinuxBlockerKind kind, String explanation, [String? detail]) {
    final index = blockers.indexWhere((b) => b.kind == kind);
    if (index < 0) {
      blockers.add(LinuxBlocker(kind, explanation, details: [?detail]));
    } else if (detail != null) {
      final existing = blockers[index];
      blockers[index] = LinuxBlocker(
        kind,
        existing.explanation,
        details: [...existing.details, detail],
      );
    }
  }

  /// Whether the helper can run privileged steps here; records the blocker
  /// (with [need] as detail) otherwise.
  bool privileged(String need) {
    final system = this.system;
    if (system == null) {
      block(
        LinuxBlockerKind.helperUnavailable,
        'Hermuse Agent cannot inspect this system '
        '(${inspection.systemError}). Reinstall Hermuse Agent.',
        need,
      );
      return false;
    }
    if (system.os != LinuxOsSupport.supported) {
      block(LinuxBlockerKind.unsupportedOs, _unsupportedOs(system.os), need);
      return false;
    }
    if (!inspection.session.canAuthorize) {
      block(
        LinuxBlockerKind.authorizationUnavailable,
        "Preparing this computer needs an administrator's authorization, "
        'which requires pkexec (polkit) in a graphical desktop session.',
        need,
      );
      return false;
    }
    return true;
  }

  void secretService() {
    switch (inspection.secretService.state) {
      case SecretServiceState.running:
        return;
      case SecretServiceState.unavailable:
        block(
          LinuxBlockerKind.sessionBusMissing,
          'No D-Bus session bus answers, so no keyring can hold your '
          'credentials. Sign in to a desktop session and try again.',
        );
        return;
      case SecretServiceState.activatable:
        steps.add(_activateSecretService);
      case SecretServiceState.absent:
        final system = this.system;
        final packages = system?.os == LinuxOsSupport.supported
            ? system!.missing(LinuxHelperCategory.secretService)
            : null;
        if (packages != null && packages.isEmpty) {
          // A provider is installed but this bus does not list it yet.
          steps.add(_activateSecretService);
          return;
        }
        final install = LinuxPlannedStep(
          LinuxDependencyStep.secretService,
          packages != null && !packages.contains('gnome-keyring')
              ? 'Install the keyring library Hermuse Agent uses '
                    '(${packages.join(', ')}).'
              : 'Install GNOME Keyring, the encrypted system keyring where '
                    'Hermuse Agent keeps your credentials '
                    '(${(packages ?? const ['gnome-keyring', 'libsecret-1-0']).join(', ')}).',
          packages: packages ?? const [],
        );
        if (!privileged(install.explanation)) return;
        steps
          ..add(install)
          ..add(_activateSecretService);
    }
  }

  void hermesTools() {
    final system = this.system;
    if (system == null || system.os != LinuxOsSupport.supported) {
      privileged('Check the build tools Hermes Agent needs.');
      return;
    }
    final packages = system.missing(LinuxHelperCategory.hermesTools);
    if (packages.isEmpty) return;
    final step = LinuxPlannedStep(
      LinuxDependencyStep.hermesTools,
      'Install the system packages Hermes Agent needs to build and run: '
      '${packages.join(', ')}.',
      packages: packages,
    );
    if (privileged(step.explanation)) steps.add(step);
  }

  void dockerEngine() => dockerState = _dockerEngine();

  LinuxDockerState? _dockerEngine() {
    final docker = this.docker;
    final context = docker.context;
    final rootful = docker.rootful;
    final rootless = docker.rootless;
    var preferRootless = false;
    if (!useLocalDockerEngine) {
      if (docker.cli != null && context == null) {
        block(
          LinuxBlockerKind.dockerContextUnavailable,
          'Docker cannot resolve its current context '
          '(${docker.contextError}). Hermuse Agent can use this '
          "computer's Docker engine instead, for itself only; your Docker "
          'settings stay as they are.',
        );
        return LinuxDockerState.contextUnavailable;
      }
      if (context != null &&
          context.host != rootful.host &&
          context.host != rootless?.host) {
        if (context.isRemote) {
          block(
            LinuxBlockerKind.dockerRemoteContext,
            'Docker is set to use the engine "${context.name}" at '
            "${context.host}, not this computer's. Hermuse Agent can use "
            "this computer's Docker engine instead, for itself only; your "
            'Docker settings stay as they are.',
          );
          return LinuxDockerState.remoteContext;
        }
        if (context.access == DockerAccess.answers) {
          endpoint = DockerEndpoint(context.host, explicit: false);
          return LinuxDockerState.usable;
        }
        block(
          LinuxBlockerKind.dockerContextUnavailable,
          'The Docker engine of the context "${context.name}" '
          '(${context.host}) does not answer'
          '${context.detail.isEmpty ? '' : ': ${context.detail}'}. Start it, '
          "or let Hermuse Agent use this computer's standard Docker engine "
          'for itself.',
        );
        return LinuxDockerState.contextUnavailable;
      }
      preferRootless = rootless != null && context?.host == rootless.host;
    }

    bool explicit(String host) =>
        useLocalDockerEngine ||
        (context == null ? docker.environmentOverride : context.host != host);
    void use(DockerEngineStatus engine) =>
        endpoint = DockerEndpoint(engine.host, explicit: explicit(engine.host));
    bool usable(DockerEngineStatus? engine) =>
        docker.cli != null &&
        engine != null &&
        (engine.access == DockerAccess.answers ||
            (identical(engine, rootful) &&
                engine.access == DockerAccess.permissionDenied &&
                docker.userInGroup));
    final startable =
        docker.cli != null &&
        rootless != null &&
        rootless.serviceLoaded &&
        !rootless.serviceActive;
    LinuxDockerState startRootless() {
      if (!inspection.session.userManager) {
        block(
          LinuxBlockerKind.userManagerMissing,
          'Your rootless Docker service is stopped and your systemd user '
          'session does not answer, so it cannot be started.',
        );
        return LinuxDockerState.rootlessStopped;
      }
      steps.add(
        const LinuxPlannedStep(
          LinuxDependencyStep.startRootlessDocker,
          'Start your rootless Docker service.',
        ),
      );
      use(rootless!);
      return LinuxDockerState.rootlessStopped;
    }

    final preferred = preferRootless ? rootless : rootful;
    final other = preferRootless ? rootful : rootless;
    if (usable(preferred)) {
      use(preferred!);
      return LinuxDockerState.usable;
    }
    if (preferRootless && startable) return startRootless();
    if (usable(other)) {
      use(other!);
      return LinuxDockerState.usable;
    }
    if (startable) return startRootless();

    if (rootful.serviceLoaded) {
      if (docker.cli == null) {
        block(
          LinuxBlockerKind.dockerUnusable,
          'Docker is installed but the docker command is missing. Hermuse '
          'Agent does not modify an existing Docker installation.',
        );
        return LinuxDockerState.unusable;
      }
      if (rootful.serviceActive &&
          rootful.access != DockerAccess.permissionDenied) {
        block(
          LinuxBlockerKind.dockerUnusable,
          'The Docker service runs but does not answer'
          '${rootful.detail.isEmpty ? '' : ': ${rootful.detail}'}. Hermuse '
          'Agent does not modify an existing Docker installation.',
        );
        return LinuxDockerState.unusable;
      }
      final start = !rootful.serviceActive;
      final join = !docker.userInGroup;
      if (join && !docker.groupExists) {
        block(
          LinuxBlockerKind.dockerUnusable,
          'Docker is installed without a docker group, so Hermuse Agent '
          'cannot be given access to it. Hermuse Agent does not modify an '
          'existing Docker installation.',
        );
        return LinuxDockerState.unusable;
      }
      final state = start
          ? LinuxDockerState.stopped
          : LinuxDockerState.noAccess;
      if (start && !inspection.session.systemd) {
        block(
          LinuxBlockerKind.systemdMissing,
          'The Docker service cannot be started: this system was not booted '
          'with systemd.',
        );
        return state;
      }
      final planned = [
        if (start) _dockerStart,
        if (join) _dockerGroup(docker.userName),
      ];
      if (privileged(planned.map((s) => s.explanation).join(' '))) {
        steps.addAll(planned);
        use(rootful);
      }
      return state;
    }

    final system = this.system;
    if (system == null || system.os != LinuxOsSupport.supported) {
      privileged("Set up Docker for the agent's computer.");
      return null;
    }
    final nothingThere =
        docker.cli == null &&
        system.dockerFootprint.isEmpty &&
        rootful.access == DockerAccess.notProbed;
    if (!nothingThere) {
      block(
        LinuxBlockerKind.dockerUnusable,
        'Docker is present on this computer but is not usable, and Hermuse '
        'Agent does not modify or replace an existing installation.',
        _dockerFindings(docker, system),
      );
      return LinuxDockerState.unusable;
    }
    if (!inspection.session.systemd) {
      block(
        LinuxBlockerKind.systemdMissing,
        'Docker cannot be installed as a service: this system was not booted '
        'with systemd.',
      );
      return LinuxDockerState.absent;
    }
    final packages = system.missing(LinuxHelperCategory.dockerInstall);
    final planned = [
      LinuxPlannedStep(
        LinuxDependencyStep.dockerInstall,
        "Install Docker from your distribution's repositories "
        "(${packages.join(', ')}) to run the agent's computer.",
        packages: packages,
      ),
      _dockerStart,
      _dockerGroup(docker.userName),
    ];
    if (privileged(planned.map((s) => s.explanation).join(' '))) {
      steps.addAll(planned);
      use(rootful);
    }
    return LinuxDockerState.absent;
  }

  static const _activateSecretService = LinuxPlannedStep(
    LinuxDependencyStep.activateSecretService,
    'Start the system keyring service in your session.',
  );

  static const _dockerStart = LinuxPlannedStep(
    LinuxDependencyStep.dockerStart,
    'Start the Docker service, and start it automatically at boot.',
  );

  static LinuxPlannedStep _dockerGroup(String user) => LinuxPlannedStep(
    LinuxDependencyStep.dockerGroup,
    'Add ${user.isEmpty ? 'your account' : user} to the docker group so '
    'Hermuse Agent can use Docker.',
    warning:
        'Members of the docker group control Docker without a password, '
        'which gives them root-equivalent access to this computer.',
  );

  static String _dockerFindings(DockerStatus docker, LinuxSystemProbe system) {
    final found = [
      if (docker.cli != null) 'docker command ${docker.cli}',
      for (final trace in system.dockerFootprint) trace.wire,
    ];
    final detail = docker.rootful.detail.isNotEmpty
        ? docker.rootful.detail
        : (docker.rootless?.detail ?? '');
    return 'Found: ${found.join(', ')}'
        '${detail.isEmpty ? '' : '. Docker says: $detail'}';
  }

  static String _unsupportedOs(LinuxOsSupport os) => switch (os) {
    LinuxOsSupport.unsupportedDistribution =>
      'Automatic setup supports Debian, Ubuntu and their derivatives (such '
          'as Pop!_OS and Linux Mint); this system is not one of them.',
    LinuxOsSupport.unsupportedRelease =>
      'Automatic setup supports Ubuntu 22.04, 24.04 and 26.04, Debian 12 '
          'and 13, and derivatives based on them; this release is not one '
          'of them.',
    LinuxOsSupport.unsupportedArchitecture =>
      'Automatic setup supports x86_64 (amd64) computers only.',
    LinuxOsSupport.unreadable =>
      'This system does not describe itself (/etc/os-release is '
          'unreadable), so it cannot be prepared automatically.',
    LinuxOsSupport.supported => '',
  };
}

/// Progress of [LinuxDependencyService.apply].
sealed class LinuxDependencyEvent {
  const LinuxDependencyEvent();
}

/// A step started ([LinuxDependencyStep.authorization]: the system dialog is
/// about to show).
final class LinuxDependencyStarted extends LinuxDependencyEvent {
  const LinuxDependencyStarted(this.step);
  final LinuxDependencyStep step;
}

/// A line of output (helper stderr, APT, a step's own message).
final class LinuxDependencyLog extends LinuxDependencyEvent {
  const LinuxDependencyLog(this.line);
  final String line;
}

/// How one step ended.
enum LinuxStepOutcome {
  done,

  /// Nothing to change (already installed, active, member…).
  skipped,
  failed,

  /// The authentication dialog was dismissed.
  dismissed,

  /// Authorization was refused or impossible.
  denied,
}

/// A step ended.
final class LinuxDependencyFinished extends LinuxDependencyEvent {
  const LinuxDependencyFinished(this.step, this.outcome, {this.detail = ''});
  final LinuxDependencyStep step;
  final LinuxStepOutcome outcome;

  /// English reason of a failure or skip, possibly empty.
  final String detail;
}

/// How [LinuxDependencyService.apply] ended.
enum LinuxApplyOutcome {
  /// Every step ran and a fresh inspection finds nothing left to do.
  ready,

  /// Every step ran, but a fresh inspection still finds work or blockers.
  incomplete,

  /// The authentication dialog was dismissed; nothing privileged ran.
  dismissed,

  /// Authorization was refused or impossible; nothing privileged ran.
  denied,

  /// A step failed, or the helper could not be trusted or understood.
  failed,

  /// [LinuxApplyCancellation.cancel] stopped it between two steps.
  cancelled,
}

/// The last event of [LinuxDependencyService.apply]: the outcome plus the
/// fresh inspection and plan it was decided on.
final class LinuxDependencyResult extends LinuxDependencyEvent {
  const LinuxDependencyResult(
    this.outcome,
    this.inspection,
    this.plan, {
    this.detail = '',
    this.helper,
  });

  final LinuxApplyOutcome outcome;

  /// Inspection taken after the steps, whatever happened.
  final LinuxDependencyInspection inspection;

  /// What remains, planned from [inspection] for the same targets.
  final LinuxDependencyPlan plan;

  /// English reason when not [LinuxApplyOutcome.ready].
  final String detail;

  /// How the privileged run ended, when there was one.
  final LinuxHelperOutcome? helper;
}

/// Stops [LinuxDependencyService.apply] before its next step. The step
/// running when [cancel] is called (an APT transaction included) always
/// completes.
final class LinuxApplyCancellation {
  bool _cancelled = false;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Inspects and prepares the Linux system for Hermuse Agent: Secret
/// Service, Hermes Agent build tools and a Docker engine.
///
/// [inspect] changes nothing. [LinuxDependencyPlan.compute] (or [plan])
/// turns an inspection into steps and blockers. [apply] runs every
/// privileged step under ONE pkexec authorization, then the user steps,
/// and decides success only from a fresh [inspect]. The app and Hermes never
/// run as root, and no password is ever read here.
///
/// Platform access goes through injectable callbacks; production uses
/// [LinuxDependencyService.system]. Every child process runs with
/// `includeParentEnvironment: false` and the host environment.
final class LinuxDependencyService {
  LinuxDependencyService({
    required LinuxSetupHelper helper,
    required LinuxPrivilegeRunner privilege,
    required Map<String, String> environment,
    required Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
      Duration timeout,
    )
    runCommand,
    required Future<bool> Function(String path) pathExists,
  }) : _helper = helper,
       _privilege = privilege,
       _environment = environment,
       _runCommand = runCommand,
       _pathExists = pathExists;

  /// Production service for [helper] with the host environment.
  factory LinuxDependencyService.system(LinuxSetupHelper helper) {
    final environment = hostEnvironment();
    return LinuxDependencyService(
      helper: helper,
      privilege: LinuxPrivilegeRunner(helper: helper, environment: environment),
      environment: environment,
      runCommand: _runDefault,
      pathExists: (path) async =>
          await FileSystemEntity.type(path) != FileSystemEntityType.notFound,
    );
  }

  final LinuxSetupHelper _helper;
  final LinuxPrivilegeRunner _privilege;
  final Map<String, String> _environment;
  final Future<ProcessResult> Function(
    String,
    List<String>,
    Map<String, String>,
    Duration,
  )
  _runCommand;
  final Future<bool> Function(String path) _pathExists;

  static const _sh = '/usr/bin/sh';
  static const _busctl = '/usr/bin/busctl';
  static const _systemctl = '/usr/bin/systemctl';
  static const _id = '/usr/bin/id';
  static const _getent = '/usr/bin/getent';
  static const _pkexec = LinuxPrivilegeRunner.pkexec;
  static const _secrets = 'org.freedesktop.secrets';
  static const _dockerSocket = '/var/run/docker.sock';
  static const _rootfulHost = 'unix://$_dockerSocket';
  static const _probeTimeout = Duration(seconds: 20);
  static const _dockerTimeout = Duration(seconds: 10);
  static const _stepTimeout = Duration(seconds: 90);
  static const _busArgs = [
    '--user',
    'call',
    'org.freedesktop.DBus',
    '/org/freedesktop/DBus',
    'org.freedesktop.DBus',
  ];

  /// Probes the system, the session, the keyring and Docker; changes
  /// nothing.
  Future<LinuxDependencyInspection> inspect() async {
    final (system, systemError) = await _probeSystem();
    final (bus, secretService) = await _probeSecretService();
    final session = LinuxSession(
      sessionBus: bus,
      graphical: _isSet('DISPLAY') || _isSet('WAYLAND_DISPLAY'),
      pkexec: await _pathExists(_pkexec),
      systemd: await _pathExists('/run/systemd/system'),
      userManager:
          (await _command(_systemctl, const [
            '--user',
            'show',
            '--property=Version',
          ])).exitCode ==
          0,
    );
    return LinuxDependencyInspection(
      system: system,
      systemError: systemError,
      session: session,
      secretService: secretService,
      docker: await _probeDocker(),
    );
  }

  /// Inspects, then plans [targets] (see [LinuxDependencyPlan.compute]).
  Future<LinuxDependencyPlan> plan(
    Set<LinuxTarget> targets, {
    bool useLocalDockerEngine = false,
  }) async => LinuxDependencyPlan.compute(
    await inspect(),
    targets,
    useLocalDockerEngine: useLocalDockerEngine,
  );

  /// Runs [plan]: its privileged steps under one authorization, then its
  /// user steps. Stops at the first refusal or failure, or before the next
  /// step once [cancellation] is cancelled — never in the middle of one.
  /// Always ends with a [LinuxDependencyResult] built on a fresh inspection.
  Stream<LinuxDependencyEvent> apply(
    LinuxDependencyPlan plan, {
    LinuxApplyCancellation? cancellation,
  }) {
    final controller = StreamController<LinuxDependencyEvent>();
    controller.onListen = () async {
      try {
        await _apply(
          plan,
          cancellation ?? LinuxApplyCancellation(),
          controller,
        );
      } on Object catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      } finally {
        await controller.close();
      }
    };
    return controller.stream;
  }

  Future<void> _apply(
    LinuxDependencyPlan plan,
    LinuxApplyCancellation cancellation,
    StreamController<LinuxDependencyEvent> controller,
  ) async {
    void emit(LinuxDependencyEvent event) {
      if (!controller.isClosed) controller.add(event);
    }

    LinuxApplyOutcome? outcome;
    var detail = '';
    LinuxHelperOutcome? helper;
    final categories = [for (final s in plan.privilegedSteps) s.step.category!];
    if (categories.isNotEmpty) {
      if (cancellation.isCancelled) {
        outcome = LinuxApplyOutcome.cancelled;
      } else {
        emit(const LinuxDependencyStarted(LinuxDependencyStep.authorization));
        var authorized = false;
        void authorize() {
          if (authorized) return;
          authorized = true;
          emit(
            const LinuxDependencyFinished(
              LinuxDependencyStep.authorization,
              LinuxStepOutcome.done,
            ),
          );
        }

        helper = await _privilege.apply(
          categories,
          onEvent: (event) {
            authorize();
            _forward(event, emit);
          },
          onLog: (line) => emit(LinuxDependencyLog(line)),
        );
        switch (helper) {
          case LinuxHelperFinished(:final result):
            authorize();
            if (!result.ok) {
              outcome = LinuxApplyOutcome.failed;
              detail = _helperFailure(result.code);
            }
          case LinuxHelperDismissed():
            outcome = LinuxApplyOutcome.dismissed;
            detail = 'The administrator authorization was dismissed.';
            emit(
              const LinuxDependencyFinished(
                LinuxDependencyStep.authorization,
                LinuxStepOutcome.dismissed,
              ),
            );
          case LinuxHelperDenied(detail: final reason):
            outcome = LinuxApplyOutcome.denied;
            detail =
                'The administrator authorization was refused or is not '
                'available in this session'
                '${reason.isEmpty ? '' : ' ($reason)'}.';
            emit(
              LinuxDependencyFinished(
                LinuxDependencyStep.authorization,
                LinuxStepOutcome.denied,
                detail: detail,
              ),
            );
          case LinuxHelperRejected(:final reason):
            outcome = LinuxApplyOutcome.failed;
            detail = _verifierFailure(reason);
            emit(
              LinuxDependencyFinished(
                LinuxDependencyStep.authorization,
                LinuxStepOutcome.failed,
                detail: detail,
              ),
            );
          case LinuxHelperFailed(:final reason):
            outcome = LinuxApplyOutcome.failed;
            detail = 'The system setup step failed: $reason.';
            if (!authorized) {
              emit(
                LinuxDependencyFinished(
                  LinuxDependencyStep.authorization,
                  LinuxStepOutcome.failed,
                  detail: detail,
                ),
              );
            }
        }
      }
    }
    if (outcome == null) {
      for (final planned in plan.userSteps) {
        if (cancellation.isCancelled) {
          outcome = LinuxApplyOutcome.cancelled;
          break;
        }
        emit(LinuxDependencyStarted(planned.step));
        final error = await _runUserStep(planned.step, emit);
        if (error == null) {
          emit(LinuxDependencyFinished(planned.step, LinuxStepOutcome.done));
        } else {
          emit(
            LinuxDependencyFinished(
              planned.step,
              LinuxStepOutcome.failed,
              detail: error,
            ),
          );
          outcome = LinuxApplyOutcome.failed;
          detail = error;
          break;
        }
      }
    }
    if (outcome == LinuxApplyOutcome.cancelled && detail.isEmpty) {
      detail = 'Stopped before the next step.';
    }
    final inspection = await inspect();
    final remaining = LinuxDependencyPlan.compute(
      inspection,
      plan.targets,
      useLocalDockerEngine: plan.useLocalDockerEngine,
    );
    if (outcome == null && !remaining.isSatisfied) {
      outcome = LinuxApplyOutcome.incomplete;
      detail = 'Some preparation is still missing.';
    }
    emit(
      LinuxDependencyResult(
        outcome ?? LinuxApplyOutcome.ready,
        inspection,
        remaining,
        detail: detail,
        helper: helper,
      ),
    );
  }

  static void _forward(
    LinuxHelperEvent event,
    void Function(LinuxDependencyEvent) emit,
  ) {
    final category = event.category;
    final step = category == null
        ? null
        : LinuxDependencyStep.forCategory(category);
    switch (event.kind) {
      case LinuxHelperEventKind.begin:
        emit(LinuxDependencyStarted(step!));
      case LinuxHelperEventKind.done:
        emit(LinuxDependencyFinished(step!, LinuxStepOutcome.done));
      case LinuxHelperEventKind.skip:
        emit(
          LinuxDependencyFinished(
            step!,
            LinuxStepOutcome.skipped,
            detail: switch (event.code) {
              'already-active' => 'Docker is already running.',
              'already-member' => 'Already a member of the docker group.',
              _ => 'Already installed.',
            },
          ),
        );
      case LinuxHelperEventKind.fail:
        emit(
          LinuxDependencyFinished(
            step!,
            LinuxStepOutcome.failed,
            detail: _helperFailure(LinuxHelperCode.fromWire(event.code)!),
          ),
        );
      case LinuxHelperEventKind.install:
        emit(LinuxDependencyLog('Installing ${event.package}.'));
      case LinuxHelperEventKind.aptUpdate when event.code == 'failed':
        emit(
          const LinuxDependencyLog(
            'Refreshing the package lists failed; installing from the lists '
            'already available.',
          ),
        );
      case LinuxHelperEventKind.note:
        emit(
          const LinuxDependencyLog(
            'Another keyring provider is installed; GNOME Keyring is not '
            'added.',
          ),
        );
      case LinuxHelperEventKind.dockerFootprint:
        emit(LinuxDependencyLog('Existing Docker found: ${event.code}.'));
      default:
        break;
    }
  }

  static String _helperFailure(LinuxHelperCode code) => switch (code) {
    LinuxHelperCode.ok => '',
    LinuxHelperCode.usage => 'The setup helper refused its arguments.',
    LinuxHelperCode.callerInvalid =>
      'The setup helper could not identify your account.',
    LinuxHelperCode.notRoot =>
      'The setup helper did not get administrator rights.',
    LinuxHelperCode.unsupportedOs =>
      'This system is not supported for automatic setup.',
    LinuxHelperCode.aptFailed =>
      'Installing packages failed; the log shows the APT error.',
    LinuxHelperCode.dockerStartFailed => 'The Docker service did not start.',
    LinuxHelperCode.usermodFailed => 'Joining the docker group failed.',
    LinuxHelperCode.dockerPresent =>
      'An existing Docker installation was found; Hermuse Agent does not '
          'replace it.',
    LinuxHelperCode.dockerUnitMissing =>
      'No Docker service is installed to start.',
    LinuxHelperCode.dockerGroupMissing =>
      'There is no docker group on this system.',
    LinuxHelperCode.internal => 'The setup helper failed unexpectedly.',
  };

  static String _verifierFailure(LinuxVerifierFailure reason) =>
      switch (reason) {
        LinuxVerifierFailure.arguments =>
          'The administrator step refused its arguments.',
        LinuxVerifierFailure.privateDirectory =>
          'The administrator step could not create its private directory.',
        LinuxVerifierFailure.copy =>
          'The setup helper is missing, unreadable or too large; reinstall '
              'Hermuse Agent.',
        LinuxVerifierFailure.digest =>
          'The setup helper does not match this version of Hermuse Agent; '
              'reinstall Hermuse Agent.',
      };

  Future<String?> _runUserStep(
    LinuxDependencyStep step,
    void Function(LinuxDependencyEvent) emit,
  ) async {
    final ProcessResult result;
    switch (step) {
      case LinuxDependencyStep.activateSecretService:
        // A provider installed moments ago is only activatable once the bus
        // re-reads its service files.
        await _command(_busctl, [
          ..._busArgs,
          'ReloadConfig',
        ], timeout: _stepTimeout);
        result = await _command(_busctl, [
          ..._busArgs,
          'StartServiceByName',
          'su',
          _secrets,
          '0',
        ], timeout: _stepTimeout);
      case LinuxDependencyStep.startRootlessDocker:
        result = await _command(_systemctl, const [
          '--user',
          'start',
          'docker.service',
        ], timeout: _stepTimeout);
      default:
        throw StateError('${step.name} is not a user step');
    }
    if (result.exitCode == 0) return null;
    for (final line in const LineSplitter().convert('${result.stderr}')) {
      if (line.trim().isNotEmpty) emit(LinuxDependencyLog(line));
    }
    final reason = _firstLine('${result.stderr}');
    return switch (step) {
          LinuxDependencyStep.activateSecretService =>
            'The keyring service did not start',
          _ => 'Your rootless Docker service did not start',
        } +
        (reason.isEmpty ? '.' : ': $reason');
  }

  Future<(LinuxSystemProbe?, String)> _probeSystem() async {
    if (!await _pathExists(_helper.path)) {
      return (null, 'the setup helper is missing: ${_helper.path}');
    }
    final result = await _command(_sh, [
      _helper.path,
      'plan',
    ], timeout: const Duration(seconds: 60));
    try {
      return (
        LinuxSystemProbe.parse(
          const LineSplitter().convert('${result.stdout}'),
          result.exitCode,
        ),
        '',
      );
    } on FormatException catch (e) {
      final error = _firstLine('${result.stderr}');
      return (
        null,
        'the setup helper answered unexpectedly: ${e.message}'
            '${error.isEmpty ? '' : ' ($error)'}',
      );
    }
  }

  Future<(bool, SecretServiceStatus)> _probeSecretService() async {
    final owner = await _command(_busctl, [
      ..._busArgs,
      'NameHasOwner',
      's',
      _secrets,
    ]);
    if (owner.exitCode != 0) {
      return (false, const SecretServiceStatus(SecretServiceState.unavailable));
    }
    if ('${owner.stdout}'.trim() == 'b true') {
      final locked = await _command(_busctl, const [
        '--user',
        'get-property',
        _secrets,
        '/org/freedesktop/secrets/aliases/default',
        'org.freedesktop.Secret.Collection',
        'Locked',
      ]);
      return (
        true,
        SecretServiceStatus(
          SecretServiceState.running,
          locked: locked.exitCode != 0
              ? null
              : switch ('${locked.stdout}'.trim()) {
                  'b true' => true,
                  'b false' => false,
                  _ => null,
                },
        ),
      );
    }
    final names = await _command(_busctl, [
      ..._busArgs,
      'ListActivatableNames',
    ]);
    final activatable =
        names.exitCode == 0 && '${names.stdout}'.contains('"$_secrets"');
    return (
      true,
      SecretServiceStatus(
        activatable
            ? SecretServiceState.activatable
            : SecretServiceState.absent,
      ),
    );
  }

  Future<DockerStatus> _probeDocker() async {
    final cli = await _which('docker');
    final user = await _command(_id, const ['-un']);
    final userName = user.exitCode == 0 ? '${user.stdout}'.trim() : '';
    final sessionGroups = await _command(_id, const ['-Gn']);
    final accountGroups = userName.isEmpty
        ? null
        : await _command(_id, ['-Gn', userName]);
    final group = await _command(_getent, const ['group', 'docker']);

    DockerContext? context;
    var contextError = '';
    if (cli != null) {
      final inspected = await _command(cli, const [
        'context',
        'inspect',
        '--format',
        '{{.Name}}|{{.Endpoints.docker.Host}}',
      ], timeout: _dockerTimeout);
      final line = _firstLine('${inspected.stdout}');
      final separator = line.indexOf('|');
      if (inspected.exitCode == 0 && separator > 0) {
        context = DockerContext(
          name: line.substring(0, separator),
          host: line.substring(separator + 1),
        );
      } else {
        final error = _firstLine('${inspected.stderr}');
        contextError = error.isEmpty ? 'docker context inspect failed' : error;
      }
    }

    final xdg = _environment['XDG_RUNTIME_DIR'] ?? '';
    final rootlessSocket = xdg.isEmpty ? null : '$xdg/docker.sock';
    final rootful = await _engine(
      cli,
      _rootfulHost,
      socket: _dockerSocket,
      userManager: false,
    );
    final rootless = rootlessSocket == null
        ? null
        : await _engine(
            cli,
            'unix://$rootlessSocket',
            socket: rootlessSocket,
            userManager: true,
          );
    if (cli != null &&
        context != null &&
        !context.isRemote &&
        context.host != rootful.host &&
        context.host != rootless?.host) {
      final (access, detail) = await _access(cli, _environment);
      context = DockerContext(
        name: context.name,
        host: context.host,
        access: access,
        detail: detail,
      );
    }
    return DockerStatus(
      cli: cli,
      context: context,
      contextError: contextError,
      rootful: rootful,
      rootless: rootless,
      environmentOverride: _isSet('DOCKER_HOST') || _isSet('DOCKER_CONTEXT'),
      userName: userName,
      groupExists: group.exitCode == 0,
      userInGroup:
          accountGroups != null &&
          accountGroups.exitCode == 0 &&
          _words('${accountGroups.stdout}').contains('docker'),
      sessionInGroup:
          sessionGroups.exitCode == 0 &&
          _words('${sessionGroups.stdout}').contains('docker'),
    );
  }

  Future<DockerEngineStatus> _engine(
    String? cli,
    String host, {
    required String socket,
    required bool userManager,
  }) async {
    final unit = await _command(_systemctl, [
      if (userManager) '--user',
      'show',
      '--property=LoadState',
      '--property=ActiveState',
      'docker.service',
    ]);
    final properties = {
      for (final line in const LineSplitter().convert('${unit.stdout}'))
        if (line.indexOf('=') case final i when i > 0)
          line.substring(0, i): line.substring(i + 1).trim(),
    };
    var access = DockerAccess.notProbed;
    var detail = '';
    if (cli != null && await _pathExists(socket)) {
      final environment = Map<String, String>.of(_environment)
        ..remove('DOCKER_CONTEXT')
        ..['DOCKER_HOST'] = host;
      (access, detail) = await _access(cli, environment);
    }
    return DockerEngineStatus(
      host: host,
      access: access,
      detail: detail,
      serviceLoaded: unit.exitCode == 0 && properties['LoadState'] == 'loaded',
      serviceActive:
          unit.exitCode == 0 && properties['ActiveState'] == 'active',
    );
  }

  Future<(DockerAccess, String)> _access(
    String cli,
    Map<String, String> environment,
  ) async {
    final result = await _command(
      cli,
      const ['version', '--format', '{{.Server.Version}}'],
      environment: environment,
      timeout: _dockerTimeout,
    );
    if (result.exitCode == 0) return (DockerAccess.answers, '');
    final detail = _firstLine('${result.stderr}');
    return (
      detail.toLowerCase().contains('permission denied')
          ? DockerAccess.permissionDenied
          : DockerAccess.noAnswer,
      detail,
    );
  }

  Future<ProcessResult> _command(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    Duration timeout = _probeTimeout,
  }) async {
    try {
      return await _runCommand(
        executable,
        arguments,
        environment ?? _environment,
        timeout,
      );
    } on ProcessException catch (e) {
      return ProcessResult(0, -1, '', 'cannot run $executable: ${e.message}');
    }
  }

  Future<String?> _which(String name) async {
    for (final dir in (_environment['PATH'] ?? '').split(':')) {
      if (!dir.startsWith('/')) continue;
      final candidate = '$dir/$name';
      if (await _pathExists(candidate)) return candidate;
    }
    return null;
  }

  bool _isSet(String name) => (_environment[name] ?? '').isNotEmpty;

  static Set<String> _words(String text) =>
      text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

  static String _firstLine(String text) => const LineSplitter()
      .convert(text)
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');

  static Future<ProcessResult> _runDefault(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
    Duration timeout,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
    );
    unawaited(process.stdin.close().catchError((Object _) {}));
    final stdout = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderr = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    if (exitCode == -1) {
      return ProcessResult(
        process.pid,
        -1,
        '',
        '$executable timed out after ${timeout.inSeconds} s',
      );
    }
    return ProcessResult(process.pid, exitCode, await stdout, await stderr);
  }
}
