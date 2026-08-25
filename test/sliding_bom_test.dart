import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
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

  test('Sliding window BOM generates correct sliding kits under other category and correct assembly screws', () {
    final fakeDb = FakeSqlDatabase();
    final model = WindowModel(db: fakeDb, width: 1500, height: 1200);
    model.systemMode = 'sliding';
    
    // Simulate active sliding series containing "67000"
    model.activeSlidingSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'E67000 Sliding Series',
      type: 'sliding',
    );

    // Simulate zones: 1 sliding zone
    model.zones = [
      WindowZone(
        id: 'z1',
        content: ZoneContent.slidingSash,
        boundary: const Rect.fromLTWH(0, 0, 1500, 1200),
      )
    ];

    // Generate BOM
    final bom = ComponentCalculator.generateBom(
      model,
      {},
      kitBundleData: {},
      kitPerLeafMap: {},
    );

    // 1. Verify Kit 67000 is present and categorized as 'other'
    final kitItem = bom.firstWhere(
      (item) => item.originalName == 'كيت 67000 (Kit 67000)',
      orElse: () => throw Exception('Kit 67000 not found'),
    );
    expect(kitItem.category, equals('other'));
    expect(kitItem.quantity, equals(1.0));

    // 2. Verify 'براغي التجميع' is present instead of 'براغي الإكسسوارات'
    // slidingTotalRoulettes = sashes * 2. With 1 sliding zone, usually sashes = 2.
    // So assembly screws quantity = 2 sashes * 4 = 8.
    final screwsItem = bom.firstWhere(
      (item) => item.originalName == 'براغي التجميع',
      orElse: () => throw Exception('Assembly screws not found'),
    );
    expect(screwsItem.category, equals('accessory'));
    expect(screwsItem.quantity, equals(8.0));

    // Verify there are no 'براغي الإكسسوارات'
    final hasGenericScrews = bom.any((item) => item.originalName == 'براغي الإكسسوارات');
    expect(hasGenericScrews, isFalse);
  });
}
