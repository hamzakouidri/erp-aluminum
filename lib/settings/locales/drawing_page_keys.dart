import '../app_settings.dart';

/// Messages of the drawing page: going back from a shutter drawing to a
/// window, and the handle-height dialog. Keys are namespaced so they never
/// override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> drawingPageKeys = {
  'shutter_toggle_back_to_window': {
    AppLanguage.arabic: 'تمت إعادة الرسم إلى نافذة',
    AppLanguage.french: 'Le dessin est revenu à une fenêtre',
    AppLanguage.english: 'The drawing is back to a window',
  },
  'handle_height_from_sash_bottom': {
    AppLanguage.arabic: 'المسافة من أسفل الضلفة إلى المقبض',
    AppLanguage.french: 'Distance du bas de l’ouvrant à la poignée',
    AppLanguage.english: 'Distance from the sash bottom to the handle',
  },
};
