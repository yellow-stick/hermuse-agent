import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/sync_plugin_assets.dart';

void main() {
  test('bundled plugin assets match hermes-plugin/hermuse', () {
    final source = pluginFiles(sourceDir);
    expect(
      pluginFiles(assetDir),
      source,
      reason: 'run tool/sync_plugin_assets.dart',
    );
    for (final rel in source) {
      expect(
        File('$assetDir/$rel').readAsBytesSync(),
        File('$sourceDir/$rel').readAsBytesSync(),
        reason: '$rel differs: run tool/sync_plugin_assets.dart',
      );
    }
  });
}
