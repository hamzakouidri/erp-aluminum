import '../app_settings.dart';

/// Glass drawer messages of the automatic glazing fit. `{name}` placeholders
/// are filled by `describeGlazingFit`.
final Map<String, Map<AppLanguage, String>> glazingFitKeys = {
  'الباركلوز': {
    AppLanguage.arabic: 'الباركلوز',
    AppLanguage.french: 'parclose',
    AppLanguage.english: 'glazing bead',
  },
  'الضلفة': {
    AppLanguage.arabic: 'الضلفة',
    AppLanguage.french: 'ouvrant',
    AppLanguage.english: 'sash',
  },
  'زجاج': {
    AppLanguage.arabic: 'زجاج',
    AppLanguage.french: 'verre',
    AppLanguage.english: 'glass',
  },
  'بانو': {
    AppLanguage.arabic: 'بانو',
    AppLanguage.french: 'panneau',
    AppLanguage.english: 'panel',
  },
  'فاصل': {
    AppLanguage.arabic: 'فاصل',
    AppLanguage.french: 'intercalaire',
    AppLanguage.english: 'spacer',
  },
  'جوان فيتراج': {
    AppLanguage.arabic: 'جوان فيتراج',
    AppLanguage.french: 'joint de vitrage',
    AppLanguage.english: 'glazing gasket',
  },
  'جوان بوراج': {
    AppLanguage.arabic: 'جوان بوراج',
    AppLanguage.french: 'joint de bourrage',
    AppLanguage.english: 'wedge gasket',
  },
  'تعذّر حساب التركيب: سعة الزجاج غير محددة في {target}.': {
    AppLanguage.arabic: 'تعذّر حساب التركيب: سعة الزجاج غير محددة في {target}.',
    AppLanguage.french:
        'Calcul impossible : la capacité de vitrage n\'est pas définie pour le {target}.',
    AppLanguage.english:
        'Cannot calculate: the glazing capacity of the {target} is not defined.',
  },
  'التركيب المعتمد: {pack} = {total} مم، وسعة {target} {capacity} مم.': {
    AppLanguage.arabic:
        'التركيب المعتمد: {pack} = {total} مم، وسعة {target} {capacity} مم.',
    AppLanguage.french:
        'Composition retenue : {pack} = {total} mm, capacité du {target} {capacity} mm.',
    AppLanguage.english:
        'Selected build-up: {pack} = {total} mm, {target} capacity {capacity} mm.',
  },
  'زيادة {excess} مم مقبولة (الحد الأقصى 1 مم).': {
    AppLanguage.arabic: 'زيادة {excess} مم مقبولة (الحد الأقصى 1 مم).',
    AppLanguage.french: 'Surépaisseur de {excess} mm acceptée (1 mm maximum).',
    AppLanguage.english: 'An excess of {excess} mm is accepted (1 mm maximum).',
  },
  'الفاصل {spacer} مم اختيار يدوي.': {
    AppLanguage.arabic: 'الفاصل {spacer} مم اختيار يدوي.',
    AppLanguage.french: 'Intercalaire de {spacer} mm choisi manuellement.',
    AppLanguage.english: 'The {spacer} mm spacer was chosen manually.',
  },
  'الفاصل {spacer} مم لا يتوافق مع سعة {target} ({capacity} مم).': {
    AppLanguage.arabic:
        'الفاصل {spacer} مم لا يتوافق مع سعة {target} ({capacity} مم).',
    AppLanguage.french:
        'L\'intercalaire de {spacer} mm ne convient pas à la capacité du {target} ({capacity} mm).',
    AppLanguage.english:
        'The {spacer} mm spacer does not suit the {target} capacity ({capacity} mm).',
  },
  'الزجاج المطلوب ({glass}) لا يتوافق مع سعة {target} ({capacity} مم).': {
    AppLanguage.arabic:
        'الزجاج المطلوب ({glass}) لا يتوافق مع سعة {target} ({capacity} مم).',
    AppLanguage.french:
        'Le vitrage demandé ({glass}) ne convient pas à la capacité du {target} ({capacity} mm).',
    AppLanguage.english:
        'The requested glass ({glass}) does not suit the {target} capacity ({capacity} mm).',
  },
  'المقترح: فاصل {spacer} مم ({pack} = {total} مم).': {
    AppLanguage.arabic: 'المقترح: فاصل {spacer} مم ({pack} = {total} مم).',
    AppLanguage.french:
        'Proposition : intercalaire de {spacer} mm ({pack} = {total} mm).',
    AppLanguage.english: 'Suggested: a {spacer} mm spacer ({pack} = {total} mm).',
  },
  'المقترح: تغيير سُمك الزجاج ({pack} = {total} مم).': {
    AppLanguage.arabic: 'المقترح: تغيير سُمك الزجاج ({pack} = {total} مم).',
    AppLanguage.french:
        'Proposition : changer l\'épaisseur du verre ({pack} = {total} mm).',
    AppLanguage.english: 'Suggested: change the glass thickness ({pack} = {total} mm).',
  },
  'لا توجد تركيبة مناسبة من الجوانات والفاصل المفعّلة؛ لا يُقبل النقص والزيادة القصوى 1 مم.': {
    AppLanguage.arabic:
        'لا توجد تركيبة مناسبة من الجوانات والفاصل المفعّلة؛ لا يُقبل النقص والزيادة القصوى 1 مم.',
    AppLanguage.french:
        'Aucune combinaison de joints et d\'intercalaires activés ne convient : aucun manque n\'est accepté, 1 mm de surépaisseur au maximum.',
    AppLanguage.english:
        'No combination of the enabled gaskets and spacers fits: no shortfall is accepted, 1 mm excess at most.',
  },
  'يمكنك تغيير الفاصل يدوياً، وسيظهر تنبيه إن لم يتوافق.': {
    AppLanguage.arabic: 'يمكنك تغيير الفاصل يدوياً، وسيظهر تنبيه إن لم يتوافق.',
    AppLanguage.french:
        'Vous pouvez changer l\'intercalaire manuellement ; une alerte s\'affiche s\'il ne convient pas.',
    AppLanguage.english:
        'You can change the spacer manually; a warning appears if it does not fit.',
  },
  'معاينة ثلاثية الأبعاد': {
    AppLanguage.arabic: 'معاينة ثلاثية الأبعاد',
    AppLanguage.french: 'Aperçu 3D',
    AppLanguage.english: '3D preview',
  },
  'إعادة ضبط المنظور': {
    AppLanguage.arabic: 'إعادة ضبط المنظور',
    AppLanguage.french: 'Réinitialiser la vue',
    AppLanguage.english: 'Reset view',
  },
  'إيقاف الحركة': {
    AppLanguage.arabic: 'إيقاف الحركة',
    AppLanguage.french: 'Arrêter l\'animation',
    AppLanguage.english: 'Stop animation',
  },
  'إغلاق النافذة': {
    AppLanguage.arabic: 'إغلاق النافذة',
    AppLanguage.french: 'Fermer la fenêtre',
    AppLanguage.english: 'Close the window',
  },
  'فتح النافذة': {
    AppLanguage.arabic: 'فتح النافذة',
    AppLanguage.french: 'Ouvrir la fenêtre',
    AppLanguage.english: 'Open the window',
  },
};
