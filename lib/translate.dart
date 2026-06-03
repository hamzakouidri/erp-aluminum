import 'dart:io';

void main() {
  var file = File('lib/settings/localization.dart');
  var content = file.readAsStringSync();

  // A comprehensive dictionary mapping Arabic words/phrases to French and English
  Map<String, Map<String, String>> dictionary = {
    "السفلية": {"fr": "Base", "en": "Base"},
    "العلوية": {"fr": "Haut", "en": "Out"}, // user requested 'out'
    "اليسرى": {"fr": "Gauche", "en": "Left"},
    "اليمنى": {"fr": "Droite", "en": "Right"},
    "القطعة": {"fr": "Pièce", "en": "Piece"},
    "العرض": {"fr": "Largeur", "en": "Width"},
    "الارتفاع": {"fr": "Hauteur", "en": "Height"},
    "اللون": {"fr": "Couleur", "en": "Color"},
    "الزجاج": {"fr": "Verre", "en": "Glass"},
    "زجاج": {"fr": "Verre", "en": "Glass"},
    "الستائر": {"fr": "Volets Roulants", "en": "Shutters"},
    "ستائر": {"fr": "Volets Roulants", "en": "Shutters"},
    "السعر": {"fr": "Prix", "en": "Price"},
    "سعر": {"fr": "Prix", "en": "Price"},
    "المبلغ": {"fr": "Montant", "en": "Amount"},
    "الرصيد": {"fr": "Solde", "en": "Balance"},
    "الإجمالي": {"fr": "Total", "en": "Total"},
    "الزبائن": {"fr": "Clients", "en": "Clients"},
    "زبون": {"fr": "Client", "en": "Client"},
    "الدفعات": {"fr": "Paiements", "en": "Payments"},
    "المشتريات": {"fr": "Achats", "en": "Purchases"},
    "المخزون": {"fr": "Stock", "en": "Stock"},
    "المستودع": {"fr": "Entrepôt", "en": "Warehouse"},
    "الطلبات": {"fr": "Commandes", "en": "Orders"},
    "طلب": {"fr": "Commande", "en": "Order"},
    "الصندوق": {"fr": "Caisse", "en": "Treasury"},
    "المالي": {"fr": "Financier", "en": "Financial"},
    "تعديل": {"fr": "Modifier", "en": "Edit"},
    "إضافة": {"fr": "Ajouter", "en": "Add"},
    "حفظ": {"fr": "Enregistrer", "en": "Save"},
    "إلغاء": {"fr": "Annuler", "en": "Cancel"},
    "تسجيل الدخول": {"fr": "Connexion", "en": "Login"},
    "خطأ": {"fr": "Erreur", "en": "Error"},
    "نجاح": {"fr": "Succès", "en": "Success"},
    "بانو": {"fr": "Panneau", "en": "Panel"},
    "خشب": {"fr": "Bois", "en": "Wood"},
    "خشبي": {"fr": "Bois", "en": "Wood"},
    "داكن": {"fr": "Foncé", "en": "Dark"},
    "فاتح": {"fr": "Clair", "en": "Light"},
    "أبيض": {"fr": "Blanc", "en": "White"},
    "أسود": {"fr": "Noir", "en": "Black"},
    "رمادي": {"fr": "Gris", "en": "Grey"},
    "فضي": {"fr": "Argent", "en": "Silver"},
    "ذهبي": {"fr": "Or", "en": "Gold"},
    "بني": {"fr": "Marron", "en": "Brown"},
    "أحمر": {"fr": "Rouge", "en": "Red"},
    "أخضر": {"fr": "Vert", "en": "Green"},
    "أزرق": {"fr": "Bleu", "en": "Blue"},
    "تفاصيل": {"fr": "Détails", "en": "Details"},
    "التقسيم": {"fr": "Division", "en": "Division"},
    "العمودي": {"fr": "Vertical", "en": "Vertical"},
    "الأفقي": {"fr": "Horizontal", "en": "Horizontal"},
    "المقطع": {"fr": "Profil", "en": "Profile"},
    "النطاق": {"fr": "Portée", "en": "Scope"},
    "النوع": {"fr": "Type", "en": "Type"},
    "الكمية": {"fr": "Quantité", "en": "Quantity"},
    "الفاتورة": {"fr": "Facture", "en": "Invoice"},
    "رقم": {"fr": "Numéro", "en": "Number"},
    "تاريخ": {"fr": "Date", "en": "Date"},
    "العميل": {"fr": "Client", "en": "Customer"},
    "اسم": {"fr": "Nom", "en": "Name"},
    "اللقب": {"fr": "Prénom", "en": "Last Name"},
    "الهاتف": {"fr": "Téléphone", "en": "Phone"},
    "البريد": {"fr": "Email", "en": "Email"},
    "الاشتراك": {"fr": "Abonnement", "en": "Subscription"},
    "السحابة": {"fr": "Cloud", "en": "Cloud"},
    "مزامنة": {"fr": "Synchronisation", "en": "Sync"},
    "حذف": {"fr": "Supprimer", "en": "Delete"},
    "تأكيد": {"fr": "Confirmer", "en": "Confirm"},
    "القياس": {"fr": "Mesure", "en": "Measurement"},
    "الداخلي": {"fr": "Intérieur", "en": "Internal"},
    "الخارجي": {"fr": "Extérieur", "en": "External"},
    "الوجه": {"fr": "Face", "en": "Face"},
    "الوزن": {"fr": "Poids", "en": "Weight"},
    "سماكة": {"fr": "Épaisseur", "en": "Thickness"},
    "ركوب": {"fr": "Chevauchement", "en": "Overlap"},
    "خصم": {"fr": "Déduction", "en": "Deduction"},
    "الوسطى": {"fr": "Milieu", "en": "Middle"},
    "مزدوج": {"fr": "Double", "en": "Double"},
    "ثابت": {"fr": "Fixe", "en": "Fixed"},
    "جديد": {"fr": "Nouveau", "en": "New"},
    "بدون": {"fr": "Sans", "en": "Without"},
    "انقر": {"fr": "Cliquez", "en": "Click"},
    "تحديد": {"fr": "Sélectionner", "en": "Select"},
    "كلمة المرور": {"fr": "Mot de passe", "en": "Password"},
    "الجوانات": {"fr": "Joints", "en": "Joints"},
    "الإكسسوارات": {"fr": "Accessoires", "en": "Accessories"},
    "الإعدادات": {"fr": "Paramètres", "en": "Settings"},
    "المصروفات": {"fr": "Dépenses", "en": "Expenses"},
    "العمال": {"fr": "Employés", "en": "Workers"},
    "سلفة": {"fr": "Avance", "en": "Advance"},
    "أجور": {"fr": "Salaires", "en": "Salaries"},
    "عامل": {"fr": "Employé", "en": "Worker"},
  };

  // Find all key blocks
  var regex = RegExp(r"(r?'''?([^']+)'''?:\s*\{\s*AppLanguage\.arabic:\s*r?'''?([^']+)'''?,\s*AppLanguage\.french:\s*)(r?'''?([^']+)'''?)(,\s*AppLanguage\.english:\s*)(r?'''?([^']+)'''?)(,\s*\})", dotAll: true);
  
  String newContent = content.replaceAllMapped(regex, (match) {
    String prefix = match.group(1)!;
    String arText = match.group(3)!;
    String frText = match.group(5)!;
    String enPrefix = match.group(6)!;
    String enText = match.group(8)!;
    String suffix = match.group(9)!;

    // Only translate if they are equal to Arabic (untranslated)
    if (frText == arText && enText == arText) {
      String newFr = arText;
      String newEn = arText;
      
      // Replace words
      dictionary.forEach((arWord, translations) {
        newFr = newFr.replaceAll(arWord, translations['fr']!);
        newEn = newEn.replaceAll(arWord, translations['en']!);
      });

      // Cleanup some formatting
      newFr = newFr.replaceAll(RegExp(r'\s+'), ' ').trim();
      newEn = newEn.replaceAll(RegExp(r'\s+'), ' ').trim();

      return "${prefix}r'''$newFr'''${enPrefix}r'''$newEn'''$suffix";
    }
    
    return match.group(0)!;
  });

  File('lib/settings/localization.dart').writeAsStringSync(newContent);
  print("Localization updated.");
}
