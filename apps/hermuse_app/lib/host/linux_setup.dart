import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_state/hermuse_state.dart';

import '../platform/local_host.dart';
import '../platform/secure_secret_store.dart';

enum LinuxSetupGoal { reopen, connect, local, computer }

enum LinuxSetupPurpose { connect, dashboardLogin, provision }

/// Desktop keyring preparation is separate from service provisioning.
final class LinuxSetupServices {
  const LinuxSetupServices({
    required this.inspect,
    required this.install,
    required this.connect,
    required this.cancel,
    required this.register,
    required this.inspectKeyring,
    required this.applyKeyring,
    required this.quiesceOwnedLegacy,
  });

  static Future<LinuxSetupServices> forHost(LocalHermesHost host) async {
    const root = String.fromEnvironment('HERMUSE_WORKSPACE_ROOT');
    final installer = LinuxServiceInstaller.system(
      workspaceRoot: root.isEmpty ? null : root,
    );
    Future<LinuxDependencyService> keyringService() async {
      final helper = linuxHelperSha256.isEmpty && root.isNotEmpty
          ? await LinuxSetupHelper.fromWorkspace(root)
          : LinuxSetupHelper.bundled();
      return LinuxDependencyService.system(helper);
    }

    return LinuxSetupServices(
      inspect: installer.inspect,
      install: ({migration}) => installer.run(migration: migration),
      connect: installer.connect,
      cancel: installer.cancel,
      register: host.registerService,
      quiesceOwnedLegacy: () async {
        // Never stop a process merely because its command mentions Hermes.
        await host.supervisor?.dispose();
      },
      inspectKeyring: () async => LinuxDependencyPlan.compute(
        await (await keyringService()).inspect(),
        const {LinuxTarget.core},
      ),
      applyKeyring: (plan) async* {
        yield* (await keyringService()).apply(plan);
      },
    );
  }

  final Future<LinuxServiceInspection> Function() inspect;
  final Stream<RemoteInstallProgress> Function() connect;
  final Stream<RemoteInstallProgress> Function({
    LegacyHermesMigration? migration,
  })
  install;
  final Future<void> Function() cancel;
  final Future<HermesInstance> Function(HermesRegistry, RemoteInstallOutcome)
  register;
  final Future<LinuxDependencyPlan> Function() inspectKeyring;
  final Stream<LinuxDependencyEvent> Function(LinuxDependencyPlan) applyKeyring;
  final Future<void> Function() quiesceOwnedLegacy;
}

final linuxSetupServicesProvider = Provider<LinuxSetupServices?>((_) => null);
final linuxSetupProvider =
    NotifierProvider<LinuxSetupController, LinuxSetupState>(
      LinuxSetupController.new,
    );

sealed class SetupPhase {
  const SetupPhase();
}

final class SetupIdle extends SetupPhase {
  const SetupIdle();
}

final class SetupWorking extends SetupPhase {
  const SetupWorking(this.message);
  final String message;
}

final class SetupReview extends SetupPhase {
  const SetupReview(this.inspection);
  final LinuxServiceInspection inspection;
}

final class SetupDashboardLogin extends SetupPhase {
  const SetupDashboardLogin();
}

final class SetupKeyringReview extends SetupPhase {
  const SetupKeyringReview(this.message, {this.plan});
  final String message;
  final LinuxDependencyPlan? plan;
}

final class SetupInstalling extends SetupPhase {
  const SetupInstalling();
}

final class SetupFailed extends SetupPhase {
  const SetupFailed(this.message);
  final String message;
}

final class SetupStopped extends SetupPhase {
  const SetupStopped();
}

final class SetupFinished extends SetupPhase {
  const SetupFinished();
}

