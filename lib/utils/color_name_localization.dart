import '../settings/app_settings.dart';

/// Catalogue colour names are data typed by the workshop, most often in
/// Arabic ("الأبيض", "أسود مطفي"). Shown to the user they follow the chosen
/// language: each known word is translated, an unknown name is kept as typed.
String localizedColorName(Object? raw, AppLanguage lang) {
  final text = (raw ?? '').toString().trim();
  // In Arabic the name stays as the workshop typed it.
  if (text.isEmpty || text == '-' || lang == AppLanguage.arabic) return text;

  final words = text
      .split(RegExp(r'[\s_\-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  final translated = <_ColorWord>[];
  for (final word in words) {
    final entry = _colorWords[_normalize(word)];
    // A name with any unknown word is kept whole rather than half
    // translated.
    if (entry == null) return text;
    translated.add(entry);
  }
  final colors = translated.where((word) => !word.isModifier);
  final modifiers = translated.where((word) => word.isModifier);
  return switch (lang) {
    // French and Arabic put the modifier after the colour ("Blanc mat");
    // English before it ("Matte White").
    AppLanguage.french => [
      ...colors.map((word) => word.french),
      ...modifiers.map((word) => word.french),
    ].join(' '),
    _ => [
      ...modifiers.map((word) => word.english),
      ...colors.map((word) => word.english),
    ].join(' '),
  };
}

/// Lower case, without the Arabic article and the letter variants, so
/// "الأبيض", "ابيض" and "Blanc" find the same entry.
String _normalize(String word) {
  var value = word
      .toLowerCase()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ç', 'c');
  if (value.startsWith('ال') && value.length > 3) value = value.substring(2);
  return value;
}

class _ColorWord {
  const _ColorWord(
    this.arabic,
    this.french,
    this.english, {
    this.isModifier = false,
  });

  final String arabic;
  final String french;
  final String english;
  final bool isModifier;
}

const _white = _ColorWord('أبيض', 'Blanc', 'White');
const _black = _ColorWord('أسود', 'Noir', 'Black');
const _grey = _ColorWord('رمادي', 'Gris', 'Grey');
const _wood = _ColorWord('خشبي', 'Bois', 'Wood');
const _brown = _ColorWord('بني', 'Marron', 'Brown');
const _gold = _ColorWord('ذهبي', 'Doré', 'Gold');
const _silver = _ColorWord('فضي', 'Argent', 'Silver');
const _bronze = _ColorWord('برونزي', 'Bronze', 'Bronze');
const _anthracite = _ColorWord('أنتراسيت', 'Anthracite', 'Anthracite');
const _cream = _ColorWord('كريمي', 'Crème', 'Cream');
const _beige = _ColorWord('بيج', 'Beige', 'Beige');
const _red = _ColorWord('أحمر', 'Rouge', 'Red');
const _blue = _ColorWord('أزرق', 'Bleu', 'Blue');
const _green = _ColorWord('أخضر', 'Vert', 'Green');
const _yellow = _ColorWord('أصفر', 'Jaune', 'Yellow');
const _orange = _ColorWord('برتقالي', 'Orange', 'Orange');
const _champagne = _ColorWord('شمبانيا', 'Champagne', 'Champagne');
const _chrome = _ColorWord('كروم', 'Chromé', 'Chrome');
const _copper = _ColorWord('نحاسي', 'Cuivre', 'Copper');
const _inox = _ColorWord('إينوكس', 'Inox', 'Stainless');
const _matte = _ColorWord('مطفي', 'mat', 'Matte', isModifier: true);
const _glossy = _ColorWord('لامع', 'brillant', 'Glossy', isModifier: true);
const _natural = _ColorWord('طبيعي', 'naturel', 'Natural', isModifier: true);
const _raw = _ColorWord('خام', 'brut', 'Raw', isModifier: true);
const _light = _ColorWord('فاتح', 'clair', 'Light', isModifier: true);
const _dark = _ColorWord('غامق', 'foncé', 'Dark', isModifier: true);
const _brushed = _ColorWord('مصقول', 'brossé', 'Brushed', isModifier: true);
const _metallic = _ColorWord(
  'ميتاليك',
  'métallisé',
  'Metallic',
  isModifier: true,
);
const _anodized = _ColorWord('أنودايز', 'anodisé', 'Anodized', isModifier: true);
const _textured = _ColorWord('محبب', 'sablé', 'Textured', isModifier: true);

final Map<String, _ColorWord> _colorWords = {
  for (final entry in <(List<String>, _ColorWord)>[
    (['ابيض', 'بيضاء', 'white', 'blanc', 'blanche'], _white),
    (['اسود', 'سوداء', 'black', 'noir', 'noire'], _black),
    (['رمادي', 'رماديه', 'grey', 'gray', 'gris', 'grise'], _grey),
    (['خشبي', 'خشب', 'wood', 'bois'], _wood),
    (['بني', 'بنيه', 'brown', 'marron'], _brown),
    (['ذهبي', 'ذهبيه', 'gold', 'golden', 'dore', 'doree'], _gold),
    (['فضي', 'فضيه', 'silver', 'argent', 'argente'], _silver),
    (['برونزي', 'برونز', 'bronze'], _bronze),
    (['انتراسيت', 'انطراسيت', 'anthracite'], _anthracite),
    (['كريمي', 'كريم', 'cream', 'creme'], _cream),
    (['بيج', 'beige'], _beige),
    (['احمر', 'حمراء', 'red', 'rouge'], _red),
    (['ازرق', 'زرقاء', 'blue', 'bleu'], _blue),
    (['اخضر', 'خضراء', 'green', 'vert', 'verte'], _green),
    (['اصفر', 'صفراء', 'yellow', 'jaune'], _yellow),
    (['برتقالي', 'orange'], _orange),
    (['شمبانيا', 'شامبانيا', 'champagne'], _champagne),
    (['كروم', 'كرومي', 'chrome', 'chromed'], _chrome),
    (['نحاسي', 'نحاس', 'copper', 'cuivre'], _copper),
    (['اينوكس', 'انوكس', 'inox', 'stainless'], _inox),
    (['مطفي', 'مطفيه', 'مات', 'matte', 'matt', 'mat', 'mate'], _matte),
    (['لامع', 'لامعه', 'glossy', 'brillant', 'brillante'], _glossy),
    (['طبيعي', 'natural', 'naturel', 'naturelle'], _natural),
    (['خام', 'raw', 'brut', 'brute'], _raw),
    (['فاتح', 'light', 'clair', 'claire'], _light),
    (['غامق', 'dark', 'fonce', 'foncee'], _dark),
    (['مصقول', 'brushed', 'brosse'], _brushed),
    (['ميتاليك', 'metallic', 'metallise'], _metallic),
    (['انودايز', 'انوديز', 'anodized', 'anodise'], _anodized),
    (['محبب', 'textured', 'sable'], _textured),
  ])
    for (final key in entry.$1) _normalize(key): entry.$2,
};
