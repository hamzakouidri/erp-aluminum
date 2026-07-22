import 'dart:io';

void main() {
  String path = 'lib/Commande/Systeme/model_serialization.dart';
  String content = File(path).readAsStringSync();
  
  // 1. Update toMap
  String toMapTarget = """
    'manualNameOverride': model.manualNameOverride,
    'manualPriceOverride': model.manualPriceOverride,
""";
  String toMapReplacement = """
    'manualNameOverride': model.manualNameOverride,
    'manualPriceOverride': model.manualPriceOverride,
    'description': model.description,
""";
  
  if (content.contains(toMapTarget)) {
    content = content.replaceFirst(toMapTarget, toMapReplacement);
  } else {
    // Maybe they weren't added yet, let's add them all
    String fallbackTarget = """
    'removedShutterSides': model.removedShutterSides.toList(),
""";
    String fallbackReplacement = """
    'removedShutterSides': model.removedShutterSides.toList(),
    'manualNameOverride': model.manualNameOverride,
    'manualPriceOverride': model.manualPriceOverride,
    'description': model.description,
""";
    if (content.contains(fallbackTarget) && !content.contains("'manualNameOverride'")) {
      content = content.replaceFirst(fallbackTarget, fallbackReplacement);
    }
  }

  // 2. Update applyWindowModelFromMap
  String applyTarget = """
  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.removedShutterSides = (map['removedShutterSides'] as List<dynamic>?)
""";
  String applyReplacement = """
  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.description = map['description']?.toString();
  model.removedShutterSides = (map['removedShutterSides'] as List<dynamic>?)
""";
  
  if (content.contains(applyTarget)) {
    content = content.replaceFirst(applyTarget, applyReplacement);
  } else {
    String fallbackTarget2 = """
  model.removedShutterSides = (map['removedShutterSides'] as List<dynamic>?)
""";
    String fallbackReplacement2 = """
  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.description = map['description']?.toString();
  model.removedShutterSides = (map['removedShutterSides'] as List<dynamic>?)
""";
    if (content.contains(fallbackTarget2) && !content.contains("model.manualNameOverride")) {
      content = content.replaceFirst(fallbackTarget2, fallbackReplacement2);
    }
  }

  File(path).writeAsStringSync(content);
  print("Updated model_serialization.dart");
}
