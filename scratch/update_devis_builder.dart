import 'dart:io';

void main() {
  String path = 'lib/Commande/devis_builder.dart';
  String content = File(path).readAsStringSync();
  
  // Replace the entire body of _buildLineItem
  int startIndex = content.indexOf('static DevisLineItem _buildLineItem(Map<String, dynamic> item) {');
  int endIndex = content.indexOf('  static String _windowTitle(String? type) {');
  
  if (startIndex != -1 && endIndex != -1) {
    String newBody = """static DevisLineItem _buildLineItem(Map<String, dynamic> item) {
    final type = item['window_type']?.toString();
    final details = <String>[];
    
    String title = _windowTitle(type); // fallback
    String systemType = _windowTitle(type);
    
    // Parse JSON
    final jsonRaw = item['partitions_json'];
    Map<String, dynamic> map = {};
    if (jsonRaw != null && jsonRaw.toString().length >= 5) {
      try {
        map = jsonDecode(jsonRaw.toString()) as Map<String, dynamic>;
      } catch (_) {}
    }

    final seriesName = map['seriesName'];
    final profileName = map['profileName'];
    final manualDesc = map['description']?.toString();
    
    // 1. Profile Name as Title
    if (profileName != null) {
      title = profileName.toString();
    }
    
    // If we have a manual description override, use it!
    if (manualDesc != null && manualDesc.trim().isNotEmpty) {
      details.addAll(manualDesc.trim().split('\\n'));
    } else {
      // --- AUTO GENERATION ---
      // 2. System Name
      details.add(systemType);
      
      // 3. Series Name
      if (seriesName != null) {
        details.add(seriesName.toString());
      } else if (map['isFrame140'] == true) {
        details.add('Série 140');
      } else if (map['profileThickness'] != null) {
        details.add('Épaisseur: \${map['profileThickness']} mm');
      }

      // 4. Dimensions
      final width = map['width'] != null ? (double.tryParse(map['width'].toString())?.toInt() ?? 0) : (double.tryParse(item['largeur']?.toString() ?? '0')?.toInt() ?? 0);
      final height = map['height'] != null ? (double.tryParse(map['height'].toString())?.toInt() ?? 0) : (double.tryParse(item['hauteur']?.toString() ?? '0')?.toInt() ?? 0);
      details.add('Largeur: \$width mm');
      details.add('Hauteur: \$height mm');

      // 5. Handle Height
      if (map['zones'] != null && (map['zones'] as List).isNotEmpty) {
        final z = map['zones'][0];
        final contentStr = z['content']?.toString() ?? '';
        // Only for sashes
        if (contentStr.contains('Sash')) {
          final ratio = double.tryParse(z['handlePositionRatio']?.toString() ?? '0.5') ?? 0.5;
          final handleH = (height * (1.0 - ratio)).toInt();
          details.add('Hauteur Poignée: \$handleH mm');
        }
      }

      // 6. Glass details
      if (map['zones'] != null && (map['zones'] as List).isNotEmpty) {
        final z = map['zones'][0];
        if (z['glass'] != null) {
          final g = z['glass'];
          final structure = g['structure']?.toString() ?? 'single';

          if (structure == 'double') {
              details.add('Vitrage: Double Vitrage');
              String outF = _formatFace(g['finishOuter']?.toString() ?? '', g['colorOuter']?.toString() ?? '', g['processingOuter']?.toString() ?? '');
              String inF = _formatFace(g['finishInner']?.toString() ?? '', g['colorInner']?.toString() ?? '', g['processingInner']?.toString() ?? '');
              details.add('Extérieur: \$outF / Intérieur: \$inF');
          } else {
              details.add('Vitrage: Simple Vitrage');
              String outF = _formatFace(g['finishOuter']?.toString() ?? '', g['colorOuter']?.toString() ?? '', g['processingOuter']?.toString() ?? '');
              details.add('Face: \$outF');
          }
        } else {
            // fallback
            final glass = item['glass']?.toString();
            if (glass != null && glass.isNotEmpty) {
              details.add('Vitrage: \${_glassLabel(glass)}');
            }
        }
      } else {
          // fallback
          final glass = item['glass']?.toString();
          if (glass != null && glass.isNotEmpty) {
              details.add('Vitrage: \${_glassLabel(glass)}');
          }
      }

      // 7. Colors
      final color = item['color']?.toString();
      if (color != null && color.isNotEmpty) {
        details.add('Couleurs: \${_colorLabel(color)}');
      }

      // 8. Shutter
      if (map['hasShutter'] == true) {
        details.add('Volet: \${map['shutterMechanism'] ?? 'Oui'}');
        if (map['shutterLame'] != null) details.add('\${map['shutterLame']}');
        if (map['shutterGlissiere'] != null) details.add('\${map['shutterGlissiere']}');
      } else if (item['volet']?.toString() == 'Yes') {
        details.add('Volet: Oui');
      }
    }

    return DevisLineItem(
      imagePath: item['drawing_image_path']?.toString(),
      title: title,
      details: details,
      unitPrice: _toDouble(item['price']),
      quantity: (item['quantity'] as num?)?.toInt() ?? 1,
    );
  }

""";
    
    content = content.replaceRange(startIndex, endIndex, newBody);
    File(path).writeAsStringSync(content);
    print("Fixed devis_builder.dart");
  } else {
    print("Could not find boundaries.");
  }
}
