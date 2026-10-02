import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hermes_client/hermes_client.dart';
import 'package:http/http.dart' as http;

import 'errors.dart';
import 'installer.dart';
import 'remote_operation.dart';
import 'remote_scripts.dart';
import 'remote_shell.dart';
import 'remote_uninstall_scripts.dart';

/// Ordered remote provisioning steps, independent of the installer's stages.
enum RemoteInstallStep {
  connect,
  preflight,
  firewall,
  hermesUser,
  hermes,
  plugin,
  computer,
  dashboard,
  web,
  https,
  verify,
}

sealed class RemoteInstallProgress {
  const RemoteInstallProgress();
}

final class RemoteInstallStepStarted extends RemoteInstallProgress {
  const RemoteInstallStepStarted(this.step);
  final RemoteInstallStep step;
}

final class RemoteInstallStepFinished extends RemoteInstallProgress {
  const RemoteInstallStepFinished(
    this.step, {
    this.previouslyCompleted = false,
  });
  final RemoteInstallStep step;

  /// Whether this session's read-only inventory proved the installed step healthy.
  final bool previouslyCompleted;
}

final class RemoteInstallLog extends RemoteInstallProgress {
  const RemoteInstallLog(this.line);
  final String line;
}

final class RemoteInstallCompleted extends RemoteInstallProgress {
  const RemoteInstallCompleted(this.outcome);
  final RemoteInstallOutcome outcome;
}

/// Credentials stay in memory until the app's existing authenticated save flow.
final class RemoteInstallOutcome {
  const RemoteInstallOutcome({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.webUrl,
  });
  final String baseUrl;
  final String username;
  final String password;

  /// HTTPS address of the web app published on this server, or null when the
  /// server publishes none.
  final String? webUrl;
}

typedef RemoteDashboardVerifier = Future<void> Function(
  RemoteInstallOutcome outcome,
  RemoteCancellation cancellation,
);

/// Provisions a supported Linux server over host-verified SSH.
///
/// Existing firewall rules and Caddy sites are preserved. Changes to either are
/// guarded by independent systemd restoration timers before mutation. Only a
/// fresh pinned-key SSH login commits the firewall; client-side TLS and password
/// authentication commit Caddy. Other completed installation stages remain on
/// failure/cancellation and can be retried. No SSH credential is persisted.
class RemoteInstaller {
  RemoteInstaller({
    RemoteConnector? connect,
    RemoteDashboardVerifier? verifyDashboard,
    Future<void> Function(Duration)? sleep,
    this.computerTimeout = const Duration(minutes: 20),
  }) : _connect = connect ?? SshRemoteShell.connect,
       _verifyDashboard = verifyDashboard ?? verifyRemoteDashboard,
       _sleep = sleep ?? Future<void>.delayed;

  final RemoteConnector _connect;
  final RemoteDashboardVerifier _verifyDashboard;
  final Future<void> Function(Duration) _sleep;
  final Duration computerTimeout;
  final _trust = RemoteHostKeyTrust();
  RemoteCancellation? _active;
  Completer<void>? _stopped;

  /// Uses [password] when supplied; otherwise uses this machine's existing keys.
  ///
  /// [webApp] publishes the web app and relay on their own sslip.io address.
  /// When false, none is added, but an existing healthy one is kept and
  /// reported; removal only happens through uninstall.
  Stream<RemoteInstallProgress> run({
    required String host,
    int port = 22,
    String username = 'root',
    String password = '',
    required Map<String, Uint8List> pluginBundle,
    required Future<bool> Function(RemoteHostKey) onHostKey,
    bool webApp = false,
  }) {
    if (_active != null) {
      throw StateError('A remote installation is already running.');
    }
    final cancellation = RemoteCancellation();
    _active = cancellation;
    final stopped = _stopped = Completer<void>();
    late final StreamController<RemoteInstallProgress> events;
    events = StreamController<RemoteInstallProgress>(
      onListen: () async {
        final attempt = _RemoteAttempt(
          installer: this,
          host: host,
          port: port,
          username: username,
          password: password,
          pluginBundle: pluginBundle,
          webApp: webApp,
          onHostKey: onHostKey,
          cancellation: cancellation,
          emit: (event) {
            if (!events.isClosed) events.add(event);
          },
        );
        try {
          await attempt.run();
        } catch (error, stack) {
          if (!events.isClosed) events.addError(error, stack);
        } finally {
          _active = null;
          stopped.complete();
          await events.close();
        }
      },
      onCancel: cancellation.cancel,
    );
    return events.stream;
  }

  /// Stops the active transport and prevents all later stages from starting.
  /// Safety timers remain armed when the connection cannot restore immediately.
  Future<void> cancel() {
    _active?.cancel();
    return _stopped?.future ?? Future<void>.value();
  }
}

enum _RemoteHealth { ready, repair, deferred, absent }

final class _RemoteAttempt {
  _RemoteAttempt({
    required this.installer,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.pluginBundle,
    required this.webApp,
    required this.onHostKey,
    required this.cancellation,
    required this.emit,
  });

