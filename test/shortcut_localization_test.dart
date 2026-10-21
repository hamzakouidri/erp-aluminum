import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/shortcut_bindings.dart';

void main() {
  test('shortcut and division labels resolve in French and English', () {
    const labels = [
      'إضافة اختصار جديد',
      'ابحث عن صفحة أو خاصية...',
      'لا توجد خصائص أخرى لإضافتها.',
      'الرسم والطلبات',
      'الحسابات والسندات',
      'الزبائن والمشاريع',
      'المخزون والمنتجات',
      'التقارير والمهام',
      'الإدارة والإعدادات',
      'المبيعات',
      'المشتريات',
      'الموردون',
      'المنتجات',
      'الزبائن',
      'كشف حساب الزبائن',
      'رفع القياسات',
      'التوزيع والتتبع',
      'مركز التقارير',
      'كل المشاريع',
      'مهامي وتصنيعاتي',
      'أرشيف المهام والتوزيع',
      'المهام الخارجية',
      'صلاحيات المستخدمين',
      'إدارة الأسعار',
      'الأنظمة المستعملة',
      'إعدادات التطبيق',
      'تقرير النواقص',
      'تُحفظ الاختصارات لجميع أعضاء الورشة.',
      'اختر أمرًا ثم اضغط المفاتيح المطلوبة. لا تعمل الاختصارات أثناء الكتابة أو فتح نافذة حوار.',
      'اضغط المفاتيح الآن (Esc للإلغاء)',
      'هذا الاختصار مستخدم لأمر آخر.',
      'تعديل الطلبية المحددة',
      'حذف الطلبية المحددة',
      'لتعديل أو حذف طلبية، حدد زر خياراتها بلوحة المفاتيح أولًا.',
      'تسعيرة الطلبية المحددة',
      'تفاصيل الطلبية المحددة',
      'استعادة الاختصارات الافتراضية',
      'هل تريد حقاً استعادة جميع الاختصارات الافتراضية؟',
      'استعادة',
    ];
    for (final key in labels) {
      for (final language in [AppLanguage.french, AppLanguage.english]) {
        expect(Localization.stored(key, language), isNotNull, reason: key);
        expect(Localization.translate(key, language), isNot(key));
      }
    }
  });

  test('shortcut catalog commands are categorized and translated', () {
    expect(
      ShortcutBindings.defaultCommands,
      everyElement(isIn(ShortcutBindings.commands.keys)),
    );
    expect(
      ShortcutBindings.commandCategories.keys,
      containsAll(ShortcutBindings.commands.keys),
    );

    for (final command in ShortcutBindings.commands.entries) {
      final category = ShortcutBindings.commandCategories[command.key];
      expect(
        category,
        isNotNull,
        reason: 'Missing category for ${command.key}',
      );
      for (final language in [AppLanguage.french, AppLanguage.english]) {
        expect(
          Localization.translate(command.value, language),
          isNot(command.value),
          reason: 'Missing ${language.name} label for ${command.key}',
        );
        expect(
          Localization.translate(category!, language),
          isNot(category),
          reason: 'Missing ${language.name} category for ${command.key}',
        );
      }
    }
  });
}
