import 'dart:async';
import 'dart:convert';

import 'errors.dart';
import 'linux_migration.dart';
import 'remote_install.dart';
import 'remote_uninstall.dart';

/// The only operations understood by the separately compiled root helper.
enum LinuxServiceMode { inspect, connect, install, inspectUninstall, uninstall }

/// Validates requests before any privileged operation is constructed.
final class LinuxServiceRequest {
  const LinuxServiceRequest({
    this.migration,
    this.legacyHome,
    this.revision,
    this.purge = false,
  });
  final String? legacyHome;

  final LegacyHermesMigration? migration;
  final String? revision;
  final bool purge;

  static LinuxServiceRequest parse(
    LinuxServiceMode mode,
    String line, {
    required String callerHome,
  }) {
    if (line.length > 65536) throw const FormatException('Request too large.');
    final value = serviceObject(jsonDecode(line));
    final allowed = switch (mode) {
      LinuxServiceMode.install => {'migration', 'legacyHome'},
      LinuxServiceMode.inspect => {'legacyHome'},
      LinuxServiceMode.uninstall => {'revision', 'purge'},
      _ => <String>{},
    };
    if (value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Unknown request field.');
    }
    final legacyHome = value['legacyHome'];
    if (legacyHome != null &&
        (legacyHome is! String ||
            !legacyHome.startsWith('$callerHome/') ||
            legacyHome.split('/').any((part) => part == '.' || part == '..') ||
            legacyHome.contains('//') ||
            legacyHome.endsWith('/') ||
            legacyHome.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const FormatException(
        'HERMES_HOME must be an ordinary directory under your account home. Move it there before migration.',
      );
    }
    LegacyHermesMigration? migration;
    if (value['migration'] != null) {
      final confirmation = serviceObject(value['migration']);
      if (confirmation.keys.any(
        (key) => !{'sourceHome', 'revision', 'summary'}.contains(key),
      )) {
        throw const FormatException('Unknown migration confirmation field.');
      }
      migration = LegacyHermesMigration.fromJson(confirmation);
      if (migration.sourceHome != (legacyHome ?? '$callerHome/.hermes') ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(migration.revision)) {
        throw const FormatException('Migration does not belong to the caller.');
      }
    }
    final revision = value['revision'];
    if (mode == LinuxServiceMode.uninstall &&
        (revision is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(revision))) {
      throw const FormatException(
        'A confirmed inventory revision is required.',
      );
    }
    if (value.containsKey('purge') && value['purge'] is! bool) {
      throw const FormatException('Invalid removal choice.');
    }
    return LinuxServiceRequest(
      migration: migration,
      revision: revision as String?,
      legacyHome: legacyHome as String?,
      purge: value['purge'] as bool? ?? false,
    );
  }
}

Map<String, Object?> serviceObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid service-helper message.');
  }
  return value;
}

Map<String, Object?> serviceResourceJson(RemoteUninstallResource resource) => {
  'id': resource.id,
  'label': resource.label,
  'kind': resource.kind,
  'removable': resource.removable,
  'purgeOnly': resource.purgeOnly,
  'reason': resource.reason,
  'managed': resource.managed,
};

Map<String, Object?> serviceInventoryJson(RemoteUninstallInventory inventory) =>
    {
      'revision': inventory.revision,
      'transactionActive': inventory.transactionActive,
      'resources': inventory.resources.map(serviceResourceJson).toList(),
    };

RemoteUninstallInventory serviceInventoryFromJson(Map<String, Object?> value) =>
    RemoteUninstallInventory(
      revision: value['revision'] as String,
      transactionActive: value['transactionActive'] as bool,
      host: 'localhost',
      resources: (value['resources'] as List)
          .map((item) => RemoteUninstallResource.fromJson(serviceObject(item)))
          .toList(),
    );

Map<String, Object?>? serviceInstallEvent(RemoteInstallProgress event) =>
    switch (event) {
      RemoteInstallStepStarted(:final step) => {
        'event': 'started',
        'step': step.name,
      },
      RemoteInstallStepFinished(:final step, :final previouslyCompleted) => {
        'event': 'finished',
        'step': step.name,
        'reused': previouslyCompleted,
      },
      RemoteInstallCompleted(:final outcome) => {
        'event': 'installed',
        'baseUrl': outcome.baseUrl,
        'sessionToken': outcome.sessionToken,
      },
      // Shell output can contain credentials from third-party tools. It never
      // crosses the root-helper IPC boundary, even on an unsuccessful command.
      RemoteInstallLog() => null,
    };

