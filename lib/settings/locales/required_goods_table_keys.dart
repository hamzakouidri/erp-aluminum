import '../app_settings.dart';

/// Labels of the required-goods table (colour column, column search fields)
/// and of its profile replacement. Keys are namespaced with
/// `required_goods_` so they never override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> requiredGoodsTableKeys = {
  'required_goods_color_column': {
    AppLanguage.arabic: 'اللون',
    AppLanguage.french: 'Couleur',
    AppLanguage.english: 'Colour',
  },
  'required_goods_search_category': {
    AppLanguage.arabic: 'بحث بالفئة...',
    AppLanguage.french: 'Catégorie...',
    AppLanguage.english: 'Category...',
  },
  'required_goods_search_name': {
    AppLanguage.arabic: 'بحث بالاسم أو الكود...',
    AppLanguage.french: 'Nom ou code...',
    AppLanguage.english: 'Name or code...',
  },
  'required_goods_search_details': {
    AppLanguage.arabic: 'بحث في التفاصيل...',
    AppLanguage.french: 'Détails...',
    AppLanguage.english: 'Details...',
  },
  'required_goods_search_color': {
    AppLanguage.arabic: 'بحث باللون...',
    AppLanguage.french: 'Couleur...',
    AppLanguage.english: 'Colour...',
  },
  'required_goods_clear_filters': {
    AppLanguage.arabic: 'مسح البحث',
    AppLanguage.french: 'Effacer les filtres',
    AppLanguage.english: 'Clear filters',
  },
  'required_goods_no_alternative': {
    AppLanguage.arabic: 'لا يوجد بديل متوافق لهذا القطاع في سلسلته.',
    AppLanguage.french:
        'Aucun profilé compatible de la même série pour remplacer celui-ci.',
    AppLanguage.english:
        'No compatible profile of the same series can replace this one.',
  },
  'required_goods_change_profile': {
    AppLanguage.arabic: 'تغيير القطاع',
    AppLanguage.french: 'Changer le profilé',
    AppLanguage.english: 'Change profile',
  },
};
