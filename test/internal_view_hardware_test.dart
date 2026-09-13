import 'dart:ui';

import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'inner face hides hardware by default and resets after a face switch',
    () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 500,
        height: 200,
        profileThickness: 10,
      );

      expect(model.isInternalView, isTrue);
      expect(model.showInternalHardware, isFalse);

      model.setInternalHardwareVisibility(true);
      expect(model.showInternalHardware, isTrue);

      model.toggleViewMode();
      expect(model.isInternalView, isFalse);
      model.toggleViewMode();
      expect(model.isInternalView, isTrue);
      expect(model.showInternalHardware, isFalse);
    },
  );

  test(
    'mixed sliding-only drawing keeps sliding profiles with fixed glass',
    () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1000,
        height: 600,
        profileThickness: 45,
        systemMode: 'mixed',
      );

      model.zones = [
        WindowZone(
          id: 'fixed',
          boundary: const Rect.fromLTWH(0, 0, 400, 600),
          content: ZoneContent.fixedGlass,
        ),
        WindowZone(
          id: 'sliding',
          boundary: const Rect.fromLTWH(400, 0, 600, 600),
          content: ZoneContent.slidingSash,
        ),
      ];

      expect(model.usesSlidingPrimaryProfiles, isTrue);
      expect(
        model.frameUsesSlidingSeries(const Rect.fromLTWH(0, 0, 1000, 600)),
        isTrue,
        reason: 'fixed glass must keep the surrounding TPR frame on 67000',
      );

      model.zones.add(
        WindowZone(
          id: 'opening',
          boundary: const Rect.fromLTWH(0, 0, 200, 600),
          content: ZoneContent.singleSash,
        ),
      );
      expect(model.usesSlidingPrimaryProfiles, isFalse);
      expect(
        model.frameUsesSlidingSeries(const Rect.fromLTWH(0, 0, 1000, 600)),
        isFalse,
        reason: 'an actual opening sash makes the shared frame use 40000',
      );
    },
  );

  test(
    'split dialog pattern divides selected sash or every sash internally',
    () {
      final model = WindowModel(
        db: SqlDatabase(),
        width: 1200,
        height: 800,
        profileThickness: 40,
      );
      final doubleSash = WindowZone(
        id: 'double',
        boundary: const Rect.fromLTWH(0, 0, 800, 800),
        content: ZoneContent.doubleSash,
        sashThickness: 40,
      );
      final singleSash = WindowZone(
        id: 'single',
        boundary: const Rect.fromLTWH(800, 0, 400, 800),
        content: ZoneContent.singleSash,
        sashThickness: 40,
      );
      model.zones = [doubleSash, singleSash];
      model.selection = const SelectionInfo(
        type: SelectionType.zone,
        zoneId: 'double',
      );
      model.activeSubZone = 'right';

      model.configureSelectedSashDivisions(horizontal: true, parts: 3);
      expect(
        model.zones,
        hasLength(2),
        reason: 'outer frame must not be split',
      );
      expect(doubleSash.innerH, 0);
      expect(doubleSash.rightInnerH, 2);
      expect(singleSash.innerH, 0);

      model.configureSelectedSashDivisions(
        horizontal: false,
        parts: 3,
        applyToAllSashes: true,
      );
      expect(model.zones, hasLength(2));
      expect(doubleSash.innerV, 2);
      expect(doubleSash.rightInnerV, 2);
      expect(singleSash.innerV, 2);
    },
  );
}
