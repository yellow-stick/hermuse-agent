import 'dart:io';

import 'package:test/test.dart';

import '../tool/gen_hermes_contract.dart';

void main() {
  test('committed contract.g.dart matches a fresh generation', () {
    final dir = Directory.systemTemp.createTempSync('hermes_contract');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fresh = File('${dir.path}/contract.g.dart')
      ..writeAsStringSync(
        generateContract(File(contractPath).readAsStringSync()),
      );
    final format = Process.runSync(Platform.resolvedExecutable, [
      'format',
      fresh.path,
    ]);
    expect(format.exitCode, 0, reason: '${format.stderr}');
    expect(
      fresh.readAsStringSync() == File(outputPath).readAsStringSync(),
      isTrue,
      reason: 'Run `dart run tool/gen_hermes_contract.dart` in packages/hermes_contract.',
    );
  });
}
