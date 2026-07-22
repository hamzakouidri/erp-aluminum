import 'dart:io';

void main() {
  String path = 'lib/Commande/add_commande.dart';
  String content = File(path).readAsStringSync();
  
  content = content.replaceAll(
    'sum + (p.totalCost * p.quantity)', 
    'sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity)'
  );
  
  File(path).writeAsStringSync(content);
  print("Updated total calculations in add_commande.dart");
}
