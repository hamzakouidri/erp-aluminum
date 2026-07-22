import sys

sys.stdout.reconfigure(encoding='utf-8')

# 1. Update model.dart
model_path = 'lib/Commande/Systeme/model.dart'
model_content = open(model_path, encoding='utf-8').read()

old_fields = """  String? manualNameOverride;
  double? manualPriceOverride;
  String? description;"""

new_fields = """  String? manualNameOverride;
  double? manualPriceOverride;
  String? description;
  String? position;"""

model_content = model_content.replace(old_fields, new_fields)
open(model_path, 'w', encoding='utf-8').write(model_content)
print("Updated model.dart successfully!")


# 2. Update model_serialization.dart
serialization_path = 'lib/Commande/Systeme/model_serialization.dart'
serialization_content = open(serialization_path, encoding='utf-8').read()

old_serialization = """      'manualNameOverride': manualNameOverride,
      'manualPriceOverride': manualPriceOverride,
      'description': description,"""

new_serialization = """      'manualNameOverride': manualNameOverride,
      'manualPriceOverride': manualPriceOverride,
      'description': description,
      'position': position,"""

serialization_content = serialization_content.replace(old_serialization, new_serialization)

old_deserialization = """  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.description = map['description']?.toString();"""

new_deserialization = """  model.manualNameOverride = map['manualNameOverride']?.toString();
  model.manualPriceOverride = (map['manualPriceOverride'] as num?)?.toDouble();
  model.description = map['description']?.toString();
  model.position = map['position']?.toString();"""

serialization_content = serialization_content.replace(old_deserialization, new_deserialization)
open(serialization_path, 'w', encoding='utf-8').write(serialization_content)
print("Updated model_serialization.dart successfully!")
