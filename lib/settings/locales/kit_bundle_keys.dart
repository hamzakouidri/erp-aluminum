import '../app_settings.dart';

/// The kit page (kits, their families, components and ranges).
const Map<String, Map<AppLanguage, String>> kitBundleKeys = {
  'وزن الستار': {
    AppLanguage.arabic: 'وزن الستار',
    AppLanguage.french: 'Poids du volet',
    AppLanguage.english: 'Shutter weight',
  },
  'كل المحركات': {
    AppLanguage.arabic: 'كل المحركات',
    AppLanguage.french: 'Tous les moteurs',
    AppLanguage.english: 'All motors',
  },
  'محرك عادي': {
    AppLanguage.arabic: 'محرك عادي',
    AppLanguage.french: 'Moteur standard',
    AppLanguage.english: 'Standard motor',
  },
  'محرك مع مانيفال احتياطي': {
    AppLanguage.arabic: 'محرك مع مانيفال احتياطي',
    AppLanguage.french: 'Moteur avec manivelle de secours',
    AppLanguage.english: 'Motor with emergency crank',
  },
  'تعديل عائلة الكيت': {
    AppLanguage.arabic: 'تعديل عائلة الكيت',
    AppLanguage.french: 'Modifier la famille du kit',
    AppLanguage.english: 'Edit kit family',
  },
  'لا توجد مركبات أو عائلات بعد': {
    AppLanguage.arabic: 'لا توجد مركبات أو عائلات بعد',
    AppLanguage.french: 'Aucun composant ni famille pour le moment',
    AppLanguage.english: 'No components or families yet',
  },
  'لا توجد مركبات داخل هذه العائلة بعد': {
    AppLanguage.arabic: 'لا توجد مركبات داخل هذه العائلة بعد',
    AppLanguage.french: 'Aucun composant dans cette famille pour le moment',
    AppLanguage.english: 'No components in this family yet',
  },
  'لكل ضلفة': {
    AppLanguage.arabic: 'لكل ضلفة',
    AppLanguage.french: 'Par ouvrant',
    AppLanguage.english: 'Per sash',
  },
  'مرة واحدة داخل الكيت': {
    AppLanguage.arabic: 'مرة واحدة داخل الكيت',
    AppLanguage.french: 'Une seule fois dans le kit',
    AppLanguage.english: 'Once in the kit',
  },
  'كغ': {
    AppLanguage.arabic: 'كغ',
    AppLanguage.french: 'kg',
    AppLanguage.english: 'kg',
  },
  'مركّب:': {
    AppLanguage.arabic: 'مركّب:',
    AppLanguage.french: 'Composant :',
    AppLanguage.english: 'Component:',
  },
  'عائلة:': {
    AppLanguage.arabic: 'عائلة:',
    AppLanguage.french: 'Famille :',
    AppLanguage.english: 'Family:',
  },
};