  final RemoteInstaller installer;
  final String host;
  final int port;
  final String username;
  final String password;
  final Map<String, Uint8List> pluginBundle;
  final bool webApp;
  final Future<bool> Function(RemoteHostKey) onHostKey;
  final RemoteCancellation cancellation;
  final void Function(RemoteInstallProgress) emit;
  final _id = _randomSecret(20);
  RemoteShell? _shell;
  RemoteOperationLock? _operation;
  var _step = RemoteInstallStep.connect;
  var _root = false;
  var _supervise = false;
  String? _dashboardPassword;
  String? _upload;
  String? _firewallRollback;
  String? _caddyRollback;
  final _healthy = <RemoteInstallStep>{};
  String? _domain;
  String? _webToken;
  _RemoteHealth? _web;
  var _dashboardInstalled = false;
  var _ownershipCaptured = false;
  var _completed = false;

  String get _directory => '$provisionRoot/$_id';

  String _redact(String value) {
    var clean = stripAnsi(value);
    for (final secret in [password, _dashboardPassword, _webToken]) {
      if (secret != null && secret.isNotEmpty) {
        clean = clean.replaceAll(secret, '[redacted]');
      }
    }
    return clean;
  }

  void _log(String line) => emit(RemoteInstallLog(_redact(line)));

  Future<void> _stage(
    RemoteInstallStep step,
    Future<void> Function() body,
  ) async {
    cancellation.check();
    if (_healthy.contains(step)) return;
    _step = step;
    emit(RemoteInstallStepStarted(step));
    await body();
    cancellation.check();
    emit(RemoteInstallStepFinished(step));
  }

  Future<RemoteShell> _connect() => installer._connect(
    host: host,
    port: port,
    username: username,
    password: password,
    verifyHostKey: (key) => installer._trust.verify(
      key,
      (key) => cancellation.bind(onHostKey(key)),
    ),
    cancellation: cancellation,
  );

  Future<RemoteResult> _run(
    String script, {
    bool root = true,
    String? stdin,
    bool log = true,
    Duration timeout = const Duration(minutes: 10),
    bool required = true,
  }) async {
    _operation?.check();
    cancellation.check();
    final body = _supervise
        ? (root
              ? _operation!.supervise(script, timeout.inSeconds)
              : supervisedCommand(script, timeout.inSeconds))
        : script;
    final command =
        '${root && !_root ? 'sudo -n ' : ''}'
        'bash -euo pipefail -c ${shellQuote(body)}';
    final result = await cancellation.bind(
      _shell!.run(
        command,
        stdin: stdin,
        timeout: timeout + const Duration(seconds: 15),
        onLine: log ? _log : null,
      ),
    );
    cancellation.check();
    if (required && result.exitCode != 0) {
      final detail = _redact('${result.stderr}\n${result.stdout}').trim();
      final tail = detail.length > 4000
          ? detail.substring(detail.length - 4000)
          : detail;
      throw RemoteInstallFailed(
        _step.name,
        '${_step.name} failed (exit ${result.exitCode}).${tail.isEmpty ? '' : '\n$tail'}',
      );
    }
    return result;
  }

  Future<_RemoteHealth> _health(String script, {String? stdin}) async {
    final result = await _run(script, stdin: stdin, log: false);
    return switch (result.stdout.trim()) {
      'HERMUSE_HEALTH_V1:ready' => _RemoteHealth.ready,
      'HERMUSE_HEALTH_V1:repair' => _RemoteHealth.repair,
      'HERMUSE_HEALTH_V1:deferred' => _RemoteHealth.deferred,
      'HERMUSE_HEALTH_V1:absent' => _RemoteHealth.absent,
      _ => throw RemoteInstallFailed(
        _step.name,
        'The server returned an invalid installation health frame.',
      ),
    };
  }

  Future<void> _prove(String script, {String? stdin}) async {
    if (await _health(script, stdin: stdin) != _RemoteHealth.ready) {
      throw RemoteInstallFailed(
        _step.name,
        'The repaired ${_step.name} step did not pass its installation health checks.',
      );
    }
  }

  Future<void> _resolveDomain() async {
    final address = await _run(publicAddressScript, log: false);
    if (address.stdout.trim().isNotEmpty) {
      _domain = sslipDomain(address.stdout.trim());
    }
  }

  late final Map<String, String> _pluginHashes = {
    for (final entry in pluginBundle.entries)
      entry.key: sha256.convert(entry.value).toString(),
  };
  late final String _pluginHealth = pluginHealthScript(_pluginHashes);
  late final String _ownershipCheckpoint = remoteOwnershipCheckpointScript;

  /// The web app image matching the bundled plugin, or null without a version.
  late final String? _webImage = switch (_bundledPluginVersion(pluginBundle)) {
    final version? => webImageReference(version),
    null => null,
  };

  String _webInventory({required bool publish}) => webInventoryScript(
    webAppDomain(_domain!),
    _domain!,
    _webImage,
    publish: publish,
  );

  /// An owned deployment keeps its route even when publishing is not chosen.
  String? get _caddyWebDomain =>
      webApp || _web == _RemoteHealth.ready || _web == _RemoteHealth.repair
      ? webAppDomain(_domain!)
      : null;

  Future<void> _inspectWeb() async {
    _step = RemoteInstallStep.web;
    _web = await _health(_webInventory(publish: webApp));
    if (_web == _RemoteHealth.ready) _healthy.add(RemoteInstallStep.web);
  }

