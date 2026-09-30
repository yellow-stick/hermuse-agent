import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  testWidgets('a skeleton box without a width spans its column', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: YsTheme(
            palette: YsPalette.dark,
            child: Center(
              child: SizedBox(
                width: 300,
                child: YsSkeleton(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.5,
                        child: YsSkeletonBox(height: 20),
                      ),
                      YsSkeletonBox(height: 14),
                      YsSkeletonBox(height: 14, width: 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boxes = find.byType(YsSkeletonBox);
    expect(tester.getSize(boxes.at(0)), const Size(150, 20));
    expect(tester.getSize(boxes.at(1)), const Size(300, 14));
    expect(tester.getSize(boxes.at(2)), const Size(120, 14));
  });
}
