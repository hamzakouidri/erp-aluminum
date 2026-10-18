import 'app_settings.dart';
import 'locales/subscription_status_keys.dart';
import 'locales/shortcut_keys.dart';
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
import 'locales/translation_phase11_keys.dart';
import 'locales/translation_phase12_keys.dart';
import 'locales/audit_log_keys.dart';
import 'locales/dashboard_activity_keys.dart';
import 'locales/drawing_validation_keys.dart';
import 'locales/window_3d_keys.dart';
import 'locales/product_movement_keys.dart';
import 'locales/glazing_fit_keys.dart';
import 'locales/ai_agent_keys.dart';
import 'locales/system_publication_keys.dart';
import 'locales/moustiquaire_price_keys.dart';

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
    ...translationPhase11Keys,
    ...translationPhase12Keys,
    ...productMovementKeys,
    ...glazingFitKeys,
    ...window3dKeys,
    ...aiAgentKeys,
    ...systemPublicationKeys,
    ...moustiquairePriceKeys,
    ...shortcutKeys,
    ...subscriptionStatusKeys,
    ...auditLogKeys,
    ...dashboardActivityKeys,
    ...drawingValidationKeys,
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

    // Intercept dynamic frame junctions: "بين الإطار X و Y" / "Entre cadre X et Y" / "Between frame X and Y"
    final junctionMatch = RegExp(
      r'^(?:بين الإطار|Entre cadre|Between frame)\s+(\d+)\s+(?:و|et|and)\s+(\d+)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (junctionMatch != null) {
      final f1 = junctionMatch.group(1)!;
      final f2 = junctionMatch.group(2)!;
      switch (lang) {
        case AppLanguage.french:
          return 'Entre cadre $f1 et $f2';
        case AppLanguage.english:
          return 'Between frame $f1 and $f2';
        case AppLanguage.arabic:
          return 'بين الإطار $f1 و $f2';
      }
    }

    // Intercept dynamic shutter box splits: "فصل الصناديق (X)" / "Séparation des caissons (X)" / "Split shutter boxes (X)"
    final shutterSplitMatch = RegExp(
      r'^(?:فصل الصناديق|Séparation des caissons|Split Caissons|Split shutter boxes)\s*\(([0-9]+)\)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (shutterSplitMatch != null) {
      final count = shutterSplitMatch.group(1)!;
      switch (lang) {
        case AppLanguage.french:
          return 'Séparation des caissons ($count)';
        case AppLanguage.english:
          return 'Split shutter boxes ($count)';
        case AppLanguage.arabic:
          return 'فصل الصناديق ($count)';
      }
    }

    // Intercept dynamic profile lengths: "طول القطاع: X مم" / "Longueur : X mm" / "Length: X mm"
    final lengthMatch = RegExp(
      r'^(?:طول القطاع|Longueur|Length)\s*:\s*([\d.,]+)\s*(?:مم|mm)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (lengthMatch != null) {
      final val = lengthMatch.group(1)!;
      switch (lang) {
        case AppLanguage.french:
          return 'Longueur : $val mm';
        case AppLanguage.english:
          return 'Length: $val mm';
        case AppLanguage.arabic:
          return 'طول القطاع: $val مم';
      }
    }

    // Intercept dynamic shutter moustiquaire dialog content:
    // "تم العثور على X نافذة تحتوي على ستار. اختر إضافة الموستيكير إليها كلها أو حذفها منها."
    final moustiquaireDialogMatch = RegExp(
      r'^(?:تم العثور على|Trouvé)\s*(\d+)\s*(?:نافذة تحتوي على ستار\.\s*اختر إضافة الموستيكير إليها كلها أو حذفها منها\.|fenêtre\(s\)? avec store\..*)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (moustiquaireDialogMatch != null) {
      final count = moustiquaireDialogMatch.group(1)!;
      switch (lang) {
        case AppLanguage.french:
          return '$count fenêtre(s) avec store trouvée(s). Choisissez d\'ajouter la moustiquaire à toutes ou de la supprimer.';
        case AppLanguage.english:
          return '$count window(s) with shutters found. Choose to add flyscreen to all or remove it.';
        case AppLanguage.arabic:
          return 'تم العثور على $count نافذة تحتوي على ستار. اختر إضافة الموستيكير إليها كلها أو حذفها منها.';
      }
    }

    // Intercept dynamic shutter moustiquaire result message:
    final moustiquaireAddedMatch = RegExp(
      r'^(?:تمت إضافة الموستيكير إلى)\s*(\d+)\s*(?:نافذة وإعادة حساب أسعارها\.)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (moustiquaireAddedMatch != null) {
      final count = moustiquaireAddedMatch.group(1)!;
      switch (lang) {
        case AppLanguage.french:
          return 'Moustiquaire ajoutée à $count fenêtre(s) et prix recalculés.';
        case AppLanguage.english:
          return 'Flyscreen added to $count window(s) and prices recalculated.';
        case AppLanguage.arabic:
          return 'تمت إضافة الموستيكير إلى $count نافذة وإعادة حساب أسعارها.';
      }
    }

    final moustiquaireRemovedMatch = RegExp(
      r'^(?:تم حذف الموستيكير من)\s*(\d+)\s*(?:نافذة وإعادة حساب أسعارها\.)$',
      caseSensitive: false,
    ).firstMatch(trimmedKey);
    if (moustiquaireRemovedMatch != null) {
      final count = moustiquaireRemovedMatch.group(1)!;
      switch (lang) {
        case AppLanguage.french:
          return 'Moustiquaire supprimée de $count fenêtre(s) et prix recalculés.';
        case AppLanguage.english:
          return 'Flyscreen removed from $count window(s) and prices recalculated.';
        case AppLanguage.arabic:
          return 'تم حذف الموستيكير من $count نافذة وإعادة حساب أسعارها.';
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
