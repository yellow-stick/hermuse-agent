import 'dart:async';

import 'package:hermes_client/hermes_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'computer.dart';
import 'onboarding.dart';
import 'product.dart';

part 'remote_setup.g.dart';

/// What Hermuse needs on a Hermes it reaches over the network, in the order
/// the component checklist lists and installs it.
enum RemotePart {
  /// Hermes Agent itself, in a release the Hermuse plugin supports.
  hermes('Hermes Agent'),

  /// The Hermuse plugin: Feed, Ideas, Goals, Library and the computer's API.
  plugin('Hermuse plugin'),

  /// The plugin's four background jobs: the daily feed, the weekly ideas and
  /// goal check-ins, the nightly reflection.
  jobs('Background jobs'),

  /// Docker on the server: it runs the agent's computer.
  docker('Docker'),

  /// The agent's computer: its image on the server, and Hermes' browser
  /// tools pointed at it.
  computer("Agent's computer"),

  /// A model provider that answers, connected in the onboarding.
  model('Model provider');

  const RemotePart(this.title);

  final String title;
}

/// Where a [RemotePart] stands.
enum RemotePartStatus {
  /// Being looked at.
  checking,

  /// In place already.
  present,

  /// Installed (or, for the model, connected) from the checklist.
  installed,

  /// Missing or out of date: the part's action installs it.
  missing,

  /// Waits on the user: a command to run on the server, a consent, a model
  /// to connect.
  needsUser,

  /// Waits on another part; its action, if any, stays disabled.
  blocked,

  /// Being installed.
  installing,

  /// The last attempt failed: the part's action tries again.
  failed;

  /// Whether the part is behind the user.
  bool get settled => this == present || this == installed;
}

/// What the button of a part does ([RemoteSetup.run]); [label] is its text.
enum RemoteAction {
  install('Install'),
  update('Update'),
  turnOn('Turn on'),

  /// Installs the plugin once the user allowed what Hermes' scan flagged.
  allowInstall('Allow and install'),
  retry('Try again'),
  checkAgain('Check again'),

  /// Opens the onboarding at its model step: the app routes it.
  setUpModel('Set up a model');

  const RemoteAction(this.label);

  final String label;
}

/// One row of the component checklist.
final class RemotePartState {
  const RemotePartState(
    this.part,
    this.status, {
    this.summary = '',
    this.notes = const [],
    this.alert = false,
    this.report,
    this.action,
    this.enabled = true,
    this.command,
  });

  final RemotePart part;
  final RemotePartStatus status;

  /// One line under the part's title.
  final String summary;

  /// What to know before acting, or why it failed.
  final List<String> notes;

  /// Whether [notes] report a problem.
  final bool alert;

  /// Hermes' own technical words behind [notes] (the scan report of a
  /// plugin it flags), shown apart from them in a box that scrolls.
  final String? report;

  final RemoteAction? action;

  /// Whether [action] can run now; [summary] says what it waits for.
  final bool enabled;

  /// A command to run on the server, offered to copy.
  final String? command;

  RemotePartState _disabled() => RemotePartState(
    part,
    status,
    summary: summary,
    notes: notes,
    alert: alert,
    report: report,
    action: action,
    enabled: false,
    command: command,
  );
}

/// Where the whole checklist stands.
enum RemoteSetupPhase {
  /// A look is under way.
  checking,

  /// The Hermes did not answer ([RemoteSetupState.unreachable] says why).
  unreachable,

  installing,

  /// An install failed.
  failed,

  /// Parts are missing and can be installed.
  needsInstall,

  /// What is left needs the user.
  needsUser,

  /// Everything is in place.
  ready,
}

/// The component checklist of one Hermes.
final class RemoteSetupState {
  const RemoteSetupState({
    required this.parts,
    this.busy = false,
    this.unreachable,
  });

  /// One per [RemotePart], in its order.
  final List<RemotePartState> parts;

  /// An install runs: every other action waits.
  final bool busy;

  /// Why the Hermes could not be reached, when it could not.
  final String? unreachable;

  RemotePartState operator [](RemotePart part) => parts[part.index];

  /// Parts behind the user.
  int get settled => parts.where((p) => p.status.settled).length;

  /// Parts "Install everything" installs now, in order.
  List<RemotePart> get installable => [
    for (final p in parts)
      if (p.status == RemotePartStatus.missing && p.enabled) p.part,
  ];

