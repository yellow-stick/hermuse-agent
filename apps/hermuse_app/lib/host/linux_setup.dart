import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';

import '../platform/local_host.dart';
import '../platform/secure_secret_store.dart';

/// What the Linux setup assistant prepares.
enum LinuxSetupGoal {
  /// The instances already registered: none connects before the keyring
  /// works.
  reopen({LinuxTarget.core}),

  /// A Hermes server about to be added: the keyring its credentials go to.
  connect({LinuxTarget.core}),

  /// Hermes Agent on this computer: the keyring, the build tools and Docker,
  /// then Hermes (adopted or installed), its backend, the Hermuse plugin,
  /// the subscription bridge and the agent's computer.
  local({LinuxTarget.core, LinuxTarget.local}),

  /// Docker for the agent's computer of the local instance, when the
  /// computer asks for the desktop setup.
  computer({LinuxTarget.core, LinuxTarget.local});

  const LinuxSetupGoal(this.targets);

  /// What the system half of this goal prepares.
  final Set<LinuxTarget> targets;
}

/// The system half of the assistant: [LinuxDependencyService] in production.
final class LinuxSystemAccess {
  const LinuxSystemAccess({required this.inspect, required this.apply})
    : unavailable = null;

  /// This build cannot run the setup helper; [reason] says why.
  const LinuxSystemAccess.unavailable(String reason)
    : unavailable = reason,
      inspect = null,
      apply = null;

  factory LinuxSystemAccess.of(LinuxDependencyService service) =>
      LinuxSystemAccess(inspect: service.inspect, apply: service.apply);

  /// [LinuxDependencyService.inspect]; null when [unavailable].
  final Future<LinuxDependencyInspection> Function()? inspect;

  /// [LinuxDependencyService.apply]; null when [unavailable].
  final Stream<LinuxDependencyEvent> Function(
    LinuxDependencyPlan plan, {
    LinuxApplyCancellation? cancellation,
  })?
  apply;

  /// Why the system cannot be inspected or prepared by this build.
  final String? unavailable;
}

/// What the assistant drives besides the providers (registry, secret store,
/// the local instance's REST client): [LinuxSetupServices.forHost] on Linux,
/// fakes in tests.
final class LinuxSetupServices {
  const LinuxSetupServices({
    required this.system,
    required this.hermesHome,
    required this.journalPath,
    required this.newInstaller,
    required this.detectHermes,
    required this.startBackend,
    required this.useDockerEndpoint,
    required this.installPlugin,
    required this.verifyBridge,
    required this.pluginDoctor,
    this.pollInterval = const Duration(seconds: 3),
  });

  /// Production services around [host], with the install journal at
  /// [journalPath]. A release build runs the helper bundled next to the
  /// executable, bound to its compiled digest; a development build runs the
  /// workspace helper only with `--dart-define=HERMUSE_WORKSPACE_ROOT=<repo>`.
  /// Without either the system half reports why it is unavailable.
  static Future<LinuxSetupServices> forHost(
    LocalHermesHost host, {
    required String journalPath,
  }) async {
    LinuxSystemAccess system;
    try {
      system = LinuxSystemAccess.of(
        LinuxDependencyService.system(await _setupHelper()),
      );
    } on LinuxSetupUnavailable catch (e) {
      system = LinuxSystemAccess.unavailable(e.message);
    }
    return LinuxSetupServices(
      system: system,
      hermesHome: host.hermesHome,
      journalPath: journalPath,
      newInstaller: () =>
          makeInstaller(host.hermesHome, journalPath: journalPath),
      detectHermes: host.detector.detect,
      startBackend: (registry, hermes, endpoint) {
        host.dockerEndpoint = endpoint;
        return host.adopt(registry, hermes);
      },
      useDockerEndpoint: (endpoint) => host.dockerEndpoint = endpoint,
      installPlugin: host.installPlugin,
      verifyBridge: CliproxyBinary.locate,
      pluginDoctor: host.pluginDoctor,
    );
  }

  final LinuxSystemAccess system;

  /// `HERMES_HOME` of this computer's Hermes.
  final String hermesHome;

  /// The [InstallJournal] of the app's own install.
  final String journalPath;

  /// A journaled installer for [hermesHome].
  final HermesInstaller Function() newInstaller;

  /// The install to use, if any; null while the journal is unfinished.
  final Future<DetectedHermes?> Function() detectHermes;

  /// Supervises a compatible install with the Docker [endpoint] and
  /// registers the local instance.
  final Future<HermesInstance> Function(
    HermesRegistry registry,
    DetectedHermes hermes,
    DockerEndpoint? endpoint,
  )
  startBackend;

  /// The Docker engine the next backend start uses.
  final void Function(DockerEndpoint? endpoint) useDockerEndpoint;

  /// Installs the bundled Hermuse plugin and restarts the backend.
  final Future<void> Function(HermesRegistry registry) installPlugin;

  /// Verifies the subscription bridge binary (it still starts on demand).
  final Future<void> Function() verifyBridge;

  /// `hermes hermuse doctor`; throws [ProcessFailed] when it reports a
  /// problem.
  final Future<void> Function() pluginDoctor;

  /// Delay between two looks at a computer being prepared.
  final Duration pollInterval;
}

/// Absolute path of the checkout a development build runs from
/// (`--dart-define=HERMUSE_WORKSPACE_ROOT=<repo>`), whose setup helper it
/// then trusts as it is.
const _workspaceRoot = String.fromEnvironment('HERMUSE_WORKSPACE_ROOT');

Future<LinuxSetupHelper> _setupHelper() async =>
    linuxHelperSha256.isEmpty && _workspaceRoot.isNotEmpty
    ? LinuxSetupHelper.fromWorkspace(_workspaceRoot)
    : LinuxSetupHelper.bundled();

