import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'app_settings.dart';
import '../utils/color_name_localization.dart';

class Localization {
  /// Translations by key, then language. Filled from `assets/i18n/<code>.json`
  /// by [load] before the first frame; a key absent from a language's file
  /// has no entry for that language.
  static final Map<String, Map<AppLanguage, String>> _dictionary = {};

  static final Map<AppLanguage, Future<void>> _languageLoads = {};

  /// Loads the built-in languages from the asset bundle. Safe to call again.
  ///
  /// With [first], only that language is awaited: the three files weigh more
  /// than 1 MB and decoding all of them before `runApp` kept a cold-started
  /// phone on the launch icon. The other languages are then decoded on a
  /// separate isolate, so the UI thread stays free.
  static Future<void> load({AssetBundle? bundle, AppLanguage? first}) async {
    if (first == null) {
      await Future.wait(
        AppLanguage.builtIn.map((l) => ensureLanguage(l, bundle: bundle)),
      );
      return;
    }
    await ensureLanguage(first, bundle: bundle, inBackground: false);
    for (final lang in AppLanguage.builtIn) {
      unawaited(ensureLanguage(lang, bundle: bundle));
    }
  }

  /// Loads [lang] once; later calls return the same pending load. A pack
  /// language is loaded with its pack ([loadJson]); only its fallback comes
  /// from the assets.
  static Future<void> ensureLanguage(
    AppLanguage lang, {
    AssetBundle? bundle,
    bool inBackground = true,
  }) {
    if (!lang.isBuiltIn) {
      return ensureLanguage(
        lang.fallback,
        bundle: bundle,
        inBackground: inBackground,
      );
    }
    // A new completed future each time: one made in another zone (such as
    // a test's fake clock) would never complete in the caller's zone.
    if (_loadedLanguages.contains(lang)) return Future.value();
    return _languageLoads[lang] ??= () async {
      final source = await (bundle ?? rootBundle).loadString(
        'assets/i18n/${lang.code}.json',
      );
      if (inBackground) {
        _addStrings(lang, await compute(_decodeStrings, source));
      } else {
        loadJson(lang, source);
      }
    }();
  }

  static Map<String, dynamic> _decodeStrings(String source) =>
      (jsonDecode(source) as Map<String, dynamic>)['strings']
          as Map<String, dynamic>;

  /// Adds the `strings` of a language file (`{"meta": …, "strings": …}`).
  /// A built-in language loaded this way is not read again from the assets.
  static void loadJson(AppLanguage lang, String source) {
    _addStrings(lang, _decodeStrings(source));
    _loadedLanguages.add(lang);
  }

  /// Languages already given their texts by [loadJson].
  static final Set<AppLanguage> _loadedLanguages = {};

  static void _addStrings(AppLanguage lang, Map<String, dynamic> strings) {
    for (final entry in strings.entries) {
      (_dictionary[entry.key] ??= {})[lang] = entry.value as String;
    }
  }

  /// Every key known to at least one language.
  static Iterable<String> get keys => _dictionary.keys;

  /// The text stored for [key] in [lang], without any fallback.
  static String? stored(String key, AppLanguage lang) =>
      _dictionary[key]?[lang];

  /// The pack text for [key], found as stored or trimmed (keeping the
  /// caller's spacing around it); null when the pack lacks it or left it
  /// empty.
  static String? _packText(String key, AppLanguage lang) {
    final exact = _dictionary[key]?[lang];
    if (exact != null && exact.trim().isNotEmpty) return exact;
    final trimmed = key.trim();
    final text = _dictionary[trimmed]?[lang]?.trim();
    if (text == null || text.isEmpty) return null;
    final start = key.indexOf(trimmed);
    return '${key.substring(0, start)}$text'
        '${key.substring(start + trimmed.length)}';
  }

  static String translate(String key, AppLanguage lang) {
    // A pack language has its own texts only; everything else, including
    // the dynamic patterns below, comes from its built-in fallback.
    if (!lang.isBuiltIn) {
      return _packText(key, lang) ?? translate(key, lang.fallback);
    }
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

    // A key stored with its surrounding spaces ('الحالة: ') is found as
    // it is; otherwise the trimmed key keeps the caller's spacing around
    // its translation. Looking up only the trimmed key left every key that
    // ends with a space untranslated.
    final exact = _dictionary[key]?[lang];
    if (exact != null && exact.trim().isNotEmpty) return exact;
    if (_dictionary.containsKey(trimmedKey) &&
        _dictionary[trimmedKey]!.containsKey(lang)) {
      final translated = _dictionary[trimmedKey]![lang]!;
      if (translated.trim().isNotEmpty) {
        if (key == trimmedKey) return translated;
        final leading = key.substring(0, key.indexOf(trimmedKey));
        final trailing = key.substring(
          key.indexOf(trimmedKey) + trimmedKey.length,
        );
        return '$leading${translated.trim()}$trailing';
      }
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

    // Catalogue colour names ("الأبيض", "أسود مطفي") are data, not keys.
    final color = localizedColorName(key, lang);
    if (color != key) return color;

    return key; // Fallback to key if not found
  }

  /// A colour name from the catalogue (stored in Arabic, sometimes as
  /// "عربي (Latin)") in [lang]. Unknown names fall back to their Latin part,
  /// then to the stored name.
  static String colorName(Object? name, AppLanguage lang) {
    final raw = (name ?? '').toString().trim();
    if (raw.isEmpty || lang == AppLanguage.arabic) return raw;
    final translated = translate(raw, lang);
    if (translated != raw) return translated;
    final latin = RegExp(r'\(([^()]*[A-Za-z][^()]*)\)').firstMatch(raw);
    if (latin != null && RegExp(r'[\u0600-\u06FF]').hasMatch(raw)) {
      return latin.group(1)!.trim();
    }
    return raw;
  }
}
