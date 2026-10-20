import '../app_settings.dart';

/// Labels of the parclose corner caps (plastic bouchons covering the corners
/// of a parclose cut at 90°). Keys are namespaced with `parclose_corner_`,
/// except the BOM row name which is translated by its Arabic label.
final Map<String, Map<AppLanguage, String>> parcloseCornerCapKeys = {
  'parclose_corner_caps_title': {
    AppLanguage.arabic: 'بوشونات زوايا الباركلوز',
    AppLanguage.french: 'Bouchons d’angle de parclose',
    AppLanguage.english: 'Parclose corner caps',
  },
  'parclose_corner_caps_hint': {
    AppLanguage.arabic:
        'بوشون بلاستيكي يغطي كل زاوية تلتقي فيها قطعتا الباركلوز المقطوعتان 90°، ويُحسب في الكمية والتكلفة.',
    AppLanguage.french:
        'Un bouchon plastique couvre chaque angle où deux parcloses coupées à 90° se rencontrent ; il est compté dans les quantités.',
    AppLanguage.english:
        'A plastic cap covers each corner where two parclose pieces cut at 90° meet; it is counted in the quantities.',
  },
  'بوشون زاوية الباركلوز (Bouchon parclose)': {
    AppLanguage.arabic: 'بوشون زاوية الباركلوز',
    AppLanguage.french: 'Bouchon d’angle parclose',
    AppLanguage.english: 'Parclose corner cap',
  },
};
