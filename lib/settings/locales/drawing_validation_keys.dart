import '../app_settings.dart';

/// Messages shown when a typed drawing dimension is outside what the
/// aluminium/PVC layout can physically take.
final Map<String, Map<AppLanguage, String>> drawingValidationKeys = {
  'عدد القطاعات': {
    AppLanguage.arabic: 'عدد القطاعات',
    AppLanguage.french: "Nombre de barres",
    AppLanguage.english: "Number of bars",
  },
  'طول القطاع': {
    AppLanguage.arabic: 'طول القطاع',
    AppLanguage.french: "Longueur de barre",
    AppLanguage.english: "Bar length",
  },
  'الهدر': {
    AppLanguage.arabic: 'الهدر',
    AppLanguage.french: "Chute",
    AppLanguage.english: "Waste",
  },
  'قطع أطول من القطاع': {
    AppLanguage.arabic: 'قطع أطول من القطاع',
    AppLanguage.french: "Pièces plus longues que la barre",
    AppLanguage.english: "Pieces longer than the bar",
  },
  'عرض خطة القص': {
    AppLanguage.arabic: 'عرض خطة القص',
    AppLanguage.french: "Voir le plan de coupe",
    AppLanguage.english: "Show the cutting plan",
  },
  'لا يوجد بديل يقبله الرسم لهذا القطاع': {
    AppLanguage.arabic: 'لا يوجد بديل يقبله الرسم لهذا القطاع',
    AppLanguage.french:
        "Aucun profil de remplacement n'est accepté par le dessin pour ce profilé",
    AppLanguage.english: 'No replacement profile fits the drawing for this profile',
  },
  'بروفيل الزاوية يركب بين إطارين متلاصقين فقط، وليس على أطراف الإطار. ألصق إطاراً بإطار ثم فعّله بينهما.': {
    AppLanguage.arabic:
        'بروفيل الزاوية يركب بين إطارين متلاصقين فقط، وليس على أطراف الإطار. ألصق إطاراً بإطار ثم فعّله بينهما.',
    AppLanguage.french:
        "Le profil d'angle se pose uniquement entre deux dormants accolés, jamais sur les bords du dormant. Accolez deux dormants puis activez-le entre eux.",
    AppLanguage.english:
        'The corner profile goes only between two joined frames, never on the edges of a frame. Join two frames, then switch it on between them.',
  },
  'بجانب بروفيل الزاوية يجب إطار لا يحمل غطاءً جانبيًا ولا غطاءً مدمجًا، ولا يوجد في السلسلة إطار مناسب لـ: {frames}': {
    AppLanguage.arabic:
        'بجانب بروفيل الزاوية يجب إطار لا يحمل غطاءً جانبيًا ولا غطاءً مدمجًا، ولا يوجد في السلسلة إطار مناسب لـ: {frames}',
    AppLanguage.french:
        'Contre le profilé d\'angle il faut un cadre sans couvre-joint ni couvre-joint intégré ; la série n\'en a aucun pour : {frames}',
    AppLanguage.english:
        'A corner profile needs a frame that carries no side cover and has no integrated cover; the series has none for: {frames}',
  },
  'القياس المسموح به بين {min} و {max} مم': {
    AppLanguage.arabic: 'القياس المسموح به بين {min} و {max} مم',
    AppLanguage.french: 'Dimension autorisée entre {min} et {max} mm',
    AppLanguage.english: 'Allowed dimension is between {min} and {max} mm',
  },
  'تم ضبط القياس إلى {value} مم ليبقى كل جزء ضمن الحد الأدنى': {
    AppLanguage.arabic:
        'تم ضبط القياس إلى {value} مم ليبقى كل جزء ضمن الحد الأدنى',
    AppLanguage.french:
        'Dimension ajustée à {value} mm pour que chaque partie reste au minimum requis',
    AppLanguage.english:
        'Dimension adjusted to {value} mm so every part keeps its minimum size',
  },
  'هذا الجزء غير مقسّم: غيّر القياس الخارجي للإطار': {
    AppLanguage.arabic: 'هذا الجزء غير مقسّم: غيّر القياس الخارجي للإطار',
    AppLanguage.french:
        'Cette partie n\'est pas divisée : modifiez la dimension extérieure du cadre',
    AppLanguage.english:
        'This part is not divided: change the frame\'s outer dimension',
  },
  'ارتفاع القائم الأيسر (mm)': {
    AppLanguage.arabic: 'ارتفاع القائم الأيسر (mm)',
    AppLanguage.french: 'Hauteur du montant gauche (mm)',
    AppLanguage.english: 'Left jamb height (mm)',
  },
  'ارتفاع القائم الأيمن (mm)': {
    AppLanguage.arabic: 'ارتفاع القائم الأيمن (mm)',
    AppLanguage.french: 'Hauteur du montant droit (mm)',
    AppLanguage.english: 'Right jamb height (mm)',
  },
  'ذروة القوس (mm)': {
    AppLanguage.arabic: 'ذروة القوس (mm)',
    AppLanguage.french: "Flèche de l'arc (mm)",
    AppLanguage.english: 'Arch rise (mm)',
  },
  // Slanted divisions (SlantedDivisionError).
  'يجب أن يبدأ التقسيم المائل وينتهي على ضلعين مختلفين': {
    AppLanguage.arabic: 'يجب أن يبدأ التقسيم المائل وينتهي على ضلعين مختلفين',
    AppLanguage.french:
        'Une traverse inclinée doit relier deux côtés différents',
    AppLanguage.english: 'A slanted mullion must join two different sides',
  },
  'طرف التقسيم المائل قريب جداً من زاوية الإطار': {
    AppLanguage.arabic: 'طرف التقسيم المائل قريب جداً من زاوية الإطار',
    AppLanguage.french:
        "L'extrémité de la traverse inclinée est trop près d'un angle",
    AppLanguage.english: 'The slanted mullion ends too close to a corner',
  },
  'زاوية التقسيم المائل مع الإطار أصغر من الحد الأدنى {min}°': {
    AppLanguage.arabic:
        'زاوية التقسيم المائل مع الإطار أصغر من الحد الأدنى {min}°',
    AppLanguage.french:
        "L'angle de la traverse inclinée est inférieur au minimum de {min}°",
    AppLanguage.english:
        'The slanted mullion angle is below the {min}° minimum',
  },
  'لا يمكن أن تتقاطع التقسيمات المائلة': {
    AppLanguage.arabic: 'لا يمكن أن تتقاطع التقسيمات المائلة',
    AppLanguage.french: 'Les traverses inclinées ne peuvent pas se croiser',
    AppLanguage.english: 'Slanted mullions cannot cross each other',
  },
  'جزء من الزجاج أضيق من {min} مم بعد التقسيم المائل': {
    AppLanguage.arabic: 'جزء من الزجاج أضيق من {min} مم بعد التقسيم المائل',
    AppLanguage.french:
        'Un vitrage devient plus étroit que {min} mm avec cette traverse',
    AppLanguage.english:
        'A glass cell becomes narrower than {min} mm with this mullion',
  },
  'التقسيم المائل متاح في الأجزاء الثابتة فقط': {
    AppLanguage.arabic: 'التقسيم المائل متاح في الأجزاء الثابتة فقط',
    AppLanguage.french:
        'La traverse inclinée est réservée aux parties fixes',
    AppLanguage.english: 'Slanted mullions are for fixed parts only',
  },
  'احذف التقسيمات المستقيمة الداخلية قبل إضافة تقسيم مائل': {
    AppLanguage.arabic:
        'احذف التقسيمات المستقيمة الداخلية قبل إضافة تقسيم مائل',
    AppLanguage.french:
        'Supprimez les divisions droites avant une traverse inclinée',
    AppLanguage.english:
        'Remove the straight inner divisions before a slanted mullion',
  },
  'التقسيم المائل غير متاح تحت رأس مائل أو مقوس حالياً': {
    AppLanguage.arabic: 'التقسيم المائل غير متاح تحت رأس مائل أو مقوس حالياً',
    AppLanguage.french:
        'Pas encore de traverse inclinée sous une tête inclinée ou cintrée',
    AppLanguage.english:
        'Slanted mullions are not yet available under a shaped head',
  },
  // Hinge editing on the drawing.
  'إضافة مفصل': {
    AppLanguage.arabic: 'إضافة مفصل',
    AppLanguage.french: 'Ajouter une paumelle',
    AppLanguage.english: 'Add hinge',
  },
  'إضافة مفصل هنا': {
    AppLanguage.arabic: 'إضافة مفصل هنا',
    AppLanguage.french: 'Ajouter une paumelle ici',
    AppLanguage.english: 'Add hinge here',
  },
  'حذف المفصل': {
    AppLanguage.arabic: 'حذف المفصل',
    AppLanguage.french: 'Supprimer la paumelle',
    AppLanguage.english: 'Delete hinge',
  },
  'توزيع المفاصل تلقائياً': {
    AppLanguage.arabic: 'توزيع المفاصل تلقائياً',
    AppLanguage.french: 'Répartition automatique des paumelles',
    AppLanguage.english: 'Automatic hinge layout',
  },
  'مفاصل نظام OB ثابتة ضمن الطقم ولا يمكن تعديلها': {
    AppLanguage.arabic: 'مفاصل نظام OB ثابتة ضمن الطقم ولا يمكن تعديلها',
    AppLanguage.french:
        'Les paumelles du système OB font partie du kit et ne se modifient pas',
    AppLanguage.english:
        'OB system hinges are part of the kit and cannot be changed',
  },
  'لا يوجد مكان لمفصل آخر: {min} مم من الطرف و {gap} مم بين المفاصل': {
    AppLanguage.arabic:
        'لا يوجد مكان لمفصل آخر: {min} مم من الطرف و {gap} مم بين المفاصل',
    AppLanguage.french:
        "Pas de place pour une autre paumelle : {min} mm des extrémités et {gap} mm entre paumelles",
    AppLanguage.english:
        'No room for another hinge: {min} mm from the ends and {gap} mm between hinges',
  },
  'يجب أن تبقى في الضلفة مفصلتان على الأقل': {
    AppLanguage.arabic: 'يجب أن تبقى في الضلفة مفصلتان على الأقل',
    AppLanguage.french: "Un ouvrant garde au moins deux paumelles",
    AppLanguage.english: 'A sash keeps at least two hinges',
  },
  'تقسيم مائل': {
    AppLanguage.arabic: 'تقسيم مائل',
    AppLanguage.french: 'Traverse inclinée',
    AppLanguage.english: 'Slanted mullion',
  },
  'الضلع العلوي': {
    AppLanguage.arabic: 'الضلع العلوي',
    AppLanguage.french: 'Côté haut',
    AppLanguage.english: 'Top side',
  },
  'الضلع السفلي': {
    AppLanguage.arabic: 'الضلع السفلي',
    AppLanguage.french: 'Côté bas',
    AppLanguage.english: 'Bottom side',
  },
  'الضلع الأيسر': {
    AppLanguage.arabic: 'الضلع الأيسر',
    AppLanguage.french: 'Côté gauche',
    AppLanguage.english: 'Left side',
  },
  'الضلع الأيمن': {
    AppLanguage.arabic: 'الضلع الأيمن',
    AppLanguage.french: 'Côté droit',
    AppLanguage.english: 'Right side',
  },
  'المسافة من يسار الإطار (mm)': {
    AppLanguage.arabic: 'المسافة من يسار الإطار (mm)',
    AppLanguage.french: 'Distance depuis la gauche du cadre (mm)',
    AppLanguage.english: 'Distance from the frame left (mm)',
  },
  'المسافة من أعلى الإطار (mm)': {
    AppLanguage.arabic: 'المسافة من أعلى الإطار (mm)',
    AppLanguage.french: 'Distance depuis le haut du cadre (mm)',
    AppLanguage.english: 'Distance from the frame top (mm)',
  },
  'الزاوية': {
    AppLanguage.arabic: 'الزاوية',
    AppLanguage.french: 'Angle',
    AppLanguage.english: 'Angle',
  },
  'زاوية القص': {
    AppLanguage.arabic: 'زاوية القص',
    AppLanguage.french: 'Angle de coupe',
    AppLanguage.english: 'Cut angle',
  },
  'طول القص': {
    AppLanguage.arabic: 'طول القص',
    AppLanguage.french: 'Longueur de coupe',
    AppLanguage.english: 'Cut length',
  },
  'مقبض مدمج (أونكاستري)': {
    AppLanguage.arabic: 'مقبض مدمج (أونكاستري)',
    AppLanguage.french: 'Poignée encastrée',
    AppLanguage.english: 'Recessed handle',
  },
  'كل المقابض': {
    AppLanguage.arabic: 'كل المقابض',
    AppLanguage.french: 'Toutes les poignées',
    AppLanguage.english: 'All handles',
  },
  'المقبض الأيسر': {
    AppLanguage.arabic: 'المقبض الأيسر',
    AppLanguage.french: 'Poignée gauche',
    AppLanguage.english: 'Left handle',
  },
  'المقبض الأيمن': {
    AppLanguage.arabic: 'المقبض الأيمن',
    AppLanguage.french: 'Poignée droite',
    AppLanguage.english: 'Right handle',
  },
  'مقابض الوسط': {
    AppLanguage.arabic: 'مقابض الوسط',
    AppLanguage.french: 'Poignées centrales',
    AppLanguage.english: 'Central handles',
  },
  'كل مقابض النافذة': {
    AppLanguage.arabic: 'كل مقابض النافذة',
    AppLanguage.french: 'Toutes les poignées de la fenêtre',
    AppLanguage.english: 'All handles of the window',
  },
  'تم تحديد كل الضلفات: الظلفة والمقبض يتغيران فيها كلها. ضغطة واحدة تحدد ضلفة واحدة.':
      {
        AppLanguage.arabic:
            'تم تحديد كل الضلفات: الظلفة والمقبض يتغيران فيها كلها. ضغطة واحدة تحدد ضلفة واحدة.',
        AppLanguage.french:
            'Tous les ouvrants sont sélectionnés : le profil et la poignée changent sur tous. Un clic sélectionne un seul ouvrant.',
        AppLanguage.english:
            'All sashes are selected: the profile and handle change on all of them. A single click selects one sash.',
      },
};
