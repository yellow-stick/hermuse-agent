import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'errors.dart';
import 'host_environment.dart';
import 'linux_migration.dart';
import 'linux_service_protocol.dart';
import 'remote_install.dart';
import 'remote_uninstall.dart';

const linuxServiceHelperSha256 = String.fromEnvironment(
  'HERMUSE_LINUX_SERVICE_SHA256',
);

/// Copies once into root-only storage, verifies that snapshot, then executes it.
/// No caller-provided code, environment, asset path or shell command reaches the
/// compiled helper. Signals cannot interrupt an in-flight package transaction.
const linuxServicePrivilegeVerifier = r'''set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077
cd / || exit 90
trap '' HUP INT QUIT TERM
[ "$#" -eq 3 ] || exit 90
expected=$1
source=$2
mode=$3
case $mode in connect|install|inspectUninstall|uninstall) ;; *) exit 90 ;; esac
case $expected in *[!0-9a-f]*) exit 90 ;; esac
[ "${#expected}" -eq 64 ] || exit 90
case $source in /*) ;; *) exit 90 ;; esac
# /run is commonly mounted noexec; the verified ELF must remain executable.
dir=$(mktemp -d /var/lib/hermuse-service-verify.XXXXXXXXXX) || exit 91
trap 'rm -rf -- "$dir"' EXIT
copy=$dir/hermuse-linux-service
[ -f "$source" ] || exit 92
head -c 67108865 -- "$source" > "$copy" || exit 92
size=$(wc -c < "$copy") || exit 92
[ "$size" -le 67108864 ] || exit 92
actual=$(sha256sum < "$copy") || exit 92
[ "${actual%% *}" = "$expected" ] || exit 93
chmod 0700 "$copy" || exit 92
"$copy" "$mode"
''';

/// A release-bound executable; plugin bytes are inside this same executable.
final class LinuxServiceHelper {
  const LinuxServiceHelper._(this.path, this.sha256);

  factory LinuxServiceHelper.bundled({
    String? executableDir,
    String compiledSha256 = linuxServiceHelperSha256,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(compiledSha256)) {
      throw const LinuxSetupUnavailable(
        'This build has no trusted system-service helper digest.',
      );
    }
    final directory =
        executableDir ?? File(Platform.resolvedExecutable).parent.path;
    return LinuxServiceHelper._(
      File('$directory/libexec/hermuse-linux-service').absolute.path,
      compiledSha256,
    );
  }

  /// Explicit development opt-in; the executable must first be built with
  /// `dart run tool/build_linux_service.dart` in the host package.
  static Future<LinuxServiceHelper> fromWorkspace(
    String root, {
    String compiledSha256 = linuxServiceHelperSha256,
  }) async {
    if (const bool.fromEnvironment('dart.vm.product') ||
        compiledSha256.isNotEmpty) {
      throw const LinuxSetupUnavailable(
        'Workspace helpers are development-only.',
      );
    }
    final file = File(
      '$root/packages/hermuse_host/build/linux-service/hermuse-linux-service',
    ).absolute;
    if (!await file.exists()) {
      throw const LinuxSetupUnavailable(
        'Build the development service helper with '
        'dart run tool/build_linux_service.dart in packages/hermuse_host.',
      );
    }
    return LinuxServiceHelper._(
      file.path,
      '${await crypto.sha256.bind(file.openRead()).first}',
    );
  }

  final String path;
  final String sha256;
}

/// Read-only discovery does not display an authorization dialog.
final class LinuxServiceInspection {
  const LinuxServiceInspection({
    required this.canonicalPresent,
    this.legacy,
    this.legacyPresent = false,
    this.authRequired,
    this.schedulerReady,
  });
  final bool canonicalPresent;
  final LegacyHermesMigration? legacy;
  final bool legacyPresent;

  /// Whether the existing loopback dashboard requires its normal login flow.
  /// Null means its read-only status could not be safely inspected.
  final bool? authRequired;

  /// Whether the canonical scheduler (Hermes gateway) service is the exact
  /// installed unit, enabled and running; false means setup must repair it.
  /// Null when no canonical service exists or its state could not be read.
  final bool? schedulerReady;
}

typedef LinuxServiceProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
);