/// The assistant's services; overridden in `main()` on Linux only, so every
/// other platform keeps its own paths.
final linuxSetupServicesProvider = Provider<LinuxSetupServices?>((_) => null);

/// The Linux setup assistant, kept alive with the app so an operation
/// outlives the screen that started it.
final linuxSetupProvider =
    NotifierProvider<LinuxSetupController, LinuxSetupState>(
      LinuxSetupController.new,
    );

/// A part of this computer the assistant prepares, in the order it does.
enum SetupPart {
  /// The system packages Hermes Agent needs to build and run.
  systemPackages,

  /// A Secret Service keyring that stores, returns and deletes a secret.
  keyring,

  /// A Docker engine the agent's computer can use.
  docker,

  /// A compatible Hermes Agent, adopted or installed, and its backend.
  hermes,

  /// The bundled Hermuse plugin on that Hermes Agent.
  plugin,

  /// The bundled subscription bridge, verified.
  bridge,

  /// The agent's computer: its image, its container and its screen.
  computer,
}

/// How a [SetupPart] became ready in this session.
enum SetupPartReadiness {
  /// It was already there and works: reused as it is.
  found,

  /// This session installed, started or set it up.
  prepared,
}

extension LinuxStepPart on LinuxDependencyStep {
  /// The part this system step prepares; null for the authorization.
  SetupPart? get part => switch (this) {
    LinuxDependencyStep.authorization => null,
    LinuxDependencyStep.hermesTools => SetupPart.systemPackages,
    LinuxDependencyStep.secretService ||
    LinuxDependencyStep.activateSecretService => SetupPart.keyring,
    LinuxDependencyStep.dockerInstall ||
    LinuxDependencyStep.dockerStart ||
    LinuxDependencyStep.dockerGroup ||
    LinuxDependencyStep.startRootlessDocker => SetupPart.docker,
  };
}

extension LinuxBlockerPart on LinuxBlocker {
  /// The part this blocker holds back; null when it concerns the whole
  /// system (no setup helper, an unsupported system, no way to authorize).
  SetupPart? get part => switch (kind) {
    LinuxBlockerKind.sessionBusMissing => SetupPart.keyring,
    LinuxBlockerKind.systemdMissing ||
    LinuxBlockerKind.userManagerMissing ||
    LinuxBlockerKind.dockerRemoteContext ||
    LinuxBlockerKind.dockerContextUnavailable ||
    LinuxBlockerKind.dockerUnusable => SetupPart.docker,
    LinuxBlockerKind.helperUnavailable ||
    LinuxBlockerKind.unsupportedOs ||
    LinuxBlockerKind.authorizationUnavailable => null,
  };
}

/// Where the assistant is.
@immutable
final class LinuxSetupState {
  const LinuxSetupState({
    this.goal,
    this.phase = const SetupIdle(),
    this.keystoreVerified = false,
    this.stopping = false,
    this.log = const [],
    this.parts = const {},
    this.hermesVersion,
  });

  final LinuxSetupGoal? goal;
  final SetupPhase phase;

  /// The keyring stored, returned and deleted a probe secret in this
  /// session: instances may connect and store their credentials.
  final bool keystoreVerified;

  /// A stop was asked; the running step finishes first.
  final bool stopping;

  /// Last output lines of the system setup or the Hermes install (at most
  /// 200).
  final List<String> log;

  /// The parts known ready in this session, and how. A part that a fresh
  /// check finds missing again leaves this map.
  final Map<SetupPart, SetupPartReadiness> parts;

  /// Release of the Hermes Agent in use (`0.21.5`), once known.
  final String? hermesVersion;

  /// Whether the assistant has something to show.
  bool get active => phase is! SetupIdle && phase is! SetupFinished;

  /// Whether the reached goal still shows its "ready" moment before the app
  /// takes the user on ([LinuxSetupController.acknowledge] ends it): the
  /// local Hermes Agent and the agent's computer, which the user watched
  /// being prepared.
  bool get showsReady =>
      phase is SetupFinished &&
      (goal == LinuxSetupGoal.local || goal == LinuxSetupGoal.computer);

  LinuxSetupState copyWith({
    LinuxSetupGoal? goal,
    SetupPhase? phase,
    bool? keystoreVerified,
    bool? stopping,
    List<String>? log,
    Map<SetupPart, SetupPartReadiness>? parts,
    String? hermesVersion,
  }) => LinuxSetupState(
    goal: goal ?? this.goal,
    phase: phase ?? this.phase,
    keystoreVerified: keystoreVerified ?? this.keystoreVerified,
    stopping: stopping ?? this.stopping,
    log: log ?? this.log,
    parts: parts ?? this.parts,
    hermesVersion: hermesVersion ?? this.hermesVersion,
  );
}

/// One screen of the assistant.
sealed class SetupPhase {
  const SetupPhase();
}

/// Nothing to prepare.
final class SetupIdle extends SetupPhase {
  const SetupIdle();
}

/// What a [SetupWorking] phase does.
enum SetupActivity {
  /// Inspecting the system half of the goal: the keyring, and for a local
  /// Hermes Agent its system packages and Docker.
  inspectingSystem(null),
  checkingKeyring(SetupPart.keyring),
  checkingDocker(SetupPart.docker),
  lookingForHermes(SetupPart.hermes),
  readingInstallPlan(SetupPart.hermes),

  /// Another app window runs the same install; this one waits for it.
  waitingForOtherInstall(SetupPart.hermes),
  startingHermes(SetupPart.hermes),
  installingPlugin(SetupPart.plugin),
  checkingBridge(SetupPart.bridge),

