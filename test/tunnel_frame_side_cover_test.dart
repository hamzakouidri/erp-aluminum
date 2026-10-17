import 'dart:async';
import 'dart:ui';

import 'package:database_data/Commande/Systeme/bom_engine_v2.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

// Profile resolution uses the catalogue methods below, never a native database.
class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FrameDatabase extends SqlDatabase {
  _FrameDatabase({this.onlyIntegrated = false});

  final bool onlyIntegrated;
  Completer<double>? pendingPrice;
  Completer<List<Map<String, dynamic>>>? pendingFrames;

  @override
  Future<Database?> get db async => _UnusedDatabase();

  @override
  Future<List<Map<String, dynamic>>> getCatalogItemRules({
    String? itemTable,
    int? itemId,
    int? seriesId,
    Iterable<String> roleKeys = const [],
    bool exactSeriesOnly = false,
    bool includeInactive = false,
  }) async => const [];

  @override
  Future<double> getSectionPrice(dynamic nameOrId, [int? colorId]) async =>
      pendingPrice == null ? 100 : await pendingPrice!.future;

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) async => pendingFrames != null
      ? await pendingFrames!.future
      : roleKeys.contains('frame')
      ? [
          if (!onlyIntegrated) _frame(seriesId, integrated: false).toMap(),
          _frame(seriesId, integrated: true).toMap(),
        ]
      : [];

  @override
  Future<List<Map<String, dynamic>>> getDesignSectionsForScopedDialogRoles(
    int seriesId,
    Iterable<String> roleKeys, {
    required String usageScope,
    bool requireDialog = true,
    bool requireQuantity = false,
    bool requireVisible = true,
  }) => getDesignSectionsForRoles(
    seriesId,
    roleKeys,
    requireDialog: requireDialog,
    requireQuantity: requireQuantity,
    requireVisible: requireVisible,
  );
}

AluminumSection _frame(int seriesId, {required bool integrated}) =>
    AluminumSection(
      id: integrated ? 102 : 101,
      seriesId: seriesId,
      code: integrated ? 'INTEGRATED' : 'PLAIN',
      name: integrated ? 'Integrated frame' : 'Plain frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 60,
      couvreJointWidth: integrated ? 25 : 0,
      barLength: 6,
    );

WindowModel _window({bool sliding = false, _FrameDatabase? database}) {
  final series = AluminumSeries(
    id: 10,
    profileId: 1,
    name: 'Test series',
    type: sliding ? 'sliding' : 'opening',
    sections: [_frame(10, integrated: false), _frame(10, integrated: true)],
  );
  final model = WindowModel(
    db: database ?? _FrameDatabase(),
    width: 1200,
    height: 1500,
    profileThickness: 60,
    systemMode: sliding ? 'sliding' : 'mixed',
  );
  model.availableSystems = [
    AluminumProfileSystem(
      id: 1,
      name: 'Aluminium system',
      type: 'Aluminium',
      series: [series],
    ),
  ];
  if (sliding) {
    model.activeSlidingSeries = series;
  } else {
    model.activeSeries = series;
  }
  model.zones = [
    WindowZone(
      id: 'window',
      boundary: const Rect.fromLTWH(60, 60, 1080, 1380),
      content: sliding ? ZoneContent.slidingSash : ZoneContent.fixedGlass,
    ),
  ];
  model.applyFrameOverride(
    series.sections.first.toMap(),
    sliding: sliding,
    manualSelection: true,
  );
  model.hasShutter = true;
  return model;
}

BomItem _frameRow({bool sliding = false}) => BomItem(
  category: 'profile',
  originalName: sliding ? 'Sliding frame' : 'Frame',
  name: 'Frame',
  quantity: 1,
  unit: 'bar',
  unitPrice: 100,
  selectorType: 'frame',
  roleKey: 'frame',
  sourceSeriesId: 10,
  materialType: 'Aluminium',
);

