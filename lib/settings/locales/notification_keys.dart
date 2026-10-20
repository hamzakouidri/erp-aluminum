import '../app_settings.dart';

/// Texts of system notifications (local and push). The same templates are
/// mirrored in supabase/functions/send-worker-assignment/index.ts so a push
/// shown by the phone while the app is closed uses the device's language.
const Map<String, Map<AppLanguage, String>> notificationKeys = {
  'notification.channel.name': {
    AppLanguage.arabic: 'إشعارات الطلبيات',
    AppLanguage.french: 'Notifications des commandes',
    AppLanguage.english: 'Order notifications',
  },
  'notification.channel.description': {
    AppLanguage.arabic:
        'تنبيهات صوتية فورية عند إضافة أو تعديل الطلبيات في الورشة',
    AppLanguage.french:
        'Alertes sonores immédiates à l\'ajout ou à la modification des commandes de l\'atelier',
    AppLanguage.english:
        'Instant sound alerts when workshop orders are added or changed',
  },
  'notification.generic.title': {
    AppLanguage.arabic: 'تنبيه جديد',
    AppLanguage.french: 'Nouvelle alerte',
    AppLanguage.english: 'New alert',
  },
  'notification.generic.body': {
    AppLanguage.arabic: 'حدث جديد في الورشة',
    AppLanguage.french: 'Nouvel événement dans l\'atelier',
    AppLanguage.english: 'New event in the workshop',
  },
  'notification.order_created.title': {
    AppLanguage.arabic: '📋 طلبية جديدة في الورشة',
    AppLanguage.french: '📋 Nouvelle commande dans l\'atelier',
    AppLanguage.english: '📋 New order in the workshop',
  },
  'notification.order_updated.title': {
    AppLanguage.arabic: '✏️ تعديل طلبية في الورشة',
    AppLanguage.french: '✏️ Commande modifiée dans l\'atelier',
    AppLanguage.english: '✏️ Order updated in the workshop',
  },
  'notification.order_deleted.title': {
    AppLanguage.arabic: '🗑️ تم حذف طلبية',
    AppLanguage.french: '🗑️ Commande supprimée',
    AppLanguage.english: '🗑️ Order deleted',
  },
  'notification.order.default_client': {
    AppLanguage.arabic: 'عميل',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Customer',
  },
  'notification.order.by': {
    AppLanguage.arabic: 'بواسطة: {author}',
    AppLanguage.french: 'Par : {author}',
    AppLanguage.english: 'By: {author}',
  },
  'notification.assignment.title': {
    AppLanguage.arabic: 'مهمة جديدة',
    AppLanguage.french: 'Nouvelle tâche',
    AppLanguage.english: 'New task',
  },
  'notification.assignment.body': {
    AppLanguage.arabic: 'تم إسناد {quantity} عنصر لك من الطلبية #{order}',
    AppLanguage.french:
        '{quantity} élément(s) de la commande #{order} vous ont été assignés',
    AppLanguage.english:
        '{quantity} item(s) from order #{order} were assigned to you',
  },
  'notification.prices.title': {
    AppLanguage.arabic: 'تحديث الأسعار',
    AppLanguage.french: 'Mise à jour des prix',
    AppLanguage.english: 'Price update',
  },
  'notification.prices.body': {
    AppLanguage.arabic: 'تم تحديث {count} سعر في إدارة الأسعار',
    AppLanguage.french: '{count} prix mis à jour dans la gestion des prix',
    AppLanguage.english: '{count} prices updated in price management',
  },
  'notification.price_publication.title': {
    AppLanguage.arabic: 'أسعار جديدة متوفرة',
    AppLanguage.french: 'Nouveaux prix disponibles',
    AppLanguage.english: 'New prices available',
  },
  'notification.price_publication.body': {
    AppLanguage.arabic:
        'نشر مدير التطبيق تحديثاً في: {category}. افتح التطبيق لقبوله أو تجاهله.',
    AppLanguage.french:
        'L\'administrateur a publié une mise à jour : {category}. Ouvrez l\'application pour l\'accepter ou l\'ignorer.',
    AppLanguage.english:
        'The administrator published an update: {category}. Open the app to accept or ignore it.',
  },
  'notification.payments.title': {
    AppLanguage.arabic: 'حركة دفع جديدة',
    AppLanguage.french: 'Nouveau paiement',
    AppLanguage.english: 'New payment',
  },
  'notification.cashbox.title': {
    AppLanguage.arabic: 'حركة صندوق جديدة',
    AppLanguage.french: 'Nouveau mouvement de caisse',
    AppLanguage.english: 'New cash movement',
  },
  'notification.money.body': {
    AppLanguage.arabic: '{description} - {amount} د.ج',
    AppLanguage.french: '{description} - {amount} DA',
    AppLanguage.english: '{description} - {amount} DZD',
  },
  'notification.delivery_plan.title': {
    AppLanguage.arabic: 'خطة توزيع جديدة',
    AppLanguage.french: 'Nouveau plan de distribution',
    AppLanguage.english: 'New distribution plan',
  },
  'notification.delivery_plan.body': {
    AppLanguage.arabic: 'تم إنشاء خطة توزيع للطلبية #{order}',
    AppLanguage.french:
        'Un plan de distribution a été créé pour la commande #{order}',
    AppLanguage.english: 'A distribution plan was created for order #{order}',
  },
  'notification.delivered.title': {
    AppLanguage.arabic: 'تم تسليم الطلبية',
    AppLanguage.french: 'Commande livrée',
    AppLanguage.english: 'Order delivered',
  },
  'notification.delivered.body': {
    AppLanguage.arabic: 'تم تأكيد خطة التوزيع بنجاح',
    AppLanguage.french: 'Le plan de distribution a été confirmé',
    AppLanguage.english: 'The distribution plan was confirmed',
  },
};