  RemoteSetupPhase get phase {
    bool any(RemotePartStatus status) => parts.any((p) => p.status == status);
    if (unreachable != null) return RemoteSetupPhase.unreachable;
    if (any(RemotePartStatus.installing)) return RemoteSetupPhase.installing;
    if (any(RemotePartStatus.checking)) return RemoteSetupPhase.checking;
    if (any(RemotePartStatus.failed)) return RemoteSetupPhase.failed;
    if (parts.every((p) => p.status.settled)) return RemoteSetupPhase.ready;
    if (any(RemotePartStatus.missing)) return RemoteSetupPhase.needsInstall;
    return RemoteSetupPhase.needsUser;
  }

  /// What happens now, in one line.
  String get headline => switch (phase) {
    RemoteSetupPhase.checking => 'Checking what this Hermes has…',
    RemoteSetupPhase.unreachable => 'Could not reach this Hermes.',
    RemoteSetupPhase.installing => () {
      final row = parts.firstWhere(
        (p) => p.status == RemotePartStatus.installing,
      );
      return '${row.part.title}: ${row.summary}';
    }(),
    RemoteSetupPhase.failed => 'An install stopped on a failure.',
    RemoteSetupPhase.needsInstall => switch (installable.length) {
      1 => 'One part to install.',
      final n when n > 1 => '$n parts to install.',
      _ => 'Parts are missing.',
    },
    RemoteSetupPhase.needsUser => 'What is left needs you.',
    RemoteSetupPhase.ready => 'Everything Hermuse needs is in place.',
  };
}

/// Timing of [RemoteSetup]; tests shorten it.
final class RemoteSetupTiming {
  const RemoteSetupTiming({
    this.poll = const Duration(seconds: 2),
    this.mountTimeout = const Duration(seconds: 10),
    this.mountPoll = const Duration(milliseconds: 500),
  });

  /// Between two looks at a computer being prepared.
  final Duration poll;

  /// How long the plugin routes may take to mount after an install, and
  /// between two probes of them.
  final Duration mountTimeout;
  final Duration mountPoll;
}

@riverpod
RemoteSetupTiming remoteSetupTiming(Ref ref) => const RemoteSetupTiming();

/// The component checklist of the Hermes [instanceId] reaches over the
/// network: each part Hermuse needs there, found in place, or installed
/// through the Hermes dashboard and the Hermuse plugin (never a shell on the
/// server). What only the user can do (a command on the server, a consent,
/// a model to connect) says so, with the command to copy.
///
/// It looks as soon as it is read, after each install and on [checkAgain];
/// a computer being prepared is looked at every [RemoteSetupTiming.poll]
/// until it is ready or failed. Parts that need another one (the jobs, Docker
/// and the computer need the plugin; the computer needs Docker) wait for it.
/// One install runs at a time.
@riverpod
class RemoteSetup extends _$RemoteSetup {
  /// What the last look found; null before the first one answered.
  _Found? _found;
  AsyncValue<OnboardingState> _model = const AsyncLoading();
  String? _unreachable;

  /// Parts shown as being looked at.
  var _checking = <RemotePart>{};

  /// The part whose install runs, and what it does now.
  RemotePart? _running;
  var _work = '';

  /// "Install everything" runs.
  var _everything = false;

  /// Parts installed from here, and the model when it got connected while
  /// the checklist showed: they show done rather than found.
  final _installed = <RemotePart>{};

  /// Why the last attempt of each part failed.
  final _failures = <RemotePart, List<String>>{};

  /// Hermes' scan report while the plugin install waits for the consent.
  String? _consent;

  /// What a retry of the plugin does: its last attempt.
  var _pluginRetry = RemoteAction.install;

  /// The dashboard must restart to serve the plugin, or its update.
  _Restart? _restart;

  /// Hermuse asked the server to install Docker.
  var _dockerTried = false;

  var _built = false;
  Future<void>? _looking;
  var _lookAgain = false;
  var _following = false;

  @override
  RemoteSetupState build(String instanceId) {
    _built = false;
    _found = null;
    _unreachable = null;
    _checking = {...RemotePart.values}..remove(RemotePart.model);
    ref.listen(onboardingProvider(instanceId), (_, next) {
      final connected = next.value;
      if (_modelMissing(_model.value) &&
          connected != null &&
          !_modelMissing(connected)) {
        _installed.add(RemotePart.model);
      }
      _model = next;
      if (_built) _publish();
    }, fireImmediately: true);
    Future.microtask(_look);
    _built = true;
    return _derive();
  }

