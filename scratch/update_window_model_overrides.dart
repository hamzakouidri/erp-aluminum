import 'dart:io';

void main() {
  String path = 'lib/Commande/Systeme/model.dart';
  String content = File(path).readAsStringSync();
  
  String target = """
  double width;
  double height;
  double totalCost = 0.0;
  int quantity = 1;
""";
  
  String replacement = """
  double width;
  double height;
  double totalCost = 0.0;
  int quantity = 1;

  // Manual Overrides
  String? manualNameOverride;
  double? manualPriceOverride;
""";
  
  if (content.contains(target) && !content.contains("manualNameOverride")) {
    content = content.replaceFirst(target, replacement);
    File(path).writeAsStringSync(content);
    print("Added overrides to WindowModel.");
  } else {
    print("Target not found or already added.");
  }
}
