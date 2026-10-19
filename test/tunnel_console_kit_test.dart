import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/shutter_calc_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sliding_bom_test.dart' show FakeSqlDatabase;

const _kit = 'Kit CT 300 moteur';

Map<String, dynamic> _range(String name, int group) => {
  'min_mm': 0.0,
  'max_mm': 1000.0,
  'product_name': name,
  'qty': 1.0,
  'compatibility_group': group,
};

List<BomItem> _bom(int console, {double width = 1700}) {
  final model = WindowModel(
    db: FakeSqlDatabase(),
    width: width,
    height: 1400,
    systemMode: 'opening',
  );
  model.hasShutter = true;
  model.isCaissonTunnel = true;
  model.tunnelConsoleGroup = console;
  model.zones = [
    WindowZone(
      id: 'z1',
      content: ZoneContent.fixedGlass,
      boundary: Rect.fromLTWH(0, 0, width, 1400),
    ),
  ];
  return ComponentCalculator.generateBom(
    model,
    const {},
    kitBundleMetadata: {
      _kit: {'id': 1, 'name': _kit, 'description': 'CT'},
    },
    kitBundleData: {
      _kit: [
        {
          'component_type': 'Tandem',
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'mechanism_scopes': 'belt,crank,motor',
          'ranges': [_range('Tandem standard', 1), _range('Embout galva', 2)],
        },
        {
          'component_type': 'Attache',
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'mechanism_scopes': 'belt,crank,motor',
          'ranges': [_range('Attache 25 kg', 0)],
        },
      ],
    },
  );
}

bool _has(List<BomItem> bom, String name) => bom.any((i) => i.name == name);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShutterCalcRules.apply({
      ShutterCalcRules.tunnelAxeStandard: 60,
      ShutterCalcRules.tunnelAxeSpecial: 90,
    });
  });
  tearDown(() => ShutterCalcRules.apply({}));

  test('the chosen console picks its kit parts and its axe deduction', () {
    final standard = _bom(1);
    expect(_has(standard, 'Tandem standard'), isTrue);
    expect(_has(standard, 'Embout galva'), isFalse);
    final standardAxe = standard.firstWhere(
      (i) => i.originalName == 'المحور (Axe)',
    );
    expect(standardAxe.pieces, [1.64]);

    final special = _bom(2);
    expect(_has(special, 'Embout galva'), isTrue);
    expect(_has(special, 'Tandem standard'), isFalse);
    final specialAxe = special.firstWhere(
      (i) => i.originalName == 'المحور (Axe)',
    );
    expect(specialAxe.pieces, [1.61]);
  });

  test('the kit attaches follow the width and are not listed twice', () {
    final bom = _bom(1);
    // 1700 mm: 4 attaches, all of the kit's type.
    expect(bom.firstWhere((i) => i.name == 'Attache 25 kg').quantity, 4);
    expect(bom.any((i) => i.originalName == 'أطاش (Attache)'), isFalse);
  });

  test('the workshop values drive the tunnel blades and rails', () {
    ShutterCalcRules.apply({
      ShutterCalcRules.tunnelBladeDeduction: 50,
      ShutterCalcRules.tunnelRailAdd: 30,
    });
    final bom = _bom(1);
    final blades = bom.firstWhere((i) => i.originalName == 'الشرائح (Lames)');
    expect(blades.pieces!.first, closeTo(1.65, 1e-9));
    final rails = bom.firstWhere((i) => i.originalName == 'السكك (Coulisses)');
    expect(rails.pieces, [1.43, 1.43]);
    final joint = bom.firstWhere(
      (i) => i.originalName == 'جوان بروس للستار (Joint Brosse Shutter)',
    );
    // 2 × 2.86 m of rails = 5.72 m, sold by the whole metre.
    expect(joint.quantity, 6);
    // The defaults keep the former axe deduction.
    ShutterCalcRules.apply({});
    final axe = _bom(1).firstWhere((i) => i.originalName == 'المحور (Axe)');
    expect(axe.pieces, [1.625]);
  });
}
