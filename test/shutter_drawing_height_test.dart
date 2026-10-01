import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('split shutter may extend below the window', () {
    final model = WindowModel(db: SqlDatabase())
      ..width = 1200
      ..height = 2000
      ..hasShutter = true
      ..isShutterSplit = true
      ..shutterSplits = [
        const ShutterSplitSection(
          width: 1200,
          leftOffset: 0,
          customHeight: 2300,
        ),
      ];

    expect(model.shutterDrawingHeight, 2300);
    expect(model.shutterIsLongerThanWindow, isTrue);
  });

  test('normal shutter does not add a separate V dimension', () {
    final model = WindowModel(db: SqlDatabase())
      ..width = 1200
      ..height = 2000
      ..hasShutter = true;

    expect(model.shutterDrawingHeight, 2000);
    expect(model.shutterIsLongerThanWindow, isFalse);
  });

  test('quotation shows how much the shutter exceeds the window', () {
    final line = DevisBuilder.buildLineItemFromDetail(
      {
        'window_type': 'mixed',
        'game': '4000',
        'largeur': 1200,
        'hauteur': 2000,
        'quantity': 1,
        'price': 1000,
        'partitions_json':
            '{"width":1200,"height":2000,"hasShutter":true,'
            '"zones":[{"content":"fixedGlass"}],'
            '"shutterSplits":[{"customHeight":2030}]}',
      },
      overrideLang: AppLanguage.french,
      forceGeneratedDetails: true,
    );

    expect(
      line.details,
      contains('Hauteur volet: +3 cm par rapport à la fenêtre'),
    );
  });

  test(
    'quotation omits shutter overrun when it does not exceed the window',
    () {
      final line = DevisBuilder.buildLineItemFromDetail(
        {
          'window_type': 'mixed',
          'game': '4000',
          'largeur': 1200,
          'hauteur': 2000,
          'quantity': 1,
          'price': 1000,
          'partitions_json':
              '{"width":1200,"height":2000,"hasShutter":true,'
              '"zones":[{"content":"fixedGlass"}],'
              '"shutterSplits":[{"customHeight":2000}]}',
        },
        overrideLang: AppLanguage.french,
        forceGeneratedDetails: true,
      );

      expect(line.details.join('\n'), isNot(contains('Hauteur volet:')));
    },
  );
}
