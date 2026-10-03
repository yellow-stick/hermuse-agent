import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Canonical local removal CLI', () {
    Future<ProcessResult> run(List<String> arguments) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/uninstall_local.dart', ...arguments],
    );

    test('should explain fixed service scope without inspecting or elevating for help', () async {
      final result = await run(['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('/home/hermes/.hermes'));
      expect(result.stdout, contains('Never targets per-user ~/.hermes'));
      expect(result.stderr, isEmpty);
    });

    test(
      'should reject obsolete arbitrary-home removal before authorization',
      () async {
        final result = await run(['--hermes-home', '/tmp/foreign']);
        expect(result.exitCode, 64);
        expect(result.stdout, isEmpty);
        expect(result.stderr, contains('Unknown option: --hermes-home'));
      },
    );

    test('should require apply with noninteractive confirmation', () async {
      final result = await run(['--yes']);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('--yes requires --apply'));
    });
  });
}
