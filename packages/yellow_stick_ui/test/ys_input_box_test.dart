import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

Future<TextEditingController> _pump(
  WidgetTester tester, {
  bool obscure = false,
}) async {
  final controller = TextEditingController();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: YsTheme(
        palette: YsPalette.dark,
        child: Center(
          child: SizedBox(
            width: 320,
            child: YsInputBox(
              controller: controller,
              placeholder: 'https://hermes.example.com',
              obscure: obscure,
            ),
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  for (final obscure in [false, true]) {
    testWidgets('placeholder and text sit on the box centre line '
        '(obscure: $obscure)', (tester) async {
      final controller = await _pump(tester, obscure: obscure);
      final box = tester.getRect(find.byType(YsInputBox));

      final placeholder = tester.getRect(
        find.text('https://hermes.example.com'),
      );
      expect(placeholder.center.dy, closeTo(box.center.dy, 1));

      controller.text = 'secret';
      await tester.pump();
      final text = tester.getRect(find.byType(EditableText));
      expect(text.center.dy, closeTo(box.center.dy, 1));
      expect(find.text('https://hermes.example.com'), findsNothing);
    });
  }
}
