import 'dart:async';

import 'package:cliproxy_client/cliproxy_client.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:hermuse_chat/hermuse_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'providers.dart';

part 'onboarding.g.dart';

/// Where this instance sits in the Hermes onboarding flow.
///
/// `setup.status` says whether any provider is configured at all (the loose
/// pre-check); `setup.runtime_check` probes whether the *resolved* model route
/// can actually be served (the strict gate). The machine descends both,
/// stopping at the first failing stage; `defaultModel` is reached only once
/// the route is servable, because the next probe must not mask the failing one.
enum OnboardingStep {
  /// Strict probe: can the resolved model route be served right now.
  runtimeCheck,

  /// No route yet: pick a way to authenticate a model provider.
  connections,

  /// A provider is configured: pick the default model.
  defaultModel,

  /// Model set: the guided presentation conversation.
  profile,

  /// Everything above is done: the instance is usable.
  ready,
}

/// One problem the strict `setup.runtime_check` probe found, with the hint
/// the UI shows next to it.
final class RuntimeProblem {
  const RuntimeProblem({required this.message, this.fixHint});

  /// The server's `error` sentence (or a generated one).
  final String message;

  /// How to fix it (the probed provider, source, model).
  final String? fixHint;
}

/// Free-tier identity verdict plus the retry path when the mint failed.
final class FreeTierInfo {
  const FreeTierInfo({
    required this.enabled,
    required this.available,
    required this.noticePending,
    required this.model,
    required this.label,
    this.error,
    this.errorCode,
    this.retryable,
    this.retryAfter,
  });

  final bool enabled;
  final bool available;
  final bool noticePending;

  /// Carry model of the free tier (e.g. `nous/welcome`).
  final String model;

  final String label;

  /// Mint-failure detail when the identity is missing (`last_mint_failure`).
  final String? error;
  final String? errorCode;
  final bool? retryable;
  final int? retryAfter;
}

/// The onboarding state of one instance.
final class OnboardingState {
  const OnboardingState({
    required this.step,
    this.providerConfigured = false,
    this.problems = const [],
    this.freeTier,
    this.modelOptions,
    this.profileName,
    this.setupSession,
    this.modelChosen = false,
    this.profileDone = false,
  });

  final OnboardingStep step;

  /// A default model is settled: chosen in this flow, skipped, or the
  /// instance was already ready when onboarding opened.
  final bool modelChosen;

  /// The presentation step is settled (started, skipped, or not needed).
  final bool profileDone;

  /// Loose `setup.status` verdict: any provider auth discoverable.
  final bool providerConfigured;

  /// Non-empty while [step] is [OnboardingStep.runtimeCheck] and failing.
  final List<RuntimeProblem> problems;

  /// Free-tier shortcut state (loaded eagerly; null while loading).
  final FreeTierInfo? freeTier;

  /// Default-model picker inventory (loaded when [step] reaches
  /// [OnboardingStep.defaultModel]).
  final ModelOptionsResult? modelOptions;

  /// Name of the backend-owned setup profile (`hermes-setup` upstream).
  final String? profileName;

  /// The guided presentation conversation, once started.
  final ThreadRef? setupSession;

  OnboardingState copyWith({
    OnboardingStep? step,
    bool? providerConfigured,
    List<RuntimeProblem>? problems,
    FreeTierInfo? Function()? freeTier,
    ModelOptionsResult? Function()? modelOptions,
    String? Function()? profileName,
    ThreadRef? Function()? setupSession,
    bool? modelChosen,
    bool? profileDone,
  }) => OnboardingState(
    step: step ?? this.step,
    providerConfigured: providerConfigured ?? this.providerConfigured,
    problems: problems ?? this.problems,
    freeTier: freeTier == null ? this.freeTier : freeTier(),
    modelOptions: modelOptions == null ? this.modelOptions : modelOptions(),
    profileName: profileName == null ? this.profileName : profileName(),
    setupSession: setupSession == null ? this.setupSession : setupSession(),
    modelChosen: modelChosen ?? this.modelChosen,
    profileDone: profileDone ?? this.profileDone,
  );
}