  /// Runs the action of [part]; [RemoteAction.setUpModel] is the app's.
  /// Nothing happens while another install runs.
  Future<void> run(RemotePart part) async {
    if (_running != null || _everything) return;
    await _act(part);
  }

  /// Installs every missing part in order, stopping at the first that
  /// needs the user or fails.
  Future<void> installEverything() async {
    if (_running != null || _everything) return;
    _everything = true;
    _publish();
    try {
      for (final part in RemotePart.values) {
        if (!ref.mounted) return;
        if (_row(part).status != RemotePartStatus.missing) continue;
        await _act(part);
        if (!ref.mounted) return;
        final after = _row(part).status;
        if (after == RemotePartStatus.failed ||
            after == RemotePartStatus.needsUser) {
          return;
        }
      }
    } finally {
      _everything = false;
      _publish();
    }
  }

  Future<void> _act(RemotePart part) async {
    final row = _row(part);
    final action = row.action;
    if (action == null || !row.enabled) return;
    switch ((part, action)) {
      case (_, RemoteAction.checkAgain):
        return checkAgain();
      case (_, RemoteAction.setUpModel) || (RemotePart.hermes, _):
        return;
      case (RemotePart.plugin, RemoteAction.update):
        return _updatePlugin();
      case (RemotePart.plugin, RemoteAction.retry):
        return _pluginRetry == RemoteAction.update
            ? _updatePlugin()
            : _installPlugin(force: _pluginRetry == RemoteAction.allowInstall);
      case (RemotePart.plugin, _):
        return _installPlugin(force: action == RemoteAction.allowInstall);
      case (RemotePart.jobs, _):
        return _scheduleJobs();
      case (RemotePart.docker || RemotePart.computer, _):
        return _setUpComputer(part);
      case (RemotePart.model, _):
        ref.invalidate(onboardingProvider(instanceId));
    }
  }

  /// Looks at every part again: what the user did on the server (a command,
  /// a dashboard restart) shows up. Failures and prompts are dropped for
  /// what the Hermes says now.
  Future<void> checkAgain() {
    _failures.clear();
    _consent = null;
    _dockerTried = false;
    _restart = null;
    _checking = {
      for (final row in state.parts)
        if (!row.status.settled && row.part != RemotePart.model) row.part,
    };
    final model = ref.read(onboardingProvider(instanceId));
    if (model.hasError && !model.hasValue) {
      ref.invalidate(onboardingProvider(instanceId));
    } else if (!model.isLoading) {
      unawaited(ref.read(onboardingProvider(instanceId).notifier).refresh());
    }
    _publish();
    return _look();
  }

  Future<HermesRestClient> _rest() =>
      ref.read(restClientProvider(instanceId).future);

  RemoteSetupTiming get _timing => ref.read(remoteSetupTimingProvider);

  void _publish() {
    if (ref.mounted) state = _derive();
  }

  // --- installs -------------------------------------------------------------

  Future<void> _installPlugin({required bool force}) {
    _pluginRetry = force ? RemoteAction.allowInstall : RemoteAction.install;
    return _attempt(RemotePart.plugin, 'Installing…', (rest) async {
      final timing = _timing;
      _plugin(
        await mountHermusePlugin(
          rest,
          force: force,
          mountTimeout: timing.mountTimeout,
          pollInterval: timing.mountPoll,
        ),
        restart: _Restart.mount,
      );
    });
  }

  Future<void> _updatePlugin() {
    _pluginRetry = RemoteAction.update;
    return _attempt(
      RemotePart.plugin,
      'Updating…',
      (rest) async =>
          _plugin(await updateHermusePlugin(rest), restart: _Restart.update),
    );
  }

  void _plugin(PluginInstallResult result, {required _Restart restart}) {
    switch (result) {
      case PluginInstalled():
        ref.invalidate(pluginStatusProvider(instanceId));
      case PluginNeedsConsent(:final detail):
        _consent = detail;
      case PluginNeedsDashboardRestart():
        _restart = restart;
      case PluginInstallFailed(:final message, :final findings):
        _failures[RemotePart.plugin] = [
          message,
          for (final f in findings) '$f',
        ];
    }
  }

