import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';
import 'package:test/test.dart';

void main() {
  group('InstallJournal', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('install_journal_test');
      path = '${dir.path}/support/hermes-install.json';
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    InstallJournal started() => InstallJournal(
      hermesHome: '/home/u/.hermes',
      installDir: '/home/u/.hermes/hermes-agent',
      runtimeHome: '/home/u/.hermes/runtime',
      commit: hermesReleaseCommit,
      startedAt: DateTime.utc(2026, 9, 29, 8),
    );

    test('reads as absent before any install', () async {
      expect(await InstallJournal.read(path), isNull);
    });

    test('keeps progress across app restarts', () async {
      await started()
          .withStageCompleted('prerequisites')
          .withStageCompleted('repository')
          .withStageStarted('venv')
          .write(path);

      final resumed = (await InstallJournal.read(path))!;
      expect(resumed.completedStages, ['prerequisites', 'repository']);
      expect(resumed.currentStage, 'venv');
      expect(resumed.finished, isFalse);
      expect(resumed.hasCompleted('repository'), isTrue);
      expect(resumed.hasCompleted('venv'), isFalse);
      expect(resumed.commit, hermesReleaseCommit);
      expect(resumed.installDir, '/home/u/.hermes/hermes-agent');
      expect(resumed.startedAt, DateTime.utc(2026, 9, 29, 8));
    });

    test('a completed stage clears the current one, once', () {
      final journal = started()
          .withStageStarted('venv')
          .withStageCompleted('venv')
          .withStageCompleted('venv');
      expect(journal.completedStages, ['venv']);
      expect(journal.currentStage, isNull);
    });

    test('reopening a stage makes it run again', () {
      final journal = started()
          .withStageCompleted('repository')
          .withStageCompleted('path')
          .withStageReopened('repository');
      expect(journal.completedStages, ['path']);
      expect(journal.currentStage, 'repository');
    });

    test('rewrites replace the file without leftovers', () async {
      await started().write(path);
      await started()
          .withStageCompleted('prerequisites')
          .asFinished()
          .write(path);
      final read = (await InstallJournal.read(path))!;
      expect(read.finished, isTrue);
      expect(read.completedStages, ['prerequisites']);
      expect(Directory('${dir.path}/support').listSync().map((e) => e.path), [
        path,
      ]);
    });

    test('refuses a file it cannot trust', () async {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('{"schema_version": 2}');
      await expectLater(InstallJournal.read(path), throwsFormatException);
      await file.writeAsString('{"schema_version": 1, "finished": true}');
      await expectLater(InstallJournal.read(path), throwsFormatException);
      await file.writeAsString('{"schema_version": 1, trunc');
      await expectLater(InstallJournal.read(path), throwsFormatException);
    });
  });
}