/// Confirmed before persisting an expensive default model: the server answered
/// `confirm_required` and asks the user to agree first.
final class ExpensiveModelConfirmation implements Exception {
  const ExpensiveModelConfirmation({required this.message});

  final String message;

  @override
  String toString() => 'ExpensiveModelConfirmation: $message';
}

/// The profile Hermes itself told us to use for this instance, or null for
/// the launch profile.
Future<String?> _profileOf(Ref ref, String instanceId) async {
  final registry = await ref.watch(registryProvider.future);
  final profile = registry.byId(instanceId)?.profile;
  return (profile == null || profile.isEmpty) ? null : profile;
}

/// `setup.status` says ready when a provider is configured (loose check).
bool setupStatusReady(SetupStatusResult status) =>
    status.providerConfigured ?? false;

/// Derives the onboarding step from the two readiness probes.
OnboardingStep deriveOnboardingStep({
  required SetupStatusResult status,
  required SetupRuntimeCheckResult runtimeCheck,
  required bool modelChosen,
  required bool profileDone,
}) {
  if (!setupStatusReady(status)) return OnboardingStep.connections;
  if (!runtimeCheck.ok) return OnboardingStep.runtimeCheck;
  if (!modelChosen) return OnboardingStep.defaultModel;
  if (!profileDone) return OnboardingStep.profile;
  return OnboardingStep.ready;
}

/// Onboarding state machine of one instance, over its shared connection.
///
/// Re-reads both readiness probes whenever the boot bootstrap re-announces
/// `setup.ready` (the event payload is only a hint), and advances
/// [OnboardingStep.defaultModel] → [OnboardingStep.profile] →
/// [OnboardingStep.ready] explicitly via [chooseModel]/[startProfileConversation].
///
/// Auto-disposed with its screen so it does not pin the instance connection.
@riverpod
class Onboarding extends _$Onboarding {
  StreamSubscription<HermesEvent>? _readySub;

  @override
  Future<OnboardingState> build(String instanceId) async {
    ref.onDispose(() => unawaited(_readySub?.cancel()));
    final connection = await ref.watch(connectionProvider(instanceId).future);
    // `setup.ready` is broadcast, not session-scoped: no chat competes for it,
    // and every chat routes only its own session's server requests.
    _readySub = connection.transport.events
        .where((event) => event is SetupReadyEvent)
        .listen((_) => refresh());
    final profile = await _profileOf(ref, instanceId);
    final status = await connection.transport.call(
      HermesMethods.setupStatus,
      ProfileParams(profile: profile),
    );
    final check = await connection.transport.call(
      HermesMethods.setupRuntimeCheck,
      SetupRuntimeCheckParams(profile: profile),
    );
    final freeTier = await _readFreeTier(connection.transport, profile);
    // An instance that already serves its configured model needs no
    // onboarding: it opens at `ready` (steps stay reachable from settings).
    final alreadyReady = setupStatusReady(status) && check.ok;
    return _derive(
      status: status,
      check: check,
      freeTier: freeTier,
      modelChosen: alreadyReady,
      profileDone: alreadyReady,
    );
  }

  /// Re-runs both readiness probes and re-derives the step, keeping the
  /// remembered `defaultModel`/`profile` progress.
  Future<void> refresh() async {
    final previous = state.value;
    if (previous == null || state.isLoading) return;
    // ignore: invalid_use_of_internal_member
    state = AsyncLoading<OnboardingState>().copyWithPrevious(state);
    try {
      final connection = await ref.read(connectionProvider(instanceId).future);
      final profile = await _profileOf(ref, instanceId);
      final status = await connection.transport.call(
        HermesMethods.setupStatus,
        ProfileParams(profile: profile),
      );
      final check = await connection.transport.call(
        HermesMethods.setupRuntimeCheck,
        SetupRuntimeCheckParams(profile: profile),
      );
      final freeTier = await _readFreeTier(connection.transport, profile);
      state = AsyncData(
        _derive(
          status: status,
          check: check,
          freeTier: freeTier,
          modelChosen: previous.modelChosen,
          modelOptions: previous.modelOptions,
          profileDone: previous.profileDone,
          profileName: previous.profileName,
          setupSession: previous.setupSession,
        ),
      );
    } on Object catch (error, stackTrace) {
      final failed = AsyncError<OnboardingState>(error, stackTrace);
      // ignore: invalid_use_of_internal_member
      state = failed.copyWithPrevious(state);
    }
  }

