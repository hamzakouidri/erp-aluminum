import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;

void main() {
  test('saved sash uses current capacity of the same catalogue section', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.activeSlidingSeries = AluminumSeries(
      id: 41, profileId: 1, name: 'Bs90', type: 'sliding',
      sections: [AluminumSection(id: 293, seriesId: 41, code: 'B90200',
        name: 'Sash', type: 'sash', maxGlassThickness: 28)],
    );
    model.slidingSashOverride = {'id': 293, 'max_glass_thickness': 0};
    expect(model.sashGlassCapacityForContext(sliding: true), 28);
    model.slidingSashOverride = {'id': 999, 'max_glass_thickness': 20};
    expect(model.sashGlassCapacityForContext(sliding: true), 20);
    model.slidingSashOverride = {'id': 999, 'max_glass_thickness': 0};
    expect(model.sashGlassCapacityForContext(sliding: true), isNull);
  });
}
