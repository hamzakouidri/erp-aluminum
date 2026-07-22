import 'dart:io';

void main() {
  String content = File('lib/Commande/Systeme/show_system_francais.dart').readAsStringSync();
  
  // Add database import
  if (!content.contains("import 'package:database_data/sql_database.dart';")) {
    content = content.replaceFirst("import 'package:database_data/Commande/Systeme/model.dart';", 
      "import 'package:database_data/Commande/Systeme/model.dart';\nimport 'package:database_data/sql_database.dart';");
  }

  // Add the dialog method
  String dialogMethod = """
  void _showShutterSettingsDialog(BuildContext context) async {
    final db = SqlDatabase();
    final options = await db.getShutterOptions();
    final lames = options['lames']!;
    final glissieres = options['glissieres']!;

    if (!lames.contains(widget.model.shutterLame) && lames.isNotEmpty) {
      widget.model.shutterLame = lames.first;
    }
    if (!glissieres.contains(widget.model.shutterGlissiere) && glissieres.isNotEmpty) {
      widget.model.shutterGlissiere = glissieres.first;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إعدادات الستار (Volet)', style: TextStyle(color: Colors.blue)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الميكانيزم'),
                    value: widget.model.shutterMechanism,
                    items: const [
                      DropdownMenuItem(value: 'Manuel', child: Text('يدوي (Manuel)')),
                      DropdownMenuItem(value: 'Manivelle', child: Text('مانيفيل (Manivelle)')),
                      DropdownMenuItem(value: 'Moteur', child: Text('محرك (Moteur)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => widget.model.shutterMechanism = val);
                        widget.model.refreshUI();
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الشفرات (Lames)'),
                    value: lames.contains(widget.model.shutterLame) ? widget.model.shutterLame : (lames.isNotEmpty ? lames.first : null),
                    items: lames.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => widget.model.shutterLame = val);
                        widget.model.refreshUI();
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'السكة (Glissière)'),
                    value: glissieres.contains(widget.model.shutterGlissiere) ? widget.model.shutterGlissiere : (glissieres.isNotEmpty ? glissieres.first : null),
                    items: glissieres.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => widget.model.shutterGlissiere = val);
                        widget.model.refreshUI();
                      }
                    },
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تم'),
                ),
              ],
            );
          }
        );
      }
    );
  }
""";

  if (!content.contains("_showShutterSettingsDialog")) {
    content = content.replaceFirst("void _showResizeDialog", dialogMethod + "\n  void _showResizeDialog");
  }

  // Add the settings button next to the Shutter switch
  String target = """
                const Text(
                  'ستار (Volet)',
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                Switch(
                  value: widget.model.hasShutter,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleShutter(value),
                ),
""";
  String replacement = """
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'ستار (Volet)',
                      style: TextStyle(color: Colors.black54, fontSize: 11),
                    ),
                    if (widget.model.hasShutter)
                      IconButton(
                        icon: const Icon(Icons.settings, color: Colors.blue, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _showShutterSettingsDialog(context),
                      ),
                  ],
                ),
                Switch(
                  value: widget.model.hasShutter,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleShutter(value),
                ),
""";
  if (!content.contains("onPressed: () => _showShutterSettingsDialog(context)")) {
    content = content.replaceFirst(target, replacement);
  }

  File('lib/Commande/Systeme/show_system_francais.dart').writeAsStringSync(content);
  print("Updated show_system_francais.dart");
}