  Future<void> _scheduleJobs() =>
      _attempt(RemotePart.jobs, 'Scheduling them…', (rest) async {
        await rest.postJson('$hermusePluginRoute/cron/enable', const {});
      });

  /// `POST /computer/setup`: points Hermes' browser tools at the computer,
  /// then prepares what it misses in the background — Docker when the server
  /// allows `sudo` without a password, then its image.
  Future<void> _setUpComputer(RemotePart part) {
    if (part == RemotePart.docker) _dockerTried = true;
    // What it prepares on the way counts as installed from here too.
    final touched = {
      for (final other in const [RemotePart.docker, RemotePart.computer])
        if (!_row(other).status.settled) other,
    };
    _installed.addAll(touched);
    return _attempt(part, 'Setting it up…', touched: touched, (rest) async {
      final status = await ComputerClient(rest).setup();
      _found = _found?._withComputer(status);
    });
  }

  /// Runs [body] as the install of [part], then looks at everything again.
  /// Until Hermes answers, [part] and the other parts the install [touched]
  /// show being looked at, not as they were before it.
  Future<void> _attempt(
    RemotePart part,
    String work,
    Future<void> Function(HermesRestClient rest) body, {
    Set<RemotePart> touched = const {},
  }) async {
    _running = part;
    _work = work;
    _installed.add(part);
    _failures.remove(part);
    _consent = null;
    _publish();
    try {
      await body(await _rest());
    } on HermesException catch (e) {
      _failures[part] = [hermesReason(e)];
    } on Object catch (e) {
      _failures[part] = ['$e'];
    }
    _running = null;
    if (!ref.mounted) return;
    // A failure or Hermes' prompt is known already; anything else, not yet.
    if (!_failures.containsKey(part) && _consent == null) {
      _checking = {..._checking, part, ...touched};
    }
    _publish();
    await _look();
  }

  // --- looking --------------------------------------------------------------

  /// One look at a time; asked again meanwhile, it looks once more after.
  Future<void> _look() {
    if (_looking case final running?) {
      _lookAgain = true;
      return running;
    }
    return _looking = () async {
      try {
        do {
          _lookAgain = false;
          await _lookOnce();
        } while (_lookAgain && ref.mounted);
      } finally {
        _looking = null;
      }
    }();
  }

  Future<void> _lookOnce() async {
    try {
      final rest = await _rest();
      final version = (await rest.getStatus()).version;
      final hub = await _hub(rest);
      final mounted = await _routesAnswer(rest);
      _Jobs? jobs;
      String? jobsError;
      ComputerStatus? computer;
      String? computerError;
      bool? pointed;
      if (mounted) {
        (jobs, jobsError) = await _jobs(rest);
        (computer, computerError) = await _computer(rest);
        pointed = await _browserPointed(rest);
      }
      _found = _Found(
        version: version,
        plugin: hub,
        mounted: mounted,
        jobs: jobs,
        jobsError: jobsError,
        computer: computer,
        computerError: computerError,
        browserPointed: pointed,
      );
      _unreachable = null;
      if (mounted && _restart == _Restart.mount) _restart = null;
    } on HermesException catch (e) {
      _unreachable = hermesReason(e);
    } on Object catch (e) {
      _unreachable = '$e';
    }
    // Asked to look again meanwhile: this look may predate what changed.
    if (!_lookAgain) _checking = {};
    if (!ref.mounted) return;
    _publish();
    if (_found?.computer?.state == ComputerState.building) unawaited(_follow());
  }

  /// Follows a computer being prepared until it is ready or failed, then
  /// looks at everything again (the setup changed Hermes' config).
  Future<void> _follow() async {
    if (_following) return;
    _following = true;
    try {
      while (_found?.computer?.state == ComputerState.building) {
        await Future<void>.delayed(_timing.poll);
        if (!ref.mounted) return;
        final status = await ComputerClient(await _rest()).status();
        if (!ref.mounted) return;
        _found = _found?._withComputer(status);
        _publish();
      }
    } on HermesException {
      // The next look says what went wrong.
    } finally {
      _following = false;
    }
    if (ref.mounted) await _look();
  }

