import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;
import 'package:database_data/Commande/Systeme/accessory_assembly.dart';
import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'accessory_assembly_rules_test.dart' show RuleDatabase;

/// The engine keeps a profile row only when the catalogue offers it for its
/// role; these tests use a series whose extension and complement profiles
/// are configured.
class _SeriesSectionsDatabase extends RuleDatabase {
  static const _sections = <String, Map<String, dynamic>>{
    'frame_extension': {'id': 305, 'code': 'B90 105', 'name': 'Extension'},
    'complement_haut_base': {'id': 314, 'code': 'B90 314', 'name': 'Complement'},
  };

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async => [
    for (final role in roleKeys)
      if (_sections[role] case final section?)
        {
          ...section,
          'series_id': seriesId,
          'type': role,
          'design_role_key': role,
          'is_active': 1,
        },
  ];

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForScopedDialogRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) => getDesignSectionsForRoles(seriesId, roleKeys);
}

void main() {
  test('Clam includes base frame, extension frame and framed sliding sashes', () async {
    final db = _SeriesSectionsDatabase();
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
    final db = _SeriesSectionsDatabase();
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
    final db = _SeriesSectionsDatabase();
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
    // Only the bound profile (section 90) counts. Screws use the top and
    // bottom quantities (2×1 + 2×2); a clam is fitted with the same quantity
    // on every 45° corner (4 corners × 1).
    for (final (role, expected) in [('clam', 4), ('assembly_screw', 6)]) {
      expect(
        assemblyQuantity({
          'role_key': role,
          'assembly_target': 'sash',
          'assembly_section_quantities': '90:1:2',
        }, demands),
        expected,
        reason: role,
      );
    }
  });
  test('clamps use the configured quantity on every 45° corner', () {
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
      4,
    );
  });
  test('BS90 frame clams progression per rail: 2 rails=4, 3 rails=6, 4 rails=8, 5 rails=10, 6 rails=12', () async {
    final db = _SeriesSectionsDatabase();
    db.rules
      ..clear()
      ..add({
        'id': 4188,
        'item_id': 61,
        'series_id': 41,
        'role_key': 'clam',
        'is_active': 1,
        'show_in_quantity': 1,
        'usage_scope': 'sliding',
        'assembly_target': 'frame',
        'assembly_section_ids': '296,305',
        'assembly_section_quantities': '296:2:2,305:1:1',
      });

    final model = WindowModel(db: db, width: 1500, height: 1200)
      ..systemMode = 'sliding'
      ..hasBottomFrame = false
      ..activeSlidingSeries = AluminumSeries(id: 41, profileId: 1, name: 'Bs90', type: 'sliding')
      ..slidingFrameOverride = {'id': 296, 'series_id': 41, 'type': 'frame'}
      ..zones = [
        WindowZone(
          id: 's',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
          slidingSashesCount: 2,
        ),
      ];

    // 2 rails: Base frame only with seuil (top=2 corners * 2 clams = 4)
    final res2 = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [],
    );
    expect(res2.singleWhere((i) => i.roleKey == 'clam').quantity, 4);

    // 3 rails: Base frame (4) + 1 rail extension (3 cuts * 1 clam per top corner = 2) -> 6
    final res3 = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Ext',
          name: 'Ext',
          quantity: 1,
          unit: 'm',
          unitPrice: 0,
          catalogItemId: 305,
          roleKey: 'frame_extension',
          sourceSeriesId: 41,
          pieces: [1.5, 1.2, 1.2],
        ),
      ],
    );
    expect(res3.singleWhere((i) => i.roleKey == 'clam').quantity, 6);

    // 4 rails: Base frame (4) + 2 rails extension (6 cuts -> 4 corners * 1 = 4) -> 8
    final res4 = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Ext',
          name: 'Ext',
          quantity: 1,
          unit: 'm',
          unitPrice: 0,
          catalogItemId: 305,
          roleKey: 'frame_extension',
          sourceSeriesId: 41,
          pieces: [1.5, 1.2, 1.2, 1.5, 1.2, 1.2],
        ),
      ],
    );
    expect(res4.singleWhere((i) => i.roleKey == 'clam').quantity, 8);

    // 5 rails: Base frame (4) + 3 rails extension (9 cuts -> 6 corners * 1 = 6) -> 10
    final res5 = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Ext',
          name: 'Ext',
          quantity: 1,
          unit: 'm',
          unitPrice: 0,
          catalogItemId: 305,
          roleKey: 'frame_extension',
          sourceSeriesId: 41,
          pieces: [1.5, 1.2, 1.2, 1.5, 1.2, 1.2, 1.5, 1.2, 1.2],
        ),
      ],
    );
    expect(res5.singleWhere((i) => i.roleKey == 'clam').quantity, 10);

    // 6 rails: Base frame (4) + 4 rails extension (12 cuts -> 8 corners * 1 = 8) -> 12
    final res6 = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Ext',
          name: 'Ext',
          quantity: 1,
          unit: 'm',
          unitPrice: 0,
          catalogItemId: 305,
          roleKey: 'frame_extension',
          sourceSeriesId: 41,
          pieces: [1.5, 1.2, 1.2, 1.5, 1.2, 1.2, 1.5, 1.2, 1.2, 1.5, 1.2, 1.2],
        ),
      ],
    );
    expect(res6.singleWhere((i) => i.roleKey == 'clam').quantity, 12);
  });

  test('BS90 face-to-face central meeting adds 4 clams for the two meeting columns', () async {
    final db = _SeriesSectionsDatabase();
    db.rules
      ..clear()
      ..add({
        'id': 4196,
        'item_id': 60,
        'series_id': 41,
        'role_key': 'clam',
        'is_active': 1,
        'show_in_quantity': 1,
        'usage_scope': 'sliding',
        'assembly_target': 'sash',
        'assembly_section_ids': '293,400',
        'assembly_section_quantities': '293:1:1,400:1:1',
      });

    final model = WindowModel(db: db, width: 2000, height: 1200)
      ..systemMode = 'sliding'
      ..activeSlidingSeries = AluminumSeries(id: 41, profileId: 1, name: 'Bs90', type: 'sliding')
      ..slidingSashOverride = {'id': 293, 'series_id': 41, 'type': 'sash'}
      ..zones = [
        WindowZone(
          id: 's',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 2000, 1200),
          slidingSashesCount: 4,
          slidingFaceToFace: true,
        ),
      ];

    // Face-to-face 2 meeting columns cut at 45° (2 top + 2 bottom corners = 4 corners * 1 clam = 4)
    final res = await BomEngineV2(database: db).filterItemsByAvailableCandidates(
      window: model,
      items: [
        BomItem(
          category: 'profile',
          originalName: 'Face',
          name: 'Face',
          quantity: 1,
          unit: 'm',
          unitPrice: 0,
          catalogItemId: 400,
          roleKey: 'face_to_face',
          sourceSeriesId: 41,
          pieces: [1.2, 1.2],
        ),
      ],
    );
    // 4 sashes (16) + 2 face-to-face columns (4) = 20 clams
    expect(res.singleWhere((i) => i.roleKey == 'clam').quantity, 20);
  });
}
