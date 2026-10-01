import 'dart:async';

import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

import '../platform/plugin_bundle.dart';
import '../shell/screens.dart';
import 'setup_view.dart';

/// Desktop-only SSH setup and removal. Credentials live only in this attempt;
/// a verified dashboard account is handed to the regular secure sign-in flow.
final class RemoteInstallScreen extends StatefulWidget {
  const RemoteInstallScreen({
    required this.onDone,
    required this.onCancel,
    this.installer,
    this.uninstaller,
    this.remove = false,
    this.initialHost,
    this.bundle,
    super.key,
  });

  final ValueChanged<RemoteInstallOutcome> onDone;
  final VoidCallback onCancel;
  final RemoteInstaller? installer;
  final RemoteUninstaller? uninstaller;
  final bool remove;
  final String? initialHost;
  final AssetBundle? bundle;

  @override
  State<RemoteInstallScreen> createState() => _RemoteInstallScreenState();
}

enum _Phase {
  form,
  consent,
  loading,
  hostKey,
  installing,
  failed,
  removalReview,
  removalFinished,
}

final class _RemoteInstallScreenState extends State<RemoteInstallScreen> {
  late final _host = TextEditingController(text: widget.initialHost);
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController(text: 'root');
  final _password = TextEditingController();
  late final _installer = widget.installer ?? RemoteInstaller();
  late final _uninstaller = widget.uninstaller ?? RemoteUninstaller();
  late bool _removing = widget.remove;
  StreamSubscription<RemoteUninstallProgress>? _uninstallSubscription;
  RemoteUninstallInventory? _inventory;
  RemoteUninstallOutcome? _removalOutcome;
  RemoteUninstallStep? _removalRunning;
  final _removalFinished = <RemoteUninstallStep>{};
  String? _inspectionPassword;
  var _inspecting = false;
  var _purging = false;
  StreamSubscription<RemoteInstallProgress>? _subscription;
  Future<void>? _stopping;
  Completer<bool>? _hostKeyDecision;
  RemoteHostKey? _hostKey;
  _Phase _phase = _Phase.form;
  RemoteInstallStep? _running;
  final _finished = <RemoteInstallStep>{};
  final _previouslyCompleted = <RemoteInstallStep>{};
  final _log = <String>[];
  String? _error;
  var _attempt = 0;
  var _completed = false;
  var _retrying = false;
  var _checkingExisting = false;

  bool _current(int attempt) => mounted && attempt == _attempt && !_completed;

  /// Invalidate callbacks before closing the stream or resolving its prompt.
  void _stop() {
    _attempt++;
    final decision = _hostKeyDecision;
    _hostKeyDecision = null;
    if (decision != null && !decision.isCompleted) decision.complete(false);
    _inspectionPassword = null;
    _inventory = null;
    _stopping = _removing ? _uninstaller.cancel() : _installer.cancel();
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final uninstallSubscription = _uninstallSubscription;
    _uninstallSubscription = null;
    if (uninstallSubscription != null) {
      unawaited(uninstallSubscription.cancel());
    }
  }

  @override
  void dispose() {
    _stop();
    _password.clear();
    _password.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    super.dispose();
  }

  void _cancel() {
    _stop();
    _password.clear();
    setState(() => _phase = _Phase.form);
    widget.onCancel();
  }

  void _review() {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    final error = host.isEmpty
        ? 'Enter a host name or IP address.'
        : RegExp(r'[\s/@?#]').hasMatch(host)
        ? 'Enter only a host name or IP address, not a dashboard URL.'
        : port == null || port < 1 || port > 65535
        ? 'Enter an SSH port between 1 and 65535.'
        : _username.text.trim().isEmpty
        ? 'Enter the SSH user name.'
        : null;
    setState(() {
      _error = error;
      if (error == null) _phase = _Phase.consent;
    });
  }

