import '../app_settings.dart';

/// Labels of the client account statement (chrono): workshop / store
/// scope, its tabs and the store lines. Keys are namespaced with
/// `client_ledger_`.
final Map<String, Map<AppLanguage, String>> clientLedgerKeys = {
  'client_ledger_scope_workshop': {
    AppLanguage.arabic: 'الورشة',
    AppLanguage.french: 'Atelier',
    AppLanguage.english: 'Workshop',
  },
  'client_ledger_scope_store': {
    AppLanguage.arabic: 'المحل',
    AppLanguage.french: 'Magasin',
    AppLanguage.english: 'Store',
  },
  'client_ledger_scope_both': {
    AppLanguage.arabic: 'الاثنان معاً',
    AppLanguage.french: 'Les deux',
    AppLanguage.english: 'Both',
  },
  'client_ledger_tab_statement': {
    AppLanguage.arabic: 'كشف الحساب',
    AppLanguage.french: 'Relevé',
    AppLanguage.english: 'Statement',
  },
  'client_ledger_tab_purchases': {
    AppLanguage.arabic: 'المشتريات',
    AppLanguage.french: 'Achats',
    AppLanguage.english: 'Purchases',
  },
  'client_ledger_tab_payments': {
    AppLanguage.arabic: 'الدفعات',
    AppLanguage.french: 'Paiements',
    AppLanguage.english: 'Payments',
  },
  'client_ledger_store_sale': {
    AppLanguage.arabic: 'بيع من المحل',
    AppLanguage.french: 'Vente magasin',
    AppLanguage.english: 'Store sale',
  },
  'client_ledger_store_return': {
    AppLanguage.arabic: 'مرتجع إلى المحل',
    AppLanguage.french: 'Retour magasin',
    AppLanguage.english: 'Store return',
  },
  'client_ledger_total_purchases': {
    AppLanguage.arabic: 'إجمالي المشتريات',
    AppLanguage.french: 'Total des achats',
    AppLanguage.english: 'Total purchases',
  },
};