  Future<bool> _inventory(Set<int> ports) async {
    _log('Checking existing server setup…');
    await _run(remoteOwnershipPreflightScript, log: false);
    final packages = await _health(prerequisitesHealthScript);
    final status = await _run(
      'if command -v ufw >/dev/null; then LC_ALL=C ufw status verbose; else echo "Status: unavailable"; fi',
      log: false,
    );
    if (ufwAllowsPorts(status.stdout, ports)) {
      _healthy.add(RemoteInstallStep.firewall);
    }
    for (final (step, script, dependencies) in [
      (
        RemoteInstallStep.hermesUser,
        hermesUserHealthScript,
        <RemoteInstallStep>[],
      ),
      (
        RemoteInstallStep.hermes,
        hermesHealthScript,
        [RemoteInstallStep.hermesUser],
      ),
      (RemoteInstallStep.plugin, _pluginHealth, [RemoteInstallStep.hermes]),
      (
        RemoteInstallStep.computer,
        computerHealthScript,
        [RemoteInstallStep.plugin],
      ),
    ]) {
      if (!dependencies.every(_healthy.contains)) continue;
      _step = step;
      if (await _health(script) == _RemoteHealth.ready) _healthy.add(step);
    }
    _step = RemoteInstallStep.computer;
    await _run(computerOwnershipScript, log: false);
    _step = RemoteInstallStep.dashboard;
    await _resolveDomain();
    if (_domain != null &&
        _healthy.containsAll({
          RemoteInstallStep.hermes,
          RemoteInstallStep.plugin,
        })) {
      _dashboardInstalled =
          await _health(dashboardHealthScript(_domain!, authenticate: false)) ==
          _RemoteHealth.ready;
    }
    if (_domain != null) await _inspectWeb();
    _step = RemoteInstallStep.https;
    if (_domain != null) {
      if (await _health(
            caddyHealthScript(_domain!, webDomain: _caddyWebDomain),
          ) ==
          _RemoteHealth.ready) {
        _healthy.add(RemoteInstallStep.https);
      }
    } else {
      // A fresh machine can defer DNS until prerequisite tools are installed.
      // Existing routes must be inspectable before any mutation is permitted.
      await _run(
        "if command -v caddy >/dev/null; then echo 'Cannot inspect existing Caddy routes without detecting the public address.' >&2; exit 1; fi",
        log: false,
      );
    }
    cancellation.check();
    for (final step in RemoteInstallStep.values) {
      if (_healthy.contains(step)) {
        emit(RemoteInstallStepFinished(step, previouslyCompleted: true));
      }
    }
    _log('Existing server setup checked.');
    _step = RemoteInstallStep.preflight;
    return packages == _RemoteHealth.ready;
  }

  Future<void> _dashboard() async {
    if (_domain == null) await _resolveDomain();
    if (_domain == null) {
      throw const RemoteInstallFailed(
        'dashboard',
        'Could not detect the server public IPv4 address.',
      );
    }
    _log(
      _dashboardInstalled
          ? 'The existing dashboard is healthy; reestablishing admin sign-in for this setup.'
          : 'No recoverable dashboard credential was found; reestablishing the admin sign-in.',
    );
    _dashboardPassword = _randomSecret(32);
    await _run(
      asHermes('$remotePython -c ${shellQuote(dashboardPasswordScript)}'),
      stdin: _dashboardPassword,
      log: false,
    );
    if (!_dashboardInstalled) {
      await _run(
        asHermes(
          '$remoteHermes config set dashboard.public_url https://$_domain',
        ),
      );
    }
    await _run(configureDashboardScript());
    await _prove(dashboardHealthScript(_domain!), stdin: _dashboardPassword);
    await _run(_ownershipCheckpoint, log: false);
  }

