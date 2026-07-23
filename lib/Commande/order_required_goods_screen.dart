import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/widgets/section_image.dart';


// ─────────────────────────────────────────────────────────────────────────────
// نموذج سلعة مجمّعة بعد الجمع من كل المنتجات
// ─────────────────────────────────────────────────────────────────────────────
class ProductBreakdown {
  final int index;
  final String name;
  final int qty;
  final double width;
  final double height;
  final WindowModel model;
  final List<BomItem> bomItems;

  ProductBreakdown({
    required this.index,
    required this.name,
    required this.qty,
    required this.width,
    required this.height,
    required this.model,
    required this.bomItems,
  });
}

class AggregatedGoodItem {
  final String name;
  final String originalName;
  final String category;
  final String unit;
  final String? imagePath;
  double unitPrice; // non-final to allow computing it later for kits
  double totalQuantity;
  double totalCost;
  final String? profileCode;
  
  // 🟢 List of sub-items if this item is a grouped Kit
  final List<BomItem> kitSubItems;
  final String? kitGroupName;

  AggregatedGoodItem({
    required this.name,
    required this.originalName,
    required this.category,
    required this.unit,
    this.imagePath,
    required this.unitPrice,
    required this.totalQuantity,
    required this.totalCost,
    this.profileCode,
    this.kitSubItems = const [],
    this.kitGroupName,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// الشاشة الرئيسية
// ─────────────────────────────────────────────────────────────────────────────
class OrderRequiredGoodsScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderRequiredGoodsScreen({
    super.key,
    required this.orderData,
    required this.db,
  });

  @override
  State<OrderRequiredGoodsScreen> createState() =>
      _OrderRequiredGoodsScreenState();
}

class _OrderRequiredGoodsScreenState extends State<OrderRequiredGoodsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AggregatedGoodItem> _aggregatedItems = [];
  int _productCount = 0;
  List<ProductBreakdown> _productBreakdowns = [];
  final Set<String> _expandedKits = {};
  late AppLanguage _currentLang;

  @override
  void initState() {
    super.initState();
    _currentLang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    _loadAndAggregate();
  }

  // ─────────────────────────────────────────────────────────────────
  // الدالة الرئيسية: تقرأ كل منتجات الطلبية وتحسب وتجمع السلع
  // ─────────────────────────────────────────────────────────────────
  double _safeDouble(dynamic val) {
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
    final dbInstance = (await widget.db.db)!;
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
            final match = RegExp(r'\d+').firstMatch(item.originalName);
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
            } else if (item.originalName.contains('Sash Central') || item.originalName.contains('قائم وسطي') || item.originalName.contains('Chicane')) {
              keywordFr = 'sash'; keywordAr = 'وسطي';
            } else if (item.originalName.contains('Renfort') || item.originalName.contains('حديد التسليح')) {
              keywordFr = 'renfort'; keywordAr = 'تسليح';
            } else if (item.originalName.contains('Rail') || item.originalName.contains('سكة')) {
              keywordFr = 'rail'; keywordAr = 'سكة';
            } else if (item.originalName.contains('Réducteur') ||
                       item.originalName.contains('ريديكتور') ||
                       item.originalName.contains('reducteur') ||
                       item.originalName.contains('مخفض')) {
              keywordFr = '67114'; keywordAr = '67114';
            } else if (item.originalName.contains('Parclose') ||
                       item.originalName.contains('باكيت')) {
              keywordFr = 'parclose'; keywordAr = 'باكيت';
            }
          }

