import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  testWidgets('hover shows a label-sized chip just above the target', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: YsTheme(
          palette: YsPalette.dark,
          child: Overlay.wrap(
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: EdgeInsets.all(40),
                child: YsTooltip(
                  message: 'Feed',
                  child: SizedBox(width: 32, height: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final target = tester.getRect(find.byType(SizedBox).last);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: target.center);
    await tester.pump();

    final chip = tester.getRect(
      find.ancestor(of: find.text('Feed'), matching: find.byType(DecoratedBox)),
    );
    final window = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(chip.width, lessThan(window.width / 4));
    expect(chip.height, lessThan(40));
    expect(chip.bottom, closeTo(target.top - 6, 0.5));
    expect(chip.center.dx, closeTo(target.center.dx, 0.5));

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('Feed'), findsNothing);
  });
}