  Future<void> run() async {
    try {
      _validateInputs();
      await _stage(RemoteInstallStep.connect, () async {
        _shell = await _connect();
      });
      var serverSshPort = port;
      await _stage(RemoteInstallStep.preflight, () async {
        final identity = await _run('id -u', root: false, log: false);
        _root = identity.stdout.trim() == '0';
        if (!_root) {
          final sudo = await _run(
            'sudo -n true',
            root: false,
            log: false,
            required: false,
          );
          if (sudo.exitCode != 0) {
            throw const RemoteInstallFailed(
              'preflight',
              'Log in as root or an administrator with passwordless sudo. '
                  'The SSH password is never reused for privilege elevation.',
            );
          }
        }
        _operation = await RemoteOperationLock.acquire(
          _shell!,
          root: _root,
          cancellation: cancellation,
        );
        final connection = await _run(
          r'printf "%s" "$SSH_CONNECTION"',
          root: false,
          log: false,
        );
        final connectionParts = connection.stdout.trim().split(RegExp(r'\s+'));
        serverSshPort = int.tryParse(connectionParts.last) ?? 0;
        if (serverSshPort < 1 || serverSshPort > 65535) {
          throw const RemoteInstallFailed(
            'preflight',
            'SSH did not report its server-side port.',
          );
        }
        await _run(preflightScript);
        _supervise = true;
        final prerequisitesReady = await _inventory({
          port,
          serverSshPort,
          80,
          443,
        });
        await _run(remoteOwnershipCaptureScript, log: false);
        _ownershipCaptured = true;
        if (!prerequisitesReady) {
          await _run(installPrerequisitesScript);
          await _prove(prerequisitesHealthScript);
          await _run(_ownershipCheckpoint, log: false);
        }
      });
      await _stage(
        RemoteInstallStep.firewall,
        () => _firewall({port, serverSshPort, 80, 443}, {port, serverSshPort}),
      );
      await _stage(RemoteInstallStep.hermesUser, () async {
        await _run(
          remoteOwnershipMutationScript({remoteHermesHome}, account: true),
          log: false,
        );
        await _run(createHermesUserScript);
        await _prove(hermesUserHealthScript);
        await _run(_ownershipCheckpoint, log: false);
      });
      await _stage(RemoteInstallStep.hermes, _installHermes);
      await _stage(RemoteInstallStep.plugin, _installPlugin);
      await _stage(RemoteInstallStep.computer, _installComputer);
      await _stage(RemoteInstallStep.dashboard, _dashboard);
      final domain = _domain!;
      final webDomain = webAppDomain(domain);
      if (_web == null) {
        // The public address was unknown during inventory; inspect read-only
        // now, before the web or Caddy steps can change anything.
        await _inspectWeb();
        if (_web == _RemoteHealth.ready) {
          emit(
            const RemoteInstallStepFinished(
              RemoteInstallStep.web,
              previouslyCompleted: true,
            ),
          );
        }
      }
      if (webApp) {
        await _stage(RemoteInstallStep.web, _installWeb);
      } else if (_web == _RemoteHealth.repair) {
        _log(
          'The existing web app at https://$webDomain is not healthy and was '
          'left unchanged. Choose to publish the web app to repair it, or '
          'uninstall to remove it.',
        );
      }
      final caddyWebDomain = _caddyWebDomain;
      await _stage(RemoteInstallStep.https, () async {
        await _run(installCaddyScript);
        await _run(
          caddyOwnershipScript(domain, webDomain: caddyWebDomain),
          log: false,
        );
        await _run(remoteOwnershipMutationScript({}, caddy: true), log: false);
        _caddyRollback = '$_directory/caddy';
        await _run(
          caddyConfigureScript(
            _caddyRollback!,
            domain,
            webDomain: caddyWebDomain,
          ),
        );
        await _prove(caddyHealthScript(domain, webDomain: caddyWebDomain));
      });
      final webPublished = _web == _RemoteHealth.ready;
      final outcome = RemoteInstallOutcome(
        baseUrl: 'https://$domain',
        username: 'admin',
        password: _dashboardPassword!,
        webUrl: webPublished ? 'https://$webDomain' : null,
      );
      await _stage(RemoteInstallStep.verify, () async {
        try {
          await cancellation.bind(
            installer._verifyDashboard(outcome, cancellation),
          );
        } on RemoteInstallCancelled {
          rethrow;
        } catch (error) {
          throw RemoteInstallFailed(
            'verify',
            'The HTTPS ${webPublished ? 'dashboard and web app' : 'dashboard'} '
                'could not be verified from this computer. '
                'Ports 80 and 443 must be reachable from the internet, including '
                'the provider firewall; $domain${webPublished ? ' and $webDomain' : ''} '
                'must resolve to the server. '
                '${_redact('$error')}',
          );
        }
        if (_caddyRollback != null) {
          await _run(
            commitRollbackScript(_caddyRollback!, 'hermuse-caddy-rollback'),
          );
          _caddyRollback = null;
          await _run(_ownershipCheckpoint, log: false);
        }
      });
      _completed = true;
      emit(RemoteInstallCompleted(outcome));
    } on HostException {
      rethrow;
    } catch (error) {
      cancellation.check();
      throw RemoteInstallFailed(_step.name, _redact('$error'));
    } finally {
      // On a broken/cancelled SSH session the independent timers do this instead.
      for (final (directory, unit) in [
        (_firewallRollback, 'hermuse-firewall-rollback'),
        (_caddyRollback, 'hermuse-caddy-rollback'),
      ]) {
        if (directory == null || cancellation.isCancelled) continue;
        try {
          await _run(restoreRollbackScript(directory, unit), log: false);
        } catch (_) {
          _log(
            'The $unit safety timer remains responsible for restoring the previous configuration.',
          );
        }
      }
      if (_upload != null && !cancellation.isCancelled) {
        try {
          await _run('rm -rf -- ${shellQuote(_upload!)}', log: false);
        } catch (_) {
          /* Private, non-secret plugin staging only. */
        }
      }
      if (_ownershipCaptured && !_completed && !cancellation.isCancelled) {
        try {
          await _run(_ownershipCheckpoint, log: false);
        } catch (_) {
          _log(
            'Partial installation identities could not be recorded; '
            'unbound resources will be preserved during uninstall.',
          );
        }
      }
      _operation?.release();
      _shell?.close();
      _dashboardPassword = null;
      _webToken = null;
    }
  }

