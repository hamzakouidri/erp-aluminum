import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;
import 'package:database_data/Commande/Systeme/accessory_assembly.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'accessory_assembly_rules_test.dart' show RuleDatabase;

void main() {
  test('Clam includes base frame, extension frame and framed sliding sashes', () async {
    final db = RuleDatabase();
    db.rules..clear()..addAll([
      {'id': 4188, 'item_id': 61, 'series_id': 41, 'role_key': 'clam',
        'is_active': 1, 'show_in_drawing': 0, 'show_in_quantity': 1,
        'usage_scope': 'sliding', 'assembly_target': 'frame',
        'assembly_section_ids': '296,305',
        'assembly_section_quantities': '296:2:2,305:1:1'},
      {'id': 4196, 'item_id': 60, 'series_id': 41, 'role_key': 'clam',
        'is_active': 1, 'show_in_quantity': 1, 'usage_scope': 'sliding',
        'assembly_section_ids': '293', 'assembly_section_quantities': '293:1:1'},
    ]);
    final model = WindowModel(db: db, width: 1500, height: 1200)
      ..systemMode = 'sliding'
      ..activeSlidingSeries = AluminumSeries(id: 41, profileId: 1,
        name: 'Bs90', type: 'sliding')
      ..slidingFrameOverride = {'id': 296, 'series_id': 41, 'type': 'frame'}
      ..slidingSashOverride = {'id': 293, 'series_id': 41, 'type': 'sash'}
      ..zones = [WindowZone(id: 's', content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200), slidingSashesCount: 2)];
    final result = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model, items: [
        BomItem(category: 'profile', originalName: 'Extension', name: 'Extension',
          quantity: 1, unit: 'm', unitPrice: 0, catalogItemId: 305,
          roleKey: 'frame_extension', sourceSeriesId: 41, pieces: [1, 1, 1, 1]),
      ]);
    final clamps = result.where((item) => item.roleKey == 'clam').toList();
    expect(clamps.singleWhere((item) => item.catalogItemId == 61).quantity, 12);
    expect(clamps.singleWhere((item) => item.catalogItemId == 60).quantity, 8);
  });
  test('BS90 quantity-only Clam follows B90 101 in mixed saved drawing', () async {
    final db = RuleDatabase();
    db.rules..clear()..add({
      'id': 4148, 'item_id': 61, 'series_id': 41, 'role_key': 'clam',
      'is_active': 1, 'show_in_drawing': 0, 'show_in_quantity': 1,
      'usage_scope': 'global', 'assembly_target': 'frame',
      'assembly_section_ids': '296,305',
      'assembly_section_quantities': '296:2:2,305:1:1',
    });
    final series = AluminumSeries(id: 41, profileId: 1, name: 'Bs 90', type: 'sliding');
    final model = WindowModel(db: db, width: 1500, height: 1200)
      ..systemMode = 'mixed'..activeSeries = series..activeSlidingSeries = series
      ..slidingFrameOverride = {'id': 296, 'series_id': 41, 'code': 'B90 101',
        'name': 'Frame', 'type': 'frame'}
      ..zones = [WindowZone(id: 's', content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200))];
    final items = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model, items: [
        // An additional row must not overwrite the actual base-frame binding.
        BomItem(category: 'profile', originalName: 'Additional frame',
          name: 'Additional frame', quantity: 1, unit: 'm', unitPrice: 0,
          catalogItemId: 999, roleKey: 'frame', sourceSeriesId: 41),
      ]);
    expect(items.singleWhere((item) => item.roleKey == 'clam').quantity, 8);
  });
  test('BS90 strike demand survives Entrematique handle selection', () {
    SharedPreferences.setMockInitialValues({});
    final model = WindowModel(db: FakeSqlDatabase(), width: 1500, height: 1200);
    model.systemMode = 'sliding';
    model.activeSlidingSeries = AluminumSeries(id: 90, profileId: 1, name: 'BS90', type: 'sliding');
    model.zones = [WindowZone(id: 's', content: ZoneContent.slidingSash,
      boundary: const Rect.fromLTWH(0, 0, 1500, 1200), slidingSashesCount: 2,
      useClassicHandle: false)];
    final items = ComponentCalculator.generateBom(model, const {});
    final strike = items.singleWhere((item) => item.roleKey == 'sliding_lock');
    expect(strike.sourceSeriesId, 90);
    expect(strike.quantity, greaterThan(0));
  });
  test('assembly screws follow configured ends of physical profile pieces', () async {
    final db = RuleDatabase();
    db.rules..clear()..add({
      'id': 4153, 'item_id': 37, 'series_id': 41,
      'role_key': 'assembly_screw', 'is_active': 1,
      'show_in_drawing': 0, 'show_in_quantity': 1,
      'assembly_section_ids': '314',
      'assembly_section_quantities': '314:1:0',
    });
    final model = WindowModel(db: db)
      ..activeSlidingSeries = AluminumSeries(
        id: 41, profileId: 1, name: 'Bs90', type: 'sliding');
    final items = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model, items: [
        BomItem(category: 'profile', originalName: 'Complement',
          name: 'Complement', quantity: 1, unit: 'm', unitPrice: 0,
          catalogItemId: 314, roleKey: 'complement_haut_base',
          sourceSeriesId: 41, pieces: [1, 1, 1, 1]),
      ]);
    expect(items.singleWhere((item) => item.roleKey == 'assembly_screw').quantity, 4);
  });
  test('section quantities bind hardware to the selected profile', () {
    const demands = [
      AssemblyDemand(
        target: 'profile',
        sliding: true,
        topCorners: 2,
        bottomCorners: 2,
        sectionId: 90,
      ),
      AssemblyDemand(
        target: 'sash',
        sliding: true,
        topCorners: 4,
        bottomCorners: 4,
        sectionId: 12,
      ),
    ];
    for (final role in ['clam', 'assembly_screw']) {
      expect(
        assemblyQuantity({
          'role_key': role,
          'assembly_target': 'sash',
          'assembly_section_quantities': '90:1:2',
        }, demands),
        6,
      );
    }
  });
  test('a zero configured bottom quantity remains zero for clamps', () {
    expect(
      assemblyQuantity(
        {'role_key': 'clam', 'assembly_section_quantities': '90:1:0'},
        const [
          AssemblyDemand(
            target: 'profile',
            sliding: true,
            topCorners: 2,
            bottomCorners: 2,
            sectionId: 90,
          ),
        ],
      ),
      2,
    );
  });
}