void main() {
  test('PVC drawing uses selected frame visible width', () {
    final model = _window();
    addTearDown(model.dispose);
    final selected = AluminumSection(
      id: 103,
      seriesId: 10,
      code: 'PVC-WIDE-INTEGRATED',
      name: 'PVC integrated frame',
      type: 'frame',
      isFrame: true,
      visibleWidth: 92,
      couvreJointWidth: 30,
      barLength: 6,
    );
    model.activeSeries = AluminumSeries(
      id: 10,
      profileId: 1,
      name: 'PVC test series',
      type: 'opening',
      sections: [selected],
    );
    model.availableSystems = [
      AluminumProfileSystem(
        id: 1,
        name: 'PVC system',
        type: 'PVC',
        series: [model.activeSeries!],
      ),
    ];
    model.applyFrameOverride(
      selected.toMap(),
      sliding: false,
      manualSelection: true,
    );

    final frameRect = model.getFrameRects().first;
    expect(model.frameVisibleWidthForRect(frameRect), 92);
    expect(model.selectedOuterFrameHasIntegratedSideCover, isTrue);
    expect(model.canUseStandaloneSideCover, isFalse);
  });

  for (final material in ['Aluminium', 'PVC']) {
    for (final mode in AccessoryDrawingMode.values) {
      for (final box in ['none', 'regular', 'tunnel']) {
        test('$material $mode frame candidates with $box box', () async {
          final result =
              await CatalogCandidateResolver(
                database: _FrameDatabase(),
              ).resolve(
                CatalogCandidateQuery(
                  category: 'profile',
                  selectorType: 'frame',
                  seriesId: 10,
                  materialType: material,
                  hasShutter: box != 'none',
                  isCaissonTunnel: box == 'tunnel',
                  hasSideCovers: true,
                  drawingMode: mode,
                ),
              );
          expect(result.map((row) => row['code']), [
            'PLAIN',
            if (material == 'PVC' || box != 'regular') 'INTEGRATED',
          ]);
        });
      }
    }
  }

  test('Tunnel does not bypass the multi-frame PVC restriction', () async {
    final result = await CatalogCandidateResolver(database: _FrameDatabase())
        .resolve(
          const CatalogCandidateQuery(
            category: 'profile',
            selectorType: 'frame',
            seriesId: 10,
            materialType: 'PVC',
            hasShutter: true,
            isCaissonTunnel: true,
            multiFrameDrawing: true,
          ),
        );
    expect(result.map((row) => row['code']), ['PLAIN']);
  });

  for (final sliding in [false, true]) {
    test(
      'Tunnel integrated selection enables its cover (sliding=$sliding)',
      () async {
        final model = _window(sliding: sliding);
        addTearDown(model.dispose);
        expect(model.hasSideCovers, isFalse);
        model.toggleCaissonTunnel(true);
        model.applyFrameOverride(
          _frame(10, integrated: true).toMap(),
          sliding: sliding,
          manualSelection: true,
        );

        expect(model.activeFrameOverride?['code'], 'INTEGRATED');
        expect(model.hasSideCovers, isTrue);
        expect(model.isIntegratedFrame, isTrue);
        expect(model.isSideCoverAllowed, isTrue);
        expect(model.sideCoverWidth, 25);

        await model.ensureFrameCompatibleWithShutter();
        await model.toggleSideCovers(true);
        final engine = BomEngineV2(database: _FrameDatabase());
        await engine.stabilizeSelections(
          window: model,
          items: [_frameRow(sliding: sliding)],
        );
        expect(model.activeFrameOverride?['code'], 'INTEGRATED');
        expect(model.hasSideCovers, isTrue);

        final bom = ComponentCalculator.generateBom(model, {});
        expect(bom.any((row) => row.profileCode == 'INTEGRATED'), isTrue);
        expect(bom.where((row) => row.roleKey == 'side_cover'), isEmpty);

        model.toggleCaissonTunnel(false);
        await model.ensureFrameCompatibleWithShutter();
        expect(model.hasShutter, isTrue);
        expect(model.activeFrameOverride?['code'], 'PLAIN');
        expect(model.isIntegratedFrame, isFalse);
      },
    );
  }

  for (final sliding in [false, true]) {
    for (final box in ['none', 'regular', 'tunnel']) {
      test(
        'cover button replaces incompatible $box frame (sliding=$sliding)',
        () async {
          final model = _window(sliding: sliding);
          addTearDown(model.dispose);
          model.hasShutter = box != 'none';
          model.isCaissonTunnel = box == 'tunnel';
          final incompatibleFrame = {
            ..._frame(10, integrated: false).toMap(),
            'id': 103,
            'code': 'NO-COVER',
            'allows_side_cover': 1,
            'design_allows_side_cover': 0,
            'design_integrated_side_cover': 0,
          };
          model.activeFrameSeries!.sections.add(
            AluminumSection.fromMap(incompatibleFrame),
          );
          model.hasSideCovers = true;
          model.applyFrameOverride(
            incompatibleFrame,
            sliding: sliding,
            manualSelection: true,
          );
          model.refreshUI();
          expect(model.activeFrameOverride?['code'], 'NO-COVER');
          // A manually chosen plain frame keeps an enabled cover as a
          // separate profile (see multi_frame_side_cover_test).
          expect(model.hasSideCovers, isTrue);
          expect(model.getFrameRects(), hasLength(1));

          for (var repeat = 0; repeat < 2; repeat++) {
            await model.toggleSideCovers(true);
            expect(model.hasSideCovers, isTrue);
            expect(
              model.activeFrameOverride?['code'],
              box == 'regular' ? 'PLAIN' : 'INTEGRATED',
            );
            expect(model.isIntegratedFrame, box != 'regular');
            await model.toggleSideCovers(false);
            expect(model.hasSideCovers, isFalse);
            expect(model.activeFrameOverride?['code'], 'PLAIN');
          }
        },
      );
    }
  }

  test(
    'pending cover activation cannot override a later manual selection',
    () async {
      final database = _FrameDatabase()
        ..pendingFrames = Completer<List<Map<String, dynamic>>>();
      final model = _window(database: database)..isCaissonTunnel = true;
      addTearDown(model.dispose);
      final enabling = model.toggleSideCovers(true);
      model.applyFrameOverride(
        _frame(10, integrated: false).toMap(),
        sliding: false,
        manualSelection: true,
      );
      database.pendingFrames!.complete([_frame(10, integrated: true).toMap()]);
      await enabling;
      // The late catalogue answer must not swap the manually chosen frame;
      // the plain frame keeps the enabled cover as a separate profile.
      expect(model.activeFrameOverride?['code'], 'PLAIN');
      expect(model.hasSideCovers, isTrue);
    },
  );

  test('no configured alternative never selects an unrelated frame', () async {
    final database = _FrameDatabase()
      ..pendingFrames = (Completer<List<Map<String, dynamic>>>()..complete([]));
    final model = _window(database: database)..isCaissonTunnel = true;
    addTearDown(model.dispose);
    await model.toggleSideCovers(true);
    expect(model.activeFrameOverride?['code'], 'PLAIN');
    expect(model.hasSideCovers, isTrue);
  });

  test('BOM candidate cache distinguishes regular and tunnel boxes', () async {
    final model = _window();
    addTearDown(model.dispose);
    final engine = BomEngineV2(database: _FrameDatabase(onlyIntegrated: true));
    final rows = [_frameRow()];
    for (final tunnel in [false, true, false, true]) {
      model.isCaissonTunnel = tunnel;
      final filtered = await engine.filterItemsByAvailableCandidates(
        window: model,
        items: rows,
      );
      expect(filtered, tunnel ? hasLength(1) : isEmpty);
    }
  });

  test(
    'pending regular-box lookup cannot replace a new tunnel frame',
    () async {
      final database = _FrameDatabase()..pendingPrice = Completer<double>();
      final model = _window(database: database);
      addTearDown(model.dispose);
      model.frameOverride = _frame(10, integrated: true).toMap();
      model.selectedDbColor = {'id': 1};
      final pending = model.ensureFrameCompatibleWithShutter();

      model.toggleCaissonTunnel(true);
      model.applyFrameOverride(
        _frame(10, integrated: true).toMap(),
        sliding: false,
        manualSelection: true,
      );
      database.pendingPrice!.complete(100);
      await pending;
      expect(model.activeFrameOverride?['code'], 'INTEGRATED');
      expect(model.hasSideCovers, isTrue);
    },
  );
}