  void _validateInputs() {
    if (host.isEmpty ||
        host.contains(RegExp(r'[\s/\x00]')) ||
        port < 1 ||
        port > 65535 ||
        username.isEmpty) {
      throw const RemoteInstallFailed(
        'connect',
        'Enter a host, valid SSH port and user name.',
      );
    }
    if (!pluginBundle.containsKey('plugin.yaml') ||
        !pluginBundle.containsKey('__init__.py')) {
      throw const RemoteInstallFailed(
        'plugin',
        'The bundled Hermuse plugin is incomplete.',
      );
    }
    for (final path in pluginBundle.keys) {
      if (path.startsWith('/') ||
          path.contains('\\') ||
          path.contains('\x00') ||
          path
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..')) {
        throw const RemoteInstallFailed(
          'plugin',
          'The plugin bundle contains an unsafe relative path.',
        );
      }
    }
    if (webApp && _webImage == null) {
      throw const RemoteInstallFailed(
        'web',
        'The bundled Hermuse plugin has no valid version, so the matching web '
            'app image cannot be selected.',
      );
    }
  }

  Future<void> _firewall(Set<int> ports, Set<int> sshPorts) async {
    final status = await _run(
      'if command -v ufw >/dev/null; then LC_ALL=C ufw status verbose; else echo "Status: unavailable"; fi',
      log: false,
    );
    if (ufwAllowsPorts(status.stdout, ports)) {
      _log(
        'Existing UFW rules already permit SSH and HTTPS; preserving all rules.',
      );
      return;
    }
    _firewallRollback = '$_directory/firewall';
    await _run(firewallConfigureScript(_firewallRollback!, ports));
    _log(
      'Validating the firewall with a new SSH connection and the accepted host key.',
    );
    RemoteShell? fresh;
    try {
      fresh = await _connect();
      final check = await fresh.run(
        'true',
        timeout: const Duration(seconds: 20),
      );
      if (check.exitCode != 0) {
        throw const RemoteUnreachable('The new SSH login did not complete.');
      }
    } catch (error) {
      if (error is RemoteHostKeyChanged || error is RemoteInstallCancelled) {
        rethrow;
      }
      throw RemoteInstallFailed(
        'firewall',
        'Fresh SSH validation failed. The previous firewall configuration is '
            'being restored (automatically within 180 seconds if SSH was lost). '
            'Check the SSH port and provider firewall. ${_redact('$error')}',
      );
    } finally {
      fresh?.close();
    }
    final repaired = await _run('LC_ALL=C ufw status verbose', log: false);
    if (!ufwAllowsPorts(repaired.stdout, ports)) {
      throw const RemoteInstallFailed(
        'firewall',
        'The repaired firewall did not allow SSH/HTTP/HTTPS for both IP families.',
      );
    }
    await _run(
      commitRollbackScript(_firewallRollback!, 'hermuse-firewall-rollback'),
    );
    _firewallRollback = null;
    await _run(recordRemoteFirewallOwnershipScript(sshPorts), log: false);
  }

  Future<void> _installHermes() async {
    if (await _health(hermesHealthScript) == _RemoteHealth.ready) return;
    await _run(
      remoteOwnershipMutationScript({
        remoteCheckout,
        '$remoteHermesHome/bin',
        '$remoteHermesHome/node',
        '$remoteHermesHome/runtime',
        '$remoteHome/.local/share/uv',
        remoteHermes,
        '$remoteHome/.local/bin/hermes-agent',
        '$remoteHome/.local/bin/hermes-acp',
        '$remoteHome/.local/bin/node',
        '$remoteHome/.local/bin/npm',
        '$remoteHome/.local/bin/npx',
        '$remoteHome/.cache/uv',
        '$remoteHome/.cache/pip',
        '$remoteHome/.cache/npm',
        '$remoteHome/.cache/ms-playwright',
        '$remoteHome/.npm',
      }),
      log: false,
    );
    const source = InstallerSource(isWindows: false);
    final directory = '$_directory/installer';
    // The installer is root-owned, readable by hermes, and never executable
    // until its hash matches the existing release pin.
    await _run('install -d -m 0711 $provisionRoot ${shellQuote(_directory)}');
    await _run(downloadInstallerScript(directory, source));
    final script = '$directory/install.sh';
    final manifestResult = await _run(
      asHermes('bash ${shellQuote(script)} --manifest'),
      log: false,
    );
    final manifest = parseManifestOutput(manifestResult.stdout);
    if (manifest.protocolVersion != 1 || manifest.stages.isEmpty) {
      throw const RemoteInstallFailed(
        'hermes',
        'Unsupported or empty staged-installer manifest.',
      );
    }
    for (final stage in manifest.stages) {
      if (const {'setup', 'configure', 'gateway'}.contains(stage.name)) {
        continue;
      }
      _log(stage.title);
      final command =
          'bash ${shellQuote(script)} --stage ${shellQuote(stage.name)} '
          '--commit ${source.commit} --force-commit --dir $remoteCheckout '
          '--skip-browser --skip-computer-use --non-interactive --json';
      final result = await _run(
        asHermes(command),
        required: false,
        timeout: const Duration(minutes: 20),
      );
      final frame = parseStageResultOutput(result.stdout);
      if (result.exitCode != 0 ||
          frame == null ||
          !frame.ok ||
          frame.stage != stage.name ||
          (frame.skipped && !stage.needsUserInput)) {
        throw RemoteInstallFailed(
          'hermes',
          'Hermes stage ${stage.name} failed: ${_redact(frame?.reason ?? 'missing, mismatched or unsuccessful result frame (exit ${result.exitCode})')}.',
        );
      }
    }
    await _prove(hermesHealthScript);
    await _run(_ownershipCheckpoint, log: false);
  }

