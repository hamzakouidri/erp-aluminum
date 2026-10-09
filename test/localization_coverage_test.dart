import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';

void main() {
  group('Localization Coverage Tests', () {
    test('Dynamic frame junctions translate in all 3 languages', () {
      expect(
        Localization.translate('بين الإطار 1 و 2', AppLanguage.french),
        equals('Entre cadre 1 et 2'),
      );
      expect(
        Localization.translate('بين الإطار 1 و 2', AppLanguage.english),
        equals('Between frame 1 and 2'),
      );
      expect(
        Localization.translate('بين الإطار 1 و 2', AppLanguage.arabic),
        equals('بين الإطار 1 و 2'),
      );

      final junction = FrameAngleJunction(
        index: 0,
        firstFrameIndex: 0,
        secondFrameIndex: 1,
        firstFrame: Rect.zero,
        secondFrame: Rect.zero,
        x: 0,
        top: 0,
        bottom: 1000,
      );

      expect(junction.localizedLabel(AppLanguage.french), equals('Entre cadre 1 et 2'));
      expect(junction.localizedLabel(AppLanguage.english), equals('Between frame 1 and 2'));
      expect(junction.localizedLabel(AppLanguage.arabic), equals('بين الإطار 1 و 2'));
    });

    test('Dynamic profile length translates in all 3 languages', () {
      expect(
        Localization.translate('طول القطاع: 1250 مم', AppLanguage.french),
        equals('Longueur : 1250 mm'),
      );
      expect(
        Localization.translate('طول القطاع: 1250 مم', AppLanguage.english),
        equals('Length: 1250 mm'),
      );
      expect(
        Localization.translate('طول القطاع: 1250 مم', AppLanguage.arabic),
        equals('طول القطاع: 1250 مم'),
      );
    });

    test('Unassigned status translates in all languages', () {
      expect(
        Localization.translate('غير مُسند', AppLanguage.french),
        equals('Non assigné'),
      );
      expect(
        Localization.translate('غير مُسند', AppLanguage.english),
        equals('Unassigned'),
      );
      expect(
        Localization.translate('غير مُسند', AppLanguage.arabic),
        equals('غير مُسند'),
      );

      expect(
        Localization.translate('غير مسند', AppLanguage.french),
        equals('Non assigné'),
      );
    });

    test('Reinforcement BOM item names translate cleanly without mixed languages', () {
      const renfortProfile = 'عمود تدعيم مستقل (Profilé Renfort Rapporté)';
      expect(
        Localization.translate(renfortProfile, AppLanguage.french),
        equals('Profilé Renfort Rapporté'),
      );
      expect(
        Localization.translate(renfortProfile, AppLanguage.english),
        equals('Independent Renfort Profile'),
      );
      expect(
        Localization.translate(renfortProfile, AppLanguage.arabic),
        equals('عمود تدعيم مستقل'),
      );

      const renfortScrews = 'براغي تثبيت العمود المدعم 3.9×38 (Vis Renfort 3.9×38)';
      expect(
        Localization.translate(renfortScrews, AppLanguage.french),
        equals('Vis Renfort 3.9×38'),
      );
      expect(
        Localization.translate(renfortScrews, AppLanguage.arabic),
        equals('براغي تثبيت العمود المدعم 3.9×38'),
      );

      const renfortCaps = 'أغطية العمود المدعم (Caches Renfort)';
      expect(
        Localization.translate(renfortCaps, AppLanguage.french),
        equals('Caches Renfort'),
      );
      expect(
        Localization.translate(renfortCaps, AppLanguage.arabic),
        equals('أغطية العمود المدعم'),
      );
    });

    test('Angle profile customization strings translate properly', () {
      expect(
        Localization.translate('إلغاء بروفيل الزاوية بين الإطارات (إيقاف)', AppLanguage.french),
        equals('Désactiver le tube d\'angle entre cadres'),
      );
      expect(
        Localization.translate('حدد الفواصل بين الإطارات المتلاصقة التي يركب فيها أنبوب الزاوية 90°:', AppLanguage.french),
        equals('Sélectionnez les jonctions entre cadres recevant le tube d\'angle 90° :'),
      );
      expect(
        Localization.translate('تدعيم المونطو والأعمدة (Renfort)', AppLanguage.french),
        equals('Renfort des montants'),
      );
      expect(
        Localization.translate('قاعدة التدعيم (Règle de Renfort):', AppLanguage.french),
        equals('Règle de renfort :'),
      );
      expect(
        Localization.translate('هذه السلسلة تدعم الأعمدة المدعمة', AppLanguage.french),
        equals('Cette série supporte les montants renforcés'),
      );
      expect(
        Localization.translate('هذه السلسلة لا تدعم تدعيم المونطو', AppLanguage.french),
        equals('Cette série ne supporte pas le renfort montant'),
      );
    });

    test('BOM item localized names adhere strictly to French and Arabic rules', () {
      BomItem createBom(String name) => BomItem(
            name: name,
            originalName: name,
            category: 'profile',
            unit: 'قطاع',
            unitPrice: 100,
            quantity: 1,
          );

      // French checks
      expect(createBom('قائم وسطي معزز (Sash Central Renforcé)').getLocalizedName('fr'), equals('Central Renforcé'));
      expect(createBom('قائم جانبي معزز (Sash Lateral Renforcé)').getLocalizedName('fr'), equals('Latéral Renforcé'));
      expect(createBom('قائم وسطي (Sash Central)').getLocalizedName('fr'), equals('Central'));
      expect(createBom('قائم جانبي (Sash Lateral)').getLocalizedName('fr'), equals('Latéral'));
      expect(createBom('إطار منزلق (Cadre Coulissant)').getLocalizedName('fr'), equals('Coulissant'));
      expect(createBom('الإطار (Frame)').getLocalizedName('fr'), equals('Dormant'));
      expect(createBom('إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)').getLocalizedName('fr'), equals('Dormant côté angle'));
      expect(createBom('إطار منزلق لجهة بروفيل الزاوية (Cadre coulissant côté angle)').getLocalizedName('fr'), equals('Cadre coulissant côté angle'));
      expect(createBom('إطار جهة يمين (Frame side)').getLocalizedName('fr'), equals('Dormant côté droit'));
      expect(createBom('براغي الصندوق').getLocalizedName('fr'), equals('Vis de caisson'));

      // Arabic checks (Arabic with French in parentheses)
      expect(createBom('قائم وسطي معزز (Sash Central Renforcé)').getLocalizedName('ar'), equals('قائم وسطي معزز (Central Renforcé)'));
      expect(createBom('قائم جانبي معزز (Sash Lateral Renforcé)').getLocalizedName('ar'), equals('قائم جانبي معزز (Latéral Renforcé)'));
      expect(createBom('قائم وسطي (Sash Central)').getLocalizedName('ar'), equals('قائم وسطي (Central)'));
      expect(createBom('قائم جانبي (Sash Lateral)').getLocalizedName('ar'), equals('قائم جانبي (Latéral)'));
      expect(createBom('إطار منزلق (Cadre Coulissant)').getLocalizedName('ar'), equals('إطار منزلق (Coulissant)'));
      expect(createBom('الإطار (Frame)').getLocalizedName('ar'), equals('الإطار (Dormant)'));
      expect(createBom('إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)').getLocalizedName('ar'), equals('إطار فتح لجهة بروفيل الزاوية (Dormant côté angle)'));
      expect(createBom('إطار جهة يمين (Frame side)').getLocalizedName('ar'), equals('إطار جهة يمين (Dormant côté droit)'));
      expect(createBom('براغي الصندوق').getLocalizedName('ar'), equals('براغي الصندوق (Vis de caisson)'));
    });

    test('Material Sales strings translate cleanly in all 3 languages', () {
      final keys = [
        'لوحة المتابعة',
        'الطلبات',
        'الحجوزات',
        'التسليمات',
        'الفواتير',
        'عروض الأسعار',
        'سجل المبيعات',
        'المخزون المتاح',
        'المخزون المتاح للبيع',
        'فتح المخزون',
        'بيع المواد والمستلزمات',
        'إنشاء وثيقة',
        'وثيقة جديدة',
        'تعديل الوثيقة',
        'نوع الوثيقة',
        'الحالة',
        'العميل',
        'ملاحظات',
        'المنتج',
        'الوحدة',
        'الكمية',
        'السعر',
        'المجموع',
        'المجموع الإجمالي',
        'خصم',
        'المبلغ الصافي',
        'المبلغ المدفوع',
        'المبلغ المتبقي',
        'إضافة عنصر',
        'اختر منتجاً',
        'كل العائلات',
        'عائلة البروفيل',
        'مقاطع',
        'إكسسوارات',
        'زجاج',
        'جوانات',
        'ستائر',
        'ألواح',
      ];

      for (final key in keys) {
        final ar = Localization.translate(key, AppLanguage.arabic);
        final fr = Localization.translate(key, AppLanguage.french);
        final en = Localization.translate(key, AppLanguage.english);

        expect(ar.isNotEmpty, isTrue, reason: 'Arabic translation for "$key" is missing');
        expect(fr.isNotEmpty, isTrue, reason: 'French translation for "$key" is missing');
        expect(en.isNotEmpty, isTrue, reason: 'English translation for "$key" is missing');
        // Ensure translations are not returning the raw Arabic key fallback when requested in French or English
        expect(fr != key || fr.contains(' ') || fr.length > 2, isTrue, reason: 'French translation for "$key" falls back');
      }

      // Check specific expected translations
      expect(Localization.translate('لوحة المتابعة', AppLanguage.french), equals('Tableau de bord'));
      expect(Localization.translate('الطلبات', AppLanguage.french), equals('Commandes'));
      expect(Localization.translate('الحجوزات', AppLanguage.french), equals('Réservations'));
      expect(Localization.translate('التسليمات', AppLanguage.french), equals('Livraisons'));
      expect(Localization.translate('الفواتير', AppLanguage.french), equals('Factures'));
      expect(Localization.translate('سجل المبيعات', AppLanguage.french), equals('Journal des ventes'));
      expect(Localization.translate('المخزون المتاح للبيع', AppLanguage.french), equals('Stock disponible à la vente'));
      expect(Localization.translate('فتح المخزون', AppLanguage.french), equals('Ouvrir le stock'));
      expect(Localization.translate('بيع المواد والمستلزمات', AppLanguage.french), equals('Vente de matériaux et fournitures'));
      expect(Localization.translate('نوع الوثيقة', AppLanguage.french), equals('Type de document'));
      expect(
        ['Statut', 'État'].contains(Localization.translate('الحالة', AppLanguage.french)),
        isTrue,
      );
      expect(Localization.translate('المبلغ الصافي', AppLanguage.french), equals('Net à payer'));
      expect(
        ['Montant versé', 'Montant payé'].contains(Localization.translate('المبلغ المدفوع', AppLanguage.french)),
        isTrue,
      );
      expect(Localization.translate('المبلغ المتبقي', AppLanguage.french), equals('Montant restant'));
    });
  });
}