  /// Hermes' record of the plugin (`GET /api/dashboard/plugins/hub`): null
  /// when Hermes does not know it or the hub does not answer.
  static Future<_HubPlugin?> _hub(HermesRestClient rest) async {
    try {
      final body = await rest.getJson('/api/dashboard/plugins/hub');
      for (final plugin in body['plugins'] as List? ?? const []) {
        if (plugin is Map && plugin['name'] == 'hermuse') {
          return _HubPlugin(
            version: '${plugin['version'] ?? ''}',
            enabled: plugin['runtime_status'] == 'enabled',
          );
        }
      }
    } on HermesHttpError {
      // Older dashboards: the routes alone say whether the plugin runs.
    }
    return null;
  }

  /// `GET /files`: the plugin routes answer, or 404.
  static Future<bool> _routesAnswer(HermesRestClient rest) async {
    try {
      await rest.getJson('$hermusePluginRoute/files');
      return true;
    } on HermesHttpError catch (e) {
      if (e.statusCode == 404) return false;
      rethrow;
    }
  }

  static Future<(_Jobs?, String?)> _jobs(HermesRestClient rest) async {
    try {
      final body = await rest.getJson('$hermusePluginRoute/cron');
      final jobs = [
        for (final job in body['jobs'] as List? ?? const [])
          if (job is Map) job,
      ];
      return (
        _Jobs(
          total: jobs.length,
          registered: jobs.where((j) => j['registered'] == true).length,
          paused: jobs
              .where((j) => j['registered'] == true && j['enabled'] == false)
              .length,
        ),
        null,
      );
    } on HermesException catch (e) {
      return (null, hermesReason(e));
    }
  }

  static Future<(ComputerStatus?, String?)> _computer(
    HermesRestClient rest,
  ) async {
    try {
      return (await ComputerClient(rest).status(), null);
    } on HermesException catch (e) {
      return (null, hermesReason(e));
    }
  }

  /// Whether Hermes' browser tools drive the computer
  /// (`browser.cloud_provider: hermuse`, set by the computer setup); null
  /// when the config does not answer.
  static Future<bool?> _browserPointed(HermesRestClient rest) async {
    try {
      final config = await rest.getJson('/api/config');
      final browser = config['browser'];
      return browser is Map && browser['cloud_provider'] == 'hermuse';
    } on HermesException {
      return null;
    }
  }

  // --- rows -----------------------------------------------------------------

  RemoteSetupState _derive() {
    final busy = _running != null || _everything;
    RemotePartState shown(RemotePart part) {
      final row = _row(part);
      // One install at a time: the other buttons wait for it.
      return busy && row.action != null && row.enabled && part != _running
          ? row._disabled()
          : row;
    }

    return RemoteSetupState(
      parts: [for (final part in RemotePart.values) shown(part)],
      busy: busy,
      unreachable: _unreachable,
    );
  }

  /// The row of [part] from what the checklist knows now.
  RemotePartState _row(RemotePart part) {
    if (part == RemotePart.model) return _modelRow();
    if (_checking.contains(part)) {
      return RemotePartState(
        part,
        RemotePartStatus.checking,
        summary: 'Checking…',
      );
    }
    final found = _found;
    if (found == null) {
      return RemotePartState(
        part,
        RemotePartStatus.blocked,
        summary: 'Waiting for the Hermes to answer',
      );
    }
    return switch (part) {
      RemotePart.hermes => _hermesRow(found),
      RemotePart.plugin => _pluginRow(found),
      RemotePart.jobs => _jobsRow(found),
      RemotePart.docker => _dockerRow(found),
      RemotePart.computer => _computerRow(found),
      RemotePart.model => _modelRow(),
    };
  }

  /// [part] is in place, with [detail] (its version, what runs): done when
  /// installed from here, found otherwise.
  RemotePartState _inPlace(RemotePart part, [String? detail]) {
    final installed = _installed.contains(part);
    final verdict = installed ? 'Installed now' : 'Already installed';
    return RemotePartState(
      part,
      installed ? RemotePartStatus.installed : RemotePartStatus.present,
      summary: detail == null ? verdict : '$verdict · $detail',
    );
  }

  RemotePartState? _runningOrFailed(RemotePart part) {
    if (_running == part) {
      return RemotePartState(part, RemotePartStatus.installing, summary: _work);
    }
    if (_failures[part] case final notes?) {
      return RemotePartState(
        part,
        RemotePartStatus.failed,
        summary: 'The last attempt failed',
        notes: notes,
        alert: true,
        action: RemoteAction.retry,
      );
    }
    return null;
  }

