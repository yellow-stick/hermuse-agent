@TestOn('linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

final _uid = '${Process.runSync('id', ['-u']).stdout}'.trim();
final _asRoot = _uid == '0';

typedef _Start = Future<Process> Function(
  String,
  List<String>,
  Map<String, String>,
);

/// Plays pkexec without privileges: runs the constant verifier with `sh` as
/// this user, its private directory moved from /run to [runDir].
_Start _fakePkexec(String runDir) => (executable, arguments, environment) {
  expect(executable, LinuxPrivilegeRunner.pkexec);
  expect(arguments.take(4), [
    '--disable-internal-agent',
    LinuxPrivilegeRunner.shell,
    '-c',
    linuxPrivilegeVerifier,
  ]);
  final script = arguments[3].replaceAll(
    '/run/hermuse-verify.',
    '$runDir/hermuse-verify.',
  );
  return Process.start(
    '/usr/bin/sh',
    ['-c', script, ...arguments.skip(4)],
    environment: {...environment, 'PKEXEC_UID': _uid},
    includeParentEnvironment: false,
  );
};

/// A pkexec that runs [snippet] instead (exit status, stdout, stderr).
_Start _scripted(String snippet) =>
    (_, _, _) => Process.start('/usr/bin/sh', ['-c', snippet]);

String _json(Object value) => jsonEncode(value);

String _result(
  String code,
  int exit, {
  List<String> applied = const [],
  bool? ok,
}) => _json({
  'result': {
    'ok': ok ?? exit == 0,
    'code': code,
    'applied': applied,
    'exit': exit,
  },
});

String _printLines(List<String> lines) =>
    "printf '%s\\n' ${lines.map((l) => "'$l'").join(' ')}";

void main() {
  late Directory tmp;
  late String runDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hermuse_privilege_test');
    runDir = '${tmp.path}/run';
    await Directory(runDir).create();
  });

  tearDown(() => tmp.delete(recursive: true));

  /// Writes a bundled helper at `<tmp>/libexec/hermuse-linux-setup` and
  /// returns it bound to the digest of [trusted] (defaults to [content]).
  Future<LinuxSetupHelper> bundledHelper(
    String content, {
    String? trusted,
  }) async {
    final file = File('${tmp.path}/libexec/hermuse-linux-setup');
    await file.create(recursive: true);
    await file.writeAsString(content);
    return LinuxSetupHelper.bundled(
      executableDir: tmp.path,
      compiledSha256: '${sha256.convert(utf8.encode(trusted ?? content))}',
    );
  }

  group('LinuxSetupHelper', () {
    test('a build without a compiled digest cannot elevate', () {
      expect(
        () => LinuxSetupHelper.bundled(executableDir: tmp.path),
        throwsA(isA<LinuxSetupUnavailable>()),
      );
      expect(
        () => LinuxSetupHelper.bundled(
          executableDir: tmp.path,
          compiledSha256: 'ABCDEF',
        ),
        throwsA(isA<LinuxSetupUnavailable>()),
      );
    });

    test('the bundled helper lives in libexec next to the executable', () {
      final helper = LinuxSetupHelper.bundled(
        executableDir: '/opt/hermuse-agent',
        compiledSha256: 'a' * 64,
      );
      expect(helper.path, '/opt/hermuse-agent/libexec/hermuse-linux-setup');
      expect(helper.development, isFalse);
    });

    test('the workspace helper is refused once a digest is compiled in', () {
      expect(
        LinuxSetupHelper.fromWorkspace(
          Directory.current.parent.parent.path,
          compiledSha256: 'a' * 64,
        ),
        throwsA(isA<LinuxSetupUnavailable>()),
      );
    });
  });

  group('verifier', () {
    test('runs the verified private copy, never the source path', () async {
      final helper = await bundledHelper('''
printf 'ran %s\\n' "\$0" >&2
${_printLines([
        _json({'event': 'begin', 'category': 'hermes-tools'}),
        _json({'event': 'done', 'category': 'hermes-tools'}),
        _result('ok', 0, applied: ['hermes-tools']),
      ])}
''');
      final logs = <String>[];
      final events = <LinuxHelperEvent>[];
      final outcome =
          await LinuxPrivilegeRunner(
            helper: helper,
            environment: const {},
            startProcess: _fakePkexec(runDir),
          ).apply(
            [LinuxHelperCategory.hermesTools],
            onEvent: events.add,
            onLog: logs.add,
          );

      expect(outcome, isA<LinuxHelperFinished>());
      final finished = outcome as LinuxHelperFinished;
      expect(finished.result.ok, isTrue);
      expect(finished.result.applied, [LinuxHelperCategory.hermesTools]);
      expect(events.map((e) => e.kind), [
        LinuxHelperEventKind.begin,
        LinuxHelperEventKind.done,
      ]);
      final ran = logs.single.substring('ran '.length);
      expect(ran, startsWith('$runDir/hermuse-verify.'));
      expect(ran, isNot(helper.path));
      expect(Directory(runDir).listSync(), isEmpty, reason: 'copy removed');
    });

    test('a helper changed after the digest was taken never runs', () async {
      final marker = '${tmp.path}/ran';
      final helper = await bundledHelper(
        'touch "$marker"\n${_printLines([
          _result('ok', 0, applied: ['hermes-tools']),
        ])}\n',
        trusted: 'the reviewed helper\n',
      );
      final outcome = await LinuxPrivilegeRunner(
        helper: helper,
        environment: const {},
        startProcess: _fakePkexec(runDir),
      ).apply([LinuxHelperCategory.hermesTools]);

      expect(
        outcome,
        isA<LinuxHelperRejected>().having(
          (r) => r.reason,
          'reason',
          LinuxVerifierFailure.digest,
        ),
      );
      expect(File(marker).existsSync(), isFalse);
      expect(Directory(runDir).listSync(), isEmpty);
    });

    test('an oversized or missing helper is refused', () async {
      final big = '${'#' * linuxHelperMaxBytes}\n';
      final oversized = await bundledHelper(big);
      expect(
        await LinuxPrivilegeRunner(
          helper: oversized,
          environment: const {},
          startProcess: _fakePkexec(runDir),
        ).apply([LinuxHelperCategory.hermesTools]),
        isA<LinuxHelperRejected>().having(
          (r) => r.reason,
          'reason',
          LinuxVerifierFailure.copy,
        ),
      );

      await File(oversized.path).delete();
      expect(
        await LinuxPrivilegeRunner(
          helper: oversized,
          environment: const {},
          startProcess: _fakePkexec(runDir),
        ).apply([LinuxHelperCategory.hermesTools]),
        isA<LinuxHelperRejected>().having(
          (r) => r.reason,
          'reason',
          LinuxVerifierFailure.copy,
        ),
      );
    });

    test('refuses arguments outside its contract', () async {
      final script = linuxPrivilegeVerifier.replaceAll(
        '/run/hermuse-verify.',
        '$runDir/hermuse-verify.',
      );
      final source = File('${tmp.path}/helper')..writeAsStringSync('exit 0\n');
      final digest = '${sha256.convert(source.readAsBytesSync())}';
      for (final arguments in [
        [digest.toUpperCase(), source.path, 'apply', 'hermes-tools'],
        [digest.substring(1), source.path, 'apply', 'hermes-tools'],
        [digest, 'helper', 'apply', 'hermes-tools'],
        [digest, source.path, 'plan', 'hermes-tools'],
        [digest, source.path, 'apply'],
      ]) {
        final result = await Process.run('/usr/bin/sh', [
          '-c',
          script,
          'hermuse-verify',
          ...arguments,
        ]);
        expect(result.exitCode, 90, reason: '$arguments');
      }
    });
  });

  group('LinuxPrivilegeRunner', () {
    final helper = LinuxSetupHelper.bundled(
      executableDir: '/opt/hermuse-agent',
      compiledSha256: 'a' * 64,
    );

    Future<LinuxHelperOutcome> run(
      String snippet, [
      List<LinuxHelperCategory> categories = const [
        LinuxHelperCategory.hermesTools,
      ],
    ]) => LinuxPrivilegeRunner(
      helper: helper,
      environment: const {},
      startProcess: _scripted(snippet),
    ).apply(categories);

    test('a dismissed dialog is not a success', () async {
      expect(await run('exit 126'), isA<LinuxHelperDismissed>());
    });

    test('a refused or impossible authorization is not a success', () async {
      final outcome = await run(
        'echo "Error executing command as another user: Not authorized" >&2; '
        'exit 127',
      );
      expect(
        outcome,
        isA<LinuxHelperDenied>().having(
          (d) => d.detail,
          'detail',
          contains('Not authorized'),
        ),
      );
    });

    test('a missing or inconsistent result is a failure', () async {
      final begin = _json({'event': 'begin', 'category': 'hermes-tools'});
      final ok = _result('ok', 0, applied: ['hermes-tools']);
      for (final snippet in [
        '${_printLines([begin])}; exit 0',
        '${_printLines([ok])}; exit 5',
        '${_printLines([
          _result('ok', 0, applied: ['hermes-tools'], ok: false),
        ])}; exit 0',
        '${_printLines(['Reading package lists...', ok])}; exit 0',
        '${_printLines([ok, begin])}; exit 0',
        '${_printLines([
          _json({'event': 'begin', 'category': 'docker.io'}),
          ok,
        ])}; exit 0',
        'exit 0',
        'exit 5',
      ]) {
        expect(await run(snippet), isA<LinuxHelperFailed>(), reason: snippet);
      }
    });

    test('a successful result must cover exactly what was asked', () async {
      final outcome = await run(
        '${_printLines([
          _result('ok', 0, applied: ['hermes-tools']),
        ])}; exit 0',
        [LinuxHelperCategory.hermesTools, LinuxHelperCategory.dockerGroup],
      );
      expect(outcome, isA<LinuxHelperFailed>());
    });

    test('a partial failure reports what was applied', () async {
      final outcome = await run(
        '${_printLines([
          _json({'event': 'begin', 'category': 'hermes-tools'}),
          _json({'event': 'done', 'category': 'hermes-tools'}),
          _json({'event': 'fail', 'category': 'docker-install', 'code': 'docker-present'}),
          _result('docker-present', 6, applied: ['hermes-tools']),
        ])}; exit 6',
        [LinuxHelperCategory.hermesTools, LinuxHelperCategory.dockerInstall],
      );
      expect(outcome, isA<LinuxHelperFinished>());
      final result = (outcome as LinuxHelperFinished).result;
      expect(result.ok, isFalse);
      expect(result.code, LinuxHelperCode.dockerPresent);
      expect(result.applied, [LinuxHelperCategory.hermesTools]);
    });

    test('pkexec gets a fixed PATH and only the session variables', () async {
      late Map<String, String> seen;
      late List<String> arguments;
      await LinuxPrivilegeRunner(
        helper: helper,
        environment: const {
          'DISPLAY': ':0',
          'WAYLAND_DISPLAY': 'wayland-0',
          'XAUTHORITY': '/run/user/1000/xauth',
          'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
          'XDG_RUNTIME_DIR': '/run/user/1000',
          'LANG': 'en_US.UTF-8',
          'PATH': '/tmp/evil:/usr/bin',
          'LD_PRELOAD': '/tmp/evil.so',
          'LD_LIBRARY_PATH': '/tmp/.mount_hermuse/usr/lib',
          'GTK_PATH': '/tmp/.mount_hermuse/usr/lib/gtk-3.0',
          'GCONV_PATH': '/tmp/evil',
          'PYTHONPATH': '/tmp/evil',
          'DOCKER_HOST': 'tcp://10.0.0.1:2375',
          'APPIMAGE': '/home/ada/Hermuse.AppImage',
          'APPDIR': '/tmp/.mount_hermuse',
          'SHELL': '/tmp/evil-shell',
          'HOME': '/home/ada',
        },
        startProcess: (executable, args, environment) {
          seen = environment;
          arguments = args;
          return Process.start('/usr/bin/sh', ['-c', 'exit 126']);
        },
      ).apply([
        LinuxHelperCategory.dockerGroup,
        LinuxHelperCategory.hermesTools,
        LinuxHelperCategory.dockerGroup,
      ]);

      expect(seen['PATH'], '/usr/sbin:/usr/bin:/sbin:/bin');
      expect(seen['DISPLAY'], ':0');
      expect(seen['DBUS_SESSION_BUS_ADDRESS'], 'unix:path=/run/user/1000/bus');
      expect(seen['XDG_RUNTIME_DIR'], '/run/user/1000');
      for (final name in [
        'LD_PRELOAD',
        'LD_LIBRARY_PATH',
        'GTK_PATH',
        'GCONV_PATH',
        'PYTHONPATH',
        'DOCKER_HOST',
        'APPIMAGE',
        'APPDIR',
        'SHELL',
        'HOME',
      ]) {
        expect(seen, isNot(contains(name)));
      }
      // One run, categories once each in the helper's fixed order.
      expect(arguments.sublist(arguments.indexOf('apply') + 1), [
        'hermes-tools',
        'docker-group',
      ]);
    });

    test(
      'the real helper, verified and run without root, refuses to act',
      () async {
        final helper = await LinuxSetupHelper.fromWorkspace(
          Directory.current.parent.parent.path,
        );
        final events = <LinuxHelperEvent>[];
        final outcome = await LinuxPrivilegeRunner(
          helper: helper,
          environment: const {},
          startProcess: _fakePkexec(runDir),
        ).apply(LinuxHelperCategory.values, onEvent: events.add);

        expect(outcome, isA<LinuxHelperFinished>());
        final result = (outcome as LinuxHelperFinished).result;
        expect(
          result.code,
          isIn([LinuxHelperCode.notRoot, LinuxHelperCode.unsupportedOs]),
        );
        expect(result.applied, isEmpty);
        expect(events.map((e) => e.kind), [LinuxHelperEventKind.os]);
        expect(Directory(runDir).listSync(), isEmpty);
      },
      skip: _asRoot ? 'never runs the real helper apply as root' : false,
    );
  });
}
