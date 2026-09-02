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

      model.zones.add(
        WindowZone(
          id: 'opening',
          boundary: const Rect.fromLTWH(0, 0, 200, 600),
          content: ZoneContent.singleSash,
        ),
      );
      expect(model.usesSlidingPrimaryProfiles, isFalse);
    },
  );
}