@immutable
final class LinuxSetupState {
  const LinuxSetupState({
    this.goal,
    this.purpose,
    this.phase = const SetupIdle(),
    this.keystoreVerified = false,
    this.stopping = false,
    this.log = const [],
    this.completed = const {},
    this.running,
  });
  final LinuxSetupGoal? goal;
  final LinuxSetupPurpose? purpose;
  final SetupPhase phase;
  final bool keystoreVerified;
  final bool stopping;
  final List<String> log;
  final Set<RemoteInstallStep> completed;
  final RemoteInstallStep? running;
  bool get active => phase is! SetupIdle && phase is! SetupFinished;
  bool get busy => phase is SetupWorking || phase is SetupInstalling;
  bool get showsReady =>
      phase is SetupFinished &&
      (goal == LinuxSetupGoal.local || goal == LinuxSetupGoal.computer);
  LinuxSetupState copyWith({
    LinuxSetupGoal? goal,
    LinuxSetupPurpose? purpose,
    SetupPhase? phase,
    bool? keystoreVerified,
    bool? stopping,
    List<String>? log,
    Set<RemoteInstallStep>? completed,
    RemoteInstallStep? running,
  }) => LinuxSetupState(
    goal: goal ?? this.goal,
    purpose: purpose ?? this.purpose,
    phase: phase ?? this.phase,
    keystoreVerified: keystoreVerified ?? this.keystoreVerified,
    stopping: stopping ?? this.stopping,
    log: log ?? this.log,
    completed: completed ?? this.completed,
    running: running ?? this.running,
  );
}

/// Linux only registers a verified system service. It never adopts ~/.hermes.
final class LinuxSetupController extends Notifier<LinuxSetupState> {
  Future<void>? _operation;
  bool _started = false;
  bool _stopRequested = false;
  LinuxSetupServices get _services => ref.read(linuxSetupServicesProvider)!;

  @override
  LinuxSetupState build() => const LinuxSetupState();

  Future<void> start() => _launch(() async {
    if (_started) return;
    _started = true;
    final registry = await ref.read(registryProvider.future);
    final local = registry.byId(localInstanceId);
    if (local?.kind == InstanceKind.local) {
      await _run(LinuxSetupGoal.local);
    } else if (registry.instances.isNotEmpty) {
      await _run(LinuxSetupGoal.reopen);
    } else {
      final inspection = await _services.inspect();
      if (inspection.canonicalPresent) {
        state = state.copyWith(goal: LinuxSetupGoal.local);
        if (await _keyring() && !_stopped()) _review(inspection);
      }
    }
  });

  Future<void> prepare(LinuxSetupGoal goal) => _launch(() => _run(goal));
  Future<void> checkAgain() => prepare(state.goal ?? LinuxSetupGoal.reopen);

  Future<void> _run(LinuxSetupGoal goal) async {
    state = LinuxSetupState(
      goal: goal,
      keystoreVerified: state.keystoreVerified,
    );
    if (!await _keyring() || _stopped()) return;
    if (goal == LinuxSetupGoal.reopen || goal == LinuxSetupGoal.connect) {
      _show(const SetupFinished());
      return;
    }
    _show(const SetupWorking('Inspecting this computer'));
    // Only app-owned processes may be quiesced. The helper refuses all others.
    await _services.quiesceOwnedLegacy();
    final inspection = await _services.inspect();
    if (!_stopped()) _review(inspection);
  }

  void _review(LinuxServiceInspection inspection) {
    final existingLocal =
        inspection.canonicalPresent && state.goal == LinuxSetupGoal.local;
    // An unavailable status probe must not be mistaken for an ungated service.
    // The login screen probes again without privileged service mutation.
    final dashboardLogin = existingLocal && inspection.authRequired != false;
    state = state.copyWith(
      purpose: dashboardLogin
          ? LinuxSetupPurpose.dashboardLogin
          : existingLocal
          ? LinuxSetupPurpose.connect
          : LinuxSetupPurpose.provision,
      phase: dashboardLogin
          ? const SetupDashboardLogin()
          : SetupReview(inspection),
    );
  }

  Future<bool> _keyring() async {
    _show(const SetupWorking('Checking the desktop keyring'));
    try {
      await verifySecretStore(ref.read(secretStoreProvider));
      state = state.copyWith(keystoreVerified: true);
      return true;
    } on Object catch (error) {
      LinuxDependencyPlan? plan;
      String detail = '$error';
      try {
        plan = await _services.inspectKeyring();
      } on Object catch (inspectionError) {
        detail = '$detail\n$inspectionError';
      }
      _show(SetupKeyringReview(detail, plan: plan));
      return false;
    }
  }