  RemotePartState _hermesRow(_Found found) {
    const part = RemotePart.hermes;
    final version = hermesVersionOf(found.version) ?? found.version;
    if (hermesVersionSupported(found.version)) {
      return _inPlace(part, 'Version $version');
    }
    return RemotePartState(
      part,
      RemotePartStatus.needsUser,
      summary: 'Version $version: Hermuse needs 0.21.5 or a later 0.21',
      notes: const [
        'Update Hermes Agent on the server to a 0.21 release from 0.21.5, '
            'then check again.',
      ],
      action: RemoteAction.checkAgain,
    );
  }

  RemotePartState _pluginRow(_Found found) {
    const part = RemotePart.plugin;
    if (_runningOrFailed(part) case final row?) return row;
    if (_consent case final report?) {
      return RemotePartState(
        part,
        RemotePartStatus.needsUser,
        summary: 'Hermes asks you to allow it',
        notes: const [
          'Hermuse needs permission to install Docker with sudo on this '
              'server (Hermes flags this for review).',
        ],
        report: report,
        action: RemoteAction.allowInstall,
      );
    }
    final plugin = found.plugin;
    if (_restart case final restart?) {
      return _restartRow(updated: restart == _Restart.update);
    }
    if (found.mounted) {
      final version = plugin?.version ?? '';
      if (_older(version)) {
        return RemotePartState(
          part,
          RemotePartStatus.missing,
          summary: 'Version $version: $hermusePluginVersion is out',
          action: RemoteAction.update,
        );
      }
      return _inPlace(part, version.isEmpty ? null : 'Version $version');
    }
    if (!hermesVersionSupported(found.version)) {
      return const RemotePartState(
        part,
        RemotePartStatus.blocked,
        summary: 'Needs a supported Hermes Agent',
        action: RemoteAction.install,
        enabled: false,
      );
    }
    if (plugin == null) {
      return const RemotePartState(
        part,
        RemotePartStatus.missing,
        summary: 'Not installed',
        notes: [
          "Feed, Ideas, Goals, Library and the agent's computer run in this "
              'plugin, on your Hermes.',
        ],
        action: RemoteAction.install,
      );
    }
    if (!plugin.enabled) {
      return const RemotePartState(
        part,
        RemotePartStatus.missing,
        summary: 'Installed but turned off',
        action: RemoteAction.turnOn,
      );
    }
    // Turned on, yet the dashboard does not serve it: it started before.
    return _restartRow(updated: false);
  }

  static RemotePartState _restartRow({required bool updated}) =>
      RemotePartState(
        RemotePart.plugin,
        RemotePartStatus.needsUser,
        summary: updated
            ? 'Updated: the Hermes dashboard must restart to run it'
            : 'The Hermes dashboard must restart to serve it',
        notes: const [
          'Under systemd run the command below; otherwise stop `hermes '
              'dashboard` and start it again. Then check again.',
        ],
        command: 'systemctl --user restart hermes-dashboard',
        action: RemoteAction.checkAgain,
      );

  RemotePartState _jobsRow(_Found found) {
    const part = RemotePart.jobs;
    if (_running == part) return _runningOrFailed(part)!;
    if (!found.mounted) return _needsPlugin(part);
    if (_runningOrFailed(part) case final row?) return row;
    final jobs = found.jobs;
    if (jobs == null) return _unread(part, found.jobsError);
    if (jobs.registered < jobs.total || jobs.total == 0) {
      return RemotePartState(
        part,
        RemotePartStatus.missing,
        summary: jobs.registered == 0
            ? 'Not scheduled'
            : '${jobs.registered} of ${jobs.total} scheduled',
        notes: const [
          'A daily feed, weekly ideas and goal check-ins, a nightly '
              'reflection: they run on the server.',
        ],
        action: RemoteAction.install,
      );
    }
    return _inPlace(
      part,
      '${jobs.total} scheduled'
      '${jobs.paused == 0 ? '' : ', ${jobs.paused} paused'}',
    );
  }