  /// The plugin's doctor, once everything else is ready.
  checkingPlugin(SetupPart.plugin);

  const SetupActivity(this.part);

  /// The part it works on; null for the whole system half.
  final SetupPart? part;
}

/// Checking or waiting on something that needs no answer.
final class SetupWorking extends SetupPhase {
  const SetupWorking(this.activity);
  final SetupActivity activity;
}

/// What the user must decide or fix: steps to authorize ("Prepare"),
/// blockers, a keyring that does not work, and how the last run ended.
final class SetupReview extends SetupPhase {
  const SetupReview({
    this.plan,
    this.blockers = const [],
    this.keyring,
    this.lastRun,
  });

  /// What remains to prepare; null when the system cannot be inspected.
  final LinuxDependencyPlan? plan;
  final List<LinuxBlocker> blockers;
  final KeyringProblem? keyring;
  final LinuxApplyReport? lastRun;

  List<LinuxPlannedStep> get steps => plan?.steps ?? const [];

  /// A blocker the user may lift by choosing this computer's Docker engine.
  bool get offersLocalDockerEngine =>
      plan?.useLocalDockerEngine != true &&
      blockers.any((b) => b.offersLocalDockerEngine);
}

/// The keyring refused the probe secret.
@immutable
final class KeyringProblem {
  const KeyringProblem({required this.locked, required this.detail});

  /// It stays locked (its unlock prompt was dismissed).
  final bool locked;
  final String detail;

  KeyringProblem seenIn(LinuxDependencyInspection? inspection) =>
      KeyringProblem(
        locked: locked || inspection?.secretService.locked == true,
        detail: detail,
      );
}

/// How a run of the planned steps ended, and which of them completed: a
/// run that did not finish may still have changed the system.
@immutable
final class LinuxApplyReport {
  const LinuxApplyReport(this.outcome, this.detail, this.finished);

  final LinuxApplyOutcome outcome;
  final String detail;

  /// Every step that ended, in order.
  final List<LinuxDependencyFinished> finished;

  /// The planned steps that were carried out.
  List<LinuxDependencyStep> get completed => [
    for (final f in finished)
      if (f.outcome == LinuxStepOutcome.done &&
          f.step != LinuxDependencyStep.authorization)
        f.step,
  ];
}

/// The planned steps running.
final class SetupApplying extends SetupPhase {
  const SetupApplying({
    required this.plan,
    this.outcomes = const {},
    this.running,
  });

  final LinuxDependencyPlan plan;
  final Map<LinuxDependencyStep, LinuxStepOutcome> outcomes;

  /// The step in progress ([LinuxDependencyStep.authorization]: the system
  /// dialog asks for the administrator password).
  final LinuxDependencyStep? running;
}

/// The Hermes Agent installer stages running.
final class SetupInstalling extends SetupPhase {
  const SetupInstalling({
    required this.manifest,
    this.done = const {},
    this.running,
  });

  final InstallManifest manifest;
  final Map<String, StageResult> done;
  final String? running;
}

/// The Hermes Agent install stopped on a failure.
final class SetupInstallFailed extends SetupPhase {
  const SetupInstallFailed({
    required this.message,
    this.manifest,
    this.done = const {},
    this.stage,
  });

  final String message;
  final InstallManifest? manifest;
  final Map<String, StageResult> done;

  /// The stage "Retry this stage" runs again; null when no single stage
  /// failed.
  final String? stage;
}

/// A Hermes install Hermuse Agent leaves as it is: an unsupported version,
/// or a checkout it did not install.
final class SetupHermesKept extends SetupPhase {
  const SetupHermesKept(this.message, {this.found});
  final String message;
  final DetectedHermes? found;
}

/// The agent's computer being prepared (image download or build, start).
final class SetupComputer extends SetupPhase {
  const SetupComputer({this.status});
  final ComputerStatus? status;
}

/// A step failed; "Check again" goes on from there.
final class SetupFailed extends SetupPhase {
  const SetupFailed(this.message, {this.part});
  final String message;

  /// The part that failed; null when the failure concerns none in
  /// particular.
  final SetupPart? part;
}

/// Stopped on request before the next step.
final class SetupStopped extends SetupPhase {
  const SetupStopped();
}

/// The goal is reached: the app takes the user on.
final class SetupFinished extends SetupPhase {
  const SetupFinished();
}

/// Prepares Linux for Hermuse Agent, in order: the system (keyring, build
/// tools, Docker) under one administrator authorization, a verified
/// keyring, then for a local Hermes: adoption or the journaled install, the
/// supervised backend, the plugin, the subscription bridge, the agent's
/// computer and the plugin's doctor.
///
/// Success is only ever what a fresh inspection or a real answer shows: a
/// dismissed or refused authorization, a failed step or a locked keyring
/// leaves an explicit incomplete state. Nothing running is interrupted: a
/// stop waits for the running step (authorization, APT transaction, install
/// stage) and prevents the next.
final class LinuxSetupController extends Notifier<LinuxSetupState> {
  static const _localDockerKey = 'linux_setup.local_docker_engine';
  static const _logLimit = 200;
  static const _setupRetry = Duration(seconds: 30);
  static const _maxStarts = 3;

  Future<void>? _operation;
  bool _started = false;
  bool _stopRequested = false;
  LinuxApplyCancellation? _cancellation;

  /// The satisfied plan of the current goal (its Docker endpoint).
  LinuxDependencyPlan? _plan;
  LinuxDependencyInspection? _inspection;

  /// The bundled plugin went onto the local Hermes in this session.
  bool _pluginInstalled = false;