/// Desktop client for the bounded, digest-verified canonical-service helper.
///
/// The desktop never supervises or terminates the system service. Successful
/// credentials are returned only in memory for the caller's SecretStore save.
final class LinuxServiceInstaller {
  LinuxServiceInstaller({
    required this._helper,
    LinuxServiceProcessStarter? startProcess,
    Map<String, String>? environment,
  }) : _start = startProcess ?? _startProcess,
       _environment = environment ?? hostEnvironment();

  static LinuxServiceInstaller system({String? workspaceRoot}) =>
      LinuxServiceInstaller(
        helper: () async =>
            workspaceRoot != null && linuxServiceHelperSha256.isEmpty
            ? LinuxServiceHelper.fromWorkspace(workspaceRoot)
            : LinuxServiceHelper.bundled(),
      );

  final Future<LinuxServiceHelper> Function() _helper;
  final LinuxServiceProcessStarter _start;
  final Map<String, String> _environment;
  Process? _process;
  Completer<void>? _stopped;
  var _cancelRequested = false;

  Future<LinuxServiceInspection> inspect() async {
    final frames = await _invoke(LinuxServiceMode.inspect, {
      'legacyHome': _environment['HERMES_HOME'],
    }, privileged: false).toList();
    if (frames.length != 1 || frames.single['event'] != 'inspection') {
      throw const FormatException('Missing service inspection.');
    }
    final value = frames.single;
    return LinuxServiceInspection(
      canonicalPresent: value['canonicalPresent'] as bool,
      legacyPresent: value['legacyPresent'] as bool? ?? value['legacy'] != null,
      authRequired: value['authRequired'] as bool?,
      schedulerReady: value['schedulerReady'] as bool?,
      legacy: value['legacy'] == null
          ? null
          : LegacyHermesMigration.fromJson(serviceObject(value['legacy'])),
    );
  }

  Stream<RemoteInstallProgress> run({LegacyHermesMigration? migration}) =>
      _invoke(LinuxServiceMode.install, {
        'migration': migration?.toJson(),
        'legacyHome': migration?.sourceHome ?? _environment['HERMES_HOME'],
      }).map(serviceInstallFromJson);

  /// Authorizes private access to a proven existing service without installing.
  Stream<RemoteInstallProgress> connect() =>
      _invoke(LinuxServiceMode.connect, const {}).map(serviceInstallFromJson);

  Future<RemoteUninstallInventory> inspectUninstall() async {
    final frames = await _invoke(
      LinuxServiceMode.inspectUninstall,
      const {},
    ).toList();
    if (frames.length != 1 || frames.single['event'] != 'inventory') {
      throw const FormatException('Missing removal inventory.');
    }
    return serviceInventoryFromJson(serviceObject(frames.single['inventory']));
  }

  Stream<RemoteUninstallProgress> uninstall({
    required RemoteUninstallInventory inspection,
    bool deleteAll = false,
  }) => _invoke(LinuxServiceMode.uninstall, {
    'revision': inspection.revision,
    'purge': deleteAll,
  }).map(serviceUninstallFromJson);

  /// Requests a stop at a safe command boundary and waits for the helper.
  /// Neither pkexec nor its subprocesses are ever killed.
  Future<void> cancel() async {
    _cancelRequested = true;
    _sendCancel();
    await _stopped?.future;
  }

  void _sendCancel() {
    final process = _process;
    if (process == null) return;
    try {
      process.stdin.writeln('{"cancel":true}');
      unawaited(process.stdin.flush().catchError((Object _) {}));
    } on StateError {
      // A completed helper may have closed the IPC stream already.
    }
  }

