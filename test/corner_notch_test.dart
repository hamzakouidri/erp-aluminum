import 'package:database_data/Commande/Systeme/corner_notch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const w = 2000.0, h = 1500.0;

  group('uncut frame', () {
    test('is the plain rectangle', () {
      const n = CornerNotches.none;
      expect(n.hasAny, isFalse);
      expect(n.outline(w, h), const [
        Offset(0, 0),
        Offset(w, 0),
        Offset(w, h),
        Offset(0, h),
      ]);
      expect(n.perimeter(w, h), 2 * (w + h));
      expect(n.frameCutLengths(w, h, profileWidth: 60), [w, h, w, h]);
      expect(n.toJson(), isEmpty);
    });
  });

  group('top-left step', () {
    const n = CornerNotches(
      topLeft: CornerNotch(width: 500, height: 300),
    );

    test('outline has six vertices with one reflex corner', () {
      expect(n.outline(w, h), const [
        Offset(0, 300),
        Offset(500, 300),
        Offset(500, 0),
        Offset(w, 0),
        Offset(w, h),
        Offset(0, h),
      ]);
      final sides = n.sides(w, h);
      expect(sides.map((s) => s.length), [500, 300, 1500, 1500, 2000, 1200]);
      expect(sides.where((s) => s.reflexEnd).length, 1);
      expect(sides[0].notchCorner, NotchCorner.topLeft);
      expect(sides[1].notchCorner, NotchCorner.topLeft);
      expect(sides[2].notchCorner, isNull);
    });

    test('a 90° step keeps the perimeter', () {
      expect(n.perimeter(w, h), 2 * (w + h));
    });

    test('cut lengths add one profile width at the reflex end', () {
      expect(n.frameCutLengths(w, h, profileWidth: 60), [
        560, // step, horizontal: reflex at its end
        360, // step, vertical: reflex at its start
        1500,
        1500,
        2000,
        1200,
      ]);
    });

    test('inner edge moves inward on both kinds of corner', () {
      final inner = n.insetOutline(w, h, inset: 60);
      expect(inner[0], const Offset(60, 360));
      expect(inner[1], const Offset(560, 360));
      expect(inner[2], const Offset(560, 60));
      expect(inner[3], const Offset(w - 60, 60));
    });
  });

  test('four cut corners: twelve sides, four reflex corners', () {
    const n = CornerNotches(
      topLeft: CornerNotch(width: 300, height: 200),
      topRight: CornerNotch(width: 400, height: 250),
      bottomRight: CornerNotch(width: 200, height: 300),
      bottomLeft: CornerNotch(width: 250, height: 150),
    );
    final sides = n.sides(w, h);
    expect(sides.length, 12);
    expect(sides.where((s) => s.reflexStart).length, 4);
    expect(n.perimeter(w, h), 2 * (w + h));
    expect(n.validate(w, h), isNull);
    final cuts = n.frameCutLengths(w, h, profileWidth: 50);
    expect(cuts.reduce((a, b) => a + b), 2 * (w + h) + 8 * 50);
  });

  group('limits', () {
    test('a small drag removes the cut', () {
      expect(
        CornerNotches.none.clampNotch(NotchCorner.topLeft, 30, 300, w, h),
        CornerNotch.none,
      );
    });

    test('a cut keeps the minimum side', () {
      final c = CornerNotches.none.clampNotch(
        NotchCorner.topLeft,
        60,
        h,
        w,
        h,
      );
      expect(c.width, CornerNotches.minSideMm);
      expect(c.height, h - CornerNotches.minSideMm);
    });

    test('neighbour cuts never meet', () {
      const n = CornerNotches(topLeft: CornerNotch(width: 1200, height: 300));
      final c = n.clampNotch(NotchCorner.topRight, 1500, 300, w, h);
      expect(c.width, w - 1200 - CornerNotches.minSideMm);
      expect(n.withCorner(NotchCorner.topRight, c).validate(w, h), isNull);
      expect(
        n
            .withCorner(
              NotchCorner.topRight,
              const CornerNotch(width: 900, height: 300),
            )
            .validate(w, h),
        'notch_overlap',
      );
    });

    test('opposite cuts never overlap', () {
      const n = CornerNotches(topLeft: CornerNotch(width: 1500, height: 1000));
      final c = n.clampNotch(NotchCorner.bottomRight, 1000, 800, w, h);
      final cut = n.withCorner(NotchCorner.bottomRight, c);
      expect(cut.validate(w, h), isNull);
    });
  });

  test('JSON round trip', () {
    const n = CornerNotches(
      topRight: CornerNotch(width: 400, height: 250),
      bottomLeft: CornerNotch(width: 250, height: 150),
    );
    final json = n.toJson();
    expect(json.keys, ['tr', 'bl']);
    expect(CornerNotches.fromJson(json), n);
    expect(CornerNotches.fromJson(null), CornerNotches.none);
    expect(CornerNotches.fromJson('bad'), CornerNotches.none);
  });
}