          if (table != null) {
            final matType = model.isPVC ? 'PVC' : 'Aluminium';
            var queryRes = await dbInstance.query(
              table,
              where: "(LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR name LIKE ? OR type LIKE ? OR code LIKE ?) AND (is_active = 1 OR is_active IS NULL) AND (material_type = ? OR material_type = 'Both' OR material_type IS NULL OR material_type = '')",
              whereArgs: ['%$keywordFr%', '%$keywordFr%', '%$keywordAr%', '%$keywordAr%', '%$keywordFr%', matType],
            );

            // 🟢 تصفية الجوانات حسب السلسلة الحالية (series_id / series_ids)
            // مهم جداً لضمان أن جوان البروس يخص السلسلة المختارة لا أي سلسلة أخرى
            if (table == 'Joints' && queryRes.isNotEmpty && model.activeSeries != null) {
              final sid = model.activeSeries!.id;
              final sidStr = sid.toString();
              // أولاً: تصفية بـ series_id المباشر
              final exactMatch = queryRes.where((j) => j['series_id'] == sid).toList();
              if (exactMatch.isNotEmpty) {
                queryRes = exactMatch;
              } else {
                // ثانياً: تصفية بـ series_ids (قائمة مفصولة بفاصلة)
                final idsMatch = queryRes.where((j) {
                  final ids = (j['series_ids'] ?? '').toString();
                  return ids.split(',').map((e) => e.trim()).contains(sidStr);
                }).toList();
                if (idsMatch.isNotEmpty) {
                  queryRes = idsMatch;
                }
                // إذا لم يوجد تطابق بالسلسلة → نأخذ الجوانات العامة (series_id = null)
                else {
                  final globalJoints = queryRes.where((j) {
                    final s = j['series_id'];
                    final ids = (j['series_ids'] ?? '').toString().trim();
                    return s == null && ids.isEmpty;
                  }).toList();
                  if (globalJoints.isNotEmpty) queryRes = globalJoints;
                }
              }
            }

            if (table == 'Sections' && queryRes.isNotEmpty) {
              if (model.activeSeries != null) {
                final seriesSections = queryRes.where((s) => s['series_id'] == model.activeSeries!.id).toList();
                if (seriesSections.isNotEmpty) {
                  queryRes = seriesSections;
                }
              }

              final origLower = item.originalName.toLowerCase();
              if (origLower.contains('rail') || origLower.contains('سكة')) {
                // استبعاد الإطارات Cadre 2 Rail / Cadre 3 Rail من نتائج السكة Rail
                final railMatches = queryRes.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  return (t == 'rail' || t.contains('rail') || n == 'rail' || n.startsWith('rail') || n.contains('سكة')) &&
                      !t.contains('frame') &&
                      !t.contains('cadre') &&
                      !n.contains('cadre') &&
                      !n.contains('إطار') &&
                      !n.contains('cadre 2 rail') &&
                      !n.contains('cadre 3 rail');
                }).toList();
                if (railMatches.isNotEmpty) {
                  queryRes = railMatches;
                }
              } else if (origLower.contains('réducteur') ||
                  origLower.contains('ريديكتور') ||
                  origLower.contains('reducteur') ||
                  origLower.contains('مخفض')) {
                // للريديكتور: البحث بكود 67114 أو reducteur أو مخفض واستبعاد الإطارات والسكك
                final redMatches = queryRes.where((s) {
                  final t = (s['type'] ?? '').toString().toLowerCase();
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (c.contains('67114') || t.contains('reduct') || n.contains('reduct') || n.contains('مخفض') || n.contains('ريديكتور')) &&
                      !t.contains('frame') && !t.contains('cadre') && !t.contains('rail') &&
                      !n.contains('cadre') && !n.contains('إطار') && !n.contains('rail') && !n.contains('سكة');
                }).toList();
                if (redMatches.isNotEmpty) {
                  queryRes = redMatches;
                }
              } else if (origLower.contains('lateral') || origLower.contains('قائم جانبي')) {
                // للقائم الجانبي: تصفية القوائم الجانبية فقط واستبعاد القائم الوسطي / الشيكان
                final latMatches = queryRes.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (n.contains('latéral') || n.contains('lateral') || n.contains('جانبي') || c.contains('lat'));
                }).toList();
                if (latMatches.isNotEmpty) {
                  queryRes = latMatches;
                }
              } else if (origLower.contains('sash central') || origLower.contains('قائم وسطي')) {
                // للقائم الوسطي: تصفية القوائم الوسطية واستبعاد الجانبي
                final cenMatches = queryRes.where((s) {
                  final n = (s['name'] ?? '').toString().toLowerCase();
                  final c = (s['code'] ?? '').toString().toLowerCase();
                  return (n.contains('central') || n.contains('وسطي') || n.contains('chicane') || c.contains('cen')) &&
                      !n.contains('latéral') &&
                      !n.contains('جانبي');
                }).toList();
                if (cenMatches.isNotEmpty) {
                  queryRes = cenMatches;
                }
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

    await model.loadSeriesTableConfig();

    final generatedBom = ComponentCalculator.generateBom(
      model,
      activeVariants,
      kitBundleData: kitBundleData,
      kitPerLeafMap: kitPerLeafMap,
    );

    return await _applySeriesTableConfigFilter(model, generatedBom);
  }

  Future<List<BomItem>> _applySeriesTableConfigFilter(
    WindowModel model,
    List<BomItem> items,
  ) async {
    int? seriesId = model.activeSeries?.id;
    if (seriesId == null && model.loadedSeriesName != null && model.loadedSeriesName!.isNotEmpty) {
      try {
        final dbInstance = await widget.db.db;
        if (dbInstance != null) {
          final res = await dbInstance.query('Series', where: 'name = ?', whereArgs: [model.loadedSeriesName]);
          if (res.isNotEmpty) {
            seriesId = res.first['id'] as int?;
          }
        }
      } catch (_) {}
    }

    if (seriesId == null) return items;

    final config = await widget.db.getSeriesTableConfig(seriesId);
    if (config == null) return items;

    final allowedAccIdsStr = (config['allowed_accessory_ids'] ?? '').toString();
    final exclAccIdsStr = (config['excluded_accessory_ids'] ?? '').toString();

    final allowedAccIds = allowedAccIdsStr.isEmpty
        ? <int>{}
        : allowedAccIdsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toSet();
    final exclAccIds = exclAccIdsStr.isEmpty
        ? <int>{}
        : exclAccIdsStr.split(',').map((e) => int.tryParse(e.trim())).whereType<int>().toSet();

    if (allowedAccIds.isEmpty && exclAccIds.isEmpty) return items;

    final filtered = <BomItem>[];
    for (var item in items) {
      if (model.isIntegratedFrame) {
        final origLower = item.originalName.toLowerCase();
        final nameLower = item.name.toLowerCase();
        if (origLower.contains('الغطاء الجانبي') ||
            origLower.contains('side cover') ||
            origLower.contains('couvre-joint') ||
            nameLower.contains('الغطاء الجانبي') ||
            nameLower.contains('couvre-joint')) {
          continue; // Strictly remove side cover when frame has integrated cover!
        }
      }

      if (item.category == 'accessory') {
        final override = model.componentOverrides[item.originalName];
        final accId = override != null ? (override['id'] as int?) : null;

        if (accId != null) {
          if (exclAccIds.contains(accId)) continue;
          if (allowedAccIds.isNotEmpty && !allowedAccIds.contains(accId)) continue;
        }
      }
      filtered.add(item);
    }
    return filtered;
  }

  Future<void> _loadAndAggregate() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final orderId = widget.orderData['id'] as int;
      final rawItems = await widget.db.readCommandeDetails(orderId);

      // مخزن التجميع: مفتاح التجميع → السلعة المجمّعة
      // مفتاح التجميع = (originalName + unit + imagePath) لتمييز السلع الفريدة
      final Map<String, AggregatedGoodItem> aggregationMap = {};
      int successCount = 0;
      final List<ProductBreakdown> breakdownsTemp = [];

      for (final item in rawItems) {
        final jsonRaw = item['partitions_json'];
        if (jsonRaw == null) continue;

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
          if (modelMap.isEmpty) continue;

          final model = WindowModel(db: widget.db);
          await applyWindowModelAndLoadCatalog(model, modelMap);

          // 🟢 استبعاد العناصر المشطوبة أو الملغاة (التي سعرها 0.0) من حساب المواد الخام
          final isReplaced = model.isReplaced ||
              (modelMap['isReplaced'] == true || modelMap['isReplaced']?.toString().toLowerCase() == 'true') ||
              ((item['price'] as num?)?.toDouble() == 0.0);
          if (isReplaced) {
            continue;
          }

          // جلب kit bundle data من قاعدة البيانات بشكل كامل وتثبيت خيار per_leaf الصحيح
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
          final productName = item['name']?.toString() ?? 'منتج ${successCount + 1}';

          if (instances.isNotEmpty) {
            final double origW = model.width;
            final double origH = model.height;
            final int origQty = model.quantity;

            int instIdx = 1;
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

              // Create a dedicated instance model for drawing and individual listing
              final instanceModel = WindowModel(db: widget.db);
              await applyWindowModelAndLoadCatalog(instanceModel, modelMap);
              instanceModel.width = w;
              instanceModel.height = h;
              instanceModel.quantity = qty;

              breakdownsTemp.add(ProductBreakdown(
                index: successCount + 1,
                name: '$productName (#$instIdx)',
                qty: qty,
                width: w,
                height: h,
                model: instanceModel,
                bomItems: instBom.where((b) => b.isActive && !b.isMissing).toList(),
              ));
              instIdx++;
            }

            // Restore original values
            model.width = origW;
            model.height = origH;
            model.quantity = origQty;
          } else {
            // Force the window model quantity to match the actual order details quantity
            model.quantity = (item['quantity'] as num?)?.toInt() ?? 1;

            final instBom = await _resolveBomForModel(model, kitBundleData, kitPerLeafMap);
            bomItems.addAll(instBom);

            breakdownsTemp.add(ProductBreakdown(
              index: successCount + 1,
              name: productName,
              qty: model.quantity,
              width: model.width,
              height: model.height,
              model: model,
              bomItems: instBom.where((b) => b.isActive && !b.isMissing).toList(),
            ));
          }

          // إضافة وتجميع السلع (مع تجميع عناصر الـ kit تحت اسم واحد)
          final Set<String> countedKitsInThisWindow = {};
          for (final bom in bomItems) {
            if (!bom.isActive) continue;
            if (bom.isMissing) continue;

            final double bomQty = (bom.exactQuantity ?? bom.quantity);
            final double bomCost = bomQty * bom.unitPrice;

            if (bom.kitGroupName != null && bom.kitGroupName!.isNotEmpty) {
              final String kitName = bom.kitGroupName!;
              final String kitKey = 'KIT___${kitName}___${bom.colorName ?? ''}';

              double kitQtyToAdd = 0.0;
              if (countedKitsInThisWindow.add(kitName)) {
                kitQtyToAdd = model.quantity.toDouble();
              }

              if (aggregationMap.containsKey(kitKey)) {
                final agg = aggregationMap[kitKey]!;
                agg.totalQuantity += kitQtyToAdd;
                agg.totalCost += bomCost;

                final existingSubIndex = agg.kitSubItems.indexWhere((sub) => sub.originalName == bom.originalName && sub.unit == bom.unit);
                if (existingSubIndex != -1) {
                  final existing = agg.kitSubItems[existingSubIndex];
                  agg.kitSubItems[existingSubIndex] = BomItem(
                    category: existing.category,
                    originalName: existing.originalName,
                    profileCode: existing.profileCode,
                    name: existing.name,
                    imagePath: existing.imagePath,
                    colorName: existing.colorName,
                    quantity: existing.quantity + bomQty,
                    unit: existing.unit,
                    unitPrice: existing.unitPrice,
                    isMissing: existing.isMissing,
                    isActive: existing.isActive,
                    kitGroupName: existing.kitGroupName,
                    exactQuantity: (existing.exactQuantity ?? existing.quantity) + bomQty,
                  );
                } else {
                  agg.kitSubItems.add(bom);
                }
              } else {
                aggregationMap[kitKey] = AggregatedGoodItem(
                  name: _currentLang == AppLanguage.french ? 'Kit $kitName' : 'كيت ($kitName)',
                  originalName: kitName,
                  category: 'accessory',
                  unit: _currentLang == AppLanguage.french ? 'Kit' : 'طقم',
                  imagePath: null,
                  unitPrice: 0.0,
                  totalQuantity: kitQtyToAdd,
                  totalCost: bomCost,
                  profileCode: null,
                  kitSubItems: [bom],
                  kitGroupName: kitName,
                );
              }
            } else {
              final String itemIdentifier = (bom.profileCode != null && bom.profileCode!.isNotEmpty)
                  ? '${bom.originalName} (${bom.profileCode})'
                  : bom.originalName;
              final aggregationKey = '${itemIdentifier}___${bom.colorName ?? ''}___${bom.unit}';

              if (aggregationMap.containsKey(aggregationKey)) {
                aggregationMap[aggregationKey]!.totalQuantity += bomQty;
                aggregationMap[aggregationKey]!.totalCost += bomCost;
              } else {
                aggregationMap[aggregationKey] = AggregatedGoodItem(
                  name: bom.name,
                  originalName: bom.originalName,
                  category: bom.category,
                  unit: bom.unit,
                  imagePath: bom.imagePath,
                  unitPrice: bom.unitPrice,
                  totalQuantity: bomQty,
                  totalCost: bomCost,
                  profileCode: bom.profileCode,
                  kitSubItems: const [],
                  kitGroupName: null,
                );
              }
            }
          }

          successCount++;
        } catch (e) {
          debugPrint('Error processing product in order: $e');
        }
      }

      // حساب سعر الوحدة الفعلي لكل طقم (Kit) كمجموع أسعار مكوناته
      for (final item in aggregationMap.values) {
        if (item.kitGroupName != null && item.totalQuantity > 0) {
          double sumPrice = 0.0;
          for (final sub in item.kitSubItems) {
            final ratio = (sub.exactQuantity ?? sub.quantity) / item.totalQuantity;
            sumPrice += sub.unitPrice * ratio;
          }
          item.unitPrice = sumPrice;
        }
      }

      // ترتيب العناصر: البروفيلات أولاً ثم الملحقات
      final sorted = aggregationMap.values.toList();
      sorted.sort((a, b) {
        const order = ['frame', 'sash', 'glass', 'shutter', 'accessory', 'misc'];
        final ai = order.indexOf(a.category);
        final bi = order.indexOf(b.category);
        if (ai != bi) return ai.compareTo(bi);
        return a.name.compareTo(b.name);
      });

      setState(() {
        _aggregatedItems = sorted;
        _productCount = successCount;
        _productBreakdowns = breakdownsTemp;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ أثناء تحميل السلع: $e';
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // بناء activeVariants من الـ model (مطابق لـ _fetchDefaults في material_consumption_screen)
  // ─────────────────────────────────────────────────────────────────
  Map<String, bool> _buildActiveVariants(WindowModel model) {
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
  }



  // ─────────────────────────────────────────────────────────────────
  // حساب مجموع التكاليف الكلية
  // ─────────────────────────────────────────────────────────────────
  double get _grandTotal =>
      _aggregatedItems.fold(0.0, (sum, item) => sum + item.totalCost);

  // ─────────────────────────────────────────────────────────────────
  // ترجمة الفئة إلى نص عربي
  // ─────────────────────────────────────────────────────────────────
  String _categoryLabel(String category) {
    switch (category) {
      case 'frame':
        return '🪟 بروفيل الإطار';
      case 'sash':
        return '🔲 بروفيل الكانة';
      case 'mullion':
        return '📐 بروفيل الفاصل';
      case 'glass':
        return '🔷 الزجاج';
      case 'shutter':
        return '🎛️ مكونات الستارة';
      case 'caisson_tunnel':
        return '📦 Caisson Tunnel';
      case 'accessory':
        return '🔩 الإكسسوارات';
      default:
        return '📦 أخرى';
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'frame':
        return Colors.blue.shade700;
      case 'sash':
        return Colors.indigo.shade600;
      case 'mullion':
        return Colors.purple.shade600;
      case 'glass':
        return Colors.cyan.shade700;
      case 'shutter':
        return Colors.orange.shade700;
      case 'caisson_tunnel':
        return Colors.amber.shade900;
      case 'accessory':
        return Colors.teal.shade600;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final clientFirst = widget.orderData['firstname']?.toString() ?? '';
    final clientLast = widget.orderData['lastname']?.toString() ?? '';
    final clientNameJoined = '$clientFirst $clientLast'.trim();
    final clientDisplay = clientNameJoined.isNotEmpty
        ? clientNameJoined
        : (widget.orderData['client_name']?.toString() ??
           widget.orderData['client_display']?.toString() ??
           'عميل غير معروف');

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF0F4FF),
      appBar: AppBar(
        title: Column(
          children: [
            const Text(
              'السلع المطلوبة',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              clientDisplay,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading && _errorMessage == null && _productBreakdowns.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.table_chart_outlined, color: Colors.white),
              label: const Text(
                'تفاصيل كل منتج',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _showProductBreakdownDialog,
            ),
          if (!_isLoading && _errorMessage == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'إعادة الحساب',
              onPressed: _loadAndAggregate,
            ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _isLoading || _errorMessage != null
          ? null
          : _buildBottomSummary(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF1A237E)),
            SizedBox(height: 16),
            Text(
              'جاري حساب السلع المطلوبة لجميع المنتجات...',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAndAggregate,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_aggregatedItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 72, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'لا توجد سلع محسوبة للطلبية',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 6),
            Text(
              'تأكد أن منتجات الطلبية تحتوي على بيانات كافية',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // شريط معلومات الملخص
        _buildInfoBanner(),
        // القائمة
        Expanded(child: _buildGroupedList()),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجمالي ${_aggregatedItems.length} نوع سلعة من $_productCount منتج',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'السلع المتشابهة مجمّعة تلقائياً',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'التكلفة الإجمالية',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
              Text(
                '${_grandTotal.toStringAsFixed(2)} دج',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList() {
    // تجميع العناصر حسب الفئة
    final Map<String, List<AggregatedGoodItem>> grouped = {};
    for (final item in _aggregatedItems) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      itemCount: grouped.length,
      itemBuilder: (context, groupIndex) {
        final category = grouped.keys.elementAt(groupIndex);
        final items = grouped[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس المجموعة
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _categoryColor(category).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _categoryColor(category).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _categoryLabel(category),
                      style: TextStyle(
                        color: _categoryColor(category),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${items.length} صنف)',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            // عناصر المجموعة
            ...items.map((item) => _buildItemCard(item, category)),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Future<void> _showSectionSelectionDialog(AggregatedGoodItem item, String category) async {
    if (_productBreakdowns.isEmpty) return;
    final model = _productBreakdowns.first.model;
    final activeSeries = model.activeSlidingSeries ?? model.activeSeries;
    if (activeSeries == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dbInstance = await widget.db.db;
    if (dbInstance == null) return;

    final origLower = item.originalName.toLowerCase();
    
    // Fetch all active sections for the active series
    final rawSections = await dbInstance.query(
      'Sections',
      where: 'series_id = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [activeSeries.id],
    );

    if (rawSections.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد قطاعات متوفرة لهذه السلسلة')),
      );
      return;
    }

    List<Map<String, dynamic>> filteredSections = [];

    if (origLower.contains('rail') || origLower.contains('سكة')) {
      // 1. السكة Rail: جلب نوع rail فقط واستبعاد الإطارات Cadre 2 Rail / Cadre 3 Rail
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        return (t == 'rail' || t.contains('rail') || n.startsWith('rail')) &&
            !t.contains('frame') && !t.contains('cadre') && !n.contains('cadre') && !n.contains('إطار');
      }).toList();
    } else if (origLower.contains('réducteur') || origLower.contains('ريديكتور') || origLower.contains('reducteur') || origLower.contains('مخفض')) {
      // 2. الريديكتور Réducteur: جلب كود 67114 أو reducteur واستبعاد الإطارات والسكك
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final c = (s['code'] ?? '').toString().toLowerCase();
        return (c.contains('67114') || t.contains('reduct') || n.contains('reduct') || n.contains('مخفض') || n.contains('ريديكتور')) &&
            !t.contains('frame') && !t.contains('cadre') && !t.contains('rail') &&
            !n.contains('cadre') && !n.contains('إطار') && !n.contains('rail') && !n.contains('سكة');
      }).toList();
    } else if (origLower.contains('side cover') || origLower.contains('غطاء جانبي') || origLower.contains('couvre')) {
      // 3. الغطاء الجانبي Couvre-joint
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        return t.contains('couvre') || t.contains('side_cover') || n.contains('couvre') || n.contains('جانبي') || n.contains('غطاء');
      }).toList();
    } else if (origLower.contains('sash lateral') || origLower.contains('قائم جانبي')) {
      // 4. القائم الجانبي Ouvrant Latéral: تصفية القوائم الجانبية واستبعاد الوسطي / الشيكان
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final c = (s['code'] ?? '').toString().toLowerCase();
        return (t.contains('sash') || t.contains('ouvrant')) &&
            (t.contains('lateral') || n.contains('latéral') || n.contains('lateral') || n.contains('جانبي') || c.contains('104') || c.contains('108')) &&
            !n.contains('central') && !n.contains('وسطي') && !n.contains('chicane');
      }).toList();
    } else if (origLower.contains('sash central') || origLower.contains('قائم وسطي') || origLower.contains('chicane')) {
      // 5. القائم الوسطي Ouvrant Central: تصفية القوائم الوسطية واستبعاد الجانبي
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        final n = (s['name'] ?? '').toString().toLowerCase();
        final c = (s['code'] ?? '').toString().toLowerCase();
        return (t.contains('sash') || t.contains('ouvrant')) &&
            (t.contains('central') || n.contains('central') || n.contains('وسطي') || n.contains('chicane') || c.contains('105') || c.contains('107')) &&
            !n.contains('latéral') && !n.contains('جانبي');
      }).toList();
    } else if (category == 'frame') {
      // الإطار Frame
      filteredSections = rawSections.where((s) {
        final t = (s['type'] ?? '').toString().toLowerCase();
        return t.contains('frame') || t.contains('cadre') || t.contains('إطار');
      }).toList();
    } else {
      filteredSections = List.from(rawSections);
    }

    if (filteredSections.isEmpty) {
      filteredSections = List.from(rawSections);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تغيير قطاع: ${item.name}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredSections.length,
                  itemBuilder: (context, idx) {
                    final sec = filteredSections[idx];
                    final secName = sec['name'] ?? 'بدون اسم';
                    final secCode = sec['code'] ?? '';
                    final imagePath = sec['image_path']?.toString();
                    final displayLabel = secCode.toString().isNotEmpty ? '$secCode - $secName' : secName.toString();

                    return ListTile(
                      leading: SizedBox(
                        width: 36,
                        height: 36,
                        child: SectionImageWidget(
                          code: secCode.toString(),
                          imagePath: imagePath,
                          size: 32,
                        ),
                      ),
                      title: Text(
                        displayLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () async {
                        Navigator.pop(ctx);

                        final sqlDb = SqlDatabase();
                        int? colorId;
                        for (var pb in _productBreakdowns) {
                          if (pb.model.selectedDbColor != null) {
                            colorId = pb.model.selectedDbColor!['id'] as int?;
                            break;
                          }
                        }

                        double price = 0.0;
                        if (colorId != null && sec['id'] != null) {
                          price = await sqlDb.getSectionPrice(sec['id'] as int, colorId);
                        }
                        if (price <= 0) {
                          price = (sec['price'] as num?)?.toDouble() ?? 0.0;
                        }

                        final mutableSec = Map<String, dynamic>.from(sec);
                        mutableSec['calculated_price'] = price;

                        for (var pb in _productBreakdowns) {
                          pb.model.componentOverrides[item.originalName] = mutableSec;
                          if (category == 'frame') {
                            pb.model.frameOverride = mutableSec;
                            pb.model.slidingFrameOverride = mutableSec;
                          } else if (origLower.contains('side cover') || origLower.contains('غطاء جانبي')) {
                            pb.model.sideCoverOverride = mutableSec;
                          }
                        }

                        _loadAndAggregate();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemCard(AggregatedGoodItem item, String category) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _categoryColor(category);
    final roundedQty = _roundQuantity(item.totalQuantity, item.unit);

    final isKit = item.kitGroupName != null && item.kitGroupName!.isNotEmpty;
    final isExpanded = _expandedKits.contains(item.name);

    if (isKit) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedKits.remove(item.name);
                  } else {
                    _expandedKits.add(item.name);
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    // مؤشر الفئة (شريط جانبي ملون)
                    Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // أيقونة الطقم
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.inventory, color: color, size: 24),
                    ),
                    const SizedBox(width: 10),
                    // الاسم والتفاصيل
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _currentLang == AppLanguage.french
                                ? 'Contient ${item.kitSubItems.length} composants (Cliquez pour afficher)'
                                : 'يحتوي على ${item.kitSubItems.length} مكونات (انقر للعرض)',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey.shade500,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // الكمية والتكلفة
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '$roundedQty ${item.unit}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.totalCost.toStringAsFixed(2)} دج',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              Container(
                color: isDark ? const Color(0xFF161616) : Colors.grey.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: item.kitSubItems.map((sub) {
                    final subRoundedQty = _roundQuantity(sub.quantity, sub.unit);
                    final subCost = sub.quantity * sub.unitPrice;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.subdirectory_arrow_left, size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              sub.name,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$subRoundedQty ${sub.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${subCost.toStringAsFixed(2)} دج',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ]
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showSectionSelectionDialog(item, category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // مؤشر الفئة (شريط جانبي ملون)
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                // الصورة أو الأيقونة
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SectionImageWidget(
                      code: item.profileCode,
                      imagePath: item.imagePath,
                      size: 32.0,
                      fallbackIcon: _categoryIcon(category),
                      fallbackColor: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // الاسم والتفاصيل
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.unitPrice.toStringAsFixed(2)} دج / ${item.unit}',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.grey.shade500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // الكمية والتكلفة
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$roundedQty ${item.unit}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.totalCost.toStringAsFixed(2)} دج',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_aggregatedItems.length} صنف من السلع',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 12),
                  ),
                  Text(
                    '${_grandTotal.toStringAsFixed(2)} دج',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A237E),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _loadAndAggregate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('تحديث'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? Colors.black : const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                side: isDark ? const BorderSide(color: Colors.white, width: 1.5) : BorderSide.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: isDark
                    ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────
  // دوال مساعدة
  // ─────────────────────────────────────────────────────────────────

  /// تقريب الكمية بذكاء: الأمتار الخطية تُقرّب لـ 2 خانات عشرية، الأعداد الصحيحة بلا كسور
  String _roundQuantity(double qty, String unit) {
    final unitLower = unit.toLowerCase();
    if (unitLower == 'ml' ||
        unitLower == 'م' ||
        unitLower.contains('متر') ||
        unitLower.contains('meter')) {
      return qty.toStringAsFixed(2);
    }
    // وحدات عدد: اعرض عددًا صحيحًا مع تقريب للأعلى
    final rounded = qty.ceil();
    return '$rounded';
  }

  void _showProductBreakdownDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF0F4FF),
          appBar: AppBar(
            title: const Text('تفاصيل حساب كل منتج', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: isDark ? Theme.of(context).appBarTheme.backgroundColor : const Color(0xFF1A237E),
            foregroundColor: Colors.white,
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: _productBreakdowns.length,
            itemBuilder: (context, index) {
              final pb = _productBreakdowns[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.only(bottom: 24.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Drawing thumbnail
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade900 : Colors.white,
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: pb.model.isCaissonTunnel
                                  ? Image.asset(
                                      'Icon/caisson_tunnel.jpg',
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) =>
                                          Image.asset('assets/Icon/caisson_tunnel.jpg', fit: BoxFit.contain),
                                    )
                                  : CustomPaint(
                                      painter: WindowPainter(model: pb.model),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          // 2. Product basic info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  pb.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark ? Colors.white : const Color(0xFF1A237E),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'المقاس: ${pb.width.toStringAsFixed(0)} مم × ${pb.height.toStringAsFixed(0)} مم',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'الكمية: ${pb.qty} حبة',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'السلسلة: ${pb.model.activeSeries?.name ?? pb.model.activeSlidingSeries?.name ?? "غير محدد"}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // 3. Materials List
                      Text(
                        'العناصر والمواد المحسوبة لهذا المنتج:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Table(
                        border: TableBorder.symmetric(
                          inside: BorderSide(
                            color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1),
                          2: FlexColumnWidth(1),
                          3: FlexColumnWidth(1.2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  'اسم العنصر',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  'الكمية',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  'الوحدة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(6.0),
                                child: Text(
                                  'التكلفة',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...pb.bomItems.map((bom) {
                            final double qty = (bom.exactQuantity ?? bom.quantity);
                            final double cost = qty * bom.unitPrice;
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SectionImageWidget(
                                        code: bom.profileCode,
                                        imagePath: bom.imagePath,
                                        size: 18.0,
                                        fallbackIcon: _categoryIcon(bom.category),
                                        fallbackColor: Colors.grey,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          bom.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    qty.toStringAsFixed(2),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    bom.unit,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6.0),
                                  child: Text(
                                    '${cost.toStringAsFixed(0)} د.ج',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'frame':
        return Icons.square_outlined;
      case 'sash':
        return Icons.open_in_new;
      case 'mullion':
        return Icons.horizontal_rule;
      case 'glass':
        return Icons.grid_on;
      case 'shutter':
        return Icons.layers;
      case 'caisson_tunnel':
        return Icons.dns_rounded;
      case 'accessory':
        return Icons.settings;
      default:
        return Icons.inventory_2;
    }
  }
}
