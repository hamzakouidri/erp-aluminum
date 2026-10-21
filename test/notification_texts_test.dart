import 'package:database_data/services/notification_texts.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every notification key has Arabic, French and English text', () {
    final keys = Localization.keys.where((k) => k.startsWith('notification.'));
    expect(keys, isNotEmpty);
    for (final key in keys) {
      for (final lang in AppLanguage.values) {
        expect(
          Localization.stored(key, lang)?.trim() ?? '',
          isNotEmpty,
          reason: '$key has no $lang text',
        );
      }
    }
  });

  test('order texts follow the requested language', () {
    final ar = NotificationTexts.order(
      action: 'created',
      clientName: 'Ali',
      orderCode: '12',
      author: 'Sami',
      lang: AppLanguage.arabic,
    );
    expect(ar.title, '📋 طلبية جديدة في الورشة');
    expect(ar.body, 'Ali  |  #12\nبواسطة: Sami');

    final fr = NotificationTexts.order(
      action: 'updated',
      clientName: '',
      orderCode: '12',
      lang: AppLanguage.french,
    );
    expect(fr.title, "✏️ Commande modifiée dans l'atelier");
    expect(fr.body, 'Client  |  #12');

    final en = NotificationTexts.order(
      action: 'deleted',
      clientName: 'Ali',
      orderCode: '',
      author: 'Sami',
      lang: AppLanguage.english,
    );
    expect(en.title, '🗑️ Order deleted');
    expect(en.body, 'Ali\nBy: Sami');
  });

  test('push data is rendered without the sender language', () {
    final assignment = NotificationTexts.fromPushData({
      'type': 'worker_assignment',
      'quantity': '3',
      'order_number': '40',
    }, AppLanguage.french)!;
    expect(assignment.title, 'Nouvelle tâche');
    expect(
      assignment.body,
      '3 élément(s) de la commande #40 vous ont été assignés',
    );

    final payment = NotificationTexts.fromPushData({
      'type': 'payments',
      'description': 'Acompte',
      'amount': '1500',
    }, AppLanguage.english)!;
    expect(payment.title, 'New payment');
    expect(payment.body, 'Acompte - 1500.00 DZD');

    final publication = NotificationTexts.fromPushData({
      'type': 'price_publication',
      'category_title_ar': 'أسعار الإكسسوارات',
      'category_title_fr': 'Prix des accessoires',
      'category_title_en': 'Accessory prices',
    }, AppLanguage.english)!;
    expect(publication.body, contains('Accessory prices'));

    final delivered = NotificationTexts.fromPushData({
      'type': 'deliveries',
      'kind': 'delivered',
    }, AppLanguage.arabic)!;
    expect(delivered.title, 'تم تسليم الطلبية');

    final order = NotificationTexts.fromPushData({
      'type': 'order_created',
      'client_name': 'Ali',
      'order_code': '7',
    }, AppLanguage.english)!;
    expect(order.title, '📋 New order in the workshop');
  });

  test('push data without the needed fields keeps the server text', () {
    expect(
      NotificationTexts.fromPushData({'type': 'payments'}, AppLanguage.french),
      isNull,
    );
    expect(
      NotificationTexts.fromPushData({'type': 'deliveries'}, AppLanguage.french),
      isNull,
    );
    expect(
      NotificationTexts.fromPushData({'type': 'other'}, AppLanguage.french),
      isNull,
    );
  });

  group('saved language without a BuildContext', () {
    Future<AppLanguage> load(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return AppSettingsProvider.loadSavedLanguage();
    }

    test('an explicit choice is kept', () async {
      expect(
        await load({'app_language': 0, 'app_language_explicit': true}),
        AppLanguage.arabic,
      );
      expect(
        await load({'app_language': 2, 'app_language_explicit': true}),
        AppLanguage.english,
      );
    });

    test('no choice falls back to French like the settings screen', () async {
      expect(await load({}), AppLanguage.french);
      expect(await load({'app_language': 0}), AppLanguage.french);
    });
  });

  test('language codes stored with the push token', () {
    expect(NotificationTexts.languageCode(AppLanguage.arabic), 'ar');
    expect(NotificationTexts.languageCode(AppLanguage.french), 'fr');
    expect(NotificationTexts.languageCode(AppLanguage.english), 'en');
  });
}