  Future<void> _start() async {
    if (_phase != _Phase.consent) return;
    final attempt = ++_attempt;
    final host = _host.text.trim();
    final port = int.parse(_port.text.trim());
    final username = _username.text.trim();
    final password = _password.text;
    _password.clear();
    setState(() {
      _phase = _removing ? _Phase.installing : _Phase.loading;
      _inspecting = _removing;
      _inventory = null;
      _removalOutcome = null;
      _removalRunning = null;
      _removalFinished.clear();
      _error = null;
      _running = null;
      _finished.clear();
      _previouslyCompleted.clear();
      _checkingExisting = false;
      _log.clear();
    });
    try {
      await _stopping;
      if (!_current(attempt)) return;
      if (_removing) {
        _inspectionPassword = password;
        final inventory = await _uninstaller.inspect(
          host: host,
          port: port,
          username: username,
          password: password,
          onHostKey: (key) => _verifyHostKey(key, attempt),
        );
        if (!_current(attempt)) return;
        setState(() {
          _inventory = inventory;
          _inspecting = false;
          _phase = _Phase.removalReview;
        });
        return;
      }
      final plugin = await loadPluginBundle(bundle: widget.bundle);
      if (!_current(attempt)) return;
      _subscription = _installer
          .run(
            host: host,
            port: port,
            username: username,
            password: password,
            pluginBundle: plugin,
            onHostKey: (key) => _verifyHostKey(key, attempt),
          )
          .listen(
            (event) => _progress(event, attempt),
            onError: (Object error, StackTrace stack) {
              if (!_current(attempt)) return;
              _fail(
                error is HostException ? error.message : 'Remote setup could not finish. Check the server and try again.',
              );
            },
            onDone: () {
              if (!_current(attempt) || _phase == _Phase.failed) return;
              _fail('Remote setup ended before the server was verified.');
            },
            cancelOnError: true,
          );
    } on HostException catch (error) {
      if (_current(attempt)) _fail(error.message);
    } on Object {
      if (_current(attempt)) {
        _fail(
          _removing
              ? 'Could not inspect the server. Check SSH access and try again.'
              : 'Could not load the bundled installer assets. Reinstall Hermuse and try again.',
        );
      }
    }
  }

  Future<bool> _verifyHostKey(RemoteHostKey key, int attempt) {
    if (!_current(attempt)) return Future.value(false);
    final decision = Completer<bool>();
    _hostKeyDecision = decision;
    setState(() {
      _hostKey = key;
      _phase = _Phase.hostKey;
    });
    return decision.future;
  }

  void _acceptHostKey() {
    final decision = _hostKeyDecision;
    if (decision == null || decision.isCompleted) return;
    _hostKeyDecision = null;
    setState(() {
      _hostKey = null;
      _phase = _Phase.installing;
    });
    decision.complete(true);
  }

  void _declineHostKey() {
    _fail(
      'SSH host key declined. No SSH credentials were sent and no server changes were made.',
    );
  }

  void _progress(RemoteInstallProgress event, int attempt) {
    if (!_current(attempt)) return;
    switch (event) {
      case RemoteInstallStepStarted(:final step):
        setState(() {
          _running = step;
          _finished.remove(step);
          _previouslyCompleted.remove(step);
          _checkingExisting = false;
          // A queued connect event must not hide an unanswered trust prompt.
          if (_hostKeyDecision == null) _phase = _Phase.installing;
        });
      case RemoteInstallStepFinished(:final step, :final previouslyCompleted):
        setState(() {
          _finished.add(step);
          if (previouslyCompleted) _previouslyCompleted.add(step);
          if (_running == step) _running = null;
        });
      case RemoteInstallLog(:final line):
        setState(() {
          if (line == 'Checking existing server setup…') {
            _checkingExisting = true;
          } else if (line == 'Existing server setup checked.') {
            _checkingExisting = false;
          }
          _log.add(line);
          if (_log.length > 200) _log.removeRange(0, _log.length - 200);
        });
      case RemoteInstallCompleted(:final outcome):
        _completed = true;
        _password.clear();
        widget.onDone(outcome);
    }
  }

