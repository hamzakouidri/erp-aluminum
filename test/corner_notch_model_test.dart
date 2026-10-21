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

/// No zone may enter a cut corner or its step bars.
void _expectZonesOutsideCuts(WindowModel model) {
  final t = model.profileThickness;
  for (final c in NotchCorner.values) {
    final cut = model.cornerNotches.cutRect(c, model.width, model.height);
    if (cut == null) continue;
    final keepOut = Rect.fromLTRB(
      CornerNotches.isLeft(c) ? 0 : cut.left - t,
      CornerNotches.isTop(c) ? 0 : cut.top - t,
      CornerNotches.isLeft(c) ? cut.right + t : model.width,
      CornerNotches.isTop(c) ? cut.bottom + t : model.height,
    );
    for (final z in model.zones) {
      expect(
        z.boundary.intersect(keepOut).isEmpty ||
            z.boundary.intersect(keepOut).width < 0.5 ||
            z.boundary.intersect(keepOut).height < 0.5,
        isTrue,
        reason: '$c ${z.boundary}',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a plain window has no cut and keeps its JSON', () {
    final model = _window();
    expect(model.hasCornerNotches, isFalse);
    expect(model.toMap().containsKey('cornerNotches'), isFalse);
    expect(model.cornerNotchBlocker, isNull);
  });

  test('a wide shallow cut adds a transom in line with its step', () {
    final model = _window();
    final t = model.profileThickness;
    final error = model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    expect(error, isNull);
    expect(
      model.cornerNotches.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    expect(model.zones.length, 2);
    // Strip right of the step, then the full-width zone under the transom.
    final strip = model.zones.firstWhere((z) => z.boundary.top < 300);
    expect(strip.boundary.left, closeTo(800 + t, 0.01));
    final lower = model.zones.firstWhere((z) => z.boundary.top >= 300);
    expect(lower.boundary.top, closeTo(300 + t, 0.01));
    expect(lower.boundary.left, closeTo(t, 0.01));
    _expectZonesOutsideCuts(model);
  });

  test('a narrow tall cut adds a mullion in line with its step', () {
    final model = _window();
    final t = model.profileThickness;
    model.setCornerNotch(
      NotchCorner.bottomRight,
      const CornerNotch(width: 300, height: 900),
    );
    expect(model.zones.length, 2);
    final column = model.zones.firstWhere((z) => z.boundary.left > 1000);
    expect(column.boundary.bottom, closeTo(1500 - 900 - t, 0.01));
    expect(column.boundary.right, closeTo(2000 - t, 0.01));
    final main = model.zones.firstWhere((z) => z.boundary.left < 1000);
    expect(main.boundary.right, closeTo(2000 - 300 - t, 0.01));
    _expectZonesOutsideCuts(model);
  });

  test('changing and removing a cut moves its zones with the step', () {
    final model = _window();
    final t = model.profileThickness;
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 800, height: 300),
    );
    model.setCornerNotch(
      NotchCorner.topLeft,
      const CornerNotch(width: 600, height: 400),
    );
    expect(model.zones.length, 2);
    expect(
      model.cornerNotches.topLeft,
      const CornerNotch(width: 600, height: 400),
    );
    final strip = model.zones.firstWhere((z) => z.boundary.top < 400);
    expect(strip.boundary.left, closeTo(600 + t, 0.01));
    _expectZonesOutsideCuts(model);

    model.setCornerNotch(NotchCorner.topLeft, CornerNotch.none);
    expect(model.hasCornerNotches, isFalse);
    // The transom stays; the strip runs again to the left frame.
    final top = model.zones.firstWhere((z) => z.boundary.top < 400);
    expect(top.boundary.left, closeTo(t, 0.01));
  });

  test('a thicker frame (another series) keeps the cuts and their zones', () {
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
    _expectZonesOutsideCuts(model);
    // Every zone side lies on the frame, a step or a mullion: none is left
    // on the faces of the old, thinner frame.
    for (final z in model.zones) {
      for (final edge in [z.boundary.left, z.boundary.top]) {
        expect(
          [40.0, 640.0, 440.0].any((e) => (edge - e).abs() < 0.5),
          isFalse,
          reason: '${z.boundary}',
        );
      }
    }
  });

  test('four cut corners keep every zone outside the cuts', () {
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
    _expectZonesOutsideCuts(model);
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
    expect(model.zones.length, 1);
    model.redo();
    expect(
      model.cornerNotches.topRight,
      const CornerNotch(width: 500, height: 300),
    );
    expect(model.zones.length, 2);
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
