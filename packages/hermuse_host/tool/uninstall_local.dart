import 'dart:io';

import 'package:hermuse_host/hermuse_host.dart';

const _usage = '''Usage: dart run tool/uninstall_local.dart [options]

Inspect the canonical Linux service at /home/hermes/.hermes.
Uses the same verified privileged helper and ownership inventory as the app.
No removal by default. Never targets per-user ~/.hermes or remote machines.

  --workspace-root PATH  Explicit development helper bundle location
  --purge                Also remove proven-owned data and caches
  --apply                Apply the displayed plan after confirmation
  --yes                  Confirm non-interactively (requires --apply)
  --help                 Show this help

Shared, changed and unproven resources are preserved. The Hermuse desktop
application and its saved connections are not removed by this command.
''';

Future<void> main(List<String> arguments) async {
  var purge = false;
  var apply = false;
  var yes = false;
  String? workspaceRoot;
  try {
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--help':
          stdout.write(_usage);
          return;
        case '--purge':
          purge = true;
        case '--apply':
          apply = true;
        case '--yes':
          yes = true;
        case '--workspace-root':
          if (++index == arguments.length) {
            throw const FormatException('--workspace-root requires a path');
          }
          workspaceRoot = arguments[index];
        default:
          throw FormatException('Unknown option: ${arguments[index]}');
      }
    }
    if (yes && !apply) throw const FormatException('--yes requires --apply');
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..write(_usage);
    exitCode = 64;
    return;
  }
  if (!Platform.isLinux) {
    stderr.writeln('Canonical service removal is supported on Linux only.');
    exitCode = 64;
    return;
  }
  final installer = LinuxServiceInstaller.system(workspaceRoot: workspaceRoot);
  try {
    final inventory = await installer.inspectUninstall();
    for (final resource in inventory.resources) {
      stdout.writeln(
        '${resource.removedBy(purge: purge) ? 'REMOVE' : 'KEEP'} '
        '${resource.label}: ${resource.reason}',
      );
    }
    if (inventory.transactionActive) {
      throw StateError(
        'Another setup or removal is active; inspect again later.',
      );
    }
    if (!apply) return;
    if (!yes) {
      stdout.write(
        purge
            ? 'Permanently purge owned data? Type UNINSTALL: '
            : 'Remove service and keep data? Type UNINSTALL: ',
      );
      if (stdin.readLineSync() != 'UNINSTALL') return;
    }
    RemoteUninstallOutcome? outcome;
    await for (final event in installer.uninstall(
      inspection: inventory,
      deleteAll: purge,
    )) {
      switch (event) {
        case RemoteUninstallLog(:final line):
          stderr.writeln(line);
        case RemoteUninstallCompleted(outcome: final result):
          outcome = result;
        case RemoteUninstallStepStarted() || RemoteUninstallStepFinished():
          break;
      }
    }
    if (outcome == null) {
      throw StateError('Removal ended without verification.');
    }
    for (final removed in outcome.removed) {
      stdout.writeln('Removed: $removed');
    }
    for (final preserved in outcome.preserved) {
      stdout.writeln('Preserved: ${preserved.label}: ${preserved.reason}');
    }
    for (final warning in outcome.warnings) {
      stderr.writeln(warning);
    }
    if (!outcome.complete) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('Canonical removal could not finish: $error');
    exitCode = 1;
  }
}
