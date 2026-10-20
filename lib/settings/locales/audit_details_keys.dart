import '../app_settings.dart';

/// Labels of the readable audit details (Trash screen → journal entry).
/// Field keys are `audit_f_<database column>`.
final Map<String, Map<AppLanguage, String>> auditDetailsKeys = {
  'audit_d_changes': {
    AppLanguage.arabic: 'التغييرات',
    AppLanguage.french: 'Modifications',
    AppLanguage.english: 'Changes',
  },
  'audit_d_no_changes': {
    AppLanguage.arabic: 'لا يوجد فرق في الحقول المعروضة',
    AppLanguage.french: 'Aucune différence dans les champs affichés',
    AppLanguage.english: 'No difference in the fields shown',
  },
  'audit_d_before': {
    AppLanguage.arabic: 'الوثيقة قبل العملية',
    AppLanguage.french: 'Document avant l\'opération',
    AppLanguage.english: 'Document before the operation',
  },
  'audit_d_lines': {
    AppLanguage.arabic: 'الأسطر',
    AppLanguage.french: 'Lignes',
    AppLanguage.english: 'Lines',
  },
  'audit_d_line_added': {
    AppLanguage.arabic: 'سطر مضاف',
    AppLanguage.french: 'Ligne ajoutée',
    AppLanguage.english: 'Line added',
  },
  'audit_d_line_removed': {
    AppLanguage.arabic: 'سطر محذوف',
    AppLanguage.french: 'Ligne supprimée',
    AppLanguage.english: 'Line removed',
  },
  'audit_d_line_changed': {
    AppLanguage.arabic: 'سطر معدل',
    AppLanguage.french: 'Ligne modifiée',
    AppLanguage.english: 'Line changed',
  },
  'audit_d_empty_value': {
    AppLanguage.arabic: '(فارغ)',
    AppLanguage.french: '(vide)',
    AppLanguage.english: '(empty)',
  },
  'audit_f_order_code': {
    AppLanguage.arabic: 'رقم الطلبية',
    AppLanguage.french: 'N° de commande',
    AppLanguage.english: 'Order number',
  },
  'audit_f_status': {
    AppLanguage.arabic: 'الحالة',
    AppLanguage.french: 'Statut',
    AppLanguage.english: 'Status',
  },
  'audit_f_description': {
    AppLanguage.arabic: 'الوصف',
    AppLanguage.french: 'Description',
    AppLanguage.english: 'Description',
  },
  'audit_f_remise': {
    AppLanguage.arabic: 'التخفيض',
    AppLanguage.french: 'Remise',
    AppLanguage.english: 'Discount',
  },
  'audit_f_tva': {
    AppLanguage.arabic: 'الضريبة',
    AppLanguage.french: 'TVA',
    AppLanguage.english: 'VAT',
  },
  'audit_f_total': {
    AppLanguage.arabic: 'المجموع',
    AppLanguage.french: 'Total',
    AppLanguage.english: 'Total',
  },
  'audit_f_net_payable': {
    AppLanguage.arabic: 'الصافي للدفع',
    AppLanguage.french: 'Net à payer',
    AppLanguage.english: 'Net payable',
  },
  'audit_f_advance_payment': {
    AppLanguage.arabic: 'التسبيق',
    AppLanguage.french: 'Acompte',
    AppLanguage.english: 'Advance payment',
  },
  'audit_f_payment_status': {
    AppLanguage.arabic: 'حالة الدفع',
    AppLanguage.french: 'État du paiement',
    AppLanguage.english: 'Payment status',
  },
  'audit_f_created_at': {
    AppLanguage.arabic: 'تاريخ الإنشاء',
    AppLanguage.french: 'Créé le',
    AppLanguage.english: 'Created on',
  },
  'audit_f_created_by': {
    AppLanguage.arabic: 'أنشأها',
    AppLanguage.french: 'Créé par',
    AppLanguage.english: 'Created by',
  },
  'audit_f_updated_by': {
    AppLanguage.arabic: 'آخر تعديل من',
    AppLanguage.french: 'Modifié par',
    AppLanguage.english: 'Updated by',
  },
  'audit_f_game': {
    AppLanguage.arabic: 'المنتج',
    AppLanguage.french: 'Produit',
    AppLanguage.english: 'Product',
  },
  'audit_f_largeur': {
    AppLanguage.arabic: 'العرض',
    AppLanguage.french: 'Largeur',
    AppLanguage.english: 'Width',
  },
  'audit_f_hauteur': {
    AppLanguage.arabic: 'الارتفاع',
    AppLanguage.french: 'Hauteur',
    AppLanguage.english: 'Height',
  },
  'audit_f_quantity': {
    AppLanguage.arabic: 'الكمية',
    AppLanguage.french: 'Quantité',
    AppLanguage.english: 'Quantity',
  },
  'audit_f_glass': {
    AppLanguage.arabic: 'الزجاج',
    AppLanguage.french: 'Vitrage',
    AppLanguage.english: 'Glass',
  },
  'audit_f_color': {
    AppLanguage.arabic: 'اللون',
    AppLanguage.french: 'Couleur',
    AppLanguage.english: 'Colour',
  },
  'audit_f_volet': {
    AppLanguage.arabic: 'الستار',
    AppLanguage.french: 'Volet',
    AppLanguage.english: 'Shutter',
  },
  'audit_f_accessories': {
    AppLanguage.arabic: 'الإكسسوارات',
    AppLanguage.french: 'Accessoires',
    AppLanguage.english: 'Accessories',
  },
  'audit_f_price': {
    AppLanguage.arabic: 'السعر',
    AppLanguage.french: 'Prix',
    AppLanguage.english: 'Price',
  },
  'audit_f_window_type': {
    AppLanguage.arabic: 'النوع',
    AppLanguage.french: 'Type',
    AppLanguage.english: 'Type',
  },
  'audit_f_delivered_qty': {
    AppLanguage.arabic: 'الكمية المسلمة',
    AppLanguage.french: 'Quantité livrée',
    AppLanguage.english: 'Delivered quantity',
  },
  'audit_f_sale_code': {
    AppLanguage.arabic: 'رقم الوثيقة',
    AppLanguage.french: 'N° de document',
    AppLanguage.english: 'Document number',
  },
  'audit_f_client_name': {
    AppLanguage.arabic: 'الزبون',
    AppLanguage.french: 'Client',
    AppLanguage.english: 'Client',
  },
  'audit_f_client_phone': {
    AppLanguage.arabic: 'هاتف الزبون',
    AppLanguage.french: 'Téléphone du client',
    AppLanguage.english: 'Client phone',
  },
  'audit_f_doc_type': {
    AppLanguage.arabic: 'نوع الوثيقة',
    AppLanguage.french: 'Type de document',
    AppLanguage.english: 'Document type',
  },
  'audit_f_subtotal': {
    AppLanguage.arabic: 'المجموع قبل التخفيض',
    AppLanguage.french: 'Sous-total',
    AppLanguage.english: 'Subtotal',
  },
  'audit_f_discount_amount': {
    AppLanguage.arabic: 'التخفيض',
    AppLanguage.french: 'Remise',
    AppLanguage.english: 'Discount',
  },
  'audit_f_net_total': {
    AppLanguage.arabic: 'الصافي',
    AppLanguage.french: 'Net',
    AppLanguage.english: 'Net total',
  },
  'audit_f_paid_amount': {
    AppLanguage.arabic: 'المدفوع',
    AppLanguage.french: 'Payé',
    AppLanguage.english: 'Paid',
  },
  'audit_f_remaining_amount': {
    AppLanguage.arabic: 'الباقي',
    AppLanguage.french: 'Reste',
    AppLanguage.english: 'Remaining',
  },
  'audit_f_notes': {
    AppLanguage.arabic: 'ملاحظات',
    AppLanguage.french: 'Notes',
    AppLanguage.english: 'Notes',
  },
  'audit_f_sale_date': {
    AppLanguage.arabic: 'تاريخ الوثيقة',
    AppLanguage.french: 'Date du document',
    AppLanguage.english: 'Document date',
  },
  'audit_f_item_name': {
    AppLanguage.arabic: 'المادة',
    AppLanguage.french: 'Article',
    AppLanguage.english: 'Item',
  },
  'audit_f_item_code': {
    AppLanguage.arabic: 'الرمز',
    AppLanguage.french: 'Code',
    AppLanguage.english: 'Code',
  },
  'audit_f_color_name': {
    AppLanguage.arabic: 'اللون',
    AppLanguage.french: 'Couleur',
    AppLanguage.english: 'Colour',
  },
  'audit_f_unit': {
    AppLanguage.arabic: 'الوحدة',
    AppLanguage.french: 'Unité',
    AppLanguage.english: 'Unit',
  },
  'audit_f_length_mm': {
    AppLanguage.arabic: 'الطول (مم)',
    AppLanguage.french: 'Longueur (mm)',
    AppLanguage.english: 'Length (mm)',
  },
  'audit_f_width_mm': {
    AppLanguage.arabic: 'العرض (مم)',
    AppLanguage.french: 'Largeur (mm)',
    AppLanguage.english: 'Width (mm)',
  },
  'audit_f_unit_price': {
    AppLanguage.arabic: 'سعر الوحدة',
    AppLanguage.french: 'Prix unitaire',
    AppLanguage.english: 'Unit price',
  },
  'audit_f_total_price': {
    AppLanguage.arabic: 'المبلغ',
    AppLanguage.french: 'Montant',
    AppLanguage.english: 'Amount',
  },
  'audit_f_invoice_number': {
    AppLanguage.arabic: 'رقم الفاتورة',
    AppLanguage.french: 'N° de facture',
    AppLanguage.english: 'Invoice number',
  },
  'audit_f_total_amount': {
    AppLanguage.arabic: 'المبلغ الإجمالي',
    AppLanguage.french: 'Montant total',
    AppLanguage.english: 'Total amount',
  },
  'audit_f_item_type': {
    AppLanguage.arabic: 'نوع المادة',
    AppLanguage.french: 'Type d\'article',
    AppLanguage.english: 'Item type',
  },
};
