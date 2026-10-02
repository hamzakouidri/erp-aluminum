import 'dart:ui';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Smart Window Composition Title and Description Tests', () {
    test('Multi-frame: 4-sash sliding + 2-sash beating with 1 fixed pane', () {
      final drawing = {
        'seriesName': 'TPR 40000',
        'slidingSeriesName': 'TPR 67000',
        'zones': [
          // Frame 1: 4-sash sliding (left: 50, right: 1450)
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 1400.0,
              'height': 1200.0,
            },
            'content': 'slidingSash',
            'slidingSashesCount': 4,
            'glass': {'structure': 'double'},
          },
          // Frame 2: 2-sash beating + 1 fixed pane (left: 1550, gap=100mm from frame 1)
          {
            'boundary': {
              'left': 1550.0,
              'top': 50.0,
              'width': 800.0,
              'height': 1200.0,
            },
            'content': 'doubleSash',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 2350.0,
              'top': 50.0,
              'width': 400.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      // French
      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(
        frComp,
        'Fenêtre coulissante 4 vantaux et Fenêtre double vantaux avec partie fixe',
      );

      final frLine = DevisBuilder.buildLineItemFromDetail({
        'id': 1,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.french);
      expect(
        frLine.title,
        'Fenêtre coulissante 4 vantaux et Fenêtre double vantaux avec partie fixe double vitrage',
      );
      expect(frLine.details.first, 'Gamme: TPR 67000 / TPR 40000');
      expect(
        frLine.details.first,
        isNot(contains('Fenêtre coulissante 4 vantaux')),
      );

      // Arabic
      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'نافذة منزلقة 4 درفات و نافذة بضلفتين مع جزء ثابت');

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 1,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.arabic);
      expect(
        arLine.title,
        'نافذة منزلقة 4 درفات و نافذة بضلفتين مع جزء ثابت بزجاج مزدوج',
      );
    });

    test('Fixed pane belongs to the sliding window instead', () {
      final drawing = {
        'zones': [
          // Frame 1: 4-sash sliding + 1 fixed pane (left: 50 to 1850)
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 1400.0,
              'height': 1200.0,
            },
            'content': 'slidingSash',
            'slidingSashesCount': 4,
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 1450.0,
              'top': 50.0,
              'width': 400.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
          // Frame 2: 2-sash beating only (left: 1950, gap=100mm from frame 1)
          {
            'boundary': {
              'left': 1950.0,
              'top': 50.0,
              'width': 800.0,
              'height': 1200.0,
            },
            'content': 'doubleSash',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(
        frComp,
        'Fenêtre coulissante 4 vantaux avec partie fixe et Fenêtre double vantaux',
      );

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'نافذة منزلقة 4 درفات مع جزء ثابت و نافذة بضلفتين');
    });

    test('Single frame: 2-sash beating with 2 fixed panes', () {
      final drawing = {
        'zones': [
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 400.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 450.0,
              'top': 50.0,
              'width': 800.0,
              'height': 1200.0,
            },
            'content': 'doubleSash',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 1250.0,
              'top': 50.0,
              'width': 400.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(frComp, 'Fenêtre double vantaux avec 2 parties fixes');

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'نافذة بضلفتين مع جزئين ثابتين');

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 2,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.arabic);
      expect(arLine.title, 'نافذة بضلفتين مع جزئين ثابتين بزجاج مزدوج');
    });

    test('Single frame: 2-sash beating with 3 fixed panes', () {
      final drawing = {
        'zones': [
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 800.0,
              'height': 1200.0,
            },
            'content': 'doubleSash',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 850.0,
              'top': 50.0,
              'width': 400.0,
              'height': 400.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 850.0,
              'top': 450.0,
              'width': 400.0,
              'height': 400.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 850.0,
              'top': 850.0,
              'width': 400.0,
              'height': 400.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(frComp, 'Fenêtre double vantaux avec 3 parties fixes');

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'نافذة بضلفتين مع 3 أجزاء ثابتة');
    });

    test('Single frame: pure fixed window (1 pane)', () {
      final drawing = {
        'zones': [
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 1000.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(frComp, 'Fixe');

      final frLine = DevisBuilder.buildLineItemFromDetail({
        'id': 3,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.french);
      expect(frLine.title, 'Fixe double vitrage');

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'إطار ثابت');

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 3,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.arabic);
      expect(arLine.title, 'إطار ثابت بزجاج مزدوج');
    });

    test('Single frame: pure fixed window (2 panes in same frame)', () {
      final drawing = {
        'zones': [
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 600.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
          {
            'boundary': {
              'left': 650.0,
              'top': 50.0,
              'width': 600.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(frComp, 'Fixe (2 parties fixes)');

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'إطار ثابت (جزئين ثابتين)');
    });

    test('Multi-frame: 4-sash sliding + pure fixed frame', () {
      final drawing = {
        'zones': [
          // Frame 1: 4-sash sliding
          {
            'boundary': {
              'left': 50.0,
              'top': 50.0,
              'width': 1600.0,
              'height': 1200.0,
            },
            'content': 'slidingSash',
            'slidingSashesCount': 4,
            'glass': {'structure': 'double'},
          },
          // Frame 2: Fixed frame (gap=100mm)
          {
            'boundary': {
              'left': 1750.0,
              'top': 50.0,
              'width': 800.0,
              'height': 1200.0,
            },
            'content': 'fixedGlass',
            'glass': {'structure': 'double'},
          },
        ],
      };

      final frComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.french,
      );
      expect(frComp, 'Fenêtre coulissante 4 vantaux et Fixe');

      final arComp = DevisBuilder.generateSmartCompositionDescription(
        drawing,
        AppLanguage.arabic,
      );
      expect(arComp, 'نافذة منزلقة 4 درفات و إطار ثابت');
    });

    test('3-sash opening window only shows opening series, not sliding', () {
      final drawing = {
        'seriesName': 'TPR 40000',
        'slidingSeriesName': 'TPR 67000',
        'zones': [
          {
            'boundary': {'left': 0.0, 'top': 0.0, 'width': 600.0, 'height': 1200.0},
            'content': 'singleSash',
          },
          {
            'boundary': {'left': 600.0, 'top': 0.0, 'width': 600.0, 'height': 1200.0},
            'content': 'singleSash',
          },
          {
            'boundary': {'left': 1200.0, 'top': 0.0, 'width': 600.0, 'height': 1200.0},
            'content': 'singleSash',
          },
        ],
      };

      final frLine = DevisBuilder.buildLineItemFromDetail({
        'id': 10,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.french);
      expect(frLine.details.first, 'Gamme: TPR 40000');
      expect(frLine.details.first.contains('67000'), isFalse);

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 10,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.arabic);
      expect(arLine.details.first, 'السلسلة: TPR 40000');
      expect(arLine.details.first.contains('67000'), isFalse);
    });

    test('2-sash sliding window only shows sliding series, not opening', () {
      final drawing = {
        'seriesName': 'TPR 40000',
        'slidingSeriesName': 'TPR 67000',
        'zones': [
          {
            'boundary': {'left': 0.0, 'top': 0.0, 'width': 1200.0, 'height': 1200.0},
            'content': 'slidingSash',
            'slidingSashesCount': 2,
          },
        ],
      };

      final frLine = DevisBuilder.buildLineItemFromDetail({
        'id': 11,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.french);
      expect(frLine.details.first, 'Gamme: TPR 67000');
      expect(frLine.details.first.contains('40000'), isFalse);

      final arLine = DevisBuilder.buildLineItemFromDetail({
        'id': 11,
        'partitions_json': drawing,
      }, overrideLang: AppLanguage.arabic);
      expect(arLine.details.first, 'السلسلة: TPR 67000');
      expect(arLine.details.first.contains('40000'), isFalse);
    });

    test('Multi-frame independent sashes: zone sashOverride and serialization', () {
      final zone1 = WindowZone(
        id: 'z1',
        boundary: const Rect.fromLTWH(0, 0, 800, 1200),
        content: ZoneContent.singleSash,
        sashOverride: {
          'id': 104,
          'code': 'TPR-104',
          'name': 'Ouvrant 104',
          'visible_width': 50.0,
        },
      );
      final zone2 = WindowZone(
        id: 'z2',
        boundary: const Rect.fromLTWH(800, 0, 800, 1200),
        content: ZoneContent.singleSash,
        sashOverride: {
          'id': 105,
          'code': 'TPR-105',
          'name': 'Ouvrant 105',
          'visible_width': 70.0,
        },
      );

      final map1 = zone1.toMap();
      final map2 = zone2.toMap();

      expect(map1['sashOverride']['code'], 'TPR-104');
      expect(map2['sashOverride']['code'], 'TPR-105');

      final restored1 = windowZoneFromMap(map1);
      final restored2 = windowZoneFromMap(map2);

      expect(restored1.sashOverride?['code'], 'TPR-104');
      expect(restored2.sashOverride?['code'], 'TPR-105');

      final cloned1 = restored1.clone();
      final cloned2 = restored2.clone();
      expect(cloned1.sashOverride?['code'], 'TPR-104');
      expect(cloned2.sashOverride?['code'], 'TPR-105');
    });
  });
}
