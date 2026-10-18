import '../app_settings.dart';

/// Labels of the 3D window preview. Keys are namespaced with `window3d_` so
/// they never override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> window3dKeys = {
  'window3d_reset_view': {
    AppLanguage.arabic: 'إعادة ضبط المنظور',
    AppLanguage.french: 'Réinitialiser la vue',
    AppLanguage.english: 'Reset view',
  },
  'window3d_open': {
    AppLanguage.arabic: 'فتح الضلف',
    AppLanguage.french: 'Ouvrir les ouvrants',
    AppLanguage.english: 'Open the sashes',
  },
  'window3d_close': {
    AppLanguage.arabic: 'غلق الضلف',
    AppLanguage.french: 'Fermer les ouvrants',
    AppLanguage.english: 'Close the sashes',
  },
  'window3d_pause': {
    AppLanguage.arabic: 'إيقاف الحركة',
    AppLanguage.french: 'Arrêter l’animation',
    AppLanguage.english: 'Stop the animation',
  },
  'window3d_view_interior': {
    AppLanguage.arabic: 'الواجهة الداخلية',
    AppLanguage.french: 'Vue intérieure',
    AppLanguage.english: 'Interior view',
  },
  'window3d_view_exterior': {
    AppLanguage.arabic: 'الواجهة الخارجية',
    AppLanguage.french: 'Vue extérieure',
    AppLanguage.english: 'Exterior view',
  },
  'window3d_view_angle': {
    AppLanguage.arabic: 'منظور بزاوية',
    AppLanguage.french: 'Vue en perspective',
    AppLanguage.english: 'Angled view',
  },
  'window3d_zoom_in': {
    AppLanguage.arabic: 'تكبير',
    AppLanguage.french: 'Zoom avant',
    AppLanguage.english: 'Zoom in',
  },
  'window3d_zoom_out': {
    AppLanguage.arabic: 'تصغير',
    AppLanguage.french: 'Zoom arrière',
    AppLanguage.english: 'Zoom out',
  },
  'window3d_hint_mouse': {
    AppLanguage.arabic:
        'اسحب بالزر الأيسر للتدوير • بالزر الأيمن للتحريك • العجلة للتكبير • نقرتان لإعادة الضبط',
    AppLanguage.french:
        'Clic gauche glissé : pivoter • Clic droit : déplacer • Molette : zoom • Double-clic : réinitialiser',
    AppLanguage.english:
        'Left-drag: rotate • Right-drag: pan • Wheel: zoom • Double-click: reset',
  },
  'window3d_hint_touch': {
    AppLanguage.arabic:
        'اسحب بإصبع للتدوير • بإصبعين للتكبير والتحريك • نقرتان لإعادة الضبط',
    AppLanguage.french:
        'Un doigt : pivoter • Deux doigts : zoom et déplacement • Double tape : réinitialiser',
    AppLanguage.english:
        'One finger: rotate • Two fingers: zoom and pan • Double-tap: reset',
  },
};
