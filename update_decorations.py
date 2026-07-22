import re

dart_file = "lib/items_produits/colors.dart"

with open(dart_file, 'r', encoding='utf-8') as f:
    content = f.read()

# Add _getDecorationImageFromName
new_method = """
  DecorationImage? _getDecorationImageFromName(String name) {
    name = name.toLowerCase();
    
    if (name.contains('أنتيك') || name.contains('antique') || name.contains('انتيك')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_antique.png'),
        fit: BoxFit.cover,
      );
    }
    
    if (name.contains('فوبوا كلير') || name.contains('clair') || name.contains('خشبي فاتح')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_d0.png'),
        fit: BoxFit.cover,
      );
    }
    
    if (name.contains('خشبي داكن') || name.contains('foncé') || name.contains('dark')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_dark.png'),
        fit: BoxFit.cover,
      );
    }

    if (name.contains('خشبي') || name.contains('bois') || name.contains('wood') || name.contains('فوبوا')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture.png'),
        fit: BoxFit.cover,
      );
    }
    
    return null;
  }
"""

if "_getDecorationImageFromName" not in content:
    content = content.replace(
        "LinearGradient _getGradientFromName(String name, [String? hexCode]) {",
        new_method + "\n  LinearGradient _getGradientFromName(String name, [String? hexCode]) {"
    )

# Replace occurrences of gradient: _getGradientFromName(...) with gradient: ..., image: _getDecorationImageFromName(...)
# Occurrence 1: line 409
content = content.replace(
    "gradient: _getGradientFromName(\n                                color['name'].toString(),\n                                color['hex_code']?.toString(),\n                              ),",
    "gradient: _getGradientFromName(\n                                color['name'].toString(),\n                                color['hex_code']?.toString(),\n                              ),\n                              image: _getDecorationImageFromName(color['name'].toString()),"
)

# Occurrence 2: line 551
content = content.replace(
    "gradient: _getGradientFromName(\n                                            color['name'].toString(),\n                                            color['hex_code']?.toString(),\n                                          ),",
    "gradient: _getGradientFromName(\n                                            color['name'].toString(),\n                                            color['hex_code']?.toString(),\n                                          ),\n                                          image: _getDecorationImageFromName(color['name'].toString()),"
)

# Occurrence 3: line 770
content = content.replace(
    "gradient: _getGradientFromName(\n                                          cRow['color_name'].toString(),\n                                          cRow['color_hex']?.toString(),\n                                        ),",
    "gradient: _getGradientFromName(\n                                          cRow['color_name'].toString(),\n                                          cRow['color_hex']?.toString(),\n                                        ),\n                                        image: _getDecorationImageFromName(cRow['color_name'].toString()),"
)

# Occurrence 4: line 947
content = content.replace(
    "gradient: _getGradientFromName(\n                                          cRow['color_name'].toString(),\n                                          cRow['color_hex']?.toString(),\n                                        ),",
    "gradient: _getGradientFromName(\n                                          cRow['color_name'].toString(),\n                                          cRow['color_hex']?.toString(),\n                                        ),\n                                        image: _getDecorationImageFromName(cRow['color_name'].toString()),"
)

# Occurrence 5: line 1225
content = content.replace(
    "gradient: _getGradientFromName(\n                                Localization.translate(item['name'].toString().trim(), lang),\n                                item['hex_code']?.toString(),\n                              ),",
    "gradient: _getGradientFromName(\n                                Localization.translate(item['name'].toString().trim(), lang),\n                                item['hex_code']?.toString(),\n                              ),\n                              image: _getDecorationImageFromName(Localization.translate(item['name'].toString().trim(), lang)),"
)

with open(dart_file, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")
