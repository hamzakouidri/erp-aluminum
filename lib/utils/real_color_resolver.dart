import 'package:flutter/material.dart';

String normalizeColorName(Object? value) {
  return (value ?? '')
      .toString()
      .toLowerCase()
      .trim()
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'[\s_\-]+'), ' ');
}

String _cleanHex(Object? value) {
  return (value ?? '').toString().trim().replaceAll('#', '').toUpperCase();
}

Color? parseRealHexColor(Object? value) {
  var clean = _cleanHex(value);
  if (clean.isEmpty) return null;
  if (clean.length == 3) {
    clean = clean.split('').map((c) => '$c$c').join();
  }
  if (clean.length == 6) clean = 'FF$clean';
  if (clean.length != 8) return null;
  final parsed = int.tryParse(clean, radix: 16);
  return parsed == null ? null : Color(parsed);
}

bool _isDefaultPlaceholderHex(Object? value) {
  final clean = _cleanHex(value);
  return clean.isEmpty ||
      clean == 'FFF' ||
      clean == 'FFFFFF' ||
      clean == 'FFFFFFFF' ||
      clean == 'F5F5DC' ||
      clean == '9E9E9E' ||
      clean == 'FF9E9E9E';
}

bool isWoodColorName(Object? value) {
  final name = normalizeColorName(value);
  return name.contains('خشب') ||
      name.contains('خشبي') ||
      name.contains('wood') ||
      name.contains('bois') ||
      name.contains('faux') ||
      name.contains('فو') ||
      name.contains('desert') ||
      name.contains('ديزر') ||
      name.contains('ديزير') ||
      name.contains('oak') ||
      name.contains('اوك') ||
      name.contains('بلوط') ||
      name.contains('chene') ||
      name.contains('chêne') ||
      name.contains('noyer') ||
      name.contains('acajou') ||
      name.contains('شين') ||
      name.contains('نويا') ||
      name.contains('اكاجو') ||
      name.contains('بوا') ||
      name.contains('antique') ||
      name.contains('انتيك') ||
      name.contains('onteak') ||
      name.contains('d0') ||
      name.contains('دي زيرو') ||
      name.contains('di zero');
}

/// "Faux bois marron clair" / "خشبي بني فاتح" / "Light brown wood grain".
/// Checked before the generic marron+bois rule, which maps to antique.
bool isLightBrownWoodName(Object? value) {
  final name = normalizeColorName(value);
  return name.contains('marron clair') ||
      name.contains('light brown') ||
      name.contains('بني فاتح');
}

bool isWoodColorData(Map<String, dynamic>? colorData) {
  return isWoodColorName(colorData?['name'] ?? colorData?['color_name']);
}

DecorationImage? realColorTextureImage(Map<String, dynamic>? colorData) {
  final name = normalizeColorName(
    colorData?['name'] ?? colorData?['color_name'],
  );
  if (!isWoodColorName(name)) return null;

  var assetPath = 'assets/images/wood_texture.png';
  if (isLightBrownWoodName(name)) {
    assetPath = 'assets/images/wood_texture_light_brown.png';
  } else if (name.contains('d0') ||
      name.contains('oak') ||
      name.contains('اوك') ||
      name.contains('شين') ||
      name.contains('chene') ||
      name.contains('chêne') ||
      name.contains('بلوط') ||
      name.contains('دي زيرو') ||
      name.contains('di zero') ||
      name.contains('desert') ||
      name.contains('ديزر') ||
      name.contains('ديزير')) {
    assetPath = 'assets/images/wood_texture_d0.png';
  } else if (_isFauxBoisMarron(name)) {
    // The faux-bois grain, lighter: not the aged grey antique.
    return const DecorationImage(
      image: AssetImage('assets/images/wood_texture.png'),
      fit: BoxFit.cover,
      colorFilter: ColorFilter.mode(Color(0x5CFFD9B0), BlendMode.screen),
    );
  } else if (name.contains('antique') ||
      name.contains('انتيك') ||
      name.contains('onteak')) {
    assetPath = 'assets/images/wood_texture_antique.png';
  } else if (name.contains('grey') ||
      name.contains('gray') ||
      name.contains('gris') ||
      name.contains('رمادي')) {
    assetPath = 'assets/images/wood_texture_grey.png';
  } else if (name.contains('dark') ||
      name.contains('داكن') ||
      name.contains('fonce') ||
      name.contains('foncé')) {
    assetPath = 'assets/images/wood_texture_dark.png';
  }

  return DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover);
}

bool _isFauxBoisMarron(String name) =>
    name.contains('faux bois marron') ||
    name.contains('marron faux bois') ||
    (name.contains('marron') &&
        (name.contains('bois') ||
            name.contains('faux') ||
            name.contains('خشب'))) ||
    (name.contains('بني') && (name.contains('خشب') || name.contains('خشبي')));

