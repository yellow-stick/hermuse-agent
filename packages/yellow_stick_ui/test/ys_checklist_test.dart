import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yellow_stick_ui/yellow_stick_ui.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) => tester.pumpWidget(
  MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: YsTheme(
        palette: YsPalette.dark,
        child: Center(child: SizedBox(width: 400, child: child)),
      ),
    ),
  ),
);

YsChecklistItem _step(YsStepState state, {double? progress}) => YsChecklistItem(
  id: 'packages',
  icon: YsIcon.package,
  title: 'System packages',
  state: state,
  status: state.name,
  progress: progress,
  notes: const [YsChecklistNote('Why it is needed.')],
  actions: [
    YsButton.neutral(
      key: const ValueKey('action'),
      label: 'Prepare',
      onPressed: () {},
    ),
  ],
);

void main() {
  group('YsChecklist', () {
    testWidgets('should unfold a row\'s notes and actions only while it '
        'needs the user, failed or waits on another step', (tester) async {
      // The same row through every state, as a setup moves it along.
      for (final state in YsStepState.values) {
        await _pump(
          tester,
          YsChecklist(items: [_step(state)]),
          reduceMotion: true,
        );

        final unfolded =
            state == YsStepState.needsAction ||
            state == YsStepState.failed ||
            state == YsStepState.pending;
        expect(
          find.byKey(const ValueKey('action')),
          unfolded ? findsOneWidget : findsNothing,
          reason: state.name,
        );
        expect(
          find.text('Why it is needed.'),
          unfolded ? findsOneWidget : findsNothing,
          reason: state.name,
        );
      }
    });

    testWidgets('should show every state at once when animations are '
        'disabled', (tester) async {
      for (final state in YsStepState.values) {
        await _pump(
          tester,
          YsChecklist(items: [_step(state, progress: 0.4)]),
          reduceMotion: true,
        );

        expect(tester.binding.hasScheduledFrame, isFalse, reason: state.name);
      }
    });

    testWidgets('should enter, draw its marks and settle otherwise', (
      tester,
    ) async {
      await _pump(tester, YsChecklist(items: [_step(YsStepState.pending)]));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();

      await _pump(tester, YsChecklist(items: [_step(YsStepState.done)]));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('YsProgressRing', () {
    testWidgets('should end the ready moment at once when animations are '
        'disabled', (tester) async {
      var completed = 0;

      await _pump(
        tester,
        YsProgressRing(
          value: 1,
          complete: true,
          onCompleted: () => completed++,
        ),
        reduceMotion: true,
      );
      await tester.pump();

      expect(completed, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('should hold the ready moment, then end it once', (
      tester,
    ) async {
      var completed = 0;
      Widget ring({required bool complete}) => YsProgressRing(
        value: 6 / 7,
        label: '6/7',
        complete: complete,
        onCompleted: () => completed++,
      );

      await _pump(tester, ring(complete: false));
      await tester.pumpAndSettle();
      await _pump(tester, ring(complete: true));
      await tester.pump(const Duration(milliseconds: 16));
      expect(completed, 0);

      await tester.pumpAndSettle();
      expect(completed, 1);
      await _pump(tester, ring(complete: true));
      await tester.pumpAndSettle();
      expect(completed, 1);
    });
  });
}
