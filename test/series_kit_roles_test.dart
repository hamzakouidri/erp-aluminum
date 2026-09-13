import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'accessory_assembly_rules_test.dart' as fixtures;

void main() {
  for (final role in [
    'kit',
    'sliding_kit',
    'sliding_kit_40000',
    'sliding_kit_67000',
  ]) {
    test('enabled $role appears with its price and quantity', () async {
      final db = fixtures.RuleDatabase();
      db.rules
        ..clear()
        ..add({
          'item_id': 10,
          'series_id': 1,
          'role_key': role,
          'show_in_quantity': 1,
        });
      final window = fixtures.makeWindow(db)..quantity = 2;
      if (role.startsWith('sliding_')) {
        window
          ..systemMode = 'sliding'
          ..activeSlidingSeries = window.activeSeries
          ..zones = [
            WindowZone(
              id: 'sliding',
              content: ZoneContent.slidingSash,
              boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
            ),
          ];
      }
      final items = await BomEngineV2(
        database: db,
      ).filterItemsByAvailableCandidates(window: window, items: []);
      final kit = items.single;
      expect(kit.roleKey, role);
      expect(kit.quantity, 2);
      expect(kit.unitPrice, 10);
    });
  }

  test('opening kit is not emitted for a sliding drawing', () async {
    final db = fixtures.RuleDatabase();
    db.rules
      ..clear()
      ..addAll([
        {
          'item_id': 10,
          'series_id': 1,
          'role_key': 'kit',
          'show_in_quantity': 1,
        },
        {
          'item_id': 11,
          'series_id': 1,
          'role_key': 'sliding_kit',
          'show_in_quantity': 1,
        },
      ]);
    final window = fixtures.makeWindow(db)
      ..systemMode = 'sliding'
      ..activeSlidingSeries = fixtures.makeWindow(db).activeSeries
      ..zones = [
        WindowZone(
          id: 'sliding',
          content: ZoneContent.slidingSash,
          boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
        ),
      ];

    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: []);

    expect(items.map((item) => item.catalogItemId), contains(11));
    expect(items.map((item) => item.catalogItemId), isNot(contains(10)));
  });

  test('three sliding leaves use one kit and four alignment squares', () async {
    final db = fixtures.RuleDatabase();
    db.rules
      ..clear()
      ..addAll([
        {
          'item_id': 11,
          'series_id': 1,
          'role_key': 'sliding_kit',
          'show_in_quantity': 1,
        },
        {
          'item_id': 12,
          'series_id': 1,
          'role_key': 'alignment_square',
          'show_in_quantity': 1,
        },
      ]);
    final window = fixtures.makeWindow(db)
      ..systemMode = 'sliding'
      ..activeSlidingSeries = fixtures.makeWindow(db).activeSeries
      ..zones = [
        WindowZone(
          id: 'three-leaves',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 3,
          boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
        ),
      ];

    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: []);
    final kit = items.singleWhere((item) => item.roleKey == 'sliding_kit');
    final alignment = items.singleWhere(
      (item) => item.roleKey == 'alignment_square',
    );

    expect(kit.quantity, 1);
    expect(alignment.quantity, 4);
    expect(alignment.unit, 'حبة');
  });

  test('two sliding leaves do not add standalone alignment squares', () async {
    final db = fixtures.RuleDatabase();
    db.rules
      ..clear()
      ..addAll([
        {
          'item_id': 11,
          'series_id': 1,
          'role_key': 'sliding_kit',
          'show_in_quantity': 1,
        },
        {
          'item_id': 12,
          'series_id': 1,
          'role_key': 'alignment_square',
          'show_in_quantity': 1,
        },
      ]);
    final window = fixtures.makeWindow(db)
      ..systemMode = 'sliding'
      ..activeSlidingSeries = fixtures.makeWindow(db).activeSeries
      ..zones = [
        WindowZone(
          id: 'two-leaves',
          content: ZoneContent.slidingSash,
          slidingSashesCount: 2,
          boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
        ),
      ];

    final items = await BomEngineV2(
      database: db,
    ).filterItemsByAvailableCandidates(window: window, items: []);

    expect(items.where((item) => item.roleKey == 'alignment_square'), isEmpty);
  });
}
