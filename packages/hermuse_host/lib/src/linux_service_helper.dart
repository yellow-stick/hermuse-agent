import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';
import 'linux_migration.dart';
import 'linux_service_protocol.dart';
import 'remote_install.dart';
import 'remote_scripts.dart';
import 'remote_shell.dart';
import 'remote_uninstall.dart';

const _systemEnvironment = {
  'PATH': '/usr/sbin:/usr/bin:/sbin:/bin',
  'HOME': '/root',
  'LANG': 'C.UTF-8',
  'LC_ALL': 'C.UTF-8',
};

/// Root-side adapter only. It is never exposed through the desktop IPC protocol.
/// Cancellation and timeouts never kill a package manager mid-transaction.
final class LinuxRootShell implements RemoteOperationHolderShell {
  var _closed = false;
  Completer<void>? _busy;
  int? _callerUid;
  Future<Process?>? _holderReady;
  Completer<void>? _holderDone;
  Future<void>? _shutdown;

  Future<void> get idle => _busy?.future ?? Future<void>.value();

  Future<void> get shutdown => _shutdown ?? Future<void>.value();

  Future<Process> _start(String command, {bool control = false}) =>
      Process.start(
        control ? '/usr/bin/env' : '/bin/bash',
        [
          if (control) ...['--default-signal=TERM', '/bin/bash'],
          '-c',
          command,
        ],
        workingDirectory: '/',
        environment: {
          ..._systemEnvironment,
          if (_callerUid case final uid?) 'PKEXEC_UID': '$uid',
        },
        includeParentEnvironment: false,
      );

  @override
  Future<RemoteResult> holdOperation(
    String command, {
    required Duration timeout,
    required void Function(String line) onLine,
  }) async {
    if (_closed) throw const RemoteInstallCancelled();
    if (_holderDone != null) {
      throw StateError('An operation holder already exists.');
    }
    final done = _holderDone = Completer<void>();
    final ready = Completer<Process?>();
    _holderReady = ready.future;
    try {
      // The verifier deliberately ignores signals for package transactions.
      // Reset TERM only for the control holder, then acknowledge that reset
      // before close() can signal it, including cancellation during startup.
      final process = await _start(
        'printf "HERMUSE_CONTROL_READY_V1\\n"; exec $command',
        control: true,
      );
      return await _collect(
        process,
        timeout: timeout,
        onLine: (line) {
          if (line == 'HERMUSE_CONTROL_READY_V1') {
            if (!ready.isCompleted) ready.complete(process);
          } else {
            onLine(line);
          }
        },
      );
    } finally {
      if (!ready.isCompleted) ready.complete(null);
      done.complete();
    }
  }

  @override
  Future<RemoteResult> run(
    String command, {
    String? stdin,
    Duration timeout = const Duration(minutes: 10),
    void Function(String line)? onLine,
  }) async {
    if (_closed) throw const RemoteInstallCancelled();
    if (_busy != null) {
      throw StateError('Concurrent root commands are not allowed.');
    }
    final busy = _busy = Completer<void>();
    try {
      return await _collect(
        await _start(command),
        stdin: stdin,
        timeout: timeout,
        onLine: onLine,
      );
    } finally {
      _busy = null;
      busy.complete();
    }
  }