  RemotePartState _dockerRow(_Found found) {
    const part = RemotePart.docker;
    if (_running == part) return _runningOrFailed(part)!;
    if (!found.mounted) {
      return const RemotePartState(
        part,
        RemotePartStatus.blocked,
        summary: 'Checked once the Hermuse plugin runs',
      );
    }
    if (_runningOrFailed(part) case final row?) return row;
    final computer = found.computer;
    if (computer == null) return _unread(part, found.computerError);
    switch (computer.state) {
      case ComputerState.building when _installsDocker(computer):
        return RemotePartState(
          part,
          RemotePartStatus.installing,
          summary: computer.detail,
        );
      case ComputerState.dockerMissing:
        // Linux servers get the command; elsewhere the detail says how.
        final command =
            computer.hint.isEmpty && computer.detail.contains('sudo')
            ? computer.detail
            : null;
        if (_dockerTried || command == null) {
          return RemotePartState(
            part,
            RemotePartStatus.needsUser,
            summary: 'Hermuse cannot install it on this server',
            notes: [
              if (command == null)
                computer.detail
              else
                'Installing it takes sudo without a password there. Run '
                    'this on the server, then check again:',
            ],
            command: command,
            action: RemoteAction.checkAgain,
          );
        }
        return const RemotePartState(
          part,
          RemotePartStatus.missing,
          summary: 'Not installed',
          notes: [
            'Hermuse installs it when the server allows sudo without a '
                'password; otherwise it gives you the command to run.',
          ],
          action: RemoteAction.install,
        );
      case ComputerState.daemonDown:
        final denied = computer.detail.toLowerCase().contains(
          'permission denied',
        );
        return RemotePartState(
          part,
          RemotePartStatus.needsUser,
          summary: denied
              ? 'Hermes may not use it'
              : 'Installed but not running',
          notes: [
            if (computer.detail.isNotEmpty) computer.detail,
            denied
                ? 'Add the user that runs Hermes to the docker group: as '
                      'that user, run this on the server, then check again:'
                : 'Start it on the server, then check again:',
          ],
          command: denied
              ? r'sudo usermod -aG docker "$USER"'
              : 'sudo systemctl start docker',
          action: RemoteAction.checkAgain,
        );
      case ComputerState.missing:
        return _needsPlugin(part);
      case ComputerState.imageMissing ||
          ComputerState.building ||
          ComputerState.stopped ||
          ComputerState.running ||
          ComputerState.error:
        return _inPlace(part, 'Running');
    }
  }

  RemotePartState _computerRow(_Found found) {
    const part = RemotePart.computer;
    if (_running == part) return _runningOrFailed(part)!;
    if (!found.mounted) return _needsPlugin(part);
    if (_runningOrFailed(part) case final row?) return row;
    final computer = found.computer;
    if (computer == null) return _unread(part, found.computerError);
    switch (computer.state) {
      case ComputerState.dockerMissing || ComputerState.daemonDown:
        return const RemotePartState(
          part,
          RemotePartStatus.blocked,
          summary: 'Needs Docker',
          action: RemoteAction.install,
          enabled: false,
        );
      case ComputerState.building when _installsDocker(computer):
        return const RemotePartState(
          part,
          RemotePartStatus.blocked,
          summary: 'Waits for Docker',
          action: RemoteAction.install,
          enabled: false,
        );
      case ComputerState.building:
        return RemotePartState(
          part,
          RemotePartStatus.installing,
          summary: computer.detail.isEmpty ? 'Preparing it…' : computer.detail,
        );
      case ComputerState.imageMissing:
        return const RemotePartState(
          part,
          RemotePartStatus.missing,
          summary: 'Not prepared yet',
          notes: [
            'Hermuse downloads its image (about 1 GB) to the server, or '
                'builds it there.',
          ],
          action: RemoteAction.install,
        );
      case ComputerState.error:
        return RemotePartState(
          part,
          RemotePartStatus.failed,
          summary: 'Its preparation failed',
          notes: [if (computer.detail.isNotEmpty) computer.detail],
          alert: true,
          action: RemoteAction.retry,
        );
      case ComputerState.missing:
        return _needsPlugin(part);
      case ComputerState.stopped || ComputerState.running:
        if (found.browserPointed == false) {
          return const RemotePartState(
            part,
            RemotePartStatus.missing,
            summary: "Ready, but Hermes' browser does not use it yet",
            action: RemoteAction.install,
          );
        }
        return _inPlace(
          part,
          computer.state == ComputerState.running ? 'Running' : 'Ready',
        );
    }
  }