  void _remove({required bool purge}) {
    final inventory = _inventory;
    if (_phase != _Phase.removalReview ||
        inventory == null ||
        inventory.transactionActive) {
      return;
    }
    final attempt = _attempt;
    final password = _inspectionPassword ?? '';
    _inspectionPassword = null;
    setState(() {
      _phase = _Phase.installing;
      _removalFinished.clear();
      _removalRunning = null;
      _purging = purge;
      _log.clear();
    });
    try {
      _uninstallSubscription = _uninstaller
          .run(
            host: _host.text.trim(),
            port: int.parse(_port.text.trim()),
            username: _username.text.trim(),
            password: password,
            inventory: inventory,
            purge: purge,
            onHostKey: (key) => _verifyHostKey(key, attempt),
          )
          .listen(
            (event) {
              if (!_current(attempt)) return;
              switch (event) {
                case RemoteUninstallStepStarted(:final step):
                  setState(() {
                    _removalRunning = step;
                    _removalFinished.remove(step);
                    if (_hostKeyDecision == null) _phase = _Phase.installing;
                  });
                case RemoteUninstallStepFinished(:final step):
                  setState(() {
                    _removalFinished.add(step);
                    if (_removalRunning == step) _removalRunning = null;
                  });
                case RemoteUninstallLog(:final line):
                  setState(() {
                    _log.add(line);
                    if (_log.length > 200) {
                      _log.removeRange(0, _log.length - 200);
                    }
                  });
                case RemoteUninstallCompleted(:final outcome):
                  _completed = true;
                  setState(() {
                    _removalOutcome = outcome;
                    _phase = _Phase.removalFinished;
                  });
              }
            },
            onError: (Object error, StackTrace stack) {
              if (_current(attempt)) {
                _fail(
                  error is HostException ? error.message : 'Server removal could not finish. Inspect the server again before retrying.',
                );
              }
            },
            onDone: () {
              if (_current(attempt) && _phase != _Phase.failed) {
                _fail('Server removal ended before its result was verified.');
              }
            },
            cancelOnError: true,
          );
    } on HostException catch (error) {
      if (_current(attempt)) _fail(error.message);
    } on Object {
      if (_current(attempt)) {
        _fail(
          'Server removal could not start. Inspect the server again before retrying.',
        );
      }
    }
  }

  void _switchOperation() {
    if (_phase != _Phase.form && _phase != _Phase.failed) return;
    // These screens have no active stream; retain any earlier cleanup future
    // so switching operations cannot start another SSH session too soon.
    _attempt++;
    _inspectionPassword = null;
    _password.clear();
    setState(() {
      _removing = !_removing;
      _phase = _Phase.form;
      _error = null;
      _retrying = false;
      _inventory = null;
    });
  }

  void _fail(String message) {
    _stop();
    setState(() {
      _phase = _Phase.failed;
      _hostKey = null;
      _error = message;
    });
  }

  void _retry() {
    _stop();
    _password.clear();
    setState(() {
      _completed = false;
      _phase = _Phase.form;
      _error = null;
      _retrying = true;
    });
  }

