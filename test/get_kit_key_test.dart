import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/sql_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A simple mock for SqlDatabase
class FakeSqlDatabase extends SqlDatabase {
  @override
  Future<List<Map<String, dynamic>>> readGlass() async => [];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getKitKey matches robust names like System Kit OB, Kit OB, Demi OB, and Verrou Central', () {
    final fakeDb = FakeSqlDatabase();
    final model = WindowModel(db: fakeDb, width: 1000, height: 1000);
    model.activeSeries = AluminumSeries(id: 1, profileId: 1, name: 'PVC Series', type: 'PVC');
    model.useSystemOB = true;
    model.useDemiOB = true;
    model.useVerrouCentral = true;

    // Custom database kit bundle items
    final simulatedKitBundleData = {
      'System Kit OB': [
        {'qty_mode': 'fixed', 'component_type': 'Compas OB', 'unit': 'U', 'base_qty': 1.0}
      ],
      'Kit Demi OB': [
        {'qty_mode': 'fixed', 'component_type': 'Bras OB', 'unit': 'U', 'base_qty': 1.0}
      ],
      'Kit Verrou Central': [
        {'qty_mode': 'fixed', 'component_type': 'Tringle', 'unit': 'U', 'base_qty': 2.0}
      ]
    };

    final simulatedKitPerLeafMap = {
      'System Kit OB': false,
      'Kit Demi OB': false,
      'Kit Verrou Central': false,
    };

    // Generate BOM
    final activeVariants = {
      'System OB': true,
      'Demi System OB': true,
      'Verrou Central': true,
    };

    // Simulate zones so we trigger hasDoubleSash and hasSingleSash
    // We add a zone of singleSash and doubleSash
    model.zones = [
      WindowZone(
        id: '1',
        content: ZoneContent.doubleSash,
        boundary: const Rect.fromLTWH(0, 0, 1000, 1000),
      )
    ];

    final bom = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: simulatedKitBundleData,
      kitPerLeafMap: simulatedKitPerLeafMap,
    );

    // Verify System OB expanded items
    final hasCompas = bom.any((item) => item.name == 'Compas OB');
    expect(hasCompas, isTrue, reason: 'System OB sub-items should be resolved from "System Kit OB"');
    expect(bom.where((item) => item.name == 'System OB'), isEmpty);

    // Verify Demi System OB expanded items
    final hasBras = bom.any((item) => item.name == 'Bras OB');
    expect(hasBras, isTrue, reason: 'Demi System OB sub-items should be resolved from "Kit Demi OB"');
    expect(bom.where((item) => item.name == 'Demi System OB'), isEmpty);

    // Verify Verrou Central expanded items
    final hasTringle = bom.any((item) => item.name == 'Tringle');
    expect(hasTringle, isTrue, reason: 'Verrou Central sub-items should be resolved from "Kit Verrou Central"');
    expect(bom.where((item) => item.name == 'Verrou Central'), isEmpty);
  });
}
