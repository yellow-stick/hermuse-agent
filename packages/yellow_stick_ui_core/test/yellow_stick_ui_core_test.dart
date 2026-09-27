import 'package:test/test.dart';
import 'package:yellow_stick_ui_core/yellow_stick_ui_core.dart';

void main() {
  test('opaque colours render as rgb(), translucent ones as rgba()', () {
    expect(const YsColor(0xFF181819).css, 'rgb(24, 24, 25)');
    expect(const YsColor(0x1FFFFFFF).css, 'rgba(255, 255, 255, 0.122)');
  });

  test('shell switches at the documented breakpoints', () {
    expect(YsShell.forWidth(YsLayout.compactMax - 1), YsShell.compact);
    // The rail + docked panel appear together at 768 (no medium band).
    expect(YsShell.forWidth(YsLayout.compactMax), YsShell.wide);
    expect(YsShell.forWidth(YsLayout.wideMin - 1), YsShell.compact);
    expect(YsShell.forWidth(YsLayout.wideMin), YsShell.wide);
  });

  group('icon motion', () {
    final motions = [for (final icon in YsIcon.values) ?YsIconMotion.of(icon)];

    test('tracks hold outside their keyframes and ease in between', () {
      const track = YsMotionTrack(YsMotionProperty.rotate, [
        YsKeyframe(10, 0, YsEase.linear),
        YsKeyframe(20, 8),
      ]);
      expect(track.valueAt(0), 0);
      expect(track.valueAt(15), closeTo(4, 1e-9));
      expect(track.valueAt(40), 8);
      expect(YsEase.standard.transform(0.5), closeTo(0.77, 0.01));
    });

    test('parts exist and trims target paths', () {
      for (final m in motions) {
        final elements = m.elements;
        for (final part in m.parts) {
          final index = part.part;
          if (index == null) continue;
          expect(index, lessThan(elements.length), reason: '${m.icon}');
          if (part.track(YsMotionProperty.trimEnd) != null) {
            expect(elements[index], startsWith('<path'), reason: '${m.icon}');
          }
        }
      }
    });

    test('extras are hidden at rest and fade out by the end', () {
      for (final m in motions) {
        for (var i = m.bodyCount; i < m.elements.length; i++) {
          final part = m.part(i);
          expect(
            part?.track(YsMotionProperty.opacity),
            isNotNull,
            reason: '${m.icon} extra $i must animate its opacity',
          );
          expect(part!.valueAt(YsMotionProperty.opacity, m.frames), 0);
        }
      }
    });

    test('body parts end at rest, so the icon does not jump when done', () {
      for (final m in motions) {
        for (final part in m.parts) {
          final index = part.part;
          if (index != null && index >= m.bodyCount) continue;
          for (final track in part.tracks) {
            expect(
              track.valueAt(m.frames),
              track.property.rest,
              reason: '${m.icon} ${index ?? 'root'} ${track.property}',
            );
          }
        }
      }
    });
  });
}
