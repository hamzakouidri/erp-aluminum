import re

path_goods = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\order_required_goods_screen.dart'

with open(path_goods, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update _buildActiveVariants to reflect useSystemOB, useDemiOB, useVerrouCentral
OLD_BUILD_VARIANTS = """  Map<String, bool> _buildActiveVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';

    return {
      'Verrou Central': false,
      'System OB': false,
      'Demi System OB': false,
      'كيت (Kit)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)': isTunnel || isMotor,
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت فولي (Kit Volet)': !isTunnel && !isMotor && !isCrank,
      'كيت حزام (Kit Sangle)': false,
    };
  }"""

NEW_BUILD_VARIANTS = """  Map<String, bool> _buildActiveVariants(WindowModel model) {
    final isTunnel = model.isCaissonTunnel;
    final isMotor = model.shutterMechanism == 'محرك';
    final isCrank =
        model.shutterMechanism == 'منايفال' ||
        model.shutterMechanism == 'مانيفال' ||
        model.shutterMechanism == 'مانيفر';

    return {
      'Verrou Central': model.useVerrouCentral,
      'System OB': model.useSystemOB,
      'Demi System OB': model.useDemiOB,
      'كيت (Kit)': false,
      'طانديم (Tandem)': isTunnel,
      'الامبو (Embout)': isMotor,
      'سيبور رولمو (Support Roulement)': isMotor,
      'سيبور موتور (Support Moteur)': isMotor || isTunnel,
      'أغطية الشفرات (Bouchons Lames)': isTunnel || isMotor,
      'كيت فولي موتور (Kit Volet Moteur)': !isTunnel && isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': !isTunnel && isCrank,
      'كيت مانيفر (Kit Manivelle)': !isTunnel && isCrank,
      'كيت فولي (Kit Volet)': !isTunnel && !isMotor && !isCrank,
      'كيت حزام (Kit Sangle)': false,
    };
  }"""

assert OLD_BUILD_VARIANTS in code, "_buildActiveVariants not found in order_required_goods_screen.dart"
code = code.replace(OLD_BUILD_VARIANTS, NEW_BUILD_VARIANTS, 1)

# 2. Add _safeDouble and _resolveBomForModel helper methods to _OrderRequiredGoodsScreenState
HELPERS_CODE = """  double _safeDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  Future<List<BomItem>> _resolveBomForModel(
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

# Insert HELPERS_CODE right before _loadAndAggregate
OLD_LOAD_AGGREGATE_START = """  Future<void> _loadAndAggregate() async {"""
code = code.replace(OLD_LOAD_AGGREGATE_START, HELPERS_CODE + "\n\n  Future<void> _loadAndAggregate() async {", 1)

# 3. Update the inner loop of _loadAndAggregate to load kit bundles correctly and invoke _resolveBomForModel
OLD_INNER_LOOP = """          // تحضير activeVariants بنفس المنطق في material_consumption_screen
          final activeVariants = _buildActiveVariants(model);

          // جلب kit bundle data من قاعدة البيانات
          final kitBundleData = await _loadKitBundleData(model);
          final kitPerLeafMap = <String, bool>{};
          for (final entry in kitBundleData.entries) {
            // per_leaf موجود داخل بيانات الكيت الأصلية - نستعمل false كافتراضي
            kitPerLeafMap[entry.key] = false;
          }

          // Read instances if they exist
          final instancesJson = item['instances_json'];
          List<Map<String, dynamic>> instances = [];
          if (instancesJson != null && instancesJson.toString().isNotEmpty) {
            try {
              final decoded = jsonDecode(instancesJson.toString()) as List<dynamic>;
              instances = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            } catch (_) {}
          }

          final List<BomItem> bomItems = [];

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            for (final inst in instances) {
              final double w = (inst['width'] as num).toDouble();
              final double h = (inst['height'] as num).toDouble();
              final int qty = inst['qty'] as int;

              model.width = w;
              model.height = h;
              model.quantity = qty;

              // Generate BOM for this specific instance
              final instBom = ComponentCalculator.generateBom(
                model,
                activeVariants,
                kitBundleData: kitBundleData,
                kitPerLeafMap: kitPerLeafMap,
              );
              bomItems.addAll(instBom);
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            final instBom = ComponentCalculator.generateBom(
              model,
              activeVariants,
              kitBundleData: kitBundleData,
              kitPerLeafMap: kitPerLeafMap,
            );
            bomItems.addAll(instBom);
          }"""

NEW_INNER_LOOP = """          // جلب kit bundle data من قاعدة البيانات بشكل كامل وتثبيت خيار per_leaf الصحيح
          final kitBundleData = <String, List<Map<String, dynamic>>>{};
          final kitPerLeafMap = <String, bool>{};
          try {
            final kits = await widget.db.readKitBundles();
            for (final kit in kits) {
              final kitName = kit['name'] as String? ?? '';
              if (kitName.isEmpty) continue;
              final kitId = kit['id'] as int;
              final details = await widget.db.readKitBundleItemsWithDetails(kitId);
              final mutableDetails = details.map((e) => Map<String, dynamic>.from(e)).toList();
              kitBundleData[kitName] = mutableDetails;
              kitPerLeafMap[kitName] = (kit['per_leaf'] ?? 0) == 1;
            }
          } catch (_) {}

          // Read instances if they exist
          final instancesJson = item['instances_json'];
          List<Map<String, dynamic>> instances = [];
          if (instancesJson != null && instancesJson.toString().isNotEmpty) {
            try {
              final decoded = jsonDecode(instancesJson.toString()) as List<dynamic>;
              instances = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
            } catch (_) {}
          }

          final List<BomItem> bomItems = [];

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            for (final inst in instances) {
              final double w = (inst['width'] as num).toDouble();
              final double h = (inst['height'] as num).toDouble();
              final int qty = inst['qty'] as int;

              model.width = w;
              model.height = h;
              model.quantity = qty;

              // Generate BOM for this specific instance using the new resolver
              final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
              bomItems.addAll(instBom);
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
            bomItems.addAll(instBom);
          }"""

assert OLD_INNER_LOOP in code, "OLD_INNER_LOOP not found in order_required_goods_screen.dart"
code = code.replace(OLD_INNER_LOOP, NEW_INNER_LOOP, 1)

with open(path_goods, 'w', encoding='utf-8') as f:
    f.write(code)
print("order_required_goods_screen.dart resolved and optimized successfully.")
