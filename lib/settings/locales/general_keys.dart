import '../app_settings.dart';

const Map<String, Map<AppLanguage, String>> generalKeys = {
  'تاريخ الإدخال': {
    AppLanguage.arabic: 'تاريخ الإدخال',
    AppLanguage.french: 'Date de création',
    AppLanguage.english: 'Created at',
  },
  'أدخل من طرف': {
    AppLanguage.arabic: 'أدخل من طرف',
    AppLanguage.french: 'Créé par',
    AppLanguage.english: 'Created by',
  },
  'عُدل من طرف': {
    AppLanguage.arabic: 'عُدل من طرف',
    AppLanguage.french: 'Modifié par',
    AppLanguage.english: 'Updated by',
  },
  'عرض كبطاقات': {
    AppLanguage.arabic: 'عرض كبطاقات',
    AppLanguage.french: 'Affichage en cartes',
    AppLanguage.english: 'Card view',
  },
  'عرض كجدول': {
    AppLanguage.arabic: 'عرض كجدول',
    AppLanguage.french: 'Affichage en tableau',
    AppLanguage.english: 'Table view',
  },
  'إضافة وثيقة جديدة': {
    AppLanguage.arabic: 'إضافة وثيقة جديدة',
    AppLanguage.french: 'Ajouter un nouveau document',
    AppLanguage.english: 'Add a new document',
  },
  'رقم الوثيقة': {
    AppLanguage.arabic: 'رقم الوثيقة',
    AppLanguage.french: 'N° du document',
    AppLanguage.english: 'Document No.',
  },
  'نوع الوثيقة': {
    AppLanguage.arabic: 'نوع الوثيقة',
    AppLanguage.french: 'Type de document',
    AppLanguage.english: 'Document type',
  },
  'كل شيء': {
    AppLanguage.arabic: 'كل شيء',
    AppLanguage.french: 'Tout',
    AppLanguage.english: 'Everything',
  },
  'الربط': {
    AppLanguage.arabic: 'الربط',
    AppLanguage.french: 'Liaison',
    AppLanguage.english: 'Link',
  },
  'صندوق المحل': {
    AppLanguage.arabic: 'صندوق المحل',
    AppLanguage.french: 'Caisse Magasin',
    AppLanguage.english: 'Store Cashbox',
  },
  'زبائن المحل': {
    AppLanguage.arabic: 'زبائن المحل',
    AppLanguage.french: 'Clients Magasin',
    AppLanguage.english: 'Store Customers',
  },
  'معطل': {
    AppLanguage.arabic: 'معطل',
    AppLanguage.french: 'Bloqué',
    AppLanguage.english: 'Blocked',
  },
  'نوع النشاط': {
    AppLanguage.arabic: 'نوع النشاط',
    AppLanguage.french: 'Type d\'activité',
    AppLanguage.english: 'Activity Type',
  },
  'تحديد طبيعة نشاط المؤسسة': {
    AppLanguage.arabic: 'تحديد طبيعة نشاط المؤسسة والوظائف المتاحة',
    AppLanguage.french:
        'Définir la nature de l\'activité et les modules actifs',
    AppLanguage.english: 'Define organization activity nature & active modules',
  },
  'ورشة فقط': {
    AppLanguage.arabic: 'ورشة فقط',
    AppLanguage.french: 'Atelier uniquement',
    AppLanguage.english: 'Workshop only',
  },
  'تصنيع النوافذ والمطابخ والطلبيات مع مستودعات ومشتريات الورشة المباشرة': {
    AppLanguage.arabic:
        'تصنيع النوافذ والمطابخ والطلبيات مع مستودعات ومشتريات الورشة المباشرة',
    AppLanguage.french:
        'Fabrication de menuiserie, commandes, stock et achats directs atelier',
    AppLanguage.english:
        'Manufacturing, orders, workshop stock and direct purchases',
  },
  'محل بيع مواد فقط': {
    AppLanguage.arabic: 'محل بيع مواد فقط',
    AppLanguage.french: 'Magasin de vente de matériaux uniquement',
    AppLanguage.english: 'Materials store only',
  },
  'بيع وتجارة المقاطع والزجاج والإكسسوارات ومستودعات ومبيعات المحل': {
    AppLanguage.arabic:
        'بيع وتجارة المقاطع والزجاج والإكسسوارات ومستودعات ومبيعات المحل',
    AppLanguage.french:
        'Vente profilés, quincaillerie, vitrage, stocks magasin et factures',
    AppLanguage.english:
        'Selling profiles, glass, accessories, store stock and invoices',
  },
  'ورشة + محل بيع مواد': {
    AppLanguage.arabic: 'ورشة + محل بيع مواد',
    AppLanguage.french: 'Atelier + Magasin de matériaux',
    AppLanguage.english: 'Workshop + Materials store',
  },
  'كلا النشاطين معاً، مع إمكانية التحويل والبيع الداخلي للورشة': {
    AppLanguage.arabic:
        'كلا النشاطين معاً، مع إمكانية التحويل والبيع الداخلي للورشة',
    AppLanguage.french:
        'Les deux activités avec vente et transfert interne vers l\'atelier',
    AppLanguage.english:
        'Both activities with internal sale and transfer to workshop',
  },
  'تأكيد واستلام في المخزون': {
    AppLanguage.arabic: 'تأكيد واستلام في المخزون',
    AppLanguage.french: 'Confirmer et réceptionner en stock',
    AppLanguage.english: 'Confirm & Receive into Stock',
  },
  'تأكيد واستلام': {
    AppLanguage.arabic: 'تأكيد واستلام',
    AppLanguage.french: 'Confirmer et réceptionner',
    AppLanguage.english: 'Confirm & Receive',
  },
  'تم تأكيد الفاتورة وإدخال الكميات للمخزون بنجاح': {
    AppLanguage.arabic: 'تم تأكيد الفاتورة وإدخال الكميات للمخزون بنجاح',
    AppLanguage.french:
        'Facture confirmée et articles ajoutés au stock avec succès',
    AppLanguage.english:
        'Invoice confirmed and items added to stock successfully',
  },
  // ── Material Sales Translations ──
  'لوحة المتابعة': {
    AppLanguage.arabic: 'لوحة المتابعة',
    AppLanguage.french: 'Tableau de bord',
    AppLanguage.english: 'Dashboard',
  },
  'الحجوزات': {
    AppLanguage.arabic: 'الحجوزات',
    AppLanguage.french: 'Réservations',
    AppLanguage.english: 'Reservations',
  },
  'التسليمات': {
    AppLanguage.arabic: 'التسليمات',
    AppLanguage.french: 'Livraisons',
    AppLanguage.english: 'Deliveries',
  },
  'عروض الأسعار': {
    AppLanguage.arabic: 'عروض الأسعار',
    AppLanguage.french: 'Devis / Proformas',
    AppLanguage.english: 'Quotations / Proformas',
  },
  'سجل المبيعات': {
    AppLanguage.arabic: 'سجل المبيعات',
    AppLanguage.french: 'Journal des ventes',
    AppLanguage.english: 'Sales Journal',
  },
  'المخزون المتاح': {
    AppLanguage.arabic: 'المخزون المتاح',
    AppLanguage.french: 'Stock disponible',
    AppLanguage.english: 'Available Stock',
  },
  'بيع المواد والمستلزمات': {
    AppLanguage.arabic: 'بيع المواد والمستلزمات',
    AppLanguage.french: 'Vente de matériaux et fournitures',
    AppLanguage.english: 'Materials & Supplies Sales',
  },
  'إنشاء وثيقة': {
    AppLanguage.arabic: 'إنشاء وثيقة',
    AppLanguage.french: 'Créer un document',
    AppLanguage.english: 'Create Document',
  },
  'وثيقة جديدة': {
    AppLanguage.arabic: 'وثيقة جديدة',
    AppLanguage.french: 'Nouveau document',
    AppLanguage.english: 'New Document',
  },
  'تعديل الوثيقة': {
    AppLanguage.arabic: 'تعديل الوثيقة',
    AppLanguage.french: 'Modifier le document',
    AppLanguage.english: 'Edit Document',
  },
  'الوثائق': {
    AppLanguage.arabic: 'الوثائق',
    AppLanguage.french: 'Documents',
    AppLanguage.english: 'Documents',
  },
  'الإيرادات': {
    AppLanguage.arabic: 'الإيرادات',
    AppLanguage.french: 'Revenus',
    AppLanguage.english: 'Revenue',
  },
  'لا توجد وثائق': {
    AppLanguage.arabic: 'لا توجد وثائق',
    AppLanguage.french: 'Aucun document',
    AppLanguage.english: 'No documents',
  },
  'المخزون المتاح للبيع': {
    AppLanguage.arabic: 'المخزون المتاح للبيع',
    AppLanguage.french: 'Stock disponible à la vente',
    AppLanguage.english: 'Stock available for sale',
  },
  'يعرض نفس مخزون الورشة المتاح للبيع، دون إنشاء مخزون منفصل.': {
    AppLanguage.arabic:
        'يعرض نفس مخزون الورشة المتاح للبيع، دون إنشاء مخزون منفصل.',
    AppLanguage.french:
        "Affiche le même stock de l'atelier disponible à la vente, sans créer de stock séparé.",
    AppLanguage.english:
        'Displays the same workshop inventory available for sale, without creating separate stock.',
  },
  'فتح المخزون': {
    AppLanguage.arabic: 'فتح المخزون',
    AppLanguage.french: 'Ouvrir le stock',
    AppLanguage.english: 'Open Inventory',
  },
  'حدث خطأ أثناء التحميل': {
    AppLanguage.arabic: 'حدث خطأ أثناء التحميل',
    AppLanguage.french: 'Une erreur est survenue lors du chargement',
    AppLanguage.english: 'An error occurred while loading',
  },
  'خطأ في الحفظ': {
    AppLanguage.arabic: 'خطأ في الحفظ',
    AppLanguage.french: 'Erreur lors de l\'enregistrement',
    AppLanguage.english: 'Error while saving',
  },
  'خطأ في الطباعة': {
    AppLanguage.arabic: 'خطأ في الطباعة',
    AppLanguage.french: 'Erreur d\'impression',
    AppLanguage.english: 'Print error',
  },
  'هل أنت متأكد من حذف الوثيقة': {
    AppLanguage.arabic: 'هل أنت متأكد من حذف الوثيقة',
    AppLanguage.french: 'Êtes-vous sûr de vouloir supprimer le document',
    AppLanguage.english: 'Are you sure you want to delete document',
  },
  'طلب مواد': {
    AppLanguage.arabic: 'طلب مواد',
    AppLanguage.french: 'Commande Matériaux',
    AppLanguage.english: 'Materials Order',
  },
  'وصل تسليم مواد': {
    AppLanguage.arabic: 'وصل تسليم مواد',
    AppLanguage.french: 'Bon de livraison Matériaux',
    AppLanguage.english: 'Delivery Note',
  },
  'وصل مسار مواد': {
    AppLanguage.arabic: 'وصل مسار مواد',
    AppLanguage.french: 'Bon de route Matériaux',
    AppLanguage.english: 'Waybill',
  },
  'فاتورة مواد': {
    AppLanguage.arabic: 'فاتورة مواد',
    AppLanguage.french: 'Facture Matériaux',
    AppLanguage.english: 'Materials Invoice',
  },
  'فاتورة أولية مواد': {
    AppLanguage.arabic: 'فاتورة أولية مواد',
    AppLanguage.french: 'Proforma Matériaux',
    AppLanguage.english: 'Proforma Invoice',
  },
  'مسودة': {
    AppLanguage.arabic: 'مسودة',
    AppLanguage.french: 'Brouillon',
    AppLanguage.english: 'Draft',
  },
  'محجوز': {
    AppLanguage.arabic: 'محجوز',
    AppLanguage.french: 'Réservé',
    AppLanguage.english: 'Reserved',
  },
  'مؤكد': {
    AppLanguage.arabic: 'مؤكد',
    AppLanguage.french: 'Confirmé',
    AppLanguage.english: 'Confirmed',
  },
  'تم التسليم': {
    AppLanguage.arabic: 'تم التسليم',
    AppLanguage.french: 'Livré',
    AppLanguage.english: 'Delivered',
  },
  'مدفوع': {
    AppLanguage.arabic: 'مدفوع',
    AppLanguage.french: 'Payé',
    AppLanguage.english: 'Paid',
  },
  // 'نوع الوثيقة': {
  //   AppLanguage.arabic: 'نوع الوثيقة',
  //   AppLanguage.french: 'Type de document',
  //   AppLanguage.english: 'Document Type',
  // },
  'العميل': {
    AppLanguage.arabic: 'العميل',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Client',
  },
  'المنتج': {
    AppLanguage.arabic: 'المنتج',
    AppLanguage.french: 'Article',
    AppLanguage.english: 'Article',
  },
  'المجموع': {
    AppLanguage.arabic: 'المجموع',
    AppLanguage.french: 'Total',
    AppLanguage.english: 'Total',
  },
  'لا توجد عناصر': {
    AppLanguage.arabic: 'لا توجد عناصر',
    AppLanguage.french: 'Aucun article',
    AppLanguage.english: 'No items',
  },
  'أضف منتجات من الزر في الأسفل': {
    AppLanguage.arabic: 'أضف منتجات من الزر في الأسفل',
    AppLanguage.french: 'Ajoutez des produits depuis le bouton ci-dessous',
    AppLanguage.english: 'Add products using the button below',
  },
  'إضافة عنصر': {
    AppLanguage.arabic: 'إضافة عنصر',
    AppLanguage.french: 'Ajouter un article',
    AppLanguage.english: 'Add item',
  },
  'اختر منتجاً': {
    AppLanguage.arabic: 'اختر منتجاً',
    AppLanguage.french: 'Choisir un produit',
    AppLanguage.english: 'Choose a product',
  },
  'البحث في': {
    AppLanguage.arabic: 'البحث في',
    AppLanguage.french: 'Rechercher dans',
    AppLanguage.english: 'Search in',
  },
  'اكتب الاسم أو الرمز للبحث...': {
    AppLanguage.arabic: 'اكتب الاسم أو الرمز للبحث...',
    AppLanguage.french: 'Saisissez le nom ou le code...',
    AppLanguage.english: 'Enter a name or code...',
  },
  'اضغط على حقل البحث لاختيار منتج': {
    AppLanguage.arabic: 'اضغط على حقل البحث لاختيار منتج',
    AppLanguage.french: 'Cliquez dans la recherche pour choisir un produit',
    AppLanguage.english: 'Click the search field to choose a product',
  },
  'تم اختيار المنتج': {
    AppLanguage.arabic: 'تم اختيار المنتج',
    AppLanguage.french: 'Produit sélectionné',
    AppLanguage.english: 'Product selected',
  },
  'كل العائلات': {
    AppLanguage.arabic: 'كل العائلات',
    AppLanguage.french: 'Toutes les familles',
    AppLanguage.english: 'All families',
  },
  'عائلة البروفيل': {
    AppLanguage.arabic: 'عائلة البروفيل',
    AppLanguage.french: 'Famille de profilé',
    AppLanguage.english: 'Profile family',
  },
  'ألواح': {
    AppLanguage.arabic: 'ألواح',
    AppLanguage.french: 'Panneaux / Tôles',
    AppLanguage.english: 'Sheets',
  },
  'خصم': {
    AppLanguage.arabic: 'خصم',
    AppLanguage.french: 'Remise',
    AppLanguage.english: 'Discount',
  },
  'المجموع الإجمالي': {
    AppLanguage.arabic: 'المجموع الإجمالي',
    AppLanguage.french: 'Sous-total',
    AppLanguage.english: 'Subtotal',
  },
  'المبلغ الصافي': {
    AppLanguage.arabic: 'المبلغ الصافي',
    AppLanguage.french: 'Net à payer',
    AppLanguage.english: 'Net to pay',
  },
  'المبلغ المتبقي': {
    AppLanguage.arabic: 'المبلغ المتبقي',
    AppLanguage.french: 'Montant restant',
    AppLanguage.english: 'Remaining amount',
  },
  'اختر عميلاً': {
    AppLanguage.arabic: 'اختر عميلاً',
    AppLanguage.french: 'Choisir un client',
    AppLanguage.english: 'Choose client',
  },
  'تم الحفظ بنجاح': {
    AppLanguage.arabic: 'تم الحفظ بنجاح',
    AppLanguage.french: 'Enregistré avec succès',
    AppLanguage.english: 'Saved successfully',
  },
  'يرجى إضافة عنصر واحد على الأقل': {
    AppLanguage.arabic: 'يرجى إضافة عنصر واحد على الأقل',
    AppLanguage.french: 'Veuillez ajouter au moins un article',
    AppLanguage.english: 'Please add at least one item',
  },
  'يرجى اختيار العميل': {
    AppLanguage.arabic: 'يرجى اختيار العميل',
    AppLanguage.french: 'Veuillez sélectionner un client',
    AppLanguage.english: 'Please select a client',
  },
  'تخصيص': {
    AppLanguage.arabic: 'تخصيص',
    AppLanguage.french: 'Personnaliser',
    AppLanguage.english: 'Customize',
  },
  'أسعار البروفيلات': {
    AppLanguage.arabic: 'أسعار البروفيلات',
    AppLanguage.french: 'Prix des profilés',
    AppLanguage.english: 'Profile Prices',
  },
  'قواعد حساب البروفيلات': {
    AppLanguage.arabic: 'قواعد حساب البروفيلات',
    AppLanguage.french: 'Règles de calcul des profilés',
    AppLanguage.english: 'Profile Calculation Rules',
  },
  'لا توجد بروفيلات.': {
    AppLanguage.arabic: 'لا توجد بروفيلات.',
    AppLanguage.french: 'Aucun profilé.',
    AppLanguage.english: 'No profiles.',
  },
  'مقابض': {
    AppLanguage.arabic: 'مقابض',
    AppLanguage.french: 'Poignées',
    AppLanguage.english: 'Handles',
  },
  'مقبض كبير ماريشال': {
    AppLanguage.arabic: 'مقبض كبير ماريشال',
    AppLanguage.french: 'Poignée Maréchal',
    AppLanguage.english: 'Maréchal Handle',
  },
  'مقبض كبير ماريشال 1.25 متر': {
    AppLanguage.arabic: 'مقبض كبير ماريشال 1.25 متر',
    AppLanguage.french: 'Poignée Maréchal 1.25m',
    AppLanguage.english: 'Maréchal Handle 1.25m',
  },
  'مقبض كبير ماريشال 2 متر': {
    AppLanguage.arabic: 'مقبض كبير ماريشال 2 متر',
    AppLanguage.french: 'Poignée Maréchal 2m',
    AppLanguage.english: 'Maréchal Handle 2m',
  },
  'الجوينات': {
    AppLanguage.arabic: 'الجوينات',
    AppLanguage.french: 'Joints',
    AppLanguage.english: 'Gaskets',
  },
  'المشاريع': {
    AppLanguage.arabic: 'المشاريع',
    AppLanguage.french: 'Projets',
    AppLanguage.english: 'Projects',
  },
  'المشروع (اختياري)': {
    AppLanguage.arabic: 'المشروع (اختياري)',
    AppLanguage.french: 'Projet (Optionnel)',
    AppLanguage.english: 'Project (Optional)',
  },
  'إضافة مشروع جديد': {
    AppLanguage.arabic: 'إضافة مشروع جديد',
    AppLanguage.french: 'Créer un nouveau projet',
    AppLanguage.english: 'Create New Project',
  },
  'تعديل المشروع': {
    AppLanguage.arabic: 'تعديل المشروع',
    AppLanguage.french: 'Modifier le projet',
    AppLanguage.english: 'Edit Project',
  },
  'حذف المشروع': {
    AppLanguage.arabic: 'حذف المشروع',
    AppLanguage.french: 'Supprimer le projet',
    AppLanguage.english: 'Delete Project',
  },
  'اسم المشروع': {
    AppLanguage.arabic: 'اسم المشروع',
    AppLanguage.french: 'Nom du projet',
    AppLanguage.english: 'Project Name',
  },
  'الوصف (اختياري)': {
    AppLanguage.arabic: 'الوصف (اختياري)',
    AppLanguage.french: 'Description (Optionnel)',
    AppLanguage.english: 'Description (Optional)',
  },
  'البحث عن مشروع...': {
    AppLanguage.arabic: 'البحث عن مشروع...',
    AppLanguage.french: 'Rechercher un projet...',
    AppLanguage.english: 'Search project...',
  },
  'لا توجد مشاريع حالية': {
    AppLanguage.arabic: 'لا توجد مشاريع حالية',
    AppLanguage.french: 'Aucun projet actuel',
    AppLanguage.english: 'No current projects',
  },
  'إضافة منتج خاص': {
    AppLanguage.arabic: 'إضافة منتج خاص',
    AppLanguage.french: 'Ajouter produit spécial',
    AppLanguage.english: 'Add Special Product',
  },
  'تعديل المنتج الخاص': {
    AppLanguage.arabic: 'تعديل المنتج الخاص',
    AppLanguage.french: 'Modifier produit spécial',
    AppLanguage.english: 'Edit Special Product',
  },
  'سعر الشراء (اختياري)': {
    AppLanguage.arabic: 'سعر الشراء (اختياري)',
    AppLanguage.french: 'Prix d\'achat (Optionnel)',
    AppLanguage.english: 'Purchase Price (Optional)',
  },
  'سعر البيع': {
    AppLanguage.arabic: 'سعر البيع',
    AppLanguage.french: 'Prix de vente',
    AppLanguage.english: 'Selling Price',
  },
  'يرجى اختيار الزبون أولاً لعرض مشاريعه': {
    AppLanguage.arabic: 'يرجى اختيار الزبون أولاً لعرض مشاريعه',
    AppLanguage.french:
        'Veuillez d\'abord choisir le client pour voir ses projets',
    AppLanguage.english: 'Please select client first to view their projects',
  },
  'اختيار المشروع': {
    AppLanguage.arabic: 'اختيار المشروع',
    AppLanguage.french: 'Sélectionner le projet',
    AppLanguage.english: 'Select Project',
  },
  'بدون مشروع / إلغاء الربط': {
    AppLanguage.arabic: 'بدون مشروع / إلغاء الربط',
    AppLanguage.french: 'Sans projet / Dissocier',
    AppLanguage.english: 'No project / Dissociate',
  },
  'لا توجد مشاريع لهذا الزبون': {
    AppLanguage.arabic: 'لا توجد مشاريع لهذا الزبون',
    AppLanguage.french: 'Aucun projet pour ce client',
    AppLanguage.english: 'No projects for this client',
  },
  'إجمالي قيمة المشروع': {
    AppLanguage.arabic: 'إجمالي قيمة المشروع',
    AppLanguage.french: 'Valeur totale du projet',
    AppLanguage.english: 'Total Project Value',
  },
  'الطلبيات المرتبطة': {
    AppLanguage.arabic: 'الطلبيات المرتبطة',
    AppLanguage.french: 'Commandes liées',
    AppLanguage.english: 'Linked Orders',
  },
  'إضافة طلبية': {
    AppLanguage.arabic: 'إضافة طلبية',
    AppLanguage.french: 'Ajouter une commande',
    AppLanguage.english: 'Add Order',
  },
  'لا توجد طلبيات مرتبطة بهذا المشروع حالياً': {
    AppLanguage.arabic: 'لا توجد طلبيات مرتبطة بهذا المشروع حالياً',
    AppLanguage.french: 'Aucune commande liée à ce projet actuellement',
    AppLanguage.english: 'No orders linked to this project currently',
  },
  'هل أنت متأكد من حذف هذا المشروع؟ سيتم فك ارتباط الطلبيات المرتبطة به دون حذفها.': {
    AppLanguage.arabic:
        'هل أنت متأكد من حذف هذا المشروع؟ سيتم فك ارتباط الطلبيات المرتبطة به دون حذفها.',
    AppLanguage.french:
        'Êtes-vous sûr de vouloir supprimer ce projet? Les commandes liées seront dissociées sans être supprimées.',
    AppLanguage.english:
        'Are you sure you want to delete this project? Linked orders will be dissociated without being deleted.',
  },
  'arabic': {
    AppLanguage.arabic: 'العربية',
    AppLanguage.french: 'Arabe',
    AppLanguage.english: 'Arabic',
  },
  'french': {
    AppLanguage.arabic: 'الفرنسية',
    AppLanguage.french: 'Français',
    AppLanguage.english: 'French',
  },
  'english': {
    AppLanguage.arabic: 'الإنجليزية',
    AppLanguage.french: 'Anglais',
    AppLanguage.english: 'English',
  },
  'light_mode': {
    AppLanguage.arabic: 'فاتح',
    AppLanguage.french: 'Clair',
    AppLanguage.english: 'Light',
  },
  'dark_mode': {
    AppLanguage.arabic: 'داكن',
    AppLanguage.french: 'Sombre',
    AppLanguage.english: 'Dark',
  },
  'linear_meter': {
    AppLanguage.arabic: 'المتر الخطي',
    AppLanguage.french: 'Mètre linéaire',
    AppLanguage.english: 'Linear Meter',
  },
  'square_meter': {
    AppLanguage.arabic: 'المتر المربع',
    AppLanguage.french: 'Mètre carré',
    AppLanguage.english: 'Square Meter',
  },
  'percentage': {
    AppLanguage.arabic: 'النسبة المئوية',
    AppLanguage.french: 'Pourcentage',
    AppLanguage.english: 'Percentage',
  },
  'Notes': {
    AppLanguage.arabic: 'ملاحظة',
    AppLanguage.french: 'Notice',
    AppLanguage.english: 'Notice',
  },
  'Tax Tva': {
    AppLanguage.arabic: 'ضريبة',
    AppLanguage.french: 'Taxes',
    AppLanguage.english: 'Taxes',
  },
  'Totale Sans Tva :': {
    AppLanguage.arabic: 'المجموع بدون رسوم :',
    AppLanguage.french: 'Total sans taxes :',
    AppLanguage.english: 'Total without taxes :',
  },
  'Tax (Tva) :': {
    AppLanguage.arabic: 'ضريبة :',
    AppLanguage.french: 'Taxes :',
    AppLanguage.english: 'Taxes :',
  },
  'Totale Avec Tva :': {
    AppLanguage.arabic: 'المجموع الكلي :',
    AppLanguage.french: 'Total avec taxes :',
    AppLanguage.english: 'Total with taxes :',
  },
  'Search': {
    AppLanguage.arabic: 'بحث',
    AppLanguage.french: 'Recherche',
    AppLanguage.english: 'Search',
  },
  'statistiques': {
    AppLanguage.arabic: 'الإحصائيات',
    AppLanguage.french: 'Statistiques',
    AppLanguage.english: 'Statistics',
  },
  'nouveau': {
    AppLanguage.arabic: 'جديد',
    AppLanguage.french: 'Nouveau',
    AppLanguage.english: 'New',
  },
  'rapports': {
    AppLanguage.arabic: 'التقارير',
    AppLanguage.french: 'Rapports',
    AppLanguage.english: 'Reports',
  },
  'achat': {
    AppLanguage.arabic: 'مشتريات',
    AppLanguage.french: 'Achat',
    AppLanguage.english: 'Purchases',
  },
  'deconnexion': {
    AppLanguage.arabic: 'تسجيل الخروج',
    AppLanguage.french: 'Déconnexion',
    AppLanguage.english: 'Logout',
  },
  'Confirmed': {
    AppLanguage.arabic: 'مؤكد',
    AppLanguage.french: 'Confirmé',
    AppLanguage.english: 'Confirmed',
  },
  'Delete': {
    AppLanguage.arabic: 'حذف',
    AppLanguage.french: 'Supprimer',
    AppLanguage.english: 'Delete',
  },
  'Delete Profile': {
    AppLanguage.arabic: 'حذف الملف',
    AppLanguage.french: 'Supprimer le profil',
    AppLanguage.english: 'Delete Profile',
  },
  'Delivered': {
    AppLanguage.arabic: 'تم التوصيل',
    AppLanguage.french: 'Livré',
    AppLanguage.english: 'Delivered',
  },
  'Description': {
    AppLanguage.arabic: 'الوصف',
    AppLanguage.french: 'Description',
    AppLanguage.english: 'Description',
  },
  'Fermer': {
    AppLanguage.arabic: 'إغلاق',
    AppLanguage.french: 'Fermer',
    AppLanguage.english: 'Close',
  },
  'Finished': {
    AppLanguage.arabic: 'منتهي',
    AppLanguage.french: 'Terminé',
    AppLanguage.english: 'Finished',
  },
  'In Delivery': {
    AppLanguage.arabic: 'قيد التوصيل',
    AppLanguage.french: 'En livraison',
    AppLanguage.english: 'In Delivery',
  },
  'In Instalation': {
    AppLanguage.arabic: 'قيد التركيب',
    AppLanguage.french: 'En installation',
    AppLanguage.english: 'In Installation',
  },
  'Info': {
    AppLanguage.arabic: 'معلومات',
    AppLanguage.french: 'Info',
    AppLanguage.english: 'Info',
  },
  'Informations de Conception': {
    AppLanguage.arabic: 'معلومات التصميم',
    AppLanguage.french: 'Informations de Conception',
    AppLanguage.english: 'Design Information',
  },
  'Installation Completed': {
    AppLanguage.arabic: 'اكتمل التركيب',
    AppLanguage.french: 'Installation terminée',
    AppLanguage.english: 'Installation Completed',
  },
  'New Quotation': {
    AppLanguage.arabic: 'تسعيرة جديدة',
    AppLanguage.french: 'Nouveau Devis',
    AppLanguage.english: 'New Quotation',
  },
  'No Data': {
    AppLanguage.arabic: 'لا توجد بيانات',
    AppLanguage.french: 'Aucune donnée',
    AppLanguage.english: 'No Data',
  },
  'Phone Numbers:': {
    AppLanguage.arabic: 'أرقام الهواتف:',
    AppLanguage.french: 'Numéros de téléphone:',
    AppLanguage.english: 'Phone Numbers:',
  },
  'Profile added': {
    AppLanguage.arabic: 'تم إضافة الملف',
    AppLanguage.french: 'Profil ajouté',
    AppLanguage.english: 'Profile added',
  },
  'Profile updated': {
    AppLanguage.arabic: 'تم تحديث الملف',
    AppLanguage.french: 'Profil mis à jour',
    AppLanguage.english: 'Profile updated',
  },
  'Save': {
    AppLanguage.arabic: 'حفظ',
    AppLanguage.french: 'Enregistrer',
    AppLanguage.english: 'Save',
  },
  'Total Payments': {
    AppLanguage.arabic: 'إجمالي المدفوعات',
    AppLanguage.french: 'Total des paiements',
    AppLanguage.english: 'Total Payments',
  },
  'إضافة نظام ألمنيوم جديد': {
    AppLanguage.arabic: 'إضافة نظام ألمنيوم جديد',
    AppLanguage.french: 'Ajouter un nouveau système en aluminium',
    AppLanguage.english: 'Add New Aluminum System',
  },
  'إطار سفلي': {
    AppLanguage.arabic: 'إطار سفلي',
    AppLanguage.french: 'Cadre de base',
    AppLanguage.english: 'Bottom Frame',
  },
  'تأكيد الخروج': {
    AppLanguage.arabic: 'تأكيد الخروج',
    AppLanguage.french: 'Confirmation de sortie',
    AppLanguage.english: 'Confirm Exit',
  },
  'هل تريد الخروج من صفحة الرسم؟': {
    AppLanguage.arabic: 'هل تريد الخروج من صفحة الرسم؟',
    AppLanguage.french: 'Voulez-vous quitter la page de dessin ?',
    AppLanguage.english: 'Do you want to leave the drawing page?',
  },
  'خروج': {
    AppLanguage.arabic: 'خروج',
    AppLanguage.french: 'Quitter',
    AppLanguage.english: 'Exit',
  },
  'الخروج من التطبيق': {
    AppLanguage.arabic: 'الخروج من التطبيق',
    AppLanguage.french: 'Quitter l\'application',
    AppLanguage.english: 'Exit Application',
  },
  'هل تريد الخروج من التطبيق؟': {
    AppLanguage.arabic: 'هل تريد الخروج من التطبيق؟',
    AppLanguage.french: 'Voulez-vous quitter l\'application ?',
    AppLanguage.english: 'Do you want to exit the application?',
  },
  'تم تحويل القياس الحالي إلى ستار': {
    AppLanguage.arabic: 'تم تحويل القياس الحالي إلى ستار',
    AppLanguage.french: 'La mesure actuelle a été convertie en volet',
    AppLanguage.english: 'The current measurement was converted to a shutter',
  },
  'فاقد المنشار والحد الأدنى للفضلات حسب نوع القطعة.': {
    AppLanguage.arabic: 'فاقد المنشار والحد الأدنى للفضلات حسب نوع القطعة.',
    AppLanguage.french:
        'Perte de scie et minimum de chute selon le type de pièce.',
    AppLanguage.english: 'Saw kerf and minimum remnant by part type.',
  },
  'اختر نظام العمل': {
    AppLanguage.arabic: 'اختر نظام العمل',
    AppLanguage.french: 'Sélectionnez le système de travail',
    AppLanguage.english: 'Select the work system',
  },
  'اختر نظاماً أولاً': {
    AppLanguage.arabic: 'اختر نظاماً أولاً',
    AppLanguage.french: 'Choisissez d\'abord un système',
    AppLanguage.english: 'Choose a system first',
  },
  'التصوير بالكاميرا فوراً': {
    AppLanguage.arabic: 'التصوير بالكاميرا فوراً',
    AppLanguage.french: 'Prendre une photo immédiatement',
    AppLanguage.english: 'Take photo immediately',
  },
  'الجوانب:': {
    AppLanguage.arabic: 'الجوانب:',
    AppLanguage.french: 'Côtés:',
    AppLanguage.english: 'Sides:',
  },
  'الذكاء الاصطناعي متاح مجاناً للمعاينة': {
    AppLanguage.arabic: 'الذكاء الاصطناعي متاح مجاناً للمعاينة',
    AppLanguage.french: 'L’IA est disponible en aperçu gratuit',
    AppLanguage.english: 'AI is available for free preview',
  },
  'القيمة الإجمالية': {
    AppLanguage.arabic: 'القيمة الإجمالية',
    AppLanguage.french: 'Valeur totale',
    AppLanguage.english: 'Total Value',
  },
  'المعالجة:': {
    AppLanguage.arabic: 'المعالجة:',
    AppLanguage.french: 'Traitement:',
    AppLanguage.english: 'Treatment:',
  },
  'المواد:': {
    AppLanguage.arabic: 'المواد:',
    AppLanguage.french: 'Matériaux:',
    AppLanguage.english: 'Materials:',
  },
  'النظام الفرنسي - System Francer': {
    AppLanguage.arabic: 'النظام الفرنسي',
    AppLanguage.french: 'Système Français',
    AppLanguage.english: 'French System',
  },
  'باغيت (Parclose)': {
    AppLanguage.arabic: 'باغيت (Parclose)',
    AppLanguage.french: 'Parclose',
    AppLanguage.english: 'Glazing Bead',
  },
  'بانوا': {
    AppLanguage.arabic: 'بانوا',
    AppLanguage.french: 'Panneau',
    AppLanguage.english: 'Panel',
  },
  'تأكيد الإلغاء': {
    AppLanguage.arabic: 'تأكيد الإلغاء',
    AppLanguage.french: 'Confirmer l\'annulation',
    AppLanguage.english: 'Confirm Cancellation',
  },
  'تاريخ التسجيل': {
    AppLanguage.arabic: 'تاريخ التسجيل',
    AppLanguage.french: 'Date d\'inscription',
    AppLanguage.english: 'Registration Date',
  },
  'تجاهل هذه السلعة': {
    AppLanguage.arabic: 'تجاهل هذه السلعة',
    AppLanguage.french: 'Ignorer cet article',
    AppLanguage.english: 'Ignore this item',
  },
  'تصدير ملف الكميات': {
    AppLanguage.arabic: 'تصدير ملف الكميات',
    AppLanguage.french: 'Exporter le fichier de quantités',
    AppLanguage.english: 'Export quantities file',
  },
  'تصميم النوافذ': {
    AppLanguage.arabic: 'تصميم النوافذ',
    AppLanguage.french: 'Conception de fenêtres',
    AppLanguage.english: 'Windows Design',
  },
  'تطبيق': {
    AppLanguage.arabic: 'تطبيق',
    AppLanguage.french: 'Appliquer',
    AppLanguage.english: 'Apply',
  },
  'تعديل المطابقة': {
    AppLanguage.arabic: 'تعديل المطابقة',
    AppLanguage.french: 'Modifier la correspondance',
    AppLanguage.english: 'Edit Match',
  },
  'تعديل بيانات النظام': {
    AppLanguage.arabic: 'تعديل بيانات النظام',
    AppLanguage.french: 'Modifier les données du système',
    AppLanguage.english: 'Edit System Data',
  },
  'تفعيل الأغطية الجانبية (المستطيل الكبير):': {
    AppLanguage.arabic: 'تفعيل الأغطية الجانبية',
    AppLanguage.french: 'Activer les caches latéraux',
    AppLanguage.english: 'Enable side covers',
  },
  'تقسيم متساوي (عدد القطع)': {
    AppLanguage.arabic: 'تقسيم متساوي (عدد القطع)',
    AppLanguage.french: 'Division égale (nombre de pièces)',
    AppLanguage.english: 'Equal division (number of pieces)',
  },
  'تقسيم:': {
    AppLanguage.arabic: 'تقسيم:',
    AppLanguage.french: 'Division:',
    AppLanguage.english: 'Division:',
  },
  'تيار / تقسيم (Mullion)': {
    AppLanguage.arabic: 'تيار / تقسيم (Mullion)',
    AppLanguage.french: 'Meneau',
    AppLanguage.english: 'Mullion',
  },
  'حذف نهائي': {
    AppLanguage.arabic: 'حذف نهائي',
    AppLanguage.french: 'Suppression définitive',
    AppLanguage.english: 'Permanent Delete',
  },
  'حفظ التعديل': {
    AppLanguage.arabic: 'حفظ التعديل',
    AppLanguage.french: 'Enregistrer la modification',
    AppLanguage.english: 'Save Edit',
  },
  'حفظ وتسجيل': {
    AppLanguage.arabic: 'حفظ وتسجيل',
    AppLanguage.french: 'Enregistrer',
    AppLanguage.english: 'Save and Register',
  },
  'حفظ وإضافة عناصر': {
    AppLanguage.arabic: 'حفظ وإضافة عناصر',
    AppLanguage.french: 'Enregistrer et ajouter des articles',
    AppLanguage.english: 'Save and add items',
  },
  'حلق خارجي (Frame)': {
    AppLanguage.arabic: 'حلق خارجي (اطار)',
    AppLanguage.french: 'Cadre',
    AppLanguage.english: 'Frame',
  },
  'ضلفة (Sash)': {
    AppLanguage.arabic: 'ضلفة (Sash)',
    AppLanguage.french: 'Ouvrant',
    AppLanguage.english: 'Sash',
  },
  'قياس مخصص (للفراغ)': {
    AppLanguage.arabic: 'قياس مخصص (للفراغ)',
    AppLanguage.french: 'Mesure personnalisée',
    AppLanguage.english: 'Custom Measurement',
  },
  'لا توجد مقاطع بالكتالوج حالياً.': {
    AppLanguage.arabic: 'لا توجد مقاطع بالكتالوج حالياً.',
    AppLanguage.french: 'Aucun profil dans le catalogue actuellement.',
    AppLanguage.english: 'No profiles in the catalog currently.',
  },
  'مزدوج': {
    AppLanguage.arabic: 'مزدوج',
    AppLanguage.french: 'Double',
    AppLanguage.english: 'Double',
  },
  'مفرد': {
    AppLanguage.arabic: 'مفرد',
    AppLanguage.french: 'Simple',
    AppLanguage.english: 'Single',
  },
  'نافذة ضلفة مزدوجة (Double Ouvante)': {
    AppLanguage.arabic: 'نافذة ضلفة مزدوجة',
    AppLanguage.french: 'Fenêtre Double Ouvrante',
    AppLanguage.english: 'Double Casement Window',
  },
  'نظام جديد': {
    AppLanguage.arabic: 'نظام جديد',
    AppLanguage.french: 'Nouveau système',
    AppLanguage.english: 'New System',
  },
  'نوع البانو:': {
    AppLanguage.arabic: 'نوع البانو:',
    AppLanguage.french: 'Type de panneau:',
    AppLanguage.english: 'Panel type:',
  },
  'اسم الإكسسوار': {
    AppLanguage.arabic: 'اسم الإكسسوار',
    AppLanguage.french: 'Nom de l\'accessoire',
    AppLanguage.english: 'Accessory Name',
  },
  'نوع الإكسسوار': {
    AppLanguage.arabic: 'نوع الإكسسوار',
    AppLanguage.french: 'Type d\'accessoire',
    AppLanguage.english: 'Accessory Type',
  },
  'إضافة إكسسوار جديد': {
    AppLanguage.arabic: 'إضافة إكسسوار جديد',
    AppLanguage.french: 'Ajouter un nouvel accessoire',
    AppLanguage.english: 'Add New Accessory',
  },
  'الستائر': {
    AppLanguage.arabic: 'الستائر',
    AppLanguage.french: 'Volets',
    AppLanguage.english: 'Shutters',
  },
  'المقاطع': {
    AppLanguage.arabic: 'مقاطع (بارات)',
    AppLanguage.french: 'Sections (Barres)',
    AppLanguage.english: 'Sections (Bars)',
  },
  'ستائر': {
    AppLanguage.arabic: 'مركبات الستائر',
    AppLanguage.french: 'Volet Roulant',
    AppLanguage.english: 'Shutters Components',
  },
  'أو': {
    AppLanguage.arabic: 'أو',
    AppLanguage.french: 'ou',
    AppLanguage.english: 'or',
  },
  'إذا كان مفصلي/فراب،': {
    AppLanguage.arabic: 'إذا كان مفصلي/فراب،',
    AppLanguage.french: 'Si c\'est battant/frappe,',
    AppLanguage.english: 'If it is casement/frappe,',
  },
  'الخاص بك:\\n\$workshopCode': {
    AppLanguage.arabic: 'الخاص بك:\\n\$workshopCode',
    AppLanguage.french: 'Votre code :\\n\$workshopCode',
    AppLanguage.english: 'Your code:\\n\$workshopCode',
  },
  'وإضافة نافذة بمقاس \$width × \$height': {
    AppLanguage.arabic: 'وإضافة نافذة بمقاس \$width × \$height',
    AppLanguage.french: 'et ajouter une fenêtre de \$width × \$height',
    AppLanguage.english: 'and add a window of \$width × \$height',
  },
  ')': {
    AppLanguage.arabic: ')',
    AppLanguage.french: ')',
    AppLanguage.english: ')',
  },
  '- color: لون الألمنيوم (مثلا': {
    AppLanguage.arabic: '- color: لون الألمنيوم (مثلا',
    AppLanguage.french: '- couleur : couleur de l\'aluminium (ex :',
    AppLanguage.english: '- color: aluminum color (ex:',
  },
  '15 يوماً': {
    AppLanguage.arabic: '15 يوماً',
    AppLanguage.french: '15 jours',
    AppLanguage.english: '15 days',
  },
  '30 يوماً': {
    AppLanguage.arabic: '30 يوماً',
    AppLanguage.french: '30 jours',
    AppLanguage.english: '30 days',
  },
  '7 أيام': {
    AppLanguage.arabic: '7 أيام',
    AppLanguage.french: '7 jours',
    AppLanguage.english: '7 days',
  },
  'أبيض': {
    AppLanguage.arabic: 'أبيض',
    AppLanguage.french: 'Blanc',
    AppLanguage.english: 'White',
  },
  'أجرة': {
    AppLanguage.arabic: 'أجرة',
    AppLanguage.french: 'Salaire',
    AppLanguage.english: 'Salary',
  },
  'أسعار المتر والإكسسوارات': {
    AppLanguage.arabic: 'أسعار المتر والإكسسوارات',
    AppLanguage.french: 'Prix du mètre & accessoires',
    AppLanguage.english: 'Meter & Accessory Prices',
  },
  'أسفل': {
    AppLanguage.arabic: 'أسفل',
    AppLanguage.french: 'Bas',
    AppLanguage.english: 'Bottom',
  },
  'أسود': {
    AppLanguage.arabic: 'أسود',
    AppLanguage.french: 'Noir',
    AppLanguage.english: 'Black',
  },
  'أصفر': {
    AppLanguage.arabic: 'أصفر',
    AppLanguage.french: 'Jaune',
    AppLanguage.english: 'Yellow',
  },
  'أعلى': {
    AppLanguage.arabic: 'أعلى',
    AppLanguage.french: 'Haut',
    AppLanguage.english: 'Top',
  },
  'أفقي': {
    AppLanguage.arabic: 'أفقي',
    AppLanguage.french: 'Horizontal',
    AppLanguage.english: 'Horizontal',
  },
  'ألصق المفتاح هنا...': {
    AppLanguage.arabic: 'ألصق المفتاح هنا...',
    AppLanguage.french: 'Coller la clé ici...',
    AppLanguage.english: 'Paste key here...',
  },
  '\'\'\'إجمالي القياس الصافي: \$': {
    AppLanguage.arabic: '',
    AppLanguage.french: '',
    AppLanguage.english: '',
  },
  'إجمالي المشتريات': {
    AppLanguage.arabic: 'إجمالي المشتريات',
    AppLanguage.french: 'Total des achats',
    AppLanguage.english: 'Total Purchases',
  },
  'إجمالي ما استلمه: \$totalReceived د.ج': {
    AppLanguage.arabic: 'إجمالي ما استلمه: \$totalReceived د.ج',
    AppLanguage.french: 'Total reçu : \$totalReceived DA',
    AppLanguage.english: 'Total received: \$totalReceived DA',
  },
  'اتجاه الفتح وسمك الضلفة:': {
    AppLanguage.arabic: 'اتجاه الفتح وسمك الضلفة:',
    AppLanguage.french: 'Direction d\'ouverture et épaisseur de l\'ouvrant :',
    AppLanguage.english: 'Opening direction and sash thickness:',
  },
  'اختر المدة التي تريد منحها للمستخدم:': {
    AppLanguage.arabic: 'اختر المدة التي تريد منحها للمستخدم:',
    AppLanguage.french: 'Choisissez la durée à accorder à l\'utilisateur :',
    AppLanguage.english: 'Choose the duration to grant the user:',
  },
  'اختيار نوع النظام': {
    AppLanguage.arabic: 'اختيار نوع النظام',
    AppLanguage.french: 'Choisir le type de système',
    AppLanguage.english: 'Choose system type',
  },
  'استعادة البيانات': {
    AppLanguage.arabic: 'استعادة البيانات',
    AppLanguage.french: 'Restaurer les données',
    AppLanguage.english: 'Restore data',
  },
  'اسم المورد *': {
    AppLanguage.arabic: 'اسم المورد *',
    AppLanguage.french: 'Nom du fournisseur *',
    AppLanguage.english: 'Supplier Name *',
  },
  'اسم المورد أو الشركة البائعة': {
    AppLanguage.arabic: 'اسم المورد أو الشركة البائعة',
    AppLanguage.french: 'Nom du fournisseur ou de la société vendeuse',
    AppLanguage.english: 'Supplier or vendor name',
  },
  'اكتب ملاحظتك، شكواك، أو اقتراحك هنا...': {
    AppLanguage.arabic: 'اكتب ملاحظتك، شكواك، أو اقتراحك هنا...',
    AppLanguage.french: 'Écrivez votre note, plainte ou suggestion ici...',
    AppLanguage.english: 'Write your note, complaint, or suggestion here...',
  },
  'الإطار/الحلق': {
    AppLanguage.arabic: 'الإطار/الحلق',
    AppLanguage.french: 'Cadre/Dormant',
    AppLanguage.english: 'Frame/Dormant',
  },
  'الإكسسوارات (Accessories)': {
    AppLanguage.arabic: 'الإكسسوارات (Accessories)',
    AppLanguage.french: 'Accessoires (Accessories)',
    AppLanguage.english: 'Accessories (Accessories)',
  },
  'البُعد الصافي للفراغ (mm)': {
    AppLanguage.arabic: 'البُعد الصافي للفراغ (mm)',
    AppLanguage.french: 'Dimension nette de l\'espace (mm)',
    AppLanguage.english: 'Net spacing dimension (mm)',
  },
  'الرجاء إدخال رقم صحيح': {
    AppLanguage.arabic: 'الرجاء إدخال رقم صحيح',
    AppLanguage.french: 'الرجاء إدخال Numéro صحيح',
    AppLanguage.english: 'الرجاء إدخال Number صحيح',
  },
  'الرجاء التأكد من وجود': {
    AppLanguage.arabic: 'الرجاء التأكد من وجود',
    AppLanguage.french: 'الرجاء التأكد من وجود',
    AppLanguage.english: 'الرجاء التأكد من وجود',
  },
  'الرد المستلم من الذكاء الاصطناعي فارغ.': {
    AppLanguage.arabic: 'الرد المستلم من الذكاء الاصطناعي فارغ.',
    AppLanguage.french: 'الرد المستلم من الذكاء الاصطناعي فارغ.',
    AppLanguage.english: 'الرد المستلم من الذكاء الاصطناعي فارغ.',
  },
  'الرصيد الإجمالي': {
    AppLanguage.arabic: 'الرصيد الإجمالي',
    AppLanguage.french: 'Solde Total',
    AppLanguage.english: 'Total Balance',
  },
  'الستائر (Shutters)': {
    AppLanguage.arabic: 'الستائر (Shutters)',
    AppLanguage.french: 'Volets Roulants',
    AppLanguage.english: 'Shutters',
  },
  '\'\'\'الصلاحية: \$': {
    AppLanguage.arabic: 'الصلاحية: \${role ==',
    AppLanguage.french: 'الصلاحية: \${role ==',
    AppLanguage.english: 'الصلاحية: \${role ==',
  },
  'سماكة القطاع / Thickness (mm)': {
    AppLanguage.arabic: 'سماكة القطاع / Thickness (mm)',
    AppLanguage.french: 'Épaisseur / Thickness (mm)',
    AppLanguage.english: 'Thickness (mm)',
  },
  'علوية': {
    AppLanguage.arabic: 'علوية',
    AppLanguage.french: 'Haut',
    AppLanguage.english: 'Top',
  },
  'يسرى': {
    AppLanguage.arabic: 'يسرى',
    AppLanguage.french: 'Gauche',
    AppLanguage.english: 'Left',
  },
  'يمنى': {
    AppLanguage.arabic: 'يمنى',
    AppLanguage.french: 'Droite',
    AppLanguage.english: 'Right',
  },
  'سفلية': {
    AppLanguage.arabic: 'سفلية',
    AppLanguage.french: 'Bas',
    AppLanguage.english: 'Bottom',
  },
  'خصائص الزجاج': {
    AppLanguage.arabic: 'خصائص الزجاج',
    AppLanguage.french: 'Propriétés du vitrage',
    AppLanguage.english: 'Glass Properties',
  },
  'نوع الباجيت:': {
    AppLanguage.arabic: 'نوع الباجيت:',
    AppLanguage.french: 'Type de parclose :',
    AppLanguage.english: 'Glass bead type:',
  },
  'ديكور الزجاج المزدوج (ورود):': {
    AppLanguage.arabic: 'ديكور الزجاج المزدوج (ورود):',
    AppLanguage.french: 'Décor du double vitrage (rosaces) :',
    AppLanguage.english: 'Double-glazing décor (rosettes):',
  },
  'وردات': {
    AppLanguage.arabic: 'وردات',
    AppLanguage.french: 'Rosaces',
    AppLanguage.english: 'Rosettes',
  },
  'لا توجد وردات ديكور في قاعدة البيانات. يرجى إضافتها أولاً.': {
    AppLanguage.arabic:
        'لا توجد وردات ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
    AppLanguage.french:
        'Aucune rosace décorative dans la base de données. Veuillez d’abord en ajouter.',
    AppLanguage.english:
        'No decorative rosettes found in the database. Please add them first.',
  },
  'سمك الفاصل (Intercall) — المقترح تلقائياً حسب Parclose:': {
    AppLanguage.arabic:
        'سمك الفاصل (Intercall) — المقترح تلقائياً حسب Parclose:',
    AppLanguage.french:
        'Épaisseur de l’intercalaire (Intercall) — proposée automatiquement selon la parclose :',
    AppLanguage.english:
        'Spacer thickness (Intercall) — automatically suggested by the parclose:',
  },
  'سُمك الزجاج مطابق لسعة البيركلوز': {
    AppLanguage.arabic: 'سُمك الزجاج مطابق لسعة البيركلوز',
    AppLanguage.french:
        'L’épaisseur du vitrage correspond à la capacité de la parclose',
    AppLanguage.english: 'Glass thickness matches the parclose capacity',
  },
  'عرض الضلفة اليسرى (مم)': {
    AppLanguage.arabic: 'عرض الضلفة اليسرى (مم)',
    AppLanguage.french: 'Largeur du battant gauche (mm)',
    AppLanguage.english: 'Left sash width (mm)',
  },
  'هيكل الزجاج:': {
    AppLanguage.arabic: 'هيكل الزجاج:',
    AppLanguage.french: 'Structure du vitrage :',
    AppLanguage.english: 'Glass structure:',
  },
  'سمك الزجاج:': {
    AppLanguage.arabic: 'سمك الزجاج:',
    AppLanguage.french: 'Épaisseur du vitrage :',
    AppLanguage.english: 'Glass thickness:',
  },
  '\'\'\'القطعة الوسطى: \$': {
    AppLanguage.arabic: '',
    AppLanguage.french: '',
    AppLanguage.english: '',
  },
  'القيمة الإجمالية (دج) *': {
    AppLanguage.arabic: 'القيمة الإجمالية (دج) *',
    AppLanguage.french: 'Valeur totale (DA) *',
    AppLanguage.english: 'Total Value (DA) *',
  },
  '\'\'\'الكود المستخرج: \$': {
    AppLanguage.arabic: 'الكود المستخرج: \${item.itemCode.isEmpty ?',
    AppLanguage.french: 'الCode المستخرج: \${item.itemCode.isEmpty ?',
    AppLanguage.english: 'الCode المستخرج: \${item.itemCode.isEmpty ?',
  },
  'اللقب': {
    AppLanguage.arabic: 'اللقب',
    AppLanguage.french: 'Prénom',
    AppLanguage.english: 'Last Name',
  },
  '\'\'\'المنطقة المحددة: \$': {
    AppLanguage.arabic: '',
    AppLanguage.french: '',
    AppLanguage.english: '',
  },
  'النسخ الاحتياطي (Cloud Sync)': {
    AppLanguage.arabic: 'النسخ الاحتياطي (Cloud Sync)',
    AppLanguage.french: 'Sauvegarde (Cloud Sync)',
    AppLanguage.english: 'Backup (Cloud Sync)',
  },
  'النطاق': {
    AppLanguage.arabic: 'النطاق',
    AppLanguage.french: 'Portée',
    AppLanguage.english: 'Scope',
  },
  'النوع:': {
    AppLanguage.arabic: 'النوع:',
    AppLanguage.french: 'Type :',
    AppLanguage.english: 'Type:',
  },
  '\'\'\'النوع: \$': {
    AppLanguage.arabic: 'النوع: \${sec[',
    AppLanguage.french: 'الType: \${sec[',
    AppLanguage.english: 'الType: \${sec[',
  },
  'الهاتف': {
    AppLanguage.arabic: 'الهاتف',
    AppLanguage.french: 'Téléphone',
    AppLanguage.english: 'Phone',
  },
  'الوجه الخارجي': {
    AppLanguage.arabic: 'الوجه الخارجي',
    AppLanguage.french: 'Face extérieure',
    AppLanguage.english: 'Outer face',
  },
  'الوجه الداخلي': {
    AppLanguage.arabic: 'الوجه الداخلي',
    AppLanguage.french: 'Face intérieure',
    AppLanguage.english: 'Inner face',
  },
  'المظهر:': {
    AppLanguage.arabic: 'المظهر:',
    AppLanguage.french: 'Aspect :',
    AppLanguage.english: 'Appearance:',
  },
  'المظهر (بانو):': {
    AppLanguage.arabic: 'المظهر (بانو):',
    AppLanguage.french: 'Aspect (panneau) :',
    AppLanguage.english: 'Appearance (panel):',
  },
  'انقر على': {
    AppLanguage.arabic: 'انقر على',
    AppLanguage.french: 'Cliquer sur',
    AppLanguage.english: 'Click on',
  },
  'انقر لتحديد وتعديل أي منطقة': {
    AppLanguage.arabic: 'انقر لتحديد وتعديل أي منطقة',
    AppLanguage.french:
        'Cliquer pour sélectionner et modifier n\'importe quelle zone',
    AppLanguage.english: 'Click to select and edit any zone',
  },
  'بدون بريد إلكتروني': {
    AppLanguage.arabic: 'بدون بريد إلكتروني',
    AppLanguage.french: 'Sans e-mail',
    AppLanguage.english: 'Without email',
  },
  'برونز': {
    AppLanguage.arabic: 'برونز',
    AppLanguage.french: 'Bronze',
    AppLanguage.english: 'Bronze',
  },
  'بليكسي قلاس': {
    AppLanguage.arabic: 'بليكسي قلاس',
    AppLanguage.french: 'Plexiglas',
    AppLanguage.english: 'Plexiglass',
  },
  'بني': {
    AppLanguage.arabic: 'بني',
    AppLanguage.french: 'Marron',
    AppLanguage.english: 'Brown',
  },
  'بيج': {
    AppLanguage.arabic: 'بيج',
    AppLanguage.french: 'Beige',
    AppLanguage.english: 'Beige',
  },
  '\'\'\'تاريخ الانتهاء: \$': {
    AppLanguage.arabic: 'تاريخ الانتهاء: \${DateFormat(',
    AppLanguage.french: 'Date الانتهاء: \${DateFormat(',
    AppLanguage.english: 'Date الانتهاء: \${DateFormat(',
  },
  'تجريبي فعال (باقي \$daysLeft يوم)': {
    AppLanguage.arabic: 'تجريبي فعال (باقي \$daysLeft يوم)',
    AppLanguage.french: 'Essai actif (reste \$daysLeft jours)',
    AppLanguage.english: 'Trial active (\$daysLeft days remaining)',
  },
  'تخصيص جهات الغطاء الجانبي:': {
    AppLanguage.arabic: 'تخصيص جهات الغطاء الجانبي:',
    AppLanguage.french: 'Personnaliser les côtés des embouts :',
    AppLanguage.english: 'Customize end cap sides:',
  },
  'تطبيق القياس الجديد': {
    AppLanguage.arabic: 'تطبيق القياس الجديد',
    AppLanguage.french: 'Appliquer les nouvelles dimensions',
    AppLanguage.english: 'Apply new dimensions',
  },
  'تعديل الفراغ الأيسر (mm)': {
    AppLanguage.arabic: 'تعديل الفراغ الأيسر (mm)',
    AppLanguage.french: 'Modifier l\'espace gauche (mm)',
    AppLanguage.english: 'Edit left gap (mm)',
  },
  'تعديل الفراغ الأيمن (mm)': {
    AppLanguage.arabic: 'تعديل الفراغ الأيمن (mm)',
    AppLanguage.french: 'Modifier l\'espace droit (mm)',
    AppLanguage.english: 'Edit right gap (mm)',
  },
  'تعديل الفراغ السفلي (mm)': {
    AppLanguage.arabic: 'تعديل الفراغ السفلي (mm)',
    AppLanguage.french: 'Modifier l\'espace inférieur (mm)',
    AppLanguage.english: 'Edit bottom gap (mm)',
  },
  'تعديل الفراغ العلوي (mm)': {
    AppLanguage.arabic: 'تعديل الفراغ العلوي (mm)',
    AppLanguage.french: 'Modifier l\'espace supérieur (mm)',
    AppLanguage.english: 'Edit top gap (mm)',
  },
  'تغيير الأسعار': {
    AppLanguage.arabic: 'تغيير الأسعار',
    AppLanguage.french: 'Changer les prix',
    AppLanguage.english: 'Change Prices',
  },
  'تقسيم متساوي (حسب عدد القطع)': {
    AppLanguage.arabic: 'تقسيم متساوي (حسب عدد القطع)',
    AppLanguage.french: 'Division égale (selon le nombre de pièces)',
    AppLanguage.english: 'Equal division (by number of pieces)',
  },
  '\'\'\'تقييم التطبيق: \$_rating نجوم\\nالملاحظة/الشكوى: \$': {
    AppLanguage.arabic: '',
    AppLanguage.french: '',
    AppLanguage.english: '',
  },
  'تم الرفع إلى السحابة بنجاح!': {
    AppLanguage.arabic: 'تم الرفع إلى السحابة بنجاح!',
    AppLanguage.french: 'Téléchargé sur le cloud avec succès !',
    AppLanguage.english: 'Uploaded to cloud successfully!',
  },
  'تم تجاهل السلعة': {
    AppLanguage.arabic: 'تم تجاهل السلعة',
    AppLanguage.french: 'Article ignoré',
    AppLanguage.english: 'Item ignored',
  },
  'تم مزامنة بيانات جديدة من السحابة 🔄': {
    AppLanguage.arabic: 'تم مزامنة بيانات جديدة من السحابة 🔄',
    AppLanguage.french: 'Nouvelles données synchronisées depuis le cloud 🔄',
    AppLanguage.english: 'New data synchronized from cloud 🔄',
  },
  'جاري التحميل...': {
    AppLanguage.arabic: 'جاري التحميل...',
    AppLanguage.french: 'Chargement...',
    AppLanguage.english: 'Loading...',
  },
  'حدث خطأ أثناء الحفظ: \$e': {
    AppLanguage.arabic: 'حدث خطأ أثناء الحفظ: \$e',
    AppLanguage.french: 'Erreur lors de l\'enregistrement : \$e',
    AppLanguage.english: 'Error during save: \$e',
  },
  'حدث خطأ: \$e': {
    AppLanguage.arabic: 'حدث خطأ: \$e',
    AppLanguage.french: 'Une erreur est survenue : \$e',
    AppLanguage.english: 'An error occurred: \$e',
  },
  '\'\'\'حدث خطأ: \$': {
    AppLanguage.arabic: 'حدث خطأ: \${e.message}',
    AppLanguage.french: 'حدث Erreur: \${e.message}',
    AppLanguage.english: 'حدث Error: \${e.message}',
  },
  'حدد السلاسل': {
    AppLanguage.arabic: 'حدد السلاسل',
    AppLanguage.french: 'Sélectionner les séries',
    AppLanguage.english: 'Select series',
  },
  'حذف التقسيم': {
    AppLanguage.arabic: 'حذف التقسيم',
    AppLanguage.french: 'Supprimer la division',
    AppLanguage.english: 'Delete division',
  },
  'حفظ تعديل': {
    AppLanguage.arabic: 'حفظ تعديل',
    AppLanguage.french: 'Enregistrer la modification',
    AppLanguage.english: 'Save edit',
  },
  'حلق ألمنيوم 45 مم (Frame)': {
    AppLanguage.arabic: 'حلق ألمنيوم 45 مم (Frame)',
    AppLanguage.french: 'Cadre aluminium 45 mm',
    AppLanguage.english: 'Aluminium frame 45 mm',
  },
  'خام': {
    AppLanguage.arabic: 'خام',
    AppLanguage.french: 'Brut',
    AppLanguage.english: 'Raw',
  },
  'بدون لون / اللون الخام': {
    AppLanguage.arabic: 'خام',
    AppLanguage.french: 'Brut',
    AppLanguage.english: 'Raw',
  },
  'خالصة': {
    AppLanguage.arabic: 'خالصة',
    AppLanguage.french: 'Payée intégralement',
    AppLanguage.english: 'Fully Paid',
  },
  'خشب': {
    AppLanguage.arabic: 'خشب',
    AppLanguage.french: 'Bois',
    AppLanguage.english: 'Wood',
  },
  'خشبي': {
    AppLanguage.arabic: 'خشبي',
    AppLanguage.french: 'Bois',
    AppLanguage.english: 'Wood',
  },
  'خطأ': {
    AppLanguage.arabic: 'خطأ',
    AppLanguage.french: 'Erreur',
    AppLanguage.english: 'Error',
  },
  'خطأ في قاعدة البيانات: \$e': {
    AppLanguage.arabic: 'خطأ في قاعدة البيانات: \$e',
    AppLanguage.french: 'Erreur de base de données : \$e',
    AppLanguage.english: 'Database error: \$e',
  },
  'رفع للسحابة': {
    AppLanguage.arabic: 'رفع للسحابة',
    AppLanguage.french: 'Télécharger vers le cloud',
    AppLanguage.english: 'Upload to cloud',
  },
  'رمادي': {
    AppLanguage.arabic: 'رمادي',
    AppLanguage.french: 'Gris',
    AppLanguage.english: 'Grey',
  },
  'ساعدنا في تحسين التطبيق': {
    AppLanguage.arabic: 'ساعدنا في تحسين التطبيق',
    AppLanguage.french: 'Aidez-nous à améliorer l\'application',
    AppLanguage.english: 'Help us improve the app',
  },
  'سحب التطبيق نهائياً (طرد)': {
    AppLanguage.arabic: 'سحب التطبيق نهائياً (طرد)',
    AppLanguage.french: 'Retirer définitivement l\'application',
    AppLanguage.english: 'Terminate app usage',
  },
  'سلفة': {
    AppLanguage.arabic: 'سلفة',
    AppLanguage.french: 'Avance',
    AppLanguage.english: 'Advance',
  },
  '\'\'\'سماكة: \$': {
    AppLanguage.arabic: 'سماكة: \${sec[',
    AppLanguage.french: 'Épaisseur: \${sec[',
    AppLanguage.english: 'Thickness: \${sec[',
  },
  'شفاف/عادي': {
    AppLanguage.arabic: 'شفاف/عادي',
    AppLanguage.french: 'Transparent/Standard',
    AppLanguage.english: 'Transparent/Standard',
  },
  'ضلفة جرار عريضة (Sliding Sash)': {
    AppLanguage.arabic: 'ضلفة جرار عريضة (Sliding Sash)',
    AppLanguage.french: 'Ouvrant coulissant large',
    AppLanguage.english: 'Sliding Sash',
  },
  'ضلفة واحدة': {
    AppLanguage.arabic: 'ضلفة واحدة',
    AppLanguage.french: 'Un seul ouvrant',
    AppLanguage.english: 'Single sash',
  },
  'ضلفتان': {
    AppLanguage.arabic: 'ضلفتان',
    AppLanguage.french: 'Double ouvrant',
    AppLanguage.english: 'Double sash',
  },
  'عادي': {
    AppLanguage.arabic: 'عادي',
    AppLanguage.french: 'Standard',
    AppLanguage.english: 'Standard',
  },
  'عام': {
    AppLanguage.arabic: 'عام',
    AppLanguage.french: 'Général',
    AppLanguage.english: 'General',
  },
  'عام (Global)': {
    AppLanguage.arabic: 'عام (Global)',
    AppLanguage.french: 'Général (Global)',
    AppLanguage.english: 'Global',
  },
  'عام لجميع السلاسل': {
    AppLanguage.arabic: 'عام لجميع السلاسل',
    AppLanguage.french: 'Général pour toutes les séries',
    AppLanguage.english: 'General for all series',
  },
  'عذراً': {
    AppLanguage.arabic: 'عذراً',
    AppLanguage.french: 'Désolé',
    AppLanguage.english: 'Sorry',
  },
  'عمودي': {
    AppLanguage.arabic: 'عمودي',
    AppLanguage.french: 'Vertical',
    AppLanguage.english: 'Vertical',
  },
  'غطاء جانبي': {
    AppLanguage.arabic: 'غطاء جانبي',
    AppLanguage.french: 'Couvre-joint',
    AppLanguage.english: 'Side Cover',
  },
  'غير خالصة': {
    AppLanguage.arabic: 'غير خالصة',
    AppLanguage.french: 'Non payée intégralement',
    AppLanguage.english: 'Not Fully Paid',
  },
  'غير متوفر': {
    AppLanguage.arabic: 'غير متوفر',
    AppLanguage.french: 'Non disponible',
    AppLanguage.english: 'Not available',
  },
  'غير مطابقة': {
    AppLanguage.arabic: 'غير مطابقة',
    AppLanguage.french: 'Non conforme',
    AppLanguage.english: 'Non-conforming',
  },
  'غير معروف': {
    AppLanguage.arabic: 'غير معروف',
    AppLanguage.french: 'Inconnu',
    AppLanguage.english: 'Unknown',
  },
  '\'\'\'فاتورة رقم: \$': {
    AppLanguage.arabic: '',
    AppLanguage.french: '',
    AppLanguage.english: '',
  },
  'فارغة': {
    AppLanguage.arabic: 'فارغة',
    AppLanguage.french: 'Vide',
    AppLanguage.english: 'Empty',
  },
  'فريد (Unique)': {
    AppLanguage.arabic: 'فريد (Unique)',
    AppLanguage.french: 'Unique',
    AppLanguage.english: 'Unique',
  },
  'فض': {
    AppLanguage.arabic: 'فض',
    AppLanguage.french: 'Argent',
    AppLanguage.english: 'Silver',
  },
  'قطاع عادي (104)': {
    AppLanguage.arabic: 'قطاع عادي (104)',
    AppLanguage.french: 'Profilé standard (104)',
    AppLanguage.english: 'Standard profile (104)',
  },
  'قطاع عريض (105)': {
    AppLanguage.arabic: 'قطاع عريض (105)',
    AppLanguage.french: 'Profilé large (105)',
    AppLanguage.english: 'Wide profile (105)',
  },
  'قياس مخصص (إدخل الأبعاد)': {
    AppLanguage.arabic: 'قياس مخصص (إدخل الأبعاد)',
    AppLanguage.french: 'Dimensions personnalisées',
    AppLanguage.english: 'Custom dimensions',
  },
  'لا يوجد بريد': {
    AppLanguage.arabic: 'لا يوجد بريد',
    AppLanguage.french: 'Aucun e-mail',
    AppLanguage.english: 'No email',
  },
  'لا يوجد مستخدمين مسجلين': {
    AppLanguage.arabic: 'لا يوجد مستخدمين مسجلين',
    AppLanguage.french: 'Aucun utilisateur enregistré',
    AppLanguage.english: 'No registered users',
  },
  'لم يتم العثور على ألوان.': {
    AppLanguage.arabic: 'لم يتم العثور على ألوان.',
    AppLanguage.french: 'Aucune couleur trouvée.',
    AppLanguage.english: 'No colors found.',
  },
  'لم يتم العثور على نسخة احتياطية سابقة': {
    AppLanguage.arabic: 'لم يتم العثور على نسخة احتياطية سابقة',
    AppLanguage.french: 'Aucune sauvegarde précédente trouvée',
    AppLanguage.english: 'No previous backup found',
  },
  'مخصص لسلاسل معينة': {
    AppLanguage.arabic: 'مخصص لسلاسل معينة',
    AppLanguage.french: 'Dédié à certaines séries',
    AppLanguage.english: 'Dedicated to specific series',
  },
  'مدير النظام': {
    AppLanguage.arabic: 'مدير النظام',
    AppLanguage.french: 'Administrateur',
    AppLanguage.english: 'System Admin',
  },
  'مدير/مسؤول': {
    AppLanguage.arabic: 'مدير/مسؤول',
    AppLanguage.french: 'Administrateur',
    AppLanguage.english: 'Administrator',
  },
  'مصروف (سحب)': {
    AppLanguage.arabic: 'مصروف (سحب)',
    AppLanguage.french: 'Dépense (Retrait)',
    AppLanguage.english: 'Expense (Withdraw)',
  },
  'مطابقة تلقائية': {
    AppLanguage.arabic: 'مطابقة تلقائية',
    AppLanguage.french: 'Correspondance automatique',
    AppLanguage.english: 'Auto-match',
  },
  'مطبخ': {
    AppLanguage.arabic: 'مطبخ',
    AppLanguage.french: 'Cuisine',
    AppLanguage.english: 'Kitchen',
  },
  'مقسى': {
    AppLanguage.arabic: 'مقسى',
    AppLanguage.french: 'Trempé',
    AppLanguage.english: 'Tempered',
  },
  'ملغى': {
    AppLanguage.arabic: 'ملغى',
    AppLanguage.french: 'Annulé',
    AppLanguage.english: 'Canceled',
  },
  'موافقة لإنشاء جديد': {
    AppLanguage.arabic: 'موافقة لإنشاء جديد',
    AppLanguage.french: 'Approuver pour créer un nouveau',
    AppLanguage.english: 'Approve to create new',
  },
  'مورق': {
    AppLanguage.arabic: 'مورق',
    AppLanguage.french: 'Feuilleté',
    AppLanguage.english: 'Laminated',
  },
  'نظام تصميم النوافذ ERP': {
    AppLanguage.arabic: 'نظام تصميم النوافذ ERP',
    AppLanguage.french: 'Système ERP de conception de fenêtres',
    AppLanguage.english: 'Window design ERP system',
  },
  'نظام فتح (Frappe)': {
    AppLanguage.arabic: 'نظام فتح (Frappe)',
    AppLanguage.french: 'Système battant (Frappe)',
    AppLanguage.english: 'Opening system (Frappe)',
  },
  'نظام منزلق (Coulissant)': {
    AppLanguage.arabic: 'نظام منزلق (Coulissant)',
    AppLanguage.french: 'Système coulissant',
    AppLanguage.english: 'Sliding system',
  },
  'نورالور للألمنيوم (Noralur)': {
    AppLanguage.arabic: 'نورالور للألمنيوم (Noralur)',
    AppLanguage.french: 'Noralur Aluminium',
    AppLanguage.english: 'Noralur Aluminium',
  },
  'نوع المادة': {
    AppLanguage.arabic: 'نوع المادة',
    AppLanguage.french: 'Type de matériau',
    AppLanguage.english: 'Material type',
  },
  'نوع المعاملة': {
    AppLanguage.arabic: 'نوع المعاملة',
    AppLanguage.french: 'Type de transaction',
    AppLanguage.english: 'Transaction type',
  },
  'وجه خارجي': {
    AppLanguage.arabic: 'وجه خارجي',
    AppLanguage.french: 'Face externe',
    AppLanguage.english: 'Outer face',
  },
  'وجه داخلي': {
    AppLanguage.arabic: 'وجه داخلي',
    AppLanguage.french: 'Face interne',
    AppLanguage.english: 'Inner face',
  },
  'وضع التحريك': {
    AppLanguage.arabic: 'وضع التحريك',
    AppLanguage.french: 'Mode Déplacement',
    AppLanguage.english: 'Pan/Move Mode',
  },
  'وضع الرسم': {
    AppLanguage.arabic: 'وضع الرسم',
    AppLanguage.french: 'Mode Dessin',
    AppLanguage.english: 'Drawing Mode',
  },
  'وضع الرسم (نشط)': {
    AppLanguage.arabic: 'وضع الرسم (نشط)',
    AppLanguage.french: 'Mode Dessin (Actif)',
    AppLanguage.english: 'Drawing Mode (Active)',
  },
  'يرجى إدخال اسم المورد': {
    AppLanguage.arabic: 'يرجى إدخال اسم المورد',
    AppLanguage.french: 'Veuillez saisir le nom du fournisseur',
    AppLanguage.english: 'Please enter the supplier\'s name',
  },
  'يرجى مطابقة كافة السلع أولاً': {
    AppLanguage.arabic: 'يرجى مطابقة كافة السلع أولاً',
    AppLanguage.french:
        'Veuillez d\'abord faire correspondre tous les articles',
    AppLanguage.english: 'Please match all items first',
  },
  'يقوم الذكاء الاصطناعي باستخراج أسماء الموردين، قيم الفواتير، والأكواد التجارية للسلع لمطابقتها تلقائياً.': {
    AppLanguage.arabic:
        'يقوم الذكاء الاصطناعي باستخراج أسماء الموردين، قيم الفواتير، والأكواد التجارية للسلع لمطابقتها تلقائياً.',
    AppLanguage.french:
        'L\'IA extrait les noms des fournisseurs, les valeurs des factures et les codes commerciaux pour une correspondance automatique.',
    AppLanguage.english:
        'AI extracts supplier names, invoice values, and commercial codes for automatic matching.',
  },
  'Address:': {
    AppLanguage.arabic: 'العنوان:',
    AppLanguage.french: 'Adresse :',
    AppLanguage.english: 'Address:',
  },
  'Paid': {
    AppLanguage.arabic: 'خالصة',
    AppLanguage.french: 'Payé',
    AppLanguage.english: 'Paid',
  },
  'Unpaid': {
    AppLanguage.arabic: 'غير خالصة',
    AppLanguage.french: 'Impayé',
    AppLanguage.english: 'Unpaid',
  },
  'Total:': {
    AppLanguage.arabic: 'الإجمالي:',
    AppLanguage.french: 'Total :',
    AppLanguage.english: 'Total:',
  },
  'Paid:': {
    AppLanguage.arabic: 'المدفوع:',
    AppLanguage.french: 'Payé :',
    AppLanguage.english: 'Paid:',
  },
  'Error:': {
    AppLanguage.arabic: 'خطأ:',
    AppLanguage.french: 'Erreur :',
    AppLanguage.english: 'Error:',
  },
  'قطر المحرك': {
    AppLanguage.arabic: 'قطر المحرك',
    AppLanguage.french: 'Diamètre du moteur',
    AppLanguage.english: 'Motor Diameter',
  },
  'قياس المحرك': {
    AppLanguage.arabic: 'قياس المحرك',
    AppLanguage.french: 'Mesure du moteur',
    AppLanguage.english: 'Motor Measurement',
  },
  'قطر المحرك (مثال: 45 أو 55)': {
    AppLanguage.arabic: 'قطر المحرك (مثال: 45 أو 55)',
    AppLanguage.french: 'Diamètre du moteur (Ex : 45 ou 55)',
    AppLanguage.english: 'Motor diameter (e.g. 45 or 55)',
  },
  'قياس المحرك (مثال: 10Nm أو 20Nm)': {
    AppLanguage.arabic: 'قياس المحرك (مثال: 10Nm أو 20Nm)',
    AppLanguage.french: 'Mesure du moteur (Ex : 10Nm ou 20Nm)',
    AppLanguage.english: 'Motor measurement (e.g. 10Nm or 20Nm)',
  },
  'قطر المحرك:': {
    AppLanguage.arabic: 'قطر المحرك:',
    AppLanguage.french: 'Diamètre du moteur :',
    AppLanguage.english: 'Motor diameter:',
  },
  'قياس المحرك:': {
    AppLanguage.arabic: 'قياس المحرك:',
    AppLanguage.french: 'Mesure du moteur :',
    AppLanguage.english: 'Motor measure:',
  },
  'كوليس': {
    AppLanguage.arabic: 'كوليس (Coulisse)',
    AppLanguage.french: 'Coulisse',
    AppLanguage.english: 'Slide (Coulisse)',
  },
  'غطاء جانبي: موجود (4 côtés)': {
    AppLanguage.arabic: 'غطاء جانبي: موجود (4 جوانب)',
    AppLanguage.french: 'Couvre-joint: Présent (4 côtés)',
    AppLanguage.english: 'Side cover: Present (4 sides)',
  },
  'ورشتي': {
    AppLanguage.arabic: 'ورشتي',
    AppLanguage.french: 'Mon Atelier',
    AppLanguage.english: 'My Workshop',
  },
  'غطاء جانبي: يمين، يسار، علوي (Gauche, Droite, Haut)': {
    AppLanguage.arabic: 'غطاء جانبي: يمين، يسار، علوي',
    AppLanguage.french: 'Couvre-joint: Gauche, Droite, Haut',
    AppLanguage.english: 'Side cover: Left, Right, Top',
  },
  'نظام دوار (Roulant)': {
    AppLanguage.arabic: 'نظام دوار (Roulant)',
    AppLanguage.french: 'Système Roulant',
    AppLanguage.english: 'Rolling System',
  },
  'نظام مفصلي (Battant)': {
    AppLanguage.arabic: 'نظام مفصلي (Battant)',
    AppLanguage.french: 'Système Battant',
    AppLanguage.english: 'Casement System',
  },
  '// Removed duplicate \'نظام منزلق (Coulissant)\'\n    \'حزام (Sangle)\'': {
    AppLanguage.arabic: 'حزام',
    AppLanguage.french: 'Sangle',
    AppLanguage.english: 'Strap',
  },
  'مانيفر (Manivelle)': {
    AppLanguage.arabic: 'مانيفر',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank',
  },
  'DEVIS': {
    AppLanguage.arabic: 'فاتورة تسعيرية',
    AppLanguage.french: 'DEVIS',
    AppLanguage.english: 'QUOTATION',
  },
  'DEVIS_PARTIAL': {
    AppLanguage.arabic: 'فاتورة شحن جزئية',
    AppLanguage.french: 'FACTURE D\'EXPÉDITION PARTIELLE',
    AppLanguage.english: 'PARTIAL SHIPPING INVOICE',
  },
  'FACTURE_VENTE': {
    AppLanguage.arabic: 'فاتورة بيع',
    AppLanguage.french: 'FACTURE DE VENTE',
    AppLanguage.english: 'SALES INVOICE',
  },
  'N°:': {
    AppLanguage.arabic: 'رقم:',
    AppLanguage.french: 'N°:',
    AppLanguage.english: 'No:',
  },
  'Date:': {
    AppLanguage.arabic: 'التاريخ:',
    AppLanguage.french: 'Date:',
    AppLanguage.english: 'Date:',
  },
  'Valide jusqu\'au:': {
    AppLanguage.arabic: 'صالح حتى:',
    AppLanguage.french: 'Valide jusqu\'au:',
    AppLanguage.english: 'Valid until:',
  },
  'FOURNISSEUR': {
    AppLanguage.arabic: 'المورّد',
    AppLanguage.french: 'FOURNISSEUR',
    AppLanguage.english: 'SUPPLIER',
  },
  'Total Brut': {
    AppLanguage.arabic: 'المجموع الإجمالي',
    AppLanguage.french: 'Total Brut',
    AppLanguage.english: 'Gross Total',
  },
  'TVA': {
    AppLanguage.arabic: 'الضريبة',
    AppLanguage.french: 'TVA',
    AppLanguage.english: 'VAT',
  },
  'TOTAL TTC': {
    AppLanguage.arabic: 'المجموع الصافي',
    AppLanguage.french: 'TOTAL TTC',
    AppLanguage.english: 'TOTAL INCL. TAX',
  },
  'Quantité Totale / مجموع الكميات': {
    AppLanguage.arabic: 'مجموع الكميات',
    AppLanguage.french: 'Quantité Totale',
    AppLanguage.english: 'Total Quantity',
  },
  'سبب التعديل: ': {
    AppLanguage.arabic: 'سبب التعديل: ',
    AppLanguage.french: 'Raison de modification: ',
    AppLanguage.english: 'Modification reason: ',
  },
  'التسعير': {
    AppLanguage.arabic: 'التسعير',
    AppLanguage.french: 'Devis',
    AppLanguage.english: 'Quotation',
  },
  'اسم الملف': {
    AppLanguage.arabic: 'اسم الملف',
    AppLanguage.french: 'Nom du fichier',
    AppLanguage.english: 'File Name',
  },
  'ادخل اسم الملف': {
    AppLanguage.arabic: 'أدخل اسم الملف',
    AppLanguage.french: 'Entrez le nom du fichier',
    AppLanguage.english: 'Enter file name',
  },
  'اختيار مسار الحفظ': {
    AppLanguage.arabic: 'اختيار مسار الحفظ',
    AppLanguage.french: 'Choisir le chemin d\'enregistrement',
    AppLanguage.english: 'Choose save path',
  },
  'تم حفظ PDF بنجاح في الهاتف': {
    AppLanguage.arabic: 'تم حفظ PDF بنجاح',
    AppLanguage.french: 'PDF enregistré avec succès',
    AppLanguage.english: 'PDF successfully saved',
  },
  'خطأ في الطباعة: ': {
    AppLanguage.arabic: 'خطأ في الطباعة: ',
    AppLanguage.french: 'Erreur d\'impression: ',
    AppLanguage.english: 'Print error: ',
  },
  'خطأ في المشاركة: ': {
    AppLanguage.arabic: 'خطأ في المشاركة: ',
    AppLanguage.french: 'Erreur de partage: ',
    AppLanguage.english: 'Share error: ',
  },
  'تم استنساخ النافذة بنجاح': {
    AppLanguage.arabic: 'تم استنساخ النافذة بنجاح',
    AppLanguage.french: 'Fenêtre dupliquée avec succès',
    AppLanguage.english: 'Window successfully duplicated',
  },
  'حذف النافذة': {
    AppLanguage.arabic: 'حذف النافذة',
    AppLanguage.french: 'Supprimer la fenêtre',
    AppLanguage.english: 'Delete Window',
  },
  '(عنصر مستبدل - غير محسوب في المجموع)': {
    AppLanguage.arabic: '(عنصر مستبدل - غير محسوب في المجموع)',
    AppLanguage.french: '(Élément remplacé - Non inclus dans le total)',
    AppLanguage.english: '(Replaced item - Not included in total)',
  },
  'سبب التعديل / الإلغاء': {
    AppLanguage.arabic: 'سبب التعديل / الإلغاء',
    AppLanguage.french: 'Raison de modification / annulation',
    AppLanguage.english: 'Reason for modification / cancellation',
  },
  'صناديق/محركات:': {
    AppLanguage.arabic: 'صناديق/محركات:',
    AppLanguage.french: 'Caissons/Moteurs:',
    AppLanguage.english: 'Boxes/Motors:',
  },
  'تعديل السبب': {
    AppLanguage.arabic: 'تعديل السبب',
    AppLanguage.french: 'Modifier la raison',
    AppLanguage.english: 'Edit reason',
  },
  'الرجاء إدخال سبب التعديل': {
    AppLanguage.arabic: 'الرجاء إدخال سبب التعديل',
    AppLanguage.french: 'Veuillez entrer la raison de la modification',
    AppLanguage.english: 'Please enter the modification reason',
  },
  'تعديل سبب التعديل': {
    AppLanguage.arabic: 'تعديل سبب التعديل',
    AppLanguage.french: 'Modifier la raison de modification',
    AppLanguage.english: 'Edit modification reason',
  },
  'إجمالي الألمنيوم (Profilés):': {
    AppLanguage.arabic: 'إجمالي الألمنيوم:',
    AppLanguage.french: 'Total Profilés:',
    AppLanguage.english: 'Total Aluminum:',
  },
  'تعديل (Amélioration)': {
    AppLanguage.arabic: 'تعديل (تحسين)',
    AppLanguage.french: 'Modification (Amélioration)',
    AppLanguage.english: 'Modification (Improvement)',
  },
  'دج': {
    AppLanguage.arabic: 'دج',
    AppLanguage.french: 'D.A.',
    AppLanguage.english: 'D.A.',
  },
  'الستائر (Volets):': {
    AppLanguage.arabic: 'الستائر:',
    AppLanguage.french: 'Volets:',
    AppLanguage.english: 'Shutters:',
  },
  'شكل النافذة': {
    AppLanguage.arabic: 'شكل النافذة',
    AppLanguage.french: 'Forme de la fenêtre',
    AppLanguage.english: 'Window shape',
  },
  'الكمية:': {
    AppLanguage.arabic: 'الكمية:',
    AppLanguage.french: 'Quantité:',
    AppLanguage.english: 'Quantity:',
  },
  'D.A': {
    AppLanguage.arabic: 'د.ج',
    AppLanguage.french: 'D.A',
    AppLanguage.english: 'DZD',
  },
  'البيان (الاسم / الموديل)': {
    AppLanguage.arabic: 'البيان (الاسم / الموديل)',
    AppLanguage.french: 'Désignation (Nom / Modèle)',
    AppLanguage.english: 'Designation (Name / Model)',
  },
  'التفاصيل المطبوعة في الـ PDF (يمكنك مسح وتعديل أي شيء)': {
    AppLanguage.arabic: 'التفاصيل المطبوعة في الـ PDF (يمكنك تعديل أي شيء)',
    AppLanguage.french: 'Détails imprimés dans le PDF (vous pouvez modifier)',
    AppLanguage.english: 'Printed details in PDF (you can modify)',
  },
  'حفظ جميع التعديلات': {
    AppLanguage.arabic: 'حفظ جميع التعديلات',
    AppLanguage.french: 'Enregistrer les modifications',
    AppLanguage.english: 'Save all changes',
  },
  'تعديل جدول الفاتورة': {
    AppLanguage.arabic: 'تعديل جدول الفاتورة',
    AppLanguage.french: 'Modifier le tableau',
    AppLanguage.english: 'Edit table',
  },
  r'''لا توجد نشاطات مسجلة بعد.''': {
    AppLanguage.arabic: r'''لا توجد نشاطات مسجلة بعد.''',
    AppLanguage.french: r'''Aucune activité récente.''',
    AppLanguage.english: r'''No recent activity.''',
  },
  r'''تصدير / رفع الكتالوج (للمدير فقط)''': {
    AppLanguage.arabic: r'''تصدير / رفع الكتالوج (للمدير فقط)''',
    AppLanguage.french:
        r'''Exporter / Télécharger le catalogue (Directeur uniquement)''',
    AppLanguage.english: r'''Export / Upload Catalog (Manager only)''',
  },
  r'''النشاطات الأخيرة''': {
    AppLanguage.arabic: r'''النشاطات الأخيرة''',
    AppLanguage.french: r'''Activité récente''',
    AppLanguage.english: r'''Recent Activity''',
  },
  r'''Vitrage: Double Vitrage''': {
    AppLanguage.arabic: r'''زجاج: مزدوج''',
    AppLanguage.french: r'''Vitrage: Double''',
    AppLanguage.english: r'''Glass: Double''',
  },
  r'''Vitrage: Simple Vitrage''': {
    AppLanguage.arabic: r'''زجاج: بسيط''',
    AppLanguage.french: r'''Vitrage: Simple''',
    AppLanguage.english: r'''Glass: Simple''',
  },
  r'''Double''': {
    AppLanguage.arabic: r'''مزدوج''',
    AppLanguage.french: r'''Double''',
    AppLanguage.english: r'''Double''',
  },
  'الكمية والتكلفة': {
    AppLanguage.arabic: 'الكمية والتكلفة',
    AppLanguage.french: 'Quantité et Coût',
    AppLanguage.english: 'Quantity and Cost',
  },
  'الالكمية والتكلفة': {
    AppLanguage.arabic: 'الكمية والتكلفة',
    AppLanguage.french: 'Quantité & Coût',
    AppLanguage.english: 'Quantity & Cost',
  },
  'جاري تجهيز الكميات والأسعار...': {
    AppLanguage.arabic: 'جاري تجهيز الكميات والأسعار...',
    AppLanguage.french: 'Préparation des quantités et des prix...',
    AppLanguage.english: 'Preparing quantities and prices...',
  },
  'إعدادات السعر': {
    AppLanguage.arabic: 'إعدادات السعر',
    AppLanguage.french: 'Paramètres de prix',
    AppLanguage.english: 'Price Settings',
  },
  'تفاصيل الحساب': {
    AppLanguage.arabic: 'تفاصيل الحساب',
    AppLanguage.french: 'Détails du compte',
    AppLanguage.english: 'Account Details',
  },
  'سعر التكلفة الإجمالي': {
    AppLanguage.arabic: 'سعر التكلفة الإجمالي',
    AppLanguage.french: 'Prix de revient total',
    AppLanguage.english: 'Total Cost Price',
  },
  'سعر القطعة': {
    AppLanguage.arabic: 'سعر القطعة',
    AppLanguage.french: 'Prix unitaire',
    AppLanguage.english: 'Piece Price',
  },
  'جدول السلع': {
    AppLanguage.arabic: 'جدول السلع',
    AppLanguage.french: 'Tableau des marchandises',
    AppLanguage.english: 'Goods Table',
  },
  'مراسلة الإدارة': {
    AppLanguage.arabic: 'مراسلة الإدارة',
    AppLanguage.french: 'Contacter l\'administration',
    AppLanguage.english: 'Contact Admin',
  },
  'الموردين': {
    AppLanguage.arabic: 'الموردين',
    AppLanguage.french: 'Fournisseurs',
    AppLanguage.english: 'Suppliers',
  },
  'ستوب صول': {
    AppLanguage.arabic: 'ستوب صول',
    AppLanguage.french: 'Stopsol',
    AppLanguage.english: 'Stopsol',
  },
  'المتوفر فقط': {
    AppLanguage.arabic: 'المتوفر فقط',
    AppLanguage.french: 'En stock uniquement',
    AppLanguage.english: 'In Stock Only',
  },
  'كل العناصر': {
    AppLanguage.arabic: 'كل العناصر',
    AppLanguage.french: 'Tous les articles',
    AppLanguage.english: 'All Items',
  },
  'البحث عن عنصر، مقطع، لون...': {
    AppLanguage.arabic: 'البحث عن عنصر، مقطع، لون...',
    AppLanguage.french: 'Rechercher un article, profil, couleur...',
    AppLanguage.english: 'Search item, profile, color...',
  },
  'تصفير المخزون (فترة تجريبية)': {
    AppLanguage.arabic: 'تصفير المخزون (فترة تجريبية)',
    AppLanguage.french: 'Réinitialiser le stock (Période d\'essai)',
    AppLanguage.english: 'Reset Stock (Trial Period)',
  },
  'تصفير المخزون!': {
    AppLanguage.arabic: 'تصفير المخزون!',
    AppLanguage.french: 'Réinitialiser le stock !',
    AppLanguage.english: 'Reset Stock!',
  },
  'تأكيد التصفير': {
    AppLanguage.arabic: 'تأكيد التصفير',
    AppLanguage.french: 'Confirmer la réinitialisation',
    AppLanguage.english: 'Confirm Reset',
  },
  'تم تصفير المخزون بنجاح': {
    AppLanguage.arabic: 'تم تصفير المخزون بنجاح',
    AppLanguage.french: 'Le stock a été réinitialisé avec succès',
    AppLanguage.english: 'Stock reset successfully',
  },
  'جرد سنوي / تعديل المخزون': {
    AppLanguage.arabic: 'جرد سنوي / تعديل المخزون',
    AppLanguage.french: 'Inventaire annuel / Ajustement du stock',
    AppLanguage.english: 'Annual Inventory / Stock Adjustment',
  },
  'القيمة الإجمالية للمخزون': {
    AppLanguage.arabic: 'القيمة الإجمالية للمخزون',
    AppLanguage.french: 'Valeur totale du stock',
    AppLanguage.english: 'Total Stock Value',
  },
  'لا توجد عناصر في هذا المخزون': {
    AppLanguage.arabic: 'لا توجد عناصر في هذا المخزون',
    AppLanguage.french: 'Aucun article dans ce stock',
    AppLanguage.english: 'No items in this stock',
  },
  'الرصيد': {
    AppLanguage.arabic: 'الرصيد',
    AppLanguage.french: 'Solde / Qté',
    AppLanguage.english: 'Balance / Qty',
  },
  'جرد المخزون: ': {
    AppLanguage.arabic: 'جرد المخزون: ',
    AppLanguage.french: 'Ajustement du stock : ',
    AppLanguage.english: 'Stock Count: ',
  },
  'تم حفظ تسوية المخزون بنجاح!': {
    AppLanguage.arabic: 'تم حفظ تسوية المخزون بنجاح!',
    AppLanguage.french: 'Ajustement du stock enregistré avec succès !',
    AppLanguage.english: 'Stock adjustment saved successfully!',
  },
  'بطاقة حركة المادة': {
    AppLanguage.arabic: 'بطاقة حركة المادة',
    AppLanguage.french: 'Fiche de mouvement de l\'article',
    AppLanguage.english: 'Item Movement Card',
  },
  'سجل الحركات:': {
    AppLanguage.arabic: 'سجل الحركات:',
    AppLanguage.french: 'Historique des mouvements :',
    AppLanguage.english: 'Movement Log:',
  },
  'لا توجد حركات مسجلة لهذه المادة.': {
    AppLanguage.arabic: 'لا توجد حركات مسجلة لهذه المادة.',
    AppLanguage.french: 'Aucun mouvement enregistré pour cet article.',
    AppLanguage.english: 'No movements registered for this item.',
  },
  'فاتورة شراء رقم ': {
    AppLanguage.arabic: 'فاتورة شراء رقم ',
    AppLanguage.french: 'Facture d\'achat n° ',
    AppLanguage.english: 'Purchase Invoice #',
  },
  'تعديل مشتريات رقم ': {
    AppLanguage.arabic: 'تعديل مشتريات رقم ',
    AppLanguage.french: 'Modification d\'achat n° ',
    AppLanguage.english: 'Purchase Edit #',
  },
  'إلغاء مشتريات رقم ': {
    AppLanguage.arabic: 'إلغاء مشتريات رقم ',
    AppLanguage.french: 'Annulation d\'achat n° ',
    AppLanguage.english: 'Purchase Deletion #',
  },
  'استهلاك في طلبية رقم ': {
    AppLanguage.arabic: 'استهلاك في طلبية رقم ',
    AppLanguage.french: 'Consommation dans la commande n° ',
    AppLanguage.english: 'Consumption in Order #',
  },
  'مورد جديد': {
    AppLanguage.arabic: 'مورد جديد',
    AppLanguage.french: 'Nouveau fournisseur',
    AppLanguage.english: 'New Supplier',
  },
  'إضافة مورد جديد': {
    AppLanguage.arabic: 'إضافة مورد جديد',
    AppLanguage.french: 'Ajouter un nouveau fournisseur',
    AppLanguage.english: 'Add New Supplier',
  },
  'تعديل بيانات المورد': {
    AppLanguage.arabic: 'تعديل بيانات المورد',
    AppLanguage.french: 'Modifier les informations du fournisseur',
    AppLanguage.english: 'Edit Supplier Details',
  },
  'اسم المورد': {
    AppLanguage.arabic: 'اسم المورد',
    AppLanguage.french: 'Nom du fournisseur',
    AppLanguage.english: 'Supplier Name',
  },
  'ملاحظات': {
    AppLanguage.arabic: 'ملاحظات',
    AppLanguage.french: 'Remarques / Notes',
    AppLanguage.english: 'Notes / Remarks',
  },
  'هل أنت متأكد من حذف هذا المورد؟': {
    AppLanguage.arabic: 'هل أنت متأكد من حذف هذا المورد؟',
    AppLanguage.french: 'Êtes-vous sûr de vouloir supprimer ce fournisseur ?',
    AppLanguage.english: 'Are you sure you want to delete this supplier?',
  },
  'لا يوجد موردين مضافين حتى الآن.': {
    AppLanguage.arabic: 'لا يوجد موردين مضافين حتى الآن.',
    AppLanguage.french: 'Aucun fournisseur ajouté pour le moment.',
    AppLanguage.english: 'No suppliers added yet.',
  },
  'الاسم مطلوب': {
    AppLanguage.arabic: 'الاسم مطلوب',
    AppLanguage.french: 'Le nom est requis',
    AppLanguage.english: 'Name is required',
  },
  'ملف المورد: ': {
    AppLanguage.arabic: 'ملف المورد: ',
    AppLanguage.french: 'Profil du fournisseur : ',
    AppLanguage.english: 'Supplier Profile: ',
  },
  'الديون': {
    AppLanguage.arabic: 'الديون',
    AppLanguage.french: 'Dettes',
    AppLanguage.english: 'Debts',
  },
  'سجل الفواتير': {
    AppLanguage.arabic: 'سجل الفواتير',
    AppLanguage.french: 'Historique des factures',
    AppLanguage.english: 'Invoices History',
  },
  'لا توجد فواتير مسجلة لهذا المورد': {
    AppLanguage.arabic: 'لا توجد فواتير مسجلة لهذا المورد',
    AppLanguage.french: 'Aucune facture enregistrée pour ce fournisseur',
    AppLanguage.english: 'No invoices registered for this supplier',
  },
  'فاتورة #': {
    AppLanguage.arabic: 'فاتورة #',
    AppLanguage.french: 'Facture N° ',
    AppLanguage.english: 'Invoice #',
  },
  'الحالة: ': {
    AppLanguage.arabic: 'الحالة: ',
    AppLanguage.french: 'Statut : ',
    AppLanguage.english: 'Status: ',
  },
  'مؤكدة': {
    AppLanguage.arabic: 'مؤكدة',
    AppLanguage.french: 'Confirmée',
    AppLanguage.english: 'Confirmed',
  },
  'قيد التعديل': {
    AppLanguage.arabic: 'قيد التعديل',
    AppLanguage.french: 'En cours de modification',
    AppLanguage.english: 'Pending Modification',
  },
  'الإجمالي: ': {
    AppLanguage.arabic: 'الإجمالي: ',
    AppLanguage.french: 'Total : ',
    AppLanguage.english: 'Total: ',
  },
  'المدفوع: ': {
    AppLanguage.arabic: 'المدفوع: ',
    AppLanguage.french: 'Payé : ',
    AppLanguage.english: 'Paid: ',
  },
  'نشطة': {
    AppLanguage.arabic: 'نشطة',
    AppLanguage.french: 'Active',
    AppLanguage.english: 'Active',
  },
  'مردودة كلياً': {
    AppLanguage.arabic: 'مردودة كلياً',
    AppLanguage.french: 'Retournée totalement',
    AppLanguage.english: 'Fully Returned',
  },
  'مردودة جزئياً': {
    AppLanguage.arabic: 'مردودة جزئياً',
    AppLanguage.french: 'Retournée partiellement',
    AppLanguage.english: 'Partially Returned',
  },
  'مؤكدة / مدفوعة': {
    AppLanguage.arabic: 'مؤكدة / مدفوعة',
    AppLanguage.french: 'Confirmée / Payée',
    AppLanguage.english: 'Confirmed / Paid',
  },
  'مؤكد/نشط': {
    AppLanguage.arabic: 'مؤكد/نشط',
    AppLanguage.french: 'Confirmé/Actif',
    AppLanguage.english: 'Confirmed/Active',
  },
  'ملغاة': {
    AppLanguage.arabic: 'ملغاة',
    AppLanguage.french: 'Annulée',
    AppLanguage.english: 'Cancelled',
  },
  'يتم إنشاؤه تلقائياً ويمكنك تعديله': {
    AppLanguage.arabic: 'يتم إنشاؤه تلقائياً ويمكنك تعديله',
    AppLanguage.french: 'Généré automatiquement et modifiable',
    AppLanguage.english: 'Automatically generated and editable',
  },
  'جارٍ توليد رقم الفاتورة...': {
    AppLanguage.arabic: 'جارٍ توليد رقم الفاتورة...',
    AppLanguage.french: 'Génération du numéro de facture...',
    AppLanguage.english: 'Generating invoice number...',
  },
  'لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.': {
    AppLanguage.arabic:
        'لا يوجد موردين مسجلين، يرجى إضافة مورد أولاً من صفحة إدارة الموردين.',
    AppLanguage.french:
        'Aucun fournisseur enregistré, veuillez d\'abord en ajouter un.',
    AppLanguage.english:
        'No registered suppliers, please add a supplier first.',
  },
  'المورد *': {
    AppLanguage.arabic: 'المورد *',
    AppLanguage.french: 'Fournisseur *',
    AppLanguage.english: 'Supplier *',
  },
  'اختر مورد': {
    AppLanguage.arabic: 'اختر مورد',
    AppLanguage.french: 'Choisir un fournisseur',
    AppLanguage.english: 'Choose a supplier',
  },
  'لا توجد مستودعات مسجلة.': {
    AppLanguage.arabic: 'لا توجد مستودعات مسجلة.',
    AppLanguage.french: 'Aucun entrepôt enregistré.',
    AppLanguage.english: 'No registered warehouses.',
  },
  'مكان التخزين (المستودع) *': {
    AppLanguage.arabic: 'مكان التخزين (المستودع) *',
    AppLanguage.french: 'Lieu de stockage (Dépôt) *',
    AppLanguage.english: 'Storage Location (Warehouse) *',
  },
  'اختر مكان التخزين': {
    AppLanguage.arabic: 'اختر مكان التخزين',
    AppLanguage.french: 'Choisir le lieu de stockage',
    AppLanguage.english: 'Choose storage location',
  },
  'الرجاء اختيار المورد': {
    AppLanguage.arabic: 'الرجاء اختيار المورد',
    AppLanguage.french: 'Veuillez choisir le fournisseur',
    AppLanguage.english: 'Please choose the supplier',
  },
  'الرجاء اختيار مكان التخزين': {
    AppLanguage.arabic: 'الرجاء اختيار مكان التخزين',
    AppLanguage.french: 'Veuillez choisir le lieu de stockage',
    AppLanguage.english: 'Please choose the storage location',
  },
  'حدث خطأ أثناء الحفظ: ': {
    AppLanguage.arabic: 'حدث خطأ أثناء الحفظ: ',
    AppLanguage.french: 'Une erreur est survenue lors de l\'enregistrement : ',
    AppLanguage.english: 'An error occurred while saving: ',
  },
  'هل أنت متأكد من رغبتك في حذف الفاتورة رقم: ': {
    AppLanguage.arabic: 'هل أنت متأكد من رغبتك في حذف الفاتورة رقم: ',
    AppLanguage.french: 'Êtes-vous sûr de vouloir supprimer la facture N°: ',
    AppLanguage.english: 'Are you sure you want to delete invoice number: ',
  },
  ' نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.': {
    AppLanguage.arabic:
        ' نهائياً من قاعدة البيانات؟ لا يمكن التراجع عن هذا الإجراء.',
    AppLanguage.french:
        ' définitivement de la base de données ? Cette action est irréversible.',
    AppLanguage.english:
        ' permanently from the database? This action cannot be undone.',
  },
  'تفاصيل المشتريات': {
    AppLanguage.arabic: 'تفاصيل المشتريات',
    AppLanguage.french: 'Détails des achats',
    AppLanguage.english: 'Purchase Details',
  },
  'المورد': {
    AppLanguage.arabic: 'المورد',
    AppLanguage.french: 'Fournisseur',
    AppLanguage.english: 'Supplier',
  },
  'مسترجعة': {
    AppLanguage.arabic: 'مسترجعة',
    AppLanguage.french: 'Retournée',
    AppLanguage.english: 'Returned',
  },
  'جزئياً مسترجعة': {
    AppLanguage.arabic: 'جزئياً مسترجعة',
    AppLanguage.french: 'Partiellement retournée',
    AppLanguage.english: 'Partially Returned',
  },
  'تراجع عن التعديلات': {
    AppLanguage.arabic: 'تراجع عن التعديلات',
    AppLanguage.french: 'Annuler les modifications',
    AppLanguage.english: 'Discard Changes',
  },
  'صورة الفاتورة المرفقة': {
    AppLanguage.arabic: 'صورة الفاتورة المرفقة',
    AppLanguage.french: 'Image de facture jointe',
    AppLanguage.english: 'Attached Invoice Image',
  },
  'ملف PDF محفوظ': {
    AppLanguage.arabic: 'ملف PDF محفوظ',
    AppLanguage.french: 'Fichier PDF enregistré',
    AppLanguage.english: 'Saved PDF File',
  },
  'فتح': {
    AppLanguage.arabic: 'فتح',
    AppLanguage.french: 'Ouvrir',
    AppLanguage.english: 'Open',
  },
  'إرفاق صورة': {
    AppLanguage.arabic: 'إرفاق صورة',
    AppLanguage.french: 'Joindre une image',
    AppLanguage.english: 'Attach Image',
  },
  'حفظ PDF': {
    AppLanguage.arabic: 'حفظ PDF',
    AppLanguage.french: 'Enregistrer en PDF',
    AppLanguage.english: 'Save PDF',
  },
  'إجمالي العناصر: ': {
    AppLanguage.arabic: 'إجمالي العناصر: ',
    AppLanguage.french: 'Total des articles : ',
    AppLanguage.english: 'Total Items: ',
  },
  'المتبقي: ': {
    AppLanguage.arabic: 'المتبقي: ',
    AppLanguage.french: 'Reste : ',
    AppLanguage.english: 'Remaining: ',
  },
  'لا توجد عناصر مضافة بعد.': {
    AppLanguage.arabic: 'لا توجد عناصر مضافة بعد.',
    AppLanguage.french: 'Aucun article ajouté pour le moment.',
    AppLanguage.english: 'No items added yet.',
  },
  'عنصر': {
    AppLanguage.arabic: 'عنصر',
    AppLanguage.french: 'Article',
    AppLanguage.english: 'Item',
  },
  'سعر الوحدة: ': {
    AppLanguage.arabic: 'سعر الوحدة: ',
    AppLanguage.french: 'Prix unitaire : ',
    AppLanguage.english: 'Unit Price: ',
  },
  'مقاطع': {
    AppLanguage.arabic: 'مقاطع',
    AppLanguage.french: 'Sections',
    AppLanguage.english: 'Sections',
  },
  'إكسسوارات': {
    AppLanguage.arabic: 'إكسسوارات',
    AppLanguage.french: 'Accessoires',
    AppLanguage.english: 'Accessories',
  },
  'مركبات الستائر': {
    AppLanguage.arabic: 'مركبات الستائر',
    AppLanguage.french: 'Composants des volets',
    AppLanguage.english: 'Shutter Components',
  },
  'جوانات': {
    AppLanguage.arabic: 'جوانات',
    AppLanguage.french: 'Joints',
    AppLanguage.english: 'Joints',
  },
  'المستودع - إضافة عناصر للفاتورة (اسحب للتحريك)': {
    AppLanguage.arabic: 'المستودع - إضافة عناصر للفاتورة (اسحب للتحريك)',
    AppLanguage.french:
        'Dépôt - Ajouter des articles à la facture (Glisser pour déplacer)',
    AppLanguage.english: 'Warehouse - Add items to invoice (Drag to move)',
  },
  'إضافة عناصر (مصغرة)': {
    AppLanguage.arabic: 'إضافة عناصر (مصغرة)',
    AppLanguage.french: 'Ajouter des articles (Minimisé)',
    AppLanguage.english: 'Add items (Minimized)',
  },
  'السعر: --': {
    AppLanguage.arabic: 'السعر: --',
    AppLanguage.french: 'Prix : --',
    AppLanguage.english: 'Price: --',
  },
  'المستودع (إضافة للفاتورة)': {
    AppLanguage.arabic: 'المستودع (إضافة للفاتورة)',
    AppLanguage.french: 'Dépôt (Ajouter à la facture)',
    AppLanguage.english: 'Warehouse (Add to Invoice)',
  },
  'السلسلة (Série)': {
    AppLanguage.arabic: 'السلسلة (Série)',
    AppLanguage.french: 'Série',
    AppLanguage.english: 'Series',
  },
  'البحث عن المادة...': {
    AppLanguage.arabic: 'البحث عن المادة...',
    AppLanguage.french: 'Rechercher l\'article...',
    AppLanguage.english: 'Search item...',
  },
  'مثال: كادر، أوفرو...': {
    AppLanguage.arabic: 'مثال: كادر، أوفرو...',
    AppLanguage.french: 'Ex: Cadre, Ouvrant...',
    AppLanguage.english: 'e.g. Frame, Sash...',
  },
  'إضافة: ': {
    AppLanguage.arabic: 'إضافة: ',
    AppLanguage.french: 'Ajouter : ',
    AppLanguage.english: 'Add: ',
  },
  'الكمية (عدد)': {
    AppLanguage.arabic: 'الكمية (عدد)',
    AppLanguage.french: 'Quantité (Nombre)',
    AppLanguage.english: 'Quantity (Count)',
  },
  'السعر للوحدة': {
    AppLanguage.arabic: 'السعر للوحدة',
    AppLanguage.french: 'Prix unitaire',
    AppLanguage.english: 'Unit Price',
  },
  'هذا العنصر موجود بالفعل في الفاتورة': {
    AppLanguage.arabic: 'هذا العنصر موجود بالفعل في الفاتورة',
    AppLanguage.french: 'Cet article existe déjà dans la facture',
    AppLanguage.english: 'This item already exists in the invoice',
  },
  'تم إضافة العنصر بنجاح!': {
    AppLanguage.arabic: 'تم إضافة العنصر بنجاح!',
    AppLanguage.french: 'Article ajouté avec succès !',
    AppLanguage.english: 'Item added successfully!',
  },
  'لا توجد عناصر مطابقة': {
    AppLanguage.arabic: 'لا توجد عناصر مطابقة',
    AppLanguage.french: 'Aucun élément correspondant',
    AppLanguage.english: 'No matching items',
  },
  'فاتورة: ': {
    AppLanguage.arabic: 'فاتورة: ',
    AppLanguage.french: 'Facture : ',
    AppLanguage.english: 'Invoice: ',
  },
  'الكمية المتاحة: ': {
    AppLanguage.arabic: 'الكمية المتاحة: ',
    AppLanguage.french: 'Quantité disponible : ',
    AppLanguage.english: 'Available quantity: ',
  },
  'المراد إرجاعه: ': {
    AppLanguage.arabic: 'المراد إرجاعه: ',
    AppLanguage.french: 'À retourner : ',
    AppLanguage.english: 'To return: ',
  },
  'موقع النافذة (مثال: المطبخ - الطابق 2)': {
    AppLanguage.arabic: 'موقع النافذة (مثال: المطبخ - الطابق 2)',
    AppLanguage.french: 'Emplacement de la fenêtre (Ex: Cuisine - 2ème Étage)',
    AppLanguage.english: 'Window Location (e.g., Kitchen - 2nd Floor)',
  },

  'الإنتركال (Intercall)': {
    AppLanguage.arabic: 'الإنتركال (Intercall)',
    AppLanguage.french: 'Intercalaire',
    AppLanguage.english: 'Spacer',
  },
  'الغاز (Gas)': {
    AppLanguage.arabic: 'الغاز (Gas)',
    AppLanguage.french: 'Gaz',
    AppLanguage.english: 'Gas',
  },
  'مغلق (Panneau)': {
    AppLanguage.arabic: 'مغلق (Panneau)',
    AppLanguage.french: 'Panneau',
    AppLanguage.english: 'Panneau',
  },
  'باجيت ديكور (Baguette)': {
    AppLanguage.arabic: 'باجيت ديكور (Baguette)',
    AppLanguage.french: 'Baguette Décor',
    AppLanguage.english: 'Decor Baguette',
  },
  'وردة ديكور (Rosette)': {
    AppLanguage.arabic: 'وردة ديكور (Rosette)',
    AppLanguage.french: 'Rosette Décor',
    AppLanguage.english: 'Decor Rosette',
  },
  'إنتركال': {
    AppLanguage.arabic: 'إنتركال',
    AppLanguage.french: 'Intercalaire',
    AppLanguage.english: 'Spacer',
  },
  'غاز': {
    AppLanguage.arabic: 'غاز',
    AppLanguage.french: 'Gaz',
    AppLanguage.english: 'Gas',
  },
  'مغلق': {
    AppLanguage.arabic: 'مغلق',
    AppLanguage.french: 'Panneau',
    AppLanguage.english: 'Panneau',
  },
  'باجيت ديكور': {
    AppLanguage.arabic: 'باجيت ديكور',
    AppLanguage.french: 'Baguette Décor',
    AppLanguage.english: 'Decor Baguette',
  },
  'وردة ديكور': {
    AppLanguage.arabic: 'وردة ديكور',
    AppLanguage.french: 'Rosette Décor',
    AppLanguage.english: 'Decor Rosette',
  },
  'الأبعاد': {
    AppLanguage.arabic: 'الأبعاد',
    AppLanguage.french: 'Dimensions',
    AppLanguage.english: 'Dimensions',
  },
  'العرض الظاهر': {
    AppLanguage.arabic: 'العرض الظاهر',
    AppLanguage.french: 'Largeur visible',
    AppLanguage.english: 'Visible width',
  },

  'الخاصية': {
    AppLanguage.arabic: 'الخاصية',
    AppLanguage.french: 'Subtype',
    AppLanguage.english: 'Subtype',
  },
  'النوع': {
    AppLanguage.arabic: 'النوع',
    AppLanguage.french: 'Type',
    AppLanguage.english: 'Type',
  },
  'دج/قطعة': {
    AppLanguage.arabic: 'دج/قطعة',
    AppLanguage.french: 'DA/pc',
    AppLanguage.english: 'DA/pc',
  },
  'دج/متر': {
    AppLanguage.arabic: 'دج/متر',
    AppLanguage.french: 'DA/m',
    AppLanguage.english: 'DA/m',
  },
  'دج/م²': {
    AppLanguage.arabic: 'دج/م²',
    AppLanguage.french: 'DA/m²',
    AppLanguage.english: 'DA/m²',
  },
  'السعر': {
    AppLanguage.arabic: 'السعر',
    AppLanguage.french: 'Prix',
    AppLanguage.english: 'Price',
  },
  'الظلفة أوفرو': {
    AppLanguage.arabic: 'الضلفة',
    AppLanguage.french: 'Ouvrant',
    AppLanguage.english: 'Sash',
  },
  'الإطار كادر': {
    AppLanguage.arabic: 'الإطار',
    AppLanguage.french: 'Cadre',
    AppLanguage.english: 'Frame',
  },
  'مكوّنات الستار': {
    AppLanguage.arabic: 'مكوّنات الستار',
    AppLanguage.french: 'Composants du volet',
    AppLanguage.english: 'Shutter Components',
  },
  'Volet': {
    AppLanguage.arabic: 'ستار',
    AppLanguage.french: 'Volet',
    AppLanguage.english: 'Shutter',
  },
  'التكلفة:': {
    AppLanguage.arabic: 'التكلفة:',
    AppLanguage.french: 'Coût :',
    AppLanguage.english: 'Cost:',
  },
  'البيع:': {
    AppLanguage.arabic: 'البيع:',
    AppLanguage.french: 'Vente :',
    AppLanguage.english: 'Sale:',
  },
  'سعر التكلفة (بدون هدر)': {
    AppLanguage.arabic: 'سعر التكلفة (بدون هدر)',
    AppLanguage.french: 'Prix de revient (sans perte)',
    AppLanguage.english: 'Cost Price (no waste)',
  },
  'سعر التكلفة (مع هدر 10%)': {
    AppLanguage.arabic: 'سعر التكلفة (مع هدر 10%)',
    AppLanguage.french: 'Prix de revient (avec perte 10%)',
    AppLanguage.english: 'Cost Price (with 10% waste)',
  },
  'سعر البيع المقترح': {
    AppLanguage.arabic: 'سعر البيع المقترح',
    AppLanguage.french: 'Prix de vente suggéré',
    AppLanguage.english: 'Suggested Selling Price',
  },
  'ملخص التسعير': {
    AppLanguage.arabic: 'ملخص التسعير',
    AppLanguage.french: 'Résumé de tarification',
    AppLanguage.english: 'Pricing Summary',
  },
  'الارتفاع': {
    AppLanguage.arabic: 'الارتفاع',
    AppLanguage.french: 'Hauteur',
    AppLanguage.english: 'Height',
  },
  'العرض:': {
    AppLanguage.arabic: 'العرض:',
    AppLanguage.french: 'Largeur :',
    AppLanguage.english: 'Width:',
  },
  'الارتفاع:': {
    AppLanguage.arabic: 'الارتفاع:',
    AppLanguage.french: 'Hauteur :',
    AppLanguage.english: 'Height:',
  },
  'نافذة': {
    AppLanguage.arabic: 'نافذة',
    AppLanguage.french: 'fenêtre',
    AppLanguage.english: 'window',
  },
  'تعديل كمية النوافذ': {
    AppLanguage.arabic: 'تعديل كمية النوافذ',
    AppLanguage.french: 'Modifier la quantité de fenêtres',
    AppLanguage.english: 'Edit windows quantity',
  },
  'الكمية المطلوبة': {
    AppLanguage.arabic: 'الكمية المطلوبة',
    AppLanguage.french: 'Quantité requise',
    AppLanguage.english: 'Required Quantity',
  },
  'سعر البروفيلات:': {
    AppLanguage.arabic: 'سعر البروفيلات:',
    AppLanguage.french: 'Prix des profilés :',
    AppLanguage.english: 'Profiles price:',
  },
  'سعر الزجاج:': {
    AppLanguage.arabic: 'سعر الزجاج:',
    AppLanguage.french: 'Prix du vitrage :',
    AppLanguage.english: 'Glass price:',
  },
  'سعر الستار:': {
    AppLanguage.arabic: 'سعر الستار:',
    AppLanguage.french: 'Prix du volet :',
    AppLanguage.english: 'Shutter price:',
  },
  'سعر الإكسسوارات:': {
    AppLanguage.arabic: 'سعر الإكسسوارات:',
    AppLanguage.french: 'Prix des accessoires :',
    AppLanguage.english: 'Accessories price:',
  },
  'سعر الجوانات:': {
    AppLanguage.arabic: 'سعر الجوانات:',
    AppLanguage.french: 'Prix des joints :',
    AppLanguage.english: 'Joints price:',
  },
  'سعر أخرى:': {
    AppLanguage.arabic: 'سعر أخرى:',
    AppLanguage.french: 'Autre prix :',
    AppLanguage.english: 'Other price:',
  },
  'المجموع الإجمالي:': {
    AppLanguage.arabic: 'المجموع الإجمالي:',
    AppLanguage.french: 'Total général :',
    AppLanguage.english: 'Grand total:',
  },
  'تعديل سعر': {
    AppLanguage.arabic: 'تعديل سعر',
    AppLanguage.french: 'Modifier le prix de',
    AppLanguage.english: 'Edit price of',
  },
  'السعر الجديد (دج)': {
    AppLanguage.arabic: 'السعر الجديد (دج)',
    AppLanguage.french: 'Nouveau prix (DA)',
    AppLanguage.english: 'New price (DA)',
  },
  'حفظ في قاعدة البيانات أيضاً': {
    AppLanguage.arabic: 'حفظ في قاعدة البيانات أيضاً',
    AppLanguage.french: 'Sauvegarder également dans la base de données',
    AppLanguage.english: 'Also save to database',
  },
  'تقسيم': {
    AppLanguage.arabic: 'تقسيم',
    AppLanguage.french: 'Division',
    AppLanguage.english: 'Split',
  },
  'إضافة إطار': {
    AppLanguage.arabic: 'إضافة إطار',
    AppLanguage.french: 'Ajouter cadre',
    AppLanguage.english: 'Add Frame',
  },

  'نسبة الربح (%)': {
    AppLanguage.arabic: 'نسبة الربح (%)',
    AppLanguage.french: 'Marge de bénéfice (%)',
    AppLanguage.english: 'Profit Margin (%)',
  },
  'سعر المتر المربع (دج)': {
    AppLanguage.arabic: 'سعر المتر المربع (دج)',
    AppLanguage.french: 'Prix au m² (DA)',
    AppLanguage.english: 'Sqm Price (DA)',
  },
  'سعر المتر الخطي (دج) — تعديل يدوي': {
    AppLanguage.arabic: 'سعر المتر الخطي (دج) — تعديل يدوي',
    AppLanguage.french: 'Prix au mètre linéaire (DA) - Manuel',
    AppLanguage.english: 'Linear meter price (DA) - Manual',
  },
  'سعر المتر المربع للستار (دج) — تعديل يدوي': {
    AppLanguage.arabic: 'سعر المتر المربع للستار (دج) — تعديل يدوي',
    AppLanguage.french: 'Prix du volet au m² (DA) - Manuel',
    AppLanguage.english: 'Shutter Sqm Price (DA) - Manual',
  },
  'سعر المتر المربع للستار (دج) — من الكتالوج': {
    AppLanguage.arabic: 'سعر المتر المربع للستار (دج) — من الكتالوج',
    AppLanguage.french: 'Prix du volet au m² (DA) — selon catalogue',
    AppLanguage.english: 'Shutter price per m² (DA) — from catalog',
  },
  'سعر المتر المربع للموستيكير (دج) — من إدارة الأسعار': {
    AppLanguage.arabic: 'سعر المتر المربع للموستيكير (دج) — من إدارة الأسعار',
    AppLanguage.french: 'Prix au m² de la moustiquaire (DA) — gestion des prix',
    AppLanguage.english: 'Moustiquaire price per m² (DA) — price management',
  },
  'المساحة = عرض النافذة × ارتفاعها × الكمية. تعديل السعر يتم من إدارة الأسعار فقط.': {
    AppLanguage.arabic:
        'المساحة = عرض النافذة × ارتفاعها × الكمية. تعديل السعر يتم من إدارة الأسعار فقط.',
    AppLanguage.french:
        'Surface = Largeur × Hauteur × Quantité. Modifiable dans la gestion des prix.',
    AppLanguage.english:
        'Area = Width × Height × Quantity. Editable only in price management.',
  },
  'دج / م²': {
    AppLanguage.arabic: 'دج / م²',
    AppLanguage.french: 'DA / m²',
    AppLanguage.english: 'DZD / m²',
  },
  'تم تأكيد هذه الطلبية': {
    AppLanguage.arabic: 'تم تأكيد هذه الطلبية',
    AppLanguage.french: 'Cette commande a été confirmée',
    AppLanguage.english: 'This order has been confirmed',
  },
  'معامل عزم المحرك (وزن كغ لكل 1 نيوتن) (الافتراضي: 1.6)': {
    AppLanguage.arabic:
        'معامل عزم المحرك (وزن كغ لكل 1 نيوتن) (الافتراضي: 1.6)',
    AppLanguage.french: 'Facteur de couple (Kg/Nm) (Défaut : 1.6)',
    AppLanguage.english: 'Motor torque factor (Kg/Nm) (Default: 1.6)',
  },

  'إضافة لون جديد': {
    AppLanguage.arabic: 'إضافة لون جديد',
    AppLanguage.french: 'Ajouter une nouvelle couleur',
    AppLanguage.english: 'Add New Color',
  },
  'اسم اللون': {
    AppLanguage.arabic: 'اسم اللون',
    AppLanguage.french: 'Nom de la couleur',
    AppLanguage.english: 'Color Name',
  },
  'تعديل اسم اللون': {
    AppLanguage.arabic: 'تعديل اسم اللون',
    AppLanguage.french: 'Modifier le nom de la couleur',
    AppLanguage.english: 'Edit Color Name',
  },
  'تخصيص الألوان حسب البروفيلات': {
    AppLanguage.arabic: 'تخصيص الألوان حسب البروفيلات',
    AppLanguage.french: 'Personnaliser les couleurs par profil',
    AppLanguage.english: 'Customize Colors by Profile',
  },
  'اختر البروفيل': {
    AppLanguage.arabic: 'اختر البروفيل',
    AppLanguage.french: 'Sélectionner le profil',
    AppLanguage.english: 'Select Profile',
  },
  'تخصيص ألوان الإكسسوارات': {
    AppLanguage.arabic: 'تخصيص ألوان الإكسسوارات',
    AppLanguage.french: 'Personnaliser les couleurs des accessoires',
    AppLanguage.english: 'Customize Accessories Colors',
  },
  'بحث عن إكسسوار...': {
    AppLanguage.arabic: 'بحث عن إكسسوار...',
    AppLanguage.french: 'Rechercher un accessoire...',
    AppLanguage.english: 'Search for accessory...',
  },
  'تخصيص ألوان مركبات الستائر': {
    AppLanguage.arabic: 'تخصيص ألوان مركبات الستائر',
    AppLanguage.french: 'Personnaliser les couleurs des volets roulants',
    AppLanguage.english: 'Customize Roller Shutter Colors',
  },
  'صندوق': {
    AppLanguage.arabic: 'صندوق',
    AppLanguage.french: 'Coffre',
    AppLanguage.english: 'Box',
  },
  'شفرة/شريحة': {
    AppLanguage.arabic: 'شفرة/شريحة',
    AppLanguage.french: 'Lame',
    AppLanguage.english: 'Blade',
  },
  'شفرات': {
    AppLanguage.arabic: 'شفرات',
    AppLanguage.french: 'Lames',
    AppLanguage.english: 'Blades',
  },
  'سكة/مسار': {
    AppLanguage.arabic: 'سكة/مسار',
    AppLanguage.french: 'Coulisse',
    AppLanguage.english: 'Track',
  },
  'كيت (Kit)': {
    AppLanguage.arabic: 'كيت (Kit)',
    AppLanguage.french: 'Kit',
    AppLanguage.english: 'Kit',
  },
  'الشفرة النهائية': {
    AppLanguage.arabic: 'الشفرة النهائية',
    AppLanguage.french: 'Lame finale',
    AppLanguage.english: 'Final Blade',
  },
  'طانديم (Tandem)': {
    AppLanguage.arabic: 'طانديم (Tandem)',
    AppLanguage.french: 'Tandem',
    AppLanguage.english: 'Tandem',
  },
  'رولمان (Roulement)': {
    AppLanguage.arabic: 'رولمان (Roulement)',
    AppLanguage.french: 'Roulement',
    AppLanguage.english: 'Bearing',
  },
  'قياس المحور المتوافق (مثال: 40 أو 60 مم)': {
    AppLanguage.arabic: 'قياس المحور المتوافق (مثال: 40 أو 60 مم)',
    AppLanguage.french: 'Diamètre d’axe compatible (ex. : 40 ou 60 mm)',
    AppLanguage.english: 'Compatible axle diameter (e.g. 40 or 60 mm)',
  },
  'توليب (Tulip)': {
    AppLanguage.arabic: 'توليب (Tulip)',
    AppLanguage.french: 'Tulipe',
    AppLanguage.english: 'Tulip',
  },
  'بالقطعة': {
    AppLanguage.arabic: 'بالقطعة',
    AppLanguage.french: 'Par pièce',
    AppLanguage.english: 'Per piece',
  },
  'بالبارة': {
    AppLanguage.arabic: 'بالبارة',
    AppLanguage.french: 'Par barre',
    AppLanguage.english: 'Per bar',
  },
  'إضافة مركب للستار': {
    AppLanguage.arabic: 'إضافة مركب للستار',
    AppLanguage.french: 'Ajouter un composant de volet',
    AppLanguage.english: 'Add shutter component',
  },
  'اسم المركب (مثال: محرك سومفي)': {
    AppLanguage.arabic: 'اسم المركب (مثال: محرك سومفي)',
    AppLanguage.french: 'Nom du composant (Ex : Moteur Somfy)',
    AppLanguage.english: 'Component name (e.g. Somfy motor)',
  },
  'طول البارة (بالمتر)': {
    AppLanguage.arabic: 'طول البارة (بالمتر)',
    AppLanguage.french: 'Longueur de barre (mètres)',
    AppLanguage.english: 'Bar length (meters)',
  },
  'نوع الشفرة/الملحق': {
    AppLanguage.arabic: 'نوع الشفرة/الملحق',
    AppLanguage.french: 'Type de lame/accessoire',
    AppLanguage.english: 'Blade/Accessory type',
  },
  'الشفرة المرتبطة (Blade)': {
    AppLanguage.arabic: 'الشفرة المرتبطة (Blade)',
    AppLanguage.french: 'Lame associée',
    AppLanguage.english: 'Associated blade',
  },
  'القياس (مثال: 185 أو 55)': {
    AppLanguage.arabic: 'القياس (مثال: 185 أو 55)',
    AppLanguage.french: 'Mesure (Ex : 185 ou 55)',
    AppLanguage.english: 'Measurement (e.g. 185 ou 55)',
  },
  'ارتفاع الشفرة (مم)': {
    AppLanguage.arabic: 'ارتفاع الشفرة (مم)',
    AppLanguage.french: 'Hauteur de lame (mm)',
    AppLanguage.english: 'Blade height (mm)',
  },
  'قياس السكة (مم)': {
    AppLanguage.arabic: 'قياس السكة (مم)',
    AppLanguage.french: 'Mesure de coulisse (mm)',
    AppLanguage.english: 'Track measurement (mm)',
  },
  'قياس السكة المطابق (مم)': {
    AppLanguage.arabic: 'قياس السكة المطابق (مم)',
    AppLanguage.french: 'Mesure de coulisse correspondante (mm)',
    AppLanguage.english: 'Matching track measurement (mm)',
  },
  'ارتفاع الشفرة:': {
    AppLanguage.arabic: 'ارتفاع الشفرة:',
    AppLanguage.french: 'Hauteur de lame :',
    AppLanguage.english: 'Blade height:',
  },
  'قياس السكة المطابق:': {
    AppLanguage.arabic: 'قياس السكة المطابق:',
    AppLanguage.french: 'Mesure de coulisse correspondante :',
    AppLanguage.english: 'Matching track measurement:',
  },
  'بحث بالاسم أو النوع': {
    AppLanguage.arabic: 'بحث بالاسم أو النوع',
    AppLanguage.french: 'Rechercher par nom ou type',
    AppLanguage.english: 'Search by name or type',
  },
  'لا توجد نتائج': {
    AppLanguage.arabic: 'لا توجد نتائج',
    AppLanguage.french: 'Aucun résultat',
    AppLanguage.english: 'No results',
  },
  'سمك أغطية الشفرات (مم)': {
    AppLanguage.arabic: 'سمك أغطية الشفرات (مم)',
    AppLanguage.french: 'Épaisseur des bouchons (mm)',
    AppLanguage.english: 'Blade end caps thickness (mm)',
  },
  'تعديل مركب للستار': {
    AppLanguage.arabic: 'تعديل مركب للستار',
    AppLanguage.french: 'Modifier le composant de volet',
    AppLanguage.english: 'Edit shutter component',
  },
  'اسم المركب': {
    AppLanguage.arabic: 'اسم المركب',
    AppLanguage.french: 'Nom du composant',
    AppLanguage.english: 'Component name',
  },
  'إخفاء المؤرشف': {
    AppLanguage.arabic: 'إخفاء المؤرشف',
    AppLanguage.french: 'Masquer les archivés',
    AppLanguage.english: 'Hide Archived',
  },
  'عرض المؤرشف': {
    AppLanguage.arabic: 'عرض المؤرشف',
    AppLanguage.french: 'Afficher les archivés',
    AppLanguage.english: 'Show Archived',
  },
  'مرتبط بـ:': {
    AppLanguage.arabic: 'مرتبط بـ:',
    AppLanguage.french: 'Associé à :',
    AppLanguage.english: 'Associated with:',
  },
  'طول البارة:': {
    AppLanguage.arabic: 'طول البارة:',
    AppLanguage.french: 'Longueur de barre :',
    AppLanguage.english: 'Bar length:',
  },
  'سمك الأغطية:': {
    AppLanguage.arabic: 'سمك الأغطية:',
    AppLanguage.french: 'Épaisseur des bouchons :',
    AppLanguage.english: 'Caps thickness:',
  },
  'اختر المكون': {
    AppLanguage.arabic: 'اختر المكون',
    AppLanguage.french: 'Sélectionner le composant',
    AppLanguage.english: 'Select Component',
  },
  'تخصيص للزجاج': {
    AppLanguage.arabic: 'تخصيص للزجاج',
    AppLanguage.french: 'Personnaliser le verre',
    AppLanguage.english: 'Customize Glass',
  },
  'تخصيص مظهر الزجاج': {
    AppLanguage.arabic: 'تخصيص مظهر الزجاج',
    AppLanguage.french: "Personnaliser l'aspect du verre",
    AppLanguage.english: 'Customize Glass Appearance',
  },
  'الزجاج الحالي': {
    AppLanguage.arabic: 'الزجاج الحالي',
    AppLanguage.french: 'Verre actuel',
    AppLanguage.english: 'Current Glass',
  },
  'Parclose': {
    AppLanguage.arabic: 'باكيت الزجاج (Parclose)',
    AppLanguage.french: 'Parclose',
    AppLanguage.english: 'Glass Bead (Parclose)',
  },
  'Choisir la parclose': {
    AppLanguage.arabic: 'اختر البيركلوز (Parclose)',
    AppLanguage.french: 'Choisir la parclose',
    AppLanguage.english: 'Choose Glass Bead (Parclose)',
  },
  'Épaisseur max du vitrage (mm)': {
    AppLanguage.arabic: 'السمك الأقصى للزجاج (مم)',
    AppLanguage.french: 'Épaisseur max du vitrage (mm)',
    AppLanguage.english: 'Max glass thickness (mm)',
  },
  'السمك الأقصى للزجاج': {
    AppLanguage.arabic: 'السمك الأقصى للزجاج',
    AppLanguage.french: 'Épaisseur max du vitrage',
    AppLanguage.english: 'Max glass thickness',
  },
  'لا توجد عناصر باكيت زجاج مسجلة لهذه السلسلة في قاعدة البيانات': {
    AppLanguage.arabic:
        'لا توجد عناصر باكيت زجاج مسجلة لهذه السلسلة في قاعدة البيانات',
    AppLanguage.french:
        'Aucune parclose enregistrée pour cette gamme dans la base de données',
    AppLanguage.english:
        'No glass bead sections registered for this series in the database',
  },
  'تخصيص الإكسسوارات': {
    AppLanguage.arabic: 'تخصيص الإكسسوارات',
    AppLanguage.french: 'Personnaliser les accessoires',
    AppLanguage.english: 'Customize Accessories',
  },
  'تخصيص مركبات الستائر': {
    AppLanguage.arabic: 'تخصيص مركبات الستائر',
    AppLanguage.french: 'Personnaliser les volets roulants',
    AppLanguage.english: 'Customize Roller Shutters',
  },
  'فضي': {
    AppLanguage.arabic: 'فضي',
    AppLanguage.french: 'Argent',
    AppLanguage.english: 'Silver',
  },
  'ذهبي': {
    AppLanguage.arabic: 'ذهبي',
    AppLanguage.french: 'Doré',
    AppLanguage.english: 'Gold',
  },
  'شامبانيا': {
    AppLanguage.arabic: 'شامبانيا',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'مخصص': {
    AppLanguage.arabic: 'مخصص',
    AppLanguage.french: 'Personnalisé',
    AppLanguage.english: 'Custom',
  },
  'خيارات الطباعة': {
    AppLanguage.arabic: 'خيارات الطباعة',
    AppLanguage.french: 'Options d\'impression',
    AppLanguage.english: 'Printing Options',
  },
  'هل تريد طباعة كل النسخ أم نسخة محددة؟': {
    AppLanguage.arabic: 'هل تريد طباعة كل النسخ أم نسخة محددة؟',
    AppLanguage.french:
        'Voulez-vous imprimer toutes les copies ou une copie spécifique?',
    AppLanguage.english: 'Do you want to print all copies or a specific one?',
  },
  'طباعة الكل': {
    AppLanguage.arabic: 'طباعة الكل',
    AppLanguage.french: 'Tout imprimer',
    AppLanguage.english: 'Print All',
  },
  'طباعة كل النسخ': {
    AppLanguage.arabic: 'طباعة كل النسخ',
    AppLanguage.french: 'Imprimer toutes les copies',
    AppLanguage.english: 'Print All Copies',
  },
  'نسخة': {
    AppLanguage.arabic: 'نسخة',
    AppLanguage.french: 'Copie',
    AppLanguage.english: 'Copy',
  },
  'طباعة النسخة رقم': {
    AppLanguage.arabic: 'طباعة النسخة رقم',
    AppLanguage.french: 'Imprimer la copie numéro',
    AppLanguage.english: 'Print Copy Number',
  },
  'يرجى حفظ القياسات قبل الطباعة': {
    AppLanguage.arabic: 'يرجى حفظ القياسات قبل الطباعة',
    AppLanguage.french: 'Veuillez enregistrer les mesures avant d\'imprimer',
    AppLanguage.english: 'Please save measurements before printing',
  },
  'طباعة العنصر': {
    AppLanguage.arabic: 'طباعة العنصر',
    AppLanguage.french: 'Imprimer l\'élément',
    AppLanguage.english: 'Print Element',
  },

  'الشامبانيا': {
    AppLanguage.arabic: 'الشامبانيا',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'الخشبي الفاتح': {
    AppLanguage.arabic: 'الخشبي الفاتح',
    AppLanguage.french: 'Faux bois clair',
    AppLanguage.english: 'Light Wood',
  },
  'الأزرق': {
    AppLanguage.arabic: 'الأزرق',
    AppLanguage.french: 'Bleu',
    AppLanguage.english: 'Blue',
  },
  'أزرق بلجيكي': {
    AppLanguage.arabic: 'أزرق بلجيكي',
    AppLanguage.french: 'Bleu Belge',
    AppLanguage.english: 'Belgian Blue',
  },
  'الذهبي': {
    AppLanguage.arabic: 'الذهبي',
    AppLanguage.french: 'Doré',
    AppLanguage.english: 'Gold',
  },
  'الفضي': {
    AppLanguage.arabic: 'الفضي',
    AppLanguage.french: 'Argent',
    AppLanguage.english: 'Silver',
  },
  'الخشبي الداكن': {
    AppLanguage.arabic: 'الخشبي الداكن',
    AppLanguage.french: 'Faux bois foncé',
    AppLanguage.english: 'Dark Wood',
  },
  'الأبيض': {
    AppLanguage.arabic: 'الأبيض',
    AppLanguage.french: 'Blanc',
    AppLanguage.english: 'White',
  },
  'الأسود': {
    AppLanguage.arabic: 'الأسود',
    AppLanguage.french: 'Noir',
    AppLanguage.english: 'Black',
  },
  'الرمادي': {
    AppLanguage.arabic: 'الرمادي',
    AppLanguage.french: 'Gris',
    AppLanguage.english: 'Grey',
  },
  'البني': {
    AppLanguage.arabic: 'البني',
    AppLanguage.french: 'Marron',
    AppLanguage.english: 'Brown',
  },
  'البيج': {
    AppLanguage.arabic: 'البيج',
    AppLanguage.french: 'Beige',
    AppLanguage.english: 'Beige',
  },
  'الخام': {
    AppLanguage.arabic: 'الخام',
    AppLanguage.french: 'Brut',
    AppLanguage.english: 'Raw',
  },
  'الأصفر': {
    AppLanguage.arabic: 'الأصفر',
    AppLanguage.french: 'Jaune',
    AppLanguage.english: 'Yellow',
  },
  'الأحمر': {
    AppLanguage.arabic: 'الأحمر',
    AppLanguage.french: 'Rouge',
    AppLanguage.english: 'Red',
  },
  'الأخضر': {
    AppLanguage.arabic: 'الأخضر',
    AppLanguage.french: 'Vert',
    AppLanguage.english: 'Green',
  },
  'الخشبي': {
    AppLanguage.arabic: 'الخشبي',
    AppLanguage.french: 'Faux bois',
    AppLanguage.english: 'Wood',
  },

  'الأزرق البلجيكي': {
    AppLanguage.arabic: 'الأزرق البلجيكي',
    AppLanguage.french: 'Bleu Belge',
    AppLanguage.english: 'Belgian Blue',
  },
  'الازرق البلجيكي': {
    AppLanguage.arabic: 'الازرق البلجيكي',
    AppLanguage.french: 'Bleu Belge',
    AppLanguage.english: 'Belgian Blue',
  },
  'الرمادي البلجيكي': {
    AppLanguage.arabic: 'الرمادي البلجيكي',
    AppLanguage.french: 'Gris Belge',
    AppLanguage.english: 'Belgian Grey',
  },
  'الاخضر': {
    AppLanguage.arabic: 'الاخضر',
    AppLanguage.french: 'Vert',
    AppLanguage.english: 'Green',
  },
  'الازرق': {
    AppLanguage.arabic: 'الازرق',
    AppLanguage.french: 'Bleu',
    AppLanguage.english: 'Blue',
  },
  'الابيض': {
    AppLanguage.arabic: 'الابيض',
    AppLanguage.french: 'Blanc',
    AppLanguage.english: 'White',
  },
  'الاسود': {
    AppLanguage.arabic: 'الاسود',
    AppLanguage.french: 'Noir',
    AppLanguage.english: 'Black',
  },
  'الاحمر': {
    AppLanguage.arabic: 'الاحمر',
    AppLanguage.french: 'Rouge',
    AppLanguage.english: 'Red',
  },
  'الاصفر': {
    AppLanguage.arabic: 'الاصفر',
    AppLanguage.french: 'Jaune',
    AppLanguage.english: 'Yellow',
  },
  'شومبانيا': {
    AppLanguage.arabic: 'شومبانيا',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'الشامبني': {
    AppLanguage.arabic: 'الشامبني',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'الشامبان': {
    AppLanguage.arabic: 'الشامبان',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },

  'اخضر': {
    AppLanguage.arabic: 'اخضر',
    AppLanguage.french: 'Vert',
    AppLanguage.english: 'Green',
  },
  'ازرق': {
    AppLanguage.arabic: 'ازرق',
    AppLanguage.french: 'Bleu',
    AppLanguage.english: 'Blue',
  },
  'شامبان': {
    AppLanguage.arabic: 'شامبان',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },

  '🇧🇪 ازرق بلجيكي': {
    AppLanguage.arabic: '🇧🇪 ازرق بلجيكي',
    AppLanguage.french: '🇧🇪 Bleu Belge',
    AppLanguage.english: '🇧🇪 Belgian Blue',
  },
  '🇧🇪 رمادي بلجيكي': {
    AppLanguage.arabic: '🇧🇪 رمادي بلجيكي',
    AppLanguage.french: '🇧🇪 Gris Belge',
    AppLanguage.english: '🇧🇪 Belgian Grey',
  },
  '🇧🇪الأزرق البلجيكي': {
    AppLanguage.arabic: '🇧🇪الأزرق البلجيكي',
    AppLanguage.french: '🇧🇪 Bleu Belge',
    AppLanguage.english: '🇧🇪 Belgian Blue',
  },
  '🇧🇪الرمادي البلجيكي': {
    AppLanguage.arabic: '🇧🇪الرمادي البلجيكي',
    AppLanguage.french: '🇧🇪 Gris Belge',
    AppLanguage.english: '🇧🇪 Belgian Grey',
  },
  '🇧🇪 الأزرق البلجيكي': {
    AppLanguage.arabic: '🇧🇪 الأزرق البلجيكي',
    AppLanguage.french: '🇧🇪 Bleu Belge',
    AppLanguage.english: '🇧🇪 Belgian Blue',
  },
  '🇧🇪 الرمادي البلجيكي': {
    AppLanguage.arabic: '🇧🇪 الرمادي البلجيكي',
    AppLanguage.french: '🇧🇪 Gris Belge',
    AppLanguage.english: '🇧🇪 Belgian Grey',
  },

  'إدارة الكتالوج (Profiles & Sections)': {
    AppLanguage.arabic: 'إدارة الكتالوج (Profiles & Sections)',
    AppLanguage.french: 'Gestion du catalogue',
    AppLanguage.english: 'Catalog Management',
  },
  'إدارة الكتالوج': {
    AppLanguage.arabic: 'إدارة الكتالوج',
    AppLanguage.french: 'Gestion du catalogue',
    AppLanguage.english: 'Catalog Management',
  },
  'تحليل الطلبيات': {
    AppLanguage.arabic: 'تحليل الطلبيات',
    AppLanguage.french: 'Analyse des commandes',
    AppLanguage.english: 'Orders Analysis',
  },
  'حالة الطلبيات': {
    AppLanguage.arabic: 'حالة الطلبيات',
    AppLanguage.french: 'Statut des commandes',
    AppLanguage.english: 'Orders Status',
  },
  'دائري': {
    AppLanguage.arabic: 'دائري',
    AppLanguage.french: 'Circulaire',
    AppLanguage.english: 'Pie',
  },
  'أشهر': {
    AppLanguage.arabic: 'أشهر',
    AppLanguage.french: 'Mois',
    AppLanguage.english: 'Months',
  },
  'منحنى بياني': {
    AppLanguage.arabic: 'منحنى بياني',
    AppLanguage.french: 'Lignes',
    AppLanguage.english: 'Lines',
  },
  'قيد الانتظار': {
    AppLanguage.arabic: 'قيد الانتظار',
    AppLanguage.french: 'En attente',
    AppLanguage.english: 'Pending',
  },
  'جارية': {
    AppLanguage.arabic: 'جارية',
    AppLanguage.french: 'En cours',
    AppLanguage.english: 'In Progress',
  },
  'تركيب': {
    AppLanguage.arabic: 'تركيب',
    AppLanguage.french: 'Installation',
    AppLanguage.english: 'Installation',
  },
  'منتهية': {
    AppLanguage.arabic: 'منتهية',
    AppLanguage.french: 'Terminée',
    AppLanguage.english: 'Done',
  },
  'جديدة': {
    AppLanguage.arabic: 'جديدة',
    AppLanguage.french: 'Nouvelle',
    AppLanguage.english: 'New',
  },
  'جديد': {
    AppLanguage.arabic: 'جديد',
    AppLanguage.french: 'Nouveau',
    AppLanguage.english: 'New',
  },


  'المستودع الرئيسي': {
    AppLanguage.arabic: 'المستودع الرئيسي',
    AppLanguage.french: 'Dépôt principal',
    AppLanguage.english: 'Main Warehouse',
  },

  'D.N.A. جزائري': {
    AppLanguage.arabic: 'D.N.A. جزائري',
    AppLanguage.french: 'D.A.',
    AppLanguage.english: 'D.A.',
  },
  'دينار جزائري': {
    AppLanguage.arabic: 'دينار جزائري',
    AppLanguage.french: 'D.A.',
    AppLanguage.english: 'D.A.',
  },
  'مدفوعة': {
    AppLanguage.arabic: 'مدفوعة',
    AppLanguage.french: 'Payée',
    AppLanguage.english: 'Paid',
  },
  'مردودة': {
    AppLanguage.arabic: 'مردودة',
    AppLanguage.french: 'Remboursée',
    AppLanguage.english: 'Refunded',
  },
  'الخزينة (Caisse)': {
    AppLanguage.arabic: 'الخزينة (Caisse)',
    AppLanguage.french: 'Caisse',
    AppLanguage.english: 'Treasury',
  },
  'الخزينة': {
    AppLanguage.arabic: 'الخزينة',
    AppLanguage.french: 'Caisse',
    AppLanguage.english: 'Treasury',
  },
  'دفع من المورد': {
    AppLanguage.arabic: 'دفع من المورد',
    AppLanguage.french: 'Paiement au fournisseur',
    AppLanguage.english: 'Payment to supplier',
  },
  'بحث بالاسم أو البيان': {
    AppLanguage.arabic: 'بحث بالاسم أو البيان',
    AppLanguage.french: 'Recherche par nom ou description',
    AppLanguage.english: 'Search by name or description',
  },
  'الفاتورة': {
    AppLanguage.arabic: 'الفاتورة',
    AppLanguage.french: 'Facture',
    AppLanguage.english: 'Invoice',
  },
  'فاتورة': {
    AppLanguage.arabic: 'فاتورة',
    AppLanguage.french: 'Facture',
    AppLanguage.english: 'Invoice',
  },
  'عامل (أجر/سلفة)': {
    AppLanguage.arabic: 'عامل (أجر/سلفة)',
    AppLanguage.french: 'Employé (Salaire/Avance)',
    AppLanguage.english: 'Worker (Salary/Advance)',
  },
  'عامل': {
    AppLanguage.arabic: 'عامل',
    AppLanguage.french: 'Ouvrier',
    AppLanguage.english: 'Worker',
  },
  'دفع فاتورة مشتريات للمورد': {
    AppLanguage.arabic: 'دفع فاتورة مشتريات للمورد',
    AppLanguage.french: 'Paiement de la facture d\'achat au fournisseur',
    AppLanguage.english: 'Payment of purchase invoice to supplier',
  },
  'استرجاع من المورد': {
    AppLanguage.arabic: 'استرجاع من المورد',
    AppLanguage.french: 'Récupération du fournisseur',
    AppLanguage.english: 'Retrieval from supplier',
  },
  'فاتورة مشتريات رقم': {
    AppLanguage.arabic: 'فاتورة مشتريات رقم',
    AppLanguage.french: 'Facture d\'achat N°',
    AppLanguage.english: 'Purchase invoice No.',
  },
  'معاملة جديدة': {
    AppLanguage.arabic: 'معاملة جديدة',
    AppLanguage.french: 'Nouvelle transaction',
    AppLanguage.english: 'New Transaction',
  },
  'إضافة معاملة للصندوق': {
    AppLanguage.arabic: 'إضافة معاملة للصندوق',
    AppLanguage.french: 'Ajouter une transaction à la caisse',
    AppLanguage.english: 'Add cash transaction',
  },
  'خيارات حذف المكون المؤرشف': {
    AppLanguage.arabic: 'خيارات حذف المكون المؤرشف',
    AppLanguage.french: 'Options de suppression du composant archivé',
    AppLanguage.english: 'Archived component deletion options',
  },
  'تأكيد الحذف والأرشفة': {
    AppLanguage.arabic: 'تأكيد الحذف والأرشفة',
    AppLanguage.french: 'Confirmer la suppression et l\'archivage',
    AppLanguage.english: 'Confirm deletion and archiving',
  },
  'هذا العنصر مؤرشف بالفعل. يمكنك استعادته ليصبح نشطاً مجدداً أو حذفه نهائياً من قاعدة البيانات.': {
    AppLanguage.arabic:
        'هذا العنصر مؤرشف بالفعل. يمكنك استعادته ليصبح نشطاً مجدداً أو حذفه نهائياً من قاعدة البيانات.',
    AppLanguage.french:
        'Cet élément est déjà archivé. Vous pouvez le restaurer pour le rendre à nouveau actif ou le supprimer définitivement de la base de données.',
    AppLanguage.english:
        'This item is already archived. You can restore it to active state or permanently delete it from the database.',
  },
  'يمكنك أرشفة هذا العنصر (إخفاؤه من الطلبيات الجديدة مع الحفاظ على الفواتير القديمة) أو حذفه نهائياً من قاعدة البيانات.': {
    AppLanguage.arabic:
        'يمكنك أرشفة هذا العنصر (إخفاؤه من الطلبيات الجديدة مع الحفاظ على الفواتير القديمة) أو حذفه نهائياً من قاعدة البيانات.',
    AppLanguage.french:
        'Vous pouvez archiver cet élément (le masquer des nouvelles commandes tout en conservant les anciennes factures) ou le supprimer définitivement de la base de données.',
    AppLanguage.english:
        'You can archive this item (hide it from new orders while keeping old invoices) or permanently delete it from the database.',
  },
  'استعادة المكون': {
    AppLanguage.arabic: 'استعادة المكون',
    AppLanguage.french: 'Restaurer le composant',
    AppLanguage.english: 'Restore component',
  },
  'أرشفة (إخفاء)': {
    AppLanguage.arabic: 'أرشفة (إخفاء)',
    AppLanguage.french: 'Archiver (Masquer)',
    AppLanguage.english: 'Archive (Hide)',
  },
  'ادارة Kits': {
    AppLanguage.arabic: 'ادارة Kits',
    AppLanguage.french: 'Gestion des Kits',
    AppLanguage.english: 'Kit Management',
  },
  'مؤرشف': {
    AppLanguage.arabic: 'مؤرشف',
    AppLanguage.french: 'Archivé',
    AppLanguage.english: 'Archived',
  },
  'إكسترودي': {
    AppLanguage.arabic: 'إكسترودي',
    AppLanguage.french: 'Extrudé',
    AppLanguage.english: 'Extruded',
  },


  'doc_devis_menu': {
    AppLanguage.arabic: 'تسعيرة (Devis)',
    AppLanguage.french: 'Devis',
    AppLanguage.english: 'Quote',
  },
  'doc_devis': {
    AppLanguage.arabic: 'تسعيرة',
    AppLanguage.french: 'Devis',
    AppLanguage.english: 'Quote',
  },
  'doc_bon_livraison_menu': {
    AppLanguage.arabic: 'وصل التسليم (Bon de livraison)',
    AppLanguage.french: 'Bon de livraison',
    AppLanguage.english: 'Delivery Note',
  },
  'doc_bon_livraison': {
    AppLanguage.arabic: 'وصل التسليم',
    AppLanguage.french: 'Bon de livraison',
    AppLanguage.english: 'Delivery Note',
  },
  'doc_bon_livraison_sans_prix_menu': {
    AppLanguage.arabic: 'وصل التسليم بدون أسعار',
    AppLanguage.french: 'Bon de livraison sans prix',
    AppLanguage.english: 'Delivery Note without prices',
  },
  'doc_bon_livraison_sans_prix': {
    AppLanguage.arabic: 'وصل التسليم بدون أسعار',
    AppLanguage.french: 'Bon de livraison sans prix',
    AppLanguage.english: 'Delivery Note without prices',
  },
  'doc_bon_livraison_partiel_menu': {
    AppLanguage.arabic: 'وصل التسليم الجزئي',
    AppLanguage.french: 'Bon de livraison partiel',
    AppLanguage.english: 'Partial Delivery Note',
  },
  'doc_bon_livraison_partiel': {
    AppLanguage.arabic: 'وصل التسليم الجزئي',
    AppLanguage.french: 'Bon de livraison partiel',
    AppLanguage.english: 'Partial Delivery Note',
  },
  'doc_bon_livraison_partiel_sans_prix_menu': {
    AppLanguage.arabic: 'وصل التسليم الجزئي بدون أسعار',
    AppLanguage.french: 'Bon de livraison partiel sans prix',
    AppLanguage.english: 'Partial Delivery Note without prices',
  },
  'doc_bon_livraison_partiel_sans_prix': {
    AppLanguage.arabic: 'وصل التسليم الجزئي بدون أسعار',
    AppLanguage.french: 'Bon de livraison partiel sans prix',
    AppLanguage.english: 'Partial Delivery Note without prices',
  },
  'doc_bon_charge_menu': {
    AppLanguage.arabic: 'وصل الشحن (Bon de charge)',
    AppLanguage.french: 'Bon de charge',
    AppLanguage.english: 'Loading Note',
  },
  'doc_bon_charge': {
    AppLanguage.arabic: 'وصل الشحن',
    AppLanguage.french: 'Bon de charge',
    AppLanguage.english: 'Loading Note',
  },
  'سلع الطلبية وموادها (تقرير النواقص)': {
    AppLanguage.arabic: 'سلع الطلبية وموادها (تقرير النواقص)',
    AppLanguage.french: 'Rapport des articles manquants',
    AppLanguage.english: 'Missing Items Report',
  },
  'السلع المطلوبة': {
    AppLanguage.arabic: 'السلع المطلوبة',
    AppLanguage.french: 'Articles demandés',
    AppLanguage.english: 'Requested Items',
  },
  'مجموع سلع جميع المنتجات مجمّعة': {
    AppLanguage.arabic: 'مجموع سلع جميع المنتجات مجمّعة',
    AppLanguage.french: 'Total des articles, tous produits confondus',
    AppLanguage.english: 'Total of all items combined',
  },
  'تأكيد القياسات والملصقات (Stickers)': {
    AppLanguage.arabic: 'تأكيد القياسات والملصقات (Stickers)',
    AppLanguage.french: 'Confirmation des mesures et étiquettes',
    AppLanguage.english: 'Confirm Measurements & Stickers',
  },
  'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة': {
    AppLanguage.arabic:
        'تعديل القياسات الفعلية للموقع وطباعة الباركود لكل قطعة',
    AppLanguage.french:
        'Modification des mesures réelles des sites et impression des codes-barres par pièce',
    AppLanguage.english:
        'Edit actual site measurements and print barcode per piece',
  },
  'تأكيد الطلبية (Confirmer)': {
    AppLanguage.arabic: 'تأكيد الطلبية (Confirmer)',
    AppLanguage.french: 'Confirmer la commande',
    AppLanguage.english: 'Confirm Order',
  },

  'نواقص كل الطلبيات (Aluminium, Verre, Acc)': {
    AppLanguage.arabic: 'نواقص كل الطلبيات (Aluminium, Verre, Acc)',
    AppLanguage.french:
        'Besoins de toutes les commandes (Aluminium, Verre, Acc)',
    AppLanguage.english: 'Needs of all orders (Aluminium, Glass, Acc)',
  },
  'أجور وسلفيات العمال': {
    AppLanguage.arabic: 'أجور وسلفيات العمال',
    AppLanguage.french: 'Salaires et Avances des Employés',
    AppLanguage.english: 'Workers Salaries & Advances',
  },
  'إدارة رواتب العمال والخصم من الصندوق': {
    AppLanguage.arabic: 'إدارة رواتب العمال والخصم من الصندوق',
    AppLanguage.french: 'Gérer les salaires et déduire de la caisse',
    AppLanguage.english: 'Manage worker salaries & deduct from treasury',
  },
  'مشتريات الورشة': {
    AppLanguage.arabic: 'مشتريات الورشة',
    AppLanguage.french: 'Achats de l\'atelier',
    AppLanguage.english: 'Workshop Purchases',
  },
  'فواتير الشراء وإدارة المصاريف': {
    AppLanguage.arabic: 'فواتير الشراء وإدارة المصاريف',
    AppLanguage.french: 'Factures d\'achat et gestion des dépenses',
    AppLanguage.english: 'Purchase invoices & expense management',
  },
  'حسابات الموردين': {
    AppLanguage.arabic: 'حسابات الموردين',
    AppLanguage.french: 'Comptes Fournisseurs',
    AppLanguage.english: 'Supplier Accounts',
  },
  'الديون ومدفوعات الموردين': {
    AppLanguage.arabic: 'الديون ومدفوعات الموردين',
    AppLanguage.french: 'Dettes et paiements des fournisseurs',
    AppLanguage.english: 'Supplier debts and payments',
  },
  'الخزينة والمالية': {
    AppLanguage.arabic: 'الخزينة والمالية',
    AppLanguage.french: 'Trésorerie et Finance',
    AppLanguage.english: 'Treasury & Finance',
  },
  'الصندوق، مدفوعات الزبائن، والأرباح': {
    AppLanguage.arabic: 'الصندوق، مدفوعات الزبائن، والأرباح',
    AppLanguage.french: 'Caisse, paiements clients et bénéfices',
    AppLanguage.english: 'Cash box, client payments, and profits',
  },
  'مركز التقارير والمالية': {
    AppLanguage.arabic: 'مركز التقارير والمالية',
    AppLanguage.french: 'Centre des Rapports et Finances',
    AppLanguage.english: 'Reports & Finance Hub',
  },
  'لا توجد لديك صلاحيات لرؤية أي تقارير': {
    AppLanguage.arabic: 'لا توجد لديك صلاحيات لرؤية أي تقارير',
    AppLanguage.french: 'Vous n\'avez pas la permission de voir les rapports',
    AppLanguage.english: 'You do not have permission to view any reports',
  },

  'قبض (Encaissement)': {
    AppLanguage.arabic: 'قبض (Encaissement)',
    AppLanguage.french: 'Encaissement',
    AppLanguage.english: 'Receipt (Inflow)',
  },
  'دفع (Décaissement)': {
    AppLanguage.arabic: 'دفع (Décaissement)',
    AppLanguage.french: 'Décaissement',
    AppLanguage.english: 'Payment (Outflow)',
  },
  'اختر الزبون': {
    AppLanguage.arabic: 'اختر الزبون',
    AppLanguage.french: 'Sélectionner le client',
    AppLanguage.english: 'Select customer',
  },
  'مصاريف عامة': {
    AppLanguage.arabic: 'مصاريف عامة',
    AppLanguage.french: 'Dépenses générales',
    AppLanguage.english: 'General expenses',
  },
  'جهة الدفع': {
    AppLanguage.arabic: 'جهة الدفع',
    AppLanguage.french: 'Bénéficiaire',
    AppLanguage.english: 'Payee',
  },
  'المبلغ': {
    AppLanguage.arabic: 'المبلغ',
    AppLanguage.french: 'Montant',
    AppLanguage.english: 'Amount',
  },
  'البيان (تفاصيل إضافية)': {
    AppLanguage.arabic: 'البيان (تفاصيل إضافية)',
    AppLanguage.french: 'Description (détails)',
    AppLanguage.english: 'Description (details)',
  },

  'بواسطة': {
    AppLanguage.arabic: 'بواسطة',
    AppLanguage.french: 'Par',
    AppLanguage.english: 'By',
  },
  'المدير': {
    AppLanguage.arabic: 'المدير',
    AppLanguage.french: 'Directeur',
    AppLanguage.english: 'Manager',
  },
  'دفع للمورد': {
    AppLanguage.arabic: 'دفع للمورد',
    AppLanguage.french: 'Paiement au fournisseur',
    AppLanguage.english: 'Payment to supplier',
  },
  'سلفة للعامل': {
    AppLanguage.arabic: 'سلفة للعامل',
    AppLanguage.french: 'Avance pour l\'ouvrier',
    AppLanguage.english: 'Advance to worker',
  },
  'أجرة للعامل': {
    AppLanguage.arabic: 'أجرة للعامل',
    AppLanguage.french: 'Salaire pour l\'ouvrier',
    AppLanguage.english: 'Salary to worker',
  },
  'من الزبون:': {
    AppLanguage.arabic: 'من الزبون:',
    AppLanguage.french: 'Du client:',
    AppLanguage.english: 'From customer:',
  },
  'إلى العامل:': {
    AppLanguage.arabic: 'إلى العامل:',
    AppLanguage.french: 'À l\'ouvrier:',
    AppLanguage.english: 'To worker:',
  },

  'commandes': {
    AppLanguage.arabic: 'الطلبيات',
    AppLanguage.french: 'Commandes',
    AppLanguage.english: 'Orders',
  },
  'clients': {
    AppLanguage.arabic: 'الزبائن',
    AppLanguage.french: 'Clients',
    AppLanguage.english: 'Customers',
  },
  'produits': {
    AppLanguage.arabic: 'المنتجات',
    AppLanguage.french: 'Produits',
    AppLanguage.english: 'Products',
  },
  'مشاركة': {
    AppLanguage.arabic: 'مشاركة',
    AppLanguage.french: 'Partager',
    AppLanguage.english: 'Share',
  },
  'طباعة': {
    AppLanguage.arabic: 'طباعة',
    AppLanguage.french: 'Imprimer',
    AppLanguage.english: 'Print',
  },
  'تم حفظ PDF بنجاح في مجلد التحميلات': {
    AppLanguage.arabic: 'تم حفظ PDF بنجاح في مجلد التحميلات',
    AppLanguage.french:
        'PDF enregistré avec succès dans le dossier Téléchargements',
    AppLanguage.english: 'PDF saved successfully in Downloads folder',
  },
  'فاتورة رسمية / أولية': {
    AppLanguage.arabic: 'فاتورة رسمية / أولية',
    AppLanguage.french: 'Facture Proforma / Officielle',
    AppLanguage.english: 'Proforma / Official Invoice',
  },
  'فاتورة رسمية / أولية بدون أسعار': {
    AppLanguage.arabic: 'فاتورة رسمية / أولية بدون أسعار',
    AppLanguage.french: 'Facture Proforma / Officielle sans prix',
    AppLanguage.english: 'Proforma / Official Invoice without prices',
  },
  'caisse': {
    AppLanguage.arabic: 'صندوق',
    AppLanguage.french: 'Caisse',
    AppLanguage.english: 'Cash Flow',
  },
  'Manage Prices': {
    AppLanguage.arabic: 'إدارة الأسعار',
    AppLanguage.french: 'Gérer les prix',
    AppLanguage.english: 'Manage Prices',
  },
  'settings': {
    AppLanguage.arabic: 'الإعدادات',
    AppLanguage.french: 'Paramètres',
    AppLanguage.english: 'Settings',
  },
  'البحث بالاسم أو النوع...': {
    AppLanguage.arabic: 'البحث بالاسم أو النوع...',
    AppLanguage.french: 'Recherche par nom ou type...',
    AppLanguage.english: 'Search by name or type...',
  },
  'البحث بالاسم...': {
    AppLanguage.arabic: 'البحث بالاسم...',
    AppLanguage.french: 'Recherche par nom...',
    AppLanguage.english: 'Search by name...',
  },
  'البحث بالنوع...': {
    AppLanguage.arabic: 'البحث بالنوع...',
    AppLanguage.french: 'Recherche par type...',
    AppLanguage.english: 'Search by type...',
  },
  'إدارة الكيت': {
    AppLanguage.arabic: 'إدارة الكيت',
    AppLanguage.french: 'Gestion des Kits',
    AppLanguage.english: 'Kit Management',
  },
  'بحث في الكيت...': {
    AppLanguage.arabic: 'بحث في الكيت...',
    AppLanguage.french: 'Recherche dans le kit...',
    AppLanguage.english: 'Search in kit...',
  },
  'المركبات': {
    AppLanguage.arabic: 'المركبات',
    AppLanguage.french: 'Composants',
    AppLanguage.english: 'Components',
  },
  'عرض الضلفة': {
    AppLanguage.arabic: 'عرض الضلفة',
    AppLanguage.french: 'Largeur du battant',
    AppLanguage.english: 'Sash width',
  },
  'طول الضلفة': {
    AppLanguage.arabic: 'طول الضلفة',
    AppLanguage.french: 'Hauteur du battant',
    AppLanguage.english: 'Sash height',
  },
  'جودة رفيعة': {
    AppLanguage.arabic: 'جودة رفيعة',
    AppLanguage.french: 'Haute qualité',
    AppLanguage.english: 'Premium Quality',
  },
  'جودة قياسية': {
    AppLanguage.arabic: 'جودة قياسية',
    AppLanguage.french: 'Qualité standard',
    AppLanguage.english: 'Standard Quality',
  },
  'جودة تجارية': {
    AppLanguage.arabic: 'جودة تجارية',
    AppLanguage.french: 'Qualité commerciale',
    AppLanguage.english: 'Commercial Quality',
  },
  'Kit منفصل لكل ضلفة': {
    AppLanguage.arabic: 'Kit منفصل لكل ضلفة',
    AppLanguage.french: 'Kit séparé pour chaque battant',
    AppLanguage.english: 'Separate kit for each sash',
  },
  'ضلفتان = Kit x2': {
    AppLanguage.arabic: 'ضلفتان = Kit x2',
    AppLanguage.french: 'Deux battants = Kit x2',
    AppLanguage.english: 'Two sashes = Kit x2',
  },
  'Kit لكل ضلفة': {
    AppLanguage.arabic: 'Kit لكل ضلفة',
    AppLanguage.french: 'Kit pour chaque battant',
    AppLanguage.english: 'Kit for each sash',
  },
  'اضافة Kit': {
    AppLanguage.arabic: 'اضافة Kit',
    AppLanguage.french: 'Ajouter un Kit',
    AppLanguage.english: 'Add Kit',
  },
  'تعديل Kit': {
    AppLanguage.arabic: 'تعديل Kit',
    AppLanguage.french: 'Modifier le Kit',
    AppLanguage.english: 'Edit Kit',
  },
  'اسم الـ Kit': {
    AppLanguage.arabic: 'اسم الـ Kit',
    AppLanguage.french: 'Nom du Kit',
    AppLanguage.english: 'Kit Name',
  },
  'الغاء': {
    AppLanguage.arabic: 'الغاء',
    AppLanguage.french: 'Annuler',
    AppLanguage.english: 'Cancel',
  },
  'اضافة': {
    AppLanguage.arabic: 'اضافة',
    AppLanguage.french: 'Ajouter',
    AppLanguage.english: 'Add',
  },
  'مجموعة': {
    AppLanguage.arabic: 'مجموعة',
    AppLanguage.french: 'Groupe',
    AppLanguage.english: 'Set',
  },

  'اضافة مركب': {
    AppLanguage.arabic: 'اضافة مركب',
    AppLanguage.french: 'Ajouter un composant',
    AppLanguage.english: 'Add Component',
  },
  'تعديل مركب': {
    AppLanguage.arabic: 'تعديل مركب',
    AppLanguage.french: 'Modifier le composant',
    AppLanguage.english: 'Edit Component',
  },
  'نوع المركب': {
    AppLanguage.arabic: 'نوع المركب',
    AppLanguage.french: 'Type de composant',
    AppLanguage.english: 'Component Type',
  },
  'اكتب أو اختر من القائمة...': {
    AppLanguage.arabic: 'اكتب أو اختر من القائمة...',
    AppLanguage.french: 'Saisissez ou choisissez dans la liste...',
    AppLanguage.english: 'Type or choose from list...',
  },
  'نوع الكمية:': {
    AppLanguage.arabic: 'نوع الكمية:',
    AppLanguage.french: 'Type de quantité :',
    AppLanguage.english: 'Quantity Type:',
  },
  'ثابتة': {
    AppLanguage.arabic: 'ثابتة',
    AppLanguage.french: 'Fixe',
    AppLanguage.english: 'Fixed',
  },
  'بالنطاق (حسب القياس)': {
    AppLanguage.arabic: 'بالنطاق (حسب القياس)',
    AppLanguage.french: 'Par plage (selon mesure)',
    AppLanguage.english: 'By range (according to measure)',
  },
  'بالنوع (Simple/Double Ouvrant)': {
    AppLanguage.arabic: 'بالنوع (Simple/Double Ouvrant)',
    AppLanguage.french: 'Par type (Simple/Double Ouvrant)',
    AppLanguage.english: 'By type (Simple/Double Ouvrant)',
  },
  'القياس المرجعي:': {
    AppLanguage.arabic: 'القياس المرجعي:',
    AppLanguage.french: 'Mesure de référence :',
    AppLanguage.english: 'Reference Measure:',
  },
  'بالنطاق': {
    AppLanguage.arabic: 'بالنطاق',
    AppLanguage.french: 'Par plage',
    AppLanguage.english: 'By range',
  },
  'Simple/Double': {
    AppLanguage.arabic: 'Simple/Double',
    AppLanguage.french: 'Simple/Double',
    AppLanguage.english: 'Simple/Double',
  },

  'الجودة (النوعية)': {
    AppLanguage.arabic: 'الجودة (النوعية)',
    AppLanguage.french: 'Qualité',
    AppLanguage.english: 'Quality',
  },
  'تصنيف الإكسسوار (النوع)': {
    AppLanguage.arabic: 'تصنيف الإكسسوار (النوع)',
    AppLanguage.french: "Catégorie d'accessoire (Type)",
    AppLanguage.english: 'Accessory Category (Type)',
  },
  'عدد البراغي المستخدمة': {
    AppLanguage.arabic: 'عدد البراغي المستخدمة',
    AppLanguage.french: 'Nombre de vis utilisées',
    AppLanguage.english: 'Number of screws used',
  },
  'البراغي': {
    AppLanguage.arabic: 'البراغي',
    AppLanguage.french: 'Vis',
    AppLanguage.english: 'Screws',
  },
  'التجميع': {
    AppLanguage.arabic: 'التجميع',
    AppLanguage.french: 'Assemblage',
    AppLanguage.english: 'Assembly',
  },
  'تجميع الصندوق': {
    AppLanguage.arabic: 'تجميع الصندوق',
    AppLanguage.french: 'Assemblage du coffre',
    AppLanguage.english: 'Box assembly',
  },
  'التثبيت': {
    AppLanguage.arabic: 'التثبيت',
    AppLanguage.french: 'Fixation',
    AppLanguage.english: 'Fixing',
  },
  'كيت الستار': {
    AppLanguage.arabic: 'كيت الستار',
    AppLanguage.french: 'Kit de volet',
    AppLanguage.english: 'Shutter kit',
  },
  'إضافة أكسسوار جديد': {
    AppLanguage.arabic: 'إضافة أكسسوار جديد',
    AppLanguage.french: 'Ajouter un nouvel accessoire',
    AppLanguage.english: 'Add New Accessory',
  },
  'اسم الأكسسوار (مثال: مقبض إيطالي)': {
    AppLanguage.arabic: 'اسم الأكسسوار (مثال: مقبض إيطالي)',
    AppLanguage.french: "Nom de l'accessoire (ex: Poignée italienne)",
    AppLanguage.english: 'Accessory Name (e.g. Italian handle)',
  },
  'سعر شراء الحزمة': {
    AppLanguage.arabic: 'سعر شراء الحزمة',
    AppLanguage.french: "Prix d'achat du pack",
    AppLanguage.english: 'Pack purchase price',
  },
  'الكمية في الحزمة': {
    AppLanguage.arabic: 'الكمية في الحزمة',
    AppLanguage.french: 'Quantité dans le pack',
    AppLanguage.english: 'Pack quantity',
  },
  'سعر شراء القطعة': {
    AppLanguage.arabic: 'سعر شراء القطعة',
    AppLanguage.french: "Prix d'achat unitaire",
    AppLanguage.english: 'Unit purchase price',
  },
  'سعر بيع القطعة': {
    AppLanguage.arabic: 'سعر بيع القطعة',
    AppLanguage.french: 'Prix de vente unitaire',
    AppLanguage.english: 'Unit selling price',
  },

  'مقابض (Poignées)': {
    AppLanguage.arabic: 'مقابض (Poignées)',
    AppLanguage.french: 'Poignées',
    AppLanguage.english: 'Handles',
  },
  'مفاصل (Paumelles)': {
    AppLanguage.arabic: 'مفاصل (Paumelles)',
    AppLanguage.french: 'Paumelles / Charnières',
    AppLanguage.english: 'Hinges',
  },
  'أقفال (Serrures)': {
    AppLanguage.arabic: 'أقفال (Serrures)',
    AppLanguage.french: 'Serrures',
    AppLanguage.english: 'Locks',
  },
  'عجلات (Roulettes)': {
    AppLanguage.arabic: 'عجلات (Roulettes)',
    AppLanguage.french: 'Roulettes',
    AppLanguage.english: 'Wheels / Rollers',
  },
  'إكسسوارات أخرى (Divers)': {
    AppLanguage.arabic: 'إكسسوارات أخرى (Divers)',
    AppLanguage.french: 'Divers',
    AppLanguage.english: 'Others',
  },

  'الاستخدامات:': {
    AppLanguage.arabic: 'الاستخدامات:',
    AppLanguage.french: 'Usages :',
    AppLanguage.english: 'Usages:',
  },
  'عدد البراغي للإكسسوار:': {
    AppLanguage.arabic: 'عدد البراغي للإكسسوار:',
    AppLanguage.french: "Nombre de vis pour l'accessoire :",
    AppLanguage.english: 'Number of screws for accessory:',
  },

  'بوشون باتمو': {
    AppLanguage.arabic: 'بوشون باتمو',
    AppLanguage.french: 'Bouchon Battelement',
    AppLanguage.english: 'Battelement Cap',
  },
  'المحرك': {
    AppLanguage.arabic: 'المحرك',
    AppLanguage.french: 'Moteur',
    AppLanguage.english: 'Motor',
  },
  'المانيفيل': {
    AppLanguage.arabic: 'المانيفيل',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank / Manivelle',
  },

  // --- Price Management Screen ---
  'أسعار المقاطع': {
    AppLanguage.arabic: 'أسعار المقاطع',
    AppLanguage.french: 'Prix des Profils',
    AppLanguage.english: 'Profile Prices',
  },
  'ألوان الأنظمة': {
    AppLanguage.arabic: 'ألوان الأنظمة',
    AppLanguage.french: 'Couleurs des Systèmes',
    AppLanguage.english: 'System Colors',
  },
  'حدود الصناديق (Caissons)': {
    AppLanguage.arabic: 'حدود الصناديق (Caissons)',
    AppLanguage.french: 'Limites des Caissons',
    AppLanguage.english: 'Shutter Box Limits',
  },
  'الصندوق:': {
    AppLanguage.arabic: 'الصندوق:',
    AppLanguage.french: 'Caisson :',
    AppLanguage.english: 'Shutter Box:',
  },
  'أقصى ارتفاع:': {
    AppLanguage.arabic: 'أقصى ارتفاع:',
    AppLanguage.french: 'Hauteur max :',
    AppLanguage.english: 'Max Height:',
  },
  'أقصى ارتفاع يحتمله الصندوق (ملم)': {
    AppLanguage.arabic: 'أقصى ارتفاع يحتمله الصندوق (ملم)',
    AppLanguage.french: 'Hauteur maximale du caisson (mm)',
    AppLanguage.english: 'Maximum box height (mm)',
  },

  // --- Order Editing Screen (add_commande) ---
  'Faux Bois Marron': {
    AppLanguage.arabic: 'خشبي بني (Faux Bois Marron)',
    AppLanguage.french: 'Faux Bois Marron',
    AppLanguage.english: 'Brown Wood (Faux Bois Marron)',
  },
  'خشبي بني (Faux Bois Marron)': {
    AppLanguage.arabic: 'خشبي بني (Faux Bois Marron)',
    AppLanguage.french: 'Faux Bois Marron',
    AppLanguage.english: 'Brown Wood (Faux Bois Marron)',
  },
  'خشبي بني': {
    AppLanguage.arabic: 'خشبي بني',
    AppLanguage.french: 'Faux Bois Marron',
    AppLanguage.english: 'Brown Wood',
  },
  'Faux bois marron clair': {
    AppLanguage.arabic: 'خشبي بني فاتح',
    AppLanguage.french: 'Faux bois marron clair',
    AppLanguage.english: 'Light brown wood grain',
  },
  'Faux Bois Marron Clair': {
    AppLanguage.arabic: 'خشبي بني فاتح',
    AppLanguage.french: 'Faux bois marron clair',
    AppLanguage.english: 'Light brown wood grain',
  },
  'خشبي بني فاتح': {
    AppLanguage.arabic: 'خشبي بني فاتح',
    AppLanguage.french: 'Faux bois marron clair',
    AppLanguage.english: 'Light brown wood grain',
  },
  'Light brown wood grain': {
    AppLanguage.arabic: 'خشبي بني فاتح',
    AppLanguage.french: 'Faux bois marron clair',
    AppLanguage.english: 'Light brown wood grain',
  },
  'بني فاتح (Faux Bois)': {
    AppLanguage.arabic: 'بني فاتح (Faux Bois)',
    AppLanguage.french: 'Marron clair (Faux Bois)',
    AppLanguage.english: 'Light Brown (Faux Bois)',
  },
  'بيج / FBM': {
    AppLanguage.arabic: 'بيج / FBM',
    AppLanguage.french: 'Beige / FBM',
    AppLanguage.english: 'Beige / FBM',
  },
  'نافذة بضلفة واحدة': {
    AppLanguage.arabic: 'نافذة بضلفة واحدة',
    AppLanguage.french: 'Fenêtre simple ouvrant',
    AppLanguage.english: 'Single Sash Window',
  },
  'نافذة بضلفتين': {
    AppLanguage.arabic: 'نافذة بضلفتين',
    AppLanguage.french: 'Fenêtre double ouvrant',
    AppLanguage.english: 'Double Sash Window',
  },
  'باب بضلفة واحدة': {
    AppLanguage.arabic: 'باب بضلفة واحدة',
    AppLanguage.french: 'Porte simple sash',
    AppLanguage.english: 'Single Sash Door',
  },
  'باب بضلفتين': {
    AppLanguage.arabic: 'باب بضلفتين',
    AppLanguage.french: 'Porte double sash',
    AppLanguage.english: 'Double Sash Door',
  },
  'اللون:': {
    AppLanguage.arabic: 'اللون:',
    AppLanguage.french: 'Couleur :',
    AppLanguage.english: 'Color:',
  },
  'المجموع:': {
    AppLanguage.arabic: 'المجموع:',
    AppLanguage.french: 'Total :',
    AppLanguage.english: 'Total:',
  },
  'السعر:': {
    AppLanguage.arabic: 'السعر:',
    AppLanguage.french: 'Prix :',
    AppLanguage.english: 'Price:',
  },
  'الزجاج:': {
    AppLanguage.arabic: 'الزجاج:',
    AppLanguage.french: 'Vitrage :',
    AppLanguage.english: 'Glass:',
  },
  'مجموع الكميات :': {
    AppLanguage.arabic: 'مجموع الكميات :',
    AppLanguage.french: 'Quantité totale :',
    AppLanguage.english: 'Total Quantity:',
  },
  'المنطقة المحددة': {
    AppLanguage.arabic: 'المنطقة المحددة',
    AppLanguage.french: 'Zone sélectionnée',
    AppLanguage.english: 'Selected zone',
  },
  'شائع': {
    AppLanguage.arabic: 'شائع',
    AppLanguage.french: 'Commun',
    AppLanguage.english: 'Common',
  },
  'ورقة': {
    AppLanguage.arabic: 'ورقة',
    AppLanguage.french: 'Ouvrant',
    AppLanguage.english: 'Sash',
  },
  'عامود': {
    AppLanguage.arabic: 'عامود',
    AppLanguage.french: 'Meneau',
    AppLanguage.english: 'Mullion',
  },
  'زجاج / حشوات': {
    AppLanguage.arabic: 'زجاج / حشوات',
    AppLanguage.french: 'Vitrage / Remplissage',
    AppLanguage.english: 'Glass / Fillings',
  },
  'الشفرات': {
    AppLanguage.arabic: 'الشفرات',
    AppLanguage.french: 'Lames',
    AppLanguage.english: 'Slats',
  },
  'السكك': {
    AppLanguage.arabic: 'السكك',
    AppLanguage.french: 'Coulisses',
    AppLanguage.english: 'Tracks',
  },
  'تقسيم أفقي': {
    AppLanguage.arabic: 'تقسيم أفقي',
    AppLanguage.french: 'Division horizontale',
    AppLanguage.english: 'Horizontal division',
  },
  'تقسيم عمودي': {
    AppLanguage.arabic: 'تقسيم عمودي',
    AppLanguage.french: 'Division verticale',
    AppLanguage.english: 'Vertical division',
  },
  'إعادة التكبير': {
    AppLanguage.arabic: 'إعادة التكبير',
    AppLanguage.french: 'Réinitialiser zoom',
    AppLanguage.english: 'Reset zoom',
  },
  'زجاج ثابت': {
    AppLanguage.arabic: 'زجاج ثابت',
    AppLanguage.french: 'Vitrage fixe',
    AppLanguage.english: 'Fixed glass',
  },
  'مشاهدة: وجه داخلي': {
    AppLanguage.arabic: 'مشاهدة: وجه داخلي',
    AppLanguage.french: 'Vue : Face interne',
    AppLanguage.english: 'View: Inner face',
  },
  'مشاهدة: وجه خارجي': {
    AppLanguage.arabic: 'مشاهدة: وجه خارجي',
    AppLanguage.french: 'Vue : Face externe',
    AppLanguage.english: 'View: Outer face',
  },
  'جرد المخزون': {
    AppLanguage.arabic: 'جرد المخزون',
    AppLanguage.french: 'Inventaire',
    AppLanguage.english: 'Inventory',
  },
  'لا توجد أسعار معدّلة بانتظار الحفظ.': {
    AppLanguage.arabic: 'لا توجد أسعار معدّلة بانتظار الحفظ.',
    AppLanguage.french: 'Aucun prix modifié en attente d’enregistrement.',
    AppLanguage.english: 'No modified prices are waiting to be saved.',
  },
  'زبون جديد': {
    AppLanguage.arabic: 'زبون جديد',
    AppLanguage.french: 'Nouveau client',
    AppLanguage.english: 'New client',
  },
  'أسعار جاهزة للحفظ.': {
    AppLanguage.arabic: 'أسعار جاهزة للحفظ.',
    AppLanguage.french: 'prix prêts à être enregistrés.',
    AppLanguage.english: 'prices ready to be saved.',
  },
  'رمادي (السعر الأساسي)': {
    AppLanguage.arabic: 'رمادي (السعر الأساسي)',
    AppLanguage.french: 'Gris (prix de base)',
    AppLanguage.english: 'Grey (base price)',
  },
  'إظهار المقابض والمفاصل والتجاويف': {
    AppLanguage.arabic: 'إظهار المقابض والمفاصل والتجاويف',
    AppLanguage.french: 'Afficher poignées, paumelles et cavités',
    AppLanguage.english: 'Show handles, hinges and cavities',
  },
  'إظهار المقابض والمفاصل والتجاويف في الوجه الخارجي': {
    AppLanguage.arabic: 'إظهار المقابض والمفاصل والتجاويف في الوجه الخارجي',
    AppLanguage.french:
        'Afficher poignées, paumelles et cavités sur la face externe',
    AppLanguage.english: 'Show handles, hinges and cavities on the outer face',
  },
  'empty': {
    AppLanguage.arabic: 'فارغة',
    AppLanguage.french: 'Vide',
    AppLanguage.english: 'Empty',
  },
  'fixedGlass': {
    AppLanguage.arabic: 'زجاج ثابت',
    AppLanguage.french: 'Vitrage fixe',
    AppLanguage.english: 'Fixed glass',
  },
  'singleSash': {
    AppLanguage.arabic: 'ضلفة واحدة',
    AppLanguage.french: 'Un seul ouvrant',
    AppLanguage.english: 'Single sash',
  },
  'doubleSash': {
    AppLanguage.arabic: 'ضلفتان',
    AppLanguage.french: 'Double ouvrant',
    AppLanguage.english: 'Double sash',
  },
  'slidingSash': {
    AppLanguage.arabic: 'منزلق',
    AppLanguage.french: 'Coulissant',
    AppLanguage.english: 'Sliding',
  },
  'منزلق 2': {
    AppLanguage.arabic: 'منزلق 2',
    AppLanguage.french: 'Coulissant 2',
    AppLanguage.english: 'Sliding 2',
  },
  'منزلق 3': {
    AppLanguage.arabic: 'منزلق 3',
    AppLanguage.french: 'Coulissant 3',
    AppLanguage.english: 'Sliding 3',
  },
  'منزلق 4': {
    AppLanguage.arabic: 'منزلق 4',
    AppLanguage.french: 'Coulissant 4',
    AppLanguage.english: 'Sliding 4',
  },
  'حذف بلانت الضلفة': {
    AppLanguage.arabic: 'حذف بلانت الضلفة',
    AppLanguage.french: 'Supprimer la plinthe de l\'ouvrant',
    AppLanguage.english: 'Remove sash plinthe',
  },
  'إضافة بلانت للضلفة': {
    AppLanguage.arabic: 'إضافة بلانت للضلفة',
    AppLanguage.french: 'Ajouter une plinthe à l\'ouvrant',
    AppLanguage.english: 'Add sash plinthe',
  },
  'استخدام بلانت بالأسفل (للإطار)': {
    AppLanguage.arabic: 'استخدام بلانت بالأسفل (للإطار)',
    AppLanguage.french: 'Utiliser la plinthe en bas (pour le cadre)',
    AppLanguage.english: 'Use plinthe at the bottom (for frame)',
  },
  'تغيير حالة الطلبية': {
    AppLanguage.arabic: 'تغيير حالة الطلبية',
    AppLanguage.french: 'Modifier le statut de la commande',
    AppLanguage.english: 'Change order status',
  },
  'إضافة ظرفين داخليتين': {
    AppLanguage.arabic: 'إضافة ظرفين داخليتين',
    AppLanguage.french: 'Ajouter deux ouvrants intérieurs',
    AppLanguage.english: 'Add double internal sashes',
  },
  'إضافة بلانت للظرف': {
    AppLanguage.arabic: 'إضافة بلانت للظرف',
    AppLanguage.french: 'Ajouter une plinthe à l\'ouvrant',
    AppLanguage.english: 'Add sash plinthe',
  },
  'إضافة ظرف': {
    AppLanguage.arabic: 'إضافة ظرف',
    AppLanguage.french: 'Ajouter un ouvrant',
    AppLanguage.english: 'Add sash',
  },
  'ظرف داخلية': {
    AppLanguage.arabic: 'ظرف داخلية',
    AppLanguage.french: 'Ouvrant intérieur',
    AppLanguage.english: 'Internal sash',
  },
  'قفل حمام': {
    AppLanguage.arabic: 'قفل حمام',
    AppLanguage.french: 'Verrou de salle de bain',
    AppLanguage.english: 'Bathroom lock',
  },
  'قفل نقطة': {
    AppLanguage.arabic: 'قفل نقطة (Point)',
    AppLanguage.french: 'Serrure à point',
    AppLanguage.english: 'Point lock',
  },
  'أوكتو': {
    AppLanguage.arabic: 'أوكتو',
    AppLanguage.french: 'Octo',
    AppLanguage.english: 'Octo',
  },
  'إضافة قفل / أوكتو': {
    AppLanguage.arabic: 'إضافة قفل / أوكتو',
    AppLanguage.french: 'Ajouter serrure / Octo',
    AppLanguage.english: 'Add lock / Octo',
  },
  'قفل بمفتاح ✓': {
    AppLanguage.arabic: 'قفل بمفتاح ✓',
    AppLanguage.french: 'Serrure à clé ✓',
    AppLanguage.english: 'Key lock ✓',
  },
  'قفل حمام ✓': {
    AppLanguage.arabic: 'قفل حمام ✓',
    AppLanguage.french: 'Verrou condamnation ✓',
    AppLanguage.english: 'Bathroom lock ✓',
  },
  'قفل نقطة ✓': {
    AppLanguage.arabic: 'قفل نقطة (Point) ✓',
    AppLanguage.french: 'Serrure à point ✓',
    AppLanguage.english: 'Point lock ✓',
  },
  'أوكتو ✓': {
    AppLanguage.arabic: 'أوكتو ✓',
    AppLanguage.french: 'Octo ✓',
    AppLanguage.english: 'Octo ✓',
  },
  'الطلبيات': {
    AppLanguage.arabic: 'الطلبيات',
    AppLanguage.french: 'Commandes',
    AppLanguage.english: 'Orders',
  },
  'آخر 6 أشهر: {count} طلبية': {
    AppLanguage.arabic: 'آخر 6 أشهر: {count} طلبية',
    AppLanguage.french: 'Derniers 6 mois : {count} commandes',
    AppLanguage.english: 'Last 6 months: {count} orders',
  },
  'يناير': {
    AppLanguage.arabic: 'يناير',
    AppLanguage.french: 'Janvier',
    AppLanguage.english: 'January',
  },
  'فبراير': {
    AppLanguage.arabic: 'فبراير',
    AppLanguage.french: 'Février',
    AppLanguage.english: 'February',
  },
  'مارس': {
    AppLanguage.arabic: 'مارس',
    AppLanguage.french: 'Mars',
    AppLanguage.english: 'March',
  },
  'أبريل': {
    AppLanguage.arabic: 'أبريل',
    AppLanguage.french: 'Avril',
    AppLanguage.english: 'April',
  },
  'مايو': {
    AppLanguage.arabic: 'مايو',
    AppLanguage.french: 'Mai',
    AppLanguage.english: 'May',
  },
  'يونيو': {
    AppLanguage.arabic: 'يونيو',
    AppLanguage.french: 'Juin',
    AppLanguage.english: 'June',
  },
  'يوليو': {
    AppLanguage.arabic: 'يوليو',
    AppLanguage.french: 'Juillet',
    AppLanguage.english: 'July',
  },
  'أغسطس': {
    AppLanguage.arabic: 'أغسطس',
    AppLanguage.french: 'Août',
    AppLanguage.english: 'August',
  },
  'سبتمبر': {
    AppLanguage.arabic: 'سبتمبر',
    AppLanguage.french: 'Septembre',
    AppLanguage.english: 'September',
  },
  'أكتوبر': {
    AppLanguage.arabic: 'أكتوبر',
    AppLanguage.french: 'Octobre',
    AppLanguage.english: 'October',
  },
  'نوفمبر': {
    AppLanguage.arabic: 'نوفمبر',
    AppLanguage.french: 'Novembre',
    AppLanguage.english: 'November',
  },
  'ديسمبر': {
    AppLanguage.arabic: 'ديسمبر',
    AppLanguage.french: 'Décembre',
    AppLanguage.english: 'December',
  },

  'تغيير الحالة المخصص': {
    AppLanguage.arabic: 'تغيير الحالة المخصص',
    AppLanguage.french: 'Modifier le statut personnalisé',
    AppLanguage.english: 'Change Custom Status',
  },
  'تكرار الطلبية (Duplicate)': {
    AppLanguage.arabic: 'تكرار الطلبية (Duplicate)',
    AppLanguage.french: 'Dupliquer la commande',
    AppLanguage.english: 'Duplicate Order',
  },
  'تم تكرار الطلبية بنجاح!': {
    AppLanguage.arabic: 'تم تكرار الطلبية بنجاح!',
    AppLanguage.french: 'Commande dupliquée avec succès !',
    AppLanguage.english: 'Order duplicated successfully!',
  },
  'حدث خطأ أثناء التكرار:': {
    AppLanguage.arabic: 'حدث خطأ أثناء التكرار:',
    AppLanguage.french: 'Une erreur est survenue lors de la duplication :',
    AppLanguage.english: 'An error occurred during duplication:',
  },
  'مسح الطلبية (Supprimer)': {
    AppLanguage.arabic: 'مسح الطلبية',
    AppLanguage.french: 'Supprimer la commande',
    AppLanguage.english: 'Delete Order',
  },
  'تم تأكيد الطلبية بنجاح!': {
    AppLanguage.arabic: 'تم تأكيد الطلبية بنجاح!',
    AppLanguage.french: 'Commande confirmée avec succès !',
    AppLanguage.english: 'Order confirmed successfully!',
  },

  'الخصائص العامة': {
    AppLanguage.arabic: 'الخصائص العامة',
    AppLanguage.french: 'Propriétés Générales',
    AppLanguage.english: 'General Properties',
  },
  'لون الإكسسوارات': {
    AppLanguage.arabic: 'لون الإكسسوارات',
    AppLanguage.french: 'Couleur des accessoires',
    AppLanguage.english: 'Accessory Color',
  },
  'لون الإكسسوارات (افتراضي)': {
    AppLanguage.arabic: 'لون الإكسسوارات (افتراضي)',
    AppLanguage.french: 'Couleur des accessoires (Par défaut)',
    AppLanguage.english: 'Accessory Color (Default)',
  },
  'رسم الجدار': {
    AppLanguage.arabic: 'رسم الجدار',
    AppLanguage.french: 'Tracé du mur',
    AppLanguage.english: 'Wall Drawing',
  },
  'اختر الغطاء الجانبي': {
    AppLanguage.arabic: 'اختر الغطاء الجانبي',
    AppLanguage.french: 'Choisir l\'covre joint',
    AppLanguage.english: 'Choose Side Cap',
  },

  'لون الألمنيوم': {
    AppLanguage.arabic: 'لون الألمنيوم',
    AppLanguage.french: 'Couleur aluminium',
    AppLanguage.english: 'Aluminium color',
  },
  'لون الإكسسوارات:': {
    AppLanguage.arabic: 'لون الإكسسوارات:',
    AppLanguage.french: 'Couleur accessoires :',
    AppLanguage.english: 'Accessory color:',
  },
  'ستار (Volet)': {
    AppLanguage.arabic: 'ستار (Volet)',
    AppLanguage.french: 'Volet',
    AppLanguage.english: 'Shutter',
  },
  'الستار (Volet)': {
    AppLanguage.arabic: 'الستار (Volet)',
    AppLanguage.french: 'Volet',
    AppLanguage.english: 'Shutter',
  },
  'صندوق نفق (Coffre Tunnel)': {
    AppLanguage.arabic: 'صندوق نفق (Coffre Tunnel)',
    AppLanguage.french: 'Coffre Tunnel',
    AppLanguage.english: 'Tunnel Box',
  },
  'صندوق النفق (Caisson tunnel)': {
    AppLanguage.arabic: 'صندوق النفق (Caisson tunnel)',
    AppLanguage.french: 'Caisson tunnel',
    AppLanguage.english: 'Tunnel box',
  },
  'صندوق نفق (Caisson tunnel)': {
    AppLanguage.arabic: 'صندوق نفق (Caisson tunnel)',
    AppLanguage.french: 'Caisson tunnel',
    AppLanguage.english: 'Tunnel box',
  },
  'صندوق النفق': {
    AppLanguage.arabic: 'صندوق النفق',
    AppLanguage.french: 'Caisson tunnel',
    AppLanguage.english: 'Tunnel box',
  },
  'صندوق نفق': {
    AppLanguage.arabic: 'صندوق نفق',
    AppLanguage.french: 'Caisson tunnel',
    AppLanguage.english: 'Tunnel box',
  },
  'الستار غير مدعوم للأشكال المقوسة أو المائلة': {
    AppLanguage.arabic: 'الستار غير مدعوم للأشكال المقوسة أو المائلة',
    AppLanguage.french:
        'Volet non supporté pour les formes arquées ou inclinées',
    AppLanguage.english: 'Shutter not supported for arched or slanted shapes',
  },
  'تدعيم المونطو (Renfort)': {
    AppLanguage.arabic: 'تدعيم المونطو (Renfort)',
    AppLanguage.french: 'Renfort montant',
    AppLanguage.english: 'Montant reinforcement',
  },
  'الجانبي (Latéral):': {
    AppLanguage.arabic: 'الجانبي (Latéral):',
    AppLanguage.french: 'Latéral :',
    AppLanguage.english: 'Lateral:',
  },
  'طرفية يسرى': {
    AppLanguage.arabic: 'الطرفية اليسرى',
    AppLanguage.french: 'Extrême gauche',
    AppLanguage.english: 'Outer left',
  },
  'طرفية يمنى': {
    AppLanguage.arabic: 'الطرفية اليمنى',
    AppLanguage.french: 'Extrême droite',
    AppLanguage.english: 'Outer right',
  },
  'وسطى يسار': {
    AppLanguage.arabic: 'الوسطى اليسرى',
    AppLanguage.french: 'Intermédiaire gauche',
    AppLanguage.english: 'Inner left',
  },
  'وسطى يمين': {
    AppLanguage.arabic: 'الوسطى اليمنى',
    AppLanguage.french: 'Intermédiaire droite',
    AppLanguage.english: 'Inner right',
  },
  'المركزي (Central):': {
    AppLanguage.arabic: 'المركزي (Central):',
    AppLanguage.french: 'Central :',
    AppLanguage.english: 'Central:',
  },
  'مركز': {
    AppLanguage.arabic: 'مركز',
    AppLanguage.french: 'Centre',
    AppLanguage.english: 'Center',
  },
  'هذه السلسلة لا تدعم تدعيم المونطو': {
    AppLanguage.arabic: 'هذه السلسلة لا تدعم تدعيم المونطو',
    AppLanguage.french: 'Cette série ne supporte pas le renfort montant',
    AppLanguage.english: 'This series does not support montant reinforcement',
  },
  'البروفيل:': {
    AppLanguage.arabic: 'القطاع:',
    AppLanguage.french: 'Profil :',
    AppLanguage.english: 'Profile:',
  },
  'هذه السلسلة لا تدعم مونتوسليم': {
    AppLanguage.arabic: 'هذه السلسلة لا تدعم القائم الوسطي النحيف',
    AppLanguage.french: 'Cette série ne prend pas en charge le Montant Slim.',
    AppLanguage.english: 'This series does not support the Slim Montant.',
  },
  'سيستم او بي (System OB)': {
    AppLanguage.arabic: 'سيستم او بي (System OB)',
    AppLanguage.french: 'Système OB',
    AppLanguage.english: 'System OB',
  },
  'ديمي او بي (Demi OB)': {
    AppLanguage.arabic: 'ديمي او بي (Demi OB)',
    AppLanguage.french: 'Demi Système OB',
    AppLanguage.english: 'Demi System OB',
  },
  'فيرو سونترال (Verrou Central)': {
    AppLanguage.arabic: 'فيرو سونترال (Verrou Central)',
    AppLanguage.french: 'Verrou central',
    AppLanguage.english: 'Central lock',
  },
  'ارتفاع Caisson Tunnel (Hauteur Tunnel):': {
    AppLanguage.arabic: 'ارتفاع Caisson Tunnel (Hauteur Tunnel):',
    AppLanguage.french: 'Hauteur coffre tunnel :',
    AppLanguage.english: 'Tunnel box height:',
  },
  'وضع الستار (Position):': {
    AppLanguage.arabic: 'وضع الستار (Position):',
    AppLanguage.french: 'Position du volet :',
    AppLanguage.english: 'Shutter position:',
  },
  'تنبيهات المخزون': {
    AppLanguage.arabic: 'تنبيهات المخزون',
    AppLanguage.french: 'Alertes de stock',
    AppLanguage.english: 'Stock alerts',
  },
  'كل الكميات متوفرة بشكل جيد ولا توجد نواقص!': {
    AppLanguage.arabic: 'كل الكميات متوفرة بشكل جيد ولا توجد نواقص!',
    AppLanguage.french:
        'Toutes les quantités sont bien disponibles et il n\'y a pas de pénurie !',
    AppLanguage.english:
        'All quantities are well available and there are no shortages!',
  },
  'العناصر التالية وصلت للحد الأدنى أو نفذت من المخزون، يرجى إعادة طلبها قريباً:': {
    AppLanguage.arabic:
        'العناصر التالية وصلت للحد الأدنى أو نفذت من المخزون، يرجى إعادة طلبها قريباً:',
    AppLanguage.french:
        'Les articles suivants ont atteint la limite minimale ou sont en rupture de stock, veuillez les réapprovisionner bientôt :',
    AppLanguage.english:
        'The following items have reached the minimum limit or are out of stock, please reorder them soon:',
  },
  'إجمالي كل المبيعات المؤكدة': {
    AppLanguage.arabic: 'إجمالي كل المبيعات المؤكدة',
    AppLanguage.french: 'Total de toutes les ventes confirmées',
    AppLanguage.english: 'Total of all confirmed sales',
  },
  'إجمالي الطلبيات المؤكدة': {
    AppLanguage.arabic: 'إجمالي الطلبيات المؤكدة',
    AppLanguage.french: 'Total des commandes confirmées',
    AppLanguage.english: 'Total of confirmed orders',
  },
  'إجمالي الطلبيات المصنعة': {
    AppLanguage.arabic: 'إجمالي الطلبيات المصنعة',
    AppLanguage.french: 'Total des commandes fabriquées',
    AppLanguage.english: 'Total of manufactured orders',
  },
  'إجمالي الطلبيات المركبة': {
    AppLanguage.arabic: 'إجمالي الطلبيات المركبة',
    AppLanguage.french: 'Total des commandes installées',
    AppLanguage.english: 'Total of installed orders',
  },
  'إجمالي المبيعات الجزئية المسلمة': {
    AppLanguage.arabic: 'إجمالي المبيعات الجزئية المسلمة',
    AppLanguage.french: 'Total des ventes partielles livrées',
    AppLanguage.english: 'Total of partial sales delivered',
  },
  'إجمالي المبيعات': {
    AppLanguage.arabic: 'إجمالي المبيعات',
    AppLanguage.french: 'Total des ventes',
    AppLanguage.english: 'Total Sales',
  },
  'المؤكدة': {
    AppLanguage.arabic: 'المؤكدة',
    AppLanguage.french: 'Confirmée',
    AppLanguage.english: 'Confirmed',
  },
  'المصنعة': {
    AppLanguage.arabic: 'المصنعة',
    AppLanguage.french: 'Fabriquée',
    AppLanguage.english: 'Manufactured',
  },
  'المركبة': {
    AppLanguage.arabic: 'المركبة',
    AppLanguage.french: 'Installée',
    AppLanguage.english: 'Installed',
  },
  'المبيعات الجزئية': {
    AppLanguage.arabic: 'المبيعات الجزئية',
    AppLanguage.french: 'Ventes partielles',
    AppLanguage.english: 'Partial Sales',
  },
  'لا توجد طلبيات مطابقة لهذا التصنيف.': {
    AppLanguage.arabic: 'لا توجد طلبيات مطابقة لهذا التصنيف.',
    AppLanguage.french: 'Aucune commande ne correspond à cette catégorie.',
    AppLanguage.english: 'No orders match this category.',
  },
  'لا توجد فواتير تسليم جزئية مسجلة حالياً.': {
    AppLanguage.arabic: 'لا توجد فواتير تسليم جزئية مسجلة حالياً.',
    AppLanguage.french:
        'Aucune facture de livraison partielle n\'est enregistrée actuellement.',
    AppLanguage.english:
        'No partial delivery invoices are currently registered.',
  },
  'طلب': {
    AppLanguage.arabic: 'طلب',
    AppLanguage.french: 'Commande',
    AppLanguage.english: 'Order',
  },
  'زبون غير معروف': {
    AppLanguage.arabic: 'زبون غير معروف',
    AppLanguage.french: 'Client inconnu',
    AppLanguage.english: 'Unknown Customer',
  },
  'قيمة الطلب': {
    AppLanguage.arabic: 'قيمة الطلب',
    AppLanguage.french: 'Valeur de la commande',
    AppLanguage.english: 'Order Value',
  },
  'مجموع المسلّم': {
    AppLanguage.arabic: 'مجموع المسلّم',
    AppLanguage.french: 'Total livré',
    AppLanguage.english: 'Total Delivered',
  },
  'مكتملة بالكامل': {
    AppLanguage.arabic: 'مكتملة بالكامل',
    AppLanguage.french: 'Entièrement complétée',
    AppLanguage.english: 'Fully Completed',
  },
  'غير جاهزة كلياً (جزئية)': {
    AppLanguage.arabic: 'غير جاهزة كلياً (جزئية)',
    AppLanguage.french: 'Non entièrement prête (Partielle)',
    AppLanguage.english: 'Not fully ready (Partial)',
  },
  'تاريخ التسليم': {
    AppLanguage.arabic: 'تاريخ التسليم',
    AppLanguage.french: 'Date de livraison',
    AppLanguage.english: 'Delivery Date',
  },
  'القطع': {
    AppLanguage.arabic: 'القطع',
    AppLanguage.french: 'Pièces',
    AppLanguage.english: 'Pieces',
  },
  'التاريخ': {
    AppLanguage.arabic: 'التاريخ',
    AppLanguage.french: 'Date',
    AppLanguage.english: 'Date',
  },
  'سعر التكلفة': {
    AppLanguage.arabic: 'سعر التكلفة',
    AppLanguage.french: 'Coût de revient',
    AppLanguage.english: 'Cost Price',
  },
  'سعر التكلفة:': {
    AppLanguage.arabic: 'سعر التكلفة:',
    AppLanguage.french: 'Coût de revient :',
    AppLanguage.english: 'Cost Price:',
  },
  'السعر الإجمالي': {
    AppLanguage.arabic: 'السعر الإجمالي',
    AppLanguage.french: 'Prix total',
    AppLanguage.english: 'Total Price',
  },
  'السعر الإجمالي:': {
    AppLanguage.arabic: 'السعر الإجمالي:',
    AppLanguage.french: 'Prix total :',
    AppLanguage.english: 'Total Price:',
  },
  'السعر للمتر الخطي': {
    AppLanguage.arabic: 'السعر للمتر الخطي',
    AppLanguage.french: 'Prix par mètre linéaire',
    AppLanguage.english: 'Price per linear meter',
  },
  'السعر للمتر الخطي:': {
    AppLanguage.arabic: 'السعر للمتر الخطي:',
    AppLanguage.french: 'Prix par mètre linéaire :',
    AppLanguage.english: 'Price per linear meter:',
  },
  'تعديل يدوي': {
    AppLanguage.arabic: 'تعديل يدوي',
    AppLanguage.french: 'Modif. manuelle',
    AppLanguage.english: 'Manual Adjustment',
  },
  'تعديل يدوي:': {
    AppLanguage.arabic: 'تعديل يدوي:',
    AppLanguage.french: 'Modif. manuelle :',
    AppLanguage.english: 'Manual Adjustment:',
  },

  'القطعة الواحدة': {
    AppLanguage.arabic: 'القطعة الواحدة',
    AppLanguage.french: 'Pièce unique',
    AppLanguage.english: 'Single Piece',
  },
  'في الأعلى': {
    AppLanguage.arabic: 'في الأعلى',
    AppLanguage.french: 'En haut',
    AppLanguage.english: 'At the top',
  },
  'تفاصيل السعر': {
    AppLanguage.arabic: 'تفاصيل السعر',
    AppLanguage.french: 'Détails du prix',
    AppLanguage.english: 'Price Details',
  },
  'حفظ وإضافة الطلب': {
    AppLanguage.arabic: 'حفظ وإضافة الطلب',
    AppLanguage.french: 'Enregistrer et ajouter la commande',
    AppLanguage.english: 'Save and Add Order',
  },
  'إعدادات الأسعار': {
    AppLanguage.arabic: 'إعدادات الأسعار',
    AppLanguage.french: 'Paramètres des prix',
    AppLanguage.english: 'Price Settings',
  },

  'لا توجد سلاسل': {
    AppLanguage.arabic: 'لا توجد سلاسل',
    AppLanguage.french: 'Aucune série disponible',
    AppLanguage.english: 'No series available',
  },
  'ابحث عن إكسسوار...': {
    AppLanguage.arabic: 'ابحث عن إكسسوار...',
    AppLanguage.french: 'Rechercher un accessoire...',
    AppLanguage.english: 'Search accessory...',
  },
  'اختر بروفيلاً': {
    AppLanguage.arabic: 'اختر بروفيلاً',
    AppLanguage.french: 'Sélectionnez un profilé',
    AppLanguage.english: 'Select a Profile',
  },
  'حدد البروفيل من الشريط العلوي': {
    AppLanguage.arabic: 'حدد البروفيل من الشريط العلوي',
    AppLanguage.french: 'Sélectionnez le profilé dans la barre supérieure',
    AppLanguage.english: 'Select the profile from the top bar',
  },
  'لا توجد إكسسوارات': {
    AppLanguage.arabic: 'لا توجد إكسسوارات',
    AppLanguage.french: 'Aucun accessoire',
    AppLanguage.english: 'No accessories',
  },
  'لا توجد إكسسوارات مطابقة لنوع مادة هذا البروفيل': {
    AppLanguage.arabic: 'لا توجد إكسسوارات مطابقة لنوع مادة هذا البروفيل',
    AppLanguage.french:
        'Aucun accessoire ne correspond au type de matériau de ce profilé',
    AppLanguage.english: 'No accessories match this profile\'s material type',
  },
  'الإكسسوارات المرتبطة': {
    AppLanguage.arabic: 'الإكسسوارات المرتبطة',
    AppLanguage.french: 'Accessoires liés',
    AppLanguage.english: 'Linked Accessories',
  },
  'غير مرتبطة بهذه السلسلة': {
    AppLanguage.arabic: 'غير مرتبطة بهذه السلسلة',
    AppLanguage.french: 'Non liés à cette série',
    AppLanguage.english: 'Unlinked from this series',
  },
  'لا نتائج': {
    AppLanguage.arabic: 'لا نتائج',
    AppLanguage.french: 'Aucun résultat',
    AppLanguage.english: 'No results',
  },
  'جرّب كلمة بحث أخرى': {
    AppLanguage.arabic: 'جرّب كلمة بحث أخرى',
    AppLanguage.french: 'Essayez un autre mot-clé',
    AppLanguage.english: 'Try another keyword',
  },


  'الستار': {
    AppLanguage.arabic: 'الستار',
    AppLanguage.french: 'Volet Roulant',
    AppLanguage.english: 'Roller Shutter',
  },
  'الإطار (Frame)': {
    AppLanguage.arabic: 'الإطار (Frame)',
    AppLanguage.french: 'Dormant (Cadre)',
    AppLanguage.english: 'Frame',
  },
  'بلانت الإطار (Plinthe Frame)': {
    AppLanguage.arabic: 'بلانت الإطار (Plinthe Frame)',
    AppLanguage.french: 'Plinthe Dormant',
    AppLanguage.english: 'Frame Plinth',
  },
  'الظلفة (Sash)': {
    AppLanguage.arabic: 'الظلفة (Sash)',
    AppLanguage.french: 'Ouvrant (Vantail)',
    AppLanguage.english: 'Sash',
  },
  'بلانت الظلفة (Plinthe Sash)': {
    AppLanguage.arabic: 'بلانت الظلفة (Plinthe Sash)',
    AppLanguage.french: 'Plinthe Ouvrant',
    AppLanguage.english: 'Sash Plinth',
  },
  'الظلفة المنزلقة (Sliding Sash)': {
    AppLanguage.arabic: 'الظلفة المنزلقة (Sliding Sash)',
    AppLanguage.french: 'Vantail Coulissant',
    AppLanguage.english: 'Sliding Sash',
  },
  'سكة الظلفة (Sash Traverse)': {
    AppLanguage.arabic: 'سكة الظلفة (Sash Traverse)',
    AppLanguage.french: 'Traverse Vantail',
    AppLanguage.english: 'Sash Traverse',
  },
  'قائم جانبي (Sash Lateral)': {
    AppLanguage.arabic: 'قائم جانبي (Sash Lateral)',
    AppLanguage.french: 'Montant Latéral Vantail',
    AppLanguage.english: 'Sash Lateral Montant',
  },
  'قائم وسطي (Sash Central)': {
    AppLanguage.arabic: 'قائم وسطي (Sash Central)',
    AppLanguage.french: 'Montant Central Vantail',
    AppLanguage.english: 'Sash Central Montant',
  },
  'الشيكان (Chicane)': {
    AppLanguage.arabic: 'الشيكان (Chicane)',
    AppLanguage.french: 'Chicane',
    AppLanguage.english: 'Chicane',
  },
  'الري (Rail)': {
    AppLanguage.arabic: 'الري (Rail)',
    AppLanguage.french: 'Rail',
    AppLanguage.english: 'Rail',
  },
  'الحديد': {
    AppLanguage.arabic: 'الحديد',
    AppLanguage.french: 'Renfort Fer',
    AppLanguage.english: 'Steel Reinforcement',
  },
  'المنزلق للبي في سي': {
    AppLanguage.arabic: 'المنزلق للبي في سي',
    AppLanguage.french: 'Coulissant PVC',
    AppLanguage.english: 'PVC Sliding',
  },
  'تعديل سعر المتر': {
    AppLanguage.arabic: 'تعديل سعر المتر',
    AppLanguage.french: 'Modifier prix/mètre',
    AppLanguage.english: 'Edit Price/Meter',
  },
  'سعر بيع المتر': {
    AppLanguage.arabic: 'سعر بيع المتر',
    AppLanguage.french: 'Prix de vente/mètre',
    AppLanguage.english: 'Selling Price/Meter',
  },

  'فك': {
    AppLanguage.arabic: 'فك',
    AppLanguage.french: 'Détacher',
    AppLanguage.english: 'Unlink',
  },
  'ربط': {
    AppLanguage.arabic: 'ربط',
    AppLanguage.french: 'Lier',
    AppLanguage.english: 'Link',
  },
  'مرتبط': {
    AppLanguage.arabic: 'مرتبط',
    AppLanguage.french: 'Lié',
    AppLanguage.english: 'Linked',
  },
  'برغي': {
    AppLanguage.arabic: 'برغي',
    AppLanguage.french: 'Vis',
    AppLanguage.english: 'Screw',
  },
  'إكسسوار عام – يظهر في كل السلاسل تلقائياً': {
    AppLanguage.arabic: 'إكسسوار عام – يظهر في كل السلاسل تلقائياً',
    AppLanguage.french:
        'Accessoire global – s\'affiche dans toutes les séries par défaut',
    AppLanguage.english:
        'Global accessory – displayed in all series by default',
  },
  'تم فك ربط': {
    AppLanguage.arabic: 'تم فك ربط',
    AppLanguage.french: 'Détaché',
    AppLanguage.english: 'Unlinked',
  },
  'تم ربط': {
    AppLanguage.arabic: 'تم ربط',
    AppLanguage.french: 'Lié',
    AppLanguage.english: 'Linked',
  },
  'بهذه السلسلة': {
    AppLanguage.arabic: 'بهذه السلسلة',
    AppLanguage.french: 'à cette série',
    AppLanguage.english: 'to this series',
  },
  'Poignée Fenêtre': {
    AppLanguage.arabic: 'مقبض نافذة',
    AppLanguage.french: 'Poignée Fenêtre',
    AppLanguage.english: 'Window Handle',
  },
  'Poignée Porte à Clé': {
    AppLanguage.arabic: 'مقبض باب بمفتاح',
    AppLanguage.french: 'Poignée Porte à Clé',
    AppLanguage.english: 'Keyed Door Handle',
  },
  'Poignée Porte Condamnation': {
    AppLanguage.arabic: 'مقبض باب بدون مفتاح',
    AppLanguage.french: 'Poignée Porte Condamnation',
    AppLanguage.english: 'Privacy Door Handle',
  },
  'Verrou': {
    AppLanguage.arabic: 'قفل / مزلاج',
    AppLanguage.french: 'Verrou',
    AppLanguage.english: 'Bolt / Latch',
  },
  'Paumelles': {
    AppLanguage.arabic: 'مفصلات',
    AppLanguage.french: 'Paumelles',
    AppLanguage.english: 'Hinges',
  },
  'Espagnolette': {
    AppLanguage.arabic: 'إسبانيوليت',
    AppLanguage.french: 'Espagnolette',
    AppLanguage.english: 'Espagnolette',
  },
  'Gâche': {
    AppLanguage.arabic: 'مقابل القفل',
    AppLanguage.french: 'Gâche',
    AppLanguage.english: 'Strike Plate',
  },
  'Serrure': {
    AppLanguage.arabic: 'قفل',
    AppLanguage.french: 'Serrure',
    AppLanguage.english: 'Lock',
  },
  'Serrure Condamnation': {
    AppLanguage.arabic: 'قفل بدون مفتاح',
    AppLanguage.french: 'Serrure Condamnation',
    AppLanguage.english: 'Privacy Lock',
  },
  'Canon': {
    AppLanguage.arabic: 'سيلندر / قلب قفل',
    AppLanguage.french: 'Canon',
    AppLanguage.english: 'Cylinder',
  },
  'Canon Condamnation': {
    AppLanguage.arabic: 'سيلندر بدون مفتاح',
    AppLanguage.french: 'Canon Condamnation',
    AppLanguage.english: 'Privacy Cylinder',
  },
  'Tasso': {
    AppLanguage.arabic: 'طاسو',
    AppLanguage.french: 'Tasso',
    AppLanguage.english: 'Tasso',
  },
  'Visse': {
    AppLanguage.arabic: 'براغي',
    AppLanguage.french: 'Visse',
    AppLanguage.english: 'Screws',
  },
  'System OB': {
    AppLanguage.arabic: 'نظام OB',
    AppLanguage.french: 'Système OB',
    AppLanguage.english: 'Tilt & Turn System',
  },
  'Demi System OB': {
    AppLanguage.arabic: 'نصف نظام OB',
    AppLanguage.french: 'Demi Système OB',
    AppLanguage.english: 'Half Tilt & Turn System',
  },
  'Verrou Central': {
    AppLanguage.arabic: 'قفل مركزي',
    AppLanguage.french: 'Verrou Central',
    AppLanguage.english: 'Central Lock',
  },
  'Gâche simple': {
    AppLanguage.arabic: 'مقابل قفل بسيط',
    AppLanguage.french: 'Gâche simple',
    AppLanguage.english: 'Simple Strike Plate',
  },
  'Espagnolette Coulissante': {
    AppLanguage.arabic: 'إسبانيوليت منزلق',
    AppLanguage.french: 'Espagnolette Coulissante',
    AppLanguage.english: 'Sliding Espagnolette',
  },
  'Coulissant Ouvrant': {
    AppLanguage.arabic: 'منزلق مفصلي',
    AppLanguage.french: 'Coulissant Ouvrant',
    AppLanguage.english: 'Sliding Opening',
  },
  'Roulette': {
    AppLanguage.arabic: 'عجلات',
    AppLanguage.french: 'Roulette',
    AppLanguage.english: 'Rollers / Wheels',
  },
  'Gâche Porte': {
    AppLanguage.arabic: 'مقابل قفل الباب',
    AppLanguage.french: 'Gâche Porte',
    AppLanguage.english: 'Door Strike Plate',
  },
  'Gâche Coulissante': {
    AppLanguage.arabic: 'مقابل قفل منزلق',
    AppLanguage.french: 'Gâche Coulissante',
    AppLanguage.english: 'Sliding Strike Plate',
  },
  'Crémone': {
    AppLanguage.arabic: 'كريمو',
    AppLanguage.french: 'Crémone',
    AppLanguage.english: 'Cremone Bolt',
  },
  'Eclipse': {
    AppLanguage.arabic: 'إيكليبس',
    AppLanguage.french: 'Eclipse',
    AppLanguage.english: 'Eclipse',
  },
  'Bouchon Parclose': {
    AppLanguage.arabic: 'سدادة باركلوز',
    AppLanguage.french: 'Bouchon Parclose',
    AppLanguage.english: 'Glass Bead Plug',
  },
  'Clam': {
    AppLanguage.arabic: 'كلام تجميع',
    AppLanguage.french: 'Clam',
    AppLanguage.english: 'Corner Joint Clam',
  },
  'Intramatique': {
    AppLanguage.arabic: 'إنتراماتيك',
    AppLanguage.french: 'Intramatique',
    AppLanguage.english: 'Intramatique',
  },
  'Autre': {
    AppLanguage.arabic: 'أخرى',
    AppLanguage.french: 'Autre',
    AppLanguage.english: 'Other',
  },
  'octo': {
    AppLanguage.arabic: 'أوكتو',
    AppLanguage.french: 'octo',
    AppLanguage.english: 'octo',
  },
  'Logteau': {
    AppLanguage.arabic: 'لوجتو',
    AppLanguage.french: 'Logteau',
    AppLanguage.english: 'Logteau',
  },
  'Poignée TPR': {
    AppLanguage.arabic: 'مقبض TPR',
    AppLanguage.french: 'Poignée TPR',
    AppLanguage.english: 'TPR Handle',
  },
  'Poignée': {
    AppLanguage.arabic: 'مقبض',
    AppLanguage.french: 'Poignée',
    AppLanguage.english: 'Handle',
  },
  'Espagnolette TPR': {
    AppLanguage.arabic: 'إسبانيوليت TPR',
    AppLanguage.french: 'Espagnolette TPR',
    AppLanguage.english: 'TPR Espagnolette',
  },
  'Kit': {
    AppLanguage.arabic: 'كيت (مجموعة)',
    AppLanguage.french: 'Kit',
    AppLanguage.english: 'Kit',
  },
  'تحديد الموقع على الخريطة': {
    AppLanguage.arabic: 'تحديد الموقع على الخريطة',
    AppLanguage.french: 'Définir la position sur la carte',
    AppLanguage.english: 'Select location on map',
  },
  'تعديل الموقع على الخريطة': {
    AppLanguage.arabic: 'تعديل الموقع على الخريطة',
    AppLanguage.french: 'Modifier la position sur la carte',
    AppLanguage.english: 'Modify location on map',
  },
  'بحث عن مكان...': {
    AppLanguage.arabic: 'بحث عن مكان...',
    AppLanguage.french: 'Rechercher un lieu...',
    AppLanguage.english: 'Search for a place...',
  },
  'اضغط على أي مكان في الخريطة لتحديد الموقع بدقة، ثم اضغط على زر الصح بالأعلى للحفظ': {
    AppLanguage.arabic:
        'اضغط على أي مكان في الخريطة لتحديد الموقع بدقة، ثم اضغط على زر الصح بالأعلى للحفظ',
    AppLanguage.french:
        'Appuyez n\'importe où sur la carte pour définir l\'emplacement, puis appuyez sur la coche en haut pour enregistrer',
    AppLanguage.english:
        'Tap anywhere on the map to specify location, then press the check button on top to save',
  },
  'فتح الموقع في الخرائط': {
    AppLanguage.arabic: 'فتح الموقع في الخرائط',
    AppLanguage.french: 'Ouvrir l\'emplacement dans Maps',
    AppLanguage.english: 'Open location in Maps',
  },
  'حذف الموقع': {
    AppLanguage.arabic: 'حذف الموقع',
    AppLanguage.french: 'Supprimer l\'emplacement',
    AppLanguage.english: 'Delete location',
  },
  'بطاقة رفع القياسات': {
    AppLanguage.arabic: 'بطاقة رفع القياسات',
    AppLanguage.french: 'Fiche de métrage',
    AppLanguage.english: 'Measurement Sheet',
  },
  'إدخال القياسات السريع بالكتابة أو بالصوت': {
    AppLanguage.arabic: 'إدخال القياسات السريع بالكتابة أو بالصوت',
    AppLanguage.french: 'Saisie rapide par écrit ou par voix',
    AppLanguage.english: 'Quick entry by typing or voice',
  },
  'الخشب الفاتح': {
    AppLanguage.arabic: 'الخشب الفاتح',
    AppLanguage.french: 'Bois clair',
    AppLanguage.english: 'Light wood',
  },
  'سعر المتر المربع': {
    AppLanguage.arabic: 'سعر المتر المربع',
    AppLanguage.french: 'Prix au mètre carré',
    AppLanguage.english: 'Price per square meter',
  },
  'سعر المتر مربع': {
    AppLanguage.arabic: 'سعر المتر مربع',
    AppLanguage.french: 'Prix au mètre carré',
    AppLanguage.english: 'Price per square meter',
  },
  'سعر المتر المربع للستار': {
    AppLanguage.arabic: 'سعر المتر المربع للستار',
    AppLanguage.french: 'Prix du volet au mètre carré',
    AppLanguage.english: 'Shutter price per square meter',
  },
  'سعر المتر مربع للستار': {
    AppLanguage.arabic: 'سعر المتر مربع للستار',
    AppLanguage.french: 'Prix du volet au mètre carré',
    AppLanguage.english: 'Shutter price per square meter',
  },
  'بحث في مكونات الستار...': {
    AppLanguage.arabic: 'بحث في مكونات الستار...',
    AppLanguage.french: 'Rechercher dans les composants du volet...',
    AppLanguage.english: 'Search shutter components...',
  },
  'أسعار المكونات والقطع': {
    AppLanguage.arabic: 'أسعار المكونات والقطع',
    AppLanguage.french: 'Prix des composants et pièces',
    AppLanguage.english: 'Component and part prices',
  },
  'أسعار المكونات والقطاع': {
    AppLanguage.arabic: 'أسعار المكونات والقطاع',
    AppLanguage.french: 'Prix des composants et profilés',
    AppLanguage.english: 'Component and profile prices',
  },
  'الشمبانيا': {
    AppLanguage.arabic: 'الشمبانيا',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'شمبانيا': {
    AppLanguage.arabic: 'شمبانيا',
    AppLanguage.french: 'Champagne',
    AppLanguage.english: 'Champagne',
  },
  'أسعار الإكسسوارات': {
    AppLanguage.arabic: 'أسعار الإكسسوارات',
    AppLanguage.french: 'Prix des accessoires',
    AppLanguage.english: 'Accessory prices',
  },
  'الإكسسوارات المحتسبة في البيع': {
    AppLanguage.arabic: 'الإكسسوارات المحتسبة في البيع',
    AppLanguage.french: 'Accessoires inclus dans la vente',
    AppLanguage.english: 'Accessories included in sale',
  },
  'الرمز': {
    AppLanguage.arabic: 'الرمز',
    AppLanguage.french: 'Code',
    AppLanguage.english: 'Code',
  },
  'الصندوق الرئيسي': {
    AppLanguage.arabic: 'الصندوق الرئيسي',
    AppLanguage.french: 'Caisse principale',
    AppLanguage.english: 'Main Cash Box',
  },
  'الكل (جميع الصناديق)': {
    AppLanguage.arabic: 'الكل (جميع الصناديق)',
    AppLanguage.french: 'Toutes les caisses',
    AppLanguage.english: 'All Cash Boxes',
  },
  'إدارة الصناديق': {
    AppLanguage.arabic: 'إدارة الصناديق',
    AppLanguage.french: 'Gérer les caisses',
    AppLanguage.english: 'Manage Cash Boxes',
  },
  'خيارات الوصل': {
    AppLanguage.arabic: 'خيارات الوصل',
    AppLanguage.french: 'Options du reçu',
    AppLanguage.english: 'Receipt Options',
  },
  'نقداً / Espèce': {
    AppLanguage.arabic: 'نقداً / Espèce',
    AppLanguage.french: 'Espèce',
    AppLanguage.english: 'Cash',
  },
  'شيك / Chèque': {
    AppLanguage.arabic: 'شيك / Chèque',
    AppLanguage.french: 'Chèque',
    AppLanguage.english: 'Check',
  },
  'شيك مصدق / Chèque de banque': {
    AppLanguage.arabic: 'شيك مصدق / Chèque de banque',
    AppLanguage.french: 'Chèque de banque',
    AppLanguage.english: 'Certified Check',
  },
  'تحويل بنكي / Virement': {
    AppLanguage.arabic: 'تحويل بنكي / Virement',
    AppLanguage.french: 'Virement bancaire',
    AppLanguage.english: 'Bank Transfer',
  },
  'بطاقة بنكية / CIB': {
    AppLanguage.arabic: 'بطاقة بنكية / CIB',
    AppLanguage.french: 'CIB / Carte bancaire',
    AppLanguage.english: 'CIB / Bank Card',
  },
  'CCP / حساب جاري': {
    AppLanguage.arabic: 'CCP / حساب جاري',
    AppLanguage.french: 'CCP / Compte courant',
    AppLanguage.english: 'CCP / Current Account',
  },
  'بريدي موب / BaridiMob': {
    AppLanguage.arabic: 'بريدي موب / BaridiMob',
    AppLanguage.french: 'BaridiMob',
    AppLanguage.english: 'BaridiMob',
  },
  'طريقة الدفع': {
    AppLanguage.arabic: 'طريقة الدفع',
    AppLanguage.french: 'Mode de paiement',
    AppLanguage.english: 'Payment Method',
  },
  'دفع للمورد الفاتورة': {
    AppLanguage.arabic: 'دفع للمورد الفاتورة',
    AppLanguage.french: 'Paiement facture fournisseur',
    AppLanguage.english: 'Supplier Invoice Payment',
  },
  // 'نوع المعاملة': {
  //   AppLanguage.arabic: 'نوع المعاملة',
  //   AppLanguage.french: 'Type de transaction',
  //   AppLanguage.english: 'Transaction Type',
  // },
  'التصنيف': {
    AppLanguage.arabic: 'التصنيف',
    AppLanguage.french: 'Classification',
    AppLanguage.english: 'Category',
  },
  'كلها': {
    AppLanguage.arabic: 'كلها',
    AppLanguage.french: 'Toutes',
    AppLanguage.english: 'All',
  },
  'تكاليف إضافية / مصاريف عامة': {
    AppLanguage.arabic: 'تكاليف إضافية / مصاريف عامة',
    AppLanguage.french: 'Faux frais / Dépenses générales',
    AppLanguage.english: 'General Expenses / Faux Frais',
  },
  'إجمالي المصفى:': {
    AppLanguage.arabic: 'إجمالي المصفى:',
    AppLanguage.french: 'Total filtré:',
    AppLanguage.english: 'Filtered Total:',
  },
  'المقبوضات:': {
    AppLanguage.arabic: 'المقبوضات:',
    AppLanguage.french: 'Recettes:',
    AppLanguage.english: 'Receipts:',
  },
  'المدفوعات:': {
    AppLanguage.arabic: 'المدفوعات:',
    AppLanguage.french: 'Dépenses:',
    AppLanguage.english: 'Payments:',
  },
  'الصافي:': {
    AppLanguage.arabic: 'الصافي:',
    AppLanguage.french: 'Net:',
    AppLanguage.english: 'Net:',
  },
  'زبون': {
    AppLanguage.arabic: 'زبون',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Customer',
  },
  'مورد (استرجاع)': {
    AppLanguage.arabic: 'مورد (استرجاع)',
    AppLanguage.french: 'Fournisseur (Retour)',
    AppLanguage.english: 'Supplier (Refund)',
  },
  'نوع الجهة': {
    AppLanguage.arabic: 'نوع الجهة',
    AppLanguage.french: 'Type d\'entité',
    AppLanguage.english: 'Entity Type',
  },
  'اختر المورد': {
    AppLanguage.arabic: 'اختر المورد',
    AppLanguage.french: 'Sélectionner le fournisseur',
    AppLanguage.english: 'Select Supplier',
  },
  'الرصيد القديم:': {
    AppLanguage.arabic: 'الرصيد القديم:',
    AppLanguage.french: 'Ancien solde:',
    AppLanguage.english: 'Old Balance:',
  },
  'الرصيد الجديد:': {
    AppLanguage.arabic: 'الرصيد الجديد:',
    AppLanguage.french: 'Nouveau solde:',
    AppLanguage.english: 'New Balance:',
  },
  'المبلغ (د.ج)': {
    AppLanguage.arabic: 'المبلغ (د.ج)',
    AppLanguage.french: 'Montant (DA)',
    AppLanguage.english: 'Amount (DZD)',
  },
  'البيان / السبب': {
    AppLanguage.arabic: 'البيان / السبب',
    AppLanguage.french: 'Libellé / Raison',
    AppLanguage.english: 'Description / Reason',
  },
  'تعديل اسم الصندوق': {
    AppLanguage.arabic: 'تعديل اسم الصندوق',
    AppLanguage.french: 'Modifier le nom de la caisse',
    AppLanguage.english: 'Edit Cash Box Name',
  },
  'هل أنت متأكد من حذف الصندوق "\$name"؟ سيتم نقل معاملاته تلقائياً للصندوق الآخر.': {
    AppLanguage.arabic:
        'هل أنت متأكد من حذف الصندوق "\$name"؟ سيتم نقل معاملاته تلقائياً للصندوق الآخر.',
    AppLanguage.french:
        'Êtes-vous sûr de vouloir supprimer la caisse "\$name" ? Ses transactions seront automatiquement transférées.',
    AppLanguage.english:
        'Are you sure you want to delete cash box "\$name"? Its transactions will be automatically transferred.',
  },
  'دفع للمورد الفاتوره': {
    AppLanguage.arabic: 'دفع للمورد الفاتوره',
    AppLanguage.french: 'Paiement facture fournisseur',
    AppLanguage.english: 'Supplier Invoice Payment',
  },
  'دفع للمورد:': {
    AppLanguage.arabic: 'دفع للمورد:',
    AppLanguage.french: 'Payé au fournisseur:',
    AppLanguage.english: 'Paid to Supplier:',
  },
  'دفع للمورد فاتورة رقم': {
    AppLanguage.arabic: 'دفع للمورد فاتورة رقم',
    AppLanguage.french: 'Paiement facture fournisseur N°',
    AppLanguage.english: 'Supplier Invoice Payment N°',
  },
  'للمورد': {
    AppLanguage.arabic: 'للمورد',
    AppLanguage.french: 'Au fournisseur',
    AppLanguage.english: 'To Supplier',
  },
  'من الزبون': {
    AppLanguage.arabic: 'من الزبون',
    AppLanguage.french: 'Du client',
    AppLanguage.english: 'From Customer',
  },
  'إلى العامل': {
    AppLanguage.arabic: 'إلى العامل',
    AppLanguage.french: 'À l\'ouvrier',
    AppLanguage.english: 'To Worker',
  },
  'تفاصيل المعاملة': {
    AppLanguage.arabic: 'تفاصيل المعاملة',
    AppLanguage.french: 'Détails de la transaction',
    AppLanguage.english: 'Transaction Details',
  },
  'تعديل معاملة': {
    AppLanguage.arabic: 'تعديل معاملة',
    AppLanguage.french: 'Modifier la transaction',
    AppLanguage.english: 'Edit Transaction',
  },
  'حذف المعاملة': {
    AppLanguage.arabic: 'حذف المعاملة',
    AppLanguage.french: 'Supprimer la transaction',
    AppLanguage.english: 'Delete Transaction',
  },
  'هل أنت متأكد أنك تريد حذف هذه المعاملة من الصندوق؟': {
    AppLanguage.arabic: 'هل أنت متأكد أنك تريد حذف هذه المعاملة من الصندوق؟',
    AppLanguage.french:
        'Êtes-vous sûr de vouloir supprimer cette transaction ?',
    AppLanguage.english: 'Are you sure you want to delete this transaction?',
  },
  'ترتيب العناصر': {
    AppLanguage.arabic: 'ترتيب العناصر',
    AppLanguage.french: 'Réorganiser les éléments',
    AppLanguage.english: 'Reorder Items',
  },
  'تم': {
    AppLanguage.arabic: 'تم',
    AppLanguage.french: 'Terminé',
    AppLanguage.english: 'Done',
  },
  'نوع كشف الحساب': {
    AppLanguage.arabic: 'نوع كشف الحساب',
    AppLanguage.french: 'Type de relevé',
    AppLanguage.english: 'Statement Type',
  },
  'كشف حساب تفصيلي (بالنوافذ والمقاسات)': {
    AppLanguage.arabic: 'كشف حساب تفصيلي (بالنوافذ والمقاسات)',
    AppLanguage.french:
        'Relevé de compte détaillé (avec fenêtres et dimensions)',
    AppLanguage.english:
        'Detailed Account Statement (with windows & dimensions)',
  },
  'كشف حساب مختصر (بالأرقام فقط)': {
    AppLanguage.arabic: 'كشف حساب مختصر (بالأرقام فقط)',
    AppLanguage.french: 'Relevé de compte condensé (chiffres uniquement)',
    AppLanguage.english: 'Condensed Account Statement (numbers only)',
  },
  'كشف حساب الزبون': {
    AppLanguage.arabic: 'كشف حساب الزبون',
    AppLanguage.french: 'Relevé de compte client',
    AppLanguage.english: 'Customer Account Statement',
  },
  'طباعة كشف الحساب': {
    AppLanguage.arabic: 'طباعة كشف الحساب',
    AppLanguage.french: 'Imprimer le relevé de compte',
    AppLanguage.english: 'Print Account Statement',
  },
  'مشاركة كشف الحساب': {
    AppLanguage.arabic: 'مشاركة كشف الحساب',
    AppLanguage.french: 'Partager le relevé de compte',
    AppLanguage.english: 'Share Account Statement',
  },
  'حفظ كشف الحساب': {
    AppLanguage.arabic: 'حفظ كشف الحساب',
    AppLanguage.french: 'Enregistrer le relevé de compte',
    AppLanguage.english: 'Save Account Statement',
  },
  'الزبون': {
    AppLanguage.arabic: 'الزبون',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Customer',
  },
  'إجمالي الطلبيات': {
    AppLanguage.arabic: 'إجمالي الطلبيات',
    AppLanguage.french: 'Total des commandes',
    AppLanguage.english: 'Total Orders',
  },
  'إجمالي المقبوضات': {
    AppLanguage.arabic: 'إجمالي المقبوضات',
    AppLanguage.french: 'Total des encaissements',
    AppLanguage.english: 'Total Receipts',
  },
  'الرصيد المتبقي': {
    AppLanguage.arabic: 'الرصيد المتبقي',
    AppLanguage.french: 'Solde restant',
    AppLanguage.english: 'Remaining Balance',
  },
  'السجل الزمني للمعاملات': {
    AppLanguage.arabic: 'السجل الزمني للمعاملات',
    AppLanguage.french: 'Historique des transactions',
    AppLanguage.english: 'Transaction History',
  },
  'معاملة': {
    AppLanguage.arabic: 'معاملة',
    AppLanguage.french: 'transaction(s)',
    AppLanguage.english: 'transaction(s)',
  },
  'لا توجد معاملات مسجلة بعد لهذا الزبون': {
    AppLanguage.arabic: 'لا توجد معاملات مسجلة بعد لهذا الزبون',
    AppLanguage.french: 'Aucune transaction enregistrée pour ce client',
    AppLanguage.english: 'No transactions recorded yet for this customer',
  },
  'طلب شراء': {
    AppLanguage.arabic: 'طلب شراء',
    AppLanguage.french: 'Bon de commande',
    AppLanguage.english: 'Purchase Order',
  },
  'دفعة مالية': {
    AppLanguage.arabic: 'دفعة مالية',
    AppLanguage.french: 'Versement / Paiement',
    AppLanguage.english: 'Payment',
  },
  'مسترجع نقدي': {
    AppLanguage.arabic: 'مسترجع نقدي',
    AppLanguage.french: 'Remboursement',
    AppLanguage.english: 'Refund',
  },
  'رصيد جاري': {
    AppLanguage.arabic: 'رصيد جاري',
    AppLanguage.french: 'Solde courant',
    AppLanguage.english: 'Current Balance',
  },
  'سجل الطلبيات والمدفوعات مرتبة زمنياً': {
    AppLanguage.arabic: 'سجل الطلبيات والمدفوعات مرتبة زمنياً',
    AppLanguage.french: 'Historique des commandes et règlements chronologique',
    AppLanguage.english: 'Chronological record of orders and payments',
  },
  'طباعة الوصل': {
    AppLanguage.arabic: 'طباعة الوصل',
    AppLanguage.french: 'Imprimer le reçu',
    AppLanguage.english: 'Print Receipt',
  },
  'رقم الطلبية': {
    AppLanguage.arabic: 'رقم الطلبية',
    AppLanguage.french: 'N° Commande',
    AppLanguage.english: 'Order N°',
  },
  'رقم الدفعة': {
    AppLanguage.arabic: 'رقم الدفعة',
    AppLanguage.french: 'N° Reçu',
    AppLanguage.english: 'Receipt N°',
  },
  'البيان': {
    AppLanguage.arabic: 'البيان',
    AppLanguage.french: 'Libellé / Description',
    AppLanguage.english: 'Description',
  },
  'مدين (+)': {
    AppLanguage.arabic: 'مدين (+)',
    AppLanguage.french: 'Débit (+)',
    AppLanguage.english: 'Debit (+)',
  },
  'دائن (-)': {
    AppLanguage.arabic: 'دائن (-)',
    AppLanguage.french: 'Crédit (-)',
    AppLanguage.english: 'Credit (-)',
  },
  'نورالور للألمنيوم / Noraleur': {
    AppLanguage.arabic: 'نورالور للألمنيوم',
    AppLanguage.french: 'Noraleur Aluminium',
    AppLanguage.english: 'Noraleur Aluminium',
  },
  'توقيع الزبون': {
    AppLanguage.arabic: 'توقيع الزبون',
    AppLanguage.french: 'Signature du client',
    AppLanguage.english: 'Customer Signature',
  },
  'إمضاء الورشة': {
    AppLanguage.arabic: 'إمضاء الورشة',
    AppLanguage.french: 'Cachet et Signature',
    AppLanguage.english: 'Stamp & Signature',
  },
  'عرض كشف الحساب التفصيلي (Chrono)': {
    AppLanguage.arabic: 'عرض كشف الحساب التفصيلي (Chrono)',
    AppLanguage.french: 'Afficher le relevé de compte détaillé (Chrono)',
    AppLanguage.english: 'Show Detailed Account Statement (Chrono)',
  },
  'عرض كشف الحساب التفصيلي': {
    AppLanguage.arabic: 'عرض كشف الحساب التفصيلي',
    AppLanguage.french: 'Afficher le relevé de compte détaillé',
    AppLanguage.english: 'Show Detailed Account Statement',
  },
  'رصيد الصندوق': {
    AppLanguage.arabic: 'رصيد الصندوق',
    AppLanguage.french: 'Solde de la Caisse',
    AppLanguage.english: 'Cash Balance',
  },
  'دفعة لطلبية': {
    AppLanguage.arabic: 'دفعة لطلبية',
    AppLanguage.french: 'Acompte pour commande',
    AppLanguage.english: 'Advance for order',
  },
  'رقم الفاتورة': {
    AppLanguage.arabic: 'رقم الفاتورة',
    AppLanguage.french: 'Numéro de facture',
    AppLanguage.english: 'Invoice Number',
  },
  'رقم': {
    AppLanguage.arabic: 'رقم',
    AppLanguage.french: 'N°',
    AppLanguage.english: 'No.',
  },
  'خطط التوزيع والتتبع': {
    AppLanguage.arabic: 'خطط التوزيع والتتبع',
    AppLanguage.french: 'Plans de distribution & Suivi',
    AppLanguage.english: 'Distribution & Tracking Plans',
  },
  'Pending': {
    AppLanguage.arabic: 'قيد الانتظار',
    AppLanguage.french: 'En attente',
    AppLanguage.english: 'Pending',
  },
  'In Progress': {
    AppLanguage.arabic: 'القياسات مؤكدة',
    AppLanguage.french: 'Mesures confirmées',
    AppLanguage.english: 'Measurements Confirmed',
  },
  'Installation': {
    AppLanguage.arabic: 'تركيب',
    AppLanguage.french: 'Installation',
    AppLanguage.english: 'Installation',
  },
  'Reserve': {
    AppLanguage.arabic: 'تحت التحفظ',
    AppLanguage.french: 'Sous réserve',
    AppLanguage.english: 'Reserve',
  },
  'Done': {
    AppLanguage.arabic: 'منتهية',
    AppLanguage.french: 'Terminée',
    AppLanguage.english: 'Done',
  },
  'New': {
    AppLanguage.arabic: 'جديد',
    AppLanguage.french: 'Nouveau',
    AppLanguage.english: 'New',
  },
  'Nouveau': {
    AppLanguage.arabic: 'جديدة',
    AppLanguage.french: 'Nouveau',
    AppLanguage.english: 'New',
  },
  'المؤكدة فما فوق': {
    AppLanguage.arabic: 'المؤكدة فما فوق',
    AppLanguage.french: 'Confirmées et plus',
    AppLanguage.english: 'Confirmed and above',
  },
  'قيد التصنيع وما بعدها': {
    AppLanguage.arabic: 'قيد التصنيع وما بعدها',
    AppLanguage.french: 'En fabrication et plus',
    AppLanguage.english: 'In manufacturing and beyond',
  },
  'التوزيع وما بعده': {
    AppLanguage.arabic: 'التوزيع وما بعده',
    AppLanguage.french: 'En distribution et plus',
    AppLanguage.english: 'In distribution and beyond',
  },
  'Partial Distribution': {
    AppLanguage.arabic: 'توزيع جزئي',
    AppLanguage.french: 'Distribution partielle',
    AppLanguage.english: 'Partial Distribution',
  },
  'Full Distribution': {
    AppLanguage.arabic: 'توزيع كلي',
    AppLanguage.french: 'Distribution complète',
    AppLanguage.english: 'Full Distribution',
  },
  'Partial Manufacturing': {
    AppLanguage.arabic: 'تصنيع جزئي',
    AppLanguage.french: 'Fabrication partielle',
    AppLanguage.english: 'Partial Manufacturing',
  },
  'Full Manufacturing': {
    AppLanguage.arabic: 'تصنيع كامل',
    AppLanguage.french: 'Fabrication complète',
    AppLanguage.english: 'Full Manufacturing',
  },
  'تصنيع كامل': {
    AppLanguage.arabic: 'تصنيع كامل',
    AppLanguage.french: 'Fabrication complète',
    AppLanguage.english: 'Full Manufacturing',
  },
  'تصنيع كلي': {
    AppLanguage.arabic: 'تصنيع كامل',
    AppLanguage.french: 'Fabrication complète',
    AppLanguage.english: 'Full Manufacturing',
  },
  'تصنيع جزئي': {
    AppLanguage.arabic: 'تصنيع جزئي',
    AppLanguage.french: 'Fabrication partielle',
    AppLanguage.english: 'Partial Manufacturing',
  },
  'توزيع كلي': {
    AppLanguage.arabic: 'توزيع كلي',
    AppLanguage.french: 'Livraison complète',
    AppLanguage.english: 'Full Distribution',
  },
  'تأكيد القياسات': {
    AppLanguage.arabic: 'تأكيد القياسات',
    AppLanguage.french: 'Confirmation des mesures',
    AppLanguage.english: 'In Progress',
  },
  'المستودع': {
    AppLanguage.arabic: 'المستودع',
    AppLanguage.french: 'Dépôt',
    AppLanguage.english: 'Warehouse',
  },
  'صناديق الورشة': {
    AppLanguage.arabic: 'صناديق الورشة',
    AppLanguage.french: 'Caisses de l\'atelier',
    AppLanguage.english: 'Workshop Cash Boxes',
  },
  'إدارة الصناديق والحسابات': {
    AppLanguage.arabic: 'إدارة الصناديق والحسابات',
    AppLanguage.french: 'Gestion des Caisses & Comptes',
    AppLanguage.english: 'Manage Cash Boxes & Accounts',
  },
  'اسم صندوق جديد': {
    AppLanguage.arabic: 'اسم صندوق جديد',
    AppLanguage.french: 'Nom de la nouvelle caisse',
    AppLanguage.english: 'New cash box name',
  },
  'الصناديق الحالية (اضغط للتعديل أو الحذف):': {
    AppLanguage.arabic: 'الصناديق الحالية (اضغط للتعديل أو الحذف):',
    AppLanguage.french: 'Caisses actuelles (cliquez pour modifier/supprimer):',
    AppLanguage.english: 'Current cash boxes (click to edit/delete):',
  },
  'الاسم الجديد': {
    AppLanguage.arabic: 'الاسم الجديد',
    AppLanguage.french: 'Nouveau nom',
    AppLanguage.english: 'New Name',
  },
  'الصندوق الثاني': {
    AppLanguage.arabic: 'الصندوق الثاني',
    AppLanguage.french: 'Deuxième Caisse',
    AppLanguage.english: 'Secondary Cash Box',
  },
  'البنك': {
    AppLanguage.arabic: 'البنك',
    AppLanguage.french: 'Banque',
    AppLanguage.english: 'Bank',
  },
  'دفعة لطلبية رقم': {
    AppLanguage.arabic: 'دفعة لطلبية رقم',
    AppLanguage.french: 'Acompte pour commande N°',
    AppLanguage.english: 'Advance for order No.',
  },
  'دفعة لطلبية رقم:': {
    AppLanguage.arabic: 'دفعة لطلبية رقم:',
    AppLanguage.french: 'Acompte pour commande N°:',
    AppLanguage.english: 'Advance for order No.:',
  },
  'فاتورة رقم:': {
    AppLanguage.arabic: 'فاتورة رقم:',
    AppLanguage.french: 'Facture N°:',
    AppLanguage.english: 'Invoice No:',
  },
  'هل أنت متأكد من حذف الصندوق': {
    AppLanguage.arabic: 'هل أنت متأكد من حذف الصندوق',
    AppLanguage.french: 'Êtes-vous sûr de vouloir supprimer la caisse',
    AppLanguage.english: 'Are you sure you want to delete the cash box',
  },
  'سيتم نقل معاملاته تلقائياً للصندوق الآخر.': {
    AppLanguage.arabic: 'سيتم نقل معاملاته تلقائياً للصندوق الآخر.',
    AppLanguage.french:
        'Ses transactions seront automatiquement transférées vers l\'autre caisse.',
    AppLanguage.english:
        'Its transactions will be automatically transferred to the other cash box.',
  },

  'BON_ROUTE': {
    AppLanguage.arabic: 'بون دو روت',
    AppLanguage.french: 'Bon de Route',
    AppLanguage.english: 'Bon de Route',
  },
  'مقبوضات': {
    AppLanguage.arabic: 'مقبوضات',
    AppLanguage.french: 'Recettes',
    AppLanguage.english: 'Receipts',
  },
  'مدفوعات': {
    AppLanguage.arabic: 'مدفوعات',
    AppLanguage.french: 'Dépenses',
    AppLanguage.english: 'Payments',
  },
  'إضافة غطاء جانبي': {
    AppLanguage.arabic: 'إضافة غطاء جانبي',
    AppLanguage.french: 'Ajouter couvre-joint',
    AppLanguage.english: 'Add Side Cover',
  },
  'إزالة غطاء جانبي': {
    AppLanguage.arabic: 'إزالة غطاء جانبي',
    AppLanguage.french: 'Retirer couvre-joint',
    AppLanguage.english: 'Remove Side Cover',
  },
  'التكلفة الفعلية': {
    AppLanguage.arabic: 'التكلفة الفعلية',
    AppLanguage.french: 'Coût réel',
    AppLanguage.english: 'Actual Cost',
  },
  'الطول': {
    AppLanguage.arabic: 'الطول',
    AppLanguage.french: 'Longueur',
    AppLanguage.english: 'Length',
  },
  'التفاصيل': {
    AppLanguage.arabic: 'التفاصيل',
    AppLanguage.french: 'Détails',
    AppLanguage.english: 'Details',
  },
  'سعر القطعة الواحدة:': {
    AppLanguage.arabic: 'سعر القطعة الواحدة:',
    AppLanguage.french: 'Prix unitaire :',
    AppLanguage.english: 'Price per unit:',
  },
  'حفظ وإضافة للطلب': {
    AppLanguage.arabic: 'حفظ وإضافة للطلب',
    AppLanguage.french: 'Enregistrer et ajouter',
    AppLanguage.english: 'Save and Add',
  },
  'إضافة واحتساب السعر': {
    AppLanguage.arabic: 'إضافة واحتساب السعر',
    AppLanguage.french: 'Ajouter et calculer le prix',
    AppLanguage.english: 'Add and calculate price',
  },
  'جاري احتساب سعر العنصر...': {
    AppLanguage.arabic: 'جاري احتساب سعر العنصر...',
    AppLanguage.french: 'Calcul du prix de l’article...',
    AppLanguage.english: 'Calculating item price...',
  },
  'تعذر احتساب سعر العنصر': {
    AppLanguage.arabic: 'تعذر احتساب سعر العنصر',
    AppLanguage.french: 'Impossible de calculer le prix de l’article',
    AppLanguage.english: 'Unable to calculate item price',
  },
  'لم تتم إضافة العنصر لأن سعره يساوي صفرًا. راجع أسعار البروفيلات والزجاج والستار ثم أعد المحاولة.': {
    AppLanguage.arabic:
        'لم تتم إضافة العنصر لأن سعره يساوي صفرًا. راجع أسعار البروفيلات والزجاج والستار ثم أعد المحاولة.',
    AppLanguage.french:
        'L’article n’a pas été ajouté car son prix est nul. Vérifiez les prix des profilés, du verre et du volet, puis réessayez.',
    AppLanguage.english:
        'The item was not added because its price is zero. Check profile, glass, and shutter prices, then try again.',
  },
  'تعذر الحفظ: يوجد عنصر بسعر صفر. راجع أسعار البروفيلات والزجاج والستار ثم أعد المحاولة.': {
    AppLanguage.arabic:
        'تعذر الحفظ: يوجد عنصر بسعر صفر. راجع أسعار البروفيلات والزجاج والستار ثم أعد المحاولة.',
    AppLanguage.french:
        'Enregistrement impossible : un article a un prix nul. Vérifiez les prix des profilés, du verre et du volet, puis réessayez.',
    AppLanguage.english:
        'Cannot save: an item has a zero price. Check profile, glass, and shutter prices, then try again.',
  },
  'المطلوب الفعلي': {
    AppLanguage.arabic: 'المطلوب الفعلي',
    AppLanguage.french: 'Besoin réel',
    AppLanguage.english: 'Actual requirement',
  },
  'الأمتار الفعلية المستعملة': {
    AppLanguage.arabic: 'الأمتار الفعلية المستعملة',
    AppLanguage.french: 'Mètres réellement utilisés',
    AppLanguage.english: 'Actual metres used',
  },
  'البيع': {
    AppLanguage.arabic: 'البيع',
    AppLanguage.french: 'Vente',
    AppLanguage.english: 'Sale',
  },
  'إخفاء': {
    AppLanguage.arabic: 'إخفاء',
    AppLanguage.french: 'Masquer',
    AppLanguage.english: 'Hide',
  },
  'تفاصيل': {
    AppLanguage.arabic: 'تفاصيل',
    AppLanguage.french: 'Détails',
    AppLanguage.english: 'Details',
  },
  'اختيار من القائمة': {
    AppLanguage.arabic: 'اختيار من القائمة',
    AppLanguage.french: 'Choisir dans la liste',
    AppLanguage.english: 'Choose from list',
  },
  'اختيار حالة الطلبية': {
    AppLanguage.arabic: 'اختيار حالة الطلبية',
    AppLanguage.french: 'Choisir le statut de la commande',
    AppLanguage.english: 'Choose order status',
  },
  'كل الحالات': {
    AppLanguage.arabic: 'كل الحالات',
    AppLanguage.french: 'Tous les statuts',
    AppLanguage.english: 'All statuses',
  },
  'السلاسل الافتراضية': {
    AppLanguage.arabic: 'السلاسل الافتراضية',
    AppLanguage.french: 'Séries par défaut',
    AppLanguage.english: 'Default Series',
  },
  'السلاسل الافتراضية للورشة': {
    AppLanguage.arabic: 'السلاسل الافتراضية للورشة',
    AppLanguage.french: 'Séries par défaut de l\'atelier',
    AppLanguage.english: 'Workshop Default Series',
  },
  'حدد السلسلة التي تفتح بها النوافذ الجديدة تلقائياً بدون الحاجة لتغييرها في كل مرة:': {
    AppLanguage.arabic:
        'حدد السلسلة التي تفتح بها النوافذ الجديدة تلقائياً بدون الحاجة لتغييرها في كل مرة:',
    AppLanguage.french:
        'Définissez les séries qui s\'ouvrent automatiquement pour les nouvelles fenêtres :',
    AppLanguage.english:
        'Define the series that open automatically for new windows:',
  },
  'سلسلة الفتح الافتراضية (Battant):': {
    AppLanguage.arabic: 'سلسلة الفتح الافتراضية (Battant):',
    AppLanguage.french: 'Série ouvrante par défaut (Battant) :',
    AppLanguage.english: 'Default opening series (Battant):',
  },
  'سلسلة المنزلق الافتراضية (Coulissant):': {
    AppLanguage.arabic: 'سلسلة المنزلق الافتراضية (Coulissant):',
    AppLanguage.french: 'Série coulissante par défaut (Coulissant) :',
    AppLanguage.english: 'Default sliding series (Coulissant):',
  },
  'تلقائي (افتراضي النظام)': {
    AppLanguage.arabic: 'تلقائي (افتراضي النظام)',
    AppLanguage.french: 'Automatique (Défaut du système)',
    AppLanguage.english: 'Automatic (System default)',
  },
  'تم حفظ السلاسل الافتراضية بنجاح': {
    AppLanguage.arabic: 'تم حفظ السلاسل الافتراضية بنجاح',
    AppLanguage.french: 'Séries par défaut enregistrées avec succès',
    AppLanguage.english: 'Default series saved successfully',
  },
  'Seuil (بروفيل C)': {
    AppLanguage.arabic: 'بروفيل C (Seuil)',
    AppLanguage.french: 'Seuil (profil C)',
    AppLanguage.english: 'Threshold (C profile)',
  },
  'مفعل حتميًا حسب قواعد السلسلة': {
    AppLanguage.arabic: 'مفعل حتميًا حسب قواعد السلسلة',
    AppLanguage.french: 'Activé selon les règles de la série',
    AppLanguage.english: 'Required by series rules',
  },
  'يستبدل الإطار السفلي': {
    AppLanguage.arabic: 'يستبدل الإطار السفلي',
    AppLanguage.french: 'Remplace le dormant bas',
    AppLanguage.english: 'Replaces bottom frame',
  },
  'تفعيل الكانيفو (Système C zéro)': {
    AppLanguage.arabic: 'تفعيل الكانيفو (Système C zéro)',
    AppLanguage.french: 'Activer Caniveau (Système C zéro)',
    AppLanguage.english: 'Enable Caniveau (C-zero system)',
  },
  'غير متاح مع بروفيل C / Seuil': {
    AppLanguage.arabic: 'غير متاح مع بروفيل C / Seuil',
    AppLanguage.french: 'Non disponible avec Seuil (profil C)',
    AppLanguage.english: 'Not available with Seuil (C profile)',
  },
  'يتطلب الإطار السفلي ويضيف الغطاء والبوشون تلقائياً': {
    AppLanguage.arabic: 'يتطلب الإطار السفلي ويضيف الغطاء والبوشون تلقائياً',
    AppLanguage.french: 'Nécessite le dormant bas et ajoute capot et bouchon',
    AppLanguage.english: 'Requires bottom frame and auto-adds cover and cap',
  },
  'البافيت (Bavette)': {
    AppLanguage.arabic: 'البافيت (Bavette)',
    AppLanguage.french: 'Bavette',
    AppLanguage.english: 'Bavette',
  },
  'أسفل فقط': {
    AppLanguage.arabic: 'أسفل فقط',
    AppLanguage.french: 'Bas uniquement',
    AppLanguage.english: 'Bottom only',
  },
  'الجهات الأربع': {
    AppLanguage.arabic: 'الجهات الأربع',
    AppLanguage.french: '4 Côtés',
    AppLanguage.english: '4 Sides',
  },
  'كاش الإطار (Cache dormant)': {
    AppLanguage.arabic: 'كاش الإطار (Cache dormant)',
    AppLanguage.french: 'Cache dormant',
    AppLanguage.english: 'Frame cover (Cache dormant)',
  },
  'يتبع فقط جهات الإطار الموجودة': {
    AppLanguage.arabic: 'يتبع فقط جهات الإطار الموجودة',
    AppLanguage.french: 'Suit uniquement les côtés du dormant existants',
    AppLanguage.english: 'Follows only existing frame sides',
  },
  'تراينغل (Triangle)': {
    AppLanguage.arabic: 'تراينغل (Triangle)',
    AppLanguage.french: 'Triangle',
    AppLanguage.english: 'Triangle',
  },
  'استعمال اختياري حسب ربط الأكسيسوار': {
    AppLanguage.arabic: 'استعمال اختياري حسب ربط الأكسيسوار',
    AppLanguage.french: 'Optionnel selon la liaison de l’accessoire',
    AppLanguage.english: 'Optional depending on accessory link',
  },
  'تدعيم المونطو والأعمدة (Renfort)': {
    AppLanguage.arabic: 'تدعيم المونطو والأعمدة',
    AppLanguage.french: 'Renfort des montants',
    AppLanguage.english: 'Montant reinforcement',
  },
  'تدعيم المونطو والأعمدة': {
    AppLanguage.arabic: 'تدعيم المونطو والأعمدة',
    AppLanguage.french: 'Renfort des montants',
    AppLanguage.english: 'Montant reinforcement',
  },
  'قاعدة التدعيم (Règle de Renfort):': {
    AppLanguage.arabic: 'قاعدة التدعيم:',
    AppLanguage.french: 'Règle de renfort :',
    AppLanguage.english: 'Reinforcement rule:',
  },
  'قاعدة التدعيم:': {
    AppLanguage.arabic: 'قاعدة التدعيم:',
    AppLanguage.french: 'Règle de renfort :',
    AppLanguage.english: 'Reinforcement rule:',
  },
  'قاعدة التدعيم': {
    AppLanguage.arabic: 'قاعدة التدعيم',
    AppLanguage.french: 'Règle de renfort',
    AppLanguage.english: 'Reinforcement rule',
  },
  'هذه السلسلة تدعم الأعمدة المدعمة': {
    AppLanguage.arabic: 'هذه السلسلة تدعم الأعمدة المدعمة',
    AppLanguage.french: 'Cette série supporte les montants renforcés',
    AppLanguage.english: 'This series supports reinforced montants',
  },
  'لا توجد مقابض مفعّلة لهذه السلسلة': {
    AppLanguage.arabic: 'لا توجد مقابض مفعّلة لهذه السلسلة',
    AppLanguage.french: 'Aucune poignée activée pour cette série',
    AppLanguage.english: 'No handles enabled for this series',
  },
  'بروفيل الزاوية 90° (Tube carré)': {
    AppLanguage.arabic: 'بروفيل الزاوية 90° (تيبيكاري)',
    AppLanguage.french: 'Profilé d\'angle 90° (Tube carré)',
    AppLanguage.english: '90° Angle Profile (Square Tube)',
  },
  'بروفيل الزاوية 90° (Profil d\'angle / Tube carré)': {
    AppLanguage.arabic: 'بروفيل الزاوية 90° (تيبيكاري)',
    AppLanguage.french: 'Profilé d\'angle 90° (Tube carré)',
    AppLanguage.english: '90° Angle Profile (Square Tube)',
  },
  'حدد الفواصل بين الإطارات المتلاصقة التي يركب فيها أنبوب الزاوية 90°:': {
    AppLanguage.arabic:
        'حدد الفواصل بين الإطارات المتلاصقة التي يركب فيها أنبوب الزاوية 90°:',
    AppLanguage.french:
        'Sélectionnez les jonctions entre cadres recevant le tube d\'angle 90° :',
    AppLanguage.english:
        'Select junctions between frames receiving 90° angle tube:',
  },
  'إلغاء بروفيل الزاوية بين الإطارات (إيقاف)': {
    AppLanguage.arabic: 'إلغاء بروفيل الزاوية بين الإطارات (إيقاف)',
    AppLanguage.french: 'Désactiver le tube d\'angle entre cadres',
    AppLanguage.english: 'Disable angle tube between frames',
  },
  'بدون أي أنبوب زاوية بين الإطارات المتلاصقة': {
    AppLanguage.arabic: 'بدون أي أنبوب زاوية بين الإطارات المتلاصقة',
    AppLanguage.french: 'Aucun tube d\'angle entre les cadres adjacents',
    AppLanguage.english: 'No angle tube between adjacent frames',
  },
  'أطراف الإطار الخارجية (يمين / يسار):': {
    AppLanguage.arabic: 'أطراف الإطار الخارجية (يمين / يسار):',
    AppLanguage.french: 'Extrémités extérieures du cadre (droite / gauche) :',
    AppLanguage.english: 'Outer frame edges (right / left):',
  },
  'اختر جهة تركيب بروفيل الزاوية 90°:': {
    AppLanguage.arabic: 'اختر جهة تركيب بروفيل الزاوية 90°:',
    AppLanguage.french: 'Choisissez le côté de pose du profilé d\'angle 90° :',
    AppLanguage.english: 'Choose placement side for 90° angle profile:',
  },
  'بدون زاوية على الأطراف الخارجية': {
    AppLanguage.arabic: 'بدون زاوية على الأطراف الخارجية',
    AppLanguage.french: 'Sans cornière sur les extrémités extérieures',
    AppLanguage.english: 'No angle on outer edges',
  },
  'إيقاف / بدون بروفيل زاوية': {
    AppLanguage.arabic: 'إيقاف / بدون بروفيل زاوية',
    AppLanguage.french: 'Désactivé / Sans profilé d\'angle',
    AppLanguage.english: 'Disabled / No angle profile',
  },
  'جهة اليمين (90° Droite)': {
    AppLanguage.arabic: 'جهة اليمين (90° يمين)',
    AppLanguage.french: 'Côté droit (90° Droite)',
    AppLanguage.english: 'Right side (90° Right)',
  },
  'أنبوب زاوية 90° على القائم الأيمن الخارجي': {
    AppLanguage.arabic: 'أنبوب زاوية 90° على القائم الأيمن الخارجي',
    AppLanguage.french: 'Tube d\'angle 90° sur montant droit extérieur',
    AppLanguage.english: '90° angle tube on outer right montant',
  },
  'جهة اليسار (90° Gauche)': {
    AppLanguage.arabic: 'جهة اليسار (90° يسار)',
    AppLanguage.french: 'Côté gauche (90° Gauche)',
    AppLanguage.english: 'Left side (90° Left)',
  },
  'أنبوب زاوية 90° على القائم الأيسر الخارجي': {
    AppLanguage.arabic: 'أنبوب زاوية 90° على القائم الأيسر الخارجي',
    AppLanguage.french: 'Tube d\'angle 90° sur montant gauche extérieur',
    AppLanguage.english: '90° angle tube on outer left montant',
  },
  'الجهتين': {
    AppLanguage.arabic: 'الجهتين',
    AppLanguage.french: 'Deux côtés',
    AppLanguage.english: 'Both sides',
  },
  'الموستيكير': {
    AppLanguage.arabic: 'الموستيكير',
    AppLanguage.french: 'Moustiquaire',
    AppLanguage.english: 'Mosquito screen',
  },
  'تظهر في الكمية والتكلفة فقط ولا تظهر في الرسم': {
    AppLanguage.arabic: 'تظهر في الكمية والتكلفة فقط ولا تظهر في الرسم',
    AppLanguage.french: 'Apparaît uniquement dans la quantité et le coût, pas sur le dessin',
    AppLanguage.english: 'Appears only in quantity and cost, not on the drawing',
  },
  'عرض الضلفة اليمنى (مم)': {
    AppLanguage.arabic: 'عرض الضلفة اليمنى (مم)',
    AppLanguage.french: 'Largeur du battant droit (mm)',
    AppLanguage.english: 'Right sash width (mm)',
  },
  'الجهتين معاً (90° Les deux côtés)': {
    AppLanguage.arabic: 'الجهتين معاً (90° الطرفين)',
    AppLanguage.french: 'Les deux côtés (90° Droite et Gauche)',
    AppLanguage.english: 'Both sides (90° Right and Left)',
  },
  'أنبوب زاوية 90° على القائمين الخارجيين': {
    AppLanguage.arabic: 'أنبوب زاوية 90° على القائمين الخارجيين',
    AppLanguage.french: 'Tube d\'angle 90° sur les deux montants extérieurs',
    AppLanguage.english: '90° angle tube on both outer montants',
  },
  'أنبوب زاوية 90° على كلا الجانبين الأيمن والأيسر': {
    AppLanguage.arabic: 'أنبوب زاوية 90° على كلا الجانبين الأيمن والأيسر',
    AppLanguage.french: 'Tube d\'angle 90° sur les deux côtés droit et gauche',
    AppLanguage.english: '90° angle tube on both right and left sides',
  },
  'عمود تدعيم مستقل (Profilé Renfort Rapporté)': {
    AppLanguage.arabic: 'عمود تدعيم مستقل',
    AppLanguage.french: 'Profilé Renfort Rapporté',
    AppLanguage.english: 'Independent Renfort Profile',
  },
  'عمود تدعيم مستقل': {
    AppLanguage.arabic: 'عمود تدعيم مستقل',
    AppLanguage.french: 'Profilé Renfort Rapporté',
    AppLanguage.english: 'Independent Renfort Profile',
  },
  'Profilé Renfort Rapporté': {
    AppLanguage.arabic: 'عمود تدعيم مستقل',
    AppLanguage.french: 'Profilé Renfort Rapporté',
    AppLanguage.english: 'Independent Renfort Profile',
  },
  'براغي تثبيت العمود المدعم 3.9×38 (Vis Renfort 3.9×38)': {
    AppLanguage.arabic: 'براغي تثبيت العمود المدعم 3.9×38',
    AppLanguage.french: 'Vis Renfort 3.9×38',
    AppLanguage.english: 'Reinforcement Screws 3.9×38',
  },
  'Vis Renfort 3.9×38': {
    AppLanguage.arabic: 'براغي تثبيت العمود المدعم 3.9×38',
    AppLanguage.french: 'Vis Renfort 3.9×38',
    AppLanguage.english: 'Reinforcement Screws 3.9×38',
  },
  'أغطية العمود المدعم (Caches Renfort)': {
    AppLanguage.arabic: 'أغطية العمود المدعم',
    AppLanguage.french: 'Caches Renfort',
    AppLanguage.english: 'Reinforcement End Caps',
  },
  'Caches Renfort': {
    AppLanguage.arabic: 'أغطية العمود المدعم',
    AppLanguage.french: 'Caches Renfort',
    AppLanguage.english: 'Reinforcement End Caps',
  },
  'شيكان معزز (Chicane Renforcée)': {
    AppLanguage.arabic: 'شيكان معزز',
    AppLanguage.french: 'Chicane Renforcée',
    AppLanguage.english: 'Reinforced Chicane',
  },
  'Chicane Renforcée': {
    AppLanguage.arabic: 'شيكان معزز',
    AppLanguage.french: 'Chicane Renforcée',
    AppLanguage.english: 'Reinforced Chicane',
  },
  'غير مُسند': {
    AppLanguage.arabic: 'غير مُسند',
    AppLanguage.french: 'Non assigné',
    AppLanguage.english: 'Unassigned',
  },
  'غير مسند': {
    AppLanguage.arabic: 'غير مسند',
    AppLanguage.french: 'Non assigné',
    AppLanguage.english: 'Unassigned',
  },
  'التقاء الوسط (Face-to-Face)': {
    AppLanguage.arabic: 'التقاء الظرفتين الوسطيتين (Batmo central)',
    AppLanguage.french: 'Rencontre face à face (Batmo central)',
    AppLanguage.english: 'Face to face meeting (Batmo central)',
  },
  'التقاء الظرفتين الوسطيتين (Batmo central)': {
    AppLanguage.arabic: 'التقاء الظرفتين الوسطيتين (Batmo central)',
    AppLanguage.french: 'Rencontre face à face (Batmo central)',
    AppLanguage.english: 'Face to face meeting (Batmo central)',
  },
  'إطار زاوية 90°': {
    AppLanguage.arabic: 'إطار زاوية 90°',
    AppLanguage.french: 'Cadre angle 90°',
    AppLanguage.english: '90° corner frame',
  },
  'إطار زاوية 90° معتمد في جدول الكمية والتكلفة': {
    AppLanguage.arabic: 'إطار زاوية 90° معتمد في جدول الكمية والتكلفة',
    AppLanguage.french: 'Cadre angle 90° appliqué au devis',
    AppLanguage.english: '90° corner frame applied in BOM',
  },
  'مقبض الوسط الشكلي: مفعّل': {
    AppLanguage.arabic: 'مقبض الوسط الشكلي: مفعّل',
    AppLanguage.french: 'Poignée centrale décorative : activée',
    AppLanguage.english: 'Decorative center handle: enabled',
  },
  'مقبض الوسط الشكلي: ملغي': {
    AppLanguage.arabic: 'مقبض الوسط الشكلي: ملغى',
    AppLanguage.french: 'Poignée centrale décorative : désactivée',
    AppLanguage.english: 'Decorative center handle: disabled',
  },
  'مقبض وسط الضلفتين': {
    AppLanguage.arabic: 'مقبض وسط الضلفتين',
    AppLanguage.french: 'Poignée centrale des deux vantaux',
    AppLanguage.english: 'Center handle between the two sashes',
  },
  'مقبض الوسط الثاني (شكلي)': {
    AppLanguage.arabic: 'مقبض الوسط الثاني (شكلي)',
    AppLanguage.french: 'Deuxième poignée centrale (décorative)',
    AppLanguage.english: 'Second center handle (decorative)',
  },
  'إضافة بروفيل زاوية 90°': {
    AppLanguage.arabic: 'إضافة بروفيل زاوية 90°',
    AppLanguage.french: "Ajouter profil d'angle 90°",
    AppLanguage.english: 'Add 90° corner profile',
  },
  'بروفيل زاوية 90°': {
    AppLanguage.arabic: 'بروفيل زاوية 90°',
    AppLanguage.french: "Profil d'angle 90°",
    AppLanguage.english: '90° corner profile',
  },
  'إضافة بلانت للإطار': {
    AppLanguage.arabic: 'إضافة بلانت للإطار',
    AppLanguage.french: 'Ajouter plinthe au dormant',
    AppLanguage.english: 'Add frame plinthe',
  },
  'حذف بلانت الإطار': {
    AppLanguage.arabic: 'حذف بلانت الإطار',
    AppLanguage.french: 'Supprimer plinthe du dormant',
    AppLanguage.english: 'Remove frame plinthe',
  },
  'مشتريات محل المواد': {
    AppLanguage.arabic: 'مشتريات محل المواد',
    AppLanguage.french: 'Achats magasin de matériaux',
    AppLanguage.english: 'Materials Store Purchases',
  },
  'مخزون محل المواد': {
    AppLanguage.arabic: 'مخزون محل المواد',
    AppLanguage.french: 'Stock magasin de matériaux',
    AppLanguage.english: 'Materials Store Inventory',
  },
  'بيع داخلي للورشة (تحويل مخزون تلقائي)': {
    AppLanguage.arabic: 'بيع داخلي للورشة (تحويل مخزون تلقائي)',
    AppLanguage.french:
        'Vente interne atelier (transfert de stock automatique)',
    AppLanguage.english: 'Internal sale to workshop (automatic stock transfer)',
  },
  'مستودع المحل (المصدر)': {
    AppLanguage.arabic: 'مستودع المحل (المصدر)',
    AppLanguage.french: 'Dépôt magasin (source)',
    AppLanguage.english: 'Store warehouse (source)',
  },
  'مستودع الورشة (المستلم)': {
    AppLanguage.arabic: 'مستودع الورشة (المستلم)',
    AppLanguage.french: 'Dépôt atelier (destinataire)',
    AppLanguage.english: 'Workshop warehouse (destination)',
  },
  'داخلي (الورشة)': {
    AppLanguage.arabic: 'داخلي (الورشة)',
    AppLanguage.french: 'Interne (Atelier)',
    AppLanguage.english: 'Internal (Workshop)',
  },
  'تحويل مباشر إلى الورشة': {
    AppLanguage.arabic: 'تحويل مباشر إلى الورشة',
    AppLanguage.french: 'Transfert direct vers l\'atelier',
    AppLanguage.english: 'Direct transfer to workshop',
  },
  'الإدارة العامة': {
    AppLanguage.arabic: 'الإدارة العامة',
    AppLanguage.french: 'Administration générale',
    AppLanguage.english: 'General Management',
  },
  'تطبيق الورشة': {
    AppLanguage.arabic: 'تطبيق الورشة',
    AppLanguage.french: 'Module Atelier',
    AppLanguage.english: 'Workshop Module',
  },
  'تطبيق محل بيع المواد': {
    AppLanguage.arabic: 'تطبيق محل بيع المواد',
    AppLanguage.french: 'Module Magasin de matériaux',
    AppLanguage.english: 'Materials Store Module',
  },
  'كل الأقسام': {
    AppLanguage.arabic: 'كل الأقسام',
    AppLanguage.french: 'Toutes les sections',
    AppLanguage.english: 'All Sections',
  },
  'تحويلات داخلية للورشة': {
    AppLanguage.arabic: 'تحويلات داخلية للورشة',
    AppLanguage.french: 'Transferts internes vers l\'atelier',
    AppLanguage.english: 'Internal Transfers to Workshop',
  },
  'تحويل داخلي إلى الورشة (مبيعات رقم ': {
    AppLanguage.arabic: 'تحويل داخلي إلى الورشة (مبيعات رقم ',
    AppLanguage.french: 'Transfert interne vers l\'atelier (Vente N° ',
    AppLanguage.english: 'Internal Transfer to Workshop (Sale #',
  },
  'استلام داخلي من المحل (مشتريات رقم ': {
    AppLanguage.arabic: 'استلام داخلي من المحل (مشتريات رقم ',
    AppLanguage.french: 'Réception interne du magasin (Achat N° ',
    AppLanguage.english: 'Internal Receipt from Store (Purchase #',
  },
  'مرتجع داخلي ملغى إلى المحل (مبيعات رقم ': {
    AppLanguage.arabic: 'مرتجع داخلي ملغى إلى المحل (مبيعات رقم ',
    AppLanguage.french: 'Retour interne annulé vers le magasin (Vente N° ',
    AppLanguage.english: 'Internal Return Reversal to Store (Sale #',
  },
  'إلغاء استلام من الورشة (مشتريات رقم ': {
    AppLanguage.arabic: 'إلغاء استلام من الورشة (مشتريات رقم ',
    AppLanguage.french: 'Annulation réception atelier (Achat N° ',
    AppLanguage.english: 'Workshop Receipt Cancellation (Purchase #',
  },
  'بيع مواد مباشر رقم ': {
    AppLanguage.arabic: 'بيع مواد مباشر رقم ',
    AppLanguage.french: 'Vente directe de matériaux N° ',
    AppLanguage.english: 'Direct Material Sale #',
  },
  'الورشة': {
    AppLanguage.arabic: 'الورشة',
    AppLanguage.french: 'Atelier',
    AppLanguage.english: 'Workshop',
  },
  'المحل': {
    AppLanguage.arabic: 'المحل',
    AppLanguage.french: 'Magasin',
    AppLanguage.english: 'Store',
  },
  'التقرير المالي الموحد للمؤسسة': {
    AppLanguage.arabic: 'التقرير المالي الموحد للمؤسسة',
    AppLanguage.french: 'Rapport financier consolidé de l\'entreprise',
    AppLanguage.english: 'Consolidated Enterprise Financial Report',
  },
  'فصل أرباح المحل والورشة واستبعاد الهامش الداخلي': {
    AppLanguage.arabic: 'فصل أرباح المحل والورشة واستبعاد الهامش الداخلي',
    AppLanguage.french:
        'Séparation magasin/atelier et élimination de la marge interne',
    AppLanguage.english:
        'Separate store & workshop profits with internal margin eliminated',
  },
  'النتيجة المجمعة للمؤسسة (بدون تحويلات داخلية)': {
    AppLanguage.arabic: 'النتيجة المجمعة للمؤسسة (بدون تحويلات داخلية)',
    AppLanguage.french:
        'Résultat consolidé de l\'entreprise (hors transferts internes)',
    AppLanguage.english:
        'Consolidated Enterprise Result (excl. internal transfers)',
  },
  'إجمالي إيراد المؤسسة الخارجي': {
    AppLanguage.arabic: 'إجمالي إيراد المؤسسة الخارجي',
    AppLanguage.french: 'Revenus externes totaux de l\'entreprise',
    AppLanguage.english: 'Total External Enterprise Revenue',
  },
  'التحصيل الفعلي (نقدًا)': {
    AppLanguage.arabic: 'التحصيل الفعلي (نقدًا)',
    AppLanguage.french: 'Encaissement effectif (liquidités)',
    AppLanguage.english: 'Actual Cash Collected',
  },
  'مشتريات خارجية فعلية': {
    AppLanguage.arabic: 'مشتريات خارجية فعلية',
    AppLanguage.french: 'Achats externes effectifs',
    AppLanguage.english: 'Actual External Purchases',
  },
  'صافي السيولة المجمعة': {
    AppLanguage.arabic: 'صافي السيولة المجمعة',
    AppLanguage.french: 'Flux de trésorerie net consolidé',
    AppLanguage.english: 'Consolidated Net Cash Flow',
  },
  'تم استبعاد تحويلات داخلية بقيمة': {
    AppLanguage.arabic: 'تم استبعاد تحويلات داخلية بقيمة',
    AppLanguage.french: 'Transferts internes éliminés pour un montant de',
    AppLanguage.english: 'Internal transfers eliminated in amount of',
  },
  'منعاً لاحتساب أرباح وهمية قبل البيع للزبون النهائي.': {
    AppLanguage.arabic: 'منعاً لاحتساب أرباح وهمية قبل البيع للزبون النهائي.',
    AppLanguage.french:
        'pour éviter la comptabilisation de profits fictifs avant la vente finale.',
    AppLanguage.english:
        'to prevent unrealized internal profits prior to external sale.',
  },
  'نشاط محل بيع المواد المستقل': {
    AppLanguage.arabic: 'نشاط محل بيع المواد المستقل',
    AppLanguage.french: 'Activité magasin de matériaux autonome',
    AppLanguage.english: 'Autonomous Materials Store Activity',
  },
  'مبيعات الزبائن الخارجيين': {
    AppLanguage.arabic: 'مبيعات الزبائن الخارجيين',
    AppLanguage.french: 'Ventes clients externes',
    AppLanguage.english: 'External Client Sales',
  },
  'المدفوع من الزبائن': {
    AppLanguage.arabic: 'المدفوع من الزبائن',
    AppLanguage.french: 'Encaissé des clients',
    AppLanguage.english: 'Paid by Clients',
  },
  'ديون الزبائن للمحل': {
    AppLanguage.arabic: 'ديون الزبائن للمحل',
    AppLanguage.french: 'Créances clients magasin',
    AppLanguage.english: 'Store Client Receivables',
  },
  'مشتريات المحل من الموردين': {
    AppLanguage.arabic: 'مشتريات المحل من الموردين',
    AppLanguage.french: 'Achats magasin auprès des fournisseurs',
    AppLanguage.english: 'Store Purchases from Suppliers',
  },
  'تحويلات داخلية للورشة (بسعر التحويل)': {
    AppLanguage.arabic: 'تحويلات داخلية للورشة (بسعر التحويل)',
    AppLanguage.french: 'Transferts internes vers l\'atelier (prix de cession)',
    AppLanguage.english: 'Internal Transfers to Workshop (Transfer Price)',
  },
  'نشاط ورشة النجارة والتصنيع': {
    AppLanguage.arabic: 'نشاط ورشة النجارة والتصنيع',
    AppLanguage.french: 'Activité atelier de fabrication',
    AppLanguage.english: 'Workshop Manufacturing Activity',
  },
  'إجمالي قيمة طلبيات النوافذ': {
    AppLanguage.arabic: 'إجمالي قيمة طلبيات النوافذ',
    AppLanguage.french: 'Chiffre d\'affaires commandes menuiserie',
    AppLanguage.english: 'Total Window Orders Turnover',
  },
  'المقبوضات والعربونات من العملاء': {
    AppLanguage.arabic: 'المقبوضات والعربونات من العملاء',
    AppLanguage.french: 'Acomptes et encaissements clients',
    AppLanguage.english: 'Client Advances & Collections',
  },
  'المتبقي بذمة عملاء الطلبيات': {
    AppLanguage.arabic: 'المتبقي بذمة عملاء الطلبيات',
    AppLanguage.french: 'Créances restantes sur commandes',
    AppLanguage.english: 'Remaining Receivables on Orders',
  },
  'مشتريات الورشة المباشرة من الموردين': {
    AppLanguage.arabic: 'مشتريات الورشة المباشرة من الموردين',
    AppLanguage.french: 'Achats directs atelier auprès des fournisseurs',
    AppLanguage.english: 'Direct Workshop Purchases from Suppliers',
  },
  'استلام مواد داخلي من المحل': {
    AppLanguage.arabic: 'استلام مواد داخلي من المحل',
    AppLanguage.french: 'Réceptions internes en provenance du magasin',
    AppLanguage.english: 'Internal Receipts from Store',
  },
  'إرجاع المواد وإلغاء التحويل': {
    AppLanguage.arabic: 'إرجاع المواد وإلغاء التحويل',
    AppLanguage.french: 'Retourner les articles et annuler le transfert',
    AppLanguage.english: 'Return items and cancel transfer',
  },
  'إلغاء التحويل الداخلي': {
    AppLanguage.arabic: 'إلغاء التحويل الداخلي',
    AppLanguage.french: 'Annuler le transfert interne',
    AppLanguage.english: 'Cancel internal transfer',
  },
  'هل أنت متأكد من إلغاء هذا التحويل الداخلي؟ سيتم إرجاع المواد من مستودع الورشة إلى مستودع المحل وتوثيق حركة عكسية دون حذف السجل التاريخي.': {
    AppLanguage.arabic:
        'هل أنت متأكد من إلغاء هذا التحويل الداخلي؟ سيتم إرجاع المواد من مستودع الورشة إلى مستودع المحل وتوثيق حركة عكسية دون حذف السجل التاريخي.',
    AppLanguage.french:
        'Êtes-vous sûr d\'annuler ce transfert interne ? Les articles seront retournés du stock atelier vers le magasin avec écriture d\'extourne sans supprimer l\'historique.',
    AppLanguage.english:
        'Are you sure you want to cancel this internal transfer? Items will be returned from workshop stock to store stock with counter-entries without deleting history.',
  },
  'تأكيد الإرجاع للمحل': {
    AppLanguage.arabic: 'تأكيد الإرجاع للمحل',
    AppLanguage.french: 'Confirmer le retour au magasin',
    AppLanguage.english: 'Confirm return to store',
  },
  'تم إرجاع المواد وإلغاء التحويل الداخلي بنجاح': {
    AppLanguage.arabic: 'تم إرجاع المواد وإلغاء التحويل الداخلي بنجاح',
    AppLanguage.french:
        'Articles retournés et transfert interne annulé avec succès',
    AppLanguage.english:
        'Items returned and internal transfer cancelled successfully',
  },
  'خطأ أثناء إلغاء التحويل': {
    AppLanguage.arabic: 'خطأ أثناء إلغاء التحويل',
    AppLanguage.french: 'Erreur lors de l\'annulation du transfert',
    AppLanguage.english: 'Error during transfer cancellation',
  },
  'مواد': {
    AppLanguage.arabic: 'مواد',
    AppLanguage.french: 'Matériaux',
    AppLanguage.english: 'Materials',
  },
  'نوافذ': {
    AppLanguage.arabic: 'نوافذ',
    AppLanguage.french: 'Fenêtres',
    AppLanguage.english: 'Windows',
  },
  'إظهار زبائن النوافذ أيضًا': {
    AppLanguage.arabic: 'إظهار زبائن النوافذ أيضًا',
    AppLanguage.french: 'Afficher aussi les clients fenêtres',
    AppLanguage.english: 'Also show window clients',
  },
  'زبون مواد جديد': {
    AppLanguage.arabic: 'زبون مواد جديد',
    AppLanguage.french: 'Nouveau client matériaux',
    AppLanguage.english: 'New materials client',
  },
  'إضافة زبون مواد جديد': {
    AppLanguage.arabic: 'إضافة زبون مواد جديد',
    AppLanguage.french: 'Ajouter un nouveau client matériaux',
    AppLanguage.english: 'Add new materials client',
  },
  'الورشة (داخلي)': {
    AppLanguage.arabic: 'الورشة (داخلي)',
    AppLanguage.french: 'Atelier (interne)',
    AppLanguage.english: 'Workshop (internal)',
  },
  'زبون عام': {
    AppLanguage.arabic: 'زبون عام',
    AppLanguage.french: 'Client divers',
    AppLanguage.english: 'General customer',
  },

  // ── مفاتيح القائمة الجانبية (Canvas Pills) ──────────────────────────────
  'حائط': {
    AppLanguage.arabic: 'حائط',
    AppLanguage.french: 'Mur',
    AppLanguage.english: 'Wall',
  },
  'نفق': {
    AppLanguage.arabic: 'نفق',
    AppLanguage.french: 'Tunnel',
    AppLanguage.english: 'Tunnel',
  },
  'الخصائص': {
    AppLanguage.arabic: 'الخصائص',
    AppLanguage.french: 'Propriétés',
    AppLanguage.english: 'Properties',
  },
  'تفعيل أو إلغاء الحائط': {
    AppLanguage.arabic: 'تفعيل أو إلغاء الحائط',
    AppLanguage.french: 'Activer / désactiver le mur',
    AppLanguage.english: 'Toggle wall',
  },
  'تفعيل أو إلغاء صندوق النفق': {
    AppLanguage.arabic: 'تفعيل أو إلغاء صندوق النفق',
    AppLanguage.french: 'Activer / désactiver le caisson tunnel',
    AppLanguage.english: 'Toggle tunnel box',
  },
  'تفعيل أو إلغاء الغطاء الجانبي': {
    AppLanguage.arabic: 'تفعيل أو إلغاء الغطاء الجانبي',
    AppLanguage.french: 'Activer / désactiver le couvre-joint',
    AppLanguage.english: 'Toggle side cover',
  },
  'تبديل جهة عرض النافذة': {
    AppLanguage.arabic: 'تبديل جهة عرض النافذة',
    AppLanguage.french: 'Basculer vue interne / externe',
    AppLanguage.english: 'Toggle inner / outer view',
  },
  'تفعيل أو إلغاء الإطار السفلي': {
    AppLanguage.arabic: 'تفعيل أو إلغاء الإطار السفلي',
    AppLanguage.french: 'Activer / désactiver le cadre bas',
    AppLanguage.english: 'Toggle bottom frame',
  },
  'فتح لوحة الخصائص': {
    AppLanguage.arabic: 'فتح لوحة الخصائص',
    AppLanguage.french: 'Ouvrir les propriétés',
    AppLanguage.english: 'Open properties panel',
  },
  'تفعيل أو إلغاء الستار على النافذة': {
    AppLanguage.arabic: 'تفعيل أو إلغاء الستار على النافذة',
    AppLanguage.french: 'Activer / désactiver le volet',
    AppLanguage.english: 'Toggle window shutter',
  },
  'الإجراءات': {
    AppLanguage.arabic: 'الإجراءات',
    AppLanguage.french: 'Actions',
    AppLanguage.english: 'Actions',
  },
  'التسوية اليومية': {
    AppLanguage.arabic: 'التسوية اليومية',
    AppLanguage.french: 'Règlement journalier',
    AppLanguage.english: 'Daily reconciliation',
  },
  'المصروفات': {
    AppLanguage.arabic: 'المصروفات',
    AppLanguage.french: 'Dépenses',
    AppLanguage.english: 'Expenses',
  },
  'المقبوضات': {
    AppLanguage.arabic: 'المقبوضات',
    AppLanguage.french: 'Encaissements',
    AppLanguage.english: 'Receipts',
  },
  'الرصيد المتوقع': {
    AppLanguage.arabic: 'الرصيد المتوقع',
    AppLanguage.french: 'Solde attendu',
    AppLanguage.english: 'Expected balance',
  },
  'النقد المحسوب فعلياً': {
    AppLanguage.arabic: 'النقد المحسوب فعلياً',
    AppLanguage.french: 'Espèces réellement comptées',
    AppLanguage.english: 'Actual cash counted',
  },
  'إغلاق اليوم': {
    AppLanguage.arabic: 'إغلاق اليوم',
    AppLanguage.french: 'Clôturer la journée',
    AppLanguage.english: 'Close business day',
  },
  'تم حفظ التسوية اليومية في السجل': {
    AppLanguage.arabic: 'تم حفظ التسوية اليومية في السجل',
    AppLanguage.french: 'Le règlement journalier a été enregistré',
    AppLanguage.english: 'Daily reconciliation was saved to the log',
  },
  'الإرجاع': {
    AppLanguage.arabic: 'الإرجاع',
    AppLanguage.french: 'Retours',
    AppLanguage.english: 'Returns',
  },
  'إرجاع إلى المخزون': {
    AppLanguage.arabic: 'إرجاع إلى المخزون',
    AppLanguage.french: 'Retour au stock',
    AppLanguage.english: 'Return to stock',
  },
  'إرجاع من الزبون إلى المخزون': {
    AppLanguage.arabic: 'إرجاع من الزبون إلى المخزون',
    AppLanguage.french: 'Retour client vers le stock',
    AppLanguage.english: 'Customer return to stock',
  },
  'اختر وثيقة البيع': {
    AppLanguage.arabic: 'اختر وثيقة البيع',
    AppLanguage.french: 'Choisir le document de vente',
    AppLanguage.english: 'Select sales document',
  },
  'أسعار الشراء تُطبَّق تلقائياً على جدول الكمية والتكلفة': {
    AppLanguage.arabic: 'أسعار الشراء تُطبَّق تلقائياً على جدول الكمية والتكلفة',
    AppLanguage.french: 'Les prix d\'achat sont appliqués automatiquement au tableau des quantités et coûts',
    AppLanguage.english: 'Purchase prices are applied automatically to the quantity and cost table',
  },
  'عند كل شراء يصبح السعر هو المتوسط المرجّح بين المخزون الحالي والكمية الجديدة، وإذا كان المخزون صفراً يُعتمد سعر الشراء الجديد مباشرة. يظهر آخر سعر شراء في الفاتورة ويمكن تعديله.': {
    AppLanguage.arabic: 'عند كل شراء يصبح السعر هو المتوسط المرجّح بين المخزون الحالي والكمية الجديدة، وإذا كان المخزون صفراً يُعتمد سعر الشراء الجديد مباشرة. يظهر آخر سعر شراء في الفاتورة ويمكن تعديله.',
    AppLanguage.french: 'À chaque achat, le prix devient le coût moyen pondéré entre le stock actuel et la nouvelle quantité ; si le stock est nul, le nouveau prix d\'achat est retenu directement. Le dernier prix d\'achat est proposé dans la facture et reste modifiable.',
    AppLanguage.english: 'On each purchase the price becomes the weighted average of the current stock and the new quantity; with no stock, the new purchase price is used directly. The last purchase price is suggested on the invoice and can be edited.',
  },
  'تطبيق أسعار الشراء على جدول الكمية والتكلفة': {
    AppLanguage.arabic: 'تطبيق أسعار الشراء على جدول الكمية والتكلفة',
    AppLanguage.french: 'Appliquer les prix d\'achat au tableau des quantités et coûts',
    AppLanguage.english: 'Apply purchase prices to quantity and cost table',
  },
  'يظهر آخر سعر شراء في الفاتورة دائماً، ويُحتسب في جدول التكلفة عند التفعيل فقط': {
    AppLanguage.arabic: 'يظهر آخر سعر شراء في الفاتورة دائماً، ويُحتسب في جدول التكلفة عند التفعيل فقط',
    AppLanguage.french: 'Le dernier prix d\'achat apparaît toujours sur la facture, et n\'est calculé dans le tableau des coûts que s\'il est activé',
    AppLanguage.english: 'The latest purchase price is always shown on the invoice, and only calculated in the cost table when enabled',
  },
};
