import '../app_settings.dart';

/// Phase 1 translations for the main list and table screens.
///
/// The Arabic text is intentionally kept as the key because the application
/// already uses the source text as its localization key.
const Map<String, Map<AppLanguage, String>> translationPhase1Keys = {
  'NIF / NIS...': {
    AppLanguage.arabic: 'NIF / NIS...',
    AppLanguage.french: 'NIF / NIS...',
    AppLanguage.english: 'NIF / NIS...',
  },
  'اسم الدافع...': {
    AppLanguage.arabic: 'اسم الدافع...',
    AppLanguage.french: 'Nom du payeur...',
    AppLanguage.english: 'Payer name...',
  },
};
