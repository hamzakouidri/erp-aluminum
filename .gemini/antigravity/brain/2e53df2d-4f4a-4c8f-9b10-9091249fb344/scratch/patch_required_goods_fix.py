import re

path_goods = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\order_required_goods_screen.dart'

with open(path_goods, 'r', encoding='utf-8') as f:
    code = f.read()

# Replace _resolveBomForModel with correct type checks, database getters and method signatures
OLD_RESOLVE_BOM_METHOD = """  Future<List<BomItem>> _resolveBomForModel(
    WindowModel model,
    Map<String, List<Map<String, dynamic>>> kitBundleData,
    Map<String, bool> kitPerLeafMap,
  ) async {
    final activeVariants = _buildActiveVariants(model);
    final db = widget.db;

    // Generate initial BOM
    final bomItems = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
    );

    final colorId = model.selectedDbColor != null ? model.selectedDbColor!['id'] as int? : null;
    final accessoryColorId = model.selectedAccessoryColor != null ? model.selectedAccessoryColor!['id'] as int? : null;

    for (var item in bomItems) {
      if (item.isMissing && !model.componentOverrides.containsKey(item.originalName)) {
        try {
          // Espagnolette special case
          if (item.originalName.contains('إسبانيوليت') || item.originalName.contains('Espagnolette')) {
            final match = RegExp(r'\\d+').firstMatch(item.originalName);
            String targetSize = match != null ? match.group(0)! : '';
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var allEsp = await db.query(
              'Accessories',
              where: "(type LIKE '%إسبانيوليت%' OR LOWER(name) LIKE '%esp%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: [matType],
            );
            if (allEsp.isNotEmpty) {
              Map<String, dynamic>? selectedEsp;
              if (targetSize.isNotEmpty) {
                for (var e in allEsp) {
                  String n = e['name'].toString();
                  String ty = e['type'].toString();
                  if (n.contains(targetSize) || ty.contains(targetSize)) {
                    selectedEsp = e;
                    break;
                  }
                }
              }
              selectedEsp ??= allEsp.first;
              final mutableItem = Map<String, dynamic>.from(selectedEsp);
              double price = 0.0;
              if (accessoryColorId != null) {
                final colorPriceRes = await db.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [selectedEsp['id'], accessoryColorId],
                );
                if (colorPriceRes.isNotEmpty && _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(selectedEsp['price_dzd'] ?? selectedEsp['price']);
                }
              } else {
                price = _safeDouble(selectedEsp['price_dzd'] ?? selectedEsp['price']);
              }
              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
            continue;
          }

          // General cases
          String? table;
          String keywordAr = '';
          String keywordFr = '';

          if (item.category == 'shutter') {
            table = 'ShutterComponents';
            if (item.originalName.contains('Lames') || item.originalName.contains('الشرائح')) {
              keywordFr = 'lame'; keywordAr = 'شريح';
            } else if (item.originalName.contains('Coulisses') || item.originalName.contains('السكك')) {
              keywordFr = 'coulisse'; keywordAr = 'سك';
            } else if (item.originalName.contains('Axe') || item.originalName.contains('المحور')) {
              keywordFr = 'axe'; keywordAr = 'محور';
            } else if (item.originalName.contains('Caisson') || item.originalName.contains('الصندوق')) {
              keywordFr = 'caisson'; keywordAr = 'صندوق';
            } else if (item.originalName.contains('Moteur') || item.originalName.contains('المحرك')) {
              keywordFr = 'moteur'; keywordAr = 'محرك';
            } else if (item.originalName.contains('Manivelle') || item.originalName.contains('المانيفال')) {
              keywordFr = 'manivelle'; keywordAr = 'مانيفال';
            } else if (item.originalName.contains('Tandem') || item.originalName.contains('طانديم')) {
              keywordFr = 'tandem'; keywordAr = 'طانديم';
            } else if (item.originalName.contains('Lame Finale') || item.originalName.contains('الشريحة النهائية')) {
              keywordFr = 'finale'; keywordAr = 'نهائي';
            } else if (item.originalName.contains('Joint Brosse') || item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross'; keywordAr = 'بروس';
            } else if (item.originalName.contains('Kit') || item.originalName.contains('كيت')) {
              keywordFr = 'kit'; keywordAr = 'كيت';
            } else if (item.originalName.contains('Attache') || item.originalName.contains('أطاش')) {
              keywordFr = 'attache'; keywordAr = 'أطاش';
            } else if (item.originalName.contains('Support Moteur') || item.originalName.contains('سيبور موتور')) {
              keywordFr = 'support_moteur'; keywordAr = 'سيبور موتور';
            } else if (item.originalName.contains('Embout') || item.originalName.contains('الامبو')) {
              keywordFr = 'embout'; keywordAr = 'امبو';
            } else if (item.originalName.contains('Support Roulement') || item.originalName.contains('سيبور رولمو')) {
              keywordFr = 'support_roulement'; keywordAr = 'سيبور رولمو';
            } else if (item.originalName.contains('Bouchons Lames') || item.originalName.contains('أغطية الشفرات')) {
              keywordFr = 'bouchon_lame'; keywordAr = 'أغطية الشفرات';
            }
          } else if (item.category == 'accessory') {
            table = 'Accessories';
            if (item.originalName.contains('المقبض') || item.originalName.contains('Handle')) {
              keywordFr = 'poign'; keywordAr = 'مقبض';
            } else if (item.originalName.contains('المفاصل') || item.originalName.contains('Hinges')) {
              keywordFr = 'paumel'; keywordAr = 'مفصل';
            } else if (item.originalName.contains('System OB')) {
              keywordFr = 'ob'; keywordAr = 'ob';
            } else if ((item.originalName.contains('الفيرو') || item.originalName.contains('Verrou')) && !item.originalName.contains('Central')) {
              keywordFr = 'verrou'; keywordAr = 'فيرو';
            } else if (item.originalName.contains('براغي') || item.originalName.toLowerCase().contains('screw')) {
              keywordFr = 'visse'; keywordAr = 'براغي';
            } else if (item.originalName.contains('عجلات') || item.originalName.contains('Roulette')) {
              keywordFr = 'roulette'; keywordAr = 'عجل';
            } else if (item.originalName.contains('أونتروماتيك') || item.originalName.contains('Entrematique')) {
              keywordFr = 'intra'; keywordAr = 'انترام';
            } else if (item.originalName.contains('اسبانيولات') || item.originalName.contains('Espagnolette')) {
              keywordFr = 'espagnol'; keywordAr = 'اسبانيول';
            } else if (item.originalName.contains('كاش كوليسون') || item.originalName.contains('Gache coulissant')) {
              keywordFr = 'gache'; keywordAr = 'كاش';
            } else if (item.originalName.contains('صداد') || item.originalName.contains('Arrêt')) {
              keywordFr = 'arret'; keywordAr = 'صداد';
            }
          } else if (item.category == 'joint') {
            table = 'Joints';
            if (item.originalName.contains('Joint Brosse') || item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross'; keywordAr = 'بروس';
            } else if (item.originalName.contains('2mm') || item.originalName.contains('2 ملم')) {
              keywordFr = '2'; keywordAr = '2';
            } else if (item.originalName.contains('3-4mm') || item.originalName.contains('3-4 ملم')) {
              keywordFr = '3'; keywordAr = '3';
            } else if (item.originalName.contains('5-6mm') || item.originalName.contains('5-6 ملم')) {
              keywordFr = '5'; keywordAr = '5';
            } else if (item.originalName.contains('7-8mm') || item.originalName.contains('7-8 ملم')) {
              keywordFr = '7'; keywordAr = '7';
            } else {
              keywordFr = 'joint'; keywordAr = 'جوان';
            }
          } else if (item.category == 'profile') {
            table = 'Sections';
            if (item.originalName.contains('Batmo') || item.originalName.contains('الباتمو')) {
              keywordFr = 'batmo'; keywordAr = 'باتمو';
            } else if (item.originalName.contains('Mullion') || item.originalName.contains('تقسيم الزجاج')) {
              final mullRes = await db.query(
                'Sections',
                where: 'series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ? OR type LIKE ?)',
                whereArgs: [model.activeSeries?.id, '%mullion%', '%mullion%', '%traverse%', '%traverse%', '%تقسيم%', '%تقسيم%'],
                limit: 1,
              );
              if (mullRes.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(mullRes.first);
                double price = 0.0;
                if (colorId != null) {
                  price = await db.getSectionPrice(sectionId: mullRes.first['id'], colorId: colorId, fallbackPrice: _safeDouble(mullRes.first['price']));
                } else {
                  price = _safeDouble(mullRes.first['price']);
                }
                mutableItem['calculated_price'] = price;
                model.componentOverrides[item.originalName] = mutableItem;
              }
              continue;
            } else if (item.originalName.contains('Plinthe') || item.originalName.contains('بلانت')) {
              keywordFr = 'plinthe'; keywordAr = 'بلانت';
            } else if (item.originalName.contains('Traverse') || item.originalName.contains('عرضي')) {
              keywordFr = 'traverse'; keywordAr = 'عرضي';
            } else if (item.originalName.contains('Sash Lateral') || item.originalName.contains('قائم جانبي')) {
              keywordFr = 'sash'; keywordAr = 'جانبي';
            } else if (item.originalName.contains('Sash Central') || item.originalName.contains('قائم وسطي')) {
              keywordFr = 'sash'; keywordAr = 'وسطي';
            } else if (item.originalName.contains('Renfort') || item.originalName.contains('حديد التسليح')) {
              keywordFr = 'renfort'; keywordAr = 'تسليح';
            } else if (item.originalName.contains('Parclose') || item.originalName.contains('باكيت')) {
              keywordFr = 'parclose'; keywordAr = 'باكيت';
            }
          }

          if (table != null) {
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var queryRes = await db.query(
              table,
              where: "(LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR name LIKE ? OR type LIKE ?) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: ['%$keywordFr%', '%$keywordFr%', '%$keywordAr%', '%$keywordAr%', matType],
            );

            if (table == 'Sections' && queryRes.isNotEmpty && model.activeSeries != null) {
              final seriesSections = queryRes.where((s) => s['series_id'] == model.activeSeries!.id).toList();
              if (seriesSections.isNotEmpty) {
                queryRes = seriesSections;
              }
            }

            if (queryRes.isNotEmpty) {
              final matched = queryRes.first;
              final mutableItem = Map<String, dynamic>.from(matched);
              double price = 0.0;

              if (table == 'Sections') {
                if (colorId != null) {
                  price = await db.getSectionPrice(sectionId: matched['id'], colorId: colorId, fallbackPrice: _safeDouble(matched['price']));
                } else {
                  price = _safeDouble(matched['price']);
                }
              } else if (table == 'Accessories') {
                if (accessoryColorId != null) {
                  final colorPriceRes = await db.query(
                    'AccessoryColorPrices',
                    where: 'accessory_id = ? AND color_id = ?',
                    whereArgs: [matched['id'], accessoryColorId],
                  );
                  if (colorPriceRes.isNotEmpty && _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(matched['price_dzd'] ?? matched['price']);
                  }
                } else {
                  price = _safeDouble(matched['price_dzd'] ?? matched['price']);
                }
              } else {
                price = _safeDouble(matched['price']);
              }

              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
          }
        } catch (_) {}
      }
    }

    return ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
    );
  }"""

