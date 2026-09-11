import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  test('plinthe preserves the neighbouring sliding frame and sash', () {
    final model = fixtures.makeWindow(fixtures.RuleDatabase());
    final opening = WindowZone(
      id: 'opening',
      boundary: const Rect.fromLTRB(50, 50, 450, 1150),
      content: ZoneContent.doubleSash,
    );
    final sliding = WindowZone(
      id: 'sliding',
      boundary: const Rect.fromLTRB(550, 50, 950, 1150),
      content: ZoneContent.slidingSash,
    );
    model.zones
      ..clear()
      ..addAll([opening, sliding]);
    final originalSliding = sliding.boundary;

    model.toggleFramePlintheBottom(true);

    expect(opening.hasSashPlintheBottom, isTrue);
    expect(sliding.hasSashPlintheBottom, isFalse);
    expect(sliding.boundary, originalSliding);
    expect(
      model.hasBottomFrameForRect(const Rect.fromLTRB(0, 0, 500, 1250)),
      isFalse,
    );
    expect(
      model.hasBottomFrameForRect(const Rect.fromLTRB(500, 0, 1000, 1200)),
      isTrue,
    );

    model.toggleFramePlintheBottom(false);
    expect(opening.hasSashPlintheBottom, isFalse);
    expect(sliding.boundary, originalSliding);
    expect(
      model.hasBottomFrameForRect(const Rect.fromLTRB(0, 0, 500, 1200)),
      isTrue,
    );
    model.dispose();
  });
}