  Future<RemoteResult> _collect(
    Process process, {
    String? stdin,
    required Duration timeout,
    void Function(String line)? onLine,
  }) async {
    final elapsed = Stopwatch()..start();
    final out = _HelperOutputTail();
    final err = _HelperOutputTail();
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          out.add(line);
          onLine?.call(line);
        });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          err.add(line);
          onLine?.call(line);
        });
    Object? inputError;
    try {
      if (stdin != null) process.stdin.write(stdin);
      await process.stdin.close();
    } catch (error) {
      inputError = error;
    }
    final code = await process.exitCode;
    await Future.wait([stdoutDone, stderrDone]);
    if (elapsed.elapsed > timeout) {
      throw TimeoutException(
        'The system command exceeded its time limit; it was allowed to finish safely.',
        timeout,
      );
    }
    if (inputError != null && code == 0) {
      throw const FileSystemException(
        'The system command did not accept its input.',
      );
    }
    return RemoteResult(stdout: out.text, stderr: err.text, exitCode: code);
  }

  @override
  Future<void> writeFile(String path, Uint8List bytes, {int mode = 384}) async {
    // Only fresh files in the engine's root-owned private staging directory.
    // Python walks with directory FDs/O_NOFOLLOW and creates O_EXCL, so an
    // installed service user cannot substitute a symlink at any path component.
    if (!RegExp(
          r'^/var/lib/hermuse-provision/[a-zA-Z0-9_-]+(?:/[a-zA-Z0-9_.-]+)+$',
        ).hasMatch(path) ||
        path.split('/').any((part) => part == '..' || part == '.') ||
        (mode != 384 && mode != 448 && mode != 420 && mode != 493)) {
      throw const FormatException('Unsafe privileged upload destination.');
    }
    final source =
        '''import base64, json, os, stat
path, mode, data = json.loads(${jsonEncode(jsonEncode([path, mode, base64Encode(bytes)]))})
fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
try:
    parts = path.strip('/').split('/')
    for part in parts[:-1]:
        nextfd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
        os.close(fd)
        fd = nextfd
        info = os.fstat(fd)
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise RuntimeError('Unsafe upload parent')
    target = os.open(parts[-1], os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=fd)
    with os.fdopen(target, 'wb') as stream:
        stream.write(base64.b64decode(data, validate=True))
        stream.flush()
        os.fsync(stream.fileno())
finally:
    os.close(fd)
''';
    final result = await run('/usr/bin/python3 -I -', stdin: source);
    if (result.exitCode != 0) {
      throw const FileSystemException('Safe helper upload failed.');
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _shutdown = () async {
      await idle;
      final holder = await _holderReady;
      // This is only the control-only lock/watchdog process, never a mutator.
      holder?.kill(ProcessSignal.sigterm);
      await _holderDone?.future;
    }();
  }
}

final class _HelperOutputTail {
  var _buffer = StringBuffer();
  void add(String line) {
    _buffer.writeln(line);
    if (_buffer.length > 2 * 1024 * 1024) {
      final value = _buffer.toString();
      _buffer = StringBuffer(value.substring(value.length - 1024 * 1024));
    }
  }

  String get text => _buffer.toString();
}

/// Resolves the authenticated caller from passwd, never from HOME or JSON input.
Future<({int uid, String home})> linuxServiceCaller({
  required bool privileged,
}) async {
  final identity = await Process.run(
    '/usr/bin/id',
    ['-u'],
    environment: _systemEnvironment,
    includeParentEnvironment: false,
  );
  final currentUid = int.tryParse('${identity.stdout}'.trim());
  final suppliedUid = Platform.environment['PKEXEC_UID'];
  if (privileged &&
      (currentUid != 0 ||
          suppliedUid == null ||
          !RegExp(r'^[0-9]+$').hasMatch(suppliedUid))) {
    throw const FormatException('Administrator authorization is required.');
  }
  final uid = privileged ? int.tryParse(suppliedUid!) : currentUid;
  if (uid == null || uid <= 0) {
    throw const FormatException('A desktop caller is required.');
  }
  final passwd = await Process.run(
    '/usr/bin/getent',
    ['passwd', '$uid'],
    environment: _systemEnvironment,
    includeParentEnvironment: false,
  );
  final records = '${passwd.stdout}'.trim().split('\n');
  final fields = records.single.split(':');
  if (passwd.exitCode != 0 ||
      fields.length != 7 ||
      fields[2] != '$uid' ||
      !fields[5].startsWith('/') ||
      fields[5] == '/' ||
      fields[5].contains(RegExp(r'[\x00-\x1f]'))) {
    throw const FormatException('Cannot resolve the desktop account.');
  }
  return (uid: uid, home: fields[5]);
}

