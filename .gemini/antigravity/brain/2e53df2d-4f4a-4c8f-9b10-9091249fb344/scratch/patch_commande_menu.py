import re

path_commande = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\commande.dart'

with open(path_commande, 'r', encoding='utf-8') as f:
    code = f.read()

# Locate the end of // 1.2. Facture Proforma Sans Prix tile
OLD_TILE_END = """                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),"""

NEW_TILES = """                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // 1.3. Facture Officielle / Proforma
              ListTile(
                leading: const Icon(Icons.description, color: Colors.indigo),
                title: Text(Localization.translate('فاتورة رسمية / أولية', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      isProForma: true,
                    );
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),

              // 1.4. Facture Officielle / Proforma Sans Prix
              ListTile(
                leading: const Icon(Icons.description_outlined, color: Colors.blueGrey),
                title: Text(Localization.translate('فاتورة رسمية / أولية بدون أسعار', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();
                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      hidePrices: true,
                      isProForma: true,
                    );
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DevisPreviewScreen(data: devis),
                      ),
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء توليد الفاتورة: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),"""

assert OLD_TILE_END in code, "Old tile end not found in commande.dart"
# Replace only the first occurrence (which is the Proforma Sans Prix tile end)
code = code.replace(OLD_TILE_END, NEW_TILES, 1)

with open(path_commande, 'w', encoding='utf-8') as f:
    f.write(code)
print("commande.dart updated successfully.")