  @override
  Widget build(BuildContext context) => YsEntrance(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(YsSpace.xl),
        child: switch (_phase) {
          _Phase.form => _form(),
          _Phase.consent => _consent(),
          _Phase.hostKey => _fingerprint(_hostKey!),
          _Phase.removalReview => _removalReview(),
          _Phase.removalFinished => _removalResult(),
          _Phase.loading ||
          _Phase.installing ||
          _Phase.failed => _removing ? _removalProgressCard() : _progressCard(),
        },
      ),
    ),
  );

  Widget _form() => YsDialogCard(
    narrow: true,
    children: [
      YsDialogHead(
        art: YsArt.remote,
        title: _removing ? 'Remove from your server' : 'Install on your server',
        helper:
            'Use root, or an administrator who already has passwordless sudo.',
        trailing: YsButton.icon(
          icon: YsIcon.close,
          onPressed: _cancel,
          semanticLabel: 'Cancel',
          tooltip: 'Cancel',
        ),
      ),
      if (_retrying)
        YsDialogBody(
          _removing
              ? 'Inspect the server again before retrying removal. Use your SSH key or re-enter your SSH password.'
              : 'Existing server setup will be checked again; only missing or unhealthy parts are repaired. Use your SSH key or re-enter your SSH password.',
        ),
      if (_removing)
        const YsDialogBody(
          'First inspect a complete or partial installation. Nothing is removed until you review the findings and choose whether to keep or purge its data.',
        ),
      _field('Host or IP address', _host, icon: YsIcon.link, autofocus: true),
      _field('SSH port', _port, icon: YsIcon.link),
      _field('SSH user', _username, icon: YsIcon.user),
      _field(
        'SSH password (optional)',
        _password,
        icon: YsIcon.lock,
        obscure: true,
      ),
      const YsDialogBody(
        'Leave blank if an SSH key is already set up for this machine.',
      ),
      const YsDialogBody(
        'Your SSH password is never saved. You will verify the server fingerprint before any SSH credentials are sent.',
      ),
      if (_error case final error?) YsDialogError(error),
      YsButton.primary(
        label: _removing ? 'Review inspection' : 'Review setup',
        onPressed: _review,
      ),
      YsButton.neutral(
        label: _removing ? 'Install instead' : 'Remove from server',
        onPressed: _switchOperation,
      ),
    ],
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    required YsIcon icon,
    bool obscure = false,
    bool autofocus = false,
  }) => YsField(
    label: label,
    child: YsInputBox(
      controller: controller,
      semanticLabel: label,
      icon: icon,
      obscure: obscure,
      autofocus: autofocus,
      onSubmitted: (_) => _review(),
    ),
  );

  Widget _consent() => _removing
      ? YsDialogCard(
          children: [
            const YsDialogTitle('Inspect before removing?'),
            YsDialogBody(
              'Connect to ${_username.text.trim()}@${_host.text.trim()} on SSH port ${_port.text.trim()}.',
            ),
            const YsDialogBody(
              'This inspection is read-only. After verifying the SSH fingerprint, review what belongs to this installation before choosing to uninstall. Unrelated server services and packages are preserved.',
            ),
            YsButton.primary(label: 'Agree and inspect', onPressed: _start),
            YsButton.neutral(
              label: 'Back',
              onPressed: () => setState(() => _phase = _Phase.form),
            ),
            YsButton.neutral(label: 'Cancel', onPressed: _cancel),
          ],
        )
      : YsDialogCard(
          children: [
            const YsDialogTitle('Allow server setup?'),
            YsDialogBody(
              'Connect to ${_username.text.trim()}@${_host.text.trim()} on SSH port ${_port.text.trim()}.',
            ),
            const YsDialogBody(
              'For Ubuntu 24.04/26.04 or Debian 12/13 with systemd, x86-64 or ARM64, '
              'at least 4 GiB RAM and 10 GiB free disk.',
            ),
            const YsDialogBody(
              'Install Hermes under a dedicated hermes account, the bundled Hermuse '
              'plugin and scheduled jobs, Docker and the agent’s computer image. '
              'Docker group membership gives that account root-equivalent control of this server.',
            ),
            const YsDialogBody(
              'Install Caddy and publish the password-protected dashboard over HTTPS '
              'at a public sslip.io address. Existing unrelated Caddy configuration '
              'and firewall rules are preserved.',
            ),
            YsDialogBody(
              'Allow SSH port ${_port.text.trim()} and TCP 80/443 through UFW. '
              'A rollback is armed before firewall changes, then a fresh SSH login '
              'checks access. You must also allow ports 80/443 in your provider firewall.',
            ),
            const YsDialogBody(
              'Only continue for a server you administer. Cancelling closes SSH; '
              'packages and other changes already installed are not removed.',
            ),
            YsButton.primary(label: 'Agree and connect', onPressed: _start),
            YsButton.neutral(
              label: 'Back',
              onPressed: () => setState(() => _phase = _Phase.form),
            ),
            YsButton.neutral(label: 'Cancel', onPressed: _cancel),
          ],
        );

  Widget _fingerprint(RemoteHostKey key) {
    final palette = YsTheme.of(context);
    return YsDialogCard(
      children: [
        const YsDialogTitle('Verify the SSH host key'),
        YsDialogBody('${key.host}:${key.port} · ${key.type}'),
        SelectableText(
          key.fingerprint,
          textAlign: TextAlign.center,
          style: YsType.body.flutter.copyWith(
            fontFamily: YsType.monoFamily,
            color: palette.contentColor,
          ),
        ),
        const YsDialogBody(
          'Compare this SHA-256 fingerprint with the host key shown by your '
          'server console or administrator through a separate trusted channel. '
          'Accept only if it matches. No SSH credentials have been sent yet.',
        ),
        YsButton.primary(
          label: 'Accept fingerprint',
          onPressed: _acceptHostKey,
        ),
        YsButton.neutral(label: 'Decline', onPressed: _declineHostKey),
        YsButton.neutral(label: 'Cancel', onPressed: _cancel),
      ],
    );
  }

  Widget _removalReview() {
    final inventory = _inventory!;
    return YsDialogCard(
      children: [
        const YsDialogTitle('Review server removal'),
        YsDialogBody('Server: ${_host.text.trim()}'),
        const YsDialogBody(
          'Uninstall stops and removes the inspected installation’s services, code and owned network configuration. Keep data to retain its settings, conversations and caches for later use.',
        ),
        const YsDialogBody(
          'Purge also permanently deletes the inspected, installer-owned data, configuration and caches, including its dedicated account when safe. This cannot be undone. Shared packages, unrelated users and unrelated sites are preserved.',
        ),
        if (inventory.resources.isEmpty)
          const YsDialogBody('No installer-owned resources were found.'),
        for (final resource in inventory.resources)
          YsDialogBody(
            '${resource.label}: ${!resource.removable
                ? 'Preserved'
                : resource.purgeOnly
                ? 'Removed only with purge'
                : 'Removed with either option'}. ${resource.reason}',
          ),
        const YsDialogBody(
          'Saved instances and dashboard credentials in this app are not deleted by server removal.',
        ),
        if (inventory.transactionActive)
          const YsDialogError(
            'Another server setup or rollback is active. Wait for it to finish, then inspect again. No removal is allowed now.',
          )
        else ...[
          YsButton.primary(
            label: 'Uninstall and keep data',
            onPressed: () => _remove(purge: false),
          ),
          YsButton.destructive(
            label: 'Uninstall and purge data',
            onPressed: () => _remove(purge: true),
          ),
        ],
        YsButton.neutral(label: 'Inspect again', onPressed: _retry),
        YsButton.neutral(label: 'Cancel', onPressed: _cancel),
      ],
    );
  }

  Widget _removalProgressCard() => SetupCard(
    title: _inspecting
        ? 'Inspecting your server'
        : 'Removing server installation',
    status: _phase == _Phase.failed
        ? 'Removal stopped'
        : _inspecting
        ? 'Read-only inspection; no changes yet…'
        : _removalRunning == null
        ? 'Preparing the next removal step…'
        : _removalRunning == RemoteUninstallStep.purge && !_purging
        ? 'Keeping data, configuration and caches'
        : _removalStepDetails(_removalRunning!).$2,
    busy: _phase != _Phase.failed,
    notices: [
      if (_error case final error?) SetupNotice(error, alert: true),
      SetupNotice(
        _inspecting
            ? 'Nothing is removed until you confirm the inspected plan.'
            : 'Cancelling closes SSH. Resources already removed are not restored. Inspect again before retrying.',
      ),
    ],
    log: _log,
    items: _inspecting
        ? [
            YsChecklistItem(
              id: RemoteUninstallStep.inspect,
              icon: YsIcon.check,
              title: 'Read-only server inspection',
              state: _phase == _Phase.failed
                  ? YsStepState.failed
                  : YsStepState.checking,
              status: _phase == _Phase.failed ? 'Stopped' : 'Inspecting…',
            ),
          ]
        : [for (final step in RemoteUninstallStep.values) _removalStep(step)],
    actions: [
      if (_phase == _Phase.failed)
        YsButton.primary(label: 'Try again', onPressed: _retry),
      YsButton.neutral(label: 'Cancel', onPressed: _cancel),
    ],
  );

  YsChecklistItem _removalStep(RemoteUninstallStep step) {
    final (icon, title) = _removalStepDetails(step);
    final done = _removalFinished.contains(step);
    final active = step == _removalRunning;
    return YsChecklistItem(
      id: step,
      icon: icon,
      title: step == RemoteUninstallStep.purge && !_purging
          ? 'Keep data, configuration and caches'
          : title,
      state: done
          ? YsStepState.done
          : active
          ? _phase == _Phase.failed
                ? YsStepState.failed
                : YsStepState.working
          : YsStepState.pending,
      status: done
          ? 'Finished'
          : active
          ? _phase == _Phase.failed
                ? 'Stopped'
                : 'Working…'
          : 'Waiting',
    );
  }

  Widget _removalResult() {
    final outcome = _removalOutcome!;
    return YsDialogCard(
      children: [
        YsDialogTitle(
          outcome.complete
              ? outcome.purged
                    ? 'Server installation purged'
                    : 'Server installation removed'
              : 'Some server resources were kept',
        ),
        YsDialogBody('Server: ${_host.text.trim()}'),
        if (!outcome.complete)
          const YsDialogError(
            'Removal could not safely finish for every managed resource. Review what was preserved below before taking further action.',
          ),
        if (outcome.removed.isEmpty)
          const YsDialogBody(
            'No removable installer-owned resources remained.',
          ),
        for (final removed in outcome.removed)
          YsDialogBody('Removed: $removed'),
        for (final resource in outcome.preserved)
          YsDialogBody('Kept ${resource.label}: ${resource.reason}'),
        for (final warning in outcome.warnings) YsDialogError(warning),
        const YsDialogBody(
          'Your saved instance and its dashboard credentials remain in this app. You can delete that saved connection separately from Hermes instances.',
        ),
        if (!outcome.complete)
          YsButton.neutral(
            label: 'Inspect remaining resources',
            onPressed: _retry,
          ),
        YsButton.primary(label: 'Done', onPressed: _cancel),
      ],
    );
  }

  Widget _progressCard() => SetupCard(
    title: 'Setting up your server',
    status: _phase == _Phase.failed
        ? 'Setup stopped'
        : _phase == _Phase.loading
        ? 'Loading the bundled Hermuse plugin…'
        : _checkingExisting
        ? 'Checking existing server setup…'
        : _running == null
        ? 'Preparing the next step…'
        : _stepDetails(_running!).$2,
    busy: _phase != _Phase.failed,
    notices: [
      if (_error case final error?) SetupNotice(error, alert: true),
      const SetupNotice(
        'Cancelling closes SSH. Changes already installed remain on the server.',
      ),
    ],
    log: _log,
    items: [for (final step in RemoteInstallStep.values) _step(step)],
    actions: [
      if (_phase == _Phase.failed)
        YsButton.primary(label: 'Try again', onPressed: _retry),
      if (_phase == _Phase.failed)
        YsButton.neutral(
          label: 'Remove from server',
          onPressed: _switchOperation,
        ),
      YsButton.neutral(label: 'Cancel', onPressed: _cancel),
    ],
  );

  YsChecklistItem _step(RemoteInstallStep step) {
    final (icon, title) = _stepDetails(step);
    final state = _finished.contains(step)
        ? _previouslyCompleted.contains(step)
              ? YsStepState.found
              : YsStepState.done
        : step == _running
        ? _phase == _Phase.failed
              ? YsStepState.failed
              : YsStepState.working
        : YsStepState.pending;
    return YsChecklistItem(
      id: step,
      icon: icon,
      title: title,
      state: state,
      status: _finished.contains(step)
          ? _previouslyCompleted.contains(step)
                ? 'Already installed'
                : 'Ready'
          : step == _running
          ? _phase == _Phase.failed
                ? 'Stopped'
                : 'Working…'
          : 'Waiting',
    );
  }
}

