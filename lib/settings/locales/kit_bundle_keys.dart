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
  'الكونسول:': {
    AppLanguage.arabic: 'الكونسول:',
    AppLanguage.french: 'Console :',
    AppLanguage.english: 'Console:',
  },
  'كونسول ستاندار': {
    AppLanguage.arabic: 'كونسول ستاندار',
    AppLanguage.french: 'Console standard',
    AppLanguage.english: 'Standard console',
  },
  'كونسول سبيسيال': {
    AppLanguage.arabic: 'كونسول سبيسيال',
    AppLanguage.french: 'Console spéciale',
    AppLanguage.english: 'Special console',
  },
  'حسابات ستار النفق': {
    AppLanguage.arabic: 'حسابات ستار النفق',
    AppLanguage.french: 'Calculs du volet tunnel',
    AppLanguage.english: 'Tunnel shutter calculations',
  },
  'المحور = العرض − خصم الكونسول. الشفرة والشفرة النهائية = العرض − خصم الشفرة. عدد الشفرات = (الارتفاع − ارتفاع النفق + الإضافة) ÷ ارتفاع الشفرة + الشفرات الإضافية. السكة = الارتفاع + الإضافة، وجوان الفرشاة = طول السكك مرتين.': {
    AppLanguage.arabic:
        'المحور = العرض − خصم الكونسول. الشفرة والشفرة النهائية = العرض − خصم الشفرة. عدد الشفرات = (الارتفاع − ارتفاع النفق + الإضافة) ÷ ارتفاع الشفرة + الشفرات الإضافية. السكة = الارتفاع + الإضافة، وجوان الفرشاة = طول السكك مرتين.',
    AppLanguage.french:
        'Axe = largeur − déduction de la console. Lame et lame finale = largeur − déduction de la lame. Nombre de lames = (hauteur − hauteur du tunnel + ajout) ÷ hauteur de lame + lames supplémentaires. Coulisse = hauteur + ajout ; le joint brosse = deux fois la longueur des coulisses.',
    AppLanguage.english:
        'Axe = width − console deduction. Blade and final blade = width − blade deduction. Blades = (height − tunnel height + addition) ÷ blade height + extra blades. Rail = height + addition; the brush joint = twice the rails\' length.',
  },
  'خصم المحور مع كونسول ستاندار (مم)': {
    AppLanguage.arabic: 'خصم المحور مع كونسول ستاندار (مم)',
    AppLanguage.french: 'Déduction de l\'axe, console standard (mm)',
    AppLanguage.english: 'Axe deduction, standard console (mm)',
  },
  'خصم المحور مع كونسول سبيسيال (مم)': {
    AppLanguage.arabic: 'خصم المحور مع كونسول سبيسيال (مم)',
    AppLanguage.french: 'Déduction de l\'axe, console spéciale (mm)',
    AppLanguage.english: 'Axe deduction, special console (mm)',
  },
  'خصم طول الشفرة (مم)': {
    AppLanguage.arabic: 'خصم طول الشفرة (مم)',
    AppLanguage.french: 'Déduction de longueur de lame (mm)',
    AppLanguage.english: 'Blade length deduction (mm)',
  },
  'إضافة إلى الارتفاع لعدد الشفرات (مم)': {
    AppLanguage.arabic: 'إضافة إلى الارتفاع لعدد الشفرات (مم)',
    AppLanguage.french: 'Ajout à la hauteur pour le nombre de lames (mm)',
    AppLanguage.english: 'Height addition for the blade count (mm)',
  },
  'شفرات إضافية': {
    AppLanguage.arabic: 'شفرات إضافية',
    AppLanguage.french: 'Lames supplémentaires',
    AppLanguage.english: 'Extra blades',
  },
  'إضافة إلى طول السكة (مم)': {
    AppLanguage.arabic: 'إضافة إلى طول السكة (مم)',
    AppLanguage.french: 'Ajout à la longueur de coulisse (mm)',
    AppLanguage.english: 'Rail length addition (mm)',
  },
  'تم حفظ حسابات ستار النفق': {
    AppLanguage.arabic: 'تم حفظ حسابات ستار النفق',
    AppLanguage.french: 'Calculs du volet tunnel enregistrés',
    AppLanguage.english: 'Tunnel shutter calculations saved',
  },
  'عائلة:': {
    AppLanguage.arabic: 'عائلة:',
    AppLanguage.french: 'Famille :',
    AppLanguage.english: 'Family:',
  },
};