  Stream<Map<String, Object?>> _invoke(
    LinuxServiceMode mode,
    Map<String, Object?> request, {
    bool privileged = true,
  }) {
    if (_stopped != null) {
      throw StateError('A service operation is already running.');
    }
    final stopped = _stopped = Completer<void>();
    _cancelRequested = false;
    late final StreamController<Map<String, Object?>> output;
    output = StreamController<Map<String, Object?>>(
      onCancel: () {
        _cancelRequested = true;
        _sendCancel();
      },
      onListen: () async {
        try {
          final helper = await _helper();
          final environment = <String, String>{
            'PATH': '/usr/sbin:/usr/bin:/sbin:/bin',
            for (final name in [
              'DISPLAY',
              'WAYLAND_DISPLAY',
              'XAUTHORITY',
              'DBUS_SESSION_BUS_ADDRESS',
              'XDG_RUNTIME_DIR',
              'LANG',
            ])
              name: ?_environment[name],
          };
          if (!privileged) {
            final digest = await crypto.sha256
                .bind(File(helper.path).openRead())
                .first;
            if ('$digest' != helper.sha256) {
              throw const LinuxSetupUnavailable(
                'The service helper digest does not match.',
              );
            }
          }
          final process = _process = await _start(
            privileged ? '/usr/bin/pkexec' : helper.path,
            privileged
                ? [
                    '--disable-internal-agent',
                    '/usr/bin/sh',
                    '-c',
                    linuxServicePrivilegeVerifier,
                    'hermuse-service-verify',
                    helper.sha256,
                    helper.path,
                    mode.name,
                  ]
                : [mode.name],
            environment,
          );
          unawaited(process.stdin.done.catchError((Object _) {}));
          process.stdin.writeln(jsonEncode(request));
          if (_cancelRequested) _sendCancel();
          // stderr is deliberately discarded: authorization or third-party
          // diagnostics must not become a credential-bearing application log.
          final stderrDone = process.stderr.drain<void>();
          var completed = false;
          Map<String, Object?>? terminal;
          Object? protocolError;
          final expectedTerminal = switch (mode) {
            LinuxServiceMode.inspect => 'inspection',
            LinuxServiceMode.install || LinuxServiceMode.connect => 'installed',
            LinuxServiceMode.inspectUninstall => 'inventory',
            LinuxServiceMode.uninstall => 'uninstalled',
          };
          try {
            await for (final line in serviceLines(process.stdout)) {
              if (protocolError != null) continue;
              try {
                final value = serviceObject(jsonDecode(line));
                if (completed) {
                  throw const FormatException('Output after completion.');
                }
                if (value['event'] == 'error') {
                  throw RemoteInstallFailed(
                    value['step'] as String? ?? 'service',
                    value['message'] as String,
                  );
                }
                if (value['event'] == 'done') {
                  if (terminal == null) {
                    throw const FormatException('Missing helper result.');
                  }
                  completed = true;
                } else if (value['event'] == expectedTerminal) {
                  if (terminal != null) {
                    throw const FormatException('Repeated helper result.');
                  }
                  terminal = value;
                } else {
                  if (terminal != null ||
                      (mode != LinuxServiceMode.install &&
                          mode != LinuxServiceMode.connect &&
                          mode != LinuxServiceMode.uninstall)) {
                    throw const FormatException('Unexpected helper event.');
                  }
                  if (value['event'] != 'started' &&
                      value['event'] != 'finished') {
                    throw const FormatException('Unexpected helper event.');
                  }
                  final step = value['step'] as String;
                  if (mode == LinuxServiceMode.install ||
                      mode == LinuxServiceMode.connect) {
                    RemoteInstallStep.values.byName(step);
                    if (value['event'] == 'finished' &&
                        value['reused'] is! bool) {
                      throw const FormatException('Invalid stage result.');
                    }
                  } else {
                    RemoteUninstallStep.values.byName(step);
                  }
                  output.add(value);
                }
              } catch (error) {
                protocolError = error is RemoteInstallFailed
                    ? error
                    : const FormatException(
                        'Invalid system-service helper response.',
                      );
              }
            }
          } catch (_) {
            protocolError ??= const FormatException(
              'Invalid system-service helper response.',
            );
          }
          final code = await process.exitCode;
          await stderrDone;
          if (protocolError != null) throw protocolError;
          if (code != 0 || !completed) {
            throw RemoteInstallFailed('service', switch (code) {
              126 => 'Administrator authorization was cancelled.',
              127 => 'Administrator authorization was denied or unavailable.',
              93 =>
                'The service helper digest does not match this application.',
              _ => 'The system-service helper did not complete (exit $code).',
            });
          }
          // Credentials/removal success only reach callers after the final frame
          // AND a successful process exit, never from a partial IPC transcript.
          output.add(terminal!);
        } catch (error, stack) {
          output.addError(error, stack);
        } finally {
          final process = _process;
          _process = null;
          if (process != null) {
            unawaited(process.stdin.close().catchError((Object _) {}));
          }
          _stopped = null;
          stopped.complete();
          await output.close();
        }
      },
    );
    return output.stream;
  }

  static Future<Process> _startProcess(
    String executable,
    List<String> arguments,
    Map<String, String> environment,
  ) => Process.start(
    executable,
    arguments,
    environment: environment,
    includeParentEnvironment: false,
  );
}
