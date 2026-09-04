import 'app_settings.dart';
import 'locales/main_menu_keys.dart';
import 'locales/drawer_keys.dart';
import 'locales/product_keys.dart';
import 'locales/order_keys.dart';
import 'locales/general_keys.dart';
import 'locales/caisson_tunnel_keys.dart';
import 'locales/measurement_keys.dart';
import 'locales/recent_development_keys.dart';
import 'locales/app_wide_keys.dart';
import 'locales/translation_phase1_keys.dart';
import 'locales/translation_phase2_keys.dart';
import 'locales/translation_phase3_keys.dart';
import 'locales/translation_phase4_keys.dart';
import 'locales/translation_phase5_keys.dart';
import 'locales/translation_phase6_keys.dart';
import 'locales/translation_phase7_keys.dart';
import 'locales/translation_phase8_keys.dart';
import 'locales/translation_phase9_keys.dart';
import 'locales/translation_phase10_keys.dart';

class Localization {
  static final Map<String, Map<AppLanguage, String>> _dictionary = {
    ...mainMenuKeys,
    ...drawerKeys,
    ...productKeys,
    ...orderKeys,
    ...generalKeys,
    ...caissonTunnelKeys,
    ...measurementKeys,
    ...recentDevelopmentKeys,
    ...appWideKeys,
    ...translationPhase1Keys,
    ...translationPhase2Keys,
    ...translationPhase3Keys,
    ...translationPhase4Keys,
    ...translationPhase5Keys,
    ...translationPhase6Keys,
    ...translationPhase7Keys,
    ...translationPhase8Keys,
    ...translationPhase9Keys,
    ...translationPhase10Keys,
  };

  static String translate(String key, AppLanguage lang) {
    final trimmedKey = key.trim();

    // Intercept dynamic series names like "سلسلة 45" or "سلسله 45" or "سلسلة"
    if (lang != AppLanguage.arabic) {
      final seriesMatch = RegExp(
        r'^(سلسلة|سلسله)\s+(.+)$',
        caseSensitive: false,
      ).firstMatch(trimmedKey);
      if (seriesMatch != null) {
        final remainder = seriesMatch.group(2)!.trim();
        final translatedRemainder =
            _dictionary.containsKey(remainder) &&
                _dictionary[remainder]!.containsKey(lang)
            ? _dictionary[remainder]![lang]!
            : remainder;
        final prefix = lang == AppLanguage.french ? 'Gamme' : 'Series';
        return '$prefix $translatedRemainder';
      }
      if (trimmedKey == 'سلسلة' || trimmedKey == 'سلسله') {
        return lang == AppLanguage.french ? 'Gamme' : 'Series';
      }
    }

    if (_dictionary.containsKey(trimmedKey) &&
        _dictionary[trimmedKey]!.containsKey(lang)) {
      final translated = _dictionary[trimmedKey]![lang]!;
      if (translated.trim().isNotEmpty) return translated;
      final arabicFallback = _dictionary[trimmedKey]![AppLanguage.arabic];
      if (arabicFallback != null && arabicFallback.trim().isNotEmpty) {
        return arabicFallback;
      }
    }

    // Try parsing compound names with quality suffix like "Name (جودة ...)"
    final match = RegExp(
      r'^(.+?)\s*\(\s*(جودة\s+[^)]+)\s*\)$',
    ).firstMatch(trimmedKey);
    if (match != null) {
      final base = match.group(1)!.trim();
      final quality = match.group(2)!.trim();

      final translatedBase = translate(base, lang);
      final translatedQuality = translate(quality, lang);

      return '$translatedBase ($translatedQuality)';
    }

    return key; // Fallback to key if not found
  }
}
