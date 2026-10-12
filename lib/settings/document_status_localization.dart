import 'app_settings.dart';
import 'localization.dart';

/// Translates persisted document workflow values without changing the value
/// stored in the database. Matching is case-insensitive because older rows
/// contain both `Confirmed` and `confirmed` forms.
String localizeDocumentStatus(dynamic value, AppLanguage language) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return '—';

  String tr(String arabic, String french, String english) {
    return switch (language) {
      AppLanguage.arabic => arabic,
      AppLanguage.french => french,
      AppLanguage.english => english,
    };
  }

  switch (raw.toLowerCase()) {
    case 'draft':
    case 'مسودة':
      return tr('مسودة', 'Brouillon', 'Draft');
    case 'confirmed':
    case 'confirmé':
    case 'confirmée':
    case 'مؤكد':
    case 'مؤكدة':
      return tr('مؤكدة', 'Confirmée', 'Confirmed');
    case 'delivered':
    case 'livré':
    case 'livrée':
    case 'تم التسليم':
    case 'تم التوصيل':
      return tr('تم التسليم', 'Livrée', 'Delivered');
    case 'reserved':
    case 'reserve':
    case 'réservé':
    case 'réservée':
    case 'محجوز':
    case 'محجوزة':
      return tr('محجوزة', 'Réservée', 'Reserved');
    case 'paid':
    case 'payé':
    case 'payée':
    case 'مدفوع':
    case 'مدفوعة':
      return tr('مدفوعة', 'Payée', 'Paid');
    case 'active':
    case 'actif':
    case 'نشط':
    case 'نشطة':
      return tr('نشطة', 'Active', 'Active');
    case 'cancelled':
    case 'canceled':
    case 'annulé':
    case 'annulée':
    case 'ملغى':
    case 'ملغاة':
      return tr('ملغاة', 'Annulée', 'Cancelled');
    case 'returned':
    case 'مردودة':
    case 'مسترجعة':
      return tr('مردودة كلياً', 'Retournée totalement', 'Fully returned');
    case 'partial returned':
    case 'partial return':
    case 'مردودة جزئياً':
    case 'جزئياً مسترجعة':
      return tr('مردودة جزئياً', 'Retournée partiellement', 'Partially returned');
    case 'pending':
    case 'en attente':
    case 'في الانتظار':
      return tr('قيد الانتظار', 'En attente', 'Pending');
    case 'completed':
    case 'finished':
    case 'done':
    case 'منتهية':
      return tr('منتهية', 'Terminée', 'Completed');
    default:
      return Localization.translate(raw, language);
  }
}
