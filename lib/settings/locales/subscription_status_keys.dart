import '../app_settings.dart';

const subscriptionStatusKeys = <String, Map<AppLanguage, String>>{
  'نشط': {
    AppLanguage.arabic: 'نشط',
    AppLanguage.french: 'Actif',
    AppLanguage.english: 'Active',
  },
  'دائم': {
    AppLanguage.arabic: 'دائم',
    AppLanguage.french: 'Permanent',
    AppLanguage.english: 'Lifetime',
  },
  'منتهي': {
    AppLanguage.arabic: 'منتهي',
    AppLanguage.french: 'Expiré',
    AppLanguage.english: 'Expired',
  },
  'يقارب على الانتهاء': {
    AppLanguage.arabic: 'يقارب على الانتهاء',
    AppLanguage.french: 'Expire bientôt',
    AppLanguage.english: 'Expiring soon',
  },
  'دائم (مدير التطبيق)': {
    AppLanguage.arabic: 'دائم (مدير التطبيق)',
    AppLanguage.french: 'Permanent (administrateur)',
    AppLanguage.english: 'Lifetime (administrator)',
  },
  'منتهي الصلاحية': {
    AppLanguage.arabic: 'منتهي الصلاحية',
    AppLanguage.french: 'Expiré',
    AppLanguage.english: 'Expired',
  },
  'سارٍ ونشط': {
    AppLanguage.arabic: 'سارٍ ونشط',
    AppLanguage.french: 'Actif',
    AppLanguage.english: 'Active',
  },
  'يوم': {
    AppLanguage.arabic: 'يوم',
    AppLanguage.french: 'jour(s)',
    AppLanguage.english: 'day(s)',
  },
  'نعم، امسح': {
    AppLanguage.arabic: 'نعم، امسح',
    AppLanguage.french: 'Oui, effacer',
    AppLanguage.english: 'Yes, clear',
  },
  'هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟': {
    AppLanguage.arabic:
        'هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟',
    AppLanguage.french: 'Voulez-vous effacer tout le dessin et recommencer ?',
    AppLanguage.english: 'Clear the entire drawing and start again?',
  },
  'مراجعة وتجديد الاشتراك': {
    AppLanguage.arabic: 'مراجعة وتجديد الاشتراك',
    AppLanguage.french: 'Consulter et renouveler l’abonnement',
    AppLanguage.english: 'Review and renew subscription',
  },
  'مراجعة تفاصيل الاشتراك': {
    AppLanguage.arabic: 'مراجعة تفاصيل الاشتراك',
    AppLanguage.french: 'Consulter l’abonnement',
    AppLanguage.english: 'Review subscription details',
  },
};