  /// This session ran the Hermes Agent install to its end.
  bool _hermesInstalled = false;

  @override
  LinuxSetupState build() => const LinuxSetupState();

  LinuxSetupServices get _services =>
      ref.read(linuxSetupServicesProvider) ??
      (throw StateError('the Linux setup assistant runs on Linux only'));

  /// App start (once): resumes an unfinished local install, or checks the
  /// keyring (and the local Docker engine) before the registered instances
  /// connect.
  Future<void> start() {
    if (_started) return _operation ?? Future.value();
    _started = true;
    return _launch(() async {
      if (await _installPending()) return _run(LinuxSetupGoal.local);
      final registry = await ref.read(registryProvider.future);
      if (registry.instances.isNotEmpty) await _run(LinuxSetupGoal.reopen);
    });
  }

  /// Prepares [goal]: the user's choice ([LinuxSetupGoal.connect],
  /// [LinuxSetupGoal.local]) or the computer's call for Docker
  /// ([LinuxSetupGoal.computer]).
  Future<void> prepare(LinuxSetupGoal goal) => _launch(() => _run(goal));

  /// "Prepare": runs the reviewed steps, the privileged ones under a single
  /// authorization, then goes on with the goal.
  Future<void> authorize() => _launch(() async {
    final review = state.phase;
    final goal = state.goal;
    if (review is! SetupReview || goal == null) return;
    final plan = review.plan;
    if (plan == null || plan.steps.isEmpty) return;
    if (await _apply(plan) && !_stopped()) await _continue(goal);
  });

  /// "Check again": inspects again and goes on from where it stopped.
  Future<void> checkAgain() =>
      _launch(() => _run(state.goal ?? LinuxSetupGoal.reopen));

  /// The user's explicit choice of this computer's Docker engine, for
  /// Hermuse Agent only (their Docker settings stay as they are).
  Future<void> useLocalDockerEngine() => _launch(() async {
    await ref
        .read(hermuseDatabaseProvider)
        .writeSetting(_localDockerKey, 'true');
    await _run(state.goal ?? LinuxSetupGoal.local);
  });

  /// "Retry this stage": runs the failed install stage again, then the
  /// remaining ones, then goes on with the local goal.
  Future<void> retryStage() => _launch(() async {
    final failed = state.phase;
    if (failed is! SetupInstallFailed) return;
    final stage = failed.stage;
    if (stage == null) return;
    final lock = await _lockInstall();
    if (lock == null) return;
    try {
      final installer = _services.newInstaller();
      final manifest = failed.manifest ?? await installer.manifest();
      final done = {...failed.done}..remove(stage);
      _clearLog();
      _show(
        SetupInstalling(
          manifest: manifest,
          done: Map.unmodifiable(done),
          running: stage,
        ),
      );
      final result = await installer.runStage(stage, onLine: _installLine);
      done[stage] = result;
      if (result.failed) {
        _show(
          SetupInstallFailed(
            message: result.reason ?? 'The stage "$stage" failed.',
            manifest: manifest,
            done: Map.unmodifiable(done),
            stage: stage,
          ),
        );
        return;
      }
      if (_stopped() || !await _runStages(installer, manifest, done)) return;
    } on InstallBlocked catch (e) {
      _show(SetupHermesKept(e.message));
      return;
    } finally {
      await lock.close();
    }
    await _local();
  });

  /// Cancel: stops the running operation before its next step (the running
  /// authorization, APT transaction or install stage always completes);
  /// with nothing running, leaves the assistant.
  void cancel() {
    if (_operation != null) {
      _requestStop();
      return;
    }
    state = LinuxSetupState(keystoreVerified: state.keystoreVerified);
  }

  /// App exit: stops before the next step and waits for the running one.
  Future<void> stopAndWait() async {
    final running = _operation;
    if (running == null) return;
    _requestStop();
    await running;
  }

  /// The app took the user where [SetupFinished] leads.
  void acknowledge() {
    if (state.phase is SetupFinished) {
      state = LinuxSetupState(keystoreVerified: state.keystoreVerified);
    }
  }

  void _requestStop() {
    _stopRequested = true;
    _cancellation?.cancel();
    if (ref.mounted) state = state.copyWith(stopping: true);
  }

  /// Runs [body] as the one operation; a second request joins the running
  /// one. Any failure ends in [SetupFailed], never in silence.
  Future<void> _launch(Future<void> Function() body) {
    if (_operation case final running?) return running;
    _stopRequested = false;
    late final Future<void> operation;
    operation = () async {
      try {
        await body();
      } on Object catch (error) {
        if (ref.mounted) {
          _show(SetupFailed(_describe(error), part: _partOf(state.phase)));
        }
      } finally {
        if (identical(_operation, operation)) _operation = null;
        _cancellation = null;
        if (ref.mounted && state.stopping) {
          state = state.copyWith(stopping: false);
        }
      }
    }();
    _operation = operation;
    return operation;
  }

  Future<void> _run(LinuxSetupGoal goal) async {
    state = state.copyWith(goal: goal);
    KeyringProblem? keyring;
    if (goal == LinuxSetupGoal.reopen) {
      // A working keyring needs no inspection of the system.
      _show(const SetupWorking(SetupActivity.checkingKeyring));
      keyring = await _probeKeystore();
      if (keyring == null) return _reopened();
    }
    if (!await _prepareSystem(goal, keyring: keyring) || _stopped()) return;
    await _continue(goal);
  }