/// Called by the generated, compiled entrypoint containing immutable plugin bytes.
Future<int> runLinuxServiceHelper(
  List<String> arguments,
  List<int> embeddedPlugin,
) async {
  final inputs = StreamIterator(serviceLines(stdin));
  final signals = <StreamSubscription<ProcessSignal>>[];
  final shell = LinuxRootShell();
  final installer = RemoteInstaller();
  final uninstaller = RemoteUninstaller();
  var connected = true;
  var cancelling = false;
  Future<void> cancel() async {
    if (cancelling) return;
    cancelling = true;
    await shell.idle;
    await Future.wait([installer.cancel(), uninstaller.cancel()]);
  }

  void emit(Map<String, Object?> value) {
    if (connected) stdout.writeln(jsonEncode(value));
  }

  unawaited(
    stdout.done.catchError((Object _) {
      connected = false;
      unawaited(cancel());
    }),
  );
  try {
    if (!Platform.isLinux || arguments.length != 1) {
      throw const FormatException('Exactly one fixed helper mode is required.');
    }
    final mode = LinuxServiceMode.values.byName(arguments.single);
    if (mode != LinuxServiceMode.inspect &&
        (stdin.hasTerminal || stdout.hasTerminal)) {
      throw const FormatException(
        'The privileged helper requires private IPC pipes.',
      );
    }
    final caller = await linuxServiceCaller(
      privileged: mode != LinuxServiceMode.inspect,
    );
    shell._callerUid = caller.uid;
    if (!await inputs.moveNext()) {
      throw const FormatException('Missing operation request.');
    }
    final request = LinuxServiceRequest.parse(
      mode,
      inputs.current,
      callerHome: caller.home,
    );
    final legacyHome = request.legacyHome ?? '${caller.home}/.hermes';
    final canonical = await shell.run(canonicalInstancePresentScript);
    if (canonical.exitCode != 0 ||
        !{
          'HERMUSE_CANONICAL_PRESENT_V1',
          'HERMUSE_CANONICAL_ABSENT_V1',
        }.contains(canonical.stdout.trim())) {
      throw const FormatException(
        'The canonical service could not be inspected safely.',
      );
    }
    final canonicalPresent =
        canonical.stdout.trim() == 'HERMUSE_CANONICAL_PRESENT_V1';
    for (final signal in [
      ProcessSignal.sigint,
      ProcessSignal.sigterm,
      ProcessSignal.sighup,
    ]) {
      signals.add(
        signal.watch().listen((_) {
          unawaited(cancel());
        }),
      );
    }
    unawaited(() async {
      try {
        while (await inputs.moveNext()) {
          if (inputs.current != '{"cancel":true}') {
            throw const FormatException('Invalid control message.');
          }
          await cancel();
        }
      } catch (_) {
        await cancel();
      }
    }());
    if (cancelling) throw const RemoteInstallCancelled();
    if (mode == LinuxServiceMode.inspect) {
      final legacy = canonicalPresent
          ? null
          : await _inspectLegacy(shell, caller.uid, caller.home, legacyHome);
      var legacyPresent = legacy != null;
      if (canonicalPresent) {
        for (final source in {legacyHome, '${caller.home}/.hermes'}) {
          if (await FileSystemEntity.type(source, followLinks: false) !=
              FileSystemEntityType.notFound) {
            legacyPresent = true;
          }
        }
      }
      bool? authRequired;
      bool? schedulerReady;
      if (canonicalPresent) {
        final status = await shell.run(inspectDashboardAuthenticationScript);
        if (status.exitCode == 0) {
          authRequired = switch (status.stdout.trim()) {
            'HERMUSE_DASHBOARD_LOGIN_V1' => true,
            'HERMUSE_DASHBOARD_TOKEN_V1' => false,
            _ => null,
          };
        }
        final scheduler = await shell.run(schedulerServiceStatusScript);
        if (scheduler.exitCode == 0) {
          schedulerReady = switch (scheduler.stdout.trim()) {
            'HERMUSE_HEALTH_V1:ready' => true,
            'HERMUSE_HEALTH_V1:repair' => false,
            _ => null,
          };
        }
      }
      emit({
        'event': 'inspection',
        'canonicalPresent': canonicalPresent,
        'authRequired': authRequired,
        'schedulerReady': schedulerReady,
        'legacyPresent': legacyPresent,
        'legacy': legacy,
      });
    } else if (mode == LinuxServiceMode.connect) {
      await for (final event in installer.connectLocal(shell: shell)) {
        final value = serviceInstallEvent(event);
        if (value != null) emit(value);
      }
    } else if (mode == LinuxServiceMode.install) {
      final legacy = canonicalPresent
          ? null
          : await _inspectLegacy(shell, caller.uid, caller.home, legacyHome);
      if (legacy != null && request.migration == null && !canonicalPresent) {
        throw const FormatException(
          'Legacy Hermes data requires explicit migration confirmation.',
        );
      }
      if (cancelling) throw const RemoteInstallCancelled();
      final bundle = serviceObject(
        jsonDecode(utf8.decode(gzip.decode(embeddedPlugin))),
      );
      final plugin = <String, Uint8List>{};
      for (final entry in bundle.entries) {
        if (entry.key.startsWith('/') ||
            entry.key
                .split('/')
                .any((part) => part.isEmpty || part == '..' || part == '.')) {
          throw const FormatException('Invalid embedded plugin path.');
        }
        plugin[entry.key] = base64Decode(entry.value as String);
      }
      await for (final event in installer.runLocal(
        shell: shell,
        pluginBundle: plugin,
        legacyHome: legacy?['sourceHome'] as String? ?? legacyHome,
        migrationRevision: request.migration?.revision,
      )) {
        final value = serviceInstallEvent(event);
        if (value != null) emit(value);
      }
    } else if (mode == LinuxServiceMode.inspectUninstall) {
      final inventory = await uninstaller.inspectLocal(shell: shell);
      emit({
        'event': 'inventory',
        'inventory': serviceInventoryJson(inventory),
      });
    } else {
      // Never trust a resource list from the desktop; reconstruct only the
      // connection-bound revision. The shared recipe inventories again under lock.
      await for (final event in uninstaller.runLocal(
        shell: shell,
        inventory: RemoteUninstallInventory(
          resources: const [],
          revision: request.revision!,
          host: 'localhost',
        ),
        purge: request.purge,
      )) {
        final value = serviceUninstallEvent(event);
        if (value != null) emit(value);
      }
    }
    emit({'event': 'done'});
    await stdout.flush();
    return 0;
  } catch (error) {
    // Do not serialize exception objects: third-party stderr can include tokens.
    emit(serviceFailureEvent(error));
    await stdout.flush().catchError((Object _) {});
    return 1;
  } finally {
    shell.close();
    await shell.shutdown;
    await inputs.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
  }
}

Future<Map<String, Object?>?> _inspectLegacy(
  LinuxRootShell shell,
  int uid,
  String callerHome,
  String selected,
) async {
  for (final source in {selected, '$callerHome/.hermes'}) {
    final validation = await shell.run(
      '/usr/bin/python3 -I -',
      stdin:
          '''
import json, os, stat
source, uid = json.loads(${jsonEncode(jsonEncode([source, uid]))})
try:
    info = os.lstat(source)
    if info.st_uid != uid or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError('Legacy path is not an ordinary caller-owned directory')
except FileNotFoundError:
    pass
''',
    );
    if (validation.exitCode != 0) {
      throw const FormatException(
        'Legacy Hermes data must be an ordinary directory owned by your desktop account.',
      );
    }
    final result = await shell.run(inspectLegacyHermesScript(source));
    if (result.exitCode != 0) {
      throw FormatException(
        serviceMigrationRefusal(result.stderr) ?? 'Legacy data could not be safely inspected. Stop legacy Hermes processes and check directory ownership before retrying.',
      );
    }
    final value = jsonDecode(result.stdout.trim());
    if (value != null) return serviceObject(value);
  }
  return null;
}
