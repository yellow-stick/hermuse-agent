import 'package:flutter/services.dart';

/// Asset folder holding the bundled plugin (see `tool/sync_plugin_assets.dart`).
const pluginAssetPrefix = 'assets/hermes-plugin/hermuse/';

/// Loads the packaged plugin with paths relative to its install directory.
Future<Map<String, Uint8List>> loadPluginBundle({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  final manifest = await AssetManifest.loadFromAssetBundle(assets);
  final files = <String, Uint8List>{};
  for (final key in manifest.listAssets()) {
    if (!key.startsWith(pluginAssetPrefix)) continue;
    final data = await assets.load(key);
    files[key.substring(pluginAssetPrefix.length)] = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
  }
  if (files.isEmpty) {
    throw StateError(
      'The bundled Hermuse plugin is missing. Reinstall the app.',
    );
  }
  return files;
}