  /// Plans [goal] and applies at once what needs no consent (steps run as
  /// the user only). True when nothing is left; otherwise the review shows
  /// what remains, with the [keyring] problem already seen.
  Future<bool> _prepareSystem(
    LinuxSetupGoal goal, {
    KeyringProblem? keyring,
  }) async {
    final inspect = _services.system.inspect;
    if (inspect == null) {
      _plan = null;
      _inspection = null;
      if (!goal.targets.contains(LinuxTarget.local) && keyring == null) {
        return true;
      }
      _show(SetupReview(keyring: keyring, blockers: [?_unavailable()]));
      return false;
    }
    _show(const SetupWorking(SetupActivity.inspectingSystem));
    final inspection = _inspection = await inspect();
    final plan = LinuxDependencyPlan.compute(
      inspection,
      goal.targets,
      useLocalDockerEngine: await _localDockerChosen(),
    );
    _noteSystem(plan, inspection);
    if (plan.steps.isNotEmpty &&
        plan.blockers.isEmpty &&
        !plan.needsAuthorization) {
      // Only steps run as the user: nothing to consent to.
      return _apply(plan);
    }
    if (!plan.isSatisfied || keyring != null) {
      _show(
        SetupReview(
          plan: plan,
          blockers: plan.blockers,
          keyring: keyring?.seenIn(inspection),
        ),
      );
      return false;
    }
    _plan = plan;
    return true;
  }

  /// Runs [plan]. True when the fresh plan after it is satisfied; otherwise
  /// the review shows how the run ended, what it completed and what remains.
  Future<bool> _apply(LinuxDependencyPlan plan) async {
    final apply = _services.system.apply!;
    final cancellation = _cancellation = LinuxApplyCancellation();
    if (_stopRequested) cancellation.cancel();
    final outcomes = <LinuxDependencyStep, LinuxStepOutcome>{};
    final finished = <LinuxDependencyFinished>[];
    LinuxDependencyStep? running;
    void show() => _show(
      SetupApplying(
        plan: plan,
        outcomes: Map.unmodifiable(outcomes),
        running: running,
      ),
    );
    void review(
      LinuxDependencyPlan remaining,
      LinuxApplyOutcome outcome,
      String detail,
    ) => _show(
      SetupReview(
        plan: remaining,
        blockers: remaining.blockers,
        lastRun: LinuxApplyReport(outcome, detail, List.unmodifiable(finished)),
      ),
    );
    _clearLog();
    show();
    LinuxDependencyResult? result;
    try {
      await for (final event in apply(plan, cancellation: cancellation)) {
        switch (event) {
          case LinuxDependencyStarted(:final step):
            running = step;
            show();
          case LinuxDependencyFinished(:final step, :final outcome):
            outcomes[step] = outcome;
            finished.add(event);
            if (running == step) running = null;
            show();
          case LinuxDependencyLog(:final line):
            _log(line);
          case LinuxDependencyResult():
            result = event;
        }
      }
    } on Object catch (error) {
      review(plan, LinuxApplyOutcome.failed, _describe(error));
      return false;
    } finally {
      _cancellation = null;
    }
    final ended = result;
    if (ended == null) {
      review(
        plan,
        LinuxApplyOutcome.failed,
        'The system setup ended without a result.',
      );
      return false;
    }
    _inspection = ended.inspection;
    _noteSystem(
      ended.plan,
      ended.inspection,
      prepared: {
        for (final f in finished)
          if (f.outcome == LinuxStepOutcome.done) ?f.step.part,
      },
    );
    if (ended.outcome == LinuxApplyOutcome.ready) {
      _plan = ended.plan;
      return true;
    }
    review(ended.plan, ended.outcome, ended.detail);
    return false;
  }

  /// The system is ready: a verified keyring, then the rest of [goal].
  Future<void> _continue(LinuxSetupGoal goal) async {
    _show(const SetupWorking(SetupActivity.checkingKeyring));
    final keyring = await _probeKeystore();
    if (keyring != null) {
      _show(
        SetupReview(
          plan: _plan,
          blockers: [...?_plan?.blockers, ?_unavailable()],
          keyring: keyring.seenIn(_inspection),
        ),
      );
      return;
    }
    if (_stopped()) return;
    switch (goal) {
      case LinuxSetupGoal.reopen:
        return _reopened();
      case LinuxSetupGoal.connect:
        return _finish();
      case LinuxSetupGoal.local:
        return _local();
      case LinuxSetupGoal.computer:
        return _computerGoal();
    }
  }

  /// A real write, read and delete of a probe secret; null when they
  /// worked. A locked keyring raises its own unlock prompt here.
  Future<KeyringProblem?> _probeKeystore() async {
    try {
      await verifySecretStore(ref.read(secretStoreProvider));
    } on Object catch (error) {
      _forget(SetupPart.keyring);
      return KeyringProblem(
        locked: isKeyringLocked(error),
        detail: _describe(error),
      );
    }
    if (ref.mounted) {
      state = state.copyWith(
        keystoreVerified: true,
        parts: {
          ...state.parts,
          SetupPart.keyring:
              state.parts[SetupPart.keyring] ?? SetupPartReadiness.found,
        },
      );
    }
    return null;
  }

  /// The registered instances may connect; a registered local instance's
  /// backend first gets the Docker engine planned for it.
  Future<void> _reopened() async {
    final registry = await ref.read(registryProvider.future);
    final inspect = _services.system.inspect;
    if (registry.byId(localInstanceId) != null && inspect != null) {
      _show(const SetupWorking(SetupActivity.checkingDocker));
      DockerEndpoint? endpoint;
      try {
        endpoint = LinuxDependencyPlan.compute(await inspect(), const {
          LinuxTarget.local,
        }, useLocalDockerEngine: await _localDockerChosen()).dockerEndpoint;
      } on Exception {
        // The agent's computer reports Docker problems itself; the
        // instances still connect.
        endpoint = null;
      }
      _services.useDockerEndpoint(endpoint);
      if (endpoint != null && !state.parts.containsKey(SetupPart.docker)) {
        _note(SetupPart.docker, SetupPartReadiness.found);
      }
    }
    _finish();
  }