  /// Loads the default-model picker inventory (only past the runtime gate).
  ///
  /// Caches the inventory on the current step without advancing: the step
  /// moves to `profile` only when [chooseModel] persists a choice. (An
  /// earlier revision derived `modelChosen: true` here, which flipped the
  /// visible step on load and made `chooseModel`'s own guard unreachable
  /// from any UI that had just loaded the inventory.)
  Future<ModelOptionsResult> loadModelOptions() async {
    final current = state.value;
    if (current == null ||
        (current.step != OnboardingStep.defaultModel &&
            current.step != OnboardingStep.profile &&
            current.step != OnboardingStep.ready)) {
      throw StateError(
        'model options are only available past the runtime gate',
      );
    }
    if (current.modelOptions != null) return current.modelOptions!;
    final connection = await ref.read(connectionProvider(instanceId).future);
    final profile = await _profileOf(ref, instanceId);
    final options = await connection.transport.call(
      HermesMethods.modelOptions,
      ModelOptionsParams(profile: profile),
    );
    state = AsyncData(current.copyWith(modelOptions: () => options));
    return options;
  }

  /// Persists the default model via REST `POST /api/model/set`.
  ///
  /// Throws [ExpensiveModelConfirmation] when the server wants the user's
  /// explicit agreement; call again with [confirmExpensiveModel] to proceed.
  Future<void> chooseModel({
    required String provider,
    required String model,
    String baseUrl = '',
    String apiKey = '',
    bool confirmExpensiveModel = false,
  }) async {
    final current = state.value;
    if (current == null) throw StateError('onboarding is still loading');
    if (current.step == OnboardingStep.runtimeCheck ||
        current.step == OnboardingStep.connections) {
      throw StateError('no default model to choose yet');
    }
    final rest = await ref.read(restClientProvider(instanceId).future);
    final response = await rest.postJson('/api/model/set', {
      'scope': 'main',
      'provider': provider,
      'model': model,
      if (baseUrl.isNotEmpty) 'base_url': baseUrl,
      if (apiKey.isNotEmpty) 'api_key': apiKey,
      if (confirmExpensiveModel) 'confirm_expensive_model': true,
    });
    if (response['confirm_required'] == true) {
      throw ExpensiveModelConfirmation(
        message:
            response['confirm_message'] as String? ??
            'This model may be expensive.',
      );
    }
    final options = await loadModelOptions();
    final latest = state.value ?? current;
    state = AsyncData(
      latest.copyWith(
        modelOptions: () => options,
        modelChosen: true,
        step: latest.step == OnboardingStep.defaultModel
            ? (latest.profileDone
                  ? OnboardingStep.ready
                  : OnboardingStep.profile)
            : latest.step,
      ),
    );
  }

  /// Explicit free-tier retry when the boot bootstrap could not mint an
  /// identity; returns whether one exists afterwards.
  Future<bool> provisionFreeTier() async {
    final connection = await ref.read(connectionProvider(instanceId).future);
    final profile = await _profileOf(ref, instanceId);
    final result = await connection.transport.call(
      HermesMethods.freeTierProvision,
      ProfileParams(profile: profile),
    );
    await refresh();
    return result.hasGuest;
  }

