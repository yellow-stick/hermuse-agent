import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: YsTheme(
      palette: YsPalette.dark,
      child: Center(child: SizedBox(width: 400, child: child)),
    ),
  ),
);

void main() {
  group('YsButton', () {
    for (final (name, button) in [
      ('primary', YsButton.primary(label: 'Edit', onPressed: () {})),
      ('neutral', YsButton.neutral(label: 'Edit', onPressed: () {})),
      ('destructive', YsButton.destructive(label: 'Edit', onPressed: () {})),
    ]) {
      testWidgets('$name should hug its label under a loose width', (
        tester,
      ) async {
        await _pump(
          tester,
          Align(alignment: Alignment.centerRight, child: button),
        );

        final rect = tester.getRect(find.byType(YsButton));
        expect(rect.width, lessThan(120));
        expect(rect.right, 400 + (800 - 400) / 2);
      });

      testWidgets('$name should fill a stretched column', (tester) async {
        await _pump(
          tester,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [button],
          ),
        );

        expect(tester.getSize(find.byType(YsButton)).width, 400);
      });
    }
  });
}
