import '../app_settings.dart';

/// Localization keys for recently added features:
/// 1. Shutter Split and its Dialog (فصل وتقسيم الصناديق)
/// 2. Montant reinforcement options in Add/Edit Series (استبدال نوع تدعيم المونطو)
/// 3. Cutting optimization screen, params, dashboard & PDF (تحسين وتقطيع البروفيلات)
/// 4. Subscriptions Review, Electronic Payment & BaridiMob (الاشتراكات والدفع الإلكتروني)
const Map<String, Map<AppLanguage, String>> translationPhase11Keys = {
  // ── 1. تدعيم المونتور في السلاسل (Montant Reinforcement) ──
  'نوع تدعيم المونطو (Type de Renfort)': {
    AppLanguage.arabic: 'نوع تدعيم المونطو (Type de Renfort)',
    AppLanguage.french: 'Type de renfort montant',
    AppLanguage.english: 'Mullion reinforcement type',
  },
  'نوع تدعيم المونطو': {
    AppLanguage.arabic: 'نوع تدعيم المونطو',
    AppLanguage.french: 'Type de renfort montant',
    AppLanguage.english: 'Mullion reinforcement type',
  },
  'استبدال كامل للمقطع (Full Substitution - مثل TPR)': {
    AppLanguage.arabic: 'استبدال كامل للمقطع (Full Substitution - مثل TPR)',
    AppLanguage.french: 'Substitution complète du profil (ex: TPR)',
    AppLanguage.english: 'Full profile substitution (e.g. TPR)',
  },
  'استبدال كامل للمقطع (مثل TPR)': {
    AppLanguage.arabic: 'استبدال كامل للمقطع (مثل TPR)',
    AppLanguage.french: 'Substitution complète du profil (ex: TPR)',
    AppLanguage.english: 'Full profile substitution (e.g. TPR)',
  },
  'شيكان مدعمة مدمجة (Chicane Renforcée)': {
    AppLanguage.arabic: 'شيكان مدعمة مدمجة (Chicane Renforcée)',
    AppLanguage.french: 'Chicane renforcée intégrée',
    AppLanguage.english: 'Integrated reinforced chicane',
  },
  'شيكان مدعمة مدمجة': {
    AppLanguage.arabic: 'شيكان مدعمة مدمجة',
    AppLanguage.french: 'Chicane renforcée intégrée',
    AppLanguage.english: 'Integrated reinforced chicane',
  },
  'عمود تدعيم مستقل ببراغي (Renfort Rapporté)': {
    AppLanguage.arabic: 'عمود تدعيم مستقل ببراغي (Renfort Rapporté)',
    AppLanguage.french: 'Renfort rapporté vissé',
    AppLanguage.english: 'Independent screwed reinforcement',
  },
  'عمود تدعيم مستقل ببراغي': {
    AppLanguage.arabic: 'عمود تدعيم مستقل ببراغي',
    AppLanguage.french: 'Renfort rapporté vissé',
    AppLanguage.english: 'Independent screwed reinforcement',
  },
  'لا تدعم التدعيم (Sans Renfort)': {
    AppLanguage.arabic: 'لا تدعم التدعيم (Sans Renfort)',
    AppLanguage.french: 'Sans renfort',
    AppLanguage.english: 'No reinforcement',
  },
  'لا تدعم التدعيم': {
    AppLanguage.arabic: 'لا تدعم التدعيم',
    AppLanguage.french: 'Sans renfort',
    AppLanguage.english: 'No reinforcement',
  },

  // ── 2. فصل الصناديق وحوارها (Shutter Box Splitting) ──
  'فصل الصناديق': {
    AppLanguage.arabic: 'فصل الصناديق',
    AppLanguage.french: 'Séparation des caissons',
    AppLanguage.english: 'Split shutter boxes',
  },
  'فصل وتقسيم صناديق الستار': {
    AppLanguage.arabic: 'فصل وتقسيم صناديق الستار',
    AppLanguage.french: 'Séparation et division des caissons',
    AppLanguage.english: 'Split and divide shutter boxes',
  },
  'الحالة: صندوق واحد موحد': {
    AppLanguage.arabic: 'الحالة: صندوق واحد موحد',
    AppLanguage.french: 'État : caisson unique unifié',
    AppLanguage.english: 'Status: unified single box',
  },
  'الحالة: مفصول إلى': {
    AppLanguage.arabic: 'الحالة: مفصول إلى',
    AppLanguage.french: 'État : séparé en',
    AppLanguage.english: 'Status: split into',
  },
  'صناديق مستقلة': {
    AppLanguage.arabic: 'صناديق مستقلة',
    AppLanguage.french: 'caissons indépendants',
    AppLanguage.english: 'independent boxes',
  },
  'صندوق لكل إطار': {
    AppLanguage.arabic: 'صندوق لكل إطار',
    AppLanguage.french: 'Un caisson par cadre',
    AppLanguage.english: 'One box per frame',
  },
  'تقسيم إطار واحد': {
    AppLanguage.arabic: 'تقسيم إطار واحد',
    AppLanguage.french: 'Division d\'un seul cadre',
    AppLanguage.english: 'Single frame division',
  },
  'التقسيم التلقائي يخصص صندوقاً مستقلاً ومحركاً ومجاري لكل إطار (بما في ذلك زاوية 90° دون إنقاص قياس الستار). يمكنك تعديل ارتفاع الستار للإطار الأقصر.': {
    AppLanguage.arabic: 'التقسيم التلقائي يخصص صندوقاً مستقلاً ومحركاً ومجاري لكل إطار (بما في ذلك زاوية 90° دون إنقاص قياس الستار). يمكنك تعديل ارتفاع الستار للإطار الأقصر.',
    AppLanguage.french: 'La séparation automatique attribue un caisson, un moteur et des coulisses indépendants par cadre (y compris profil d\'angle 90° sans déduction). Vous pouvez ajuster la hauteur du volet pour le cadre plus court.',
    AppLanguage.english: 'Automatic split allocates an independent box, motor and tracks per frame (including 90° corner profile without deduction). You can adjust shutter height for the shorter frame.',
  },
  'الإطارات المكتشفة': {
    AppLanguage.arabic: 'الإطارات المكتشفة',
    AppLanguage.french: 'Cadres détectés',
    AppLanguage.english: 'Detected frames',
  },
  'إطار': {
    AppLanguage.arabic: 'إطار',
    AppLanguage.french: 'Cadre',
    AppLanguage.english: 'Frame',
  },
  'العرض': {
    AppLanguage.arabic: 'العرض',
    AppLanguage.french: 'Largeur',
    AppLanguage.english: 'Width',
  },
  'ارتفاع الستار': {
    AppLanguage.arabic: 'ارتفاع الستار',
    AppLanguage.french: 'Hauteur du volet',
    AppLanguage.english: 'Shutter height',
  },
  'تقسيم الصندوق في إطار واحد إلى عدة أقسام مستقلة. الترتيب يبدأ من اليمين إلى اليسار.': {
    AppLanguage.arabic: 'تقسيم الصندوق في إطار واحد إلى عدة أقسام مستقلة. الترتيب يبدأ من اليمين إلى اليسار.',
    AppLanguage.french: 'Division du caisson d\'un seul cadre en plusieurs sections indépendantes. L\'ordre commence de droite à gauche.',
    AppLanguage.english: 'Divide single frame box into multiple independent sections. Order starts from right to left.',
  },
  'عدد الأقسام:': {
    AppLanguage.arabic: 'عدد الأقسام:',
    AppLanguage.french: 'Nombre de sections :',
    AppLanguage.english: 'Number of sections:',
  },
  'توزيع بالتساوي': {
    AppLanguage.arabic: 'توزيع بالتساوي',
    AppLanguage.french: 'Distribuer équitablement',
    AppLanguage.english: 'Distribute equally',
  },
  'الصندوق 1 (اليمين)': {
    AppLanguage.arabic: 'الصندوق 1 (اليمين)',
    AppLanguage.french: 'Caisson 1 (Droite)',
    AppLanguage.english: 'Box 1 (Right)',
  },
  'الصندوق': {
    AppLanguage.arabic: 'الصندوق',
    AppLanguage.french: 'Caisson',
    AppLanguage.english: 'Box',
  },
  'اليمين': {
    AppLanguage.arabic: 'اليمين',
    AppLanguage.french: 'Droite',
    AppLanguage.english: 'Right',
  },
  'اليسار': {
    AppLanguage.arabic: 'اليسار',
    AppLanguage.french: 'Gauche',
    AppLanguage.english: 'Left',
  },
  'الوسط': {
    AppLanguage.arabic: 'الوسط',
    AppLanguage.french: 'Centre',
    AppLanguage.english: 'Center',
  },
  'العرض الكلي للإطار': {
    AppLanguage.arabic: 'العرض الكلي للإطار',
    AppLanguage.french: 'Largeur totale du cadre',
    AppLanguage.english: 'Total frame width',
  },
  'العرض الكلي للإطار:': {
    AppLanguage.arabic: 'العرض الكلي للإطار:',
    AppLanguage.french: 'Largeur totale du cadre :',
    AppLanguage.english: 'Total frame width:',
  },
  'دمج الصناديق (إلغاء الفصل)': {
    AppLanguage.arabic: 'دمج الصناديق (إلغاء الفصل)',
    AppLanguage.french: 'Fusionner les caissons (Annuler)',
    AppLanguage.english: 'Merge boxes (Reset split)',
  },
  'تطبيق الفصل': {
    AppLanguage.arabic: 'تطبيق الفصل',
    AppLanguage.french: 'Appliquer la séparation',
    AppLanguage.english: 'Apply split',
  },
  'نوع الستار': {
    AppLanguage.arabic: 'نوع الستار',
    AppLanguage.french: 'Type de volet',
    AppLanguage.english: 'Shutter mechanism',
  },
  'نوع الستار:': {
    AppLanguage.arabic: 'نوع الستار:',
    AppLanguage.french: 'Type de volet :',
    AppLanguage.english: 'Shutter mechanism:',
  },
  'نوع الستار (Mechanism):': {
    AppLanguage.arabic: 'نوع الستار (Mechanism):',
    AppLanguage.french: 'Mécanisme du volet :',
    AppLanguage.english: 'Shutter mechanism:',
  },
  'جهة الستار': {
    AppLanguage.arabic: 'جهة الستار',
    AppLanguage.french: 'Côté commande',
    AppLanguage.english: 'Drive side',
  },
  'جهة الستار:': {
    AppLanguage.arabic: 'جهة الستار:',
    AppLanguage.french: 'Côté commande :',
    AppLanguage.english: 'Drive side:',
  },
  'جهة الستار (Drive Side):': {
    AppLanguage.arabic: 'جهة الستار (Drive Side):',
    AppLanguage.french: 'Côté commande :',
    AppLanguage.english: 'Drive side:',
  },
  'حزام': {
    AppLanguage.arabic: 'حزام',
    AppLanguage.french: 'Sangle',
    AppLanguage.english: 'Strap',
  },
  'حزام (Sangle)': {
    AppLanguage.arabic: 'حزام (Sangle)',
    AppLanguage.french: 'Sangle',
    AppLanguage.english: 'Strap',
  },
  'مانيفيل': {
    AppLanguage.arabic: 'مانيفيل',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank',
  },
  'منايفال': {
    AppLanguage.arabic: 'مانيفيل',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank',
  },
  'مانيفيل (Manivelle)': {
    AppLanguage.arabic: 'مانيفيل (Manivelle)',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank',
  },
  'محرك': {
    AppLanguage.arabic: 'محرك',
    AppLanguage.french: 'Moteur',
    AppLanguage.english: 'Motor',
  },
  'محرك (Moteur)': {
    AppLanguage.arabic: 'محرك (Moteur)',
    AppLanguage.french: 'Moteur',
    AppLanguage.english: 'Motor',
  },
  'يسار': {
    AppLanguage.arabic: 'يسار',
    AppLanguage.french: 'Gauche',
    AppLanguage.english: 'Left',
  },
  'يسار (Gauche)': {
    AppLanguage.arabic: 'يسار (Gauche)',
    AppLanguage.french: 'Gauche',
    AppLanguage.english: 'Left',
  },
  'يمين': {
    AppLanguage.arabic: 'يمين',
    AppLanguage.french: 'Droite',
    AppLanguage.english: 'Right',
  },
  'يمين (Droite)': {
    AppLanguage.arabic: 'يمين (Droite)',
    AppLanguage.french: 'Droite',
    AppLanguage.english: 'Right',
  },

  // ── خيارات تحديث التطبيق (App Update Settings) ──
  'تحديث التطبيق': {
    AppLanguage.arabic: 'تحديث التطبيق',
    AppLanguage.french: 'Mise à jour de l\'application',
    AppLanguage.english: 'App update',
  },
  'الإصدار الحالي:': {
    AppLanguage.arabic: 'الإصدار الحالي:',
    AppLanguage.french: 'Version actuelle :',
    AppLanguage.english: 'Current version:',
  },
  'طريقة التحديث:': {
    AppLanguage.arabic: 'طريقة التحديث:',
    AppLanguage.french: 'Mode de mise à jour :',
    AppLanguage.english: 'Update mode:',
  },
  'تحديث آلي (تلقائي)': {
    AppLanguage.arabic: 'تحديث آلي (تلقائي)',
    AppLanguage.french: 'Mise à jour automatique',
    AppLanguage.english: 'Automatic update',
  },
  'تحديث آلي': {
    AppLanguage.arabic: 'تحديث آلي',
    AppLanguage.french: 'Mise à jour automatique',
    AppLanguage.english: 'Automatic update',
  },
  'التحقق من التحديثات وتنزيلها تلقائياً عند توفر إصدار جديد.': {
    AppLanguage.arabic: 'التحقق من التحديثات وتنزيلها تلقائياً عند توفر إصدار جديد.',
    AppLanguage.french: 'Vérifier et télécharger automatiquement les mises à jour lorsqu\'une nouvelle version est disponible.',
    AppLanguage.english: 'Automatically check and download updates when a new version is available.',
  },
  'تحديث يدوي': {
    AppLanguage.arabic: 'تحديث يدوي',
    AppLanguage.french: 'Mise à jour manuelle',
    AppLanguage.english: 'Manual update',
  },
  'يتم التحديث فقط عند طلبك اليدوي بالضغط على زر الفحص.': {
    AppLanguage.arabic: 'يتم التحديث فقط عند طلبك اليدوي بالضغط على زر الفحص.',
    AppLanguage.french: 'Les mises à jour ne sont appliquées que sur demande manuelle.',
    AppLanguage.english: 'Updates are only checked and applied when manually requested.',
  },
  'التحقق من وجود تحديثات الآن': {
    AppLanguage.arabic: 'التحقق من وجود تحديثات الآن',
    AppLanguage.french: 'Vérifier les mises à jour',
    AppLanguage.english: 'Check for updates now',
  },
  'جارٍ التحقق من وجود تحديثات...': {
    AppLanguage.arabic: 'جارٍ التحقق من وجود تحديثات...',
    AppLanguage.french: 'Recherche de mises à jour...',
    AppLanguage.english: 'Checking for updates...',
  },
  'التطبيق محدّث': {
    AppLanguage.arabic: 'التطبيق محدّث',
    AppLanguage.french: 'Application à jour',
    AppLanguage.english: 'App is up to date',
  },
  'أنت تستخدم أحدث إصدار من التطبيق': {
    AppLanguage.arabic: 'أنت تستخدم أحدث إصدار من التطبيق',
    AppLanguage.french: 'Vous utilisez la dernière version de l\'application',
    AppLanguage.english: 'You are using the latest version of the application',
  },
  'حسناً': {
    AppLanguage.arabic: 'حسناً',
    AppLanguage.french: 'D\'accord',
    AppLanguage.english: 'OK',
  },

  // ── 3. تحسين وتقطيع البروفيلات (Cutting Optimization) ──
  'تحسين وتقطيع البروفيلات (Optimisation)': {
    AppLanguage.arabic: 'تحسين وتقطيع البروفيلات (Optimisation)',
    AppLanguage.french: 'Optimisation et découpe des profilés',
    AppLanguage.english: 'Profile cutting optimization',
  },
  'تحسين القص (Optimisation de Coupe)': {
    AppLanguage.arabic: 'تحسين القص (Optimisation de Coupe)',
    AppLanguage.french: 'Optimisation de coupe',
    AppLanguage.english: 'Cutting optimization',
  },
  'مخطط تحسين القص (Optimisation de Coupe)': {
    AppLanguage.arabic: 'مخطط تحسين القص (Optimisation de Coupe)',
    AppLanguage.french: 'Plan d\'optimisation de coupe',
    AppLanguage.english: 'Cutting optimization plan',
  },
  'تشغيل خوارزمية التحسين': {
    AppLanguage.arabic: 'تشغيل خوارزمية التحسين',
    AppLanguage.french: 'Lancer l\'optimisation',
    AppLanguage.english: 'Run optimization',
  },
  'إعادة الحساب والتحسين': {
    AppLanguage.arabic: 'إعادة الحساب والتحسين',
    AppLanguage.french: 'Recalculer et optimiser',
    AppLanguage.english: 'Recalculate and optimize',
  },
  'طباعة وحفظ كـ PDF': {
    AppLanguage.arabic: 'طباعة وحفظ كـ PDF',
    AppLanguage.french: 'Imprimer et exporter en PDF',
    AppLanguage.english: 'Print and export as PDF',
  },
  'نطاق التحسين': {
    AppLanguage.arabic: 'نطاق التحسين',
    AppLanguage.french: 'Portée de l\'optimisation',
    AppLanguage.english: 'Optimization scope',
  },
  '1. طلبية كاملة': {
    AppLanguage.arabic: '1. طلبية كاملة',
    AppLanguage.french: '1. Commande complète',
    AppLanguage.english: '1. Full order',
  },
  '2. عدة طلبيات مجمعة': {
    AppLanguage.arabic: '2. عدة طلبيات مجمعة',
    AppLanguage.french: '2. Plusieurs commandes combinées',
    AppLanguage.english: '2. Multiple combined orders',
  },
  '3. جزء من طلبية لنهايتها': {
    AppLanguage.arabic: '3. جزء من طلبية لنهايتها',
    AppLanguage.french: '3. Partie de commande jusqu\'à la fin',
    AppLanguage.english: '3. Order range to end',
  },
  '4. عناصر مختارة من طلبيات': {
    AppLanguage.arabic: '4. عناصر مختارة من طلبيات',
    AppLanguage.french: '4. Éléments sélectionnés de commandes',
    AppLanguage.english: '4. Custom selected elements',
  },
  'اختر الطلبية': {
    AppLanguage.arabic: 'اختر الطلبية',
    AppLanguage.french: 'Choisir la commande',
    AppLanguage.english: 'Select order',
  },
  'حدد الطلبيات المراد دمجها': {
    AppLanguage.arabic: 'حدد الطلبيات المراد دمجها',
    AppLanguage.french: 'Sélectionner les commandes à combiner',
    AppLanguage.english: 'Select orders to combine',
  },
  'الطلبية المحددة': {
    AppLanguage.arabic: 'الطلبية المحددة',
    AppLanguage.french: 'Commande sélectionnée',
    AppLanguage.english: 'Selected order',
  },
  'من العنصر رقم': {
    AppLanguage.arabic: 'من العنصر رقم',
    AppLanguage.french: 'De l\'article n°',
    AppLanguage.english: 'From item #',
  },
  'إلى نهاية الطلب': {
    AppLanguage.arabic: 'إلى نهاية الطلب',
    AppLanguage.french: 'Jusqu\'à la fin de la commande',
    AppLanguage.english: 'To the end of order',
  },
  'اختر العناصر المطلوبة': {
    AppLanguage.arabic: 'اختر العناصر المطلوبة',
    AppLanguage.french: 'Choisir les articles requis',
    AppLanguage.english: 'Select required items',
  },
  'إعدادات المنشار والبارات': {
    AppLanguage.arabic: 'إعدادات المنشار والبارات',
    AppLanguage.french: 'Paramètres de scie et barres',
    AppLanguage.english: 'Saw and bar settings',
  },
  'طول البار الخام القياسي': {
    AppLanguage.arabic: 'طول البار الخام القياسي',
    AppLanguage.french: 'Longueur standard de barre',
    AppLanguage.english: 'Standard raw bar length',
  },
  'سماكة القرص (Kerf)': {
    AppLanguage.arabic: 'سماكة القرص (Kerf)',
    AppLanguage.french: 'Trait de scie (Kerf)',
    AppLanguage.english: 'Saw blade kerf',
  },
  'حد الفضلة الصالحة': {
    AppLanguage.arabic: 'حد الفضلة الصالحة',
    AppLanguage.french: 'Seuil chute réutilisable',
    AppLanguage.english: 'Reusable remnant threshold',
  },
  'ملخص القص العام': {
    AppLanguage.arabic: 'ملخص القص العام',
    AppLanguage.french: 'Résumé général de coupe',
    AppLanguage.english: 'Cutting summary',
  },
  'إجمالي البارات': {
    AppLanguage.arabic: 'إجمالي البارات',
    AppLanguage.french: 'Total des barres',
    AppLanguage.english: 'Total bars',
  },
  'عدد القطع المطلوبة': {
    AppLanguage.arabic: 'عدد القطع المطلوبة',
    AppLanguage.french: 'Nombre de pièces requises',
    AppLanguage.english: 'Required pieces count',
  },
  'نسبة الوفر والكفاءة': {
    AppLanguage.arabic: 'نسبة الوفر والكفاءة',
    AppLanguage.french: 'Taux de rendement et efficacité',
    AppLanguage.english: 'Efficiency rate',
  },
  'الفواضل الصالحة': {
    AppLanguage.arabic: 'الفواضل الصالحة',
    AppLanguage.french: 'Chutes réutilisables',
    AppLanguage.english: 'Reusable remnants',
  },
  'استغلال أمثل': {
    AppLanguage.arabic: 'استغلال أمثل',
    AppLanguage.french: 'Utilisation optimale',
    AppLanguage.english: 'Optimal utilization',
  },
  'تُحفظ لإعادة الاستخدام': {
    AppLanguage.arabic: 'تُحفظ لإعادة الاستخدام',
    AppLanguage.french: 'À conserver pour réutilisation',
    AppLanguage.english: 'Save for reuse',
  },
  'الكل': {
    AppLanguage.arabic: 'الكل',
    AppLanguage.french: 'Tous',
    AppLanguage.english: 'All',
  },
  'بار': {
    AppLanguage.arabic: 'بار',
    AppLanguage.french: 'barre(s)',
    AppLanguage.english: 'bar(s)',
  },
  'سم': {
    AppLanguage.arabic: 'سم',
    AppLanguage.french: 'cm',
    AppLanguage.english: 'cm',
  },
  'قطعة': {
    AppLanguage.arabic: 'قطعة',
    AppLanguage.french: 'pièce(s)',
    AppLanguage.english: 'piece(s)',
  },
  'متر طولي': {
    AppLanguage.arabic: 'متر طولي',
    AppLanguage.french: 'mètres linéaires',
    AppLanguage.english: 'linear meters',
  },
  'الهالك': {
    AppLanguage.arabic: 'الهالك',
    AppLanguage.french: 'Déchet',
    AppLanguage.english: 'Scrap',
  },
  'اضغط على "تشغيل خوارزمية التحسين" لبدء القص الأمثل': {
    AppLanguage.arabic: 'اضغط على "تشغيل خوارزمية التحسين" لبدء القص الأمثل',
    AppLanguage.french: 'Cliquez sur "Lancer l\'optimisation" pour commencer la découpe',
    AppLanguage.english: 'Click "Run optimization" to start cutting calculation',
  },
  'جاري تجهيز وثيقة تحسين القص PDF...': {
    AppLanguage.arabic: 'جاري تجهيز وثيقة تحسين القص PDF...',
    AppLanguage.french: 'Préparation du document PDF d\'optimisation en cours...',
    AppLanguage.english: 'Generating cutting optimization PDF...',
  },

  // ── 4. الاشتراكات والدفع الإلكتروني (Subscriptions & Online Payment) ──
  'مراجعة الاشتراك': {
    AppLanguage.arabic: 'مراجعة الاشتراك',
    AppLanguage.french: 'Détails de l\'abonnement',
    AppLanguage.english: 'Subscription details',
  },
  'تجديد الاشتراك متاح الآن': {
    AppLanguage.arabic: 'تجديد الاشتراك متاح الآن',
    AppLanguage.french: 'Renouvellement disponible',
    AppLanguage.english: 'Subscription renewal available now',
  },
  'يمكنك تجديد اشتراكك السنوي الآن نظراً لاقتراب موعد الانتهاء بأقل من شهر.': {
    AppLanguage.arabic: 'يمكنك تجديد اشتراكك السنوي الآن نظراً لاقتراب موعد الانتهاء بأقل من شهر.',
    AppLanguage.french: 'Vous pouvez renouveler votre abonnement annuel car il expire dans moins d\'un mois.',
    AppLanguage.english: 'You can renew your annual subscription now as it expires in less than a month.',
  },
  'يمكنك تجديد اشتراكك الآن نظراً لاقتراب موعد الانتهاء بأقل من أسبوع.': {
    AppLanguage.arabic: 'يمكنك تجديد اشتراكك الآن نظراً لاقتراب موعد الانتهاء بأقل من أسبوع.',
    AppLanguage.french: 'Vous pouvez renouveler votre abonnement car il expire dans moins d\'une semaine.',
    AppLanguage.english: 'You can renew your subscription now as it expires in less than a week.',
  },
  'الدفع عبر BaridiMob (CCP/RIP):': {
    AppLanguage.arabic: 'الدفع عبر BaridiMob (CCP/RIP):',
    AppLanguage.french: 'Paiement via BaridiMob (CCP/RIP) :',
    AppLanguage.english: 'Payment via BaridiMob (CCP/RIP):',
  },
  'لم يتم تحديد الرقم بعد': {
    AppLanguage.arabic: 'لم يتم تحديد الرقم بعد',
    AppLanguage.french: 'Numéro non encore défini',
    AppLanguage.english: 'Number not defined yet',
  },
  'نسخ رقم RIP': {
    AppLanguage.arabic: 'نسخ رقم RIP',
    AppLanguage.french: 'Copier le RIP',
    AppLanguage.english: 'Copy RIP',
  },
  'تم نسخ رقم RIP الخاص بـ BaridiMob بنجاح': {
    AppLanguage.arabic: 'تم نسخ رقم RIP الخاص بـ BaridiMob بنجاح',
    AppLanguage.french: 'Numéro RIP BaridiMob copié avec succès',
    AppLanguage.english: 'BaridiMob RIP copied successfully',
  },
  'الدفع الإلكتروني الفوري (الذهبية / CIB / بريدي موب)': {
    AppLanguage.arabic: 'الدفع الإلكتروني الفوري (الذهبية / CIB / بريدي موب)',
    AppLanguage.french: 'Paiement électronique instantané (Edahabia / CIB / BaridiMob)',
    AppLanguage.english: 'Instant online payment (Edahabia / CIB / BaridiMob)',
  },
  'طلب تجديد الاشتراك عبر واتساب': {
    AppLanguage.arabic: 'طلب تجديد الاشتراك عبر واتساب',
    AppLanguage.french: 'Demander le renouvellement via WhatsApp',
    AppLanguage.english: 'Request subscription renewal via WhatsApp',
  },
  'الدفع الإلكتروني وتجديد الاشتراك': {
    AppLanguage.arabic: 'الدفع الإلكتروني وتجديد الاشتراك',
    AppLanguage.french: 'Paiement électronique et renouvellement',
    AppLanguage.english: 'Online payment and subscription renewal',
  },
  '1. اختر باقة الاشتراك': {
    AppLanguage.arabic: '1. اختر باقة الاشتراك',
    AppLanguage.french: '1. Choisissez le forfait',
    AppLanguage.english: '1. Select subscription plan',
  },
  '2. وسيلة الدفع بالدينار الجزائري': {
    AppLanguage.arabic: '2. وسيلة الدفع بالدينار الجزائري',
    AppLanguage.french: '2. Mode de paiement (DZD)',
    AppLanguage.english: '2. Payment method (DZD)',
  },
  'البطاقة الذهبية (Edahabia)': {
    AppLanguage.arabic: 'البطاقة الذهبية (Edahabia)',
    AppLanguage.french: 'Carte Edahabia',
    AppLanguage.english: 'Edahabia card',
  },
  'دفع فوري آمن لبريد الجزائر مع رمز SMS': {
    AppLanguage.arabic: 'دفع فوري آمن لبريد الجزائر مع رمز SMS',
    AppLanguage.french: 'Paiement instantané sécurisé Algérie Poste par SMS',
    AppLanguage.english: 'Secure instant payment via Algérie Poste with SMS',
  },
  'الأكثر استخداماً': {
    AppLanguage.arabic: 'الأكثر استخداماً',
    AppLanguage.french: 'Le plus utilisé',
    AppLanguage.english: 'Most popular',
  },
  'بطاقة CIB البنكية': {
    AppLanguage.arabic: 'بطاقة CIB البنكية',
    AppLanguage.french: 'Carte bancaire CIB',
    AppLanguage.english: 'CIB bank card',
  },
  'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)': {
    AppLanguage.arabic: 'جميع البنوك الجزائرية (BNA, BEA, CPA, BDL, BADR, إلخ)',
    AppLanguage.french: 'Toutes les banques algériennes (BNA, BEA, CPA, BDL, BADR, etc.)',
    AppLanguage.english: 'All Algerian banks (BNA, BEA, CPA, BDL, BADR, etc.)',
  },
  'شبكة SATIM': {
    AppLanguage.arabic: 'شبكة SATIM',
    AppLanguage.french: 'Réseau SATIM',
    AppLanguage.english: 'SATIM Network',
  },
  'تأكيد ومتابعة الدفع': {
    AppLanguage.arabic: 'تأكيد ومتابعة الدفع',
    AppLanguage.french: 'Confirmer et procéder au paiement',
    AppLanguage.english: 'Confirm and proceed to payment',
  },
  'أو التحويل اليدوي عبر بريدي موب (BaridiMob Rip):': {
    AppLanguage.arabic: 'أو التحويل اليدوي عبر بريدي موب (BaridiMob Rip):',
    AppLanguage.french: 'Ou virement manuel via BaridiMob (RIP) :',
    AppLanguage.english: 'Or manual transfer via BaridiMob (RIP):',
  },
  'أدخل رقم المعاملة بعد التحويل:': {
    AppLanguage.arabic: 'أدخل رقم المعاملة بعد التحويل:',
    AppLanguage.french: 'Entrez le numéro de transaction après le virement :',
    AppLanguage.english: 'Enter transaction number after transfer:',
  },
  'إرسال إشعار التحويل للإدارة': {
    AppLanguage.arabic: 'إرسال إشعار التحويل للإدارة',
    AppLanguage.french: 'Envoyer la notification à l\'administration',
    AppLanguage.english: 'Send transfer notification to admin',
  },
  'تم استلام معلومات التحويل': {
    AppLanguage.arabic: 'تم استلام معلومات التحويل',
    AppLanguage.french: 'Informations de virement reçues',
    AppLanguage.english: 'Transfer info received',
  },
  'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.': {
    AppLanguage.arabic: 'تم إرسال إشعار الدفع عبر بريدي موب للإدارة.\nسيتم مراجعة رقم المعاملة وتفعيل الاشتراك خلال دقائق معدودة.',
    AppLanguage.french: 'Notification de paiement envoyée.\nLe virement sera validé et l\'abonnement activé dans quelques minutes.',
    AppLanguage.english: 'Payment notification sent.\nTransaction will be reviewed and subscription activated in a few minutes.',
  },
  'العودة للتطبيق': {
    AppLanguage.arabic: 'العودة للتطبيق',
    AppLanguage.french: 'Retour à l\'application',
    AppLanguage.english: 'Return to application',
  },
  'موافق': {
    AppLanguage.arabic: 'موافق',
    AppLanguage.french: 'OK',
    AppLanguage.english: 'OK',
  },
  'تاريخ بداية الاشتراك:': {
    AppLanguage.arabic: 'تاريخ بداية الاشتراك:',
    AppLanguage.french: 'Date de début :',
    AppLanguage.english: 'Start date:',
  },
  'تاريخ نهاية الاشتراك:': {
    AppLanguage.arabic: 'تاريخ نهاية الاشتراك:',
    AppLanguage.french: 'Date d\'expiration :',
    AppLanguage.english: 'End date:',
  },
  'كود الورشة:': {
    AppLanguage.arabic: 'كود الورشة:',
    AppLanguage.french: 'Code de l\'atelier :',
    AppLanguage.english: 'Workshop code:',
  },
  'تعذر تحميل بيانات الاشتراك': {
    AppLanguage.arabic: 'تعذر تحميل بيانات الاشتراك',
    AppLanguage.french: 'Impossible de charger les données d\'abonnement',
    AppLanguage.english: 'Failed to load subscription data',
  },

  // ── 5. وحدات القياس وعبارات تقطيع البروفيلات (Units & Cutting labels) ──
  'طول': {
    AppLanguage.arabic: 'طول',
    AppLanguage.french: 'Longueur',
    AppLanguage.english: 'Length',
  },
  'مم': {
    AppLanguage.arabic: 'مم',
    AppLanguage.french: 'mm',
    AppLanguage.english: 'mm',
  },
  'متر': {
    AppLanguage.arabic: 'متر',
    AppLanguage.french: 'm',
    AppLanguage.english: 'm',
  },
  'م': {
    AppLanguage.arabic: 'م',
    AppLanguage.french: 'm',
    AppLanguage.english: 'm',
  },
  'بار رقم': {
    AppLanguage.arabic: 'بار رقم',
    AppLanguage.french: 'Barre n°',
    AppLanguage.english: 'Bar #',
  },
  'فضل متبقي صالح': {
    AppLanguage.arabic: 'فضل متبقي صالح',
    AppLanguage.french: 'Chute réutilisable',
    AppLanguage.english: 'Reusable remnant',
  },
  'فضل متبقي صالح:': {
    AppLanguage.arabic: 'فضل متبقي صالح:',
    AppLanguage.french: 'Chute réutilisable :',
    AppLanguage.english: 'Reusable remnant:',
  },
  'رايش هدر': {
    AppLanguage.arabic: 'رايش هدر',
    AppLanguage.french: 'Déchet / Perte',
    AppLanguage.english: 'Waste scrap',
  },
  'رايش هدر:': {
    AppLanguage.arabic: 'رايش هدر:',
    AppLanguage.french: 'Déchet / Perte :',
    AppLanguage.english: 'Waste scrap:',
  },
  'فضلة': {
    AppLanguage.arabic: 'فضلة',
    AppLanguage.french: 'Chute',
    AppLanguage.english: 'Remnant',
  },
  'رايش': {
    AppLanguage.arabic: 'رايش',
    AppLanguage.french: 'Déchet',
    AppLanguage.english: 'Scrap',
  },
  'كفاءة': {
    AppLanguage.arabic: 'كفاءة',
    AppLanguage.french: 'Efficacité',
    AppLanguage.english: 'Efficiency',
  },
  'الكمية': {
    AppLanguage.arabic: 'الكمية',
    AppLanguage.french: 'Quantité',
    AppLanguage.english: 'Quantity',
  },
  'لون': {
    AppLanguage.arabic: 'لون',
    AppLanguage.french: 'Couleur',
    AppLanguage.english: 'Color',
  },
  'النهاية': {
    AppLanguage.arabic: 'النهاية',
    AppLanguage.french: 'Fin',
    AppLanguage.english: 'End',
  },

  // ── 6. إضافات الدفع الإلكتروني (Online Payment Details) ──
  'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر': {
    AppLanguage.arabic: 'دفع مشفر وآمن 100% ومطابق لمعايير الأمان البنكي وبريد الجزائر',
    AppLanguage.french: 'Paiement 100% sécurisé et conforme aux normes bancaires et Algérie Poste',
    AppLanguage.english: '100% encrypted & secure payment compliant with banking & Algérie Poste standards',
  },
  'بوابة الدفع الإلكتروني المعتمدة': {
    AppLanguage.arabic: 'بوابة الدفع الإلكتروني المعتمدة',
    AppLanguage.french: 'Passerelle de paiement électronique agréée',
    AppLanguage.english: 'Approved electronic payment gateway',
  },
  'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل': {
    AppLanguage.arabic: 'الدفع متاح الآن مباشرة بالبطاقات الجزائرية دون الحاجة للتنقل',
    AppLanguage.french: 'Le paiement est disponible directement avec les cartes algériennes sans déplacement',
    AppLanguage.english: 'Online payment available directly with Algerian cards without traveling',
  },
  'بريدي موب (BaridiMob)': {
    AppLanguage.arabic: 'بريدي موب (BaridiMob)',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'تحويل فوري للتطبيق عبر RIP والـ QR': {
    AppLanguage.arabic: 'تحويل فوري للتطبيق عبر RIP والـ QR',
    AppLanguage.french: 'Virement instantané via RIP et code QR',
    AppLanguage.english: 'Instant transfer via RIP and QR code',
  },
  'تحويل مباشر': {
    AppLanguage.arabic: 'تحويل مباشر',
    AppLanguage.french: 'Virement direct',
    AppLanguage.english: 'Direct transfer',
  },
  'كارت فيزا / ماستركارد (Visa / Mastercard)': {
    AppLanguage.arabic: 'كارت فيزا / ماستركارد (Visa / Mastercard)',
    AppLanguage.french: 'Carte Visa / Mastercard',
    AppLanguage.english: 'Visa / Mastercard',
  },
  'البطاقات الدولية والمحلية المعتمدة': {
    AppLanguage.arabic: 'البطاقات الدولية والمحلية المعتمدة',
    AppLanguage.french: 'Cartes nationales et internationales agréées',
    AppLanguage.english: 'Approved domestic and international cards',
  },
  'دولي': {
    AppLanguage.arabic: 'دولي',
    AppLanguage.french: 'International',
    AppLanguage.english: 'International',
  },
  'المبلغ الإجمالي للدفع:': {
    AppLanguage.arabic: 'المبلغ الإجمالي للدفع:',
    AppLanguage.french: 'Montant total à payer :',
    AppLanguage.english: 'Total amount to pay:',
  },
  'ادفع الآن بالبطاقة': {
    AppLanguage.arabic: 'ادفع الآن بالبطاقة',
    AppLanguage.french: 'Payer maintenant par carte',
    AppLanguage.english: 'Pay now by card',
  },
  'جاري تجهيز بوابة الدفع...': {
    AppLanguage.arabic: 'جاري تجهيز بوابة الدفع...',
    AppLanguage.french: 'Préparation de la passerelle...',
    AppLanguage.english: 'Preparing payment gateway...',
  },
  'خطوات الدفع عبر بريدي موب (BaridiMob):': {
    AppLanguage.arabic: 'خطوات الدفع عبر بريدي موب (BaridiMob):',
    AppLanguage.french: 'Étapes de paiement via BaridiMob :',
    AppLanguage.english: 'Steps for paying via BaridiMob:',
  },
  '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.': {
    AppLanguage.arabic: '1. انسخ رقم الـ RIP أدناه.\n2. افتح تطبيق BaridiMob وقم بإجراء تحويل بالمبلغ المطلوب.\n3. ضع رقم المعاملة (N° de transaction) هنا لتفعيل اشتراكك.',
    AppLanguage.french: '1. Copiez le numéro RIP ci-dessous.\n2. Ouvrez l\'application BaridiMob et effectuez le virement.\n3. Saisissez le numéro de transaction ici pour activer votre abonnement.',
    AppLanguage.english: '1. Copy the RIP number below.\n2. Open BaridiMob app and make the transfer.\n3. Enter the transaction number here to activate your subscription.',
  },
  'رقم الحساب البريدي (RIP):': {
    AppLanguage.arabic: 'رقم الحساب البريدي (RIP):',
    AppLanguage.french: 'Numéro de compte postal (RIP) :',
    AppLanguage.english: 'Postal account number (RIP):',
  },
  'نسخ رقم الـ RIP': {
    AppLanguage.arabic: 'نسخ رقم الـ RIP',
    AppLanguage.french: 'Copier le numéro RIP',
    AppLanguage.english: 'Copy RIP number',
  },
  'تم نسخ رقم الـ RIP بنجاح': {
    AppLanguage.arabic: 'تم نسخ رقم الـ RIP بنجاح',
    AppLanguage.french: 'Numéro RIP copié avec succès',
    AppLanguage.english: 'RIP number copied successfully',
  },
  'رقم معاملة بريدي موب (Numéro de transaction)': {
    AppLanguage.arabic: 'رقم معاملة بريدي موب (Numéro de transaction)',
    AppLanguage.french: 'Numéro de transaction BaridiMob',
    AppLanguage.english: 'BaridiMob transaction number',
  },
  'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)': {
    AppLanguage.arabic: 'ملاحظة إضافية (اختياري - اسم الورشة أو رقم الهاتف)',
    AppLanguage.french: 'Note additionnelle (facultatif - nom atelier ou tél)',
    AppLanguage.english: 'Additional note (optional - workshop name or phone)',
  },
  'تأكيد التحويل وإرسال الإشعار': {
    AppLanguage.arabic: 'تأكيد التحويل وإرسال الإشعار',
    AppLanguage.french: 'Confirmer le virement et envoyer',
    AppLanguage.english: 'Confirm transfer and send notice',
  },
  'بانتظار إتمام الدفع...': {
    AppLanguage.arabic: 'بانتظار إتمام الدفع...',
    AppLanguage.french: 'En attente du paiement...',
    AppLanguage.english: 'Awaiting payment completion...',
  },
  'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.': {
    AppLanguage.arabic: 'تم فتح صفحة الدفع الآمنة على المتصفح.\nيرجى إدخال بيانات البطاقة والرمز السري SMS المرسل إلى هاتفك لإتمام المعاملة.',
    AppLanguage.french: 'Page de paiement sécurisée ouverte dans le navigateur.\nVeuillez saisir les coordonnées de la carte et le code SMS reçu sur votre téléphone.',
    AppLanguage.english: 'Secure payment page opened in browser.\nPlease enter card details and SMS code received on your phone.',
  },
  'تحقق من تفعيل الدفع': {
    AppLanguage.arabic: 'تحقق من تفعيل الدفع',
    AppLanguage.french: 'Vérifier l\'activation du paiement',
    AppLanguage.english: 'Verify payment activation',
  },
  'تم الدفع وتفعيل الاشتراك بنجاح!': {
    AppLanguage.arabic: 'تم الدفع وتفعيل الاشتراك بنجاح!',
    AppLanguage.french: 'Paiement effectué et abonnement activé avec succès !',
    AppLanguage.english: 'Payment successful and subscription activated!',
  },
  'الأكثر طلباً': {
    AppLanguage.arabic: 'الأكثر طلباً',
    AppLanguage.french: 'Le plus demandé',
    AppLanguage.english: 'Most requested',
  },
  'د.ج': {
    AppLanguage.arabic: 'د.ج',
    AppLanguage.french: 'DZD',
    AppLanguage.english: 'DZD',
  },
  'الذهبية': {
    AppLanguage.arabic: 'الذهبية',
    AppLanguage.french: 'Edahabia',
    AppLanguage.english: 'Edahabia',
  },
  'CIB': {
    AppLanguage.arabic: 'CIB',
    AppLanguage.french: 'CIB',
    AppLanguage.english: 'CIB',
  },
  'BaridiMob': {
    AppLanguage.arabic: 'BaridiMob',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'البار #': {
    AppLanguage.arabic: 'البار #',
    AppLanguage.french: 'Barre #',
    AppLanguage.english: 'Bar #',
  },
  'القطع المقصوصة (مم)': {
    AppLanguage.arabic: 'القطع المقصوصة (مم)',
    AppLanguage.french: 'Pièces découpées (mm)',
    AppLanguage.english: 'Cut pieces (mm)',
  },
  'المستغل (مم)': {
    AppLanguage.arabic: 'المستغل (مم)',
    AppLanguage.french: 'Utilisé (mm)',
    AppLanguage.english: 'Used (mm)',
  },
  'الفضل المتبقي (مم)': {
    AppLanguage.arabic: 'الفضل المتبقي (مم)',
    AppLanguage.french: 'Chute restante (mm)',
    AppLanguage.english: 'Remaining remnant (mm)',
  },
  'الحالة': {
    AppLanguage.arabic: 'الحالة',
    AppLanguage.french: 'État',
    AppLanguage.english: 'Status',
  },
  'فضلة صالحة': {
    AppLanguage.arabic: 'فضلة صالحة',
    AppLanguage.french: 'Chute réutilisable',
    AppLanguage.english: 'Usable remnant',
  },
  'التاريخ:': {
    AppLanguage.arabic: 'التاريخ:',
    AppLanguage.french: 'Date :',
    AppLanguage.english: 'Date:',
  },
  'البارات:': {
    AppLanguage.arabic: 'البارات:',
    AppLanguage.french: 'Barres :',
    AppLanguage.english: 'Bars:',
  },
  'القطع:': {
    AppLanguage.arabic: 'القطع:',
    AppLanguage.french: 'Pièces :',
    AppLanguage.english: 'Pieces:',
  },
  'الكفاءة:': {
    AppLanguage.arabic: 'الكفاءة:',
    AppLanguage.french: 'Rendement :',
    AppLanguage.english: 'Efficiency:',
  },
  'إجمالي البارات المطلوبة': {
    AppLanguage.arabic: 'إجمالي البارات المطلوبة',
    AppLanguage.french: 'Total des barres requises',
    AppLanguage.english: 'Total bars needed',
  },
  'إجمالي القطع:': {
    AppLanguage.arabic: 'إجمالي القطع:',
    AppLanguage.french: 'Total pièces :',
    AppLanguage.english: 'Total pieces:',
  },
  'نسبة الاستغلال والوفر:': {
    AppLanguage.arabic: 'نسبة الاستغلال والوفر:',
    AppLanguage.french: 'Taux de rendement :',
    AppLanguage.english: 'Yield rate:',
  },
  'الفواضل الصالحة للاستعمال:': {
    AppLanguage.arabic: 'الفواضل الصالحة للاستعمال:',
    AppLanguage.french: 'Chutes réutilisables :',
    AppLanguage.english: 'Reusable remnants:',
  },
  // ── 5. حجز السلع بالمخزون وتقرير النواقص (Stock Reservation & Shortage) ──
  'تقرير النواقص والمخزون': {
    AppLanguage.arabic: 'تقرير النواقص والمخزون',
    AppLanguage.french: 'Rapport de manque & Stock',
    AppLanguage.english: 'Shortage & Stock Report',
  },
  'حالة حجز السلع بالمخزون:': {
    AppLanguage.arabic: 'حالة حجز السلع بالمخزون:',
    AppLanguage.french: 'Statut de réservation en stock :',
    AppLanguage.english: 'Stock reservation status:',
  },
  'حالة حجز المخزون:': {
    AppLanguage.arabic: 'حالة حجز المخزون:',
    AppLanguage.french: 'Réservation stock :',
    AppLanguage.english: 'Stock reservation:',
  },
  'تم الحجز': {
    AppLanguage.arabic: 'تم الحجز',
    AppLanguage.french: 'Réservé',
    AppLanguage.english: 'Reserved',
  },
  'لم يُحجز بعد': {
    AppLanguage.arabic: 'لم يُحجز بعد',
    AppLanguage.french: 'Non réservé',
    AppLanguage.english: 'Not reserved',
  },
  'حجز السلع للطلبية': {
    AppLanguage.arabic: 'حجز السلع للطلبية',
    AppLanguage.french: 'Réserver pour la commande',
    AppLanguage.english: 'Reserve stock for order',
  },
  'إلغاء الحجز': {
    AppLanguage.arabic: 'إلغاء الحجز',
    AppLanguage.french: 'Annuler la réservation',
    AppLanguage.english: 'Cancel reservation',
  },
  'إدارة الحجز / النواقص': {
    AppLanguage.arabic: 'إدارة الحجز / النواقص',
    AppLanguage.french: 'Gérer la réservation / Manques',
    AppLanguage.english: 'Manage reservation / Shortages',
  },
  'تم حجز سلع هذه الطلبية في المخزون بنجاح': {
    AppLanguage.arabic: 'تم حجز سلع هذه الطلبية في المخزون بنجاح',
    AppLanguage.french: 'Articles réservés en stock avec succès pour cette commande',
    AppLanguage.english: 'Order items successfully reserved in stock',
  },
  'تم إلغاء حجز سلع هذه الطلبية في المخزون': {
    AppLanguage.arabic: 'تم إلغاء حجز سلع هذه الطلبية في المخزون',
    AppLanguage.french: 'Réservation en stock annulée pour cette commande',
    AppLanguage.english: 'Stock reservation cancelled for this order',
  },
  'تعذر تحديث الحجز': {
    AppLanguage.arabic: 'تعذر تحديث الحجز',
    AppLanguage.french: 'Échec de mise à jour de la réservation',
    AppLanguage.english: 'Failed to update reservation',
  },
  'تم حجز القطع والفواضل اللازمة لهذه الطلبية بالمخزون لمنع استهلاكها لطلبيات أخرى.': {
    AppLanguage.arabic: 'تم حجز القطع والفواضل اللازمة لهذه الطلبية بالمخزون لمنع استهلاكها لطلبيات أخرى.',
    AppLanguage.french: 'Les barres et chutes nécessaires ont été réservées pour empêcher leur utilisation ailleurs.',
    AppLanguage.english: 'Stock bars and remnants reserved for this order to prevent duplicate consumption.',
  },
  'حجز السلع يربط القطع والفواضل المحددة بالطلبية ويضمن عدم استهلاكها لطلبيات أخرى.': {
    AppLanguage.arabic: 'حجز السلع يربط القطع والفواضل المحددة بالطلبية ويضمن عدم استهلاكها لطلبيات أخرى.',
    AppLanguage.french: 'La réservation lie les barres et chutes à la commande pour garantir leur disponibilité.',
    AppLanguage.english: 'Reservation links matching stock and remnants to ensure availability for this order.',
  },
  // ── 6. توافق الإطارات عند بروفيل الزاوية 90° (Corner Profile Frame Compatibility) ──
  'توافق الإطارات عند الزاوية 90°': {
    AppLanguage.arabic: 'توافق الإطارات عند الزاوية 90°',
    AppLanguage.french: 'Compatibilité dormant d\'angle 90°',
    AppLanguage.english: '90° corner frame compatibility',
  },
  'توافق الإطارات عند الزاوية': {
    AppLanguage.arabic: 'توافق الإطارات عند الزاوية',
    AppLanguage.french: 'Compatibilité du cadre à l\'angle',
    AppLanguage.english: 'Frame compatibility at corner',
  },
  'تم استبدال الإطار تلقائياً بإطار بدون غطاء مدمج مطابق في العرض الظاهر ليناسب زاوية 90°:': {
    AppLanguage.arabic: 'تم استبدال الإطار تلقائياً بإطار بدون غطاء مدمج مطابق في العرض الظاهر ليناسب زاوية 90°:',
    AppLanguage.french: 'Dormant remplacé automatiquement par un dormant sans couvre-joint à largeur apparente identique :',
    AppLanguage.english: 'Frame automatically replaced with a non-integrated cover frame with matching visible width:',
  },
  'لا يمكن تركيب إطار بغطاء مدمج عند الزاوية 90°؛ يقوم النظام تلقائياً باختيار إطار بدون غطاء مدمج مطابق تماماً في العرض الظاهر.': {
    AppLanguage.arabic: 'لا يمكن تركيب إطار بغطاء مدمج عند الزاوية 90°؛ يقوم النظام تلقائياً باختيار إطار بدون غطاء مدمج مطابق تماماً في العرض الظاهر.',
    AppLanguage.french: 'Un dormant avec couvre-joint intégré ne peut être monté sur un angle 90° ; le système adapte automatiquement un dormant sans couvre-joint de même largeur apparente.',
    AppLanguage.english: 'Frames with integrated cover cannot join at a 90° corner; the system automatically switches to a matching frame without cover and equal visible width.',
  },

  // ── 7. ترجمات أسئلة المحذوفات ومونتو سليم ومدى الحياة وتخصيص البروفيل ──
  'استعادة الفاتورة': {
    AppLanguage.arabic: 'استعادة الفاتورة',
    AppLanguage.french: 'Restaurer la facture',
    AppLanguage.english: 'Restore invoice',
  },
  'هل ترغب في استعادة فاتورة الشراء هذه؟': {
    AppLanguage.arabic: 'هل ترغب في استعادة فاتورة الشراء هذه؟',
    AppLanguage.french: 'Voulez-vous restaurer cette facture d\'achat ?',
    AppLanguage.english: 'Do you want to restore this purchase invoice?',
  },
  'هل أنت متأكد من الحذف النهائي لفاتورة الشراء؟ لا يمكن التراجع عن هذا الإجراء.': {
    AppLanguage.arabic: 'هل أنت متأكد من الحذف النهائي لفاتورة الشراء؟ لا يمكن التراجع عن هذا الإجراء.',
    AppLanguage.french: 'Êtes-vous sûr de vouloir supprimer définitivement cette facture d\'achat ? Cette action est irréversible.',
    AppLanguage.english: 'Are you sure you want to permanently delete this purchase invoice? This action cannot be undone.',
  },
  'هل أنت متأكد من تفريغ سلة فواتير الشراء نهائياً؟': {
    AppLanguage.arabic: 'هل أنت متأكد من تفريغ سلة فواتير الشراء نهائياً؟',
    AppLanguage.french: 'Êtes-vous sûr de vider définitivement la corbeille des achats ?',
    AppLanguage.english: 'Are you sure you want to permanently empty the purchase trash?',
  },
  'مونتو سليم': {
    AppLanguage.arabic: 'مونتو سليم',
    AppLanguage.french: 'Montant Slim',
    AppLanguage.english: 'Slim Montant',
  },
  'مونتوسليم (Montant Slim)': {
    AppLanguage.arabic: 'مونتو سليم (Montant Slim)',
    AppLanguage.french: 'Montant Slim',
    AppLanguage.english: 'Slim Montant',
  },
  'المونتوسليم (Montant Slim):': {
    AppLanguage.arabic: 'المونتو سليم (Montant Slim):',
    AppLanguage.french: 'Montant Slim :',
    AppLanguage.english: 'Slim Montant:',
  },
  'قائم وسطي سليم (Montant Slim)': {
    AppLanguage.arabic: 'قائم وسطي سليم (Montant Slim)',
    AppLanguage.french: 'Montant central slim',
    AppLanguage.english: 'Slim central montant',
  },
  'مدى الحياة': {
    AppLanguage.arabic: 'مدى الحياة',
    AppLanguage.french: 'À vie',
    AppLanguage.english: 'Lifetime',
  },
  'اشتراك مدى الحياة': {
    AppLanguage.arabic: 'اشتراك مدى الحياة',
    AppLanguage.french: 'Abonnement à vie',
    AppLanguage.english: 'Lifetime subscription',
  },
  'غير محدود (مدى الحياة)': {
    AppLanguage.arabic: 'غير محدود (مدى الحياة)',
    AppLanguage.french: 'Illimité (À vie)',
    AppLanguage.english: 'Unlimited (Lifetime)',
  },
  'تخصيص البروفيل': {
    AppLanguage.arabic: 'تخصيص البروفيل',
    AppLanguage.french: 'Personnalisation du profil',
    AppLanguage.english: 'Profile customization',
  },
  'تم حفظ قواعد الأكسسوار بنجاح': {
    AppLanguage.arabic: 'تم حفظ قواعد الأكسسوار بنجاح',
    AppLanguage.french: 'Règles d\'accessoire enregistrées avec succès',
    AppLanguage.english: 'Accessory rules saved successfully',
  },
  'أدخل رقمًا صالحًا أكبر من أو يساوي صفرًا': {
    AppLanguage.arabic: 'أدخل رقمًا صالحًا أكبر من أو يساوي صفرًا',
    AppLanguage.french: 'Entrez un nombre valide supérieur ou égal à zéro',
    AppLanguage.english: 'Enter a valid number greater than or equal to zero',
  },
  'تطبيق تعديلات الوصف فقط — لا يغيّر السعر': {
    AppLanguage.arabic: 'تطبيق تعديلات الوصف فقط — لا يغيّر السعر',
    AppLanguage.french:
        'Appliquer uniquement les modifications de description — ne modifie pas le prix',
    AppLanguage.english:
        'Apply description edits only — does not change price',
  },
  'تعديل الرسم والخيارات — اعتماد السعر من جدول الكمية والتكلفة': {
    AppLanguage.arabic:
        'تعديل الرسم والخيارات — اعتماد السعر من جدول الكمية والتكلفة',
    AppLanguage.french:
        'Modifier le dessin et les options — Appliquer le prix du tableau quantité et coût',
    AppLanguage.english:
        'Edit drawing and options — Apply price from quantity and cost table',
  },
  'Largeur: ': {
    AppLanguage.arabic: 'العرض: ',
    AppLanguage.french: 'Largeur : ',
    AppLanguage.english: 'Width: ',
  },
  'Hauteur: ': {
    AppLanguage.arabic: 'الارتفاع: ',
    AppLanguage.french: 'Hauteur : ',
    AppLanguage.english: 'Height: ',
  },
  'الكريمون يولّد قطعتين تراينغل تلقائيًا، وموضع المقبض يؤخذ من الرسم.': {
    AppLanguage.arabic:
        'الكريمون يولّد قطعتين تراينغل تلقائيًا، وموضع المقبض يؤخذ من الرسم.',
    AppLanguage.french:
        'La crémone génère automatiquement deux tringles, et la position de la poignée est issue du dessin.',
    AppLanguage.english:
        'The cremone automatically generates two triangle rods, and the handle position is taken from the drawing.',
  },
  'ربط هذا الأكسيسوار بالتراينغل': {
    AppLanguage.arabic: 'ربط هذا الأكسيسوار بالتراينغل',
    AppLanguage.french: 'Lier cet accessoire à la tringle',
    AppLanguage.english: 'Link this accessory to triangle rod',
  },
  'بدون تراينغل': {
    AppLanguage.arabic: 'بدون تراينغل',
    AppLanguage.french: 'Sans tringle',
    AppLanguage.english: 'Without triangle rod',
  },
  'عدد التراينغل لهذا الأكسيسوار': {
    AppLanguage.arabic: 'عدد التراينغل لهذا الأكسيسوار',
    AppLanguage.french: 'Nombre de tringles pour cet accessoire',
    AppLanguage.english: 'Number of triangle rods for this accessory',
  },
  'موضع التقسيم': {
    AppLanguage.arabic: 'موضع التقسيم',
    AppLanguage.french: 'Position de division',
    AppLanguage.english: 'Division position',
  },
  'منتصف الضلفة': {
    AppLanguage.arabic: 'منتصف الضلفة',
    AppLanguage.french: 'Milieu du vantail',
    AppLanguage.english: 'Middle of sash',
  },
  'مسافة من الأسفل': {
    AppLanguage.arabic: 'مسافة من الأسفل',
    AppLanguage.french: 'Distance depuis le bas',
    AppLanguage.english: 'Distance from bottom',
  },
  'المسافة من أسفل الضلفة (مم)': {
    AppLanguage.arabic: 'المسافة من أسفل الضلفة (مم)',
    AppLanguage.french: 'Distance depuis le bas du vantail (mm)',
    AppLanguage.english: 'Distance from sash bottom (mm)',
  },

  // ── 7. الأنظمة الجاهزة للرسم السريع (Preset Window Systems) ──
  'الأنظمة الجاهزة': {
    AppLanguage.arabic: 'الأنظمة الجاهزة',
    AppLanguage.french: 'Systèmes prêts',
    AppLanguage.english: 'Ready systems',
  },
  'اختيار نظام جاهز': {
    AppLanguage.arabic: 'اختيار نظام جاهز',
    AppLanguage.french: 'Choisir un modèle prêt',
    AppLanguage.english: 'Select a preset system',
  },
  'أنظمة ونماذج جاهزة للرسم السريع': {
    AppLanguage.arabic: 'أنظمة ونماذج جاهزة للرسم السريع',
    AppLanguage.french: 'Modèles prêts pour un dessin rapide',
    AppLanguage.english: 'Ready models for quick drawing',
  },
  'أدخل أبعاد الإطار واختر النموذج المطلوب ليرسم تلقائياً بدقة': {
    AppLanguage.arabic: 'أدخل أبعاد الإطار واختر النموذج المطلوب ليرسم تلقائياً بدقة',
    AppLanguage.french: 'Saisissez les dimensions et choisissez le modèle à dessiner automatiquement',
    AppLanguage.english: 'Enter frame dimensions and choose the template to draw automatically',
  },
  'نافذة بدون ستار': {
    AppLanguage.arabic: 'نافذة بدون ستار',
    AppLanguage.french: 'Fenêtre sans volet',
    AppLanguage.english: 'Window without shutter',
  },
  'دلفة أو دلفتين تفتح جانبياً حسب العرض': {
    AppLanguage.arabic: 'دلفة أو دلفتين تفتح جانبياً حسب العرض',
    AppLanguage.french: '1 ou 2 vantaux ouvrants selon la largeur',
    AppLanguage.english: '1 or 2 sashes based on width',
  },
  'نافذة مع ستار': {
    AppLanguage.arabic: 'نافذة مع ستار',
    AppLanguage.french: 'Fenêtre avec volet',
    AppLanguage.english: 'Window with shutter',
  },
  'دلفة أو دلفتين مع صندوق الستار (Monobloc)': {
    AppLanguage.arabic: 'دلفة أو دلفتين مع صندوق الستار (Monobloc)',
    AppLanguage.french: '1 ou 2 vantaux avec coffre volet monobloc',
    AppLanguage.english: '1 or 2 sashes with monobloc shutter',
  },
  'نافذة جرارة بدون ستار': {
    AppLanguage.arabic: 'نافذة جرارة بدون ستار',
    AppLanguage.french: 'Coulissant sans volet',
    AppLanguage.english: 'Sliding window without shutter',
  },
  'نافذة منزلقة بضلفتين (2 Vantaux)': {
    AppLanguage.arabic: 'نافذة منزلقة بضلفتين (2 Vantaux)',
    AppLanguage.french: 'Coulissant standard à 2 vantaux',
    AppLanguage.english: 'Standard 2-sash sliding window',
  },
  'نافذة جرارة مع الستار': {
    AppLanguage.arabic: 'نافذة جرارة مع الستار',
    AppLanguage.french: 'Coulissant avec volet',
    AppLanguage.english: 'Sliding window with shutter',
  },
  'نافذة منزلقة بضلفتين مع صندوق الستار': {
    AppLanguage.arabic: 'نافذة منزلقة بضلفتين مع صندوق الستار',
    AppLanguage.french: 'Coulissant 2 vantaux avec coffre volet',
    AppLanguage.english: '2-sash sliding with shutter box',
  },
  'باب بضلفة واحدة مع قفل': {
    AppLanguage.arabic: 'باب بضلفة واحدة مع قفل',
    AppLanguage.french: 'Porte 1 vantail avec serrure',
    AppLanguage.english: 'Single door with lock',
  },
  'بروفيل ضلفة 105، قفل بمفتاح وبدون إطار سفلي': {
    AppLanguage.arabic: 'بروفيل ضلفة 105، قفل بمفتاح وبدون إطار سفلي',
    AppLanguage.french: 'Ouvrant 105, serrure à clé, sans dormant bas',
    AppLanguage.english: 'Sash 105, key lock, without bottom frame',
  },
  'باب بضلفتين مع قفل': {
    AppLanguage.arabic: 'باب بضلفتين مع قفل',
    AppLanguage.french: 'Porte 2 vantaux مع serrure',
    AppLanguage.english: 'Double door with lock',
  },
  'ضلفتين 105، قفل بمفتاح وبدون إطار سفلي': {
    AppLanguage.arabic: 'ضلفتين 105، قفل بمفتاح وبدون إطار سفلي',
    AppLanguage.french: '2 vantaux 105, serrure à clé, sans dormant bas',
    AppLanguage.english: '2 sashes 105, key lock, without bottom frame',
  },
  'ستار وحده': {
    AppLanguage.arabic: 'ستار وحده',
    AppLanguage.french: 'Volet roulant seul',
    AppLanguage.english: 'Roller shutter only',
  },
  'صندوق وشفرات الستار مع المجاري فقط': {
    AppLanguage.arabic: 'صندوق وشفرات الستار مع المجاري فقط',
    AppLanguage.french: 'Coffre et lames avec coulisses uniquement',
    AppLanguage.english: 'Shutter box and slats with guides only',
  },
  'نافذة صغيرة تفتح من الأعلى': {
    AppLanguage.arabic: 'نافذة صغيرة تفتح من الأعلى',
    AppLanguage.french: 'Châssis à soufflet (abattant)',
    AppLanguage.english: 'Top-opening hopper window (soufflet)',
  },
  'مفصلات سفلية وتفتح من الأعلى (Soufflet)': {
    AppLanguage.arabic: 'مفصلات سفلية وتفتح من الأعلى (Soufflet)',
    AppLanguage.french: 'Paumelles en bas et ouverture par le haut',
    AppLanguage.english: 'Hinges on bottom, opens from top (soufflet)',
  },
  'رسم هذا النظام': {
    AppLanguage.arabic: 'رسم هذا النظام',
    AppLanguage.french: 'Dessiner ce modèle',
    AppLanguage.english: 'Draw this template',
  },
  'تطبيق ورسم النظام': {
    AppLanguage.arabic: 'تطبيق ورسم النظام',
    AppLanguage.french: 'Appliquer et dessiner',
    AppLanguage.english: 'Apply and draw',
  },
  'القياس الافتراضي': {
    AppLanguage.arabic: 'القياس الافتراضي',
    AppLanguage.french: 'Dimension par défaut',
    AppLanguage.english: 'Default dimension',
  },

  // ── إعدادات الإشعارات (Notification Settings) ──
  'إعدادات الإشعارات': {
    AppLanguage.arabic: 'إعدادات الإشعارات',
    AppLanguage.french: 'Paramètres des notifications',
    AppLanguage.english: 'Notification Settings',
  },
  'إسناد مهمة جديدة': {
    AppLanguage.arabic: 'إسناد مهمة جديدة',
    AppLanguage.french: 'Attribution d\'une nouvelle tâche',
    AppLanguage.english: 'New task assignment',
  },
  'إضافة وتعديل وحذف الطلبيات': {
    AppLanguage.arabic: 'إضافة وتعديل وحذف الطلبيات',
    AppLanguage.french: 'Ajout, modification et suppression des commandes',
    AppLanguage.english: 'Add, modify, and delete orders',
  },
  'حركة صندوق الورشة': {
    AppLanguage.arabic: 'حركة صندوق الورشة',
    AppLanguage.french: 'Mouvements de caisse d\'atelier',
    AppLanguage.english: 'Workshop cashbox activity',
  },
  'المقبوضات والمدفوعات': {
    AppLanguage.arabic: 'المقبوضات والمدفوعات',
    AppLanguage.french: 'Encaissements et paiements',
    AppLanguage.english: 'Receipts and payments',
  },
  'الفواتير': {
    AppLanguage.arabic: 'الفواتير',
    AppLanguage.french: 'Factures',
    AppLanguage.english: 'Invoices',
  },
  'التسليمات ووصول السلع': {
    AppLanguage.arabic: 'التسليمات ووصول السلع',
    AppLanguage.french: 'Livraisons et arrivées de marchandises',
    AppLanguage.english: 'Deliveries and goods arrival',
  },
  'دخول المواد إلى الورشة': {
    AppLanguage.arabic: 'دخول المواد إلى الورشة',
    AppLanguage.french: 'Entrée des matières à l\'atelier',
    AppLanguage.english: 'Material entry to workshop',
  },
  'تلقي التنبيهات الفورية عند حدوث أي نشاط': {
    AppLanguage.arabic: 'تلقي التنبيهات الفورية عند حدوث أي نشاط',
    AppLanguage.french: 'Recevoir des alertes instantanées lors de toute activité',
    AppLanguage.english: 'Receive instant alerts for any activity',
  },

  // ── تثبيت وتحرير حركة رسم النوافذ ──
  'تثبيت الرسم': {
    AppLanguage.arabic: 'تثبيت الرسم',
    AppLanguage.french: 'Fixer le dessin',
    AppLanguage.english: 'Freeze drawing',
  },
  'تثبيت الرسم ومنع حركته': {
    AppLanguage.arabic: 'تثبيت الرسم ومنع حركته',
    AppLanguage.french: 'Verrouiller le déplacement du dessin',
    AppLanguage.english: 'Lock drawing movement',
  },
  'تحرير حركة الرسم': {
    AppLanguage.arabic: 'تحرير حركة الرسم',
    AppLanguage.french: 'Déverrouiller le déplacement',
    AppLanguage.english: 'Unlock drawing movement',
  },
  'تحرير حركة الرسم (الرسم مثبت حالياً)': {
    AppLanguage.arabic: 'تحرير حركة الرسم (الرسم مثبت حالياً)',
    AppLanguage.french: 'Déverrouiller le déplacement (actuellement fixé)',
    AppLanguage.english: 'Unlock movement (currently frozen)',
  },
  'تم تثبيت الرسم ومنع حركته': {
    AppLanguage.arabic: 'تم تثبيت الرسم ومنع حركته',
    AppLanguage.french: 'Le dessin est fixé',
    AppLanguage.english: 'Drawing movement is locked',
  },
  'تم تحرير حركة الرسم': {
    AppLanguage.arabic: 'تم تحرير حركة الرسم',
    AppLanguage.french: 'Déplacement du dessin déverrouillé',
    AppLanguage.english: 'Drawing movement unlocked',
  },
  'الرسم ثابت': {
    AppLanguage.arabic: 'الرسم ثابت',
    AppLanguage.french: 'Dessin fixe',
    AppLanguage.english: 'Fixed drawing',
  },
  'حركة حرة': {
    AppLanguage.arabic: 'حركة حرة',
    AppLanguage.french: 'Mouvement libre',
    AppLanguage.english: 'Free movement',
  },
};