  Future<void> _installPlugin() async {
    if (await _health(_pluginHealth) == _RemoteHealth.ready) return;
    final upload = '/tmp/hermuse-upload-$_id';
    await _run(createPluginStagingScript(upload), root: false);
    // Cleanup only paths this attempt created, never an attacker's preexisting
    // directory or symlink that made the exclusive mkdir fail.
    _upload = upload;
    final directories = <String>{_upload!};
    for (final path in pluginBundle.keys) {
      final slash = path.lastIndexOf('/');
      if (slash >= 0) directories.add('$_upload/${path.substring(0, slash)}');
    }
    await _run(
      'umask 077\nmkdir -p -- ${directories.map(shellQuote).join(' ')}',
      root: false,
    );
    for (final entry in pluginBundle.entries) {
      cancellation.check();
      await cancellation.bind(
        _shell!.writeFile('$_upload/${entry.key}', entry.value),
      );
    }
    const target = '$remoteHermesHome/plugins/hermuse';
    await _run(remoteOwnershipMutationScript({target}), log: false);
    await _run('''
if [ -e $target ] && [ ! -f $target/.hermuse-remote-managed ]; then
  echo 'An unrelated plugin occupies the Hermuse plugin directory.' >&2; exit 1
fi
install -d -o hermes -g hermes -m 0700 $remoteHermesHome/plugins
cp -a ${shellQuote(_upload!)} $target.next-$_id
chown -R hermes:hermes $target.next-$_id
touch $target.next-$_id/.hermuse-remote-managed
if [ -e $target ]; then mv $target $target.previous-$_id; fi
if ! mv $target.next-$_id $target; then
  [ ! -e $target.previous-$_id ] || mv $target.previous-$_id $target
  exit 1
fi
rm -rf -- $target.previous-$_id
''');
    await _run(
      asHermes(
        '$remoteHermes plugins enable hermuse\n$remoteHermes hermuse enable',
      ),
    );
    await _prove(_pluginHealth);
    await _run(_ownershipCheckpoint, log: false);
  }

  Future<void> _installComputer() async {
    if (await _health(computerHealthScript) == _RemoteHealth.ready) return;
    await _run(installDockerScript);
    await _run(recordRemoteDockerBaselineScript, log: false);
    await _run(remoteOwnershipMutationScript({}, computer: true), log: false);
    await _run(
      asHermes('docker version --format ${shellQuote('{{.Server.Version}}')}'),
    );
    await _run(
      asHermes('$remotePython -c ${shellQuote(prepareComputerImageScript)}'),
      timeout: installer.computerTimeout,
    );
    var result = await _run(
      asHermes('$remoteHermes hermuse computer setup'),
      required: false,
    );
    final watch = Stopwatch()..start();
    while (true) {
      cancellation.check();
      final state = parseRemoteComputerStatus(result.stdout);
      if (result.exitCode != 0 ||
          !const {'building', 'stopped', 'running'}.contains(state['state'])) {
        throw RemoteInstallFailed(
          'computer',
          'The agent computer is not ready: ${_redact('${state['state']}: ${state['detail'] ?? ''}')} '
              '(exit ${result.exitCode}).',
        );
      }
      if (state['state'] == 'stopped' || state['state'] == 'running') break;
      if (watch.elapsed >= installer.computerTimeout) {
        throw const RemoteInstallFailed(
          'computer',
          'Timed out waiting for the Docker computer image.',
        );
      }
      _log('${state['detail'] ?? 'Preparing the agent computer image…'}');
      await cancellation.bind(installer._sleep(const Duration(seconds: 3)));
      result = await _run(
        asHermes('$remoteHermes hermuse computer status'),
        required: false,
        log: false,
      );
    }
    await _run(
      asHermes(
        '$remotePython -B -c ${shellQuote(repairComputerContainerScript)}',
      ),
    );
    // Image presence alone is insufficient: start checks the container and CDP.
    await _run(
      asHermes('$remoteHermes hermuse computer start'),
      timeout: const Duration(minutes: 2),
    );
    result = await _run(
      asHermes('$remoteHermes hermuse computer status'),
      log: false,
    );
    if (parseRemoteComputerStatus(result.stdout)['state'] != 'running') {
      throw const RemoteInstallFailed(
        'computer',
        'The computer container did not become ready.',
      );
    }
    await _prove(computerHealthScript);
    await _run(_ownershipCheckpoint, log: false);
  }

