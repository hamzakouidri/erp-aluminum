import '../app_settings.dart';

/// First batch of translations for the partial-delivery screen.
const Map<String, Map<AppLanguage, String>> translationPhase4Keys = {
  'حدث خطأ أثناء إعادة التعيين:': {
    AppLanguage.arabic: 'حدث خطأ أثناء إعادة التعيين:',
    AppLanguage.french: 'Erreur lors de la réinitialisation :',
    AppLanguage.english: 'Error while resetting:',
  },
  'خطأ أثناء التعديل:': {
    AppLanguage.arabic: 'خطأ أثناء التعديل:',
    AppLanguage.french: 'Erreur lors de la modification :',
    AppLanguage.english: 'Error while editing:',
  },
  'خطأ أثناء معاينة الفاتورة:': {
    AppLanguage.arabic: 'خطأ أثناء معاينة الفاتورة:',
    AppLanguage.french: 'Erreur lors de l’aperçu de la facture :',
    AppLanguage.english: 'Error while previewing the invoice:',
  },
  'خطأ أثناء تأكيد وحفظ التسليم:': {
    AppLanguage.arabic: 'خطأ أثناء تأكيد وحفظ التسليم:',
    AppLanguage.french: 'Erreur lors de la confirmation et de l’enregistrement de la livraison :',
    AppLanguage.english: 'Error while confirming and saving the delivery:',
  },
  'تأكيد إعادة التعيين': {
    AppLanguage.arabic: 'تأكيد إعادة التعيين',
    AppLanguage.french: 'Confirmation de la réinitialisation',
    AppLanguage.english: 'Confirm reset',
  },
  'هل أنت متأكد من رغبتك في إعادة تعيين كل كميات التسليم إلى صفر لهذه الطلبية؟ سيتم حذف جميع سجلات التسليم السابقة لمواد هذا الطلب.': {
    AppLanguage.arabic:
        'هل أنت متأكد من رغبتك في إعادة تعيين كل كميات التسليم إلى صفر لهذه الطلبية؟ سيتم حذف جميع سجلات التسليم السابقة لمواد هذا الطلب.',
    AppLanguage.french:
        'Voulez-vous vraiment remettre à zéro toutes les quantités livrées pour cette commande ? Tous les anciens enregistrements de livraison de ses articles seront supprimés.',
    AppLanguage.english:
        'Are you sure you want to reset all delivered quantities for this order to zero? All previous delivery records for its items will be deleted.',
  },
  'تأكيد وإعادة تعيين': {
    AppLanguage.arabic: 'تأكيد وإعادة تعيين',
    AppLanguage.french: 'Confirmer et réinitialiser',
    AppLanguage.english: 'Confirm and reset',
  },
  'تمت إعادة تعيين كل كميات التسليم بنجاح': {
    AppLanguage.arabic: 'تمت إعادة تعيين كل كميات التسليم بنجاح',
    AppLanguage.french: 'Toutes les quantités livrées ont été réinitialisées.',
    AppLanguage.english: 'All delivered quantities were reset successfully.',
  },
  'تعديل الكمية المسلمة سابقاً': {
    AppLanguage.arabic: 'تعديل الكمية المسلمة سابقاً',
    AppLanguage.french: 'Modifier la quantité déjà livrée',
    AppLanguage.english: 'Edit previously delivered quantity',
  },
  'الكمية الإجمالية المطلوبة': {
    AppLanguage.arabic: 'الكمية الإجمالية المطلوبة',
    AppLanguage.french: 'Quantité totale demandée',
    AppLanguage.english: 'Total requested quantity',
  },
  'الكمية المسلمة المعدلة': {
    AppLanguage.arabic: 'الكمية المسلمة المعدلة',
    AppLanguage.french: 'Quantité livrée modifiée',
    AppLanguage.english: 'Edited delivered quantity',
  },
  'الكمية يجب أن تكون بين': {
    AppLanguage.arabic: 'الكمية يجب أن تكون بين',
    AppLanguage.french: 'La quantité doit être comprise entre',
    AppLanguage.english: 'Quantity must be between',
  },
  'تم تحديث الكمية المسلمة بنجاح': {
    AppLanguage.arabic: 'تم تحديث الكمية المسلمة بنجاح',
    AppLanguage.french: 'La quantité livrée a été mise à jour.',
    AppLanguage.english: 'Delivered quantity updated successfully.',
  },
  'يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل للمعاينة!': {
    AppLanguage.arabic: 'يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل للمعاينة!',
    AppLanguage.french: 'Sélectionnez une quantité supérieure à zéro pour au moins un article afin de prévisualiser.',
    AppLanguage.english: 'Select a quantity greater than zero for at least one item to preview.',
  },
  'يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل لتأكيد التسليم!': {
    AppLanguage.arabic: 'يرجى تحديد كمية أكبر من صفر لعنصر واحد على الأقل لتأكيد التسليم!',
    AppLanguage.french: 'Sélectionnez une quantité supérieure à zéro pour au moins un article afin de confirmer la livraison.',
    AppLanguage.english: 'Select a quantity greater than zero for at least one item to confirm delivery.',
  },
  'تأكيد وحفظ التسليم': {
    AppLanguage.arabic: 'تأكيد وحفظ التسليم',
    AppLanguage.french: 'Confirmer et enregistrer la livraison',
    AppLanguage.english: 'Confirm and save delivery',
  },
  'هل ترغب في تأكيد وحفظ تسليم': {
    AppLanguage.arabic: 'هل ترغب في تأكيد وحفظ تسليم',
    AppLanguage.french: 'Voulez-vous confirmer et enregistrer la livraison de',
    AppLanguage.english: 'Do you want to confirm and save the delivery of',
  },
  'نافذة في قاعدة البيانات؟': {
    AppLanguage.arabic: 'نافذة في قاعدة البيانات؟',
    AppLanguage.french: 'fenêtre(s) dans la base de données ?',
    AppLanguage.english: 'window(s) in the database?',
  },
  'سيتم تحديث سجلات الطلب بالكميات المحددة.': {
    AppLanguage.arabic: 'سيتم تحديث سجلات الطلب بالكميات المحددة.',
    AppLanguage.french: 'Les enregistrements de la commande seront mis à jour avec les quantités sélectionnées.',
    AppLanguage.english: 'The order records will be updated with the selected quantities.',
  },
  'تأكيد وحفظ': {
    AppLanguage.arabic: 'تأكيد وحفظ',
    AppLanguage.french: 'Confirmer et enregistrer',
    AppLanguage.english: 'Confirm and save',
  },
  'تم حفظ التسليم بنجاح': {
    AppLanguage.arabic: 'تم حفظ التسليم بنجاح',
    AppLanguage.french: 'La livraison a été enregistrée avec succès.',
    AppLanguage.english: 'Delivery saved successfully.',
  },
  'تم تأكيد وحفظ كميات التسليم في قاعدة البيانات بنجاح. هل ترغب في طباعة الفاتورة التقديرية الجزئية للتسليم الحالي الآن؟': {
    AppLanguage.arabic:
        'تم تأكيد وحفظ كميات التسليم في قاعدة البيانات بنجاح. هل ترغب في طباعة الفاتورة التقديرية الجزئية للتسليم الحالي الآن؟',
    AppLanguage.french:
        'Les quantités livrées ont été confirmées et enregistrées avec succès. Voulez-vous imprimer maintenant le devis partiel de cette livraison ?',
    AppLanguage.english:
        'The delivered quantities were confirmed and saved successfully. Would you like to print the partial proforma for this delivery now?',
  },
  'طباعة الفاتورة': {
    AppLanguage.arabic: 'طباعة الفاتورة',
    AppLanguage.french: 'Imprimer la facture',
    AppLanguage.english: 'Print invoice',
  },
  'سجل الفواتير الجزئية المسلمة': {
    AppLanguage.arabic: 'سجل الفواتير الجزئية المسلمة',
    AppLanguage.french: 'Historique des factures partielles livrées',
    AppLanguage.english: 'Partial delivery invoice history',
  },
  'لا توجد فواتير جزئية مسلمة سابقاً': {
    AppLanguage.arabic: 'لا توجد فواتير جزئية مسلمة سابقاً',
    AppLanguage.french: 'Aucune facture partielle livrée précédemment.',
    AppLanguage.english: 'No previous partial delivery invoices.',
  },
  'إجمالي تقدم تسليم الطلبية': {
    AppLanguage.arabic: 'إجمالي تقدم تسليم الطلبية',
    AppLanguage.french: 'Avancement total de la livraison de la commande',
    AppLanguage.english: 'Overall order delivery progress',
  },
  'الإجمالي': {
    AppLanguage.arabic: 'الإجمالي',
    AppLanguage.french: 'Total',
    AppLanguage.english: 'Total',
  },
  'سلمت سابقاً': {
    AppLanguage.arabic: 'سلمت سابقاً',
    AppLanguage.french: 'Déjà livré',
    AppLanguage.english: 'Previously delivered',
  },
  'التسليم الحالي:': {
    AppLanguage.arabic: 'التسليم الحالي:',
    AppLanguage.french: 'Livraison actuelle :',
    AppLanguage.english: 'Current delivery:',
  },
  'تم تسليم هذا البند بالكامل': {
    AppLanguage.arabic: 'تم تسليم هذا البند بالكامل',
    AppLanguage.french: 'Cet article a été entièrement livré',
    AppLanguage.english: 'This item has been fully delivered',
  },
  'الكميات المحددة': {
    AppLanguage.arabic: 'الكميات المحددة',
    AppLanguage.french: 'Quantités sélectionnées',
    AppLanguage.english: 'Selected quantities',
  },
  'القيمة الإجمالية للتسليم': {
    AppLanguage.arabic: 'القيمة الإجمالية للتسليم',
    AppLanguage.french: 'Valeur totale de la livraison',
    AppLanguage.english: 'Total delivery value',
  },
  'معاينة الفاتورة': {
    AppLanguage.arabic: 'معاينة الفاتورة',
    AppLanguage.french: 'Aperçu de la facture',
    AppLanguage.english: 'Invoice preview',
  },
};
