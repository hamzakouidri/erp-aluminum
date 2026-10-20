import '../app_settings.dart';

/// Messages of the recycle bin. Keys are namespaced with `trash_`.
final Map<String, Map<AppLanguage, String>> trashKeys = {
  'trash_confirm_empty_material_sales': {
    AppLanguage.arabic:
        'هل أنت متأكد من تفريغ سلة مبيعات المحل نهائياً؟ لا يمكن التراجع عن هذا الإجراء.',
    AppLanguage.french:
        'Vider définitivement la corbeille des ventes du magasin ? Cette action est irréversible.',
    AppLanguage.english:
        'Permanently empty the store sales bin? This cannot be undone.',
  },
  'audit_action_create': {
    AppLanguage.arabic: 'إنشاء',
    AppLanguage.french: 'Création',
    AppLanguage.english: 'Created',
  },
  'audit_action_status': {
    AppLanguage.arabic: 'تغيير المرحلة',
    AppLanguage.french: 'Changement d’étape',
    AppLanguage.english: 'Stage changed',
  },
  'audit_entity_client': {
    AppLanguage.arabic: 'زبون',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Client',
  },
  'audit_entity_payment': {
    AppLanguage.arabic: 'حركة صندوق',
    AppLanguage.french: 'Mouvement de caisse',
    AppLanguage.english: 'Cash movement',
  },
  'trash_material_sales_emptied': {
    AppLanguage.arabic: 'تم حذف {count} من مبيعات المحل نهائياً',
    AppLanguage.french: '{count} ventes du magasin supprimées définitivement',
    AppLanguage.english: '{count} store sales permanently deleted',
  },
};
