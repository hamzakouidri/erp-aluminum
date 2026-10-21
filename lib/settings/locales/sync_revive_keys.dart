import '../app_settings.dart';

/// Labels of the settings action that uploads again the rows of this device
/// that Supabase holds as deleted. Keys are namespaced with `sync_revive_`.
final Map<String, Map<AppLanguage, String>> syncReviveKeys = {
  'sync_revive_button': {
    AppLanguage.arabic: 'استرجاع السجلات المحذوفة على الخادم',
    AppLanguage.french: 'Restaurer les lignes supprimées sur le serveur',
    AppLanguage.english: 'Restore rows deleted on the server',
  },
  'sync_revive_checking': {
    AppLanguage.arabic: 'جاري مقارنة بيانات هذا الجهاز مع Supabase...',
    AppLanguage.french: 'Comparaison des données de cet appareil avec Supabase...',
    AppLanguage.english: 'Comparing this device’s data with Supabase...',
  },
  'sync_revive_none': {
    AppLanguage.arabic:
        'لا توجد على هذا الجهاز سجلات محذوفة على الخادم. لم يُرفع شيء.',
    AppLanguage.french:
        'Aucune ligne de cet appareil n’est supprimée sur le serveur. Rien n’a été envoyé.',
    AppLanguage.english:
        'No row of this device is deleted on the server. Nothing was sent.',
  },
  'sync_revive_title': {
    AppLanguage.arabic: 'سجلات موجودة هنا ومحذوفة على الخادم',
    AppLanguage.french: 'Lignes présentes ici mais supprimées sur le serveur',
    AppLanguage.english: 'Rows present here but deleted on the server',
  },
  'sync_revive_body': {
    AppLanguage.arabic:
        'هذه السجلات موجودة على هذا الجهاز، لكن Supabase يعتبرها محذوفة، فلا تصل إلى الأجهزة الأخرى. عند التأكيد تُؤخذ نسخة من قاعدة البيانات ثم تُرفع هذه السجلات لتعود إلى كل الأجهزة. لا يُحذف أي شيء.',
    AppLanguage.french:
        'Ces lignes existent sur cet appareil, mais Supabase les considère supprimées : les autres appareils ne les reçoivent pas. Après confirmation, la base est copiée puis ces lignes sont envoyées pour revenir sur tous les appareils. Rien n’est supprimé.',
    AppLanguage.english:
        'These rows exist on this device, but Supabase holds them as deleted, so other devices never get them. On confirmation the database is copied, then these rows are uploaded so they return on every device. Nothing is deleted.',
  },
  'sync_revive_confirm': {
    AppLanguage.arabic: 'استرجاعها لكل الأجهزة',
    AppLanguage.french: 'Les restaurer partout',
    AppLanguage.english: 'Restore them everywhere',
  },
  'sync_revive_cancel': {
    AppLanguage.arabic: 'إلغاء',
    AppLanguage.french: 'Annuler',
    AppLanguage.english: 'Cancel',
  },
  'sync_revive_done': {
    AppLanguage.arabic: 'تم استرجاع السجلات على الخادم',
    AppLanguage.french: 'Lignes restaurées sur le serveur',
    AppLanguage.english: 'Rows restored on the server',
  },
  'sync_revive_failed': {
    AppLanguage.arabic: 'تعذر استرجاع السجلات',
    AppLanguage.french: 'Échec de la restauration des lignes',
    AppLanguage.english: 'Could not restore the rows',
  },
};
