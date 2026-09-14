import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSqlDatabase extends SqlDatabase {}

void main() {
  test('global aluminium gasket rules apply to a selected series', () {
    for (final role in const [
      'joint_vitrage',
      'joint_bourrage',
      'joint_frappe',
      'joint_central',
      'joint_brosse',
    ]) {
      expect(
        catalogRuleMatchesExactScope({'series_id': null, 'role_key': role}, 7),
        isTrue,
        reason: role,
      );
    }
  });

  test('side covers default to enabled and preserve an explicit off state', () {
    final model = WindowModel(db: FakeSqlDatabase());

    expect(model.hasSideCovers, isTrue);

    applyWindowModelFromMap(model, {'hasSideCovers': false});
    expect(model.hasSideCovers, isFalse);

    applyWindowModelFromMap(model, {'hasSideCovers': '0'});
    expect(model.hasSideCovers, isFalse);

    // Legacy drawings without the field use the new default.
    applyWindowModelFromMap(model, const {});
    expect(model.hasSideCovers, isTrue);
  });

  test('belt shutter defaults left and preserves an explicit saved side', () {
    final model = WindowModel(db: FakeSqlDatabase());
    expect(model.shutterMechanism, 'حزام');
    expect(model.shutterDriveSide, 'left');

    applyWindowModelFromMap(model, const {'shutterMechanism': 'حزام'});
    expect(model.shutterDriveSide, 'left');

    applyWindowModelFromMap(model, const {
      'shutterMechanism': 'حزام',
      'shutterDriveSide': 'right',
    });
    expect(model.shutterDriveSide, 'right');
  });

  test('shutter curtain weight follows the actual blade cuts', () {
    final weight = ComponentCalculator.shutterCurtainWeightKg(
      windowWidthMm: 1200,
      windowHeightMm: 1400,
      shutterBoxHeightMm: 185,
      isTunnel: false,
      bladeHeightMm: 55,
      bladeWeightPerSqm: 3,
    );

    // 25 blades × 1.135 m × 0.055 m × 3 kg/m².
    expect(weight, closeTo(4.682, 0.001));
  });

  test('hiding the bottom wall removes the lower side cover automatically', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1500)
      ..hasSideCovers = true
      ..useCustomSideCoverLayout = true
      ..sideCoverSegments = const [
        SideCoverSegment(
          side: 'top',
          startOffset: 0,
          endOffset: 1200,
          visibleWidth: 30,
        ),
        SideCoverSegment(
          side: 'bottom',
          startOffset: 0,
          endOffset: 1200,
          visibleWidth: 30,
        ),
      ];

    model.toggleBottomWall();

    expect(model.showBottomWall, isFalse);
    expect(model.removedShutterSides, contains('bottom'));
    expect(model.hiddenSideCoverSegments, contains('bottom'));
    expect(
      model.sideCoverSegments.map((segment) => segment.side),
      isNot(contains('bottom')),
    );
    expect(model.isSideCoverSegmentEnabled('bottom'), isFalse);
  });

  test('kit compatibility accepts common components in either family', () {
    final group = ComponentCalculator.selectKitCompatibilityGroup(
      shutterWeightKg: 12,
      kitItems: [
        {
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'ranges': [
            {'min_mm': 1.0, 'max_mm': 15.0, 'compatibility_group': 1},
          ],
        },
        {
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'ranges': [
            {'min_mm': 1.0, 'max_mm': 30.0, 'compatibility_group': 0},
          ],
        },
      ],
    );

    expect(group, 1);
  });

  test('kit compatibility falls back to second complete family', () {
    final group = ComponentCalculator.selectKitCompatibilityGroup(
      shutterWeightKg: 20,
      kitItems: [
        {
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'ranges': [
            {'min_mm': 1.0, 'max_mm': 15.0, 'compatibility_group': 1},
            {'min_mm': 10.0, 'max_mm': 30.0, 'compatibility_group': 2},
          ],
        },
        {
          'qty_mode': 'by_range',
          'dimension': 'shutter_weight',
          'ranges': [
            {'min_mm': 1.0, 'max_mm': 30.0, 'compatibility_group': 0},
          ],
        },
      ],
    );

    expect(group, 2);
  });

  test('kit components are filtered between belt and crank', () {
    expect(ComponentCalculator.shutterMechanismScope('حزام'), 'belt');
    expect(ComponentCalculator.shutterMechanismScope('مانيفال'), 'crank');
    expect(
      ComponentCalculator.kitItemAppliesToMechanism({
        'mechanism_scope': 'belt',
      }, 'crank'),
      isFalse,
    );
    expect(
      ComponentCalculator.kitItemAppliesToMechanism({
        'mechanism_scope': 'all',
      }, 'crank'),
      isTrue,
    );
  });

  test('kit components support multiple mechanisms including motor', () {
    expect(ComponentCalculator.shutterMechanismScope('محرك'), 'motor');
    const item = {'mechanism_scopes': 'belt,motor'};
    expect(ComponentCalculator.kitItemAppliesToMechanism(item, 'belt'), isTrue);
    expect(
      ComponentCalculator.kitItemAppliesToMechanism(item, 'motor'),
      isTrue,
    );
    expect(
      ComponentCalculator.kitItemAppliesToMechanism(item, 'crank'),
      isFalse,
    );
  });

  test(
    'motor kit scopes distinguish an emergency crank from a plain motor',
    () {
      final emergencyScopes = ComponentCalculator.shutterMechanismScopes(
        'محرك',
        motorHasEmergencyCrank: true,
      );
      final plainScopes = ComponentCalculator.shutterMechanismScopes(
        'محرك',
        motorHasEmergencyCrank: false,
      );

      expect(
        ComponentCalculator.kitItemAppliesToMechanisms(const {
          'mechanism_scopes': 'motor_emergency',
        }, emergencyScopes),
        isTrue,
      );
      expect(
        ComponentCalculator.kitItemAppliesToMechanisms(const {
          'mechanism_scopes': 'motor_emergency',
        }, plainScopes),
        isFalse,
      );
      expect(
        ComponentCalculator.kitItemAppliesToMechanisms(const {
          'mechanism_scopes': 'motor_plain',
        }, plainScopes),
        isTrue,
      );
    },
  );

  test('tunnel kit contains only configured children', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1400)
      ..hasShutter = true
      ..isCaissonTunnel = true
      ..shutterMechanism = 'محرك';
    model.componentOverrides['الشرائح (Lames)'] = {
      'id': 1,
      'component_type': 'blade',
      'name': 'Lame test 55',
      'measurement': '55',
      'weight_per_sqm': 3,
    };
    model.componentOverrides['المحرك (Moteur)'] = {
      'motor_has_emergency_crank': true,
    };

    final bom = ComponentCalculator.generateBom(
      model,
      const {},
      kitBundleData: {
        'Kit Caisson Tunnel': [
          {
            'component_type': 'Sélection famille moteur',
            'qty_mode': 'by_range',
            'dimension': 'shutter_weight',
            'mechanism_scopes': 'motor',
            'ranges': [
              {
                'min_mm': 0.0,
                'max_mm': 100.0,
                'qty': 1.0,
                'family': {
                  'name': 'Embout + Support Roulement secours',
                  'mechanism_scopes': 'motor_emergency',
                  'blade_scope': 'all',
                  'per_leaf': 0,
                  'items': [
                    {
                      'component_type': 'Embout moteur secours',
                      'qty_mode': 'fixed',
                      'base_qty': 1.0,
                      'mechanism_scopes': 'motor',
                      'family': {
                        'name': 'Embout + Support Roulement secours',
                        'mechanism_scopes': 'motor_emergency',
                        'blade_scope': 'all',
                        'per_leaf': 0,
                      },
                    },
                  ],
                },
              },
            ],
          },
          {
            // A created family is not active until a range selects it.
            'component_type': 'Embout moteur normal',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'motor',
            'family': {
              'name': 'Embout + Support Roulement normal',
              'mechanism_scopes': 'motor_plain',
              'blade_scope': 'all',
              'per_leaf': 0,
            },
          },
          {
            // Components can still be used independently at the Kit root.
            'component_type': 'Rondelle indépendante',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'motor',
          },
          {
            'component_type': 'Embout manivelle',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'crank',
          },
        ],
      },
      kitBundleMetadata: {
        'Kit Caisson Tunnel': {
          'name': 'Kit Caisson Tunnel',
          'description': 'CT',
        },
      },
    );

    final names = bom.map((item) => item.name).toList();
    final originalNames = bom.map((item) => item.originalName).toList();
    final tunnelKitRows = bom
        .where((item) => item.name == 'Kit Caisson Tunnel')
        .toList();
    // A configured kit is a container only: once it has children, its own
    // parent row must not be displayed or charged.
    expect(tunnelKitRows, isEmpty);
    expect(names, contains('Embout moteur secours'));
    expect(names, contains('Rondelle indépendante'));
    expect(
      bom
          .firstWhere((item) => item.name == 'Embout moteur secours')
          .kitGroupName,
      'Kit Caisson Tunnel',
    );
    expect(names, isNot(contains('Embout moteur normal')));
    expect(names, isNot(contains('Embout manivelle')));
    // The ordinary shutter BOM remains in the shutter section, but none of
    // those calculated rows may be presented as a child of the tunnel kit.
    expect(names, isNot(contains('الصندوق (Caisson)')));
    expect(originalNames, contains('المحور (Axe)'));
    expect(originalNames, contains('المحرك (Moteur)'));
    expect(originalNames, contains('الشرائح (Lames)'));
    expect(originalNames, contains('السكك (Coulisses)'));
    for (final item in bom.where(
      (item) => const {
        'المحور (Axe)',
        'المحرك (Moteur)',
        'براغي المحرك',
        'الشرائح (Lames)',
        'الشريحة النهائية (Lame Finale)',
        'السكك (Coulisses)',
        'جوان بروس للستار (Joint Brosse Shutter)',
      }.contains(item.originalName),
    )) {
      expect(item.kitGroupName, isNull, reason: item.originalName);
    }
  });

  test('tunnel manivelle kit stays separate from caisson tunnel kit', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1400)
      ..hasShutter = true
      ..isCaissonTunnel = true
      ..shutterMechanism = 'مانيفال';

    final bom = ComponentCalculator.generateBom(
      model,
      const {},
      kitBundleData: const {
        'Kit Caisson Tunnel Manivelle': [
          {
            'component_type': 'Pièce tunnel',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'crank',
          },
        ],
        'Kit Manivelle': [
          {
            'component_type': 'Pièce kit manivelle',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'crank',
          },
        ],
      },
      kitBundleMetadata: const {
        'Kit Caisson Tunnel Manivelle': {
          'name': 'Kit Caisson Tunnel Manivelle',
          'description': 'CT',
        },
        'Kit Manivelle': {'name': 'Kit Manivelle', 'description': 'M'},
      },
    );

    expect(
      bom.firstWhere((item) => item.name == 'Pièce tunnel').kitGroupName,
      'Kit Caisson Tunnel Manivelle',
    );
    expect(
      bom.firstWhere((item) => item.name == 'Pièce kit manivelle').kitGroupName,
      'Kit Manivelle',
    );
    expect(
      bom.where((item) => item.originalName == 'المانيفال (Manivelle)'),
      isEmpty,
    );
  });

  test('an unselected kit family does not add its children', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1400)
      ..hasShutter = true
      ..isCaissonTunnel = true
      ..shutterMechanism = 'محرك';
    final bom = ComponentCalculator.generateBom(
      model,
      const {},
      kitBundleData: {
        'Kit Caisson Tunnel': [
          {
            'component_type': 'Embout non sélectionné',
            'qty_mode': 'fixed',
            'base_qty': 1.0,
            'mechanism_scopes': 'motor',
            'family': {
              'name': 'Famille non sélectionnée',
              'mechanism_scopes': 'motor_emergency',
              'blade_scope': 'all',
              'per_leaf': 0,
            },
          },
        ],
      },
      kitBundleMetadata: {
        'Kit Caisson Tunnel': {
          'name': 'Kit Caisson Tunnel',
          'description': 'CT',
        },
      },
    );

    final names = bom.map((item) => item.name).toList();
    expect(names, isNot(contains('Embout non sélectionné')));
  });

  test('kit components distinguish normal and extruded blades', () {
    expect(
      ComponentCalculator.kitItemAppliesToBlade(const {
        'blade_scope': 'extruded',
      }, 'extruded'),
      isTrue,
    );
    expect(
      ComponentCalculator.kitItemAppliesToBlade(const {
        'blade_scope': 'extruded',
      }, 'normal'),
      isFalse,
    );
    expect(
      ComponentCalculator.kitItemAppliesToBlade(const {
        'blade_scope': 'all',
      }, 'normal'),
      isTrue,
    );
    expect(
      ComponentCalculator.kitItemAppliesToBlade(const {
        'blade_scope': 'x3d',
      }, 'extruded'),
      isTrue,
      reason: 'old X3D values remain compatible with Extrudé',
    );
  });

  test('weight kit expands every matching range from the selected kit', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1400);
    model.hasShutter = true;
    model.customShutterBoxHeight = 155;
    model.shutterMechanism = 'حزام';
    model.componentOverrides['الشرائح (Lames)'] = {
      'id': 1,
      'component_type': 'blade',
      'name': 'Lame test 55',
      'measurement': '55',
      'weight_per_sqm': 3,
      'price': 0,
      'unit': 'bar',
    };

    final bom = ComponentCalculator.generateBom(
      model,
      const {},
      kitBundleData: {
        'Kit volet 155': [
          {
            'qty_mode': 'by_range',
            'dimension': 'shutter_weight',
            'component_type': 'Console Quissonnel',
            'ranges': [
              {
                'min_mm': 1.0,
                'max_mm': 10.0,
                'product_name': 'أومبو 40',
                'qty': 1.0,
                'compatibility_group': 1,
              },
              {
                'min_mm': 1.0,
                'max_mm': 10.0,
                'product_name': 'سيبور رولمان 40',
                'qty': 1.0,
                'compatibility_group': 1,
              },
            ],
          },
        ],
      },
      kitBundleMetadata: {
        'Kit volet 155': {'name': 'Kit volet 155', 'description': 'V'},
      },
    );

    final kitItems = bom
        .where((item) => item.originalName.startsWith('Kit volet 155_'))
        .map((item) => item.name)
        .toList();
    expect(kitItems, contains('أومبو 40'));
    expect(kitItems, contains('سيبور رولمان 40'));
  });

  test('shutter component uses its configured colour price over zero base', () {
    final price = resolveShutterComponentUnitPrice(
      component: {
        'id': 55,
        'name': 'Attache inox',
        'component_type': 'attache',
        'price': 0.0,
      },
      colorPrices: const [
        {'shutter_component_id': 55, 'color_id': 1, 'price': 30.0},
      ],
      selectedColorId: 1,
    );

    expect(price, 30.0);
  });

  test('shutter component falls back to its grey colour base price', () {
    final price = resolveShutterComponentUnitPrice(
      component: {
        'id': 55,
        'name': 'Attache inox',
        'component_type': 'attache',
        'price': 999.0,
      },
      colorPrices: const [
        {'shutter_component_id': 55, 'color_id': 4, 'price': 42.0},
        {'shutter_component_id': 55, 'color_id': 9, 'price': 70.0},
      ],
      selectedColorId: 99,
      fallbackColorId: 4,
    );

    expect(price, 42.0);
  });

  test(
    'shutter component does not use an unrelated colour as its base price',
    () {
      final price = resolveShutterComponentUnitPrice(
        component: {'id': 55, 'price': 0.0},
        colorPrices: const [
          {'shutter_component_id': 55, 'color_id': 4, 'price': 0.0},
          {'shutter_component_id': 55, 'color_id': 9, 'price': 70.0},
        ],
        selectedColorId: 99,
        fallbackColorId: 4,
      );

      expect(price, 0.0);
    },
  );

  test('purchase quantity rounds profiles without changing their cost', () {
    final profile = BomItem(
      category: 'profile',
      originalName: 'Frame',
      name: 'Frame',
      quantity: 1.2,
      exactQuantity: 1.2,
      unit: 'قطاع',
      unitPrice: 4000,
    );
    final glass = BomItem(
      category: 'glass',
      originalName: 'Glass',
      name: 'Glass',
      quantity: 1.2,
      unit: 'م²',
      unitPrice: 1000,
    );

    expect(profile.purchaseQuantity, 2);
    expect(profile.total, 4800);
    expect(glass.purchaseQuantity, 1.2);
    expect(glass.total, 1200);
  });

  test('20 bardage cuts of 500 mm require two 6 m bars', () {
    final result = ComponentCalculator.optimizeCutting(
      pieces: List<double>.filled(20, 0.5),
      barLength: 6.0,
    );

    expect(result['optimizedBars'], 2);
    expect(result['exactBars'], closeTo(1.75, 0.001));
  });

  test('bardage is priced by complete stock pieces, not linear metres', () {
    final frame = AluminumSection(
      id: 1,
      seriesId: 1,
      code: 'F-1',
      name: 'Frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 60,
    );
    final bardage = AluminumSection(
      id: 3,
      seriesId: 1,
      code: 'B-3',
      name: 'Bardage',
      type: 'bardage',
      thickness: 10,
      visibleWidth: 10,
      barLength: 6,
    );
    final model = WindowModel(db: FakeSqlDatabase(), width: 510, height: 210);
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Test',
      type: 'Aluminium',
      sections: [frame, bardage],
    );
    model.frameOverride = frame.toMap();
    model.componentOverrides['البارداج (Bardage)'] = {
      ...bardage.toMap(),
      'calculated_price': 4000.0,
    };
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 510, 210),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.bardage,
          finishInner: GlassFinish.bardage,
          panneauSubtype: 'bardage',
          panneauProductId: 3,
        ),
      ),
    ];

    final item = ComponentCalculator.generateBom(
      model,
      {},
    ).firstWhere((row) => row.originalName == 'البارداج (Bardage)');

    expect(item.pieces, hasLength(20));
    expect(item.quantity, 2);
    expect(item.requiredQuantity, 2);
    expect(item.purchaseQuantity, 2);
    expect(item.catalogItemId, 3);
    expect(item.inventoryItemType, 'Section');
    expect(item.unit, 'قطعة');
    expect(item.total, 8000);
  });

  test(
    'ordinary panneau remains area-priced even when a legacy profile is configured',
    () {
      final frame = AluminumSection(
        id: 1,
        seriesId: 1,
        code: 'F-1',
        name: 'Frame',
        type: 'frame',
        isFrame: true,
        visibleWidth: 60,
      );
      final panneau = AluminumSection(
        id: 4,
        seriesId: 1,
        code: 'P-4',
        name: 'Panneau profile',
        type: 'panneau',
        thickness: 10,
        visibleWidth: 100,
        barLength: 6,
      );
      final model = WindowModel(db: FakeSqlDatabase(), width: 460, height: 910);
      model.activeSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'Test',
        type: 'Aluminium',
        sections: [frame, panneau],
      );
      model.frameOverride = frame.toMap();
      model.componentOverrides['البانو (Panneau)'] = {
        ...panneau.toMap(),
        'calculated_price': 3000.0,
      };
      model.zones = [
        WindowZone(
          id: 'z1',
          boundary: const Rect.fromLTWH(0, 0, 460, 910),
          glass: const GlassSpecification(
            structure: GlassStructure.closed,
            finishOuter: GlassFinish.resine,
            finishInner: GlassFinish.resine,
            panneauSubtype: 'resine',
          ),
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      expect(bom.where((row) => row.category == 'panneau'), isNotEmpty);
      expect(
        bom.where((row) => row.originalName == 'البانو (Panneau)'),
        isEmpty,
      );
    },
  );

  test(
    'Arabic برداج spelling is emitted as profile bars, never as panneau',
    () {
      final bardage = AluminumSection(
        id: 6,
        seriesId: 1,
        code: 'BR-6',
        name: 'برداج',
        type: 'برداج',
        thickness: 10,
        visibleWidth: 100,
        barLength: 6,
      );
      final model = WindowModel(db: FakeSqlDatabase(), width: 460, height: 910);
      model.componentOverrides['البارداج (Bardage)'] = {
        ...bardage.toMap(),
        'calculated_price': 2700.0,
      };
      model.zones = [
        WindowZone(
          id: 'z1',
          boundary: const Rect.fromLTWH(0, 0, 460, 910),
          glass: const GlassSpecification(
            structure: GlassStructure.closed,
            finishOuter: GlassFinish.resine,
            finishInner: GlassFinish.resine,
            panneauSubtype: 'برداج',
          ),
        ),
      ];

      final bom = ComponentCalculator.generateBom(model, {});
      final item = bom.firstWhere(
        (row) => row.originalName == 'البارداج (Bardage)',
      );

      expect(item.category, 'profile');
      expect(item.inventoryItemType, 'Section');
      expect(item.catalogItemId, 6);
      expect(item.unit, 'قطعة');
      expect(item.pieces, hasLength(9));
      expect(item.quantity, 1);
      expect(bom.where((row) => row.category == 'panneau'), isEmpty);
    },
  );

  test('bardage without a configured section never falls back to glass', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 460, height: 910);
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 460, 910),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.paneauSandwitch,
          finishInner: GlassFinish.paneauSandwitch,
          panneauSubtype: 'البرداش',
        ),
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, {});
    final missingBardage = bom.firstWhere(
      (row) => row.originalName == 'البارداج (Bardage)',
    );

    expect(missingBardage.category, 'profile');
    expect(missingBardage.isMissing, isTrue);
    expect(missingBardage.unit, 'قطعة');
    expect(bom.where((row) => row.category == 'panneau'), isEmpty);
  });

  test('bardage uses the configured panneau role as a profile', () {
    final panneau = AluminumSection(
      id: 5,
      seriesId: 1,
      code: 'P-B',
      name: 'Bardage panneau profile',
      type: 'bardage',
      thickness: 10,
      visibleWidth: 100,
      barLength: 6,
    );
    final model = WindowModel(db: FakeSqlDatabase(), width: 460, height: 910);
    model.componentOverrides['البانو (Panneau)'] = {
      ...panneau.toMap(),
      'calculated_price': 2500.0,
    };
    expect(model.bardageVisibleWidth, 100);
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 460, 910),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.bardage,
          finishInner: GlassFinish.bardage,
          panneauSubtype: 'bardage',
        ),
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, {});
    final item = bom.firstWhere(
      (row) => row.originalName == 'البارداج (Bardage)',
    );

    expect(item.category, 'profile');
    expect(item.roleKey, 'panneau');
    expect(item.inventoryItemType, 'Section');
    expect(item.catalogItemId, 5);
    expect(item.pieces, hasLength(9));
    expect(item.quantity, 1);
    expect(item.total, 2500);
    expect(bom.where((row) => row.category == 'panneau'), isEmpty);
  });

  test('bardage follows the frame colour until the user overrides it', () {
    final model = WindowModel(db: FakeSqlDatabase());
    final white = <String, dynamic>{'id': 1, 'name': 'White'};
    final grey = <String, dynamic>{'id': 2, 'name': 'Grey'};
    model.availableColors = [white, grey];
    model.selectedDbColor = white;

    const automatic = GlassSpecification(
      structure: GlassStructure.closed,
      finishOuter: GlassFinish.bardage,
      panneauSubtype: 'bardage',
      bardageUsesFrameColor: true,
    );
    const customWhite = GlassSpecification(
      structure: GlassStructure.closed,
      finishOuter: GlassFinish.bardage,
      panneauSubtype: 'bardage',
      panneauColor: 'White',
      bardageUsesFrameColor: false,
    );

    expect(model.getBardageColorNameForSpec(automatic), 'White');
    expect(model.getBardageColorNameForSpec(customWhite), 'White');

    model.selectedDbColor = grey;
    expect(model.getBardageColorNameForSpec(automatic), 'Grey');
    expect(model.getBardageColorNameForSpec(customWhite), 'White');
  });

  test('bardage quantities and prices stay separated by colour', () {
    final frame = AluminumSection(
      id: 1,
      seriesId: 1,
      code: 'F-1',
      name: 'Frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 60,
    );
    final bardage = AluminumSection(
      id: 3,
      seriesId: 1,
      code: 'B-3',
      name: 'Bardage',
      type: 'bardage',
      thickness: 10,
      visibleWidth: 10,
      barLength: 6,
    );
    final model = WindowModel(db: FakeSqlDatabase(), width: 510, height: 420);
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Test',
      type: 'Aluminium',
      sections: [frame, bardage],
    );
    model.frameOverride = frame.toMap();
    final white = <String, dynamic>{'id': 1, 'name': 'White'};
    final grey = <String, dynamic>{'id': 2, 'name': 'Grey'};
    model.availableColors = [white, grey];
    model.selectedDbColor = white;
    model.componentOverrides['البارداج (Bardage)'] = {
      ...bardage.toMap(),
      'calculated_price': 4000.0,
      'color_prices': {
        'id:1': 4000.0,
        'name:white': 4000.0,
        'id:2': 5000.0,
        'name:grey': 5000.0,
      },
    };
    model.zones = [
      WindowZone(
        id: 'white',
        boundary: const Rect.fromLTWH(0, 0, 510, 210),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.bardage,
          finishInner: GlassFinish.bardage,
          panneauSubtype: 'bardage',
          panneauProductId: 3,
          bardageUsesFrameColor: true,
        ),
      ),
      WindowZone(
        id: 'grey',
        boundary: const Rect.fromLTWH(0, 210, 510, 210),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.bardage,
          finishInner: GlassFinish.bardage,
          panneauSubtype: 'bardage',
          panneauColor: 'Grey',
          panneauProductId: 3,
          bardageUsesFrameColor: false,
        ),
      ),
    ];

    final rows = ComponentCalculator.generateBom(
      model,
      {},
    ).where((row) => row.originalName == 'البارداج (Bardage)').toList();
    final whiteRow = rows.firstWhere((row) => row.colorName == 'White');
    final greyRow = rows.firstWhere((row) => row.colorName == 'Grey');

    expect(rows, hasLength(2));
    expect(whiteRow.quantity, 2);
    expect(whiteRow.unitPrice, 4000);
    expect(whiteRow.total, 8000);
    expect(greyRow.quantity, 2);
    expect(greyRow.unitPrice, 5000);
    expect(greyRow.total, 10000);
  });

  test(
    'decor panel keeps its fixed orientation when checking available space',
    () {
      expect(
        decorPanelFitsSpace(
          spaceWidth: 900,
          spaceHeight: 1200,
          decorWidth: 800,
          decorHeight: 1100,
        ),
        isTrue,
      );
      expect(
        decorPanelFitsSpace(
          spaceWidth: 1200,
          spaceHeight: 900,
          decorWidth: 800,
          decorHeight: 1100,
        ),
        isFalse,
      );
    },
  );

  test('decor panel is billed as one glass-catalogue piece', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 900, height: 1200);
    model.allGlassCache = [
      {
        'id': 9,
        'name': 'Decor 9',
        'type': 'Panneau',
        'subtype': 'panneau décor',
        'color': 'White',
        'thickness': 24.0,
        'visible_width': 800.0,
        'height': 1100.0,
        'price_per_sqm': 4000.0,
      },
    ];
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 900, 1200),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.paneauSandwitchDecore,
          finishInner: GlassFinish.paneauSandwitchDecore,
          panneauSubtype: 'panneau décor',
          panneauColor: 'White',
          panneauProductId: 9,
        ),
      ),
    ];

    final item = ComponentCalculator.generateBom(
      model,
      {},
    ).firstWhere((row) => row.originalName == 'البانو ديكور');

    expect(item.quantity, 1);
    expect(item.unit, 'قطعة');
    expect(item.unitPrice, 4000);
    expect(item.total, 4000);
  });

  test('ordinary panneau remains billed by square metre', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 2010, height: 1010);
    model.allGlassCache = [
      {
        'id': 10,
        'name': 'Sandwich',
        'type': 'Panneau',
        'subtype': 'panneau sandwitch',
        'color': 'White',
        'thickness': 24.0,
        'price_per_sqm': 1000.0,
      },
    ];
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 2010, 1010),
        glass: const GlassSpecification(
          structure: GlassStructure.closed,
          finishOuter: GlassFinish.paneauSandwitch,
          finishInner: GlassFinish.paneauSandwitch,
          panneauSubtype: 'panneau sandwitch',
          panneauColor: 'White',
          panneauProductId: 10,
        ),
      ),
    ];

    final item = ComponentCalculator.generateBom(
      model,
      {},
    ).firstWhere((row) => row.originalName == 'البانو');

    expect(item.quantity, closeTo(2, 0.001));
    expect(item.unit, 'م²');
    expect(item.total, closeTo(2000, 0.001));
  });

  test('accepting decor placement removes the interfering cell divisions', () {
    final model = WindowModel(db: FakeSqlDatabase());
    final zone = WindowZone(
      id: 'z1',
      boundary: const Rect.fromLTWH(0, 0, 1000, 1200),
      content: ZoneContent.singleSash,
      innerH: 1,
      innerV: 1,
      innerHPositions: const [0.5],
      innerVPositions: const [0.5],
      disabledVerticalDivisions: <String, bool>{},
      disabledHorizontalDivisions: <String, bool>{},
      cellGlassSpec: {
        'main_cell_1_1': const GlassSpecification(
          structure: GlassStructure.simple,
        ),
      },
    );
    model.zones = [zone];

    final normalizedCell = model.removeSashDivisions(
      zoneOverride: zone,
      targetCellKey: 'main_cell_1_1',
    );

    expect(normalizedCell, 'main_cell_0_0');
    expect(zone.innerH, 0);
    expect(zone.innerV, 0);
    expect(zone.innerHPositions, isEmpty);
    expect(zone.innerVPositions, isEmpty);
    expect(zone.cellGlassSpec, isEmpty);
  });

  test(
    'custom standalone cover adds its visible width only at an outer end',
    () {
      final fromBottom =
          ComponentCalculator.standaloneSideCoverSegmentCutLength(
            sideLength: 2000,
            start: 0,
            end: 1000,
            visibleWidth: 60,
            weldingAllowance: 5,
          );
      final fromTop = ComponentCalculator.standaloneSideCoverSegmentCutLength(
        sideLength: 2000,
        start: 1000,
        end: 2000,
        visibleWidth: 60,
        weldingAllowance: 5,
      );
      final inMiddle = ComponentCalculator.standaloneSideCoverSegmentCutLength(
        sideLength: 2000,
        start: 500,
        end: 1500,
        visibleWidth: 60,
        weldingAllowance: 5,
      );
      final fullSide = ComponentCalculator.standaloneSideCoverSegmentCutLength(
        sideLength: 2000,
        start: 0,
        end: 2000,
        visibleWidth: 60,
        weldingAllowance: 5,
      );

      expect(fromBottom, 1065);
      expect(fromTop, 1065);
      expect(inMiddle, 1005);
      expect(fullSide, 2125);
    },
  );

  test('standalone cover uses only its selected face widths', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.selectedSideCover = AluminumSection(
      id: 7,
      seriesId: 1,
      code: 'CJ-7',
      name: 'Standalone cover',
      type: 'side_cover',
      couvreJointWidth: 35,
      couvreJointThickness: 10,
      visibleWidth: 60,
    );
    // Even a stale frame value must never enter the standalone getter.
    model.frameOverride = {
      'name': 'Integrated frame',
      'type': 'frame',
      'couvre_joint_width': 80.0,
    };

    expect(model.standaloneSideCoverWidth, 35);
    expect(model.standaloneSideCoverThickness, 10);
    model.sideCoverUseSecondWidth = true;
    expect(model.standaloneSideCoverWidth, 60);
  });

  test('standalone cover falls back to its only non-zero face', () {
    final model = WindowModel(db: FakeSqlDatabase());
    model.selectedSideCover = AluminumSection(
      id: 8,
      seriesId: 1,
      code: 'CJ-8',
      name: 'Single-face cover',
      type: 'side_cover',
      couvreJointWidth: 40,
      visibleWidth: 0,
    );
    model.sideCoverUseSecondWidth = true;

    expect(model.standaloneSideCoverWidth, 40);
  });

  test('standalone cover thickness shortens only the covered frame sides', () {
    final frame = AluminumSection(
      id: 1,
      seriesId: 1,
      code: 'F-1',
      name: 'Plain frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 60,
    );
    final cover = AluminumSection(
      id: 2,
      seriesId: 1,
      code: 'CJ-2',
      name: 'Two-face cover',
      type: 'side_cover',
      couvreJointWidth: 35,
      visibleWidth: 60,
      couvreJointThickness: 10,
      barLength: 6,
    );
    final model = WindowModel(db: FakeSqlDatabase(), width: 1000, height: 1200);
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'PVC test',
      type: 'PVC',
      sections: [frame, cover],
    );
    model.availableSystems = [
      AluminumProfileSystem(id: 1, name: 'PVC test', type: 'PVC'),
    ];
    model.frameOverride = frame.toMap();
    model.selectedSideCover = cover;
    model.sideCoverOverride = cover.toMap();
    model.zones = [
      WindowZone(id: 'z1', boundary: const Rect.fromLTWH(0, 0, 1000, 1200)),
    ];
    // Keep only left and top covers: width and height each lose 10 mm once.
    model.removedShutterSides.addAll(['right', 'bottom']);

    final bom = ComponentCalculator.generateBom(model, {});
    final frameItem = bom.firstWhere(
      (item) => item.originalName == 'الإطار (Frame)',
    );
    final coverItem = bom.firstWhere(
      (item) => item.originalName == 'الغطاء الجانبي (Side Cover)',
    );

    expect(frameItem.pieces, containsAllInOrder([0.995, 0.995, 1.195, 1.195]));
    expect(coverItem.pieces, containsAllInOrder([1.275, 1.075]));
  });

  test('series colour previews use the real requested finishes', () {
    final ral9007 = getEffectiveGradientColors(FrameColor.white, {
      'name': 'Gris 9007',
      'hex_code': '#FFFFFF',
    });
    final gold = getEffectiveGradientColors(FrameColor.white, {
      'name': 'Gold',
      'hex_code': '#FFFFFF',
    });
    final champagne = getEffectiveGradientColors(FrameColor.white, {
      'name': 'Champagne',
      'hex_code': '#FFFFFF',
    });
    final desertOak = getEffectiveGradientColors(FrameColor.white, {
      'name': 'ديزيرت أوك',
      'hex_code': '#FFFFFF',
    });

    expect(ral9007[1], const Color(0xFF8A939E));
    expect(gold[1], const Color(0xFFD4AF37));
    expect(champagne[1], const Color(0xFFF7E7CE));
    expect(desertOak[1], FrameColor.lightWood.gradientColors[1]);
  });

  test('simple glazing always resolves parclose code 514 with its price', () {
    final frame = AluminumSection(
      id: 1,
      seriesId: 1,
      code: 'F-1',
      name: 'Frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 60,
    );
    final otherSimple = AluminumSection(
      id: 513,
      seriesId: 1,
      code: '513',
      name: 'Other simple parclose',
      type: 'parclose',
      maxGlassThickness: 5,
    );
    final parclose514 = AluminumSection(
      id: 514,
      seriesId: 1,
      code: '514',
      name: 'Parclose simple vitrage',
      type: 'parclose',
      maxGlassThickness: 5,
      barLength: 6,
    );
    final model = WindowModel(db: FakeSqlDatabase(), width: 1000, height: 1000);
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Test',
      type: 'Aluminium',
      sections: [frame, otherSimple, parclose514],
    );
    model.frameOverride = frame.toMap();
    model.quantity = 2;
    model.sectionPricesForSelectedColor[514] = 2500;
    model.zones = [
      WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 1000, 1000),
        glass: const GlassSpecification(
          structure: GlassStructure.simple,
          thicknessOuter: 5,
        ),
      ),
    ];

    final bom = ComponentCalculator.generateBom(model, {});
    final item = bom.firstWhere(
      (row) => row.originalName == 'باكيت زجاج مفرد (Parclose Simple)',
    );
    final glass = bom.firstWhere((row) => row.originalName == 'الزجاج');

    expect(item.profileCode, '514');
    expect(item.unitPrice, 2500);
    expect(item.isMissing, isFalse);
    expect(glass.pieceCount, 2);
    expect(
      glass.name,
      contains('Dimensions / القياس: 990 × 990 مم\n- Quantité / الكمية: 2'),
    );
  });

  test(
    'Tasso uses two pieces per division and only the regular PVC caisson exception',
    () {
      expect(
        ComponentCalculator.tassoQuantity(
          divisionPieceCount: 3,
          isPvc: false,
          hasRegularCaissonAboveWindow: false,
          selectedFrameHasIntegratedCover: false,
        ),
        6,
      );
      expect(
        ComponentCalculator.tassoQuantity(
          divisionPieceCount: 0,
          isPvc: true,
          hasRegularCaissonAboveWindow: true,
          selectedFrameHasIntegratedCover: true,
        ),
        2,
      );
      expect(
        ComponentCalculator.tassoQuantity(
          divisionPieceCount: 0,
          isPvc: true,
          hasRegularCaissonAboveWindow: true,
          selectedFrameHasIntegratedCover: false,
        ),
        0,
      );
      expect(
        ComponentCalculator.tassoQuantity(
          divisionPieceCount: 0,
          isPvc: false,
          hasRegularCaissonAboveWindow: true,
          selectedFrameHasIntegratedCover: true,
        ),
        0,
      );
      expect(
        ComponentCalculator.tassoQuantity(
          divisionPieceCount: 0,
          isPvc: true,
          // Caisson tunnel / shutter behind the window.
          hasRegularCaissonAboveWindow: false,
          selectedFrameHasIntegratedCover: true,
        ),
        0,
      );
    },
  );

  test('removing the bottom frame also removes its custom side cover', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1200, height: 1400)
      ..zones = [
        WindowZone(
          id: '1',
          content: ZoneContent.singleSash,
          boundary: const Rect.fromLTWH(0, 0, 1200, 1400),
        ),
      ]
      ..useCustomSideCoverLayout = true
      ..hasSideCovers = true
      ..sideCoverSegments = [
        const SideCoverSegment(
          side: 'bottom',
          startOffset: 0,
          endOffset: 1200,
          visibleWidth: 20,
        ),
        const SideCoverSegment(
          side: 'left',
          startOffset: 0,
          endOffset: 1400,
          visibleWidth: 20,
        ),
      ];

    model.toggleBottomFrame(false);

    expect(model.hasBottomFrame, isFalse);
    expect(
      model.sideCoverSegments.map((segment) => segment.side),
      isNot(contains('bottom')),
    );
    expect(
      model.effectiveSideCoverSegments.map((segment) => segment.side),
      isNot(contains('bottom')),
    );
    expect(model.hiddenSideCoverSegments, contains('bottom'));
  });

  test('opening sash cuts always use the current frame, box and overlap', () {
    final frame = AluminumSection(
      id: 1,
      seriesId: 1,
      code: 'F-40',
      name: 'Frame 40',
      type: 'frame',
      isFrame: true,
      visibleWidth: 40,
    );
    final otherSash = AluminumSection(
      id: 2,
      seriesId: 1,
      code: 'S-other',
      name: 'Other sash',
      type: 'sash',
      isSash: true,
      visibleWidth: 45,
      sashOverlap: 7,
    );
    final selectedSash = AluminumSection(
      id: 3,
      seriesId: 1,
      code: '104',
      name: 'Selected sash',
      type: 'sash',
      isSash: true,
      visibleWidth: 50,
      sashOverlap: 10,
    );
    final model = WindowModel(
      db: FakeSqlDatabase(),
      width: 1200,
      height: 1400,
      profileThickness: 47,
    );
    model.activeSeries = AluminumSeries(
      id: 1,
      profileId: 1,
      name: 'Opening test',
      type: 'Aluminium',
      sections: [frame, otherSash, selectedSash],
    );
    model.frameOverride = frame.toMap();
    model.sashOverride = selectedSash.toMap();
    model.selectedSashCode = '104';
    model.hasShutter = true;
    model.customShutterBoxHeight = 155;
    model.zones = [
      WindowZone(
        id: 'z1',
        // Deliberately stale: these edges belonged to a 47 mm former frame.
        boundary: const Rect.fromLTRB(47, 202, 1153, 1353),
        content: ZoneContent.doubleSash,
      ),
    ];

    final item = ComponentCalculator.generateBom(
      model,
      {},
    ).firstWhere((row) => row.originalName == 'الظلفة (Sash)');

    expect(model.openingSashOverlap, 10);
    expect(
      item.pieces!.where((piece) => (piece - 0.570).abs() < 0.0001),
      hasLength(4),
    );
    expect(
      item.pieces!.where((piece) => (piece - 1.185).abs() < 0.0001),
      hasLength(4),
    );
  });

  test(
    'shutter limits select a valid box and flag heights above all boxes',
    () {
      final limits = <Map<String, dynamic>>[
        {'box_size': 155, 'max_height': 1600},
        {'box_size': 185, 'max_height': 2400},
        {'box_size': 205, 'max_height': 2800},
      ];

      final automatic = WindowModel.resolveShutterBoxFromLimits(
        windowHeight: 2000,
        limits: limits,
      );
      final validManual = WindowModel.resolveShutterBoxFromLimits(
        windowHeight: 2000,
        limits: limits,
        manuallySelectedBoxSize: 205,
      );
      final tooTall = WindowModel.resolveShutterBoxFromLimits(
        windowHeight: 3000,
        limits: limits,
      );

      expect(automatic!.boxSize, 185);
      expect(automatic.exceedsAllLimits, isFalse);
      expect(validManual!.boxSize, 205);
      expect(tooTall!.boxSize, 205);
      expect(tooTall.exceedsAllLimits, isTrue);
      expect(tooTall.maximumSupportedHeight, 2800);
    },
  );

  test('blade catalogue excludes caps and resolves only its linked track', () {
    final blade = <String, dynamic>{
      'id': 52,
      'component_type': 'blade',
      'name': 'Lame olaluxe 55 injecté ',
      'measurement': '55',
      'track_measurement': '35.0',
    };
    final tracks = <Map<String, dynamic>>[
      {
        'id': 39,
        'component_type': 'track',
        'name': 'Coulisse simple alusys',
        'measurement': '25',
      },
      {
        'id': 53,
        'component_type': 'track',
        'name': 'Coulisse simple GM',
        'measurement': '35',
      },
    ];
    final cap = <String, dynamic>{
      'id': 68,
      'component_type': 'bouchon_lame',
      'name': 'Bochon lame 55 injecté',
      'shutter_subtype': 'Lame olaluxe 55 injecté ',
      'cap_thickness': 4,
    };

    expect(WindowModel.isShutterBladeComponent(blade), isTrue);
    expect(WindowModel.isShutterBladeComponent(cap), isFalse);
    expect(WindowModel.isBladeEndCapLinkedTo(cap, blade), isTrue);
    expect(WindowModel.compatibleShutterTracks(blade, tracks), hasLength(1));
    expect(WindowModel.compatibleShutterTracks(blade, tracks).single['id'], 53);

    final futureBlade = <String, dynamic>{
      'id': 99,
      'component_type': 'blade',
      'name': 'Future blade 44',
      'measurement': '44',
      'track_measurement': '25',
    };
    final futureCap = <String, dynamic>{
      'component_type': 'bouchon_lame',
      'name': 'Future cap 44',
      'shutter_subtype': 'Future blade 44',
      'cap_thickness': 3,
    };
    expect(
      WindowModel.compatibleShutterTracks(futureBlade, tracks).single['id'],
      39,
    );
    expect(WindowModel.isBladeEndCapLinkedTo(futureCap, futureBlade), isTrue);
    expect(WindowModel.isBladeEndCapLinkedTo(cap, futureBlade), isFalse);

    final prices = <Map<String, dynamic>>[
      {
        'blade_type': 'Lame 43mm olaluxe',
        'color_id': 36,
        'price_per_sqm': 15000,
      },
      {
        // Same blade with its catalogue words in a different order.
        'blade_type': 'Lame 55 olaluxe injecté',
        'color_id': 36,
        'price_per_sqm': 14000,
      },
      {'blade_type': 'Future blade 44', 'color_id': 7, 'price_per_sqm': 17000},
    ];
    expect(
      WindowModel.resolveShutterSqmPrice(
        bladeName: blade['name'].toString(),
        bladeSubtype: 'normal',
        colorId: 36,
        prices: prices,
      ),
      14000,
    );
    expect(
      WindowModel.resolveShutterSqmPrice(
        bladeName: futureBlade['name'].toString(),
        bladeSubtype: 'normal',
        colorId: 7,
        prices: prices,
      ),
      17000,
    );
  });

  test('blade catalogue excludes caps and resolves only its linked track', () {
    final blades = [
      {'id': 1, 'component_type': 'blade', 'name': 'Blade 43'},
      {'id': 2, 'component_type': 'bouchon_lame', 'name': 'Cap 43'},
    ];
    final filtered = blades
        .where((b) => b['component_type'] == 'blade')
        .toList();
    expect(filtered.length, 1);
    expect(filtered.first['name'], 'Blade 43');
  });

  test('linked blade cap is automatic and shortens both cut ends', () {
    final model = WindowModel(db: FakeSqlDatabase(), width: 1000, height: 1400);
    model.hasShutter = true;
    model.customShutterBoxHeight = 155;
    model.componentOverrides['الشرائح (Lames)'] = {
      'id': 52,
      'component_type': 'blade',
      'name': 'Lame olaluxe 55 injecté ',
      'price': 1300,
      'unit': 'bar',
      'measurement': '55',
      'track_measurement': '35',
      'bar_length_m': 5.8,
    };
    model.componentOverrides['أغطية الشفرات (Bouchons Lames)'] = {
      'id': 68,
      'component_type': 'bouchon_lame',
      'name': 'Bochon lame 55 injecté ',
      'price': 6,
      'unit': 'piece',
      'shutter_subtype': 'Lame olaluxe 55 injecté ',
      'cap_thickness': 4,
    };

    final bom = ComponentCalculator.generateBom(model, {});
    final blades = bom.firstWhere(
      (item) => item.originalName == 'الشرائح (Lames)',
    );
    final caps = bom.firstWhere(
      (item) => item.originalName == 'أغطية الشفرات (Bouchons Lames)',
    );

    expect(blades.unitPrice, 1300);
    expect(blades.pieces, isNotEmpty);
    expect(
      blades.pieces!.every((piece) => (piece - 0.927).abs() < 0.0001),
      isTrue,
    );
    expect(caps.quantity, 24);
    expect(caps.unitPrice, 6);
    expect(caps.catalogItemId, 68);
    expect(caps.inventoryItemType, 'ShutterComponent');
    expect(caps.isInteractive, isFalse);
  });
}
