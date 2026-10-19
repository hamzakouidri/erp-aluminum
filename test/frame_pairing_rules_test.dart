import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _PairingDatabase extends SqlDatabase {
  _PairingDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

AluminumSection _frame(int id, {double cover = 0}) => AluminumSection(
  id: id,
  seriesId: 1,
  code: 'F$id',
  name: 'Cadre $id',
  type: 'frame',
  thickness: 45,
  visibleWidth: 45,
  couvreJointWidth: cover,
);

void main() {
  test('the old corner list becomes each frame\'s corner frame', () async {
    sqfliteFfiInit();
    SqlDatabase.resetDb();
    SharedPreferences.setMockInitialValues({});
    final connection = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(connection.close);
    await connection.execute(
      'CREATE TABLE Sections (id INTEGER PRIMARY KEY, series_id INTEGER, '
      'type TEXT, name TEXT, code TEXT)',
    );
    await connection.execute(
      'CREATE TABLE SeriesDesignRoles (id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'series_id INTEGER, role_key TEXT, section_id INTEGER, '
      "compatible_frame_ids TEXT DEFAULT '')",
    );
    for (final id in [50, 51, 52]) {
      await connection.insert('Sections', {
        'id': id,
        'series_id': 5,
        'type': 'frame',
      });
    }
    await connection.insert('SeriesDesignRoles', {
      'series_id': 5,
      'role_key': 'profile_angle',
      'section_id': 90,
      'compatible_frame_ids': '51',
    });

    final pairings = await _PairingDatabase(connection).readFramePairings();
    // A listed frame stands against the corner itself; the others take it.
    expect(pairings[50]?['corner_frame_id'], 51);
    expect(pairings[51]?['corner_frame_id'], 51);
    expect(pairings[52]?['corner_frame_id'], 51);
  });

  test('a side cut from the frame without cover follows the frame', () {
    final covered = _frame(1, cover: 20);
    final otherCovered = _frame(2, cover: 20);
    final plain = _frame(3);
    final otherPlain = _frame(4);
    final model = WindowModel(
      db: SqlDatabase(),
      width: 1200,
      height: 1200,
      profileThickness: 45,
    );
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Série',
      type: 'opening',
      sections: [covered, otherCovered, plain, otherPlain],
    );
    model.zones = [
      WindowZone(
        id: 'zone',
        boundary: const Rect.fromLTRB(45, 45, 1155, 1155),
      ),
    ];
    model.frameOverride = covered.toMap();
    model.setFramePairingsForTest({
      1: {'no_cover_frame_id': 3},
      2: {'no_cover_frame_id': 4},
    });

    expect(model.framesWithNoCoverPartnerOnSide('left'), hasLength(1));
    model.useNoCoverFrameOnSide('left');
    expect(model.sideUsesNoCoverFrame('left'), isTrue);
    final frame = model.getFrameRects().single;
    expect(model.frameSideOverrideForRect(frame, 'left')?['id'], 3);

    // The frame changes: its side takes the new frame's "without cover".
    model.frameOverride = otherCovered.toMap();
    expect(model.frameSideOverrideForRect(frame, 'left')?['id'], 4);

    // A frame without a "without cover" set is not offered any more.
    expect(
      model.frameFitsCurrentDrawing(_frame(9, cover: 20).toMap(), sliding: false),
      isFalse,
    );
    expect(
      model.frameFitsCurrentDrawing(covered.toMap(), sliding: false),
      isTrue,
    );

    model.restoreCoveredFrameOnSide('left');
    expect(model.sideUsesNoCoverFrame('left'), isFalse);
    expect(model.frameSideOverrideForRect(frame, 'left'), isNull);
  });
}