  /// Marks the one-time free-tier availability notice as shown.
  Future<bool> ackFreeTierNotice() async {
    final connection = await ref.read(connectionProvider(instanceId).future);
    final profile = await _profileOf(ref, instanceId);
    final result = await connection.transport.call(
      HermesMethods.freeTierAckNotice,
      ProfileParams(profile: profile),
    );
    final current = state.value;
    final info = current?.freeTier;
    if (current != null && info != null) {
      state = AsyncData(
        current.copyWith(
          freeTier: () => FreeTierInfo(
            enabled: info.enabled,
            available: info.available,
            noticePending: false,
            model: info.model,
            label: info.label,
            error: info.error,
            errorCode: info.errorCode,
            retryable: info.retryable,
            retryAfter: info.retryAfter,
          ),
        ),
      );
    }
    return result.acked;
  }

  /// Ensures the backend-owned setup profile and opens (or adopts) the guided
  /// presentation conversation in it, like the desktop kickoff: the existing
  /// `Welcome to Hermes` session is re-found by exact title so a relaunch never
  /// leaves an untitled duplicate behind.
  Future<ThreadRef> startProfileConversation() async {
    final current = state.value;
    if (current == null) throw StateError('onboarding is still loading');
    if (current.setupSession != null) return current.setupSession!;
    final connection = await ref.read(connectionProvider(instanceId).future);
    final setup = await connection.transport.call(
      HermesMethods.onboardingEnsureSetupProfile,
      const Params(),
    );
    // The guide runs on the setup profile's own socket: a provider that only
    // exists there must not be masked by the launch profile's fallback chain.
    final record = await connection.transport.call(
      HermesMethods.setupStatus,
      ProfileParams(profile: setup.name),
    );
    if (record.ready != true || (record.providerConfigured ?? false) != true) {
      throw StateError('the setup profile has no provider configured yet');
    }
    ThreadRef thread;
    final existing = await connection.transport.call(
      HermesMethods.sessionList,
      SessionListParams(
        profile: setup.name,
        title: setupChatTitle,
        includeHidden: true,
      ),
    );
    if (existing.sessions.isNotEmpty) {
      thread = ThreadRef(
        instanceId: instanceId,
        sessionId: existing.sessions.first.id,
      );
    } else {
      final created = await connection.transport.call(
        HermesMethods.sessionCreate,
        SessionCreateParams(
          profile: setup.name,
          title: setupChatTitle,
          reasoningEffort: record.freeTier == true ? 'minimal' : null,
          messages: const [
            SeedMessage(
              role: 'user',
              content: setupRunbookSeed,
              displayKind: 'hidden',
            ),
            SeedMessage(role: 'assistant', content: setupGreetingSeed),
          ],
        ),
      );
      thread = ThreadRef(
        instanceId: instanceId,
        sessionId: created.storedSessionId,
      );
      // The backend must not name the session after the hidden runbook row.
      await connection.transport
          .call(
            HermesMethods.sessionTitle,
            SessionTitleParams(
              sessionId: created.sessionId,
              title: setupChatTitle,
            ),
          )
          .then((_) {}, onError: (_) {});
    }
    state = AsyncData(
      current.copyWith(
        step: OnboardingStep.ready,
        profileName: () => setup.name,
        setupSession: () => thread,
        profileDone: true,
      ),
    );
    return thread;
  }

  /// Re-opens a settled step of a ready instance ("Change default model",
  /// "Take the tour"): [OnboardingStep.defaultModel] or
  /// [OnboardingStep.profile]. The runtime gate must have passed.
  void revisit(OnboardingStep step) {
    final current = state.value;
    if (current == null) return;
    if (step != OnboardingStep.defaultModel && step != OnboardingStep.profile) {
      throw ArgumentError.value(step, 'step', 'only defaultModel or profile');
    }
    if (current.step == OnboardingStep.runtimeCheck ||
        current.step == OnboardingStep.connections) {
      throw StateError('finish ${current.step.name} first');
    }
    state = AsyncData(current.copyWith(step: step));
  }

