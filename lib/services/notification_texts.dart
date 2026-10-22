import '../settings/app_settings.dart';
import '../settings/localization.dart';

class NotificationText {
  final String title;
  final String body;
  const NotificationText(this.title, this.body);
}

/// Builds notification titles and bodies in the reader's language from the
/// language-neutral fields of an event (the push `data` payload or a Realtime
/// broadcast). The server function keeps the same templates for pushes shown
/// by the system while the application is closed.
class NotificationTexts {
  NotificationTexts._();

  static String _t(String key, AppLanguage lang, [Map<String, String>? args]) {
    var text = Localization.translate(key, lang);
    args?.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }

  static String channelName(AppLanguage lang) =>
      _t('notification.channel.name', lang);

  static String channelDescription(AppLanguage lang) =>
      _t('notification.channel.description', lang);

  /// [action] is `created`, `updated` or `deleted`.
  static NotificationText order({
    required String action,
    required String clientName,
    required String orderCode,
    String author = '',
    required AppLanguage lang,
  }) {
    final titleKey = switch (action) {
      'created' => 'notification.order_created.title',
      'deleted' => 'notification.order_deleted.title',
      _ => 'notification.order_updated.title',
    };
    final client = clientName.trim().isEmpty
        ? _t('notification.order.default_client', lang)
        : clientName.trim();
    var body = client;
    if (orderCode.trim().isNotEmpty) body += '  |  #${orderCode.trim()}';
    if (author.trim().isNotEmpty) {
      body += '\n${_t('notification.order.by', lang, {'author': author.trim()})}';
    }
    return NotificationText(_t(titleKey, lang), body);
  }

  static NotificationText prices(int count, AppLanguage lang) =>
      NotificationText(
        _t('notification.prices.title', lang),
        _t('notification.prices.body', lang, {'count': count.toString()}),
      );

  /// Text for a push `data` payload, keyed by its `type`. Returns null when
  /// the payload lacks the fields needed, so the caller keeps the server text.
  static NotificationText? fromPushData(
    Map<String, dynamic> data,
    AppLanguage lang,
  ) {
    String field(String name) => data[name]?.toString().trim() ?? '';
    final type = field('type');
    if (type.startsWith('order_')) {
      final action = field('action').isNotEmpty
          ? field('action')
          : type.substring('order_'.length);
      return order(
        action: action,
        clientName: field('client_name'),
        orderCode: field('order_code').isNotEmpty
            ? field('order_code')
            : field('order_number'),
        author: field('author'),
        lang: lang,
      );
    }
    switch (type) {
      case 'worker_assignment':
        return NotificationText(
          _t('notification.assignment.title', lang),
          _t('notification.assignment.body', lang, {
            'quantity': field('quantity').isEmpty ? '0' : field('quantity'),
            'order': field('order_number'),
          }),
        );
      case 'prices':
        final count = int.tryParse(field('count'));
        return count == null ? null : prices(count, lang);
      case 'price_publication':
        final category = switch (lang) {
          AppLanguage.arabic => field('category_title_ar'),
          AppLanguage.french => field('category_title_fr'),
          _ => field('category_title_en'),
        };
        final fallback = field('category_title_fr').isNotEmpty
            ? field('category_title_fr')
            : field('category');
        return NotificationText(
          _t('notification.price_publication.title', lang),
          _t('notification.price_publication.body', lang, {
            'category': category.isEmpty ? fallback : category,
          }),
        );
      case 'payments':
      case 'cashbox':
        if (field('amount').isEmpty) return null;
        final amount = double.tryParse(field('amount'));
        return NotificationText(
          _t('notification.$type.title', lang),
          _t('notification.money.body', lang, {
            'description': field('description'),
            'amount': amount?.toStringAsFixed(2) ?? field('amount'),
          }),
        );
      case 'deliveries':
        if (field('kind') == 'plan_created') {
          return NotificationText(
            _t('notification.delivery_plan.title', lang),
            _t('notification.delivery_plan.body', lang, {
              'order': field('order_id'),
            }),
          );
        }
        if (field('kind') == 'delivered') {
          return NotificationText(
            _t('notification.delivered.title', lang),
            _t('notification.delivered.body', lang),
          );
        }
        return null;
    }
    return null;
  }

  /// Short code stored with the push token so the server can pick the text.
  /// The server writes Arabic, French and English only: a pack language
  /// receives its fallback's text.
  static String languageCode(AppLanguage lang) => lang.fallback.code;
}
