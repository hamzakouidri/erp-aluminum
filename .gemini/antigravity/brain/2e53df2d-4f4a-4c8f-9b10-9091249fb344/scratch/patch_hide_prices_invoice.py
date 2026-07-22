import re

path_devis = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_builder.dart'
path_pdf = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\pdf_invoice_api.dart'
path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'
path_partial = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\partial_proforma_screen.dart'
path_commande = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\commande.dart'

# ────────────────────────────────────────────────────
# 5. Update commande.dart
# ────────────────────────────────────────────────────
with open(path_commande, 'r', encoding='utf-8') as f:
    code_commande = f.read()

OLD_COMMANDE_LIST_TILES = """              // 1.5. Facture Proforma Partielle
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.blue),
                title: Text(Localization.translate('فاتورة تقديرية جزئية (Proforma Partielle)', lang)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartialProformaScreen(order: orderData),
                    ),
                  );
                },
              ),"""

NEW_COMMANDE_LIST_TILES = """              // 1.5. Facture Proforma Partielle
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined, color: Colors.blue),
                title: Text(Localization.translate('فاتورة تقديرية جزئية (Proforma Partielle)', lang)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartialProformaScreen(order: orderData),
                    ),
                  );
                },
              ),

              // 1.6. Facture Proforma Partielle Sans Prix
              ListTile(
                leading: const Icon(Icons.print_disabled_outlined, color: Colors.blueGrey),
                title: Text(Localization.translate('فاتورة تقديرية جزئية بدون أسعار', lang)),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PartialProformaScreen(order: orderData, hidePrices: true),
                    ),
                  );
                },
              ),"""

OLD_PROFORMA_TILE = """              // 1. Facture Proforma
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(Localization.translate('فاتورة تقديرية (Facture Proforma)', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
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

NEW_PROFORMA_TILE = """              // 1. Facture Proforma
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(Localization.translate('فاتورة تقديرية (Facture Proforma)', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
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

              // 1.2. Facture Proforma Sans Prix
              ListTile(
                leading: const Icon(Icons.print_disabled, color: Colors.blueGrey),
                title: Text(Localization.translate('فاتورة تقديرية بدون أسعار (Proforma sans prix)', lang)),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    final rawItems = await db.readCommandeDetails(orderData['id']);
                    final List<Map<String, dynamic>> items = rawItems.map((item) => Map<String, dynamic>.from(item)).toList();

                    for (var item in items) {
                      final path = item['drawing_image_path']?.toString() ?? '';
                      if (path.isEmpty || !File(path).existsSync()) {
                        final jsonRaw = item['partitions_json'];
                        if (jsonRaw != null) {
                          try {
                            Map<String, dynamic> modelMap = {};
                            if (jsonRaw is Map<String, dynamic>) {
                              modelMap = jsonRaw;
                            } else if (jsonRaw is Map) {
                              modelMap = Map<String, dynamic>.from(jsonRaw);
                            } else {
                              final str = jsonRaw.toString().trim();
                              if (str.length >= 5) {
                                modelMap = jsonDecode(str) as Map<String, dynamic>;
                              }
                            }
                            if (modelMap.isNotEmpty) {
                              final model = WindowModel(db: db);
                              await applyWindowModelAndLoadCatalog(model, modelMap);
                              final newPath = await saveWindowImageToDisk(model);
                              if (newPath.isNotEmpty) {
                                await db.updateCommandeDetailImagePath(item['id'] as int, newPath);
                                item['drawing_image_path'] = newPath;
                              }
                            }
                          } catch (err) {
                            debugPrint('Error generating missing image: $err');
                          }
                        }
                      }
                    }

                    final workshop = await DevisBuilder.loadWorkshopInfo();
                    final devis = await DevisBuilder.build(
                      order: orderData,
                      items: items,
                      workshop: workshop,
                      hidePrices: true,
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

assert OLD_PROFORMA_TILE in code_commande, "Proforma tile not found in commande"
code_commande = code_commande.replace(OLD_PROFORMA_TILE, NEW_PROFORMA_TILE, 1)

assert OLD_COMMANDE_LIST_TILES in code_commande, "Partial proforma tile not found in commande"
code_commande = code_commande.replace(OLD_COMMANDE_LIST_TILES, NEW_COMMANDE_LIST_TILES, 1)

with open(path_commande, 'w', encoding='utf-8') as f:
    f.write(code_commande)
print("commande.dart updated successfully.")
