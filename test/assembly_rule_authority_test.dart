import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'montant_slim_test.dart' show FakeSqlDatabase;
import 'package:database_data/Commande/Systeme/accessory_assembly.dart';

void main() {
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
