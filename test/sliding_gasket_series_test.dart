import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/sql_database.dart';

class _Database extends SqlDatabase {
  @override
  Future<List<Map<String, dynamic>>> readGlass() async => [];
}

void main() {
  test('mixed drawing assigns sliding glazing and brush demand to BS90', () {
    SharedPreferences.setMockInitialValues({});
    final model = WindowModel(db: _Database(), width: 1500, height: 1200);
    model.systemMode = 'mixed';
    model.activeSeries = AluminumSeries(id: 1, profileId: 1, name: 'Opening', type: 'opening');
    model.activeSlidingSeries = AluminumSeries(id: 90, profileId: 1, name: 'BS90', type: 'sliding');
    model.zones = [WindowZone(id: 'sliding', content: ZoneContent.slidingSash, boundary: const Rect.fromLTWH(0, 0, 1500, 1200), slidingSashesCount: 2)];
    final items = ComponentCalculator.generateBom(model, const {});
    final bourrage = items.where((item) => item.category == 'joint' && item.originalName.contains('Bourrage'));
    expect(bourrage, isNotEmpty);
    for (final item in bourrage) {
      expect(item.sourceSeriesId, 90);
      expect(item.requiredQuantity, greaterThan(0));
    }
    final brushes = items.where((item) => item.originalName.contains('Joint Brosse Sash'));
    expect(brushes, isNotEmpty);
    expect(brushes.every((item) => item.sourceSeriesId == 90), isTrue);
  });
}
