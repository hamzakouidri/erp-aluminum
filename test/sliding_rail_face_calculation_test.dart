import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<List<Map<String, dynamic>>> readGlass() async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('face to face pieces count is 1 for 4-sash window', () {
    final fakeDb = FakeSqlDatabase();
    final model = WindowModel(db: fakeDb, width: 2000, height: 1500);
    model.systemMode = 'sliding';

    // A sliding zone with 4 sashes and face-to-face active
    final zone = model.zones.first;
    zone.content = ZoneContent.slidingSash;
    zone.slidingSashesCount = 4;
    zone.slidingTrackCount = 2;
    zone.slidingFaceToFace = true;

    // Simulate face_to_face section rule
    model.componentOverrides['قائم Face to Face (Face-to-Face)'] = {
      'id': 999,
      'code': 'FTF01',
      'name': 'Face to Face Profile',
      'thickness': 40.0,
      'visible_width': 40.0,
    };

    final bom = ComponentCalculator.generateBom(model, const {});

    final ftfItems = bom.where((i) => i.name.contains('Face to Face') || i.originalName.contains('Face to Face')).toList();
    expect(ftfItems.isNotEmpty, isTrue);
    final totalFtfPieces = ftfItems.fold<int>(0, (sum, item) => sum + (item.pieces?.length ?? 0));
    expect(totalFtfPieces, equals(1));
  });

  test('multi-frame window calculates rail length using containing frame width minus 2x frame visible width', () {
    final fakeDb = FakeSqlDatabase();
    final model = WindowModel(db: fakeDb, width: 3000, height: 1500);
    model.profileThickness = 40.0;
    model.systemMode = 'sliding';

    // Two frames: frame 1 (0 to 1500), frame 2 (1500 to 3000)
    final z1 = model.zones.first;
    z1.boundary = const Rect.fromLTRB(40, 40, 1460, 1460);
    z1.content = ZoneContent.slidingSash;
    z1.slidingSashesCount = 2;
    z1.slidingTrackCount = 2;

    final z2 = WindowZone(
      id: 'z2',
      boundary: const Rect.fromLTRB(1540, 40, 2960, 1460),
      content: ZoneContent.empty,
    );
    model.zones.add(z2);

    final bom = ComponentCalculator.generateBom(model, const {});

    final railItems = bom.where((i) => i.name.contains('سكة') || i.name.contains('Rail') || i.originalName.contains('سكة') || i.originalName.contains('Rail')).toList();
    expect(railItems.isNotEmpty, isTrue);
    // Containing frame width is 1500mm. Visible width is 40mm.
    // Rail length = 1500 - (40 * 2) = 1420mm = 1.42m
    for (final item in railItems) {
      for (final piece in item.pieces ?? <double>[]) {
        expect((piece - 1.42).abs() < 0.05, isTrue,
            reason: 'Rail piece length $piece should be ~1.42m, not ~2.92m');
      }
    }
  });
}