RemoteInstallProgress serviceInstallFromJson(Map<String, Object?> value) {
  switch (value['event']) {
    case 'started':
      return RemoteInstallStepStarted(
        RemoteInstallStep.values.byName(value['step'] as String),
      );
    case 'finished':
      return RemoteInstallStepFinished(
        RemoteInstallStep.values.byName(value['step'] as String),
        previouslyCompleted: value['reused'] as bool,
      );
    case 'installed':
      final token = value['sessionToken'];
      if (value['baseUrl'] != 'http://127.0.0.1:9119' ||
          token is! String ||
          token.isEmpty ||
          token.length > 4096 ||
          token.contains(RegExp(r'[\r\n]'))) {
        throw const FormatException('Invalid loopback authentication handoff.');
      }
      return RemoteInstallCompleted(
        RemoteInstallOutcome(
          baseUrl: 'http://127.0.0.1:9119',
          username: '',
          password: '',
          sessionToken: token,
        ),
      );
    default:
      throw const FormatException('Unexpected installation event.');
  }
}

Map<String, Object?>? serviceUninstallEvent(RemoteUninstallProgress event) =>
    switch (event) {
      RemoteUninstallStepStarted(:final step) => {
        'event': 'started',
        'step': step.name,
      },
      RemoteUninstallStepFinished(:final step) => {
        'event': 'finished',
        'step': step.name,
      },
      RemoteUninstallLog() => null,
      RemoteUninstallCompleted(:final outcome) => {
        'event': 'uninstalled',
        'purged': outcome.purged,
        'removed': outcome.removed,
        'preserved': outcome.preserved.map(serviceResourceJson).toList(),
        'warnings': outcome.warnings,
        'complete': outcome.complete,
      },
    };

RemoteUninstallProgress serviceUninstallFromJson(Map<String, Object?> value) =>
    switch (value['event']) {
      'started' => RemoteUninstallStepStarted(
        RemoteUninstallStep.values.byName(value['step'] as String),
      ),
      'finished' => RemoteUninstallStepFinished(
        RemoteUninstallStep.values.byName(value['step'] as String),
      ),
      'uninstalled' => RemoteUninstallCompleted(
        RemoteUninstallOutcome(
          purged: value['purged'] as bool,
          removed: (value['removed'] as List).cast<String>(),
          preserved: (value['preserved'] as List)
              .map(
                (item) => RemoteUninstallResource.fromJson(serviceObject(item)),
              )
              .toList(),
          warnings: (value['warnings'] as List).cast<String>(),
          complete: value['complete'] as bool,
        ),
      ),
      _ => throw const FormatException('Unexpected removal event.'),
    };

/// Frames a bounded UTF-8 JSON-line protocol without accumulating partial input.
Stream<String> serviceLines(Stream<List<int>> bytes) {
  final pending = StringBuffer();
  // A synchronous transformer propagates cancellation to an idle input pipe.
  // An async generator awaiting the next chunk would keep the helper alive.
  return bytes
      .transform(utf8.decoder)
      .transform(
        StreamTransformer<String, String>.fromHandlers(
          handleData: (text, sink) {
            for (final part in text.split('\n').indexed) {
              if (part.$1 > 0) {
                sink.add(pending.toString());
                pending.clear();
              }
              if (pending.length + part.$2.length > 65536) {
                sink.addError(
                  const FormatException('Service-helper frame too large.'),
                );
                sink.close();
                return;
              }
              pending.write(part.$2);
            }
          },
          handleDone: (sink) {
            if (pending.isNotEmpty) {
              sink.addError(const FormatException('Truncated helper frame.'));
            }
            sink.close();
          },
        ),
      );
}

/// Maps fixed refusal categories to advice without forwarding command output.
String? serviceMigrationRefusal(String detail) {
  const messages = <String, String>{
    'Stop processes': 'Stop the legacy and canonical Hermes processes before migration, then inspect again.',
    'Legacy data changed': 'Legacy data changed after inspection. Inspect it again and confirm the new inventory.',
    'Legacy directories changed': 'Legacy directories changed after inspection. Inspect again before confirming migration.',
    'Canonical Hermes data already exists': 'Canonical Hermes data already exists. Use that instance; migration never merges installations.',
    'Backup verification failed': 'Backup verification failed. Original data and the retained backup were preserved; recover them before retrying.',
    'The retained backup no longer matches': 'The retained backup changed. Original data was preserved; verify the backup before retrying.',
    'Interrupted backup has no ownership receipt': 'An interrupted backup needs manual recovery. Original data was preserved.',
    'Legacy data does not belong': 'Legacy data must belong to your desktop account. Correct ownership and inspect again.',
    'Legacy data contains files owned': 'Legacy data contains files owned by another account. Correct ownership before migration.',
    'Group/world-writable legacy data':
        'Remove group/world write access from legacy data before migration.',
    'An absolute normalized': 'Use an ordinary, absolute legacy data directory under your desktop account home.',
    'A profile symlink escapes': 'A profile link points outside the legacy data directory. Correct the link before migration.',
    'Broken, chained, or runtime-linked': 'A profile link is broken, chained, or points into a runtime. Correct it before migration.',
    'Existing computer runtime references block automatic migration': 'Stop the old computer and export its persistent /home/hermuse volume. Restore it separately after verified canonical setup; computer names may be shared.',
    'Desktop subscription auth has no complete configuration': 'Restore complete desktop bridge configuration and OAuth files before migration.',
    'Incomplete or nonlocal desktop bridge': 'Restore a complete local desktop bridge configuration and OAuth files before migration.',
    'A local model endpoint has no preserved server bridge credentials': 'Restore the bridge credentials for the local model endpoint before migration.',
    'Both desktop and server subscription bridges contain data': 'Both subscription bridges contain data. Resolve that conflict first; migration never merges credentials.',
  };
  for (final entry in messages.entries) {
    if (detail.contains(entry.key)) return entry.value;
  }
  return null;
}

