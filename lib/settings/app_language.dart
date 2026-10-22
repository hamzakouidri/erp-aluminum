/// An application language: one of the three built into the app, or one
/// installed from a downloaded language pack.
///
/// Instances are canonical — the built-in ones are constants and a pack
/// language is created once per code by [register] — so they compare by
/// identity and can be used as constant patterns in a `switch`. Code that
/// only knows the built-in languages handles a pack language in its
/// default branch, which gives the English text ([fallback]).
class AppLanguage {
  const AppLanguage._(
    this.code,
    this.name,
    this.nativeName, {
    this.isRtl = false,
    this.isBuiltIn = true,
  });

  /// ISO code, also the name of the language file (`assets/i18n/fr.json`).
  final String code;

  /// Stable English identifier (`arabic`, `french`, `english`, `spanish`…).
  final String name;

  /// The language's name written in that language.
  final String nativeName;

  /// Written right to left.
  final bool isRtl;

  /// Shipped with the app rather than downloaded.
  final bool isBuiltIn;

  static const arabic = AppLanguage._(
    'ar',
    'arabic',
    'العربية',
    isRtl: true,
  );
  static const french = AppLanguage._('fr', 'french', 'Français');
  static const english = AppLanguage._('en', 'english', 'English');

  /// The built-in languages, in the order of the former enum: older
  /// versions saved the language as its position in this list.
  static const builtIn = [arabic, french, english];

  static final Map<String, AppLanguage> _installed = {};

  /// The built-in languages followed by the installed packs.
  static List<AppLanguage> get values => [...builtIn, ..._installed.values];

  /// The language of an installed pack, created once per [code].
  static AppLanguage register({
    required String code,
    required String name,
    required String nativeName,
    bool isRtl = false,
  }) {
    final normalized = code.trim().toLowerCase();
    final existing = fromCode(normalized);
    if (existing != null) return existing;
    return _installed[normalized] = AppLanguage._(
      normalized,
      name,
      nativeName,
      isRtl: isRtl,
      isBuiltIn: false,
    );
  }

  /// Forgets a pack language after its pack was removed.
  static void unregister(AppLanguage language) {
    if (!language.isBuiltIn) _installed.remove(language.code);
  }

  /// The built-in or installed language with [code], if any.
  static AppLanguage? fromCode(String? code) {
    final normalized = code?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final language in builtIn) {
      if (language.code == normalized) return language;
    }
    return _installed[normalized];
  }

  /// The built-in language standing in for this one where a text or a rule
  /// exists only in the built-in languages: itself, or English for a pack.
  AppLanguage get fallback => isBuiltIn ? this : english;

  /// Position in [builtIn], saved by older versions; a pack language saves
  /// the position of its [fallback].
  int get index => builtIn.indexOf(fallback);

  @override
  String toString() => 'AppLanguage.$name';
}
