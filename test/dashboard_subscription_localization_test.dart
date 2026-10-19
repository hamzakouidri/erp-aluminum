import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard empty orders message is translated in all languages', () {
    expect(
      Localization.translate('لا توجد طلبيات بعد', AppLanguage.arabic),
      'لا توجد طلبيات بعد',
    );
    expect(
      Localization.translate('لا توجد طلبيات بعد', AppLanguage.french),
      'Aucune commande pour le moment',
    );
    expect(
      Localization.translate('لا توجد طلبيات بعد', AppLanguage.english),
      'No orders yet',
    );
  });

  test('lifetime labels are translated in all languages', () {
    expect(
      Localization.translate('اشتراك مدى الحياة', AppLanguage.arabic),
      'اشتراك مدى الحياة',
    );
    expect(
      Localization.translate('اشتراك مدى الحياة', AppLanguage.french),
      'Abonnement à vie',
    );
    expect(
      Localization.translate('اشتراك مدى الحياة', AppLanguage.english),
      'Lifetime subscription',
    );

    expect(
      Localization.translate('مدى الحياة', AppLanguage.arabic),
      'مدى الحياة',
    );
    expect(Localization.translate('مدى الحياة', AppLanguage.french), 'À vie');
    expect(
      Localization.translate('مدى الحياة', AppLanguage.english),
      'Lifetime',
    );

    expect(
      Localization.translate(
        'تتمتع ورشتكم باشتراك دائم وصلاحيات غير محدودة مدى الحياة دون الحاجة إلى تجديد.',
        AppLanguage.english,
      ),
      'Your workshop has a permanent, unlimited lifetime subscription that does not require renewal.',
    );
  });
}
