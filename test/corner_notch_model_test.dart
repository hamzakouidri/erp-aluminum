import 'package:database_data/Commande/Systeme/corner_notch.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<Database?> get db async => null;
}

WindowModel _window() {
  final model = WindowModel(db: FakeSqlDatabase());
  model.width = 2000;
  model.height = 1500;
  final t = model.profileThickness;
  model.zones = [
    WindowZone(
      id: 'glass',
      content: ZoneContent.fixedGlass,
      boundary: Rect.fromLTRB(t, t, 2000 - t, 1500 - t),
    ),
  ];
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plain window has no cut and keeps its JSON', () {
    final model = _window();
    expect(model.hasCornerNotches, isFalse);
    expect(model.toMap().containsKey('cornerNotches'), isFalse);
    expect(model.cornerNotchBlocker, isNull);
  });

  test('a cut changes the outline only: no mullion, the zone stays full', () {
    final model = _window();
    final before = model.zones.single.boundary;
    final error = model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    expect(error, isNull);
    expect(
      model.cornerNotches.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    expect(model.zones.length, 1);
    expect(model.zones.single.boundary, before);
    expect(model.mullionCreationOrder, isEmpty);
  });

  test('changing and removing a cut leaves the zones alone', () {
    final model = _window();
    final before = model.zones.single.boundary;
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 600, height: 400),
    );
    expect(
      model.cornerNotches.topLeft,
      const CornerNotch(width: 600, height: 400),
    );
    model.setCornerNotch(NotchCorner.topLeft, CornerNotch.none);
    expect(model.hasCornerNotches, isFalse);
    expect(model.zones.single.boundary, before);
  });

  test('a thicker frame (another series) keeps the cut sizes', () {
    final model = _window();
    for (final c in [NotchCorner.topLeft, NotchCorner.bottomRight]) {
      model.setCornerNotch(c, const CornerNotch(width: 600, height: 400));
    }
    final before = model.cornerNotches;
    model.frameOverride = {'visible_width': 70.0};
    model.updateProfileThickness();
    model.notifyListeners();
    expect(model.profileThickness, 70.0);
    expect(model.cornerNotches, before);
    expect(
      model.zones.single.boundary,
      const Rect.fromLTRB(70, 70, 2000 - 70, 1500 - 70),
    );
  });

  test('a smaller frame shortens a cut that no longer fits', () {
    final model = _window();
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    model.width = 700;
    model.notifyListeners();
    final cut = model.cornerNotches.topLeft;
    expect(cut.isCut, isTrue);
    expect(cut.width, lessThanOrEqualTo(700 - CornerNotches.minSideMm));
    expect(cut.height, 300);
  });

  test('four cut corners keep a single full zone', () {
    final model = _window();
    for (final c in NotchCorner.values) {
      expect(
        model.setCornerNotch(c, const CornerNotch(width: 300, height: 250)),
        isNull,
      );
    }
    expect(
      NotchCorner.values.every((c) => model.cornerNotches.of(c).isCut),
      isTrue,
    );
    expect(model.zones.length, 1);
  });

  test('undo restores the window before the cut', () {
    final model = _window();
    model.setCornerNotch(
      NotchCorner.topRight,
      const CornerNotch(width: 500, height: 300),
    );
    expect(model.hasCornerNotches, isTrue);
    model.undo();
    expect(model.hasCornerNotches, isFalse);
    model.redo();
    expect(
      model.cornerNotches.topRight,
      const CornerNotch(width: 500, height: 300),
    );
    expect(model.zones.length, 1);
  });

  test('save and load keep the cut', () {
    final model = _window();
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 700, height: 350),
    );
    final map = model.toMap();
    expect(map['cornerNotches'], {
      'tl': {'w': 700.0, 'h': 350.0},
    });
    final loaded = WindowModel(db: FakeSqlDatabase());
    applyWindowModelFromMap(loaded, map);
    expect(loaded.cornerNotches, model.cornerNotches);
  });

  test('a shutter or a slanted head blocks the cut', () {
    final model = _window()..hasShutter = true;
    expect(model.cornerNotchBlocker, 'notch_no_shutter');
    expect(
      model.setCornerNotch(
        NotchCorner.topLeft,
        const CornerNotch(width: 500, height: 300),
      ),
      'notch_no_shutter',
    );
    expect(model.hasCornerNotches, isFalse);

    final slanted = _window()..topSlantLeftY = 200;
    expect(slanted.cornerNotchBlocker, 'notch_no_shaped_head');
  });

  test('side covers and a cut corner exclude each other', () {
    final covered = _window()..hasSideCovers = true;
    expect(covered.cornerNotchBlocker, 'notch_no_side_covers');

    final model = _window();
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 500, height: 300),
    );
    model.toggleSideCovers(true);
    expect(model.hasSideCovers, isFalse);
  });

  test('a cut window refuses a shutter and a slant', () {
    final model = _window();
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 500, height: 300),
    );
    model.toggleShutter(true);
    expect(model.hasShutter, isFalse);
    model.updateTopSlantAndArch(leftSlant: 200);
    expect(model.topSlantLeftY, 0);
  });
}
