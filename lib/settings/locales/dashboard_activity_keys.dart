import '../app_settings.dart';

/// Labels of the dashboard "Recent activity" card. Keys are namespaced with
/// `dashboard_activity_` so they never override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> dashboardActivityKeys = {
  'dashboard_activity_title': {
    AppLanguage.arabic: 'آخر النشاطات',
    AppLanguage.french: 'Activités récentes',
    AppLanguage.english: 'Recent activity',
  },
  'dashboard_activity_subtitle': {
    AppLanguage.arabic:
        'آخر 12 عملية: طلبيات، زبائن، دفعات، مبيعات، مشتريات وتسليم',
    AppLanguage.french:
        'Les 12 dernières opérations : commandes, clients, paiements, ventes, achats et livraisons',
    AppLanguage.english:
        'Latest 12 orders, clients, payments, sales, purchases, and deliveries',
  },
  'dashboard_activity_empty': {
    AppLanguage.arabic: 'لا توجد نشاطات حديثة',
    AppLanguage.french: 'Aucune activité récente',
    AppLanguage.english: 'No recent activity',
  },
  'dashboard_activity_order_added': {
    AppLanguage.arabic: 'إضافة طلبية',
    AppLanguage.french: 'Commande ajoutée',
    AppLanguage.english: 'Order added',
  },
  'dashboard_activity_order_updated': {
    AppLanguage.arabic: 'تعديل طلبية',
    AppLanguage.french: 'Commande modifiée',
    AppLanguage.english: 'Order updated',
  },
  'dashboard_activity_order_opened': {
    AppLanguage.arabic: 'فتح طلبية',
    AppLanguage.french: 'Commande ouverte',
    AppLanguage.english: 'Order opened',
  },
  'dashboard_activity_delivery_added': {
    AppLanguage.arabic: 'إضافة وصل تسليم',
    AppLanguage.french: 'Bon de livraison ajouté',
    AppLanguage.english: 'Delivery note added',
  },
  'dashboard_activity_sale_added': {
    AppLanguage.arabic: 'إضافة بيع',
    AppLanguage.french: 'Vente ajoutée',
    AppLanguage.english: 'Sale added',
  },
  'dashboard_activity_sale_updated': {
    AppLanguage.arabic: 'تعديل بيع',
    AppLanguage.french: 'Vente modifiée',
    AppLanguage.english: 'Sale updated',
  },
  'dashboard_activity_purchase_added': {
    AppLanguage.arabic: 'إضافة شراء',
    AppLanguage.french: 'Achat ajouté',
    AppLanguage.english: 'Purchase added',
  },
  'dashboard_activity_purchase_updated': {
    AppLanguage.arabic: 'تعديل شراء',
    AppLanguage.french: 'Achat modifié',
    AppLanguage.english: 'Purchase updated',
  },
  'dashboard_activity_client_added': {
    AppLanguage.arabic: 'إضافة زبون',
    AppLanguage.french: 'Client ajouté',
    AppLanguage.english: 'Client added',
  },
  'dashboard_activity_client_updated': {
    AppLanguage.arabic: 'تعديل زبون',
    AppLanguage.french: 'Client modifié',
    AppLanguage.english: 'Client updated',
  },
  'dashboard_activity_payment_in': {
    AppLanguage.arabic: 'دفعة واردة',
    AppLanguage.french: 'Encaissement',
    AppLanguage.english: 'Payment received',
  },
  'dashboard_activity_payment_out': {
    AppLanguage.arabic: 'دفعة صادرة',
    AppLanguage.french: 'Décaissement',
    AppLanguage.english: 'Payment made',
  },
};