  RemotePartState _modelRow() {
    const part = RemotePart.model;
    final model = _model;
    if (model.isLoading) {
      return const RemotePartState(
        part,
        RemotePartStatus.checking,
        summary: 'Checking…',
      );
    }
    final onboarding = model.value;
    if (onboarding == null) {
      return RemotePartState(
        part,
        RemotePartStatus.failed,
        summary: 'Could not check it',
        notes: [
          switch (model.error) {
            final HermesException e => hermesReason(e),
            final e => '$e',
          },
        ],
        alert: true,
        action: RemoteAction.retry,
      );
    }
    return switch (onboarding.step) {
      OnboardingStep.connections => const RemotePartState(
        part,
        RemotePartStatus.needsUser,
        summary: 'No model provider connected',
        notes: [
          'Hermes needs a model to think with: a subscription, an API key '
              'or a model of your own.',
        ],
        action: RemoteAction.setUpModel,
      ),
      OnboardingStep.runtimeCheck => RemotePartState(
        part,
        RemotePartStatus.needsUser,
        summary: 'The model provider does not answer',
        notes: [for (final problem in onboarding.problems) problem.message],
        alert: true,
        action: RemoteAction.setUpModel,
      ),
      _ =>
        _installed.contains(part)
            ? const RemotePartState(
                part,
                RemotePartStatus.installed,
                summary: 'Connected now',
              )
            : const RemotePartState(
                part,
                RemotePartStatus.present,
                summary: 'Already connected',
              ),
    };
  }

  /// Whether [onboarding] still waits for a model provider that answers.
  static bool _modelMissing(OnboardingState? onboarding) =>
      onboarding?.step == OnboardingStep.connections ||
      onboarding?.step == OnboardingStep.runtimeCheck;

  static RemotePartState _needsPlugin(RemotePart part) => RemotePartState(
    part,
    RemotePartStatus.blocked,
    summary: 'Needs the Hermuse plugin',
    action: RemoteAction.install,
    enabled: false,
  );

  static RemotePartState _unread(RemotePart part, String? error) =>
      RemotePartState(
        part,
        RemotePartStatus.failed,
        summary: 'Could not check it',
        notes: [?error],
        alert: true,
        action: RemoteAction.checkAgain,
      );

  /// The bootstrap installs Docker (its first step), per its status detail.
  static bool _installsDocker(ComputerStatus status) =>
      status.detail.startsWith('Installing Docker');

  /// Whether plugin [version] is older than [hermusePluginVersion]; false
  /// when either is not `X.Y.Z`.
  static bool _older(String version) {
    List<int>? parse(String text) {
      final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
      return match == null
          ? null
          : [for (var i = 1; i <= 3; i++) int.parse(match[i]!)];
    }

    final installed = parse(version);
    final bundled = parse(hermusePluginVersion);
    if (installed == null || bundled == null) return false;
    for (var i = 0; i < 3; i++) {
      if (installed[i] != bundled[i]) return installed[i] < bundled[i];
    }
    return false;
  }
}

/// Why the Hermes dashboard must restart before the plugin works.
enum _Restart {
  /// Its routes did not mount after it was installed or turned on.
  mount,

  /// It was updated: the dashboard still runs the version it loaded.
  update,
}

/// Hermes' record of the installed plugin.
final class _HubPlugin {
  const _HubPlugin({required this.version, required this.enabled});

  final String version;
  final bool enabled;
}

/// The plugin's jobs: how many exist, are registered, and are paused.
final class _Jobs {
  const _Jobs({
    required this.total,
    required this.registered,
    required this.paused,
  });

  final int total;
  final int registered;
  final int paused;
}

/// What the last look found.
final class _Found {
  const _Found({
    required this.version,
    required this.plugin,
    required this.mounted,
    this.jobs,
    this.jobsError,
    this.computer,
    this.computerError,
    this.browserPointed,
  });

  /// Hermes' own version (`/api/status`).
  final String version;
  final _HubPlugin? plugin;

  /// The plugin routes answer.
  final bool mounted;
  final _Jobs? jobs;
  final String? jobsError;
  final ComputerStatus? computer;
  final String? computerError;
  final bool? browserPointed;

  _Found _withComputer(ComputerStatus status) => _Found(
    version: version,
    plugin: plugin,
    mounted: mounted,
    jobs: jobs,
    jobsError: jobsError,
    computer: status,
    browserPointed: browserPointed,
  );
}