  Future<void> _local() async {
    final hermes = await _hermes();
    if (hermes == null || _stopped()) return;
    final registry = await ref.read(registryProvider.future);
    _show(const SetupWorking(SetupActivity.startingHermes));
    await _startBackend(registry, hermes);
    if (_stopped()) return;
    if (!_pluginInstalled) {
      _show(const SetupWorking(SetupActivity.installingPlugin));
      await _services.installPlugin(registry);
      // The backend restarted on a new port.
      _reconnectLocal();
      await _withLocalRest(_pluginMounted);
      _pluginInstalled = true;
    }
    _note(SetupPart.plugin, SetupPartReadiness.prepared);
    if (_stopped()) return;
    _show(const SetupWorking(SetupActivity.checkingBridge));
    try {
      await _services.verifyBridge();
    } on CliproxyVerificationFailed catch (e) {
      _show(
        SetupFailed(
          'The subscription bridge cannot be trusted: ${e.message}. '
          'Reinstall Hermuse Agent.',
          part: SetupPart.bridge,
        ),
      );
      return;
    }
    _note(SetupPart.bridge, SetupPartReadiness.found);
    if (_stopped() || !await _computerUntilReady(registry, hermes)) return;
    _show(const SetupWorking(SetupActivity.checkingPlugin));
    try {
      await _services.pluginDoctor();
    } on ProcessFailed catch (e) {
      _clearLog();
      e.outputTail.split('\n').where((l) => l.trim().isNotEmpty).forEach(_log);
      _show(SetupFailed(e.message, part: SetupPart.plugin));
      return;
    }
    await ref.read(activeThreadProvider.notifier).openInstance(localInstanceId);
    _finish();
  }

  Future<void> _computerGoal() async {
    _show(const SetupWorking(SetupActivity.lookingForHermes));
    final hermes = await _services.detectHermes();
    if (hermes == null || !hermes.compatible) {
      _show(
        SetupFailed(
          hermes == null
              ? 'Hermes Agent is not installed on this computer.'
              : incompatibleHermesMessage(hermes),
          part: SetupPart.hermes,
        ),
      );
      return;
    }
    _noteHermes(hermes);
    final registry = await ref.read(registryProvider.future);
    _show(const SetupWorking(SetupActivity.startingHermes));
    await _startBackend(registry, hermes);
    if (!_stopped() && await _computerUntilReady(registry, hermes)) _finish();
  }

  /// A compatible Hermes to supervise: the one found (an unsupported one is
  /// left as it is), or the journaled install, fresh or resumed.
  Future<DetectedHermes?> _hermes() async {
    _show(const SetupWorking(SetupActivity.lookingForHermes));
    final found = await _services.detectHermes();
    if (found != null) {
      if (found.compatible) {
        _noteHermes(found);
        return found;
      }
      _forget(SetupPart.hermes);
      _show(SetupHermesKept(incompatibleHermesMessage(found), found: found));
      return null;
    }
    if (_stopped() || !await _install()) return null;
    final installed = await _services.detectHermes();
    if (installed != null && installed.compatible) {
      _noteHermes(installed);
      return installed;
    }
    _show(
      SetupFailed(
        installed == null
            ? 'The install finished, but its Hermes Agent does not answer.'
            : incompatibleHermesMessage(installed),
        part: SetupPart.hermes,
      ),
    );
    return null;
  }

  /// [hermes] is the one in use: prepared when this session installed it,
  /// found otherwise.
  void _noteHermes(DetectedHermes hermes) {
    if (!ref.mounted) return;
    state = state.copyWith(
      parts: {
        ...state.parts,
        SetupPart.hermes: _hermesInstalled
            ? SetupPartReadiness.prepared
            : SetupPartReadiness.found,
      },
      hermesVersion: hermes.semver,
    );
  }

  Future<bool> _install() async {
    final lock = await _lockInstall();
    if (lock == null) return false;
    try {
      final installer = _services.newInstaller();
      _show(const SetupWorking(SetupActivity.readingInstallPlan));
      final manifest = await installer.manifest();
      if (_stopped()) return false;
      _clearLog();
      return await _runStages(installer, manifest, {});
    } on InstallBlocked catch (e) {
      _show(SetupHermesKept(e.message));
      return false;
    } on InstallFailed catch (e) {
      _show(SetupInstallFailed(message: e.message));
      return false;
    } finally {
      await lock.close();
    }
  }

  /// [HermesInstaller.run] with its logs as they come; a stage the journal
  /// records as done is not run again. A stop lets the running stage finish
  /// (and be journaled) and starts no other.
  Future<bool> _runStages(
    HermesInstaller installer,
    InstallManifest manifest,
    Map<String, StageResult> done,
  ) async {
    String? running;
    void show() => _show(
      SetupInstalling(
        manifest: manifest,
        done: Map.unmodifiable(done),
        running: running,
      ),
    );
    show();
    try {
      await for (final event in installer.run()) {
        switch (event) {
          case InstallStageStarted(:final stage):
            running = stage.name;
            show();
          case InstallStageFinished(:final stage, :final result):
            done[stage.name] = result;
            running = null;
            show();
            // A failed stage ends the run with its InstallFailed.
            if (!result.failed && _stopped()) return false;
          case InstallLog(:final stream, :final line):
            _installLine(stream, line);
        }
      }
    } on InstallFailed catch (e) {
      _show(
        SetupInstallFailed(
          message: e.message,
          manifest: manifest,
          done: Map.unmodifiable(done),
          stage: manifest.stages.any((s) => s.name == e.stage) ? e.stage : null,
        ),
      );
      return false;
    }
    _hermesInstalled = true;
    return true;
  }

