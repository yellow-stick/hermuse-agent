@TestOn('linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:hermuse_host/src/errors.dart';
import 'package:hermuse_host/src/linux_service_helper.dart';
import 'package:hermuse_host/src/remote_scripts.dart';
import 'package:test/test.dart';

void main() {
  for (final arguments in [
    ['exec', '/usr/bin/touch', 'not-authorized'],
    ['install'],
  ]) {
    test(
      'helper rejects unauthorized invocation $arguments and closes open IPC',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'hermuse-helper-rejection-',
        );
        addTearDown(() => temporary.delete(recursive: true));
        final entrypoint = File('${temporary.path}/helper.dart');
        await entrypoint.writeAsString("""
import 'dart:io';
import 'package:hermuse_host/src/linux_service_helper.dart';
Future<void> main(List<String> arguments) async {
  exitCode = await runLinuxServiceHelper(arguments, const []);
}
""");
        final packageConfig = await Isolate.packageConfig;
        final process = await Process.start(
          Platform.resolvedExecutable,
          [
            '--packages=${File.fromUri(packageConfig!).path}',
            entrypoint.path,
            ...arguments,
          ],
          environment: const {
            'PATH': '/usr/bin:/bin',
            'HOME': '/root',
            'PKEXEC_UID': '0',
          },
          includeParentEnvironment: false,
        );
        // Deliberately leave stdin open. A rejected operation must still exit.
        final output = process.stdout.transform(utf8.decoder).join();
        final diagnostics = process.stderr.transform(utf8.decoder).join();
        expect(await process.exitCode.timeout(const Duration(seconds: 20)), 1);
        final event = jsonDecode((await output).trim()) as Map;
        expect(event['event'], 'error');
        expect(await diagnostics, isEmpty);
        await process.stdin.close();
      },
    );
  }

  test(
    'command adapter captures both outputs without inheriting caller HOME',
    () async {
      final shell = LinuxRootShell();
      final result = await shell.run(
        r'printf "%s\n" "$HOME"; printf diagnostic >&2',
      );
      expect(result.stdout.trim(), '/root');
      expect(result.stderr.trim(), 'diagnostic');
      expect(result.exitCode, 0);
      shell.close();
      await shell.shutdown;
    },
  );

  test(
    'close allows current transaction to finish and refuses new work',
    () async {
      final shell = LinuxRootShell();
      final started = Completer<void>();
      final operation = shell.run(
        'printf "started\\n"; sleep 0.15; printf "committed\\n"',
        onLine: (line) {
          if (line == 'started') started.complete();
        },
      );
      await started.future;
      shell.close();
      final result = await operation;
      await shell.shutdown;
      expect(result.stdout, contains('committed'));
      await expectLater(
        shell.run('true'),
        throwsA(isA<RemoteInstallCancelled>()),
      );
    },
  );

  test('a timed-out command is reaped only after safe completion', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'hermuse-safe-timeout-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final marker = File('${temporary.path}/committed');
    final shell = LinuxRootShell();
    await expectLater(
      shell.run(
        'sleep 0.05; printf committed > ${shellQuote(marker.path)}',
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(await marker.readAsString(), 'committed');
    shell.close();
    await shell.shutdown;
  });

  test('control holder is concurrent, excluded from idle, and reaped on close', () async {
    final shell = LinuxRootShell();
    final ready = Completer<void>();
    // This is a control-only process fixture, not an operation on system paths.
    final holder = shell.holdOperation(
      'bash -c ${shellQuote("trap 'exit 0' TERM; printf 'ready\\n'; while :; do sleep 0.05; done")}',
      timeout: const Duration(seconds: 10),
      onLine: (line) {
        if (line == 'ready') ready.complete();
      },
    );
    await ready.future;
    await shell.idle;
    final result = await shell.run('printf mutation');
    expect(result.stdout.trim(), 'mutation');
    shell.close();
    await shell.shutdown;
    await holder;
  });

  test(
    'control holder shuts down despite verifier-inherited ignored TERM',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'hermuse-control-signals-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final entrypoint = File('${temporary.path}/control.dart');
      await entrypoint.writeAsString(r'''
import 'dart:async';
import 'package:hermuse_host/src/linux_service_helper.dart';
import 'package:hermuse_host/src/remote_scripts.dart';
Future<void> main() async {
  final shell = LinuxRootShell();
  final ready = Completer<void>();
  final holder = shell.holdOperation(
    'bash -c ${shellQuote("trap 'exit 0' TERM; printf 'ready\\n'; while :; do sleep 0.05; done")}',
    timeout: const Duration(seconds: 10),
    onLine: (line) { if (line == 'ready') ready.complete(); },
  );
  await ready.future;
  shell.close();
  await shell.shutdown;
  await holder;
  print('closed');
}
''');
      final packageConfig = await Isolate.packageConfig;
      final result = await Process.run('/usr/bin/timeout', [
        '--signal=KILL',
        '15s',
        '/usr/bin/env',
        '--ignore-signal=TERM',
        Platform.resolvedExecutable,
        '--packages=${File.fromUri(packageConfig!).path}',
        entrypoint.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect((result.stdout as String).trim(), 'closed');
    },
  );

  test(
    'upload boundary refuses traversal and non-staging destinations',
    () async {
      final shell = LinuxRootShell();
      for (final path in [
        '/etc/passwd',
        '/tmp/plugin.py',
        '/var/lib/hermuse-provision/run/../passwd',
        '/var/lib/hermuse-provision/run/plugin/file\n',
      ]) {
        await expectLater(
          shell.writeFile(path, Uint8List.fromList([1])),
          throwsFormatException,
        );
      }
      await expectLater(
        shell.writeFile(
          '/var/lib/hermuse-provision/run/plugin/file',
          Uint8List(0),
          mode: 511,
        ),
        throwsFormatException,
      );
      shell.close();
      await shell.shutdown;
    },
  );
}
