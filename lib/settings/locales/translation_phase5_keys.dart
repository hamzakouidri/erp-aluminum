import '../app_settings.dart';

/// UI strings found during the direct-Arabic audit.  Keep these keys in a
/// separate phase so the remaining screens can be migrated without changing
/// the existing translation tables.
const Map<String, Map<AppLanguage, String>> translationPhase5Keys = {
  'فشل حفظ الطلبية': {
    AppLanguage.arabic: 'فشل حفظ الطلبية',
    AppLanguage.french: 'Échec de l’enregistrement de la commande',
    AppLanguage.english: 'Failed to save the order',
  },
  'بنجاح': {
    AppLanguage.arabic: 'بنجاح',
    AppLanguage.french: 'avec succès',
    AppLanguage.english: 'successfully',
  },
  'الطلبية لم تعد موجودة في قاعدة البيانات.': {
    AppLanguage.arabic: 'الطلبية لم تعد موجودة في قاعدة البيانات.',
    AppLanguage.french: 'La commande n’existe plus dans la base de données.',
    AppLanguage.english: 'The order no longer exists in the database.',
  },
  'تم حذف الطلبية بنجاح.': {
    AppLanguage.arabic: 'تم حذف الطلبية بنجاح.',
    AppLanguage.french: 'La commande a été supprimée avec succès.',
    AppLanguage.english: 'The order was deleted successfully.',
  },
  'تعذر حذف الطلبية:': {
    AppLanguage.arabic: 'تعذر حذف الطلبية:',
    AppLanguage.french: 'Impossible de supprimer la commande :',
    AppLanguage.english: 'Could not delete the order:',
  },
  'حدد عنصرًا واحدًا على الأقل لتطبيق': {
    AppLanguage.arabic: 'حدد عنصرًا واحدًا على الأقل لتطبيق',
    AppLanguage.french: 'Sélectionnez au moins un élément à appliquer pour',
    AppLanguage.english: 'Select at least one item to apply',
  },
  'تعذر تطبيق التخصيص:': {
    AppLanguage.arabic: 'تعذر تطبيق التخصيص:',
    AppLanguage.french: 'Impossible d’appliquer la personnalisation :',
    AppLanguage.english: 'Could not apply customization:',
  },
  'تم تغيير اللون لـ': {
    AppLanguage.arabic: 'تم تغيير اللون لـ',
    AppLanguage.french: 'La couleur a été modifiée pour',
    AppLanguage.english: 'Color changed for',
  },
  'تم تغيير السلسلة لـ': {
    AppLanguage.arabic: 'تم تغيير السلسلة لـ',
    AppLanguage.french: 'La gamme a été modifiée pour',
    AppLanguage.english: 'Series changed for',
  },
  'تم تغيير الزجاج لـ': {
    AppLanguage.arabic: 'تم تغيير الزجاج لـ',
    AppLanguage.french: 'Le vitrage a été modifié pour',
    AppLanguage.english: 'Glass changed for',
  },
  'تحديد الكل': {
    AppLanguage.arabic: 'تحديد الكل',
    AppLanguage.french: 'Tout sélectionner',
    AppLanguage.english: 'Select all',
  },
  'تم تحديد': {
    AppLanguage.arabic: 'تم تحديد',
    AppLanguage.french: 'Sélectionné :',
    AppLanguage.english: 'Selected:',
  },
  'خطأ أثناء توليد الفاتورة': {
    AppLanguage.arabic: 'خطأ أثناء توليد الفاتورة',
    AppLanguage.french: 'Erreur lors de la génération de la facture',
    AppLanguage.english: 'Error generating the invoice',
  },
  'خطأ أثناء توليد المستند': {
    AppLanguage.arabic: 'خطأ أثناء توليد المستند',
    AppLanguage.french: 'Erreur lors de la génération du document',
    AppLanguage.english: 'Error generating the document',
  },
  'خطأ أثناء توليد ملف الصور:': {
    AppLanguage.arabic: 'خطأ أثناء توليد ملف الصور:',
    AppLanguage.french: 'Erreur lors de la génération du fichier image :',
    AppLanguage.english: 'Error generating the image file:',
  },
  'فشل توليد ملف PDF': {
    AppLanguage.arabic: 'فشل توليد ملف PDF',
    AppLanguage.french: 'Échec de la génération du fichier PDF',
    AppLanguage.english: 'Failed to generate the PDF file',
  },
  'فريق العمل': {
    AppLanguage.arabic: 'فريق العمل',
    AppLanguage.french: 'Équipe de travail',
    AppLanguage.english: 'Team',
  },
  'الطلبات والمبيعات': {
    AppLanguage.arabic: 'الطلبات والمبيعات',
    AppLanguage.french: 'Commandes et ventes',
    AppLanguage.english: 'Orders and sales',
  },
  'المخزون والمنتجات': {
    AppLanguage.arabic: 'المخزون والمنتجات',
    AppLanguage.french: 'Stock et produits',
    AppLanguage.english: 'Inventory and products',
  },
  'الصندوق والحسابات': {
    AppLanguage.arabic: 'الصندوق والحسابات',
    AppLanguage.french: 'Caisse et comptes',
    AppLanguage.english: 'Cashbox and accounts',
  },
  'الجلسة مغلقة - اضغط لتسجيل الدخول': {
    AppLanguage.arabic: 'الجلسة مغلقة - اضغط لتسجيل الدخول',
    AppLanguage.french: 'Session fermée – cliquez pour vous connecter',
    AppLanguage.english: 'Session closed – click to sign in',
  },
  'جلسة الورشة': {
    AppLanguage.arabic: 'جلسة الورشة',
    AppLanguage.french: 'Session de l’atelier',
    AppLanguage.english: 'Workshop session',
  },
  'سجّل جلسة Supabase مرة واحدة عند الحاجة، وبعدها تعمل المزامنة تلقائياً في الخلفية.': {
    AppLanguage.arabic:
        'سجّل جلسة Supabase مرة واحدة عند الحاجة، وبعدها تعمل المزامنة تلقائياً في الخلفية.',
    AppLanguage.french:
        'Connectez la session Supabase une seule fois si nécessaire ; la synchronisation fonctionnera ensuite automatiquement en arrière-plan.',
    AppLanguage.english:
        'Sign in to the Supabase session once when needed; synchronization will then run automatically in the background.',
  },
  'جلسة الورشة مسجلة': {
    AppLanguage.arabic: 'جلسة الورشة مسجلة',
    AppLanguage.french: 'Session de l’atelier enregistrée',
    AppLanguage.english: 'Workshop session registered',
  },
  'تسجيل جلسة الورشة': {
    AppLanguage.arabic: 'تسجيل جلسة الورشة',
    AppLanguage.french: 'Enregistrer la session de l’atelier',
    AppLanguage.english: 'Register workshop session',
  },
  'تم تسجيل جلسة الورشة. ستتم المزامنة تلقائياً في الخلفية.': {
    AppLanguage.arabic:
        'تم تسجيل جلسة الورشة. ستتم المزامنة تلقائياً في الخلفية.',
    AppLanguage.french:
        'La session de l’atelier est enregistrée. La synchronisation fonctionnera automatiquement en arrière-plan.',
    AppLanguage.english:
        'The workshop session is registered. Synchronization will run automatically in the background.',
  },
  'إظهار القائمة': {
    AppLanguage.arabic: 'إظهار القائمة',
    AppLanguage.french: 'Afficher le menu',
    AppLanguage.english: 'Show menu',
  },
  'الإعدادات والإدارة': {
    AppLanguage.arabic: 'الإعدادات والإدارة',
    AppLanguage.french: 'Paramètres et gestion',
    AppLanguage.english: 'Settings and management',
  },
  'تأكيد الحذف': {
    AppLanguage.arabic: 'تأكيد الحذف',
    AppLanguage.french: 'Confirmation de suppression',
    AppLanguage.english: 'Confirm deletion',
  },
  'لا يمكن الحذف': {
    AppLanguage.arabic: 'لا يمكن الحذف',
    AppLanguage.french: 'Suppression impossible',
    AppLanguage.english: 'Cannot delete',
  },
  'غير مصرح': {
    AppLanguage.arabic: 'غير مصرح',
    AppLanguage.french: 'Non autorisé',
    AppLanguage.english: 'Not authorized',
  },
  'الحد الأقصى هو 3 طلبيات مفتوحة.': {
    AppLanguage.arabic: 'الحد الأقصى هو 3 طلبيات مفتوحة.',
    AppLanguage.french: 'Le maximum est de 3 commandes ouvertes.',
    AppLanguage.english: 'The maximum is 3 open orders.',
  },
  'إغلاق الطلبية؟': {
    AppLanguage.arabic: 'إغلاق الطلبية؟',
    AppLanguage.french: 'Fermer la commande ?',
    AppLanguage.english: 'Close the order?',
  },
  'أي تعديلات لم تُحفظ في هذه الطلبية ستُفقد.': {
    AppLanguage.arabic: 'أي تعديلات لم تُحفظ في هذه الطلبية ستُفقد.',
    AppLanguage.french: 'Toute modification non enregistrée sera perdue.',
    AppLanguage.english: 'Any unsaved changes to this order will be lost.',
  },
  'فتح طلبية محفوظة': {
    AppLanguage.arabic: 'فتح طلبية محفوظة',
    AppLanguage.french: 'Ouvrir une commande enregistrée',
    AppLanguage.english: 'Open saved order',
  },
  'الطلبيات المفتوحة': {
    AppLanguage.arabic: 'الطلبيات المفتوحة',
    AppLanguage.french: 'Commandes ouvertes',
    AppLanguage.english: 'Open orders',
  },
  'طلبية جديدة': {
    AppLanguage.arabic: 'طلبية جديدة',
    AppLanguage.french: 'Nouvelle commande',
    AppLanguage.english: 'New order',
  },
  'الحد الأقصى:': {
    AppLanguage.arabic: 'الحد الأقصى:',
    AppLanguage.french: 'Maximum :',
    AppLanguage.english: 'Maximum:',
  },
  'طلبية': {
    AppLanguage.arabic: 'طلبية',
    AppLanguage.french: 'Commande',
    AppLanguage.english: 'Order',
  },
  'إضافة مستودع': {
    AppLanguage.arabic: 'إضافة مستودع',
    AppLanguage.french: 'Ajouter un dépôt',
    AppLanguage.english: 'Add warehouse',
  },
  'اسم المستودع': {
    AppLanguage.arabic: 'اسم المستودع',
    AppLanguage.french: 'Nom du dépôt',
    AppLanguage.english: 'Warehouse name',
  },
  'مثال: مستودع المواد الجاهزة': {
    AppLanguage.arabic: 'مثال: مستودع المواد الجاهزة',
    AppLanguage.french: 'Exemple : dépôt des produits finis',
    AppLanguage.english: 'Example: finished-goods warehouse',
  },
  'نوع الزجاج': {
    AppLanguage.arabic: 'نوع الزجاج',
    AppLanguage.french: 'Type de vitrage',
    AppLanguage.english: 'Glass type',
  },
  'معالجة الوجه الخارجي': {
    AppLanguage.arabic: 'معالجة الوجه الخارجي',
    AppLanguage.french: 'Traitement de la face extérieure',
    AppLanguage.english: 'Outer-face treatment',
  },
  'نوع الوجه الخارجي': {
    AppLanguage.arabic: 'نوع الوجه الخارجي',
    AppLanguage.french: 'Type de face extérieure',
    AppLanguage.english: 'Outer-face type',
  },
  'لون الوجه الخارجي': {
    AppLanguage.arabic: 'لون الوجه الخارجي',
    AppLanguage.french: 'Couleur de la face extérieure',
    AppLanguage.english: 'Outer-face color',
  },
  'معالجة الوجه الداخلي': {
    AppLanguage.arabic: 'معالجة الوجه الداخلي',
    AppLanguage.french: 'Traitement de la face intérieure',
    AppLanguage.english: 'Inner-face treatment',
  },
  'نوع الوجه الداخلي': {
    AppLanguage.arabic: 'نوع الوجه الداخلي',
    AppLanguage.french: 'Type de face intérieure',
    AppLanguage.english: 'Inner-face type',
  },
  'لون الوجه الداخلي': {
    AppLanguage.arabic: 'لون الوجه الداخلي',
    AppLanguage.french: 'Couleur de la face intérieure',
    AppLanguage.english: 'Inner-face color',
  },
  'فريق التنفيذ': {
    AppLanguage.arabic: 'فريق التنفيذ',
    AppLanguage.french: 'Équipe d’exécution',
    AppLanguage.english: 'Execution team',
  },
  'لا يوجد مستخدمون مسجلون في ورشتك بعد.': {
    AppLanguage.arabic: 'لا يوجد مستخدمون مسجلون في ورشتك بعد.',
    AppLanguage.french:
        'Aucun utilisateur n’est encore enregistré dans votre atelier.',
    AppLanguage.english: 'No users are registered in your workshop yet.',
  },
  'خطأ في الحفظ:': {
    AppLanguage.arabic: 'خطأ في الحفظ:',
    AppLanguage.french: 'Erreur lors de l’enregistrement :',
    AppLanguage.english: 'Error while saving:',
  },
  'تعديل معلومات المستخدم': {
    AppLanguage.arabic: 'تعديل معلومات المستخدم',
    AppLanguage.french: 'Modifier les informations de l’utilisateur',
    AppLanguage.english: 'Edit user information',
  },
  'حفظ المعلومات': {
    AppLanguage.arabic: 'حفظ المعلومات',
    AppLanguage.french: 'Enregistrer les informations',
    AppLanguage.english: 'Save information',
  },
  'مثال: ألمنيوم، زجاج، بي في سي...': {
    AppLanguage.arabic: 'مثال: ألمنيوم، زجاج، بي في سي...',
    AppLanguage.french: 'Exemple : aluminium, verre, PVC…',
    AppLanguage.english: 'Example: aluminium, glass, PVC…',
  },
  'مثال: 5': {
    AppLanguage.arabic: 'مثال: 5',
    AppLanguage.french: 'Exemple : 5',
    AppLanguage.english: 'Example: 5',
  },
  'زجاج ثابت (Fixe)': {
    AppLanguage.arabic: 'زجاج ثابت (Fixe)',
    AppLanguage.french: 'Vitrage fixe (Fixe)',
    AppLanguage.english: 'Fixed glass (Fixe)',
  },
  'ضلفة عادية (Ouvrant Simple)': {
    AppLanguage.arabic: 'ضلفة عادية (Ouvrant Simple)',
    AppLanguage.french: 'Ouvrant simple',
    AppLanguage.english: 'Single sash',
  },
  'ضلفة فرنسية مزدوجة (Double Ouvrant)': {
    AppLanguage.arabic: 'ضلفة فرنسية مزدوجة (Double Ouvrant)',
    AppLanguage.french: 'Double ouvrant',
    AppLanguage.english: 'Double sash',
  },
  'منزلق 2 ضلف (Coulissant 2 Vantaux)': {
    AppLanguage.arabic: 'منزلق 2 ضلف (Coulissant 2 Vantaux)',
    AppLanguage.french: 'Coulissant 2 vantaux',
    AppLanguage.english: '2-sash sliding',
  },
  'منزلق 3 ضلف (Coulissant 3 Vantaux)': {
    AppLanguage.arabic: 'منزلق 3 ضلف (Coulissant 3 Vantaux)',
    AppLanguage.french: 'Coulissant 3 vantaux',
    AppLanguage.english: '3-sash sliding',
  },
  'منزلق 4 ضلف (Coulissant 4 Vantaux)': {
    AppLanguage.arabic: 'منزلق 4 ضلف (Coulissant 4 Vantaux)',
    AppLanguage.french: 'Coulissant 4 vantaux',
    AppLanguage.english: '4-sash sliding',
  },
  'تفريغ (Vide)': {
    AppLanguage.arabic: 'تفريغ (Vide)',
    AppLanguage.french: 'Vide',
    AppLanguage.english: 'Empty',
  },
  'إضافة قاطع أفقي (+ Traverse)': {
    AppLanguage.arabic: 'إضافة قاطع أفقي (+ Traverse)',
    AppLanguage.french: 'Ajouter une traverse horizontale',
    AppLanguage.english: 'Add horizontal divider',
  },
  'إضافة قاطع عمودي (+ Montant)': {
    AppLanguage.arabic: 'إضافة قاطع عمودي (+ Montant)',
    AppLanguage.french: 'Ajouter un montant vertical',
    AppLanguage.english: 'Add vertical divider',
  },
  'مسح القواطع الداخلية': {
    AppLanguage.arabic: 'مسح القواطع الداخلية',
    AppLanguage.french: 'Effacer les séparations intérieures',
    AppLanguage.english: 'Clear inner dividers',
  },
  'حزام (Sangle)': {
    AppLanguage.arabic: 'حزام (Sangle)',
    AppLanguage.french: 'Sangle',
    AppLanguage.english: 'Strap',
  },
  'منايفال (Manivelle)': {
    AppLanguage.arabic: 'منايفال (Manivelle)',
    AppLanguage.french: 'Manivelle',
    AppLanguage.english: 'Crank handle',
  },
  'قاطعة (Interrupteur)': {
    AppLanguage.arabic: 'قاطعة (Interrupteur)',
    AppLanguage.french: 'Interrupteur',
    AppLanguage.english: 'Switch',
  },
  'جهاز تحكم (Télécommande)': {
    AppLanguage.arabic: 'جهاز تحكم (Télécommande)',
    AppLanguage.french: 'Télécommande',
    AppLanguage.english: 'Remote control',
  },
  'حذف هذا الإطار': {
    AppLanguage.arabic: 'حذف هذا الإطار',
    AppLanguage.french: 'Supprimer ce cadre',
    AppLanguage.english: 'Delete this frame',
  },
  'تراجع (Undo)': {
    AppLanguage.arabic: 'تراجع (Undo)',
    AppLanguage.french: 'Annuler (Undo)',
    AppLanguage.english: 'Undo',
  },
  'إعادة (Redo)': {
    AppLanguage.arabic: 'إعادة (Redo)',
    AppLanguage.french: 'Rétablir (Redo)',
    AppLanguage.english: 'Redo',
  },
  '25 سم': {
    AppLanguage.arabic: '25 سم',
    AppLanguage.french: '25 cm',
    AppLanguage.english: '25 cm',
  },
  '30 سم': {
    AppLanguage.arabic: '30 سم',
    AppLanguage.french: '30 cm',
    AppLanguage.english: '30 cm',
  },
  '40 سم': {
    AppLanguage.arabic: '40 سم',
    AppLanguage.french: '40 cm',
    AppLanguage.english: '40 cm',
  },
  'تم تغيير تاريخ المشتريات': {
    AppLanguage.arabic: 'تم تغيير تاريخ المشتريات',
    AppLanguage.french: 'La date d’achat a été modifiée',
    AppLanguage.english: 'Purchase date changed',
  },
  'إغلاق القائمة': {
    AppLanguage.arabic: 'إغلاق القائمة',
    AppLanguage.french: 'Fermer le menu',
    AppLanguage.english: 'Close menu',
  },
  'فتح القائمة': {
    AppLanguage.arabic: 'فتح القائمة',
    AppLanguage.french: 'Ouvrir le menu',
    AppLanguage.english: 'Open menu',
  },
  'أدخل رقم CCP/RIP أولاً.': {
    AppLanguage.arabic: 'أدخل رقم CCP/RIP أولاً.',
    AppLanguage.french: 'Saisissez d’abord le numéro CCP/RIP.',
    AppLanguage.english: 'Enter the CCP/RIP number first.',
  },
  'تم حفظ رقم CCP/RIP. سيظهر للمستخدمين مباشرة.': {
    AppLanguage.arabic: 'تم حفظ رقم CCP/RIP. سيظهر للمستخدمين مباشرة.',
    AppLanguage.french:
        'Le numéro CCP/RIP est enregistré et sera visible immédiatement.',
    AppLanguage.english:
        'The CCP/RIP number was saved and will appear to users immediately.',
  },
  'تعذر حفظ رقم CCP/RIP:': {
    AppLanguage.arabic: 'تعذر حفظ رقم CCP/RIP:',
    AppLanguage.french: 'Impossible d’enregistrer le numéro CCP/RIP :',
    AppLanguage.english: 'Could not save the CCP/RIP number:',
  },
  'بيانات دفع الاشتراك': {
    AppLanguage.arabic: 'بيانات دفع الاشتراك',
    AppLanguage.french: 'Informations de paiement de l’abonnement',
    AppLanguage.english: 'Subscription payment details',
  },
  'ضع رقم الحساب البريدي الجاري الذي سيدفع إليه المشتركون. سيظهر لهم في مراجعة الاشتراك.': {
    AppLanguage.arabic:
        'ضع رقم الحساب البريدي الجاري الذي سيدفع إليه المشتركون. سيظهر لهم في مراجعة الاشتراك.',
    AppLanguage.french:
        'Saisissez le compte CCP sur lequel les abonnés effectueront le paiement. Il apparaîtra lors de la vérification de l’abonnement.',
    AppLanguage.english:
        'Enter the CCP account where subscribers will pay. It will appear during subscription review.',
  },
  'رقم CCP / RIP لـ BaridiMob': {
    AppLanguage.arabic: 'رقم CCP / RIP لـ BaridiMob',
    AppLanguage.french: 'Numéro CCP / RIP pour BaridiMob',
    AppLanguage.english: 'CCP / RIP number for BaridiMob',
  },
  'حفظ رقم الدفع': {
    AppLanguage.arabic: 'حفظ رقم الدفع',
    AppLanguage.french: 'Enregistrer le numéro de paiement',
    AppLanguage.english: 'Save payment number',
  },
  'تفعيل': {
    AppLanguage.arabic: 'تفعيل',
    AppLanguage.french: 'Activer',
    AppLanguage.english: 'Activate',
  },
  'الكل': {
    AppLanguage.arabic: 'الكل',
    AppLanguage.french: 'Tous',
    AppLanguage.english: 'All',
  },
  'منتهية / بحاجة تفعيل': {
    AppLanguage.arabic: 'منتهية / بحاجة تفعيل',
    AppLanguage.french: 'Expirées / à activer',
    AppLanguage.english: 'Expired / needs activation',
  },
  'فعّالة': {
    AppLanguage.arabic: 'فعّالة',
    AppLanguage.french: 'Actives',
    AppLanguage.english: 'Active',
  },
  'بحث بالاسم أو البريد الإلكتروني...': {
    AppLanguage.arabic: 'بحث بالاسم أو البريد الإلكتروني...',
    AppLanguage.french: 'Rechercher par nom ou e-mail...',
    AppLanguage.english: 'Search by name or email...',
  },
  'إدارة الحساب': {
    AppLanguage.arabic: 'إدارة الحساب',
    AppLanguage.french: 'Gérer le compte',
    AppLanguage.english: 'Manage account',
  },
  'إدارة:': {
    AppLanguage.arabic: 'إدارة:',
    AppLanguage.french: 'Gestion :',
    AppLanguage.english: 'Manage:',
  },
  'حد مستخدمي الورشة (يشمل مدير الورشة):': {
    AppLanguage.arabic: 'حد مستخدمي الورشة (يشمل مدير الورشة):',
    AppLanguage.french:
        'Limite d’utilisateurs de l’atelier (y compris le responsable) :',
    AppLanguage.english: 'Workshop user limit (including the manager):',
  },
  'حد أنظمة العمل:': {
    AppLanguage.arabic: 'حد أنظمة العمل:',
    AppLanguage.french: 'Limite des systèmes de travail :',
    AppLanguage.english: 'Work systems limit:',
  },
  'حد البروفيلات:': {
    AppLanguage.arabic: 'حد البروفيلات:',
    AppLanguage.french: 'Limite des profils :',
    AppLanguage.english: 'Profiles limit:',
  },
  'إعداد الاشتراك': {
    AppLanguage.arabic: 'إعداد الاشتراك',
    AppLanguage.french: 'Paramètres de l’abonnement',
    AppLanguage.english: 'Subscription settings',
  },
  '⏱ إعداد مدة الاشتراك وحد المستخدمين:': {
    AppLanguage.arabic: '⏱ إعداد مدة الاشتراك وحد المستخدمين:',
    AppLanguage.french: '⏱ Définir la durée et la limite d’utilisateurs :',
    AppLanguage.english: '⏱ Set subscription duration and user limit:',
  },
  'اختيار المدة وعدد المستخدمين': {
    AppLanguage.arabic: 'اختيار المدة وعدد المستخدمين',
    AppLanguage.french: 'Choisir la durée et le nombre d’utilisateurs',
    AppLanguage.english: 'Choose duration and number of users',
  },
  'مدة الاشتراك:': {
    AppLanguage.arabic: 'مدة الاشتراك:',
    AppLanguage.french: 'Durée de l’abonnement :',
    AppLanguage.english: 'Subscription duration:',
  },
  'عدد المستخدمين المسموح به (يشمل المدير):': {
    AppLanguage.arabic: 'عدد المستخدمين المسموح به (يشمل المدير):',
    AppLanguage.french:
        'Nombre d’utilisateurs autorisés (responsable inclus) :',
    AppLanguage.english: 'Allowed users (including the manager):',
  },
  'حفظ الاشتراك': {
    AppLanguage.arabic: 'حفظ الاشتراك',
    AppLanguage.french: 'Enregistrer l’abonnement',
    AppLanguage.english: 'Save subscription',
  },
  'يوم واحد': {
    AppLanguage.arabic: 'يوم واحد',
    AppLanguage.french: '1 jour',
    AppLanguage.english: '1 day',
  },
  'يومان': {
    AppLanguage.arabic: 'يومان',
    AppLanguage.french: '2 jours',
    AppLanguage.english: '2 days',
  },
  '3 أيام': {
    AppLanguage.arabic: '3 أيام',
    AppLanguage.french: '3 jours',
    AppLanguage.english: '3 days',
  },
  'أسبوع': {
    AppLanguage.arabic: 'أسبوع',
    AppLanguage.french: '1 semaine',
    AppLanguage.english: '1 week',
  },
  '15 يومًا': {
    AppLanguage.arabic: '15 يومًا',
    AppLanguage.french: '15 jours',
    AppLanguage.english: '15 days',
  },
  'شهر': {
    AppLanguage.arabic: 'شهر',
    AppLanguage.french: '1 mois',
    AppLanguage.english: '1 month',
  },
  'شهران': {
    AppLanguage.arabic: 'شهران',
    AppLanguage.french: '2 mois',
    AppLanguage.english: '2 months',
  },
  '6 أشهر': {
    AppLanguage.arabic: '6 أشهر',
    AppLanguage.french: '6 mois',
    AppLanguage.english: '6 months',
  },
  'سنة': {
    AppLanguage.arabic: 'سنة',
    AppLanguage.french: '1 an',
    AppLanguage.english: '1 year',
  },
  'لمدة {days} يومًا': {
    AppLanguage.arabic: 'لمدة {days} يومًا',
    AppLanguage.french: 'pour {days} jours',
    AppLanguage.english: 'for {days} days',
  },
  'تم حفظ اشتراك {email}: {duration}، الحد {users}': {
    AppLanguage.arabic: 'تم حفظ اشتراك {email}: {duration}، الحد {users}',
    AppLanguage.french:
        'Abonnement de {email} enregistré : {duration}, limite {users}',
    AppLanguage.english:
        'Subscription for {email} saved: {duration}, limit {users}',
  },
  'تم حفظ الاشتراك الدائم وحد المستخدمين.': {
    AppLanguage.arabic: 'تم حفظ الاشتراك الدائم وحد المستخدمين.',
    AppLanguage.french:
        'Abonnement permanent et limite d’utilisateurs enregistrés.',
    AppLanguage.english: 'Permanent subscription and user limit saved.',
  },
  'تم حفظ الاشتراك لمدة {days} يومًا وحد المستخدمين.': {
    AppLanguage.arabic: 'تم حفظ الاشتراك لمدة {days} يومًا وحد المستخدمين.',
    AppLanguage.french:
        'Abonnement de {days} jours et limite d’utilisateurs enregistrés.',
    AppLanguage.english: '{days}-day subscription and user limit saved.',
  },
  'مسح ورشة': {
    AppLanguage.arabic: 'مسح ورشة',
    AppLanguage.french: 'Supprimer l’atelier',
    AppLanguage.english: 'Delete workshop',
  },
  'وجميع مستخدميها؟ لا يمكن التراجع.': {
    AppLanguage.arabic: 'وجميع مستخدميها؟ لا يمكن التراجع.',
    AppLanguage.french:
        'et tous ses utilisateurs ? Cette action est irréversible.',
    AppLanguage.english: 'and all its users? This action cannot be undone.',
  },
  'مسح نهائي': {
    AppLanguage.arabic: 'مسح نهائي',
    AppLanguage.french: 'Supprimer définitivement',
    AppLanguage.english: 'Delete permanently',
  },
  'تجريبي – باقي {days} يوم 🟡': {
    AppLanguage.arabic: 'تجريبي – باقي {days} يوم 🟡',
    AppLanguage.french: 'Essai – il reste {days} jours 🟡',
    AppLanguage.english: 'Trial – {days} days remaining 🟡',
  },
  'منتهي منذ {days} يوم ❌': {
    AppLanguage.arabic: 'منتهي منذ {days} يوم ❌',
    AppLanguage.french: 'Expiré depuis {days} jours ❌',
    AppLanguage.english: 'Expired {days} days ago ❌',
  },
  'تجريبي منتهٍ (trialing) ❌': {
    AppLanguage.arabic: 'تجريبي منتهٍ (trialing) ❌',
    AppLanguage.french: 'Essai terminé (trialing) ❌',
    AppLanguage.english: 'Trial ended (trialing) ❌',
  },
  'منتهي الصلاحية ❌': {
    AppLanguage.arabic: 'منتهي الصلاحية ❌',
    AppLanguage.french: 'Abonnement expiré ❌',
    AppLanguage.english: 'Expired ❌',
  },
  'اشتراك مدفوع ✅': {
    AppLanguage.arabic: 'اشتراك مدفوع ✅',
    AppLanguage.french: 'Abonnement payé ✅',
    AppLanguage.english: 'Paid subscription ✅',
  },
  'غير مفعّل ❌': {
    AppLanguage.arabic: 'غير مفعّل ❌',
    AppLanguage.french: 'Non activé ❌',
    AppLanguage.english: 'Not active ❌',
  },
  'خطأ:': {
    AppLanguage.arabic: 'خطأ:',
    AppLanguage.french: 'Erreur :',
    AppLanguage.english: 'Error:',
  },
  '✅ تم تفعيل {email} لمدة {days} أيام': {
    AppLanguage.arabic: '✅ تم تفعيل {email} لمدة {days} أيام',
    AppLanguage.french: '✅ {email} activé pour {days} jours',
    AppLanguage.english: '✅ {email} activated for {days} days',
  },
  '✅ تم تفعيل {email} كاشتراك دائم': {
    AppLanguage.arabic: '✅ تم تفعيل {email} كاشتراك دائم',
    AppLanguage.french: '✅ {email} activé comme abonnement permanent',
    AppLanguage.english: '✅ {email} activated as a permanent subscription',
  },
  'تم سحب اشتراك {email}': {
    AppLanguage.arabic: 'تم سحب اشتراك {email}',
    AppLanguage.french: 'L’abonnement de {email} a été révoqué',
    AppLanguage.english: '{email}’s subscription was revoked',
  },
  'فُتح الحد الأقصى لورشة {email}': {
    AppLanguage.arabic: 'فُتح الحد الأقصى لورشة {email}',
    AppLanguage.french: 'La limite de l’atelier {email} est ouverte',
    AppLanguage.english: 'The limit for workshop {email} is now open',
  },
  'الحد الأقصى = {limit} مستخدمين لورشة {email}': {
    AppLanguage.arabic: 'الحد الأقصى = {limit} مستخدمين لورشة {email}',
    AppLanguage.french: 'Limite = {limit} utilisateurs pour l’atelier {email}',
    AppLanguage.english: 'Limit = {limit} users for workshop {email}',
  },
  'تم إلغاء حد {label} لورشة {email}': {
    AppLanguage.arabic: 'تم إلغاء حد {label} لورشة {email}',
    AppLanguage.french:
        'La limite {label} de l’atelier {email} a été supprimée',
    AppLanguage.english: 'The {label} limit for workshop {email} was removed',
  },
  'حد {label} = {limit} لورشة {email}': {
    AppLanguage.arabic: 'حد {label} = {limit} لورشة {email}',
    AppLanguage.french: 'Limite {label} = {limit} pour l’atelier {email}',
    AppLanguage.english: '{label} limit = {limit} for workshop {email}',
  },
  'خطأ في حفظ حد': {
    AppLanguage.arabic: 'خطأ في حفظ حد',
    AppLanguage.french: 'Erreur lors de l’enregistrement de la limite',
    AppLanguage.english: 'Error saving limit',
  },
  'تم مسح ورشة {email}': {
    AppLanguage.arabic: 'تم مسح ورشة {email}',
    AppLanguage.french: 'L’atelier {email} a été supprimé',
    AppLanguage.english: 'Workshop {email} was deleted',
  },
  '⏱ منح فترة تجريبية:': {
    AppLanguage.arabic: '⏱ منح فترة تجريبية:',
    AppLanguage.french: '⏱ Accorder une période d’essai :',
    AppLanguage.english: '⏱ Grant trial period:',
  },
  '{days} يوم': {
    AppLanguage.arabic: '{days} يوم',
    AppLanguage.french: '{days} jours',
    AppLanguage.english: '{days} days',
  },
  '{count} مستخدمين': {
    AppLanguage.arabic: '{count} مستخدمين',
    AppLanguage.french: '{count} utilisateurs',
    AppLanguage.english: '{count} users',
  },
  'حدث خطأ أثناء فحص الاشتراك:': {
    AppLanguage.arabic: 'حدث خطأ أثناء فحص الاشتراك:',
    AppLanguage.french:
        'Une erreur est survenue lors de la vérification de l’abonnement :',
    AppLanguage.english: 'An error occurred while checking the subscription:',
  },
  'خطأ: لم يتم العثور على بيانات الورشة.': {
    AppLanguage.arabic: 'خطأ: لم يتم العثور على بيانات الورشة.',
    AppLanguage.french: 'Erreur : les données de l’atelier sont introuvables.',
    AppLanguage.english: 'Error: workshop data was not found.',
  },
  'أسطر مخزون': {
    AppLanguage.arabic: 'أسطر مخزون',
    AppLanguage.french: 'Lignes de stock',
    AppLanguage.english: 'Inventory lines',
  },
  'إجراء': {
    AppLanguage.arabic: 'إجراء',
    AppLanguage.french: 'Action',
    AppLanguage.english: 'Action',
  },
  'إجمالي المدفوعات': {
    AppLanguage.arabic: 'إجمالي المدفوعات',
    AppLanguage.french: 'Total des paiements',
    AppLanguage.english: 'Total payments',
  },
  'إجمالي المرتجعات': {
    AppLanguage.arabic: 'إجمالي المرتجعات',
    AppLanguage.french: 'Total des retours',
    AppLanguage.english: 'Total returns',
  },
  'إلغاء تحديد الكل': {
    AppLanguage.arabic: 'إلغاء تحديد الكل',
    AppLanguage.french: 'Tout désélectionner',
    AppLanguage.english: 'Deselect all',
  },
  'إلى:': {
    AppLanguage.arabic: 'إلى:',
    AppLanguage.french: 'À :',
    AppLanguage.english: 'To:',
  },
  'اسم الدافع': {
    AppLanguage.arabic: 'اسم الدافع',
    AppLanguage.french: 'Nom du payeur',
    AppLanguage.english: 'Payer name',
  },
  'اسم السلسلة': {
    AppLanguage.arabic: 'اسم السلسلة',
    AppLanguage.french: 'Nom de la série',
    AppLanguage.english: 'Series name',
  },
  'اسم الغلق': {
    AppLanguage.arabic: 'اسم الغلق',
    AppLanguage.french: 'Nom de la fermeture',
    AppLanguage.english: 'Lock name',
  },
  'اسم القطعة الجانبية': {
    AppLanguage.arabic: 'اسم القطعة الجانبية',
    AppLanguage.french: 'Nom de la pièce latérale',
    AppLanguage.english: 'Side piece name',
  },
  'اسم لون الأكسيسوار': {
    AppLanguage.arabic: 'اسم لون الأكسيسوار',
    AppLanguage.french: 'Nom de la couleur de l’accessoire',
    AppLanguage.english: 'Accessory color name',
  },
  'اسم لون البروفيل': {
    AppLanguage.arabic: 'اسم لون البروفيل',
    AppLanguage.french: 'Nom de la couleur du profilé',
    AppLanguage.english: 'Profile color name',
  },
  'اسم لون الستار': {
    AppLanguage.arabic: 'اسم لون الستار',
    AppLanguage.french: 'Nom de la couleur du volet',
    AppLanguage.english: 'Shutter color name',
  },
  'اسم ميكانيزم الستار': {
    AppLanguage.arabic: 'اسم ميكانيزم الستار',
    AppLanguage.french: 'Nom du mécanisme du volet',
    AppLanguage.english: 'Shutter mechanism name',
  },
  'اعتماد': {
    AppLanguage.arabic: 'اعتماد',
    AppLanguage.french: 'Valider',
    AppLanguage.english: 'Approve',
  },
  'اعتماد الصرف': {
    AppLanguage.arabic: 'اعتماد الصرف',
    AppLanguage.french: 'Valider la sortie',
    AppLanguage.english: 'Approve issue',
  },
  'اعتماد صرف المخزون': {
    AppLanguage.arabic: 'اعتماد صرف المخزون',
    AppLanguage.french: 'Valider la sortie du stock',
    AppLanguage.english: 'Approve stock issue',
  },
  'الإطار محدد': {
    AppLanguage.arabic: 'الإطار محدد',
    AppLanguage.french: 'Cadre sélectionné',
    AppLanguage.english: 'Frame selected',
  },
  'البحث...': {
    AppLanguage.arabic: 'البحث...',
    AppLanguage.french: 'Rechercher...',
    AppLanguage.english: 'Search...',
  },
  'البيان / اسم الموديل': {
    AppLanguage.arabic: 'البيان / اسم الموديل',
    AppLanguage.french: 'Libellé / nom du modèle',
    AppLanguage.english: 'Description / model name',
  },
  'البيان / التفاصيل': {
    AppLanguage.arabic: 'البيان / التفاصيل',
    AppLanguage.french: 'Libellé / détails',
    AppLanguage.english: 'Description / details',
  },
  'الفضلات المتاحة': {
    AppLanguage.arabic: 'الفضلات المتاحة',
    AppLanguage.french: 'Chutes disponibles',
    AppLanguage.english: 'Available remnants',
  },
  'المهام والتنفيذ': {
    AppLanguage.arabic: 'المهام والتنفيذ',
    AppLanguage.french: 'Tâches et exécution',
    AppLanguage.english: 'Tasks and execution',
  },
  'الوحدة:': {
    AppLanguage.arabic: 'الوحدة:',
    AppLanguage.french: 'Unité :',
    AppLanguage.english: 'Unit:',
  },
  'انقر على ': {
    AppLanguage.arabic: 'انقر على ',
    AppLanguage.french: 'Cliquez sur ',
    AppLanguage.english: 'Click on ',
  },
  'تاريخ التصدير': {
    AppLanguage.arabic: 'تاريخ التصدير',
    AppLanguage.french: 'Date d’exportation',
    AppLanguage.english: 'Export date',
  },
  'تاريخ المشتريات': {
    AppLanguage.arabic: 'تاريخ المشتريات',
    AppLanguage.french: 'Date des achats',
    AppLanguage.english: 'Purchase date',
  },
  'تسجيل الدخول / فتح الجلسة': {
    AppLanguage.arabic: 'تسجيل الدخول / فتح الجلسة',
    AppLanguage.french: 'Connexion / ouvrir la session',
    AppLanguage.english: 'Sign in / open session',
  },
  'تطبيق جميع الخصائص معاً': {
    AppLanguage.arabic: 'تطبيق جميع الخصائص معاً',
    AppLanguage.french: 'Appliquer toutes les propriétés ensemble',
    AppLanguage.english: 'Apply all properties together',
  },
  'تطبيق على الكل': {
    AppLanguage.arabic: 'تطبيق على الكل',
    AppLanguage.french: 'Appliquer à tous',
    AppLanguage.english: 'Apply to all',
  },
  'تعديل الخصائص الموحدة لجميع العناصر (Bulk Edit)': {
    AppLanguage.arabic: 'تعديل الخصائص الموحدة لجميع العناصر (Bulk Edit)',
    AppLanguage.french:
        'Modifier les propriétés communes de tous les éléments (édition groupée)',
    AppLanguage.english: 'Edit shared properties for all items (Bulk Edit)',
  },
  'تفاصيل الزجاج / Vitrage': {
    AppLanguage.arabic: 'تفاصيل الزجاج / Vitrage',
    AppLanguage.french: 'Détails du vitrage',
    AppLanguage.english: 'Glass details',
  },
  'تفعيل تنبيه نفاد الكمية': {
    AppLanguage.arabic: 'تفعيل تنبيه نفاد الكمية',
    AppLanguage.french: 'Activer l’alerte de rupture de stock',
    AppLanguage.english: 'Enable low-stock alert',
  },
  'تم إيقاف': {
    AppLanguage.arabic: 'تم إيقاف',
    AppLanguage.french: 'Désactivé',
    AppLanguage.english: 'Disabled',
  },
  'تم اعتماد الصرف': {
    AppLanguage.arabic: 'تم اعتماد الصرف',
    AppLanguage.french: 'Sortie validée',
    AppLanguage.english: 'Issue approved',
  },
  'تم اعتماد صرف هذه الطلبية سابقاً.': {
    AppLanguage.arabic: 'تم اعتماد صرف هذه الطلبية سابقاً.',
    AppLanguage.french: 'La sortie de cette commande a déjà été validée.',
    AppLanguage.english: 'This order issue was already approved.',
  },
  'جار تجهيز الصور': {
    AppLanguage.arabic: 'جار تجهيز الصور',
    AppLanguage.french: 'Préparation des images',
    AppLanguage.english: 'Preparing images',
  },
  'حذف الإطار': {
    AppLanguage.arabic: 'حذف الإطار',
    AppLanguage.french: 'Supprimer le cadre',
    AppLanguage.english: 'Delete frame',
  },
  'حذف المنتج': {
    AppLanguage.arabic: 'حذف المنتج',
    AppLanguage.french: 'Supprimer le produit',
    AppLanguage.english: 'Delete product',
  },
  'دائن': {
    AppLanguage.arabic: 'دائن',
    AppLanguage.french: 'Crédit',
    AppLanguage.english: 'Credit',
  },
  'مدين': {
    AppLanguage.arabic: 'مدين',
    AppLanguage.french: 'Débit',
    AppLanguage.english: 'Debit',
  },
  'مشاركة / حفظ PDF': {
    AppLanguage.arabic: 'مشاركة / حفظ PDF',
    AppLanguage.french: 'Partager / enregistrer le PDF',
    AppLanguage.english: 'Share / save PDF',
  },
  'لا توجد صورة محفوظة لهذا العنصر': {
    AppLanguage.arabic: 'لا توجد صورة محفوظة لهذا العنصر',
    AppLanguage.french: 'Aucune image enregistrée pour cet élément',
    AppLanguage.english: 'No saved image for this item',
  },
  'لا توجد فضلات قابلة للاستعمال في هذا المخزون.': {
    AppLanguage.arabic: 'لا توجد فضلات قابلة للاستعمال في هذا المخزون.',
    AppLanguage.french: 'Aucune chute utilisable dans ce stock.',
    AppLanguage.english: 'No usable remnants in this inventory.',
  },
  'لا توجد كميات متاحة لاعتماد صرفها.': {
    AppLanguage.arabic: 'لا توجد كميات متاحة لاعتماد صرفها.',
    AppLanguage.french: 'Aucune quantité disponible à valider pour la sortie.',
    AppLanguage.english: 'No quantities available to approve for issue.',
  },
  'من:': {
    AppLanguage.arabic: 'من:',
    AppLanguage.french: 'De :',
    AppLanguage.english: 'From:',
  },
  'محدد': {
    AppLanguage.arabic: 'محدد',
    AppLanguage.french: 'Sélectionné',
    AppLanguage.english: 'Selected',
  },
  'نوع': {
    AppLanguage.arabic: 'نوع',
    AppLanguage.french: 'Type',
    AppLanguage.english: 'Type',
  },
  'منتج خاص': {
    AppLanguage.arabic: 'منتج خاص',
    AppLanguage.french: 'Produit spécial',
    AppLanguage.english: 'Special product',
  },
  'هل أنت متأكد أنك تريد حذف هذا المنتج؟': {
    AppLanguage.arabic: 'هل أنت متأكد أنك تريد حذف هذا المنتج؟',
    AppLanguage.french: 'Voulez-vous vraiment supprimer ce produit ?',
    AppLanguage.english: 'Are you sure you want to delete this product?',
  },
  'يرجى تحديد ألوان النظام أولاً من تبويب ': {
    AppLanguage.arabic: 'يرجى تحديد ألوان النظام أولاً من تبويب ',
    AppLanguage.french:
        'Veuillez d’abord sélectionner les couleurs du système dans l’onglet ',
    AppLanguage.english: 'Please select the system colors first from the tab ',
  },
  'اسم الإطار السفلي': {
    AppLanguage.arabic: 'اسم الإطار السفلي',
    AppLanguage.french: 'Nom du cadre inférieur',
    AppLanguage.english: 'Bottom frame name',
  },
  'اضبط اسم الخاصية وقيمتها واضغط ⚡ للتطبيق على الكل، أو استخدم الزر السفلي للكل:': {
    AppLanguage.arabic:
        'اضبط اسم الخاصية وقيمتها واضغط ⚡ للتطبيق على الكل، أو استخدم الزر السفلي للكل:',
    AppLanguage.french:
        'Définissez le nom et la valeur de la propriété puis appuyez sur ⚡ pour tout appliquer, ou utilisez le bouton inférieur :',
    AppLanguage.english:
        'Set the property name and value, then press ⚡ to apply to all, or use the bottom button:',
  },
  'تُستخدم هذه القيم في حساب عدد القضبان. أدخل القيم بالمليمتر؛ مثال: 5 مم = نصف سنتيمتر. الحد الخاص بنوع البروفيل يتقدم على الحد العام.': {
    AppLanguage.arabic:
        'تُستخدم هذه القيم في حساب عدد القضبان. أدخل القيم بالمليمتر؛ مثال: 5 مم = نصف سنتيمتر. الحد الخاص بنوع البروفيل يتقدم على الحد العام.',
    AppLanguage.french:
        'Ces valeurs servent à calculer le nombre de barres. Saisissez les valeurs en millimètres ; exemple : 5 mm = un demi-centimètre. Le seuil du profilé est prioritaire sur le seuil général.',
    AppLanguage.english:
        'These values calculate the number of bars. Enter values in millimeters; example: 5 mm = half a centimeter. The profile-specific threshold takes priority over the general threshold.',
  },
  'تم تطبيق التعديل بنجاح على جميع العناصر': {
    AppLanguage.arabic: 'تم تطبيق التعديل بنجاح على جميع العناصر',
    AppLanguage.french: 'La modification a été appliquée à tous les éléments',
    AppLanguage.english: 'The change was applied successfully to all items',
  },
  'تم تطبيق الخصائص الموحدة على جميع العناصر بنجاح': {
    AppLanguage.arabic: 'تم تطبيق الخصائص الموحدة على جميع العناصر بنجاح',
    AppLanguage.french:
        'Les propriétés communes ont été appliquées à tous les éléments',
    AppLanguage.english:
        'Shared properties were applied successfully to all items',
  },
  'تم تفعيل': {
    AppLanguage.arabic: 'تم تفعيل',
    AppLanguage.french: 'Activé',
    AppLanguage.english: 'Activated',
  },
  'تم حفظ PDF بنجاح': {
    AppLanguage.arabic: 'تم حفظ PDF بنجاح',
    AppLanguage.french: 'PDF enregistré avec succès',
    AppLanguage.english: 'PDF saved successfully',
  },
  'توقيع المورد': {
    AppLanguage.arabic: 'توقيع المورد',
    AppLanguage.french: 'Signature du fournisseur',
    AppLanguage.english: 'Supplier signature',
  },
  'دفعات / إرجاع (دائن)': {
    AppLanguage.arabic: 'دفعات / إرجاع (دائن)',
    AppLanguage.french: 'Paiements / retours (crédit)',
    AppLanguage.english: 'Payments / returns (credit)',
  },
  'سيتم خصم القطع الكاملة من المخزون وتغيير حالة الفضلات المستعملة إلى منتهية. لا يمكن اعتماد نفس الطلبية مرتين.': {
    AppLanguage.arabic:
        'سيتم خصم القطع الكاملة من المخزون وتغيير حالة الفضلات المستعملة إلى منتهية. لا يمكن اعتماد نفس الطلبية مرتين.',
    AppLanguage.french:
        'Les pièces entières seront déduites du stock et les chutes utilisées seront marquées comme terminées. La même commande ne peut pas être validée deux fois.',
    AppLanguage.english:
        'Complete pieces will be deducted from stock and used remnants marked as finished. The same order cannot be approved twice.',
  },
  'صورة العمل الزجاجي': {
    AppLanguage.arabic: 'صورة العمل الزجاجي',
    AppLanguage.french: 'Image du travail de vitrage',
    AppLanguage.english: 'Glass work image',
  },
  'صورة الموستيكير': {
    AppLanguage.arabic: 'صورة الموستيكير',
    AppLanguage.french: 'Image de la moustiquaire',
    AppLanguage.english: 'Mosquito screen image',
  },
  'عذراً، ليس لديك صلاحية للوصول إلى هذه الشاشة.': {
    AppLanguage.arabic: 'عذراً، ليس لديك صلاحية للوصول إلى هذه الشاشة.',
    AppLanguage.french:
        'Désolé, vous n’êtes pas autorisé à accéder à cet écran.',
    AppLanguage.english: 'Sorry, you are not authorized to access this screen.',
  },
  'فضلات': {
    AppLanguage.arabic: 'فضلات',
    AppLanguage.french: 'Chutes',
    AppLanguage.english: 'Remnants',
  },
  'لون الستار': {
    AppLanguage.arabic: 'لون الستار',
    AppLanguage.french: 'Couleur du volet',
    AppLanguage.english: 'Shutter color',
  },
  'مثال: 300': {
    AppLanguage.arabic: 'مثال: 300',
    AppLanguage.french: 'Exemple : 300',
    AppLanguage.english: 'Example: 300',
  },
  'مثال: 4 أو 5': {
    AppLanguage.arabic: 'مثال: 4 أو 5',
    AppLanguage.french: 'Exemple : 4 ou 5',
    AppLanguage.english: 'Example: 4 or 5',
  },
  'مشتريات (مدين)': {
    AppLanguage.arabic: 'مشتريات (مدين)',
    AppLanguage.french: 'Achats (débit)',
    AppLanguage.english: 'Purchases (debit)',
  },
  'حديد الدعم الخاص بهذا المقطع (Renfort)': {
    AppLanguage.arabic: 'حديد الدعم الخاص بهذا المقطع (Renfort)',
    AppLanguage.french: 'Renfort propre à ce profilé',
    AppLanguage.english: 'Reinforcement for this profile',
  },
  'أنبوب المحرك (L\'axe)': {
    AppLanguage.arabic: 'أنبوب المحرك (L\'axe)',
    AppLanguage.french: 'Tube moteur (L’axe)',
    AppLanguage.english: 'Motor tube (shaft)',
  },
  'قيمة الإطار السفلي': {
    AppLanguage.arabic: 'قيمة الإطار السفلي',
    AppLanguage.french: 'Valeur du cadre inférieur',
    AppLanguage.english: 'Bottom frame value',
  },
  'قيمة السلسلة': {
    AppLanguage.arabic: 'قيمة السلسلة',
    AppLanguage.french: 'Valeur de la série',
    AppLanguage.english: 'Series value',
  },
  'قيمة الغلق': {
    AppLanguage.arabic: 'قيمة الغلق',
    AppLanguage.french: 'Valeur de la fermeture',
    AppLanguage.english: 'Lock value',
  },
  'قيمة القطعة الجانبية': {
    AppLanguage.arabic: 'قيمة القطعة الجانبية',
    AppLanguage.french: 'Valeur de la pièce latérale',
    AppLanguage.english: 'Side piece value',
  },
  'قيمة الكوليس (Coulisse)': {
    AppLanguage.arabic: 'قيمة الكوليس (Coulisse)',
    AppLanguage.french: 'Valeur de la coulisse',
    AppLanguage.english: 'Track value',
  },
  'قيمة اللام (Lame volet)': {
    AppLanguage.arabic: 'قيمة اللام (Lame volet)',
    AppLanguage.french: 'Valeur de la lame du volet',
    AppLanguage.english: 'Shutter slat value',
  },
  'قيمة الميكانيزم': {
    AppLanguage.arabic: 'قيمة الميكانيزم',
    AppLanguage.french: 'Valeur du mécanisme',
    AppLanguage.english: 'Mechanism value',
  },
  'قيمة لون الأكسيسوار': {
    AppLanguage.arabic: 'قيمة لون الأكسيسوار',
    AppLanguage.french: 'Valeur de la couleur de l’accessoire',
    AppLanguage.english: 'Accessory color value',
  },
  'قيمة لون البروفيل': {
    AppLanguage.arabic: 'قيمة لون البروفيل',
    AppLanguage.french: 'Valeur de la couleur du profilé',
    AppLanguage.english: 'Profile color value',
  },
  'قيمة لون الستار': {
    AppLanguage.arabic: 'قيمة لون الستار',
    AppLanguage.french: 'Valeur de la couleur du volet',
    AppLanguage.english: 'Shutter color value',
  },
  'لن يظهر هذا العنصر في التنبيهات إلا إذا كان هذا الخيار مفعلاً.': {
    AppLanguage.arabic:
        'لن يظهر هذا العنصر في التنبيهات إلا إذا كان هذا الخيار مفعلاً.',
    AppLanguage.french:
        'Cet élément n’apparaîtra dans les alertes que si cette option est activée.',
    AppLanguage.english:
        'This item will appear in alerts only when this option is enabled.',
  },
  'تم تطبيق التعديل على العناصر المحددة': {
    AppLanguage.arabic: 'تم تطبيق التعديل على العناصر المحددة',
    AppLanguage.french:
        'La modification a été appliquée aux éléments sélectionnés',
    AppLanguage.english: 'The change was applied to the selected items',
  },
};
