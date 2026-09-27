import 'dart:async';
import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

/// Writes a tiny Dart child script printing [lines] then sleeping, and
/// returns its path. The supervisor spawns it via [Platform.resolvedExecutable].
Future<String> _writeChild(
  Directory dir,
  String name,
  List<String> lines, {
  int exitCode = 0,
  int sleepSeconds = 30,
}) async {
  final file = File('${dir.path}/$name.dart');
  await file.writeAsString('''
import 'dart:io';
Future<void> main() async {
  ${lines.map((l) => "print(${_quote(l)});").join('\n  ')}
  await stdout.flush();
  ${exitCode == -1 ? 'await Future<void>.delayed(Duration(seconds: $sleepSeconds));' : 'exit($exitCode);'}
}
''');
  return file.path;
}

String _quote(String s) => "'${s.replaceAll("'", "\\'")}'";

void main() {
  group('supervisorBackoff', () {
    test('grows exponentially and caps at 30s', () {
      expect(supervisorBackoff(0), const Duration(seconds: 1));
      expect(supervisorBackoff(1), const Duration(seconds: 2));
      expect(supervisorBackoff(2), const Duration(seconds: 4));
      expect(supervisorBackoff(4), const Duration(seconds: 16));
      expect(supervisorBackoff(5), const Duration(seconds: 30));
      expect(supervisorBackoff(99), const Duration(seconds: 30));
    });
  });

  group('Supervisor', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('supervisor_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test(
      'starts, matches readiness, streams logs, stops own process',
      () async {
        final script = await _writeChild(dir, 'ready', [
          'booting…',
          'HERMES_BACKEND_READY port=45678',
        ], exitCode: -1);
        final supervisor = Supervisor(
          executable: Platform.resolvedExecutable,
          arguments: [script],
          readiness: parseBackendReadyPort,
          startTimeout: const Duration(seconds: 15),
        );
        final states = <SupervisorState>[];
        final logs = <SupervisorLog>[];
        supervisor.stateChanges.listen(states.add);
        supervisor.logs.listen(logs.add);
        try {
          final started = await supervisor.ensureStarted();
          expect(started.alreadyRunning, isFalse);
          expect(started.pid, supervisor.pid);
          expect(supervisor.readyValue, 45678);
          expect(supervisor.state, SupervisorState.running);

          // Second call is a no-op on the same process.
          final again = await supervisor.ensureStarted();
          expect(again.alreadyRunning, isTrue);
          expect(again.pid, started.pid);

          expect(
            logs.map((l) => l.line),
            containsAll(['booting…', 'HERMES_BACKEND_READY port=45678']),
          );
        } finally {
          await supervisor.dispose();
        }
        expect(supervisor.state, SupervisorState.stopped);
        expect(
          states,
          containsAllInOrder([
            SupervisorState.starting,
            SupervisorState.running,
            SupervisorState.stopped,
          ]),
        );
        // The child is gone: the OS reaps it (no zombie lingers as a live pid
        // we own — `stop` waited for exitCode).
        expect(supervisor.pid, isNull);
      },
    );

    test('stop kills only its own process', () async {
      final script = await _writeChild(dir, 'sibling', ['alive'], exitCode: -1);
      // A sibling Dart process the supervisor must NOT touch.
      final sibling = await Process.start(Platform.resolvedExecutable, [
        script,
      ]);
      // Drain so the sibling never blocks on a full pipe.
      unawaited(sibling.stdout.drain());
      unawaited(sibling.stderr.drain());
      final supervisor = Supervisor(
        executable: Platform.resolvedExecutable,
        arguments: [script],
        startTimeout: const Duration(seconds: 15),
      );
      try {
        await supervisor.start();
        final ownedPid = supervisor.pid!;
        expect(ownedPid, isNot(sibling.pid));
        await supervisor.stop();
        // Sibling still answers: SIGTERM-then-SIGKILL went to the owned
        // handle only, never by pid/name.
        expect(await _isAlive(sibling.pid), isTrue);
      } finally {
        await supervisor.dispose();
        sibling.kill(ProcessSignal.sigkill);
        await sibling.exitCode;
      }
    });

    test('unexpected exit restarts with backoff', () async {
      final script = await _writeChild(dir, 'flaky', ['boom'], exitCode: 3);
      final supervisor = Supervisor(
        executable: Platform.resolvedExecutable,
        arguments: [script],
        // No readiness: running as soon as spawned, then the exit is
        // unexpected and schedules a restart.
        startTimeout: const Duration(seconds: 15),
      );
      final states = <SupervisorState>[];
      supervisor.stateChanges.listen(states.add);
      try {
        await supervisor.start();
        // First restart fires after ~1s; wait for the restarting state plus
        // the respawn cycle (the respawn exits again → restarting).
        await _waitFor(
          () => supervisor.restartCount >= 1,
          const Duration(seconds: 10),
        );
        expect(supervisor.restartCount, greaterThanOrEqualTo(1));
        expect(states, contains(SupervisorState.restarting));
        // Stopping cancels the pending restart: no more respawns.
        await supervisor.stop();
        final count = supervisor.restartCount;
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(supervisor.restartCount, count);
        expect(supervisor.state, SupervisorState.stopped);
      } finally {
        await supervisor.dispose();
      }
    });

    test('early exit before readiness fails the start', () async {
      final script = await _writeChild(dir, 'early', [
        'traceback: boom',
      ], exitCode: 1);
      final supervisor = Supervisor(
        executable: Platform.resolvedExecutable,
        arguments: [script],
        readiness: parseBackendReadyPort,
        startTimeout: const Duration(seconds: 15),
      );
      try {
        await expectLater(
          supervisor.start(),
          throwsA(
            isA<ProcessFailed>().having(
              (e) => e.outputTail,
              'tail',
              contains('traceback: boom'),
            ),
          ),
        );
      } finally {
        await supervisor.dispose();
      }
    });

    test('readiness timeout fails with the output tail', () async {
      final script = await _writeChild(dir, 'silent', [
        'waiting for something…',
      ], exitCode: -1);
      final supervisor = Supervisor(
        executable: Platform.resolvedExecutable,
        arguments: [script],
        readiness: parseBackendReadyPort,
        startTimeout: const Duration(milliseconds: 300),
      );
      try {
        await expectLater(supervisor.start(), throwsA(isA<ProcessFailed>()));
      } finally {
        await supervisor.dispose();
      }
    });
  });
}

Future<void> _waitFor(bool Function() done, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<bool> _isAlive(int pid) async {
  try {
    // Signal 0 probes liveness without delivering anything.
    final result = await Process.run('kill', ['-0', '$pid']);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