  /// Holds the install for this app instance: another window running the
  /// same stages waits here instead. Null when stopped while waiting.
  Future<RandomAccessFile?> _lockInstall() async {
    final file = File('${_services.journalPath}.lock');
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);
    var waiting = false;
    while (true) {
      try {
        await handle.lock(FileLock.exclusive);
        return handle;
      } on FileSystemException {
        if (!waiting) {
          waiting = true;
          _show(const SetupWorking(SetupActivity.waitingForOtherInstall));
        }
      }
      if (_stopped()) {
        await handle.close();
        return null;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _startBackend(
    HermesRegistry registry,
    DetectedHermes hermes,
  ) async {
    final before = registry.byId(localInstanceId)?.baseUrl;
    final instance = await _services.startBackend(
      registry,
      hermes,
      _plan?.dockerEndpoint,
    );
    if (before != null && before != instance.baseUrl) _reconnectLocal();
  }

  /// Waits for the plugin routes of the restarted backend (the plugin
  /// install registered the Hermuse jobs).
  Future<void> _pluginMounted(HermesRestClient rest) async {
    for (var attempt = 1; ; attempt++) {
      try {
        await rest.getJson('$hermusePluginRoute/files');
        return;
      } on HermesHttpError catch (e) {
        if (e.statusCode != 404 || attempt >= 20) rethrow;
      }
      await Future<void>.delayed(_services.pollInterval);
    }
  }

  /// [_computer] until the agent's computer is ready. When Docker does not
  /// answer the computer, the system is checked again once (its review
  /// shows what is missing); when the system is ready, the backend restarts
  /// with the Docker engine now planned and the computer is set up again.
  Future<bool> _computerUntilReady(
    HermesRegistry registry,
    DetectedHermes hermes,
  ) async {
    for (var recheck = true; ; recheck = false) {
      switch (await _computer(recheck: recheck)) {
        case _ComputerResult.ready:
          return true;
        case _ComputerResult.stopped:
          return false;
        case _ComputerResult.recheck:
          if (_stopped()) return false;
          await _startBackend(registry, hermes);
      }
    }
  }

  /// Sets the agent's computer up through the backend and follows its real
  /// state until it runs and its screen answers. A download or build in
  /// progress is not ready; Docker missing (the desktop-setup hint) or not
  /// answering goes back to the system, once ([recheck]).
  Future<_ComputerResult> _computer({required bool recheck}) => _withLocalRest((
    rest,
  ) async {
    final computer = ComputerClient(rest);
    _show(const SetupComputer());
    var status = await computer.setup();
    // Running at once: the computer was already there.
    final found = status.state == ComputerState.running;
    var setupAt = DateTime.now();
    var starts = 0;
    while (true) {
      _show(SetupComputer(status: status));
      switch (status.state) {
        case ComputerState.running:
          if (!await _showsScreen(computer)) return _ComputerResult.stopped;
          _note(
            SetupPart.computer,
            found ? SetupPartReadiness.found : SetupPartReadiness.prepared,
          );
          return _ComputerResult.ready;
        case ComputerState.stopped:
          if (++starts > _maxStarts) {
            _show(
              SetupFailed(
                "The agent's computer stops right after it starts"
                '${status.detail.isEmpty ? '' : ': ${status.detail}'}.',
                part: SetupPart.computer,
              ),
            );
            return _ComputerResult.stopped;
          }
          await computer.start();
          status = await computer.status();
          continue;
        case ComputerState.dockerMissing || ComputerState.daemonDown:
          if (!recheck) {
            _show(SetupFailed(_dockerUnusable(status), part: SetupPart.docker));
            return _ComputerResult.stopped;
          }
          return await _prepareSystem(state.goal ?? LinuxSetupGoal.computer)
              ? _ComputerResult.recheck
              : _ComputerResult.stopped;
        case ComputerState.error:
          _show(
            SetupFailed(
              status.detail.isEmpty
                  ? "The agent's computer could not be prepared."
                  : status.detail,
              part: SetupPart.computer,
            ),
          );
          return _ComputerResult.stopped;
        case ComputerState.missing:
          _show(
            const SetupFailed(
              'The Hermuse plugin does not answer on this computer.',
              part: SetupPart.plugin,
            ),
          );
          return _ComputerResult.stopped;
        case ComputerState.imageMissing || ComputerState.building:
          break;
      }
      if (_stopped()) return _ComputerResult.stopped;
      await Future<void>.delayed(_services.pollInterval);
      if (status.state == ComputerState.imageMissing &&
          DateTime.now().difference(setupAt) >= _setupRetry) {
        // No bootstrap runs: start it again (this retries a failed one).
        status = await computer.setup();
        setupAt = DateTime.now();
      } else {
        status = await computer.status();
      }
    }
  });

  static String _dockerUnusable(ComputerStatus status) =>
      'Docker is prepared on this computer, but Hermes Agent cannot use it'
      '${status.needsDesktopSetup || status.detail.isEmpty ? '' : ': ${status.detail}'}.';

  /// A running computer counts once its screen answers.
  Future<bool> _showsScreen(ComputerClient computer) async {
    Object? failure;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        if ((await computer.thumbnail()).isNotEmpty) return true;
      } on HermesException catch (e) {
        failure = e;
      }
      if (_stopped()) return false;
      await Future<void>.delayed(_services.pollInterval);
    }
    _show(
      SetupFailed(
        "The agent's computer runs but its screen does not answer"
        '${failure == null ? '' : ': ${_describe(failure)}'}.',
        part: SetupPart.computer,
      ),
    );
    return false;
  }

