import '../app_settings.dart';

// Text introduced by the catalogue, profile-rules, inventory and required
// goods workflows. Keep the Arabic phrase as the key so existing calls to
// Localization.translate continue to work without a second UI model.
const Map<String, Map<AppLanguage, String>> translationPhase9Keys = {
  'تقارير متطلبات واستعمال السلاسل': {
    AppLanguage.arabic: 'تقارير متطلبات واستعمال السلاسل',
    AppLanguage.french: 'Rapports des besoins et de l’utilisation des gammes',
    AppLanguage.english: 'Series requirements and usage reports',
  },
  'متطلبات واستعمال السلاسل': {
    AppLanguage.arabic: 'متطلبات واستعمال السلاسل',
    AppLanguage.french: 'Besoins et utilisation des gammes',
    AppLanguage.english: 'Series requirements and usage',
  },
  'الألوان': {
    AppLanguage.arabic: 'الألوان',
    AppLanguage.french: 'Couleurs',
    AppLanguage.english: 'Colours',
  },
  'الإكسسوارات': {
    AppLanguage.arabic: 'الإكسسوارات',
    AppLanguage.french: 'Accessoires',
    AppLanguage.english: 'Accessories',
  },
  'الأكسسوارات': {
    AppLanguage.arabic: 'الأكسسوارات',
    AppLanguage.french: 'Accessoires',
    AppLanguage.english: 'Accessories',
  },
  'البروفيلات والانظمة': {
    AppLanguage.arabic: 'البروفيلات والأنظمة',
    AppLanguage.french: 'Profilés et systèmes',
    AppLanguage.english: 'Profiles and systems',
  },
  'الجوانات': {
    AppLanguage.arabic: 'الجوانات',
    AppLanguage.french: 'Joints',
    AppLanguage.english: 'Gaskets',
  },
  'ستار': {
    AppLanguage.arabic: 'ستار',
    AppLanguage.french: 'Volet',
    AppLanguage.english: 'Shutter',
  },
  'الإطار': {
    AppLanguage.arabic: 'الإطار',
    AppLanguage.french: 'Cadre',
    AppLanguage.english: 'Frame',
  },
  'السكك المضافة': {
    AppLanguage.arabic: 'السكك المضافة',
    AppLanguage.french: 'Rails ajoutés',
    AppLanguage.english: 'Added rails',
  },
  'السكك المقبولة': {
    AppLanguage.arabic: 'السكك المقبولة',
    AppLanguage.french: 'Rails acceptés',
    AppLanguage.english: 'Allowed rails',
  },
  'السكك الموجودة': {
    AppLanguage.arabic: 'السكك الموجودة',
    AppLanguage.french: 'Rails existants',
    AppLanguage.english: 'Existing rails',
  },
  'قواعد': {
    AppLanguage.arabic: 'قواعد',
    AppLanguage.french: 'Règles',
    AppLanguage.english: 'Rules',
  },
  'قواعد الأكسسوار': {
    AppLanguage.arabic: 'قواعد الأكسسوار',
    AppLanguage.french: "Règles de l'accessoire",
    AppLanguage.english: 'Accessory rules',
  },
  'قواعد الإكسسوار': {
    AppLanguage.arabic: 'قواعد الإكسسوار',
    AppLanguage.french: 'Règles de l’accessoire',
    AppLanguage.english: 'Accessory rules',
  },
  'قواعد الإكسسوارات والجوانات': {
    AppLanguage.arabic: 'قواعد الإكسسوارات والجوانات',
    AppLanguage.french: 'Règles des accessoires et des joints',
    AppLanguage.english: 'Accessory and gasket rules',
  },
  'قواعد الكتالوج العامة': {
    AppLanguage.arabic: 'قواعد الكتالوج العامة',
    AppLanguage.french: 'Règles générales du catalogue',
    AppLanguage.english: 'General catalogue rules',
  },
  'قواعد المقاطع المختارة': {
    AppLanguage.arabic: 'قواعد المقاطع المختارة',
    AppLanguage.french: 'Règles des profilés sélectionnés',
    AppLanguage.english: 'Selected profile rules',
  },
  'الروابط الحسابية': {
    AppLanguage.arabic: 'الروابط الحسابية',
    AppLanguage.french: 'Liens de calcul',
    AppLanguage.english: 'Calculation links',
  },
  'مكوّنات وحسابات السلسلة': {
    AppLanguage.arabic: 'مكوّنات وحسابات السلسلة',
    AppLanguage.french: 'Composants et calculs de la gamme',
    AppLanguage.english: 'Series components and calculations',
  },
  'حسابات ضلف النظام المنزلق': {
    AppLanguage.arabic: 'حسابات ضلف النظام المنزلق',
    AppLanguage.french: 'Calculs des vantaux du système coulissant',
    AppLanguage.english: 'Sliding-system sash calculations',
  },
  'نوع الإطار والسكك': {
    AppLanguage.arabic: 'نوع الإطار والسكك',
    AppLanguage.french: 'Type de cadre et de rails',
    AppLanguage.english: 'Frame and rail type',
  },
  'إطار أساسي': {
    AppLanguage.arabic: 'إطار أساسي',
    AppLanguage.french: 'Cadre de base',
    AppLanguage.english: 'Base frame',
  },
  'إطار كامل بعدة سكك': {
    AppLanguage.arabic: 'إطار كامل بعدة سكك',
    AppLanguage.french: 'Cadre complet à plusieurs rails',
    AppLanguage.english: 'Multi-rail complete frame',
  },
  'إضافة سكة: بروفيل إضافي يركب بعد الإطار الأساسي لزيادة عدد السكك. كلمة Classic أو autre تعني «كلاسيك أو غيره» وليست نوع حساب مستقل.': {
    AppLanguage.arabic: 'إضافة سكة: بروفيل إضافي يركب بعد الإطار الأساسي لزيادة عدد السكك. كلمة Classic أو autre تعني «كلاسيك أو غيره» وليست نوع حساب مستقل.',
    AppLanguage.french: 'Ajout de rail : profil supplémentaire monté après le cadre de base pour augmenter le nombre de rails. « Classic ou autre » désigne le complément, pas un calcul indépendant.',
    AppLanguage.english: 'Rail addition: an extra profile installed after the base frame to increase the rail count. “Classic or other” identifies the extension, not a separate calculation.',
  },
  'إطار أساسي: البروفيل الرئيسي الذي يبدأ منه الإطار. في المنزلق هو إطار السكتين الأساسي، ثم يمكن إضافة سكة أخرى عند الحاجة.': {
    AppLanguage.arabic: 'إطار أساسي: البروفيل الرئيسي الذي يبدأ منه الإطار. في المنزلق هو إطار السكتين الأساسي، ثم يمكن إضافة سكة أخرى عند الحاجة.',
    AppLanguage.french: 'Cadre de base : profil principal de départ. Dans un coulissant, c’est le cadre à deux rails auquel un rail peut être ajouté si nécessaire.',
    AppLanguage.english: 'Base frame: the main profile from which the frame starts. In a sliding system it is the two-rail base frame, with another rail added when needed.',
  },
  'إطار كامل متعدد السكك: عدة سكك مدمجة داخل نفس البروفيل. استعمله عندما يكون القطاع نفسه إطارًا بـ 3 أو 4 أو 5 سكك، ولا توجد إضافة منفصلة.': {
    AppLanguage.arabic: 'إطار كامل متعدد السكك: عدة سكك مدمجة داخل نفس البروفيل. استعمله عندما يكون القطاع نفسه إطارًا بـ 3 أو 4 أو 5 سكك، ولا توجد إضافة منفصلة.',
    AppLanguage.french: 'Cadre complet multi-rails : plusieurs rails intégrés dans le même profil. Utilisez-le lorsque le profil est directement un cadre à 3, 4 ou 5 rails, sans complément séparé.',
    AppLanguage.english: 'Multi-rail complete frame: several rails integrated into one profile. Use it when the profile itself is a 3-, 4- or 5-rail frame with no separate extension.',
  },
  'إضافة سكة (كلاسيك أو غيره)': {
    AppLanguage.arabic: 'إضافة سكة (كلاسيك أو غيره)',
    AppLanguage.french: 'Ajouter un rail (Classic ou autre)',
    AppLanguage.english: 'Add a rail (Classic or other)',
  },
  'افتراضي': {
    AppLanguage.arabic: 'افتراضي',
    AppLanguage.french: 'Par défaut',
    AppLanguage.english: 'Default',
  },
  'القيمة': {
    AppLanguage.arabic: 'القيمة',
    AppLanguage.french: 'Valeur',
    AppLanguage.english: 'Value',
  },
  'الفئة': {
    AppLanguage.arabic: 'الفئة',
    AppLanguage.french: 'Catégorie',
    AppLanguage.english: 'Category',
  },
  'المواد': {
    AppLanguage.arabic: 'المواد',
    AppLanguage.french: 'Matériaux',
    AppLanguage.english: 'Materials',
  },
  'المورّد': {
    AppLanguage.arabic: 'المورّد',
    AppLanguage.french: 'Fournisseur',
    AppLanguage.english: 'Supplier',
  },
  'مكان التخزين': {
    AppLanguage.arabic: 'مكان التخزين',
    AppLanguage.french: 'Emplacement de stockage',
    AppLanguage.english: 'Storage location',
  },
  'جدول الكمية': {
    AppLanguage.arabic: 'جدول الكمية',
    AppLanguage.french: 'Tableau des quantités',
    AppLanguage.english: 'Quantity table',
  },
  'خطة القص': {
    AppLanguage.arabic: 'خطة القص',
    AppLanguage.french: 'Plan de coupe',
    AppLanguage.english: 'Cutting plan',
  },
  'كمية الشراء': {
    AppLanguage.arabic: 'كمية الشراء',
    AppLanguage.french: "Quantité d'achat",
    AppLanguage.english: 'Purchase quantity',
  },
  'تغيير القطاع': {
    AppLanguage.arabic: 'تغيير القطاع',
    AppLanguage.french: 'Changer le profilé',
    AppLanguage.english: 'Change profile',
  },
  'استعمال المقطع': {
    AppLanguage.arabic: 'استعمال المقطع',
    AppLanguage.french: 'Utilisation du profilé',
    AppLanguage.english: 'Profile usage',
  },
  'مجال استعمال العنصر': {
    AppLanguage.arabic: 'مجال استعمال العنصر',
    AppLanguage.french: "Domaine d'utilisation de l'élément",
    AppLanguage.english: 'Item usage scope',
  },
  'مكوّن داخل الكِت': {
    AppLanguage.arabic: 'مكوّن داخل الكِت',
    AppLanguage.french: 'Composant du kit',
    AppLanguage.english: 'Kit component',
  },
  'يظهر في الرسم': {
    AppLanguage.arabic: 'يظهر في الرسم',
    AppLanguage.french: 'Visible sur le dessin',
    AppLanguage.english: 'Shown in drawing',
  },
  'يظهر في جدول الكمية': {
    AppLanguage.arabic: 'يظهر في جدول الكمية',
    AppLanguage.french: 'Visible dans le tableau des quantités',
    AppLanguage.english: 'Shown in quantity table',
  },
  'يظهر في نافذة التغيير': {
    AppLanguage.arabic: 'يظهر في نافذة التغيير',
    AppLanguage.french: 'Visible dans la fenêtre de modification',
    AppLanguage.english: 'Shown in change window',
  },
  'يظهر مع الزجاج': {
    AppLanguage.arabic: 'يظهر مع الزجاج',
    AppLanguage.french: 'Visible avec le verre',
    AppLanguage.english: 'Shown with glass',
  },
  'مسموح مع الستار': {
    AppLanguage.arabic: 'مسموح مع الستار',
    AppLanguage.french: 'Autorisé avec volet',
    AppLanguage.english: 'Allowed with shutter',
  },
  'ممنوع مع الستار': {
    AppLanguage.arabic: 'ممنوع مع الستار',
    AppLanguage.french: 'Interdit avec volet',
    AppLanguage.english: 'Not allowed with shutter',
  },
  'منزلق فقط': {
    AppLanguage.arabic: 'منزلق فقط',
    AppLanguage.french: 'Coulissant uniquement',
    AppLanguage.english: 'Sliding only',
  },
  'فتح فقط': {
    AppLanguage.arabic: 'فتح فقط',
    AppLanguage.french: 'Ouverture uniquement',
    AppLanguage.english: 'Opening only',
  },
  'فتح ومنزلق': {
    AppLanguage.arabic: 'فتح ومنزلق',
    AppLanguage.french: 'Ouverture et coulissant',
    AppLanguage.english: 'Opening and sliding',
  },
  'لا توجد عناصر.': {
    AppLanguage.arabic: 'لا توجد عناصر.',
    AppLanguage.french: 'Aucun élément.',
    AppLanguage.english: 'No items.',
  },
  'لا توجد نتائج.': {
    AppLanguage.arabic: 'لا توجد نتائج.',
    AppLanguage.french: 'Aucun résultat.',
    AppLanguage.english: 'No results.',
  },
  'بدون ربط': {
    AppLanguage.arabic: 'بدون ربط',
    AppLanguage.french: 'Non lié',
    AppLanguage.english: 'Unlinked',
  },
  'تعديل القواعد': {
    AppLanguage.arabic: 'تعديل القواعد',
    AppLanguage.french: 'Modifier les règles',
    AppLanguage.english: 'Edit rules',
  },
  'حفظ المكوّنات': {
    AppLanguage.arabic: 'حفظ المكوّنات',
    AppLanguage.french: 'Enregistrer les composants',
    AppLanguage.english: 'Save components',
  },
  'حفظ': {
    AppLanguage.arabic: 'حفظ',
    AppLanguage.french: 'Enregistrer',
    AppLanguage.english: 'Save',
  },
  'إلغاء': {
    AppLanguage.arabic: 'إلغاء',
    AppLanguage.french: 'Annuler',
    AppLanguage.english: 'Cancel',
  },
  'إنشاء': {
    AppLanguage.arabic: 'إنشاء',
    AppLanguage.french: 'Créer',
    AppLanguage.english: 'Create',
  },
  'تعديل': {
    AppLanguage.arabic: 'تعديل',
    AppLanguage.french: 'Modifier',
    AppLanguage.english: 'Edit',
  },
  'مسح البحث': {
    AppLanguage.arabic: 'مسح البحث',
    AppLanguage.french: 'Effacer la recherche',
    AppLanguage.english: 'Clear search',
  },
  'بحث بالكود، الاسم، النوع أو العنوان...': {
    AppLanguage.arabic: 'بحث بالكود، الاسم، النوع أو العنوان...',
    AppLanguage.french: 'Rechercher par code, nom, type ou titre...',
    AppLanguage.english: 'Search by code, name, type or title...',
  },
  'أدخل رقم الوثيقة': {
    AppLanguage.arabic: 'أدخل رقم الوثيقة',
    AppLanguage.french: 'Saisissez le numéro du document',
    AppLanguage.english: 'Enter the document number',
  },
  'رقم طلب الشراء': {
    AppLanguage.arabic: 'رقم طلب الشراء',
    AppLanguage.french: "Numéro de demande d'achat",
    AppLanguage.english: 'Purchase order number',
  },
  'رقم فاتورة الشراء': {
    AppLanguage.arabic: 'رقم فاتورة الشراء',
    AppLanguage.french: "Numéro de facture d'achat",
    AppLanguage.english: 'Purchase invoice number',
  },
  'طلب شراء (مسودة)': {
    AppLanguage.arabic: 'طلب شراء (مسودة)',
    AppLanguage.french: "Demande d'achat (brouillon)",
    AppLanguage.english: 'Purchase order (draft)',
  },
  'فاتورة شراء': {
    AppLanguage.arabic: 'فاتورة شراء',
    AppLanguage.french: "Facture d'achat",
    AppLanguage.english: 'Purchase invoice',
  },
  'تحويل إلى طلب أو فاتورة شراء': {
    AppLanguage.arabic: 'تحويل إلى طلب أو فاتورة شراء',
    AppLanguage.french: "Convertir en demande ou facture d'achat",
    AppLanguage.english: 'Convert to purchase order or invoice',
  },
  'لا توجد سلع مرتبطة بقاعدة البيانات لتحويلها إلى شراء.': {
    AppLanguage.arabic: 'لا توجد سلع مرتبطة بقاعدة البيانات لتحويلها إلى شراء.',
    AppLanguage.french: 'Aucun article lié à la base de données à convertir en achat.',
    AppLanguage.english: 'No database-linked goods to convert to a purchase.',
  },
  'تم الحفظ بنجاح!': {
    AppLanguage.arabic: 'تم الحفظ بنجاح!',
    AppLanguage.french: 'Enregistré avec succès !',
    AppLanguage.english: 'Saved successfully!',
  },
  'تعذر الحفظ': {
    AppLanguage.arabic: 'تعذر الحفظ',
    AppLanguage.french: "Échec de l'enregistrement",
    AppLanguage.english: 'Could not save',
  },
  'تعذر إنشاء ملف PDF': {
    AppLanguage.arabic: 'تعذر إنشاء ملف PDF',
    AppLanguage.french: 'Impossible de créer le fichier PDF',
    AppLanguage.english: 'Could not create the PDF file',
  },
  'تحويل الكميات المطلوبة إلى شراء': {
    AppLanguage.arabic: 'تحويل الكميات المطلوبة إلى شراء',
    AppLanguage.french: 'Convertir les quantités requises en achat',
    AppLanguage.english: 'Convert required quantities to purchase',
  },
  'تسجيل هدر': {
    AppLanguage.arabic: 'تسجيل هدر',
    AppLanguage.french: 'Enregistrer une perte',
    AppLanguage.english: 'Record waste',
  },
  'تأكيد': {
    AppLanguage.arabic: 'تأكيد',
    AppLanguage.french: 'Confirmer',
    AppLanguage.english: 'Confirm',
  },
  'ملاحظة حسابية': {
    AppLanguage.arabic: 'ملاحظة حسابية',
    AppLanguage.french: 'Note de calcul',
    AppLanguage.english: 'Calculation note',
  },
  'ملاحظة خاصة بالسلسلة': {
    AppLanguage.arabic: 'ملاحظة خاصة بالسلسلة',
    AppLanguage.french: 'Note spécifique à la gamme',
    AppLanguage.english: 'Series-specific note',
  },
  'اكتب سبب التصحيح أو طريقة الحساب': {
    AppLanguage.arabic: 'اكتب سبب التصحيح أو طريقة الحساب',
    AppLanguage.french: 'Écrivez la raison de la correction ou la méthode de calcul',
    AppLanguage.english: 'Write the reason for the correction or the calculation method',
  },
  'تصحيح العرض (مم)': {
    AppLanguage.arabic: 'تصحيح العرض (مم)',
    AppLanguage.french: 'Correction de largeur (mm)',
    AppLanguage.english: 'Width correction (mm)',
  },
  'تصحيح الارتفاع (مم)': {
    AppLanguage.arabic: 'تصحيح الارتفاع (مم)',
    AppLanguage.french: 'Correction de hauteur (mm)',
    AppLanguage.english: 'Height correction (mm)',
  },
  'خصم عرض ضلفتين (مم)': {
    AppLanguage.arabic: 'خصم عرض ضلفتين (مم)',
    AppLanguage.french: 'Déduction de largeur pour deux vantaux (mm)',
    AppLanguage.english: 'Two-sash width deduction (mm)',
  },
  'خصم عرض 3 ضلفات (مم)': {
    AppLanguage.arabic: 'خصم عرض 3 ضلفات (مم)',
    AppLanguage.french: 'Déduction de largeur pour 3 vantaux (mm)',
    AppLanguage.english: 'Three-sash width deduction (mm)',
  },
  'خصم عرض 4 ضلفات (مم)': {
    AppLanguage.arabic: 'خصم عرض 4 ضلفات (مم)',
    AppLanguage.french: 'Déduction de largeur pour 4 vantaux (mm)',
    AppLanguage.english: 'Four-sash width deduction (mm)',
  },
  'خلوص تركيب السكة (مم)': {
    AppLanguage.arabic: 'خلوص تركيب السكة (مم)',
    AppLanguage.french: "Jeu d'installation du rail (mm)",
    AppLanguage.english: 'Rail installation clearance (mm)',
  },
  'تداخل طول الضلفة (مم)': {
    AppLanguage.arabic: 'تداخل طول الضلفة (مم)',
    AppLanguage.french: 'Recouvrement de longueur du vantail (mm)',
    AppLanguage.english: 'Sash length overlap (mm)',
  },
  'خصم أمان عرض الزجاج (مم)': {
    AppLanguage.arabic: 'خصم أمان عرض الزجاج (مم)',
    AppLanguage.french: 'Déduction de sécurité de largeur du verre (mm)',
    AppLanguage.english: 'Glass width safety deduction (mm)',
  },
  'الباكلوز': {
    AppLanguage.arabic: 'الباكلوز',
    AppLanguage.french: 'Parclose',
    AppLanguage.english: 'Glazing bead',
  },
  'غطاء جانبي مدمج': {
    AppLanguage.arabic: 'غطاء جانبي مدمج',
    AppLanguage.french: 'Couvre-joint latéral intégré',
    AppLanguage.english: 'Integrated side cover',
  },
  'حامل الجوان': {
    AppLanguage.arabic: 'حامل الجوان',
    AppLanguage.french: 'Porte-joint',
    AppLanguage.english: 'Gasket holder',
  },
  'جوان البروس يحسب بطول ضعفي حامل الجوان.': {
    AppLanguage.arabic: 'جوان البروس يحسب بطول ضعفي حامل الجوان.',
    AppLanguage.french: 'Le joint brosse est calculé sur deux fois la longueur du porte-joint.',
    AppLanguage.english: 'The brush gasket is calculated at twice the holder length.',
  },
  'قاش': {
    AppLanguage.arabic: 'قاش',
    AppLanguage.french: 'Parclose',
    AppLanguage.english: 'Glazing bead',
  },
  'الفيس المرتبط بهذا العنصر': {
    AppLanguage.arabic: 'الفيس المرتبط بهذا العنصر',
    AppLanguage.french: 'Vis liée à cet élément',
    AppLanguage.english: 'Screw linked to this item',
  },
  'عدد الفيس لهذا العنصر': {
    AppLanguage.arabic: 'عدد الفيس لهذا العنصر',
    AppLanguage.french: 'Nombre de vis pour cet élément',
    AppLanguage.english: 'Number of screws for this item',
  },
  'عدد القاش المرتبط': {
    AppLanguage.arabic: 'عدد القاش المرتبط',
    AppLanguage.french: 'Quantité de parclose liée',
    AppLanguage.english: 'Linked glazing-bead quantity',
  },
  'عدد القاش لهذا الأكسسوار': {
    AppLanguage.arabic: 'عدد القاش لهذا الأكسسوار',
    AppLanguage.french: "Quantité de parclose pour cet accessoire",
    AppLanguage.english: 'Glazing-bead quantity for this accessory',
  },
  'سيتم فصل الشراء تلقائيًا إلى وثيقتين:': {
    AppLanguage.arabic: 'سيتم فصل الشراء تلقائيًا إلى وثيقتين:',
    AppLanguage.french: "L'achat sera automatiquement séparé en deux documents :",
    AppLanguage.english: 'The purchase will be automatically split into two documents:',
  },
  'يمكن تعديل كل وثيقة بعد إنشائها.': {
    AppLanguage.arabic: 'يمكن تعديل كل وثيقة بعد إنشائها.',
    AppLanguage.french: 'Chaque document peut être modifié après sa création.',
    AppLanguage.english: 'Each document can be edited after creation.',
  },
  'تُنشأ بالعناصر المحسوبة وقابلة للتعديل.': {
    AppLanguage.arabic: 'تُنشأ بالعناصر المحسوبة وقابلة للتعديل.',
    AppLanguage.french: 'Créées avec les éléments calculés et modifiables.',
    AppLanguage.english: 'Created with calculated, editable items.',
  },
  'إضافة': {
    AppLanguage.arabic: 'إضافة',
    AppLanguage.french: 'Ajouter',
    AppLanguage.english: 'Add',
  },
  'Order': {
    AppLanguage.arabic: 'طلبية',
    AppLanguage.french: 'Commande',
    AppLanguage.english: 'Order',
  },
  'Phone': {
    AppLanguage.arabic: 'الهاتف',
    AppLanguage.french: 'Téléphone',
    AppLanguage.english: 'Phone',
  },
  'Address': {
    AppLanguage.arabic: 'العنوان',
    AppLanguage.french: 'Adresse',
    AppLanguage.english: 'Address',
  },
  'Global': {
    AppLanguage.arabic: 'عام',
    AppLanguage.french: 'Global',
    AppLanguage.english: 'Global',
  },
  'Please add products': {
    AppLanguage.arabic: 'يرجى إضافة منتجات',
    AppLanguage.french: 'Veuillez ajouter des produits',
    AppLanguage.english: 'Please add products',
  },
  'إكسسوارات السلاسل': {
    AppLanguage.arabic: 'إكسسوارات السلاسل',
    AppLanguage.french: 'Accessoires des gammes',
    AppLanguage.english: 'Series accessories',
  },
  'الالوان': {
    AppLanguage.arabic: 'الألوان',
    AppLanguage.french: 'Couleurs',
    AppLanguage.english: 'Colours',
  },
  'الاجوانات / الجلادات': {
    AppLanguage.arabic: 'الجوانات / الجلادات',
    AppLanguage.french: 'Joints / garnitures',
    AppLanguage.english: 'Gaskets / seals',
  },
  'السماكة': {
    AppLanguage.arabic: 'السماكة',
    AppLanguage.french: 'Épaisseur',
    AppLanguage.english: 'Thickness',
  },
  'إضافة جوان جديد': {
    AppLanguage.arabic: 'إضافة جوان جديد',
    AppLanguage.french: 'Ajouter un nouveau joint',
    AppLanguage.english: 'Add new gasket',
  },
  'سعر المتر': {
    AppLanguage.arabic: 'سعر المتر',
    AppLanguage.french: 'Prix au mètre',
    AppLanguage.english: 'Price per metre',
  },
  'مجموعات الكيت (Kit)': {
    AppLanguage.arabic: 'مجموعات الكيت (Kit)',
    AppLanguage.french: 'Groupes de kits',
    AppLanguage.english: 'Kit bundles',
  },
  'الاختيار الافتراضي': {
    AppLanguage.arabic: 'الاختيار الافتراضي',
    AppLanguage.french: 'Sélection par défaut',
    AppLanguage.english: 'Default selection',
  },
  'الباقي': {
    AppLanguage.arabic: 'الباقي',
    AppLanguage.french: 'Reste',
    AppLanguage.english: 'Remainder',
  },
  'الدور / العنوان': {
    AppLanguage.arabic: 'الدور / العنوان',
    AppLanguage.french: 'Rôle / titre',
    AppLanguage.english: 'Role / title',
  },
  'الزجاج (Verre)': {
    AppLanguage.arabic: 'الزجاج',
    AppLanguage.french: 'Verre',
    AppLanguage.english: 'Glass',
  },
  'القاش المرتبط بالقفل': {
    AppLanguage.arabic: 'القاش المرتبط بالقفل',
    AppLanguage.french: 'Parclose liée à la serrure',
    AppLanguage.english: 'Glazing bead linked to lock',
  },
  'القاش المرتبط بهذا القفل/الأكسسوار': {
    AppLanguage.arabic: 'القاش المرتبط بهذا القفل/الأكسسوار',
    AppLanguage.french: "Parclose liée à cette serrure/accessoire",
    AppLanguage.english: 'Glazing bead linked to this lock/accessory',
  },
  'بدون فيس مرتبط': {
    AppLanguage.arabic: 'بدون فيس مرتبط',
    AppLanguage.french: 'Aucune vis liée',
    AppLanguage.english: 'No linked screw',
  },
  'بدون قاش مرتبط': {
    AppLanguage.arabic: 'بدون قاش مرتبط',
    AppLanguage.french: 'Aucune parclose liée',
    AppLanguage.english: 'No linked glazing bead',
  },
  'بروفيلات السلسلة': {
    AppLanguage.arabic: 'بروفيلات السلسلة',
    AppLanguage.french: 'Profilés de la gamme',
    AppLanguage.english: 'Series profiles',
  },
  'عرض بيانات الزبون': {
    AppLanguage.arabic: 'عرض بيانات الزبون',
    AppLanguage.french: 'Afficher les données du client',
    AppLanguage.english: 'Show customer details',
  },
  'غطاء مدمج': {
    AppLanguage.arabic: 'غطاء مدمج',
    AppLanguage.french: 'Couvre-joint intégré',
    AppLanguage.english: 'Integrated cover',
  },
  'غير مرتبط بسماكة الزجاج': {
    AppLanguage.arabic: 'غير مرتبط بسماكة الزجاج',
    AppLanguage.french: "Non lié à l'épaisseur du verre",
    AppLanguage.english: 'Not linked to glass thickness',
  },
  'قطاعات الألمنيوم (Aluminium)': {
    AppLanguage.arabic: 'قطاعات الألمنيوم',
    AppLanguage.french: 'Profilés aluminium',
    AppLanguage.english: 'Aluminium profiles',
  },
  'قطع الشيكان لكل فاصل': {
    AppLanguage.arabic: 'قطع الشيكان لكل فاصل',
    AppLanguage.french: 'Pièces de chicane par séparation',
    AppLanguage.english: 'Chicane pieces per divider',
  },
  'كل أنواع الزجاج': {
    AppLanguage.arabic: 'كل أنواع الزجاج',
    AppLanguage.french: 'Tous les types de vitrage',
    AppLanguage.english: 'All glass types',
  },
  'نافذة التغيير': {
    AppLanguage.arabic: 'نافذة التغيير',
    AppLanguage.french: 'Fenêtre de modification',
    AppLanguage.english: 'Change window',
  },
  'زجاج مفرد فقط': {
    AppLanguage.arabic: 'زجاج مفرد فقط',
    AppLanguage.french: 'Vitrage simple uniquement',
    AppLanguage.english: 'Single glass only',
  },
  'زجاج مزدوج فقط': {
    AppLanguage.arabic: 'زجاج مزدوج فقط',
    AppLanguage.french: 'Double vitrage uniquement',
    AppLanguage.english: 'Double glass only',
  },
  'سطر': {
    AppLanguage.arabic: 'سطر',
    AppLanguage.french: 'Ligne',
    AppLanguage.english: 'Row',
  },
  'لا توجد عناصر لهذا العنوان في قاعدة البيانات.': {
    AppLanguage.arabic: 'لا توجد عناصر لهذا العنوان في قاعدة البيانات.',
    AppLanguage.french: 'Aucun élément pour ce titre dans la base de données.',
    AppLanguage.english: 'No items for this title in the database.',
  },
  'لا يقبل كوفرجوا': {
    AppLanguage.arabic: 'لا يقبل كوفرجوا',
    AppLanguage.french: 'N’accepte pas de couvre-joint',
    AppLanguage.english: 'Does not accept a cover joint',
  },
  'مثال: +5 أو -6': {
    AppLanguage.arabic: 'مثال: +5 أو -6',
    AppLanguage.french: 'Exemple : +5 ou -6',
    AppLanguage.english: 'Example: +5 or -6',
  },
  'مثال: +60 أو -10': {
    AppLanguage.arabic: 'مثال: +60 أو -10',
    AppLanguage.french: 'Exemple : +60 ou -10',
    AppLanguage.english: 'Example: +60 or -10',
  },
  'مثال: 3,4,5,6': {
    AppLanguage.arabic: 'مثال: 3,4,5,6',
    AppLanguage.french: 'Exemple : 3,4,5,6',
    AppLanguage.english: 'Example: 3,4,5,6',
  },
  'يُختار تلقائياً عند توفر هذا النوع': {
    AppLanguage.arabic: 'يُختار تلقائياً عند توفر هذا النوع',
    AppLanguage.french: 'Sélectionné automatiquement si ce type est disponible',
    AppLanguage.english: 'Selected automatically when this type is available',
  },
  'يرجى تحديد ألوان النظام أولاً من تبويب \'ألوان الأنظمة\'.': {
    AppLanguage.arabic: 'يرجى تحديد ألوان النظام أولاً من تبويب ألوان الأنظمة.',
    AppLanguage.french: "Sélectionnez d'abord les couleurs du système dans l'onglet « Couleurs des systèmes ».",
    AppLanguage.english: 'First select the system colours in the System Colours tab.',
  },
  'يستعمل تلقائياً مع البلانت': {
    AppLanguage.arabic: 'يستعمل تلقائياً مع البلانت',
    AppLanguage.french: 'Utilisé automatiquement avec la plinthe',
    AppLanguage.english: 'Used automatically with plinth',
  },
  'يقبل كوفرجوا منفصل': {
    AppLanguage.arabic: 'يقبل كوفرجوا منفصل',
    AppLanguage.french: 'Accepte un couvre-joint séparé',
    AppLanguage.english: 'Accepts a separate cover joint',
  },
  'توزيع المهام على العمال (إسناد الورشة)': {
    AppLanguage.arabic: 'توزيع المهام على العمال (إسناد الورشة)',
    AppLanguage.french: 'Répartition des tâches aux ouvriers (atelier)',
    AppLanguage.english: 'Assign tasks to workers (workshop)',
  },
  'تم حفظ تعريف مكوّنات السلسلة.': {
    AppLanguage.arabic: 'تم حفظ تعريف مكوّنات السلسلة.',
    AppLanguage.french: 'La définition des composants de la gamme a été enregistrée.',
    AppLanguage.english: 'Series component definition saved.',
  },
  'تم حفظ قواعد الكتالوج العامة.': {
    AppLanguage.arabic: 'تم حفظ قواعد الكتالوج العامة.',
    AppLanguage.french: 'Les règles générales du catalogue ont été enregistrées.',
    AppLanguage.english: 'General catalogue rules saved.',
  },
  'تعذر حفظ قواعد الكتالوج': {
    AppLanguage.arabic: 'تعذر حفظ قواعد الكتالوج',
    AppLanguage.french: 'Impossible d’enregistrer les règles du catalogue',
    AppLanguage.english: 'Could not save catalogue rules',
  },
  'تعذر حفظ ارتباط الأكسسوار': {
    AppLanguage.arabic: 'تعذر حفظ ارتباط الأكسسوار',
    AppLanguage.french: 'Impossible d’enregistrer le lien de l’accessoire',
    AppLanguage.english: 'Could not save accessory link',
  },
  'تعذر إنشاء وثيقة الشراء:': {
    AppLanguage.arabic: 'تعذر إنشاء وثيقة الشراء:',
    AppLanguage.french: 'Impossible de créer le document d’achat :',
    AppLanguage.english: 'Could not create the purchase document:',
  },
  'تم إنشاء وثائق الشراء:': {
    AppLanguage.arabic: 'تم إنشاء وثائق الشراء:',
    AppLanguage.french: 'Documents d’achat créés :',
    AppLanguage.english: 'Purchase documents created:',
  },
  'أضف مورّدًا ومكان تخزين قبل إنشاء طلب الشراء.': {
    AppLanguage.arabic: 'أضف مورّدًا ومكان تخزين قبل إنشاء طلب الشراء.',
    AppLanguage.french: 'Ajoutez un fournisseur et un emplacement avant de créer la demande d’achat.',
    AppLanguage.english: 'Add a supplier and storage location before creating the purchase order.',
  },
  'يمكن مراجعته وتأكيده لاحقًا دون إدخال المخزون.': {
    AppLanguage.arabic: 'يمكن مراجعته وتأكيده لاحقًا دون إدخال المخزون.',
    AppLanguage.french: 'Il peut être vérifié et confirmé plus tard sans mouvement de stock.',
    AppLanguage.english: 'It can be reviewed and confirmed later without entering stock.',
  },
  'مكمل الإطار': {
    AppLanguage.arabic: 'مكمل الإطار',
    AppLanguage.french: 'Complément dormant',
    AppLanguage.english: 'Frame extension',
  },
  'بروفيل زاوية': {
    AppLanguage.arabic: 'بروفيل زاوية',
    AppLanguage.french: "Profil d'angle",
    AppLanguage.english: 'Corner profile',
  },
  'كانيڤو': {
    AppLanguage.arabic: 'كانيڤو',
    AppLanguage.french: 'Caniveau',
    AppLanguage.english: 'Drain channel',
  },
  'غطاء الكانيڤو': {
    AppLanguage.arabic: 'غطاء الكانيڤو',
    AppLanguage.french: 'Cache-caniveau',
    AppLanguage.english: 'Drain-channel cover',
  },
  'مكمل الضلفة': {
    AppLanguage.arabic: 'مكمل الضلفة',
    AppLanguage.french: 'Complément ouvrant',
    AppLanguage.english: 'Sash extension',
  },
  'قائم جانبي منزلق': {
    AppLanguage.arabic: 'قائم جانبي منزلق',
    AppLanguage.french: 'Montant latéral coulissant',
    AppLanguage.english: 'Sliding side stile',
  },
  'قائم وسطي منزلق': {
    AppLanguage.arabic: 'قائم وسطي منزلق',
    AppLanguage.french: 'Montant central coulissant',
    AppLanguage.english: 'Sliding central stile',
  },
  'قائم وسطي Slim': {
    AppLanguage.arabic: 'قائم وسطي Slim',
    AppLanguage.french: 'Montant central Slim',
    AppLanguage.english: 'Slim central stile',
  },
  'سكة / ترافيرس الضلفة': {
    AppLanguage.arabic: 'سكة / ترافيرس الضلفة',
    AppLanguage.french: 'Traverse ouvrant coulissant',
    AppLanguage.english: 'Sliding sash rail / transom',
  },
  'مكمل علوي وسفلي': {
    AppLanguage.arabic: 'مكمل علوي وسفلي',
    AppLanguage.french: 'Complément haut et bas',
    AppLanguage.english: 'Top and bottom extension',
  },
  'باغيت / غطاء الزجاج': {
    AppLanguage.arabic: 'باغيت / غطاء الزجاج',
    AppLanguage.french: 'Parclose',
    AppLanguage.english: 'Glazing bead',
  },
  'Cache-rainure': {
    AppLanguage.arabic: 'غطاء المجرى',
    AppLanguage.french: 'Cache-rainure',
    AppLanguage.english: 'Groove cover',
  },
  'Cache-rail': {
    AppLanguage.arabic: 'غطاء السكة',
    AppLanguage.french: 'Cache-rail',
    AppLanguage.english: 'Rail cover',
  },
  'Bavette': {
    AppLanguage.arabic: 'بافيت',
    AppLanguage.french: 'Bavette',
    AppLanguage.english: 'Drip trim',
  },
  'Seuil': {
    AppLanguage.arabic: 'عتبة',
    AppLanguage.french: 'Seuil',
    AppLanguage.english: 'Sill',
  },
  'التقسيم': {
    AppLanguage.arabic: 'التقسيم',
    AppLanguage.french: 'Traverse / montant',
    AppLanguage.english: 'Mullion / divider',
  },
  'الغطاء الجانبي': {
    AppLanguage.arabic: 'الغطاء الجانبي',
    AppLanguage.french: 'Couvre-joint',
    AppLanguage.english: 'Side cover',
  },
  'البرداج': {
    AppLanguage.arabic: 'البرداج',
    AppLanguage.french: 'Bardage',
    AppLanguage.english: 'Cladding',
  },
  'الباتمو': {
    AppLanguage.arabic: 'الباتمو',
    AppLanguage.french: 'Battement',
    AppLanguage.english: 'Meeting stile',
  },
  'البلانت': {
    AppLanguage.arabic: 'البلانت',
    AppLanguage.french: 'Plinthe',
    AppLanguage.english: 'Plinth',
  },
  'السكة': {
    AppLanguage.arabic: 'السكة',
    AppLanguage.french: 'Rail',
    AppLanguage.english: 'Rail',
  },
  'الشيكان': {
    AppLanguage.arabic: 'الشيكان',
    AppLanguage.french: 'Chicane',
    AppLanguage.english: 'Interlocking stile',
  },
  'مخفض الزجاج': {
    AppLanguage.arabic: 'مخفض الزجاج',
    AppLanguage.french: 'Réducteur',
    AppLanguage.english: 'Glass reducer',
  },
  'مقطع خاص آخر': {
    AppLanguage.arabic: 'مقطع خاص آخر',
    AppLanguage.french: 'Autre profil spécifique',
    AppLanguage.english: 'Other custom profile',
  },
  'حديد الدعم': {
    AppLanguage.arabic: 'حديد الدعم',
    AppLanguage.french: 'Renfort',
    AppLanguage.english: 'Reinforcement',
  },
  'غطاء التعزيز': {
    AppLanguage.arabic: 'غطاء التعزيز',
    AppLanguage.french: 'Cache renfort',
    AppLanguage.english: 'Reinforcement cover',
  },
  'غطاء الإطار الثابت': {
    AppLanguage.arabic: 'غطاء الإطار الثابت',
    AppLanguage.french: 'Cache dormant',
    AppLanguage.english: 'Fixed-frame cover',
  },
  'اختر القاش': {
    AppLanguage.arabic: 'اختر القاش',
    AppLanguage.french: 'Choisir la parclose',
    AppLanguage.english: 'Select glazing bead',
  },
  'اختر المورّد': {
    AppLanguage.arabic: 'اختر المورّد',
    AppLanguage.french: 'Choisir le fournisseur',
    AppLanguage.english: 'Select supplier',
  },
  'اختر سلسلة': {
    AppLanguage.arabic: 'اختر سلسلة',
    AppLanguage.french: 'Choisir une gamme',
    AppLanguage.english: 'Select a series',
  },
  'حدد الإطار لهذه السلسلة أولاً.': {
    AppLanguage.arabic: 'حدد الإطار لهذه السلسلة أولاً.',
    AppLanguage.french: 'Choisissez d’abord le dormant de cette gamme.',
    AppLanguage.english: 'Select the frame for this series first.',
  },
  'تفعيل الزر لفتح تخصيص العنصر ودوره.': {
    AppLanguage.arabic: 'فعّل الزر لفتح تخصيص العنصر ودوره.',
    AppLanguage.french: 'Activez le bouton pour personnaliser l’élément et son rôle.',
    AppLanguage.english: 'Enable the button to customise the item and its role.',
  },
  'فعّل الزر لفتح تخصيص العنصر ودوره.': {
    AppLanguage.arabic: 'فعّل الزر لفتح تخصيص العنصر ودوره.',
    AppLanguage.french: 'Activez le bouton pour personnaliser l’élément et son rôle.',
    AppLanguage.english: 'Enable the button to customise the item and its role.',
  },
  'حدد المقاطع التي تستعملها السلسلة. عند اختيار سلسلة منزلقة تظهر هنا حسابات عرض الضلفة لكل حالتين أو ثلاث أو أربع ضلفات، وتستعمل في الرسم وحساب الكميات.': {
    AppLanguage.arabic: 'حدد المقاطع التي تستعملها السلسلة. عند اختيار سلسلة منزلقة تظهر هنا حسابات عرض الضلفة لكل حالتين أو ثلاث أو أربع ضلفات، وتستعمل في الرسم وحساب الكميات.',
    AppLanguage.french: 'Définissez les profilés utilisés par la gamme. Pour une gamme coulissante, les calculs de largeur pour 2, 3 ou 4 vantaux sont utilisés par le dessin et les quantités.',
    AppLanguage.english: 'Define the profiles used by the series. For a sliding series, sash-width calculations for 2, 3 or 4 sashes are used by the drawing and quantities.',
  },
  'حدد ما تستعمله السلسلة فعلاً. يمكن اختيار أكثر من مقطع لنفس الدور؛ اضغط مطولاً على المقطع المختار لجعله الافتراضي.': {
    AppLanguage.arabic: 'حدد ما تستعمله السلسلة فعلاً. يمكن اختيار أكثر من مقطع لنفس الدور؛ اضغط مطولاً على المقطع المختار لجعله الافتراضي.',
    AppLanguage.french: 'Sélectionnez ce que la gamme utilise réellement. Plusieurs profilés sont possibles par rôle ; maintenez un profil sélectionné pour le définir par défaut.',
    AppLanguage.english: 'Select what the series actually uses. Multiple profiles may be selected for one role; long-press a selected profile to make it the default.',
  },
  'ربط أنواع الجوانات': {
    AppLanguage.arabic: 'ربط أنواع الجوانات',
    AppLanguage.french: 'Lier les types de joints',
    AppLanguage.english: 'Link gasket types',
  },
  'هذا الدور لا يتغير بين زجاج مفرد ومزدوج.': {
    AppLanguage.arabic: 'هذا الدور لا يتغير بين زجاج مفرد ومزدوج.',
    AppLanguage.french: 'Ce rôle ne change pas entre vitrage simple et double.',
    AppLanguage.english: 'This role does not change between single and double glazing.',
  },
  'هذه الضلفة بدون بيركلوز': {
    AppLanguage.arabic: 'هذه الضلفة بدون بيركلوز',
    AppLanguage.french: 'Cet ouvrant est sans parclose',
    AppLanguage.english: 'This sash has no glazing bead',
  },
  'وباقي العناصر': {
    AppLanguage.arabic: 'وباقي العناصر',
    AppLanguage.french: 'Et les autres éléments',
    AppLanguage.english: 'And the remaining items',
  },
  'صنف مرتبط سيُضاف إلى الوثيقة': {
    AppLanguage.arabic: 'صنف مرتبط سيُضاف إلى الوثيقة',
    AppLanguage.french: 'Article lié à ajouter au document',
    AppLanguage.english: 'Linked item to add to the document',
  },
  'عدد البراغي يؤخذ من حقل عدد البراغي في الأكسسوار': {
    AppLanguage.arabic: 'عدد البراغي يؤخذ من حقل عدد البراغي في الأكسسوار',
    AppLanguage.french: 'Le nombre de vis provient du champ de l’accessoire.',
    AppLanguage.english: 'The screw quantity is taken from the accessory screw-count field.',
  },
  'سيتم حفظ الفضلة كسجل هدر مع إبقاء رقمها وأثرها، ولن تُحذف نهائيًا. هل تريد المتابعة؟': {
    AppLanguage.arabic: 'سيتم حفظ الفضلة كسجل هدر مع إبقاء رقمها وأثرها، ولن تُحذف نهائيًا. هل تريد المتابعة؟',
    AppLanguage.french: 'La chute sera conservée comme perte avec son numéro et sa traçabilité ; elle ne sera pas supprimée. Continuer ?',
    AppLanguage.english: 'The remnant will be kept as a waste record with its number and audit trail; it will not be deleted. Continue?',
  },
  'استخدام البراغي:': {
    AppLanguage.arabic: 'استخدام البراغي:',
    AppLanguage.french: 'Utilisation des vis :',
    AppLanguage.english: 'Screw usage:',
  },
  'نوع اللاش:': {
    AppLanguage.arabic: 'نوع اللاش:',
    AppLanguage.french: 'Type de gâche :',
    AppLanguage.english: 'Strike type:',
  },
  'نوع القفل:': {
    AppLanguage.arabic: 'نوع القفل:',
    AppLanguage.french: 'Type de serrure :',
    AppLanguage.english: 'Lock type:',
  },
  'Gache Simple Ouvrant': {
    AppLanguage.arabic: 'قاش ضلفة مفرد',
    AppLanguage.french: 'Gâche simple ouvrant',
    AppLanguage.english: 'Single-sash strike',
  },
  'Gache Double Ouvrant': {
    AppLanguage.arabic: 'قاش ضلفتين',
    AppLanguage.french: 'Gâche double ouvrant',
    AppLanguage.english: 'Double-sash strike',
  },
  'Gache Porte': {
    AppLanguage.arabic: 'قاش باب',
    AppLanguage.french: 'Gâche de porte',
    AppLanguage.english: 'Door strike',
  },
  '1. اختر البروفيل': {
    AppLanguage.arabic: '1. اختر البروفيل',
    AppLanguage.french: '1. Choisissez le profilé',
    AppLanguage.english: '1. Select the profile',
  },
  'Libellé / Description': {
    AppLanguage.arabic: 'الاسم / الوصف',
    AppLanguage.french: 'Libellé / Description',
    AppLanguage.english: 'Label / Description',
  },
  'Unique (Per Series)': {
    AppLanguage.arabic: 'فريد (لكل سلسلة)',
    AppLanguage.french: 'Unique (par gamme)',
    AppLanguage.english: 'Unique (per series)',
  },
  'Saved successfully!': {
    AppLanguage.arabic: 'تم الحفظ بنجاح!',
    AppLanguage.french: 'Enregistré avec succès !',
    AppLanguage.english: 'Saved successfully!',
  },
  'لا توجد بيانات': {
    AppLanguage.arabic: 'لا توجد بيانات',
    AppLanguage.french: 'Aucune donnée',
    AppLanguage.english: 'No data',
  },
  'إعدادات التراينغل': {
    AppLanguage.arabic: 'إعدادات التراينغل',
    AppLanguage.french: 'Paramètres du triangle',
    AppLanguage.english: 'Triangle settings',
  },
  'الدور': {
    AppLanguage.arabic: 'الدور',
    AppLanguage.french: 'Rôle',
    AppLanguage.english: 'Role',
  },
  'الخصم من طول الظلفة (مم)': {
    AppLanguage.arabic: 'الخصم من طول الظلفة (مم)',
    AppLanguage.french: 'Déduction de longueur du vantail (mm)',
    AppLanguage.english: 'Sash length deduction (mm)',
  },
  'نوع البرغي': {
    AppLanguage.arabic: 'نوع البرغي',
    AppLanguage.french: 'Type de vis',
    AppLanguage.english: 'Screw type',
  },
  'الطلبية': {
    AppLanguage.arabic: 'الطلبية',
    AppLanguage.french: 'Commande',
    AppLanguage.english: 'Order',
  },
  'اختر سلسلة، ثم حدد مقاطعها الأساسية. سيتم اعتماد صياغة الجدول لاحقًا بشكل مستقل.': {
    AppLanguage.arabic: 'اختر سلسلة، ثم حدد مقاطعها الأساسية. سيتم اعتماد صياغة الجدول لاحقًا بشكل مستقل.',
    AppLanguage.french: 'Choisissez une gamme, puis ses profilés principaux. Le format du tableau sera défini séparément ultérieurement.',
    AppLanguage.english: 'Select a series, then its main profiles. The table format will be defined separately later.',
  },
  'الإكسسوارات (Accessoires)': {
    AppLanguage.arabic: 'الإكسسوارات',
    AppLanguage.french: 'Accessoires',
    AppLanguage.english: 'Accessories',
  },
  'قواعد الأكسسوارات والجوانات': {
    AppLanguage.arabic: 'قواعد الأكسسوارات والجوانات',
    AppLanguage.french: 'Règles des accessoires et des joints',
    AppLanguage.english: 'Accessory and gasket rules',
  },
  'لا توجد أنواع جوانات ألمنيوم في الكتالوج.': {
    AppLanguage.arabic: 'لا توجد أنواع جوانات ألمنيوم في الكتالوج.',
    AppLanguage.french: 'Aucun type de joint aluminium dans le catalogue.',
    AppLanguage.english: 'No aluminium gasket types in the catalogue.',
  },
  'لا توجد سلاسل في هذا البروفيل.': {
    AppLanguage.arabic: 'لا توجد سلاسل في هذا البروفيل.',
    AppLanguage.french: 'Aucune gamme pour ce profilé.',
    AppLanguage.english: 'No series for this profile.',
  },
  'ليس لديك صلاحية إنشاء المشتريات': {
    AppLanguage.arabic: 'ليس لديك صلاحية إنشاء المشتريات',
    AppLanguage.french: 'Vous n’avez pas l’autorisation de créer des achats',
    AppLanguage.english: 'You are not authorised to create purchases',
  },
  'ليس لديك صلاحية للوصول إلى إعدادات السلسلة.': {
    AppLanguage.arabic: 'ليس لديك صلاحية للوصول إلى إعدادات السلسلة.',
    AppLanguage.french: 'Vous n’avez pas accès aux paramètres de la gamme.',
    AppLanguage.english: 'You do not have permission to access series settings.',
  },
  'ليس لديك صلاحية للوصول إلى قواعد الكتالوج.': {
    AppLanguage.arabic: 'ليس لديك صلاحية للوصول إلى قواعد الكتالوج.',
    AppLanguage.french: 'Vous n’avez pas accès aux règles du catalogue.',
    AppLanguage.english: 'You do not have permission to access catalogue rules.',
  },
};
