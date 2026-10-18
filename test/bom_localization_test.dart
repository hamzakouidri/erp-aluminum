import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';

void main() {
  group('BOM Label and Localization Tests', () {
    test('Cache dormant localized cleanly in FR and AR', () {
      final item = BomItem(
        category: 'profile',
        quantity: 1,
        unit: 'قطاع',
        unitPrice: 0.0,
        originalName: 'Cache dormant (Coulissant)',
        name: 'Cache dormant (Coulissant)',
      );
      expect(item.getLocalizedName('fr'), 'Cache dormant');
      expect(item.getLocalizedName('ar'), 'كاش دورمو (Cache dormant)');
    });

    test('Seuil localized cleanly in FR and AR', () {
      final item = BomItem(
        category: 'profile',
        quantity: 1,
        unit: 'قطاع',
        unitPrice: 0.0,
        originalName: 'Seuil (Coulissant)',
        name: 'Seuil (Coulissant)',
      );
      expect(item.getLocalizedName('fr'), 'Seuil');
      expect(item.getLocalizedName('ar'), 'سوي (Seuil)');
    });

    test('Cache-rail localized cleanly in FR and AR', () {
      final item = BomItem(
        category: 'profile',
        quantity: 1,
        unit: 'قطاع',
        unitPrice: 0.0,
        originalName: 'Cache-rail (Coulissant)',
        name: 'Cache-rail (Coulissant)',
      );
      expect(item.getLocalizedName('fr'), 'Cache-rail');
      expect(item.getLocalizedName('ar'), 'كاش راي (Cache-rail)');
    });

    test(
      'Chicane displays as Chicane in FR and شيكان in AR without extra prefixes',
      () {
        final item = BomItem(
          category: 'profile',
          quantity: 1,
          unit: 'قطاع',
          unitPrice: 0.0,
          originalName: 'الشيكان (Chicane)',
          name: 'الشيكان (Chicane)',
        );
        expect(item.getLocalizedName('fr'), 'Chicane');
        expect(item.getLocalizedName('ar'), 'شيكان (Chicane)');
      },
    );

    test(
      'Sliding sash eliminates Arabic المنزلقة in French and is clean in Arabic',
      () {
        final item = BomItem(
          category: 'profile',
          quantity: 1,
          unit: 'قطاع',
          unitPrice: 0.0,
          originalName: 'الظلفة المنزلقة (Sliding Sash)',
          name: 'الظلفة المنزلقة (Sliding Sash)',
        );
        expect(item.getLocalizedName('fr'), 'Ouvrant Coulissant');
        expect(item.getLocalizedName('en'), 'Sliding Sash');
        expect(
          item.getLocalizedName('ar'),
          'الضلفة المنزلقة (Ouvrant Coulissant)',
        );
      },
    );

    test(
      'Frame extension displays as Complément Dormant in FR and كومبليمو دورمو in AR',
      () {
        final item = BomItem(
          category: 'profile',
          quantity: 1,
          unit: 'قطاع',
          unitPrice: 0.0,
          originalName: 'كومبليمو دورمو (Complément Dormant)',
          name: 'كومبليمو دورمو (Complément Dormant)',
        );
        expect(item.getLocalizedName('fr'), 'Complément Dormant');
        expect(
          item.getLocalizedName('ar'),
          'كومبليمو دورمو (Complément Dormant)',
        );
      },
    );

    test(
      'localizeSubText translates المطلوب الفعلي to Besoin réel in French',
      () {
        const sub = '(المطلوب الفعلي: 1.37 بارة / 1.37 bar)';
        expect(BomItem.localizeSubText(sub, 'fr'), '(Besoin réel: 1.37 bar)');
        // Arabic keeps the full line, including the bars breakdown.
        expect(BomItem.localizeSubText(sub, 'ar'), sub);
        expect(
          BomItem.localizeSubText(sub, 'en'),
          '(Actual requirement: 1.37 bar)',
        );
      },
    );

    test(
      'getLocalizedCuttingList translates قطع القص to Liste de coupe in French',
      () {
        final item = BomItem(
          category: 'profile',
          quantity: 1,
          unit: 'قطاع',
          unitPrice: 0.0,
          originalName: 'الشيكان (Chicane)',
          name: 'الشيكان (Chicane)',
          cuttingList: 'قطع القص: 6 × 2400 مم',
        );
        expect(
          item.getLocalizedCuttingList('fr'),
          'Liste de coupe: 6 × 2400 mm',
        );
        expect(item.getLocalizedCuttingList('en'), 'Cutting list: 6 × 2400 mm');
        expect(item.getLocalizedCuttingList('ar'), 'قطع القص: 6 × 2400 مم');
      },
    );
  });
}