NEW_RESOLVE_BOM_METHOD = """  Future<List<BomItem>> _resolveBomForModel(
    WindowModel model,
    Map<String, List<Map<String, dynamic>>> kitBundleData,
    Map<String, bool> kitPerLeafMap,
  ) async {
    final activeVariants = _buildActiveVariants(model);
    final dbInstance = await widget.db.db;
    final sqlDb = widget.db;

    // Generate initial BOM
    final bomItems = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
    );

    final colorId = model.selectedDbColor != null ? model.selectedDbColor!['id'] as int? : null;
    final accessoryColorId = model.selectedAccessoryColor != null ? model.selectedAccessoryColor!['id'] as int? : null;

    for (var item in bomItems) {
      if (item.isMissing && !model.componentOverrides.containsKey(item.originalName)) {
        try {
          // Espagnolette special case
          if (item.originalName.contains('إسبانيوليت') || item.originalName.contains('Espagnolette')) {
            final match = RegExp(r'\\d+').firstMatch(item.originalName);
            String targetSize = match != null ? match.group(0)! : '';
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var allEsp = await dbInstance.query(
              'Accessories',
              where: "(type LIKE '%إسبانيوليت%' OR LOWER(name) LIKE '%esp%') AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: [matType],
            );
            if (allEsp.isNotEmpty) {
              Map<String, dynamic>? selectedEsp;
              if (targetSize.isNotEmpty) {
                for (var e in allEsp) {
                  String n = e['name'].toString();
                  String ty = e['type'].toString();
                  if (n.contains(targetSize) || ty.contains(targetSize)) {
                    selectedEsp = e;
                    break;
                  }
                }
              }
              selectedEsp ??= allEsp.first;
              final mutableItem = Map<String, dynamic>.from(selectedEsp);
              double price = 0.0;
              if (accessoryColorId != null) {
                final colorPriceRes = await dbInstance.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [selectedEsp['id'], accessoryColorId],
                );
                if (colorPriceRes.isNotEmpty && _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(selectedEsp['price_dzd'] ?? selectedEsp['price']);
                }
              } else {
                price = _safeDouble(selectedEsp['price_dzd'] ?? selectedEsp['price']);
              }
              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
            continue;
          }

          // General cases
          String? table;
          String keywordAr = '';
          String keywordFr = '';

          if (item.category == 'shutter') {
            table = 'ShutterComponents';
            if (item.originalName.contains('Lames') || item.originalName.contains('الشرائح')) {
              keywordFr = 'lame'; keywordAr = 'شريح';
            } else if (item.originalName.contains('Coulisses') || item.originalName.contains('السكك')) {
              keywordFr = 'coulisse'; keywordAr = 'سك';
            } else if (item.originalName.contains('Axe') || item.originalName.contains('المحور')) {
              keywordFr = 'axe'; keywordAr = 'محور';
            } else if (item.originalName.contains('Caisson') || item.originalName.contains('الصندوق')) {
              keywordFr = 'caisson'; keywordAr = 'صندوق';
            } else if (item.originalName.contains('Moteur') || item.originalName.contains('المحرك')) {
              keywordFr = 'moteur'; keywordAr = 'محرك';
            } else if (item.originalName.contains('Manivelle') || item.originalName.contains('المانيفال')) {
              keywordFr = 'manivelle'; keywordAr = 'مانيفال';
            } else if (item.originalName.contains('Tandem') || item.originalName.contains('طانديم')) {
              keywordFr = 'tandem'; keywordAr = 'طانديم';
            } else if (item.originalName.contains('Lame Finale') || item.originalName.contains('الشريحة النهائية')) {
              keywordFr = 'finale'; keywordAr = 'نهائي';
            } else if (item.originalName.contains('Joint Brosse') || item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross'; keywordAr = 'بروس';
            } else if (item.originalName.contains('Kit') || item.originalName.contains('كيت')) {
              keywordFr = 'kit'; keywordAr = 'كيت';
            } else if (item.originalName.contains('Attache') || item.originalName.contains('أطاش')) {
              keywordFr = 'attache'; keywordAr = 'أطاش';
            } else if (item.originalName.contains('Support Moteur') || item.originalName.contains('سيبور موتور')) {
              keywordFr = 'support_moteur'; keywordAr = 'سيبور موتور';
            } else if (item.originalName.contains('Embout') || item.originalName.contains('الامبو')) {
              keywordFr = 'embout'; keywordAr = 'امبو';
            } else if (item.originalName.contains('Support Roulement') || item.originalName.contains('سيبور رولمو')) {
              keywordFr = 'support_roulement'; keywordAr = 'سيبور رولمو';
            } else if (item.originalName.contains('Bouchons Lames') || item.originalName.contains('أغطية الشفرات')) {
              keywordFr = 'bouchon_lame'; keywordAr = 'أغطية الشفرات';
            }
          } else if (item.category == 'accessory') {
            table = 'Accessories';
            if (item.originalName.contains('المقبض') || item.originalName.contains('Handle')) {
              keywordFr = 'poign'; keywordAr = 'مقبض';
            } else if (item.originalName.contains('المفاصل') || item.originalName.contains('Hinges')) {
              keywordFr = 'paumel'; keywordAr = 'مفصل';
            } else if (item.originalName.contains('System OB')) {
              keywordFr = 'ob'; keywordAr = 'ob';
            } else if ((item.originalName.contains('الفيرو') || item.originalName.contains('Verrou')) && !item.originalName.contains('Central')) {
              keywordFr = 'verrou'; keywordAr = 'فيرو';
            } else if (item.originalName.contains('براغي') || item.originalName.toLowerCase().contains('screw')) {
              keywordFr = 'visse'; keywordAr = 'براغي';
            } else if (item.originalName.contains('عجلات') || item.originalName.contains('Roulette')) {
              keywordFr = 'roulette'; keywordAr = 'عجل';
            } else if (item.originalName.contains('أونتروماتيك') || item.originalName.contains('Entrematique')) {
              keywordFr = 'intra'; keywordAr = 'انترام';
            } else if (item.originalName.contains('اسبانيولات') || item.originalName.contains('Espagnolette')) {
              keywordFr = 'espagnol'; keywordAr = 'اسبانيول';
            } else if (item.originalName.contains('كاش كوليسون') || item.originalName.contains('Gache coulissant')) {
              keywordFr = 'gache'; keywordAr = 'كاش';
            } else if (item.originalName.contains('صداد') || item.originalName.contains('Arrêt')) {
              keywordFr = 'arret'; keywordAr = 'صداد';
            }
          } else if (item.category == 'joint') {
            table = 'Joints';
            if (item.originalName.contains('Joint Brosse') || item.originalName.contains('جوان بروس')) {
              keywordFr = 'bross'; keywordAr = 'بروس';
            } else if (item.originalName.contains('2mm') || item.originalName.contains('2 ملم')) {
              keywordFr = '2'; keywordAr = '2';
            } else if (item.originalName.contains('3-4mm') || item.originalName.contains('3-4 ملم')) {
              keywordFr = '3'; keywordAr = '3';
            } else if (item.originalName.contains('5-6mm') || item.originalName.contains('5-6 ملم')) {
              keywordFr = '5'; keywordAr = '5';
            } else if (item.originalName.contains('7-8mm') || item.originalName.contains('7-8 ملم')) {
              keywordFr = '7'; keywordAr = '7';
            } else {
              keywordFr = 'joint'; keywordAr = 'جوان';
            }
          } else if (item.category == 'profile') {
            table = 'Sections';
            if (item.originalName.contains('Batmo') || item.originalName.contains('الباتمو')) {
              keywordFr = 'batmo'; keywordAr = 'باتمو';
            } else if (item.originalName.contains('Mullion') || item.originalName.contains('تقسيم الزجاج')) {
              final mullRes = await dbInstance.query(
                'Sections',
                where: 'series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ? OR type LIKE ?)',
                whereArgs: [model.activeSeries?.id, '%mullion%', '%mullion%', '%traverse%', '%traverse%', '%تقسيم%', '%تقسيم%'],
                limit: 1,
              );
              if (mullRes.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(mullRes.first);
                double price = await sqlDb.getSectionPrice(mullRes.first['id'], colorId);
                if (price <= 0) {
                  price = _safeDouble(mullRes.first['price']);
                }
                mutableItem['calculated_price'] = price;
                model.componentOverrides[item.originalName] = mutableItem;
              }
              continue;
            } else if (item.originalName.contains('Plinthe') || item.originalName.contains('بلانت')) {
              keywordFr = 'plinthe'; keywordAr = 'بلانت';
            } else if (item.originalName.contains('Traverse') || item.originalName.contains('عرضي')) {
              keywordFr = 'traverse'; keywordAr = 'عرضي';
            } else if (item.originalName.contains('Sash Lateral') || item.originalName.contains('قائم جانبي')) {
              keywordFr = 'sash'; keywordAr = 'جانبي';
            } else if (item.originalName.contains('Sash Central') || item.originalName.contains('قائم وسطي')) {
              keywordFr = 'sash'; keywordAr = 'وسطي';
            } else if (item.originalName.contains('Renfort') || item.originalName.contains('حديد التسليح')) {
              keywordFr = 'renfort'; keywordAr = 'تسليح';
            } else if (item.originalName.contains('Parclose') || item.originalName.contains('باكيت')) {
              keywordFr = 'parclose'; keywordAr = 'باكيت';
            }
          }

          if (table != null) {
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var queryRes = await dbInstance.query(
              table,
              where: "(LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR name LIKE ? OR type LIKE ?) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: ['%$keywordFr%', '%$keywordFr%', '%$keywordAr%', '%$keywordAr%', matType],
            );

            if (table == 'Sections' && queryRes.isNotEmpty && model.activeSeries != null) {
              final seriesSections = queryRes.where((s) => s['series_id'] == model.activeSeries!.id).toList();
              if (seriesSections.isNotEmpty) {
                queryRes = seriesSections;
              }
            }

            if (queryRes.isNotEmpty) {
              final matched = queryRes.first;
              final mutableItem = Map<String, dynamic>.from(matched);
              double price = 0.0;

              if (table == 'Sections') {
                price = await sqlDb.getSectionPrice(matched['id'], colorId);
                if (price <= 0) {
                  price = _safeDouble(matched['price']);
                }
              } else if (table == 'Accessories') {
                if (accessoryColorId != null) {
                  final colorPriceRes = await dbInstance.query(
                    'AccessoryColorPrices',
                    where: 'accessory_id = ? AND color_id = ?',
                    whereArgs: [matched['id'], accessoryColorId],
                  );
                  if (colorPriceRes.isNotEmpty && _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(matched['price_dzd'] ?? matched['price']);
                  }
                } else {
                  price = _safeDouble(matched['price_dzd'] ?? matched['price']);
                }
              } else {
                price = _safeDouble(matched['price']);
              }

              mutableItem['calculated_price'] = price;
              model.componentOverrides[item.originalName] = mutableItem;
            }
          }
        } catch (_) {}
      }
    }

    return ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
    );
  }"""

assert OLD_RESOLVE_BOM_METHOD in code, "OLD_RESOLVE_BOM_METHOD not found in order_required_goods_screen.dart"
code = code.replace(OLD_RESOLVE_BOM_METHOD, NEW_RESOLVE_BOM_METHOD, 1)

with open(path_goods, 'w', encoding='utf-8') as f:
    f.write(code)
print("order_required_goods_screen.dart resolved errors successfully.")
