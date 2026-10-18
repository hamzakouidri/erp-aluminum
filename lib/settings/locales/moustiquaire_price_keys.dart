import '../app_settings.dart';

/// Texts of the mosquito-net prices by colour.
final Map<String, Map<AppLanguage, String>> moustiquairePriceKeys = {
  'سعر م² لهذا اللون': {
    AppLanguage.arabic: 'سعر م² لهذا اللون',
    AppLanguage.french: 'Prix au m² de cette couleur',
    AppLanguage.english: 'Price per m² for this colour',
  },
  '+ سعر حسب اللون': {
    AppLanguage.arabic: '+ سعر حسب اللون',
    AppLanguage.french: '+ Prix par couleur',
    AppLanguage.english: '+ Price by colour',
  },
};
