import '../app_settings.dart';

/// Labels of the audit log tab (Trash screen). Keys are namespaced with
/// `audit_` so they never override generic words such as "حذف" elsewhere.
final Map<String, Map<AppLanguage, String>> auditLogKeys = {
  'audit_tab_title': {
    AppLanguage.arabic: 'سجل التدقيق والرقابة',
    AppLanguage.french: 'Journal d\'audit',
    AppLanguage.english: 'Audit log',
  },
  'audit_no_permission': {
    AppLanguage.arabic: 'ليس لديك صلاحية مشاهدة سجل التعديلات',
    AppLanguage.french:
        'Vous n\'avez pas l\'autorisation de consulter le journal des modifications',
    AppLanguage.english: 'You do not have permission to view the change log',
  },
  'audit_no_permission_hint': {
    AppLanguage.arabic:
        'هذا السجل متاح لمدير الورشة أو للعامل الذي منحه المدير صلاحية سجل التعديلات',
    AppLanguage.french:
        'Ce journal est réservé au gérant de l\'atelier ou à l\'employé ayant reçu l\'autorisation correspondante',
    AppLanguage.english:
        'This log is reserved for the workshop manager or a worker explicitly granted the change-log permission',
  },
  'audit_empty_title': {
    AppLanguage.arabic: 'لا توجد سجلات تدقيق',
    AppLanguage.french: 'Aucun journal d\'audit',
    AppLanguage.english: 'No audit entries',
  },
  'audit_empty_subtitle': {
    AppLanguage.arabic: 'يتم تسجيل أي حذف أو تعديل أو استرجاع هنا تلقائياً',
    AppLanguage.french:
        'Toutes les suppressions, modifications et restaurations sont enregistrées ici automatiquement',
    AppLanguage.english:
        'Every deletion, modification and restoration is recorded here automatically',
  },
  'audit_no_results': {
    AppLanguage.arabic: 'لا توجد نتائج مطابقة للبحث',
    AppLanguage.french: 'Aucun résultat ne correspond à la recherche',
    AppLanguage.english: 'No entries match your search',
  },
  'audit_showing_count': {
    AppLanguage.arabic: 'عرض {shown} من {total} سجل',
    AppLanguage.french: '{shown} sur {total} entrées affichées',
    AppLanguage.english: 'Showing {shown} of {total} entries',
  },
  'audit_load_more': {
    AppLanguage.arabic: 'تحميل المزيد',
    AppLanguage.french: 'Charger plus',
    AppLanguage.english: 'Load more',
  },
  'audit_action_delete': {
    AppLanguage.arabic: 'حذف',
    AppLanguage.french: 'Suppression',
    AppLanguage.english: 'Deletion',
  },
  'audit_action_restore': {
    AppLanguage.arabic: 'استرجاع',
    AppLanguage.french: 'Restauration',
    AppLanguage.english: 'Restoration',
  },
  'audit_action_update': {
    AppLanguage.arabic: 'تعديل',
    AppLanguage.french: 'Modification',
    AppLanguage.english: 'Modification',
  },
  'audit_action_confirm': {
    AppLanguage.arabic: 'تأكيد',
    AppLanguage.french: 'Confirmation',
    AppLanguage.english: 'Confirmation',
  },
  'audit_action_return': {
    AppLanguage.arabic: 'إرجاع',
    AppLanguage.french: 'Retour',
    AppLanguage.english: 'Return',
  },
  'audit_action_daily_close': {
    AppLanguage.arabic: 'إغلاق يومي',
    AppLanguage.french: 'Clôture journalière',
    AppLanguage.english: 'Daily closing',
  },
  'audit_action_other': {
    AppLanguage.arabic: 'إجراء',
    AppLanguage.french: 'Action',
    AppLanguage.english: 'Action',
  },
  'audit_entity_order': {
    AppLanguage.arabic: 'طلبية',
    AppLanguage.french: 'Commande',
    AppLanguage.english: 'Order',
  },
  'audit_entity_purchase': {
    AppLanguage.arabic: 'فاتورة شراء',
    AppLanguage.french: 'Facture d\'achat',
    AppLanguage.english: 'Purchase invoice',
  },
  'audit_entity_material_sale': {
    AppLanguage.arabic: 'وثيقة مبيعات المحل',
    AppLanguage.french: 'Vente magasin',
    AppLanguage.english: 'Store sale',
  },
  'audit_entity_store': {
    AppLanguage.arabic: 'المحل',
    AppLanguage.french: 'Magasin',
    AppLanguage.english: 'Store',
  },
  'audit_entity_workshop': {
    AppLanguage.arabic: 'الورشة',
    AppLanguage.french: 'Atelier',
    AppLanguage.english: 'Workshop',
  },
  'audit_entity_other': {
    AppLanguage.arabic: 'وثيقة',
    AppLanguage.french: 'Document',
    AppLanguage.english: 'Document',
  },
  'audit_unknown_user': {
    AppLanguage.arabic: 'مستخدم غير معروف',
    AppLanguage.french: 'Utilisateur inconnu',
    AppLanguage.english: 'Unknown user',
  },
  'audit_view_details': {
    AppLanguage.arabic: 'عرض تفاصيل التعديل',
    AppLanguage.french: 'Voir le détail de la modification',
    AppLanguage.english: 'View change details',
  },
  'audit_details_title': {
    AppLanguage.arabic: 'تفاصيل ما قبل وبعد التعديل',
    AppLanguage.french: 'Détail avant / après la modification',
    AppLanguage.english: 'Before / after details',
  },
  'audit_details_empty': {
    AppLanguage.arabic: 'لا توجد تفاصيل محفوظة لهذا السجل',
    AppLanguage.french: 'Aucun détail enregistré pour cette entrée',
    AppLanguage.english: 'No details were saved for this entry',
  },
  'audit_close': {
    AppLanguage.arabic: 'إغلاق',
    AppLanguage.french: 'Fermer',
    AppLanguage.english: 'Close',
  },
};
