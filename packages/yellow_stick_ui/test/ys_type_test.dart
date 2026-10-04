import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  test('text styles use bundled Inter, then system color emoji', () {
    final style = YsType.body.flutter;
    expect(style.fontFamily, 'packages/yellow_stick_ui/Inter');
    // System families stay unprefixed so the platform font is found.
    expect(style.fontFamilyFallback, YsType.emoji);
    expect(style.fontFamilyFallback, contains('Noto Color Emoji'));
    expect(
      style.copyWith(fontFamily: YsType.monoFamily).fontFamily,
      'monospace',
    );
  });
}