  /// Authorizes desktop access or the explicitly reviewed provisioning plan.
  /// Migration revisions are passed unchanged for helper-side validation.
  Future<void> authorize() => _launch(() async {
    final phase = state.phase;
    if (phase is SetupKeyringReview) {
      final plan = phase.plan;
      if (plan == null || plan.blockers.isNotEmpty) return;
      _show(const SetupWorking('Preparing the desktop keyring'));
      await for (final event in _services.applyKeyring(plan)) {
        if (event is LinuxDependencyLog) _log(event.line);
      }
      if (!_stopped()) await _run(state.goal ?? LinuxSetupGoal.reopen);
      return;
    }
    if (phase is! SetupReview) return;
    _show(const SetupInstalling());
    var completed = false;
    final progress = state.purpose == LinuxSetupPurpose.connect
        ? _services.connect()
        : _services.install(
            migration: phase.inspection.canonicalPresent
                ? null
                : phase.inspection.legacy,
          );
    await for (final event in progress) {
      switch (event) {
        case RemoteInstallStepStarted(:final step):
          state = state.copyWith(running: step);
        case RemoteInstallStepFinished(:final step):
          state = state.copyWith(completed: {...state.completed, step});
        case RemoteInstallLog(:final line):
          _log(line);
        case RemoteInstallCompleted(:final outcome):
          final registry = await ref.read(registryProvider.future);
          await _services.register(registry, outcome);
          ref.invalidate(connectionProvider(localInstanceId));
          // Do not report ready just because the helper exited successfully.
          await ref.read(restClientProvider(localInstanceId).future);
          completed = true;
      }
    }
    if (_stopped()) return;
    if (!completed) {
      throw StateError('Setup ended before the service was ready.');
    }
    _show(const SetupFinished());
  });

  /// Completes local setup after the dashboard login saved a verified instance.
  Future<void> dashboardLoginCompleted(String instanceId) => _launch(() async {
    if (state.phase is! SetupDashboardLogin) return;
    final registry = await ref.read(registryProvider.future);
    final instance = registry.byId(instanceId);
    if (instanceId != localInstanceId ||
        instance?.kind != InstanceKind.system) {
      throw StateError('Dashboard login did not register the local service.');
    }
    _show(const SetupWorking('Checking authenticated desktop access'));
    ref.invalidate(connectionProvider(localInstanceId));
    await ref.read(restClientProvider(localInstanceId).future);
    if (_stopped()) return;
    state = state.copyWith(
      completed: {...state.completed, RemoteInstallStep.verify},
      phase: const SetupFinished(),
    );
  });

  void cancel() {
    if (_operation != null) {
      _stopRequested = true;
      state = state.copyWith(stopping: true);
      unawaited(_services.cancel());
    } else {
      state = LinuxSetupState(keystoreVerified: state.keystoreVerified);
    }
  }

  Future<void> stopAndWait() async {
    final operation = _operation;
    if (operation == null) return;
    cancel();
    await operation;
  }

  void acknowledge() {
    if (state.phase is SetupFinished) {
      state = LinuxSetupState(keystoreVerified: state.keystoreVerified);
    }
  }

  bool _stopped() {
    if (!_stopRequested) return false;
    _show(const SetupStopped());
    return true;
  }

  Future<void> _launch(Future<void> Function() action) {
    if (_operation case final operation?) return operation;
    _stopRequested = false;
    // Scheduling the action also makes reentrant calls join this operation.
    final operation = Future<void>.microtask(() async {
      try {
        await action();
      } on Object catch (error) {
        if (!_stopped()) {
          _show(
            SetupFailed(
              error is RemoteInstallFailed ? error.message : '$error',
            ),
          );
        }
      } finally {
        _operation = null;
        if (ref.mounted) state = state.copyWith(stopping: false);
      }
    });
    _operation = operation;
    return operation;
  }

  void _show(SetupPhase phase) {
    if (ref.mounted) state = state.copyWith(phase: phase);
  }

  void _log(String line) {
    if (!ref.mounted) return;
    final lines = [...state.log, line];
    state = state.copyWith(
      log: lines.length > 200 ? lines.sublist(lines.length - 200) : lines,
    );
  }
}
