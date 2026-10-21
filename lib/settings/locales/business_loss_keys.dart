import '../app_settings.dart';

/// Labels of the prompt shown when a download would delete many local
/// clients, orders or treasury rows. Keys are namespaced with
/// `business_loss_` so they never override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> businessLossKeys = {
  'business_loss_title': {
    AppLanguage.arabic: 'حذف كبير لبيانات الورشة',
    AppLanguage.french: 'Suppression importante des données de l’atelier',
    AppLanguage.english: 'Large deletion of workshop data',
  },
  'business_loss_body': {
    AppLanguage.arabic:
        'وصلت من السيرفر عمليات حذف ستمسح عدداً كبيراً من الزبائن أو الطلبيات أو حركات الصندوق من هذا الجهاز. لم يُحذف شيء بعد. اختر ما تريد:',
    AppLanguage.french:
        'Le serveur a envoyé des suppressions qui effaceraient beaucoup de clients, de commandes ou de mouvements de caisse sur cet appareil. Rien n’a encore été supprimé. Choisissez :',
    AppLanguage.english:
        'The server sent deletions that would erase many clients, orders or treasury entries on this device. Nothing has been deleted yet. Choose:',
  },
  'business_loss_local': {
    AppLanguage.arabic: 'على الجهاز',
    AppLanguage.french: 'Sur l’appareil',
    AppLanguage.english: 'On device',
  },
  'business_loss_lost': {
    AppLanguage.arabic: 'سيُحذف',
    AppLanguage.french: 'À supprimer',
    AppLanguage.english: 'To delete',
  },
  'business_loss_table_Client': {
    AppLanguage.arabic: 'الزبائن',
    AppLanguage.french: 'Clients',
    AppLanguage.english: 'Clients',
  },
  'business_loss_table_Commandes': {
    AppLanguage.arabic: 'الطلبيات',
    AppLanguage.french: 'Commandes',
    AppLanguage.english: 'Orders',
  },
  'business_loss_table_Treasury': {
    AppLanguage.arabic: 'حركات الصندوق',
    AppLanguage.french: 'Mouvements de caisse',
    AppLanguage.english: 'Treasury entries',
  },
  'business_loss_keep_local': {
    AppLanguage.arabic: 'الاحتفاظ ببيانات الجهاز',
    AppLanguage.french: 'Garder les données de l’appareil',
    AppLanguage.english: 'Keep this device’s data',
  },
  'business_loss_apply_remote': {
    AppLanguage.arabic: 'تطبيق الحذف',
    AppLanguage.french: 'Appliquer la suppression',
    AppLanguage.english: 'Apply the deletion',
  },
  'business_loss_later': {
    AppLanguage.arabic: 'لاحقاً',
    AppLanguage.french: 'Plus tard',
    AppLanguage.english: 'Later',
  },
  'business_loss_kept_local': {
    AppLanguage.arabic: 'تم الاحتفاظ ببيانات الجهاز وإعادة رفعها إلى السيرفر.',
    AppLanguage.french:
        'Les données de l’appareil sont conservées et renvoyées au serveur.',
    AppLanguage.english:
        'This device’s data was kept and uploaded to the server again.',
  },
  'business_loss_applied_remote': {
    AppLanguage.arabic: 'تم تطبيق الحذف القادم من السيرفر.',
    AppLanguage.french: 'La suppression venant du serveur a été appliquée.',
    AppLanguage.english: 'The deletion from the server was applied.',
  },
  'business_loss_failed': {
    AppLanguage.arabic: 'تعذرت العملية',
    AppLanguage.french: 'L’opération a échoué',
    AppLanguage.english: 'The operation failed',
  },
};