  Future<void> _installWeb() async {
    final domain = _domain!;
    final webDomain = webAppDomain(domain);
    final image = _webImage!;
    // Docker and Python may only exist now; foreign containers and port
    // conflicts still stop before the first web mutation.
    _web = await _health(_webInventory(publish: true));
    if (_web == _RemoteHealth.ready) return;
    await _run(remoteOwnershipMutationScript({}, web: true), log: false);
    final pulled = await _run(
      'docker pull ${shellQuote(image)}',
      required: false,
      timeout: const Duration(minutes: 20),
    );
    if (pulled.exitCode != 0) {
      throw RemoteInstallFailed(
        'web',
        'The web app image $image could not be downloaded from ghcr.io. '
            'The server needs outbound HTTPS access to ghcr.io; retry once it '
            'is reachable.',
      );
    }
    _webToken = _randomSecret(32);
    await _run(
      webDeployScript(webDomain, domain, image),
      stdin: _webToken,
      timeout: const Duration(minutes: 5),
    );
    await _prove(_webInventory(publish: true));
    _web = _RemoteHealth.ready;
    await _run(_ownershipCheckpoint, log: false);
  }
}

/// The `version:` of the bundled plugin.yaml when it is a valid image tag.
/// The web app image is published under the plugin version it works with.
String? _bundledPluginVersion(Map<String, Uint8List> bundle) {
  final manifest = bundle['plugin.yaml'];
  if (manifest == null) return null;
  for (final line in const LineSplitter().convert(
    utf8.decode(manifest, allowMalformed: true),
  )) {
    final match = RegExp(r'^version:\s*(.*?)\s*$').firstMatch(line);
    if (match == null) continue;
    final version = match[1]!.replaceAll(RegExp(r'''["'\s]'''), '');
    return RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$').hasMatch(version)
        ? version
        : null;
  }
  return null;
}

String _randomSecret(int length) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return String.fromCharCodes(
    List.generate(
      length,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ),
  );
}

/// Derives sslip.io DNS only from a valid, public IPv4 address.
String sslipDomain(String address) {
  final parts = address.split('.');
  final octets = parts.map(int.tryParse).toList();
  if (parts.length != 4 ||
      octets.any((n) => n == null || n < 0 || n > 255) ||
      parts.asMap().entries.any((e) => '${octets[e.key]}' != e.value)) {
    throw const RemoteInstallFailed(
      'dashboard',
      'The server did not report a valid public IPv4 address.',
    );
  }
  final a = octets[0]!;
  final b = octets[1]!;
  if (a == 0 ||
      a == 10 ||
      a == 127 ||
      a >= 224 ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 100 && b >= 64 && b <= 127)) {
    throw const RemoteInstallFailed(
      'dashboard',
      'A public IPv4 address is required for sslip.io HTTPS.',
    );
  }
  return 'hermuse.${parts.join('-')}.sslip.io';
}

/// Conservatively skips rule changes only when both IP families already allow
/// each required TCP port. Other rules/default policies are never removed.
bool ufwAllowsPorts(String output, Set<int> ports) {
  if (!const LineSplitter().convert(output).contains('Status: active')) {
    return false;
  }
  final rule = RegExp(
    r'^(.+?)\s+(ALLOW|DENY|REJECT|LIMIT)(?:\s+(IN|OUT|FWD))?\s+(.+?)(?:\s+#.*)?$',
  );
  final allowed = <(int, bool), bool>{};
  for (final line in const LineSplitter().convert(output)) {
    final match = rule.firstMatch(line.trim());
    if (match == null || (match[3] != null && match[3] != 'IN')) continue;
    final target = match[1]!.replaceAll(' (v6)', '');
    for (final port in ports) {
      if (target != '$port/tcp' && target != '$port' && target != 'Anywhere') {
        continue;
      }
      final v6 = match[1]!.endsWith('(v6)');
      allowed.putIfAbsent(
        (port, v6),
        () =>
            match[2] == 'ALLOW' &&
            match[4]!.replaceAll(' (v6)', '') == 'Anywhere',
      );
    }
  }
  return ports.every(
    (port) => allowed[(port, false)] == true && allowed[(port, true)] == true,
  );
}

/// Reads the pretty-printed plugin CLI JSON after any Hermes banner lines.
Map<String, Object?> parseRemoteComputerStatus(String stdout) {
  for (
    var index = stdout.indexOf('{');
    index >= 0;
    index = stdout.indexOf('{', index + 1)
  ) {
    try {
      final value = jsonDecode(stdout.substring(index).trim());
      if (value is Map<String, Object?> && value['state'] is String) {
        return value;
      }
    } on FormatException {
      continue;
    }
  }
  throw const RemoteInstallFailed(
    'computer',
    'The computer command returned no valid status.',
  );
}

