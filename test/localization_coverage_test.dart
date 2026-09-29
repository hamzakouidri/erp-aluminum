import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/Commande/Systeme/model.dart';
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
  });
}