/// Brushed-metal gradients with a highlight band: a flat hex cannot show the
/// shine of gold, silver or champagne anodising.
List<Color>? _metallicGradient(String name) {
  final isGold =
      name.contains('gold') ||
      name.contains('ذهب') ||
      name.contains('doré') ||
      name.contains('dore') ||
      RegExp(r'(^|[\s/(_-])or($|[\s/)_-])').hasMatch(name);
  if (isGold) {
    return const [
      Color(0xFF8A6A1F),
      Color(0xFFD9B44A),
      Color(0xFFFFF3B0),
      Color(0xFFD4AF37),
      Color(0xFF94721F),
    ];
  }
  if (name.contains('silver') ||
      name.contains('argent') ||
      name.contains('فضي') ||
      name.contains('inox')) {
    return const [
      Color(0xFF7B8086),
      Color(0xFFC3C7CC),
      Color(0xFFF5F7F9),
      Color(0xFFB9BEC3),
      Color(0xFF858A90),
    ];
  }
  if (name.contains('champagne') ||
      name.contains('chompagne') ||
      name.contains('شامبان') ||
      name.contains('شمبان') ||
      name.contains('شومبان')) {
    return const [
      Color(0xFFA08A68),
      Color(0xFFD8C6A2),
      Color(0xFFF7EDD8),
      Color(0xFFCDB892),
      Color(0xFFA48D6A),
    ];
  }
  return null;
}

List<Color>? _namedGradient(Object? rawName) {
  final name = normalizeColorName(rawName);
  if (_isFauxBoisMarron(name)) {
    return const [Color(0xFFC79566), Color(0xFFA9774E), Color(0xFF85593A)];
  }
  final metallic = _metallicGradient(name);
  if (metallic != null) return metallic;

  if (name.contains('white') ||
      name.contains('blanc') ||
      name.contains('ابيض')) {
    return [Colors.white, const Color(0xFFF3F4F6), const Color(0xFFD1D5DB)];
  }
  if (name.contains('black') ||
      name.contains('noir') ||
      name.contains('اسود')) {
    return [Colors.grey.shade800, Colors.black87, Colors.black];
  }
  if (name.contains('9007')) {
    return const [Color(0xFFB8C0C8), Color(0xFF8A939E), Color(0xFF606A75)];
  }
  if (name.contains('7024') ||
      name.contains('7824') ||
      name.contains('anthracite') ||
      name.contains('انترسيت')) {
    return const [Color(0xFF6E7688), Color(0xFF565E70), Color(0xFF414858)];
  }
  if (name.contains('grey') ||
      name.contains('gray') ||
      name.contains('gris') ||
      name.contains('رمادي')) {
    return [Colors.grey.shade500, Colors.grey.shade700, Colors.grey.shade800];
  }
  if (name.contains('beige') || name.contains('بيج')) {
    return const [Color(0xFFF5F5DC), Color(0xFFE4DEB8), Color(0xFFC0C090)];
  }
  if (name.contains('brown') ||
      name.contains('marron') ||
      name.contains('بني')) {
    return [
      Colors.brown.shade400,
      Colors.brown.shade700,
      Colors.brown.shade900,
    ];
  }
  if (name.contains('blue') || name.contains('bleu') || name.contains('ازرق')) {
    return [Colors.blue.shade300, Colors.blue.shade600, Colors.blue.shade900];
  }
  if (name.contains('green') ||
      name.contains('vert') ||
      name.contains('اخضر')) {
    return [
      Colors.green.shade300,
      Colors.green.shade600,
      Colors.green.shade900,
    ];
  }
  if (name.contains('red') || name.contains('rouge') || name.contains('احمر')) {
    return [Colors.red.shade300, Colors.red.shade600, Colors.red.shade900];
  }
  if (name.contains('yellow') ||
      name.contains('jaune') ||
      name.contains('اصفر')) {
    return [
      Colors.amber.shade200,
      Colors.amber.shade500,
      Colors.orange.shade700,
    ];
  }
  if (isWoodColorName(name)) {
    return [
      Colors.brown.shade300,
      Colors.brown.shade600,
      Colors.brown.shade900,
    ];
  }
  if (name.contains('brut') || name.contains('raw') || name.contains('خام')) {
    return [Colors.grey.shade300, Colors.grey.shade500, Colors.grey.shade700];
  }
  return null;
}

List<Color> gradientFromColor(Color color) {
  final hsl = HSLColor.fromColor(color);
  final light = hsl
      .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
      .toColor();
  final dark = hsl
      .withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0))
      .toColor();
  return [light, color, dark];
}

List<Color> realGradientColors(
  Map<String, dynamic>? colorData, {
  List<Color>? fallback,
}) {
  final hex =
      colorData?['hex_code'] ?? colorData?['hex'] ?? colorData?['color_hex'];
  final parsed = parseRealHexColor(hex);
  final named = _namedGradient(colorData?['name'] ?? colorData?['color_name']);
  final metallic = _metallicGradient(
    normalizeColorName(colorData?['name'] ?? colorData?['color_name']),
  );
  if (metallic != null) return metallic;

  if (parsed != null && !_isDefaultPlaceholderHex(hex)) {
    return gradientFromColor(parsed);
  }
  if (named != null) return named;
  if (parsed != null) return gradientFromColor(parsed);
  return fallback ??
      [Colors.grey.shade200, Colors.grey.shade300, Colors.grey.shade400];
}

Color realBorderColor(
  Map<String, dynamic>? colorData, {
  Color fallback = Colors.grey,
}) {
  final colors = realGradientColors(
    colorData,
    fallback: [fallback, fallback, fallback],
  );
  final base = colors.length > 1 ? colors[1] : colors.first;
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor();
}
