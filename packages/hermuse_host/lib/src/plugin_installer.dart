// Private fields with public constructor params need explicit initializers.
// ignore_for_file: prefer_initializing_formals
import 'dart:io';

import 'detector.dart';
import 'errors.dart';

/// Result of [HermusePluginInstaller.install].
final class HermusePluginInstall {
  const HermusePluginInstall({
    required this.pluginDir,
    required this.overwrote,
    required this.enableOutput,
  });

  /// `$HERMES_HOME/plugins/hermuse`.
  final String pluginDir;

  /// True when an identical existing install was replaced.
  final bool overwrote;

  /// Combined stdout of `hermes plugins enable hermuse`.
  final String enableOutput;
}

/// Installs the Hermuse product-layer plugin into a LOCAL instance's
/// `$HERMES_HOME/plugins/hermuse` and enables it.
///
/// Steps mirror the plugin README: recursive copy of the `hermes-plugin/hermuse`
/// source tree (excluding `tests/`), then `hermes plugins enable hermuse`
/// with `HERMES_HOME` pointed at the instance home. The dashboard/gateway
/// must restart afterwards for the new routes to load (owned by the caller:
/// [HermesSupervisor.restart] on a supervised instance).
///
/// Safety: an existing `plugins/hermuse` dir whose `plugin.yaml` does NOT
/// describe the Hermuse plugin is never touched unless [overwrite] is true;
/// an identical existing install is refreshed in place. Remote instances are
/// refused — Hermuse cannot write their filesystem.
final class HermusePluginInstaller {
  HermusePluginInstaller({
    required String pluginSourceDir,
    Future<ProcessResult> Function(
      String executable,
      List<String> args, {
      Map<String, String>? environment,
    })?
    runProcess,
  }) : _pluginSourceDir = pluginSourceDir,
       _runProcess =
           runProcess ??
           ((executable, args, {environment}) =>
               Process.run(executable, args, environment: environment));

  final String _pluginSourceDir;
  final Future<ProcessResult> Function(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
  })
  _runProcess;

  /// Plugin dir name under `$HERMES_HOME/plugins/`.
  static const pluginName = 'hermuse';

  /// Installs + enables the plugin for the instance at [hermesHome] using
  /// the [hermesExecutable] launcher.
  Future<HermusePluginInstall> install({
    required String hermesHome,
    required String hermesExecutable,
    bool overwrite = false,
  }) async {
    final source = Directory(_pluginSourceDir);
    if (!await source.exists()) {
      throw PrerequisiteMissing(
        'Hermuse plugin sources not found at $_pluginSourceDir',
      );
    }
    final manifest = File('${source.path}${Platform.pathSeparator}plugin.yaml');
    if (!await manifest.exists()) {
      throw PrerequisiteMissing(
        '$_pluginSourceDir is not a plugin tree (no plugin.yaml)',
      );
    }
    final target = Directory(
      '$hermesHome${Platform.pathSeparator}plugins'
      '${Platform.pathSeparator}$pluginName',
    );
    var overwrote = false;
    if (await target.exists()) {
      if (!await _isHermusePlugin(target)) {
        if (!overwrite) {
          throw InstallFailed(
            'plugin-copy',
            '${target.path} holds a different plugin; '
                'pass overwrite: true to replace it',
          );
        }
      } else {
        overwrote = true;
      }
      await target.delete(recursive: true);
    }
    await _copyTree(source, target);
    final enable = await _runProcess(
      hermesExecutable,
      ['plugins', 'enable', pluginName],
      environment: {'HERMES_HOME': hermesHome},
    );
    if (enable.exitCode != 0) {
      throw InstallFailed(
        'plugins-enable',
        'hermes plugins enable $pluginName failed '
            '(exit ${enable.exitCode}): ${enable.stdout}${enable.stderr}',
      );
    }
    return HermusePluginInstall(
      pluginDir: target.path,
      overwrote: overwrote,
      enableOutput: '${enable.stdout}'.trim(),
    );
  }

  /// True when [dir] looks like an installed Hermuse plugin.
  Future<bool> _isHermusePlugin(Directory dir) async {
    final manifest = File('${dir.path}${Platform.pathSeparator}plugin.yaml');
    if (!await manifest.exists()) return false;
    try {
      final text = await manifest.readAsString();
      return RegExp(r'^name:\s*hermuse\s*$', multiLine: true).hasMatch(text);
    } on Object {
      return false;
    }
  }

  Future<void> _copyTree(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        if (name == 'tests' || name == '__pycache__') continue;
        await _copyTree(
          entity,
          Directory('${target.path}${Platform.pathSeparator}$name'),
        );
      } else if (entity is File) {
        await entity.copy('${target.path}${Platform.pathSeparator}$name');
      }
    }
  }
}

/// Resolves the plugin source tree bundled next to this package.
///
/// Layout: `<repo>/packages/hermuse_host` + `<repo>/hermes-plugin/hermuse`.
/// Returns null when the checkout layout does not contain it (installed app
/// bundles ship the tree elsewhere — the app passes the path explicitly).
Future<String?> findBundledPluginSource() async {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate =
        '${dir.path}${Platform.pathSeparator}hermes-plugin'
        '${Platform.pathSeparator}hermuse';
    if (await File('$candidate${Platform.pathSeparator}plugin.yaml').exists()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

/// Convenience: install into a [DetectedHermes] home.
extension HermusePluginInstallerOnDetection on HermusePluginInstaller {
  Future<HermusePluginInstall> installFor(
    DetectedHermes hermes, {
    bool overwrite = false,
  }) => install(
    hermesHome: hermes.home,
    hermesExecutable: hermes.executable,
    overwrite: overwrite,
  );
}