  /// [body] with the local instance's REST client, kept open meanwhile.
  Future<T> _withLocalRest<T>(
    Future<T> Function(HermesRestClient rest) body,
  ) async {
    final subscription = ref.listen(
      restClientProvider(localInstanceId).future,
      (_, _) {},
    );
    try {
      return await body(await subscription.read());
    } finally {
      subscription.close();
    }
  }

  /// The local backend restarted: reopen its connection and the chats that
  /// held the old one.
  void _reconnectLocal() {
    ref.invalidate(connectionProvider(localInstanceId));
    ref.invalidate(chatSessionProvider);
    ref.invalidate(pluginStatusProvider(localInstanceId));
  }

  /// An unfinished (or unreadable) journal of this Hermes home: its install
  /// resumes before anything connects.
  Future<bool> _installPending() async {
    final services = _services;
    try {
      final journal = await InstallJournal.read(services.journalPath);
      return journal != null &&
          !journal.finished &&
          journal.hermesHome == services.hermesHome;
    } on FormatException {
      return true;
    } on FileSystemException {
      return true;
    }
  }

  Future<bool> _localDockerChosen() async =>
      await ref.read(hermuseDatabaseProvider).readSetting(_localDockerKey) ==
      'true';

  /// The blocker of a build that cannot run the setup helper; null when it
  /// can.
  LinuxBlocker? _unavailable() => switch (_services.system.unavailable) {
    null => null,
    final reason => LinuxBlocker(
      LinuxBlockerKind.helperUnavailable,
      'Hermuse Agent cannot inspect or prepare this computer: $reason.',
    ),
  };

  /// Whether a stop was asked; the stopped state shows when it was.
  bool _stopped() {
    if (!_stopRequested) return false;
    _show(const SetupStopped());
    return true;
  }

  void _finish() => _show(const SetupFinished());

  void _show(SetupPhase phase) {
    if (ref.mounted) state = state.copyWith(phase: phase);
  }

  void _note(SetupPart part, SetupPartReadiness readiness) {
    if (ref.mounted) {
      state = state.copyWith(parts: {...state.parts, part: readiness});
    }
  }

  void _forget(SetupPart part) {
    if (ref.mounted && state.parts.containsKey(part)) {
      state = state.copyWith(parts: {...state.parts}..remove(part));
    }
  }

  /// Records the system parts of [plan]'s targets that [inspection] finds
  /// ready: the [prepared] ones as prepared by this session, the others as
  /// found (a part this session prepared stays so). A part with work left
  /// or a blocker is forgotten.
  void _noteSystem(
    LinuxDependencyPlan plan,
    LinuxDependencyInspection inspection, {
    Set<SetupPart> prepared = const {},
  }) {
    if (!ref.mounted) return;
    final parts = {...state.parts};
    for (final part in [
      if (plan.targets.contains(LinuxTarget.local)) SetupPart.systemPackages,
      if (plan.targets.contains(LinuxTarget.core)) SetupPart.keyring,
      if (plan.targets.contains(LinuxTarget.local)) SetupPart.docker,
    ]) {
      if (!_systemReady(part, plan, inspection)) {
        parts.remove(part);
      } else if (prepared.contains(part)) {
        parts[part] = SetupPartReadiness.prepared;
      } else {
        parts.putIfAbsent(part, () => SetupPartReadiness.found);
      }
    }
    state = state.copyWith(parts: parts);
  }

  /// Whether [plan] leaves [part] nothing to do, nothing blocks it, and
  /// [inspection] saw it in place.
  static bool _systemReady(
    SetupPart part,
    LinuxDependencyPlan plan,
    LinuxDependencyInspection inspection,
  ) {
    if (plan.steps.any((s) => s.step.part == part) ||
        plan.blockers.any((b) => b.part == part)) {
      return false;
    }
    final system = inspection.system;
    return switch (part) {
      SetupPart.systemPackages =>
        system != null &&
            system.os == LinuxOsSupport.supported &&
            system.missing(LinuxHelperCategory.hermesTools).isEmpty,
      SetupPart.keyring =>
        inspection.secretService.state == SecretServiceState.running,
      SetupPart.docker => plan.dockerState == LinuxDockerState.usable,
      _ => false,
    };
  }

  /// The part [phase] works on, which a failure during it concerns.
  static SetupPart? _partOf(SetupPhase phase) => switch (phase) {
    SetupWorking(:final activity) => activity.part,
    SetupInstalling() => SetupPart.hermes,
    SetupComputer() => SetupPart.computer,
    _ => null,
  };

  void _clearLog() {
    if (ref.mounted) state = state.copyWith(log: const []);
  }

  void _installLine(String stream, String line) => _log('[$stream] $line');

  void _log(String line) {
    if (!ref.mounted) return;
    final log = [...state.log, line];
    state = state.copyWith(
      log: log.length > _logLimit ? log.sublist(log.length - _logLimit) : log,
    );
  }
}

enum _ComputerResult {
  ready,

  /// The state on screen says why (failure, review, stop).
  stopped,

  /// The system was prepared again: restart the backend, then retry.
  recheck,
}

/// A sentence for the user, not a stack dump.
String _describe(Object error) => switch (error) {
  HostException(:final message) => message,
  HermesException(:final message) => message,
  PlatformException(:final message, :final code) => message ?? code,
  StateError(:final message) => message,
  FormatException(:final message) => message,
  FileSystemException(:final message, :final path) =>
    path == null ? message : '$message: $path',
  _ => '$error',
};
