import '../app_settings.dart';

/// Texts of the installation (labour) prices, kept apart from part prices.
const Map<String, Map<AppLanguage, String>> installationPriceKeys = {
  'أجور التركيب': {
    AppLanguage.arabic: 'أجور التركيب',
    AppLanguage.french: 'Prix de pose',
    AppLanguage.english: 'Installation fees',
  },
  'أجور التركيب:': {
    AppLanguage.arabic: 'أجور التركيب:',
    AppLanguage.french: 'Prix de pose :',
    AppLanguage.english: 'Installation fees:',
  },
  'منها أجور التركيب': {
    AppLanguage.arabic: 'منها أجور التركيب',
    AppLanguage.french: 'Dont pose',
    AppLanguage.english: 'Including installation',
  },
  'سعر الموستيكير:': {
    AppLanguage.arabic: 'سعر الموستيكير:',
    AppLanguage.french: 'Prix moustiquaire :',
    AppLanguage.english: 'Mosquito net price:',
  },
  'تركيب الستار': {
    AppLanguage.arabic: 'تركيب الستار',
    AppLanguage.french: 'Pose du volet',
    AppLanguage.english: 'Shutter installation',
  },
  'تركيب المحرك': {
    AppLanguage.arabic: 'تركيب المحرك',
    AppLanguage.french: 'Pose du moteur',
    AppLanguage.english: 'Motor installation',
  },
  'تركيب المانيفال': {
    AppLanguage.arabic: 'تركيب المانيفال',
    AppLanguage.french: 'Pose du kit manivelle',
    AppLanguage.english: 'Crank kit installation',
  },
  'تركيب System OB': {
    AppLanguage.arabic: 'تركيب System OB',
    AppLanguage.french: 'Pose System OB',
    AppLanguage.english: 'System OB installation',
  },
  'تركيب Demi System OB': {
    AppLanguage.arabic: 'تركيب Demi System OB',
    AppLanguage.french: 'Pose Demi System OB',
    AppLanguage.english: 'Demi System OB installation',
  },
  'تركيب Verrou Central': {
    AppLanguage.arabic: 'تركيب Verrou Central',
    AppLanguage.french: 'Pose Verrou Central',
    AppLanguage.english: 'Verrou Central installation',
  },
  'لكل نافذة': {
    AppLanguage.arabic: 'لكل نافذة',
    AppLanguage.french: 'Par fenêtre',
    AppLanguage.english: 'Per window',
  },
  'لكل وحدة': {
    AppLanguage.arabic: 'لكل وحدة',
    AppLanguage.french: 'Par unité',
    AppLanguage.english: 'Per unit',
  },
  'لكل كيت': {
    AppLanguage.arabic: 'لكل كيت',
    AppLanguage.french: 'Par kit',
    AppLanguage.english: 'Per kit',
  },
  'احتساب أجور التركيب في السعر': {
    AppLanguage.arabic: 'احتساب أجور التركيب في السعر',
    AppLanguage.french: 'Inclure la pose dans le prix',
    AppLanguage.english: 'Include installation in the price',
  },
  'أجور التركيب منفصلة عن سعر القطع ولا يدخل عليها هامش الربح.': {
    AppLanguage.arabic:
        'أجور التركيب منفصلة عن سعر القطع ولا يدخل عليها هامش الربح.',
    AppLanguage.french:
        'La pose est séparée du prix des pièces et ne reçoit pas de marge.',
    AppLanguage.english:
        'Installation is separate from the part prices and gets no margin.',
  },
  'إظهار أجور التركيب في الديفي': {
    AppLanguage.arabic: 'إظهار أجور التركيب في الديفي',
    AppLanguage.french: 'Afficher la pose sur le devis',
    AppLanguage.english: 'Show installation on the quote',
  },
  'يظهر تحت كل نافذة سطر «منها أجور التركيب».': {
    AppLanguage.arabic: 'يظهر تحت كل نافذة سطر «منها أجور التركيب».',
    AppLanguage.french: 'Une ligne « Dont pose » sous chaque fenêtre.',
    AppLanguage.english: 'An “Including installation” line under each window.',
  },
  'بحث في أجور التركيب...': {
    AppLanguage.arabic: 'بحث في أجور التركيب...',
    AppLanguage.french: 'Rechercher dans les prix de pose...',
    AppLanguage.english: 'Search installation fees...',
  },
  'أجور التركيب العامة': {
    AppLanguage.arabic: 'أجور التركيب العامة',
    AppLanguage.french: 'Prix de pose généraux',
    AppLanguage.english: 'General installation fees',
  },
  'تركيب الكيتات': {
    AppLanguage.arabic: 'تركيب الكيتات',
    AppLanguage.french: 'Pose des kits',
    AppLanguage.english: 'Kit installation',
  },
  'تركيب مكوّنات الستار': {
    AppLanguage.arabic: 'تركيب مكوّنات الستار',
    AppLanguage.french: 'Pose des composants de volet',
    AppLanguage.english: 'Shutter component installation',
  },
  'تركيب الإكسسوارات': {
    AppLanguage.arabic: 'تركيب الإكسسوارات',
    AppLanguage.french: 'Pose des accessoires',
    AppLanguage.english: 'Accessory installation',
  },
  'أجور تركيب المحرك والمانيفال والكيتات أصبحت في تبويب «أجور التركيب» المستقل.':
      {
        AppLanguage.arabic:
            'أجور تركيب المحرك والمانيفال والكيتات أصبحت في تبويب «أجور التركيب» المستقل.',
        AppLanguage.french:
            'La pose du moteur, de la manivelle et des kits est dans l’onglet « Prix de pose ».',
        AppLanguage.english:
            'Motor, crank and kit installation fees are now in the “Installation fees” tab.',
      },
};