/// Checks real TLS, Hermes compatibility, authentication, plugin and computer
/// readiness from the installing computer, not merely from the server itself.
/// A published web app must also answer, know the dashboard and reach it
/// through its relay; it never receives the dashboard credential.
Future<void> verifyRemoteDashboard(
  RemoteInstallOutcome outcome,
  RemoteCancellation cancellation, {
  http.Client? client,
  Duration readyTimeout = const Duration(minutes: 4),
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async {
  final connection = _NoRedirectClient(client ?? http.Client());
  cancellation.addListener(connection.close);
  final base = Uri.parse(outcome.baseUrl);
  final web = outcome.webUrl == null ? null : Uri.parse(outcome.webUrl!);
  if (base.scheme != 'https' ||
      base.userInfo.isNotEmpty ||
      (web != null &&
          (web.scheme != 'https' ||
              web.userInfo.isNotEmpty ||
              !web.hasAuthority))) {
    connection.close();
    cancellation.removeListener(connection.close);
    throw const RemoteInstallFailed(
      'verify',
      'Remote dashboards and web apps must use HTTPS.',
    );
  }
  final rest = HermesRestClient(connection, baseUrl: base);
  Future<T> bounded<T>(Future<T> request) =>
      cancellation.bind(request.timeout(const Duration(seconds: 15)));
  try {
    final watch = Stopwatch()..start();
    late HermesStatus status;
    while (true) {
      cancellation.check();
      try {
        status = await bounded(rest.getStatus());
        break;
      } catch (_) {
        cancellation.check();
        if (watch.elapsed >= readyTimeout) rethrow;
        await cancellation.bind(sleep(const Duration(seconds: 3)));
      }
    }
    checkSupportedVersion(status.version);
    if (!status.authRequired || !status.authProviders.contains('basic')) {
      throw const RemoteInstallFailed(
        'verify',
        'The public dashboard is not protected by password login.',
      );
    }
    final unauthenticated = await bounded(
      connection.get(base.resolve('/api/plugins/hermuse/files')),
    );
    if (unauthenticated.statusCode != 401 &&
        unauthenticated.statusCode != 403) {
      throw const RemoteInstallFailed(
        'verify',
        'The public plugin API did not enforce authentication.',
      );
    }
    await bounded(
      rest.passwordLogin(
        username: outcome.username,
        password: outcome.password,
      ),
    );
    if (!rest.hasCookieSession) {
      throw const RemoteInstallFailed(
        'verify',
        'Dashboard login did not establish an authenticated session.',
      );
    }
    await bounded(rest.getJson('/api/plugins/hermuse/files'));
    final jobs = await bounded(rest.getJson('/api/plugins/hermuse/cron'));
    final registered = {
      for (final job in (jobs['jobs'] as List? ?? const []))
        if (job is Map && job['registered'] == true) job['key'],
    };
    if (!registered.containsAll(const {
      'feed',
      'ideas',
      'goals',
      'reflection',
    })) {
      throw const RemoteInstallFailed(
        'verify',
        'The Hermuse background jobs were not all registered.',
      );
    }
    final computer = await bounded(
      rest.getJson('/api/plugins/hermuse/computer/status'),
    );
    if (computer['state'] != 'running') {
      throw const RemoteInstallFailed(
        'verify',
        'The remote computer is not ready through the dashboard.',
      );
    }
    if (web != null) {
      await _verifyWebApp(
        connection,
        web,
        outcome.baseUrl,
        bounded,
        cancellation,
        readyTimeout: readyTimeout,
        sleep: sleep,
      );
    }
  } finally {
    cancellation.removeListener(connection.close);
    connection.close();
  }
}

Future<void> _verifyWebApp(
  http.Client connection,
  Uri web,
  String dashboardUrl,
  Future<T> Function<T>(Future<T>) bounded,
  RemoteCancellation cancellation, {
  required Duration readyTimeout,
  required Future<void> Function(Duration) sleep,
}) async {
  final address = 'https://${web.authority}';
  Uri at(List<String> segments, [Map<String, String>? query]) => Uri(
    scheme: 'https',
    host: web.host,
    port: web.hasPort ? web.port : null,
    pathSegments: segments,
    queryParameters: query,
  );
  Future<Map<String, Object?>> json(Uri uri, String failure) async {
    final response = await bounded(connection.get(uri));
    final Object? body;
    try {
      body = response.statusCode == 200 ? jsonDecode(response.body) : null;
    } on FormatException {
      throw RemoteInstallFailed(
        'verify',
        'The web app at $address $failure (invalid response).',
      );
    }
    if (body is! Map<String, Object?>) {
      throw RemoteInstallFailed(
        'verify',
        'The web app at $address $failure (HTTP ${response.statusCode}).',
      );
    }
    return body;
  }

  // Its certificate is issued independently of the dashboard's.
  final watch = Stopwatch()..start();
  while (true) {
    cancellation.check();
    try {
      final health = await json(
        at(['relay', 'health']),
        'did not report healthy',
      );
      if (health['ok'] != true) {
        throw RemoteInstallFailed(
          'verify',
          'The web app at $address did not report healthy.',
        );
      }
      break;
    } catch (_) {
      cancellation.check();
      if (watch.elapsed >= readyTimeout) rethrow;
      await cancellation.bind(sleep(const Duration(seconds: 3)));
    }
  }
  final resolved = await json(
    at(['relay', 'resolve'], {'url': dashboardUrl}),
    'does not know the dashboard $dashboardUrl',
  );
  final id = resolved['id'];
  if (id is! String || id.isEmpty) {
    throw RemoteInstallFailed(
      'verify',
      'The web app at $address does not know the dashboard $dashboardUrl.',
    );
  }
  await json(
    at(['hermes', id, 'api', 'status']),
    'could not reach the dashboard through its relay',
  );
}

/// A provisioning credential is never forwarded to a redirect target.
final class _NoRedirectClient extends http.BaseClient {
  _NoRedirectClient(this._inner);
  final http.Client _inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
