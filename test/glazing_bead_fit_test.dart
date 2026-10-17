import 'package:database_data/Commande/Systeme/glass_joint_fit.dart';
import 'package:database_data/Commande/Systeme/glazing_fit_message.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AluminumSection _bead(int id, double capacity) => AluminumSection(
  id: id,
  seriesId: 1,
  code: 'P$id',
  name: 'Parclose $id',
  type: 'parclose',
  maxGlassThickness: capacity,
);

WindowModel _model({required String name, required List<AluminumSection> beads}) {
  final model = WindowModel(
    db: SqlDatabase(),
    width: 1000,
    height: 1200,
    profileThickness: 60,
  );
  model.activeSeries = AluminumSeries(
    id: 1,
    profileId: 1,
    name: name,
    type: 'opening',
    sections: beads,
  );
  model.zones = [
    WindowZone(
      id: 'z',
      content: ZoneContent.singleSash,
      boundary: const Rect.fromLTWH(60, 60, 880, 1080),
    ),
  ];
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PVC 18 mm bead with 5+5 panes takes an 8 mm spacer, not 12', () {
    final model = _model(name: 'PVC 70', beads: [_bead(1, 18)]);
    expect(model.isPVC, isTrue);
    expect(
      model.suggestedIntercallThicknessForDoubleGlass(
        thicknessOuter: 5,
        thicknessInner: 5,
        sliding: false,
      ),
      8,
    );
  });

  test('a simple bead that counts its gaskets is not taken for a double', () {
    // 16 mm simple bead (5 mm glass + gaskets) and a 26 mm double bead.
    final model = _model(name: 'TP67', beads: [_bead(1, 26), _bead(2, 16)]);
    expect(
      model
          .glazingBeadForGlass(
            const GlassSpecification(structure: GlassStructure.simple),
            sliding: false,
          )
          ?.id,
      2,
    );
    expect(
      model
          .glazingBeadForGlass(
            const GlassSpecification(structure: GlassStructure.double),
            sliding: false,
          )
          ?.id,
      1,
    );
  });

  test('a simple pane is never glazed in a double bead', () {
    final model = _model(name: 'TP67', beads: [_bead(1, 24)]);
    expect(
      model.glazingBeadForGlass(
        const GlassSpecification(structure: GlassStructure.simple),
        sliding: false,
      ),
      isNull,
    );
  });

  test('aluminium pack: vitrage, glass and spacer, then a bourrage +1 mm', () {
    // 24 mm bead, 5+5 panes, 3 mm vitrage; bourrage 2 or 4 mm (no 3 mm).
    final fit = fitGlassPack(
      capacity: 24,
      outer: 5,
      inner: 5,
      spacer: 12,
      doubleGlass: true,
      jointChoices: [
        for (final bourrage in [2, 4])
          [
            {'thickness': 3},
            {'thickness': bourrage},
          ],
      ],
      spacers: const [6, 8, 10, 12, 14, 16],
      outerPanes: const [5],
      innerPanes: const [5],
    )!;
    final total = fit.total;
    expect(total, greaterThanOrEqualTo(24));
    expect(total, lessThanOrEqualTo(25));
    expect(fit.outer + fit.inner, 10);
  });

  test('a manual spacer is kept and reported instead of replaced', () {
    GlassPackFit? solve({required bool lock}) => fitGlassPack(
      capacity: 18,
      outer: 5,
      inner: 5,
      spacer: 12,
      doubleGlass: true,
      jointChoices: const [[]],
      spacers: const [6, 8, 10, 12],
      outerPanes: const [5],
      innerPanes: const [5],
      lockSpacer: lock,
    );
    expect(solve(lock: true), isNull);
    expect(solve(lock: false)!.spacer, 8);

    final report = GlazingFitReport(
      structure: GlassStructure.double,
      usesBead: true,
      sliding: false,
      capacity: 18,
      outer: 5,
      inner: 5,
      spacer: 12,
      valid: false,
      manualSpacer: true,
      suggestion: solve(lock: false),
    );
    final french = describeGlazingFit(report, AppLanguage.french);
    expect(french, contains('intercalaire de 12 mm'));
    expect(french, contains('8 mm'));
    expect(french, isNot(contains('مم')));
    final arabic = describeGlazingFit(report, AppLanguage.arabic);
    expect(arabic, contains('الفاصل 12 مم'));
  });

  test('smallest fitting bead allows 1 mm excess, never a shortfall', () {
    final beads = [10.0, 14.0, 24.0];
    double? pick(double pack) =>
        smallestFittingGlazingBead(beads, (b) => b, requiredPack: pack);
    expect(pick(11), 10); // 1 mm over a 10 mm bead is accepted
    expect(pick(11.5), 14);
    expect(pick(30), 24); // nothing holds it: the largest reports overflow
  });
}
