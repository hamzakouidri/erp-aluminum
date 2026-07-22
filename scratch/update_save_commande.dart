import 'dart:io';

void main() {
  String path = 'lib/Commande/add_commande.dart';
  String content = File(path).readAsStringSync();

  // 1. Update insertCommandeDetail in _saveCommande to include manual overrides
  String target1 = """
        await widget.db.insertCommandeDetail(
          idCommande: commandeId,
          largeur: p.width,
          hauteur: p.height,
          windowType: p.zones.any((z) => z.content == ZoneContent.doubleSash)
              ? 'Double Sash'
              : 'Single Sash',
          partitionsJson: jsonEncode(p.toMap()),
          drawingImagePath: imagePath,
          price: p.totalCost,
          quantity: p.quantity,
          color: p.frameColor.toString().split('.').last,
          glass: p.zones.isNotEmpty &&
                  p.zones.first.glass.structure == GlassStructure.double
              ? 'Double'
              : 'Single',
          volet: p.hasShutter ? 'Yes' : 'No',
        );
""";

  String replacement1 = """
        await widget.db.insertCommandeDetail(
          idCommande: commandeId,
          largeur: p.width,
          hauteur: p.height,
          game: p.manualNameOverride ?? '',
          description: p.description ?? '',
          windowType: p.zones.any((z) => z.content == ZoneContent.doubleSash)
              ? 'Double Sash'
              : 'Single Sash',
          partitionsJson: jsonEncode(p.toMap()),
          drawingImagePath: imagePath,
          price: p.manualPriceOverride ?? p.totalCost,
          quantity: p.quantity,
          color: p.frameColor.toString().split('.').last,
          glass: p.zones.isNotEmpty &&
                  p.zones.first.glass.structure == GlassStructure.double
              ? 'Double'
              : 'Single',
          volet: p.hasShutter ? 'Yes' : 'No',
        );
""";

  if (content.contains(target1)) {
    content = content.replaceFirst(target1, replacement1);
  } else {
    print("Target 1 not found in add_commande.dart");
  }

  // 2. Add the button to open OrderTableEditScreen
  String target2 = """
                  const Divider(color: Colors.grey, thickness: 1.0, height: 20),
                  Row(
""";

  String replacement2 = """
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.table_view),
                    label: Text(
                      Localization.translate(
                        "تعديل جدول الفاتورة (سريع)",
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () async {
                      import 'package:database_data/Commande/order_table_edit_screen.dart'; // Dynamic import simulation
                      // Actually, we must import it at the top of the file!
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrderTableEditScreen(products: addedProducts),
                        ),
                      );
                      if (result == true) {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.grey, thickness: 1.0, height: 20),
                  Row(
""";

  if (content.contains(target2) && !content.contains("OrderTableEditScreen")) {
    content = content.replaceFirst(target2, replacement2);
  } else {
    print("Target 2 not found or already added in add_commande.dart");
  }

  // We need to add the import for OrderTableEditScreen
  if (!content.contains("import 'order_table_edit_screen.dart';")) {
    content = content.replaceFirst(
      "import 'dart:convert';",
      "import 'dart:convert';\nimport 'order_table_edit_screen.dart';"
    );
  }

  File(path).writeAsStringSync(content);
  print("Updated add_commande.dart");
}
