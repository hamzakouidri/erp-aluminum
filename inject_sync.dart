import 'dart:io';

void main() async {
  final missingFile = File('missing_arabic.txt');
  final locFile = File('lib/settings/localization.dart');
  
  if (!missingFile.existsSync() || !locFile.existsSync()) return;
  
  final missing = await missingFile.readAsLines();
  String locContent = await locFile.readAsString();
  
  final buffer = StringBuffer();
  
  for (var key in missing) {
    if (key.trim().isEmpty) continue;
    // Basic translations or placeholders
    String fr = key;
    String en = key;
    
    // Auto-translate some common ones
    if (key.contains('إضافة')) { fr = 'Ajouter'; en = 'Add'; }
    if (key.contains('تعديل')) { fr = 'Modifier'; en = 'Edit'; }
    if (key.contains('حذف')) { fr = 'Supprimer'; en = 'Delete'; }
    if (key.contains('اسم')) { fr = 'Nom'; en = 'Name'; }
    if (key.contains('سعر')) { fr = 'Prix'; en = 'Price'; }
    if (key.contains('نوع')) { fr = 'Type'; en = 'Type'; }
    
    // Fallback dictionary for common exact matches
    final dict = {
      'الزجاج (Glass)': ['Verre', 'Glass'],
      'الستائر (Shutters)': ['Volets Roulants', 'Shutters'],
      'الطلبات (Orders)': ['Commandes', 'Orders'],
      'المشتريات': ['Achats', 'Purchases'],
      'الصندوق المالي': ['Caisse', 'Treasury'],
      'الزبائن والدفعات': ['Clients & Paiements', 'Clients & Payments'],
      'تسجيل الدخول': ['Connexion', 'Login'],
      'إنشاء حساب': ['Créer un compte', 'Create Account'],
    };
    
    if (dict.containsKey(key)) {
      fr = dict[key]![0];
      en = dict[key]![1];
    }
    
    buffer.writeln("    '''$key''': {");
    buffer.writeln("      AppLanguage.arabic: '''$key''',");
    buffer.writeln("      AppLanguage.french: '''$fr''',");
    buffer.writeln("      AppLanguage.english: '''$en''',");
    buffer.writeln("    },");
  }
  
  // Insert before the last closing brace
  int index = locContent.lastIndexOf('};');
  if (index != -1) {
    locContent = locContent.substring(0, index) + buffer.toString() + locContent.substring(index);
    await locFile.writeAsString(locContent);
    print("Injected ${missing.length} keys!");
  }
}
