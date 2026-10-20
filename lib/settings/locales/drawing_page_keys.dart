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
  'separate_shutter_belt_inside': {
    AppLanguage.arabic: 'الحزام: داخلي',
    AppLanguage.french: 'Sangle : intérieure',
    AppLanguage.english: 'Belt: inside',
  },
  'separate_shutter_belt_outside': {
    AppLanguage.arabic: 'الحزام: خارجي',
    AppLanguage.french: 'Sangle : extérieure',
    AppLanguage.english: 'Belt: outside',
  },
  'separate_shutter_belt_hint': {
    AppLanguage.arabic:
        'داخلي: بكرة في الإطار تُدخل الحزام إلى المنزل. خارجي: يبقى الحزام بين النافذة وسكك الستار.',
    AppLanguage.french:
        'Intérieure : une poulie dans le dormant fait entrer la sangle. Extérieure : la sangle reste entre la fenêtre et les coulisses.',
    AppLanguage.english:
        'Inside: a pulley in the frame brings the belt indoors. Outside: the belt stays between the window and the shutter rails.',
  },
  'بكرة الحزام الداخلية (Poulie sangle)': {
    AppLanguage.arabic: 'بكرة الحزام الداخلية',
    AppLanguage.french: 'Poulie de sangle intérieure',
    AppLanguage.english: 'Inside belt pulley',
  },
  'handle_height_from_sash_bottom': {
    AppLanguage.arabic: 'المسافة من أسفل الضلفة إلى المقبض',
    AppLanguage.french: 'Distance du bas de l’ouvrant à la poignée',
    AppLanguage.english: 'Distance from the sash bottom to the handle',
  },
};
