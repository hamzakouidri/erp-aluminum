import '../app_settings.dart';

/// Labels, label printers, barcode scanning, worker hand-over, stock counts
/// and remnant rules.
const Map<String, Map<AppLanguage, String>> workshopScanKeys = {
  'طابعة الملصقات': {
    AppLanguage.arabic: 'طابعة الملصقات',
    AppLanguage.french: 'Imprimante d\'étiquettes',
    AppLanguage.english: 'Label printer',
  },
  'طابعة النظام (PDF)': {
    AppLanguage.arabic: 'طابعة النظام (PDF)',
    AppLanguage.french: 'Imprimante système (PDF)',
    AppLanguage.english: 'System printer (PDF)',
  },
  'نافذة الطباعة العادية لأي طابعة': {
    AppLanguage.arabic: 'نافذة الطباعة العادية لأي طابعة',
    AppLanguage.french: 'Boîte d\'impression standard, pour toute imprimante',
    AppLanguage.english: 'The standard print dialog, for any printer',
  },
  'طابعة ملصقات حرارية (ZPL)': {
    AppLanguage.arabic: 'طابعة ملصقات حرارية (ZPL)',
    AppLanguage.french: 'Imprimante d\'étiquettes thermique (ZPL)',
    AppLanguage.english: 'Thermal label printer (ZPL)',
  },
  'طباعة مباشرة عبر الشبكة دون نافذة الطباعة': {
    AppLanguage.arabic: 'طباعة مباشرة عبر الشبكة دون نافذة الطباعة',
    AppLanguage.french:
        'Impression directe par le réseau, sans boîte d\'impression',
    AppLanguage.english: 'Prints straight over the network, no print dialog',
  },
  'عنوان IP للطابعة': {
    AppLanguage.arabic: 'عنوان IP للطابعة',
    AppLanguage.french: 'Adresse IP de l\'imprimante',
    AppLanguage.english: 'Printer IP address',
  },
  'منفذ الطابعة': {
    AppLanguage.arabic: 'منفذ الطابعة',
    AppLanguage.french: 'Port',
    AppLanguage.english: 'Port',
  },
  'دقة رأس الطباعة': {
    AppLanguage.arabic: 'دقة رأس الطباعة',
    AppLanguage.french: 'Résolution de la tête',
    AppLanguage.english: 'Print head resolution',
  },
  'طباعة ملصق تجريبي': {
    AppLanguage.arabic: 'طباعة ملصق تجريبي',
    AppLanguage.french: 'Imprimer une étiquette test',
    AppLanguage.english: 'Print a test label',
  },
  'تم إرسال الملصق التجريبي': {
    AppLanguage.arabic: 'تم إرسال الملصق التجريبي',
    AppLanguage.french: 'Étiquette test envoyée',
    AppLanguage.english: 'Test label sent',
  },
  'تعذر الاتصال بالطابعة': {
    AppLanguage.arabic: 'تعذر الاتصال بالطابعة',
    AppLanguage.french: 'Impossible de joindre l\'imprimante',
    AppLanguage.english: 'Could not reach the printer',
  },
  'ملصق لكل قطعة مقصوصة': {
    AppLanguage.arabic: 'ملصق لكل قطعة مقصوصة',
    AppLanguage.french: 'Une étiquette par pièce coupée',
    AppLanguage.english: 'A label for each cut piece',
  },
  'تم إرسال ملصقات القطع': {
    AppLanguage.arabic: 'تم إرسال ملصقات القطع',
    AppLanguage.french: 'Étiquettes des pièces envoyées',
    AppLanguage.english: 'Cut-piece labels sent',
  },
};
