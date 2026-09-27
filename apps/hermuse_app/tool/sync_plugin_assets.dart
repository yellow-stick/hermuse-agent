// Copies the Hermes plugin sources (`hermes-plugin/hermuse`, minus tests and
// caches) into `assets/hermes-plugin/hermuse/` so desktop builds can install
// the plugin on the local Hermes. Run from `apps/hermuse_app`:
//   dart run tool/sync_plugin_assets.dart
// `test/plugin_assets_test.dart` fails when the copy drifts from the source.
import 'dart:io';

const sourceDir = '../../hermes-plugin/hermuse';
const assetDir = 'assets/hermes-plugin/hermuse';

/// Plugin files shipped to users, relative to [sourceDir], sorted.
List<String> pluginFiles(String root) {
  final base = Directory(root).absolute.path;
  final files = <String>[];
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.absolute.path
        .substring(base.length + 1)
        .replaceAll(r'\', '/');
    final parts = rel.split('/');
    if (parts.first == 'tests' ||
        parts.contains('__pycache__') ||
        parts.any((p) => p.startsWith('.'))) {
      continue;
    }
    files.add(rel);
  }
  return files..sort();
}

void main() {
  final target = Directory(assetDir);
  if (target.existsSync()) target.deleteSync(recursive: true);
  for (final rel in pluginFiles(sourceDir)) {
    final dest = File('$assetDir/$rel')..parent.createSync(recursive: true);
    File('$sourceDir/$rel').copySync(dest.path);
  }
  stdout.writeln('synced ${pluginFiles(assetDir).length} files');
}