  /// Skips the current step without satisfying it (advanced users only).
  void skip() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        modelChosen:
            current.modelChosen || current.step == OnboardingStep.defaultModel,
        profileDone:
            current.profileDone || current.step == OnboardingStep.profile,
        step: switch (current.step) {
          OnboardingStep.runtimeCheck => OnboardingStep.connections,
          OnboardingStep.connections => OnboardingStep.defaultModel,
          OnboardingStep.defaultModel => OnboardingStep.profile,
          OnboardingStep.profile => OnboardingStep.ready,
          OnboardingStep.ready => OnboardingStep.ready,
        },
      ),
    );
  }

  /// Re-probes and advances one satisfied step (used after an out-of-band fix).
  Future<void> next() async {
    await refresh();
  }

  OnboardingState _derive({
    required SetupStatusResult status,
    required SetupRuntimeCheckResult check,
    required FreeTierInfo? freeTier,
    bool modelChosen = false,
    ModelOptionsResult? modelOptions,
    bool profileDone = false,
    String? profileName,
    ThreadRef? setupSession,
  }) => OnboardingState(
    modelChosen: modelChosen,
    profileDone: profileDone,
    step: deriveOnboardingStep(
      status: status,
      runtimeCheck: check,
      modelChosen: modelChosen,
      profileDone: profileDone,
    ),
    providerConfigured: setupStatusReady(status),
    problems: check.ok
        ? const []
        : [
            RuntimeProblem(
              message:
                  check.error ??
                  'The configured model cannot be served right now.',
              fixHint: [
                if (check.provider != null) 'provider: ${check.provider}',
                if (check.model != null && check.model!.isNotEmpty)
                  'model: ${check.model}',
                if (check.source != null && check.source!.isNotEmpty)
                  'source: ${check.source}',
              ].join(' · '),
            ),
          ],
    freeTier: freeTier,
    modelOptions: modelOptions,
    profileName: profileName,
    setupSession: setupSession,
  );

  Future<FreeTierInfo?> _readFreeTier(
    HermesTransport transport,
    String? profile,
  ) async {
    try {
      final result = await transport.call(
        HermesMethods.freeTierStatus,
        ProfileParams(profile: profile),
      );
      return FreeTierInfo(
        enabled: result.enabled,
        available: result.available,
        noticePending: result.noticePending,
        model: result.model,
        label: result.label,
      );
    } on HermesRpcError {
      // Old servers predate the free tier; the shortcut simply stays hidden.
      return null;
    }
  }
}

/// Title of the guided presentation chat. Kickoff re-finds the chat by exact
/// title after a relaunch (same as the desktop gate), so this string is also a
/// lookup key — never change it.
const setupChatTitle = 'Welcome to Hermes';

/// Hidden runbook seed of the guided conversation: tells the setup-profile
/// agent to present this Hermes instance before anything else.
const setupRunbookSeed =
    'You are the onboarding guide of this Hermes instance. '
    'Present what this assistant can do, then ask one question at a time to '
    'learn who the user is and what they want to build.';

/// Pre-written first assistant row: the chat shows a greeting without spending
/// a model turn.
const setupGreetingSeed =
    'Welcome to Hermes — your own AI chief of staff. Tell me a little about '
    'yourself and what you would like to get done first.';

/// Authenticated REST client of one instance, borrowed from its live
/// [DashboardTransport]. Overridable for tests whose transport is a fake.
@riverpod
Future<HermesRestClient> restClient(Ref ref, String instanceId) async {
  final transport = (await ref.watch(connectionProvider(instanceId).future))
      .transport;
  if (transport is! DashboardTransport) {
    throw StateError(
      'restClientProvider($instanceId) needs a DashboardTransport; '
      'override it in tests',
    );
  }
  return transport.rest;
}

/// The desktop CLIProxyAPI sidecar, or null where there is none (web/mobile:
/// bridge cards stay hidden). The desktop app overrides this with a
/// [SupervisorBridgeHost] from `package:hermuse_host`.
@Riverpod(keepAlive: true)
BridgeHost? bridgeHost(Ref ref) => null;
