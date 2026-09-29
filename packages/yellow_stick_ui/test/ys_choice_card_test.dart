import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

Widget _frame(Widget child, {bool reduced = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduced),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: YsTheme(
      palette: YsPalette.dark,
      child: Center(child: child),
    ),
  ),
);

void main() {
  testWidgets('a choice card activates on click, Enter and Space', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _frame(
        YsChoiceCard(
          art: YsArt.remote,
          title: 'Connect to a Hermes',
          body: 'A Hermes on a server.',
          autofocus: true,
          onPressed: () => presses++,
        ),
      ),
    );
    await tester.tap(find.text('Connect to a Hermes'));
    expect(presses, 1);

    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(presses, 3);
    await tester.pumpAndSettle();
  });

  testWidgets('with reduced motion, illustrations and cards never tick', (
    tester,
  ) async {
    await tester.pumpWidget(
      _frame(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            YsChoiceCard(
              art: YsArt.local,
              title: 'Install Hermes on this computer',
              onPressed: () {},
            ),
            YsArtView(YsArt.feed),
            const YsEntrance(child: SizedBox(width: 10, height: 10)),
          ],
        ),
        reduced: true,
      ),
    );
    expect(tester.binding.hasScheduledFrame, isFalse);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(YsChoiceCard)));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('without reduced motion an illustration draws in, then rests', (
    tester,
  ) async {
    await tester.pumpWidget(_frame(YsArtView(YsArt.goals)));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