(YsIcon, String) _stepDetails(RemoteInstallStep step) => switch (step) {
  RemoteInstallStep.connect => (YsIcon.link, 'SSH connection'),
  RemoteInstallStep.preflight => (YsIcon.check, 'Server requirements'),
  RemoteInstallStep.firewall => (YsIcon.lock, 'Guarded firewall setup'),
  RemoteInstallStep.hermesUser => (YsIcon.user, 'Dedicated Hermes account'),
  RemoteInstallStep.hermes => (YsIcon.bot, 'Hermes Agent'),
  RemoteInstallStep.plugin => (YsIcon.puzzle, 'Hermuse plugin and jobs'),
  RemoteInstallStep.computer => (YsIcon.monitor, 'Docker and agent’s computer'),
  RemoteInstallStep.dashboard => (YsIcon.keyRound, 'Dashboard account'),
  RemoteInstallStep.https => (YsIcon.lock, 'Caddy and public HTTPS'),
  RemoteInstallStep.verify => (YsIcon.check, 'Final readiness checks'),
};

(YsIcon, String) _removalStepDetails(
  RemoteUninstallStep step,
) => switch (step) {
  RemoteUninstallStep.connect => (YsIcon.link, 'SSH connection'),
  RemoteUninstallStep.inspect => (YsIcon.check, 'Recheck removal plan'),
  RemoteUninstallStep.services => (YsIcon.bot, 'Stop installer-owned services'),
  RemoteUninstallStep.runtime => (YsIcon.puzzle, 'Remove installed runtime'),
  RemoteUninstallStep.network => (
    YsIcon.lock,
    'Restore owned network configuration',
  ),
  RemoteUninstallStep.purge => (
    YsIcon.user,
    'Purge owned data and dedicated account',
  ),
  RemoteUninstallStep.verify => (YsIcon.check, 'Verify server removal'),
};
