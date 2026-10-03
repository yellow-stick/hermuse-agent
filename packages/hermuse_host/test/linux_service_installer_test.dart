@TestOn('linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hermuse_host/hermuse_host.dart';
import 'package:hermuse_host/src/linux_service_protocol.dart';
import 'package:test/test.dart';

String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
String _frames(List<Map<String, Object?>> values) =>
    "printf '%s\\n' ${values.map((value) => _quote(jsonEncode(value))).join(' ')}";

void main() {
  failureProtocolTests();
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('hermuse-service-test-');
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<LinuxServiceHelper> helper(String script, {String? pinned}) async {
    final file = File('${temporary.path}/libexec/hermuse-linux-service');
    await file.create(recursive: true);
    await file.writeAsString('#!/bin/sh\n$script\n');
    await Process.run('/usr/bin/chmod', ['0755', file.path]);
    return LinuxServiceHelper.bundled(
      executableDir: temporary.path,
      compiledSha256:
          '${sha256.convert(utf8.encode(pinned ?? '#!/bin/sh\n$script\n'))}',
    );
  }

  LinuxServiceProcessStarter verifier({
    void Function(Map<String, String>)? environmentSeen,
  }) => (executable, arguments, environment) async {
    expect(executable, '/usr/bin/pkexec');
    expect(arguments.take(4), [
      '--disable-internal-agent',
      '/usr/bin/sh',
      '-c',
      linuxServicePrivilegeVerifier,
    ]);
    environmentSeen?.call(environment);
    return Process.start(
      '/usr/bin/sh',
      [
        '-c',
        arguments[3].replaceAll(
          '/var/lib/hermuse-service-verify.',
          '${temporary.path}/snapshot.',
        ),
        ...arguments.skip(4),
      ],
      environment: environment,
      includeParentEnvironment: false,
    );
  };

  final installed = <String, Object?>{
    'event': 'installed',
    'baseUrl': 'http://127.0.0.1:9119',
    'sessionToken': 't' * 64,
  };
  final done = <String, Object?>{'event': 'done'};

  test('connect authorizes only a fieldless request and returns private completion', () async {
    final requestFile = File('${temporary.path}/connect-request');
    final binary = await helper('''[ "\$1" = connect ] || exit 98
read request
printf '%s' "\$request" > ${_quote(requestFile.path)}
${_frames([
      {'event': 'started', 'step': 'connect'},
      {'event': 'finished', 'step': 'connect', 'reused': false},
      installed,
      done,
    ])}''');
    final service = LinuxServiceInstaller(
      helper: () async => binary,
      environment: {'HERMES_HOME': '/untrusted/legacy'},
      startProcess: verifier(),
    );
    final events = await service.connect().toList();
    expect(jsonDecode(await requestFile.readAsString()), isEmpty);
    expect(
      events.whereType<RemoteInstallCompleted>().single.outcome.sessionToken,
      't' * 64,
    );
  });

  test('failed connection never invokes installation as a fallback', () async {
    var invocations = 0;
    final binary = await helper('''[ "\$1" = connect ] || exit 98
${_frames([
      {'event': 'error', 'step': 'connect', 'code': 'connect-refused', 'message': 'Existing service refused.'},
    ])}
exit 1''');
    final start = verifier();
    final service = LinuxServiceInstaller(
      helper: () async => binary,
      startProcess: (executable, arguments, environment) {
        invocations++;
        expect(arguments.last, 'connect');
        return start(executable, arguments, environment);
      },
    );
    await expectLater(
      service.connect().toList(),
      throwsA(isA<RemoteInstallFailed>()),
    );
    expect(invocations, 1);
  });

  test('connection protocol rejects every install or identity field', () {
    final request = LinuxServiceRequest.parse(
      LinuxServiceMode.connect,
      '{}',
      callerHome: '/home/desktop',
    );
    expect(request.migration, isNull);
    for (final key in [
      'migration',
      'legacyHome',
      'revision',
      'purge',
      'command',
      'token',
      'uid',
      'pluginBundle',
    ]) {
      expect(
        () => LinuxServiceRequest.parse(
          LinuxServiceMode.connect,
          jsonEncode({key: null}),
          callerHome: '/home/desktop',
        ),
        throwsFormatException,
      );
    }
  });

  test('missing release digest fails closed and release pin forbids workspace trust', () async {
    expect(
      () => LinuxServiceHelper.bundled(compiledSha256: ''),
      throwsA(isA<LinuxSetupUnavailable>()),
    );
    await expectLater(
      LinuxServiceHelper.fromWorkspace(
        temporary.path,
        compiledSha256: 'a' * 64,
      ),
      throwsA(isA<LinuxSetupUnavailable>()),
    );
  });

  test(
    'nonprivileged inspection verifies helper and never invokes pkexec',
    () async {
      final binary = await helper(
        _frames([
          {
            'event': 'inspection',
            'canonicalPresent': true,
            'legacyPresent': true,
            'legacy': null,
          },
          done,
        ]),
      );
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: (executable, arguments, environment) {
          expect(executable, binary.path);
          expect(arguments, ['inspect']);
          return Process.start(
            executable,
            arguments,
            environment: environment,
            includeParentEnvironment: false,
          );
        },
      );
      final result = await service.inspect();
      expect(result.canonicalPresent, isTrue);
      expect(result.legacyPresent, isTrue);
      expect(result.legacy, isNull);
    },
  );

  test(
    'root verifier refuses substituted executable before any action',
    () async {
      final marker = '${temporary.path}/executed';
      final binary = await helper(
        'touch ${_quote(marker)}',
        pinned: 'trusted bytes',
      );
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: verifier(),
      );
      await expectLater(
        service.run().toList(),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(await File(marker).exists(), isFalse);
      expect(
        await temporary
            .list()
            .where((item) => item.path.contains('/snapshot.'))
            .isEmpty,
        isTrue,
      );
    },
  );

  test(
    'verification executes the private snapshot after the source changes',
    () async {
      final started = Completer<void>();
      final binary = await helper('''read request
${_frames([
        {'event': 'started', 'step': 'preflight'},
      ])}
read control
${_frames([installed, done])}''');
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: verifier(),
      );
      final result = service.run().map((event) {
        if (event is RemoteInstallStepStarted) started.complete();
        return event;
      }).toList();
      await started.future;
      await File(binary.path).writeAsString('#!/bin/sh\nexit 99\n');
      await service.cancel();
      expect((await result).whereType<RemoteInstallCompleted>(), hasLength(1));
    },
  );

  test('credentials are handed off privately and subprocess environment is bounded', () async {
    final binary = await helper(
      'read request\nprintf secret-diagnostic >&2\n${_frames([installed, done])}',
    );
    late Map<String, String> passed;
    final service = LinuxServiceInstaller(
      helper: () async => binary,
      startProcess: verifier(
        environmentSeen: (value) {
          passed = value;
        },
      ),
      environment: const {
        'DISPLAY': ':0',
        'HOME': '/tmp/not-the-caller',
        'PKEXEC_UID': '0',
        'PATH': '/tmp/evil',
        'LD_PRELOAD': '/tmp/evil.so',
        'PYTHONPATH': '/tmp/code',
        'DOCKER_HOST': 'tcp://public:2375',
        'APPDIR': '/tmp/image',
      },
    );
    final events = await service.run().toList();
    expect(events, hasLength(1));
    final outcome = (events.single as RemoteInstallCompleted).outcome;
    expect(outcome.sessionToken, 't' * 64);
    expect(outcome.username, isEmpty);
    expect(outcome.password, isEmpty);
    expect(passed, {'PATH': '/usr/sbin:/usr/bin:/sbin:/bin', 'DISPLAY': ':0'});
  });

  for (final ending in [
    'exit 1',
    'true',
    '${_frames([done])}; exit 1',
  ]) {
    test('partial outcome never releases credentials: $ending', () async {
      final binary = await helper('${_frames([installed])}\n$ending');
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: verifier(),
      );
      final events = <RemoteInstallProgress>[];
      await expectLater(
        service.run().forEach(events.add),
        throwsA(isA<RemoteInstallFailed>()),
      );
      expect(events.whereType<RemoteInstallCompleted>(), isEmpty);
    });
  }

  test('malformed IPC does not expose source text or stop draining', () async {
    final binary = await helper(
      "printf 'secret-not-json\\n'\n${_frames([installed, done])}",
    );
    final service = LinuxServiceInstaller(
      helper: () async => binary,
      startProcess: verifier(),
    );
    await expectLater(
      service.run().toList(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.toString(),
          'redacted error',
          isNot(contains('secret-not-json')),
        ),
      ),
    );
  });

  test(
    'cancel waits for a safe command boundary instead of killing the helper',
    () async {
      final marker = File('${temporary.path}/transaction-finished');
      final started = Completer<void>();
      final binary = await helper('''read request
${_frames([
        {'event': 'started', 'step': 'hermes'},
      ])}
read control
[ "\$control" = '{"cancel":true}' ] || exit 2
sleep 0.15
printf committed > ${_quote(marker.path)}
${_frames([
        {'event': 'error', 'message': 'Cancelled safely.'},
      ])}
exit 1''');
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: verifier(),
      );
      final running = service.run().forEach((event) {
        if (event is RemoteInstallStepStarted) started.complete();
      });
      final failed = expectLater(running, throwsA(isA<RemoteInstallFailed>()));
      await started.future;
      await service.cancel();
      expect(await marker.readAsString(), 'committed');
      await failed;
    },
  );

  test(
    'uninstall sends only confirmed revision and explicit purge choice',
    () async {
      final requestFile = File('${temporary.path}/request');
      final binary = await helper('''read request
printf '%s' "\$request" > ${_quote(requestFile.path)}
${_frames([
        {
          'event': 'uninstalled',
          'purged': true,
          'removed': ['dashboard'],
          'preserved': [],
          'warnings': [],
          'complete': true,
        },
        done,
      ])}''');
      final service = LinuxServiceInstaller(
        helper: () async => binary,
        startProcess: verifier(),
      );
      final events = await service
          .uninstall(
            inspection: RemoteUninstallInventory(
              resources: const [],
              revision: 'b' * 64,
              host: 'localhost',
            ),
            deleteAll: true,
          )
          .toList();
      expect(
        (events.single as RemoteUninstallCompleted).outcome.purged,
        isTrue,
      );
      expect(jsonDecode(await requestFile.readAsString()), {
        'revision': 'b' * 64,
        'purge': true,
      });
    },
  );

  test(
    'request protocol cannot become a command, identity or plugin broker',
    () {
      for (final key in [
        'command',
        'script',
        'pluginBundle',
        'helperPath',
        'uid',
        'home',
        'environment',
      ]) {
        expect(
          () => LinuxServiceRequest.parse(
            LinuxServiceMode.install,
            jsonEncode({key: 'untrusted'}),
            callerHome: '/home/desktop',
          ),
          throwsFormatException,
        );
      }
      for (final home in [
        '/root/.hermes',
        '/home/desktop/../root',
        '/home/desktop//data',
        'relative',
        '/home/desktop/data\n',
      ]) {
        expect(
          () => LinuxServiceRequest.parse(
            LinuxServiceMode.install,
            jsonEncode({'legacyHome': home}),
            callerHome: '/home/desktop',
          ),
          throwsFormatException,
        );
      }
      final valid = LinuxServiceRequest.parse(
        LinuxServiceMode.install,
        '{"legacyHome":"/home/desktop/data"}',
        callerHome: '/home/desktop',
      );
      expect(valid.legacyHome, '/home/desktop/data');
    },
  );

  test(
    'migration confirmation is bound to selected caller path and revision',
    () {
      final inventory = LegacyHermesMigration(
        sourceHome: '/home/other/.hermes',
        revision: 'a' * 64,
        summary: 'data',
      );
      expect(
        () => LinuxServiceRequest.parse(
          LinuxServiceMode.install,
          jsonEncode({'migration': inventory.toJson()}),
          callerHome: '/home/desktop',
        ),
        throwsFormatException,
      );
      expect(
        () => LinuxServiceRequest.parse(
          LinuxServiceMode.uninstall,
          '{"purge":true}',
          callerHome: '/home/desktop',
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'completed helper cancels control input while the client pipe stays open',
    () async {
      final input = StreamController<List<int>>();
      addTearDown(input.close);
      final frames = StreamIterator(serviceLines(input.stream));
      final first = frames.moveNext();
      input.add(utf8.encode('{}\n'));
      expect(await first, isTrue);
      final next = frames.moveNext();
      await Future<void>.delayed(Duration.zero);
      await frames.cancel().timeout(const Duration(seconds: 2));
      expect(await next, isFalse);
    },
  );

  test(
    'output framing bounds partial frames and rejects truncated UTF-8 JSON',
    () async {
      await expectLater(
        serviceLines(Stream.value(utf8.encode('a' * 65537))).toList(),
        throwsFormatException,
      );
      await expectLater(
        serviceLines(Stream.value(utf8.encode('{}'))).toList(),
        throwsFormatException,
      );
      expect(
        await serviceLines(
          Stream.fromIterable([utf8.encode('{'), utf8.encode('}\n')]),
        ).toList(),
        ['{}'],
      );
    },
  );

  test('raw engine logs never cross privileged IPC', () {
    expect(serviceInstallEvent(const RemoteInstallLog('TOKEN=secret')), isNull);
    expect(
      serviceUninstallEvent(const RemoteUninstallLog('password=secret')),
      isNull,
    );
    expect(
      () => serviceInstallFromJson({
        'event': 'installed',
        'baseUrl': 'https://public.example',
        'sessionToken': 'secret',
      }),
      throwsFormatException,
    );
  });
}

// These messages can be rendered by the app; command output cannot.
void failureProtocolTests() {
  test(
    'failure frames preserve a safe stage without credentials or raw stderr',
    () {
      final failure = serviceFailureEvent(
        const RemoteInstallFailed('dashboard', 'TOKEN=secret password=private'),
      );
      expect(failure['step'], 'dashboard');
      expect(failure['code'], 'stage-failed');
      expect(jsonEncode(failure), isNot(contains('secret')));
      expect(jsonEncode(failure), isNot(contains('private')));
    },
  );
  test(
    'ownership refusal retains its category without leaking command output',
    () {
      final failure = serviceFailureEvent(
        const RemoteInstallFailed(
          'preflight',
          'An unrelated plugin occupies the Hermuse plugin directory.\nTOKEN=private-token',
        ),
      );
      expect(failure['step'], 'preflight');
      expect(failure['code'], 'preflight-refused');
      expect(jsonEncode(failure), isNot(contains('private-token')));
    },
  );

  test('migration refusals preserve actionable safe categories', () {
    final failure = serviceFailureEvent(
      const RemoteInstallFailed(
        'hermes',
        'secret text: Stop processes before migration',
      ),
    );
    expect(failure['code'], 'migration-refused');
    expect(jsonEncode(failure), isNot(contains('secret text')));
    expect(
      serviceMigrationRefusal('unrecognized sensitive command output'),
      isNull,
    );
  });
}
