import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AluminumSection _section(int id, int seriesId, String code) => AluminumSection(
  id: id,
  seriesId: seriesId,
  code: code,
  name: code,
  type: 'frame',
  isFrame: true,
  visibleWidth: 60,
);

WindowModel _model({String systemMode = 'french'}) {
  final model = WindowModel(
    db: SqlDatabase(),
    width: 1200,
    height: 1400,
    profileThickness: 60,
    systemMode: systemMode,
  );
  model.zones = [
    WindowZone(id: 'zone_1', boundary: const Rect.fromLTRB(60, 60, 1140, 1340)),
  ];
  return model;
}

/// BS 90 (aluminium, profile 1) and a PVC series (profile 2), plus a sibling
/// PVC sliding series in the same profile system.
void _useCatalog(WindowModel model) {
  final bs90 = AluminumSeries(
    id: 10,
    profileId: 1,
    name: 'BS 90',
    type: 'opening',
    sections: [_section(101, 10, 'BS90-FRAME'), _section(102, 10, 'BS90-SASH')],
  );
  final pvc = AluminumSeries(
    id: 20,
    profileId: 2,
    name: 'PVC 70',
    type: 'opening',
    sections: [_section(201, 20, 'PVC-FRAME')],
  );
  final pvcSliding = AluminumSeries(
    id: 21,
    profileId: 2,
    name: 'PVC sliding',
    type: 'sliding',
    sections: [_section(211, 21, 'PVC-COVER')],
  );
  model.availableSystems = [
    AluminumProfileSystem(id: 1, name: 'Alu', type: 'Aluminium')
      ..series = [bs90],
    AluminumProfileSystem(id: 2, name: 'PVC', type: 'PVC')
      ..series = [pvc, pvcSliding],
  ];
  model.activeSeries = pvc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('glass default is owned by each drawing', () {
    test('painting glass in one drawing does not change another one', () {
      final first = _model();
      final second = _model();
      const doubleGlass = GlassSpecification(structure: GlassStructure.double);

      first.paintZoneOrCellSpec('zone_1', spec: doubleGlass);

      expect(first.defaultGlass.structure, GlassStructure.double);
      expect(second.defaultGlass.structure, GlassStructure.simple);
      expect(second.hasDoubleGlassForRules, isFalse);
      // A zone created without explicit glass no longer reads shared state.
      expect(
        WindowZone(id: 'new', boundary: Rect.zero).glass.structure,
        GlassStructure.simple,
      );
    });

    test('default glass survives save and reopen', () {
      final model = _model();
      model.defaultGlass = const GlassSpecification(
        structure: GlassStructure.double,
        intercallThickness: 16,
      );
      final map = model.toMap();
      expect(map['drawingSchemaVersion'], currentDrawingSchemaVersion);

      final restored = WindowModel(db: SqlDatabase());
      applyWindowModelFromMap(restored, map);
      expect(restored.defaultGlass.structure, GlassStructure.double);
      expect(restored.defaultGlass.intercallThickness, 16);
    });
  });

  group('drawing schema migration', () {
    test('unversioned drawings are read as v1 and upgraded', () {
      final legacy = <String, dynamic>{
        'width': 1000,
        'zones': [
          {
            'glass': const GlassSpecification(
              structure: GlassStructure.closed,
            ).toMap(),
          },
          {
            'glass': const GlassSpecification(
              structure: GlassStructure.double,
            ).toMap(),
          },
        ],
      };
      expect(savedDrawingSchemaVersion(legacy), 1);

      final migrated = migrateSavedWindowModelMap(legacy);
      expect(migrated['drawingSchemaVersion'], currentDrawingSchemaVersion);
      // The panneau zone is skipped; the first glazed zone is the default.
      expect(
        glassSpecificationFromMap(
          Map<String, dynamic>.from(migrated['defaultGlass'] as Map),
        ).structure,
        GlassStructure.double,
      );
      expect(legacy.containsKey('defaultGlass'), isFalse);
      expect(legacy.containsKey('drawingSchemaVersion'), isFalse);
    });

    test('a current drawing is not rewritten', () {
      final map = _model().toMap();
      final migrated = migrateSavedWindowModelMap(map);
      expect(migrated['defaultGlass'], map['defaultGlass']);
    });
  });

  test('undo and redo restore the series together with its profiles', () {
    final model = _model();
    _useCatalog(model);
    final pvc = model.activeSeries!;
    final bs90 = model.availableSystems.first.series.first;
    model.loadedSeriesId = pvc.id;
    model.sashOverride = _section(201, 20, 'PVC-FRAME').toMap();
    model.saveSnapshotOutside();

    model.activeSeries = bs90;
    model.loadedSeriesId = bs90.id;
    model.sashOverride = _section(102, 10, 'BS90-SASH').toMap();

    model.undo();
    expect(model.activeSeries?.id, pvc.id);
    expect(model.loadedSeriesId, pvc.id);
    expect(model.sashOverride?['code'], 'PVC-FRAME');

    model.redo();
    expect(model.activeSeries?.id, bs90.id);
    expect(model.loadedSeriesId, bs90.id);
    expect(model.sashOverride?['code'], 'BS90-SASH');
  });

  test('undo and redo keep the item quantity', () {
    final model = _model();
    model.quantity = 5;
    model.saveSnapshotOutside();
    model.width = 1500;

    model.undo();
    expect(model.width, 1200);
    expect(model.quantity, 5);

    model.redo();
    expect(model.width, 1500);
    expect(model.quantity, 5);
  });

  group('profiles from another series are rejected', () {
    test('BS 90 profiles are removed after switching to PVC', () {
      final model = _model();
      _useCatalog(model);
      model.componentOverrides = {
        'bs90 component': _section(102, 10, 'BS90-SASH').toMap(),
        'pvc component': _section(201, 20, 'PVC-FRAME').toMap(),
        'shared into pvc': {
          ..._section(150, 10, 'SHARED').toMap(),
          'is_shared': 1,
          'sharing_target_id': 20,
        },
        'sibling pvc series': _section(211, 21, 'PVC-COVER').toMap(),
        'accessory': {'id': 7, 'name': 'Handle', 'material_type': 'pvc'},
        'frame-bottom:zone_1': true,
      };
      model.zones.first.sashOverride = _section(102, 10, 'BS90-SASH').toMap();
      model.zones.first.cellSashOverrides = {
        'main_cell_0_0': _section(101, 10, 'BS90-FRAME').toMap(),
        'main_cell_0_1': _section(201, 20, 'PVC-FRAME').toMap(),
      };
      model.sideCoverOverride = _section(101, 10, 'BS90-FRAME').toMap();

      final found = model.overridesFromForeignSeries;
      expect(found, contains('bs90 component'));
      expect(model.componentOverrides.keys, contains('bs90 component'));
      expect(model.zones.first.sashOverride, isNotNull);

      final removed = model.removeOverridesFromForeignSeries();
      expect(removed, found);
      expect(model.overridesFromForeignSeries, isEmpty);

      expect(model.componentOverrides.keys, isNot(contains('bs90 component')));
      expect(
        model.componentOverrides.keys,
        containsAll([
          'pvc component',
          'shared into pvc',
          'sibling pvc series',
          'accessory',
          'frame-bottom:zone_1',
        ]),
      );
      expect(model.zones.first.sashOverride, isNull);
      expect(model.zones.first.cellSashOverrides.keys, ['main_cell_0_1']);
      expect(model.sideCoverOverride, isNull);
      expect(removed, contains('bs90 component'));
    });

    test('a stale sliding series does not protect profiles in french mode', () {
      final model = _model(systemMode: 'french');
      _useCatalog(model);
      model.activeSlidingSeries = model.availableSystems.first.series.first;
      model.componentOverrides = {
        'bs90 component': _section(101, 10, 'BS90-FRAME').toMap(),
      };

      model.removeOverridesFromForeignSeries();

      expect(model.componentOverrides, isEmpty);
    });

    test('the sliding series of a mixed drawing stays valid', () {
      final model = _model(systemMode: 'mixed');
      _useCatalog(model);
      model.activeSlidingSeries = model.availableSystems.first.series.first;
      model.componentOverrides = {
        'bs90 sliding part': _section(101, 10, 'BS90-FRAME').toMap(),
      };

      model.removeOverridesFromForeignSeries();

      expect(model.componentOverrides.keys, ['bs90 sliding part']);
    });
  });
}
