import '../app_settings.dart';

/// Labels of the workshop rule snapshots screen and of the prompt shown when
/// a remote copy would remove many rules. Keys are namespaced with
/// `rule_snapshot_` so they never override generic words elsewhere.
final Map<String, Map<AppLanguage, String>> ruleSnapshotKeys = {
  'rule_snapshot_title': {
    AppLanguage.arabic: 'نسخ قواعد الورشة',
    AppLanguage.french: 'Copies des règles de l’atelier',
    AppLanguage.english: 'Workshop rule copies',
  },
  'rule_snapshot_menu_subtitle': {
    AppLanguage.arabic:
        'نسخ محلية لأدوار المقاطع وقواعد الإكسسوارات تُحفظ قبل كل مزامنة، مع إمكانية الاسترجاع.',
    AppLanguage.french:
        'Copies locales des rôles de profilés et des règles d’accessoires, prises avant chaque synchronisation, avec restauration.',
    AppLanguage.english:
        'Local copies of profile roles and accessory rules, taken before each sync, with restore.',
  },
  'rule_snapshot_empty': {
    AppLanguage.arabic: 'لا توجد نسخ محفوظة بعد.',
    AppLanguage.french: 'Aucune copie enregistrée pour le moment.',
    AppLanguage.english: 'No saved copies yet.',
  },
  'rule_snapshot_save_now': {
    AppLanguage.arabic: 'حفظ نسخة الآن',
    AppLanguage.french: 'Enregistrer une copie',
    AppLanguage.english: 'Save a copy now',
  },
  'rule_snapshot_saved': {
    AppLanguage.arabic: 'تم حفظ نسخة من القواعد الحالية.',
    AppLanguage.french: 'Une copie des règles actuelles a été enregistrée.',
    AppLanguage.english: 'A copy of the current rules was saved.',
  },
  'rule_snapshot_not_saved': {
    AppLanguage.arabic: 'لم تُحفظ نسخة: القواعد فارغة أو مطابقة لآخر نسخة.',
    AppLanguage.french:
        'Aucune copie : les règles sont vides ou identiques à la dernière copie.',
    AppLanguage.english:
        'No copy saved: the rules are empty or match the latest copy.',
  },
  'rule_snapshot_restore': {
    AppLanguage.arabic: 'استرجاع',
    AppLanguage.french: 'Restaurer',
    AppLanguage.english: 'Restore',
  },
  'rule_snapshot_restore_confirm_title': {
    AppLanguage.arabic: 'استرجاع هذه النسخة؟',
    AppLanguage.french: 'Restaurer cette copie ?',
    AppLanguage.english: 'Restore this copy?',
  },
  'rule_snapshot_restore_confirm_body': {
    AppLanguage.arabic:
        'ستحل قواعد هذه النسخة محل القواعد الحالية ثم تُرفع إلى باقي أجهزة الورشة. تُحفظ القواعد الحالية في نسخة قبل الاسترجاع.',
    AppLanguage.french:
        'Les règles de cette copie remplaceront les règles actuelles puis seront envoyées aux autres appareils de l’atelier. Les règles actuelles sont copiées avant la restauration.',
    AppLanguage.english:
        'This copy’s rules will replace the current rules and then be uploaded to the workshop’s other devices. The current rules are copied before the restore.',
  },
  'rule_snapshot_restored': {
    AppLanguage.arabic: 'تم استرجاع القواعد ورفعها إلى الورشة.',
    AppLanguage.french: 'Règles restaurées et envoyées à l’atelier.',
    AppLanguage.english: 'Rules restored and uploaded to the workshop.',
  },
  'rule_snapshot_restored_not_uploaded': {
    AppLanguage.arabic:
        'تم استرجاع القواعد محلياً، لكن تعذر رفعها الآن وستُعاد المحاولة تلقائياً.',
    AppLanguage.french:
        'Règles restaurées localement, mais l’envoi a échoué ; il sera réessayé automatiquement.',
    AppLanguage.english:
        'Rules restored locally, but the upload failed; it will be retried automatically.',
  },
  'rule_snapshot_failed': {
    AppLanguage.arabic: 'تعذرت العملية',
    AppLanguage.french: 'L’opération a échoué',
    AppLanguage.english: 'The operation failed',
  },
  'rule_snapshot_rows': {
    AppLanguage.arabic: 'سطر',
    AppLanguage.french: 'lignes',
    AppLanguage.english: 'rows',
  },
  'rule_snapshot_workshop': {
    AppLanguage.arabic: 'الورشة',
    AppLanguage.french: 'Atelier',
    AppLanguage.english: 'Workshop',
  },
  'rule_snapshot_reason_remote_configuration': {
    AppLanguage.arabic: 'قبل تطبيق قواعد الورشة من السحابة',
    AppLanguage.french: 'Avant l’application des règles de l’atelier du cloud',
    AppLanguage.english: 'Before applying the workshop rules from the cloud',
  },
  'rule_snapshot_reason_data_import': {
    AppLanguage.arabic: 'قبل استيراد بيانات أو استرجاع نسخة احتياطية',
    AppLanguage.french:
        'Avant une importation ou une restauration de sauvegarde',
    AppLanguage.english: 'Before a data import or backup restore',
  },
  'rule_snapshot_reason_workshop_change': {
    AppLanguage.arabic: 'قبل تغيير الورشة',
    AppLanguage.french: 'Avant le changement d’atelier',
    AppLanguage.english: 'Before switching workshop',
  },
  'rule_snapshot_reason_before_restore': {
    AppLanguage.arabic: 'قبل استرجاع نسخة',
    AppLanguage.french: 'Avant une restauration',
    AppLanguage.english: 'Before a restore',
  },
  'rule_snapshot_reason_manual': {
    AppLanguage.arabic: 'نسخة يدوية',
    AppLanguage.french: 'Copie manuelle',
    AppLanguage.english: 'Manual copy',
  },
  'rule_snapshot_conflict_title': {
    AppLanguage.arabic: 'نسخة السحابة تحذف كثيراً من القواعد',
    AppLanguage.french: 'La copie du cloud supprime beaucoup de règles',
    AppLanguage.english: 'The cloud copy removes many rules',
  },
  'rule_snapshot_conflict_body': {
    AppLanguage.arabic:
        'وصلت نسخة من قواعد الورشة ستحذف عدداً كبيراً من القواعد الموجودة على هذا الجهاز، فلم تُطبَّق. اختر ما تريد:',
    AppLanguage.french:
        'Une copie des règles de l’atelier supprimerait beaucoup de règles de cet appareil ; elle n’a pas été appliquée. Choisissez :',
    AppLanguage.english:
        'A copy of the workshop rules would remove many rules on this device, so it was not applied. Choose:',
  },
  'rule_snapshot_conflict_local': {
    AppLanguage.arabic: 'على هذا الجهاز',
    AppLanguage.french: 'Sur cet appareil',
    AppLanguage.english: 'On this device',
  },
  'rule_snapshot_conflict_remote': {
    AppLanguage.arabic: 'في السحابة',
    AppLanguage.french: 'Dans le cloud',
    AppLanguage.english: 'In the cloud',
  },
  'rule_snapshot_conflict_lost': {
    AppLanguage.arabic: 'سيُحذف',
    AppLanguage.french: 'Supprimées',
    AppLanguage.english: 'Removed',
  },
  'rule_snapshot_keep_local': {
    AppLanguage.arabic: 'الإبقاء على قواعد هذا الجهاز',
    AppLanguage.french: 'Garder les règles de cet appareil',
    AppLanguage.english: 'Keep this device’s rules',
  },
  'rule_snapshot_apply_remote': {
    AppLanguage.arabic: 'تطبيق نسخة السحابة',
    AppLanguage.french: 'Appliquer la copie du cloud',
    AppLanguage.english: 'Apply the cloud copy',
  },
  'rule_snapshot_later': {
    AppLanguage.arabic: 'لاحقاً',
    AppLanguage.french: 'Plus tard',
    AppLanguage.english: 'Later',
  },
  'rule_snapshot_kept_local': {
    AppLanguage.arabic: 'تم الإبقاء على قواعد هذا الجهاز ورفعها إلى الورشة.',
    AppLanguage.french:
        'Les règles de cet appareil sont conservées et envoyées à l’atelier.',
    AppLanguage.english:
        'This device’s rules were kept and uploaded to the workshop.',
  },
  'rule_snapshot_applied_remote': {
    AppLanguage.arabic:
        'تم تطبيق نسخة السحابة. القواعد السابقة محفوظة في نسخ القواعد.',
    AppLanguage.french:
        'Copie du cloud appliquée. Les règles précédentes sont dans les copies des règles.',
    AppLanguage.english:
        'Cloud copy applied. The previous rules are kept in the rule copies.',
  },
  'rule_table_SeriesTableConfig': {
    AppLanguage.arabic: 'إعداد جداول السلاسل',
    AppLanguage.french: 'Configuration des tableaux de gammes',
    AppLanguage.english: 'Series table settings',
  },
  'rule_table_SeriesDesignConfig': {
    AppLanguage.arabic: 'إعداد تصاميم السلاسل',
    AppLanguage.french: 'Configuration des modèles de gammes',
    AppLanguage.english: 'Series design settings',
  },
  'rule_table_SeriesDesignRoles': {
    AppLanguage.arabic: 'أدوار مقاطع السلاسل',
    AppLanguage.french: 'Rôles des profilés de gamme',
    AppLanguage.english: 'Series profile roles',
  },
  'rule_table_SectionSharingRules': {
    AppLanguage.arabic: 'قواعد مشاركة المقاطع',
    AppLanguage.french: 'Règles de partage des profilés',
    AppLanguage.english: 'Profile sharing rules',
  },
  'rule_table_FrameJoinRules': {
    AppLanguage.arabic: 'قواعد وصل الإطارات',
    AppLanguage.french: 'Règles d’assemblage des cadres',
    AppLanguage.english: 'Frame join rules',
  },
  'rule_table_ProfileCompatibilityGroups': {
    AppLanguage.arabic: 'مجموعات توافق البروفايلات',
    AppLanguage.french: 'Groupes de compatibilité des profilés',
    AppLanguage.english: 'Profile compatibility groups',
  },
  'rule_table_FramePairingRules': {
    AppLanguage.arabic: 'قواعد اقتران الإطارات',
    AppLanguage.french: 'Règles d’appariement des cadres',
    AppLanguage.english: 'Frame pairing rules',
  },
  'rule_table_ShutterCalcRules': {
    AppLanguage.arabic: 'قواعد حساب الشتر',
    AppLanguage.french: 'Règles de calcul des volets',
    AppLanguage.english: 'Shutter calculation rules',
  },
  'rule_table_CatalogItemRules': {
    AppLanguage.arabic: 'قواعد الإكسسوارات والكتالوج',
    AppLanguage.french: 'Règles des accessoires et du catalogue',
    AppLanguage.english: 'Accessory and catalogue rules',
  },
  'rule_table_ProfileCalculationRules': {
    AppLanguage.arabic: 'قواعد حساب البروفايلات',
    AppLanguage.french: 'Règles de calcul des profilés',
    AppLanguage.english: 'Profile calculation rules',
  },
  'rule_table_SectionJointLinks': {
    AppLanguage.arabic: 'روابط الجوانات بالمقاطع',
    AppLanguage.french: 'Liens joints–profilés',
    AppLanguage.english: 'Joint–profile links',
  },
  'rule_table_SeriesShutterRules': {
    AppLanguage.arabic: 'قواعد شتر السلاسل',
    AppLanguage.french: 'Règles de volets des gammes',
    AppLanguage.english: 'Series shutter rules',
  },
  'rule_table_AccessoryLinks': {
    AppLanguage.arabic: 'روابط الإكسسوارات',
    AppLanguage.french: 'Liens des accessoires',
    AppLanguage.english: 'Accessory links',
  },
  'rule_table_AccessoryRoleLinks': {
    AppLanguage.arabic: 'روابط الإكسسوارات بالأدوار',
    AppLanguage.french: 'Liens accessoires–rôles',
    AppLanguage.english: 'Accessory–role links',
  },
};
