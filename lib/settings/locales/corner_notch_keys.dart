import '../app_settings.dart';

/// Corner cuts (90° steps) of the drawing page. Keys are namespaced with
/// `notch_`.
final Map<String, Map<AppLanguage, String>> cornerNotchKeys = {
  'notch_button': {
    AppLanguage.arabic: 'زاوية مقطوعة',
    AppLanguage.french: 'Angle découpé',
    AppLanguage.english: 'Cut corner',
  },
  'notch_hint': {
    AppLanguage.arabic:
        'اسحب مربع الزاوية نحو الداخل لقطعها، وانقر على أي قياس لتعديله. أعده إلى الزاوية لإلغاء القطع.',
    AppLanguage.french:
        'Glissez le carré d’un angle vers l’intérieur pour le découper ; touchez une cote pour la modifier. Ramenez-le à l’angle pour annuler la découpe.',
    AppLanguage.english:
        'Drag a corner square inward to cut it; tap a length to edit it. Drag it back to the corner to remove the cut.',
  },
  'notch_side_length': {
    AppLanguage.arabic: 'طول الضلع',
    AppLanguage.french: 'Longueur du côté',
    AppLanguage.english: 'Side length',
  },
  'notch_min_hint': {
    AppLanguage.arabic: 'لا يقل أي ضلع عن 80 مم',
    AppLanguage.french: 'Aucun côté sous 80 mm',
    AppLanguage.english: 'No side under 80 mm',
  },
  'notch_full_side_hint': {
    AppLanguage.arabic: 'هذا ضلع كامل: عدّله من العرض أو الارتفاع العام.',
    AppLanguage.french:
        'Côté complet : modifiez-le par la largeur ou la hauteur totale.',
    AppLanguage.english:
        'A full side: change it with the overall width or height.',
  },
  'notch_single_frame_only': {
    AppLanguage.arabic: 'قطع الزاوية متاح لنافذة بإطار واحد فقط.',
    AppLanguage.french: 'La découpe d’angle est réservée à un seul cadre.',
    AppLanguage.english: 'A cut corner needs a drawing with a single frame.',
  },
  'notch_no_shutter': {
    AppLanguage.arabic: 'احذف الستار (الصندوق) أولاً: لا يجتمع مع زاوية مقطوعة.',
    AppLanguage.french:
        'Retirez d’abord le volet (caisson) : il ne se combine pas avec un angle découpé.',
    AppLanguage.english:
        'Remove the shutter (box) first: it does not combine with a cut corner.',
  },
  'notch_no_shaped_head': {
    AppLanguage.arabic: 'لا تجتمع الزاوية المقطوعة مع الإطار المائل أو المقوس.',
    AppLanguage.french:
        'Un angle découpé ne se combine pas avec un cadre incliné ou cintré.',
    AppLanguage.english:
        'A cut corner does not combine with a slanted or arched frame.',
  },
  'notch_needs_bottom_frame': {
    AppLanguage.arabic: 'قطع الزاوية يحتاج إطاراً سفلياً كاملاً.',
    AppLanguage.french: 'La découpe d’angle demande un cadre bas complet.',
    AppLanguage.english: 'A cut corner needs a full bottom frame.',
  },
  'notch_no_side_covers': {
    AppLanguage.arabic:
        'الغطاء الجانبي لا يجتمع مع زاوية مقطوعة حالياً: احذف أحدهما أولاً.',
    AppLanguage.french:
        'Le couvre-joint latéral ne se combine pas encore avec un angle découpé : retirez l’un des deux.',
    AppLanguage.english:
        'A side cover does not combine with a cut corner yet: remove one of them first.',
  },
  'notch_no_slanted_mullion': {
    AppLanguage.arabic: 'احذف القواطع المائلة أولاً.',
    AppLanguage.french: 'Supprimez d’abord les montants inclinés.',
    AppLanguage.english: 'Remove the slanted mullions first.',
  },
  'notch_zones_conflict': {
    AppLanguage.arabic:
        'لا يتسع هذا القطع مع التقسيمات الحالية: صغّر القطع أو عدّل التقسيمات.',
    AppLanguage.french:
        'Cette découpe ne tient pas avec les divisions actuelles : réduisez-la ou modifiez les divisions.',
    AppLanguage.english:
        'This cut does not fit the current divisions: make it smaller or change the divisions.',
  },
};
