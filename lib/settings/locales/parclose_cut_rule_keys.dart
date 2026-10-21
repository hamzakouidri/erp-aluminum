import '../app_settings.dart';

/// Labels of the aluminium parclose cut: the choice in the drawing and the
/// rule a parclose profile sets in the catalogue (see `ParcloseCutRule`).
/// Keys are namespaced with `parclose_cut_`.
final Map<String, Map<AppLanguage, String>> parcloseCutRuleKeys = {
  'parclose_cut_title': {
    AppLanguage.arabic: 'قطع الباركلوز (Parclose)',
    AppLanguage.french: 'Coupe parclose',
    AppLanguage.english: 'Parclose cut',
  },
  'parclose_cut_45': {
    AppLanguage.arabic: 'قطع 45°',
    AppLanguage.french: 'Coupe 45°',
    AppLanguage.english: '45° cut',
  },
  'parclose_cut_90_length': {
    AppLanguage.arabic: '90° الأولوية للطول',
    AppLanguage.french: '90° priorité hauteur',
    AppLanguage.english: '90° height first',
  },
  'parclose_cut_90_width': {
    AppLanguage.arabic: '90° الأولوية للعرض',
    AppLanguage.french: '90° priorité largeur',
    AppLanguage.english: '90° width first',
  },
  'parclose_cut_hint_45': {
    AppLanguage.arabic: 'كل القطع بمقاس الفراغ الداخلي (مثل PVC)',
    AppLanguage.french: 'Toutes les coupes au clair intérieur (comme le PVC)',
    AppLanguage.english: 'Every piece at the inner clear size (like PVC)',
  },
  'parclose_cut_hint_90_length': {
    AppLanguage.arabic:
        'القطع الطولية = الفراغ الداخلي، والعرضية = الفراغ الداخلي − 2 × ركوب الزجاج للباركلوز',
    AppLanguage.french:
        'Montants = clair intérieur, traverses = clair − 2 × déduction vitrage de la parclose',
    AppLanguage.english:
        'Vertical pieces = inner clear size, horizontal = clear − 2 × parclose glass deduction',
  },
  'parclose_cut_hint_90_width': {
    AppLanguage.arabic:
        'القطع العرضية = الفراغ الداخلي، والطولية = الفراغ الداخلي − 2 × ركوب الزجاج للباركلوز',
    AppLanguage.french:
        'Traverses = clair intérieur, montants = clair − 2 × déduction vitrage de la parclose',
    AppLanguage.english:
        'Horizontal pieces = inner clear size, vertical = clear − 2 × parclose glass deduction',
  },
  'parclose_cut_fixed_by_profile': {
    AppLanguage.arabic: 'نوع القطع محدد في قواعد هذا الباركلوز',
    AppLanguage.french: 'Coupe imposée par les règles de cette parclose',
    AppLanguage.english: 'Cut set by this parclose’s profile rules',
  },
  'parclose_cut_support_label': {
    AppLanguage.arabic: 'نوع القطع المدعوم',
    AppLanguage.french: 'Coupes possibles',
    AppLanguage.english: 'Supported cuts',
  },
  'parclose_cut_support_both': {
    AppLanguage.arabic: '45° و 90° معاً',
    AppLanguage.french: '45° et 90°',
    AppLanguage.english: '45° and 90°',
  },
  'parclose_cut_support_45': {
    AppLanguage.arabic: '45° فقط',
    AppLanguage.french: '45° uniquement',
    AppLanguage.english: '45° only',
  },
  'parclose_cut_support_90': {
    AppLanguage.arabic: '90° فقط',
    AppLanguage.french: '90° uniquement',
    AppLanguage.english: '90° only',
  },
  'parclose_cut_default_label': {
    AppLanguage.arabic: 'القطع الافتراضي للرسم الجديد',
    AppLanguage.french: 'Coupe par défaut d’un nouveau dessin',
    AppLanguage.english: 'Default cut for a new drawing',
  },
  'parclose_cut_priority_label': {
    AppLanguage.arabic: 'أولوية القطع 90°',
    AppLanguage.french: 'Priorité de la coupe à 90°',
    AppLanguage.english: '90° cut priority',
  },
};