String? _preflightRefusal(String detail) {
  const messages = {
    'An unrelated plugin occupies the Hermuse plugin directory.': 'The plugin at /home/hermes/.hermes/plugins/hermuse is not owned by this installer and was left unchanged. Use Connect with a dashboard URL to connect to the existing instance without reinstalling it.',
    'The hermes user already exists and is not owned by this installer.': 'The existing hermes account is not owned by this installer. It was left unchanged; connect to its existing dashboard instead.',
    'An unrelated hermuse-dashboard.service exists; it will not be overwritten.': 'An unmanaged hermuse-dashboard.service already exists and was left unchanged. Connect to its existing dashboard instead.',
    'An unrelated hermuse-gateway.service exists; it will not be overwritten.': 'An unmanaged hermuse-gateway.service already exists and was left unchanged. Remove or rename that scheduler service before setup.',
    '/home/hermes already exists; it will not be overwritten.': '/home/hermes already contains an unmanaged home. It was left unchanged; resolve that directory conflict before setup.',
    'At least 4 GB RAM is required.':
        'This installation requires at least 4 GB of RAM.',
    'At least 10 GiB free disk under /home is required.': 'This installation requires at least 10 GiB of free disk space under /home.',
    'A running systemd is required.':
        'A running systemd is required to manage the Hermes service.',
    'Supported servers: Ubuntu 24.04/26.04 or Debian 12/13.':
        'Local setup supports Ubuntu 22.04/24.04/26.04 and Debian 12/13.',
    'Installer ownership paths must not be symlinks.': 'An installer ownership path is a symbolic link. Nothing was replaced; resolve that unsafe path before setup.',
    'Installer ownership paths must be root-owned and not writable by other users.': 'Installer ownership metadata has unsafe permissions. Restore root ownership and remove non-root write access before setup.',
    'Refusing a symlink at managed path:': 'A managed installation path is a symbolic link. Nothing was replaced; resolve that unsafe path before setup.',
  };
  for (final entry in messages.entries) {
    if (detail.contains(entry.key)) return entry.value;
  }
  return null;
}

/// Safe failures preserve the stage and known refusal category, never stderr.
Map<String, Object?> serviceFailureEvent(Object error) {
  if (error is RemoteInstallCancelled) {
    return {
      'event': 'error',
      'step': 'service',
      'code': 'cancelled',
      'message': 'The operation was cancelled at a safe command boundary.',
    };
  }
  if (error is RemoteInstallFailed) {
    final step =
        {
          ...RemoteInstallStep.values.map((value) => value.name),
          ...RemoteUninstallStep.values.map((value) => value.name),
          'migration',
          'service',
        }.contains(error.step)
        ? error.step
        : 'service';
    final preflight = step == 'preflight'
        ? _preflightRefusal(error.message)
        : null;
    final migration = serviceMigrationRefusal(error.message);
    final connection = error.message.contains('HERMUSE_CONNECT_REFUSED_V1')
        ? 'The existing dashboard could not be safely connected. It must be an active, unmodified canonical system service without overrides and support private desktop authentication. Ask its administrator to inspect the service; no installation or repair was attempted.'
        : null;
    final refusal = connection ?? preflight ?? migration;
    return {
      'event': 'error',
      'step': step,
      'code': connection != null
          ? 'connect-refused'
          : preflight != null
          ? 'preflight-refused'
          : migration != null
          ? 'migration-refused'
          : 'stage-failed',
      'message':
          refusal ??
          'The system-service operation failed during $step. Existing data was retained; inspect before retrying.',
    };
  }
  return {
    'event': 'error',
    'step': 'service',
    'code': 'refused',
    'message': error is FormatException && error.source == null
        ? error.message
        : 'The system-service operation failed. Existing data was retained; inspect before retrying.',
  };
}
