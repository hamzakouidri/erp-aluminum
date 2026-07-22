import 'package:flutter/material.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MaterialConsumptionScreen extends StatefulWidget {
  final WindowModel model;

  const MaterialConsumptionScreen({super.key, required this.model});

  @override
  State<MaterialConsumptionScreen> createState() =>
      _MaterialConsumptionScreenState();
}

class _MaterialConsumptionScreenState extends State<MaterialConsumptionScreen> {
  bool showCostPrice = true; // TODO: Link to Manager permission later
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  bool _isBottomBarExpanded = false;

  double _profitMargin = 20.0;
  double _pricePerSqm = 12000.0;
  double _pricePerLinearMeter = 8000.0;
  CostMethod _costMethod = CostMethod.percentage;
  Map<String, List<Map<String, dynamic>>> _kitBundleData = {};
  Map<String, bool> _kitPerLeafMap = {};
  final Map<String, bool> _kitGroupExpanded = {};

  late TextEditingController _profitMarginController;
  late TextEditingController _pricePerSqmController;
  late TextEditingController _pricePerLinearMeterController;

  Future<Map<String, dynamic>?> _findShutterComponent(
    String componentType,
    String subtype,
  ) async {
    final dbInstance = await SqlDatabase().db;
    if (dbInstance == null) return null;
    var queryRes = await dbInstance.query(
      'ShutterComponents',
      where:
          'component_type = ? AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [componentType, subtype],
      limit: 1,
    );
    if (queryRes.isEmpty) {
      queryRes = await dbInstance.query(
        'ShutterComponents',
        where: 'component_type = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [componentType],
        limit: 1,
      );
    }
    if (queryRes.isNotEmpty) {
      final row = Map<String, dynamic>.from(queryRes.first);
      row['calculated_price'] = _safeDouble(row['price_dzd'] ?? row['price']);
      return row;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _findClosestFinalBlade(
    Database dbInstance,
    double targetSize,
    String subtype,
  ) async {
    var finalBlades = await dbInstance.query(
      'ShutterComponents',
      where:
          "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
          "AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [subtype],
    );

    if (finalBlades.isEmpty) {
      finalBlades = await dbInstance.query(
        'ShutterComponents',
        where:
            "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
            "AND (is_active = 1 OR is_active IS NULL)",
      );
    }

    if (finalBlades.isEmpty) return null;

    double parseSize(Map<String, dynamic> component) {
      final sizeStr = getComponentSize(component) ?? '';
      return double.tryParse(sizeStr) ?? 0.0;
    }

    Map<String, dynamic>? closest;
    double minDiff = double.infinity;

    for (final row in finalBlades) {
      final sz = parseSize(row);
      if (sz > 0) {
        final diff = (sz - targetSize).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = row;
        }
      }
    }

    closest ??= finalBlades.first;
    final row = Map<String, dynamic>.from(closest);
    row['calculated_price'] = _safeDouble(row['price_dzd'] ?? row['price']);
    return row;
  }

  Map<String, bool> activeVariants = {
    'Verrou Central': false,
    'System OB': false,
    'Demi System OB': false,
    'كيت (Kit)': false,
    'طانديم (Tandem)': false,
    'الامبو (Embout)': false,
    'سيبور رولمو (Support Roulement)': false,
    'سيبور موتور (Support Moteur)': false,
    'أغطية الشفرات (Bouchons Lames)': false,
  };

  String? _lastAlignedLameKey;

  static const double _rowHeight = 45;
  static const double _wImg = 50;
  static const double _wName = 220;
  static const double _wColor = 100;
  static const double _wLen = 80;
  static const double _wQty = 80;
  static const double _wPrice = 120;
  static const double _wTotal = 120;
  static const double _wCheck = 80;
  static const double _minW =
      _wImg + _wName + _wColor + _wLen + _wQty + _wPrice + _wTotal + _wCheck;

  // --- دالة الجلب الذكي للمكونات الافتراضية ---
  // --- دالة الجلب الذكي للمكونات الافتراضية ---
  Future<void> _fetchDefaults() async {
    await widget.model.updateShutterDefaultsIfNeeded();
    final db = await SqlDatabase().db;
    if (db == null) return;

    try {
      final colorId = widget.model.selectedDbColor?['id'];
      final sqlDb = SqlDatabase();

      // تنظيف الأخطاء القديمة المخزنة للبراغي (التنظيف الذاتي)
      widget.model.componentOverrides.removeWhere((key, val) {
        if (key.contains('براغي') && val is Map) {
          final n = val['name'].toString().toLowerCase();
          final t = (val['type'] ?? '').toString().toLowerCase();
          return n.contains('verrou') ||
              t.contains('verrou') ||
              n.contains('verro') ||
              t.contains('verro') ||
              n.contains('gevisse') ||
              t.contains('gevisse');
        }
        return false;
      });

      // محاذاة القياسات تلقائياً عند فتح الشاشة لتجنب عدم التطابق السابق (مثلاً الصندوق والكيت)
      try {
        final caisson = widget.model.componentOverrides['الصندوق (Caisson)'];
        final isMotor = widget.model.shutterMechanism == 'محرك';
        final isCrank =
            widget.model.shutterMechanism == 'منايفال' ||
            widget.model.shutterMechanism == 'مانيفال' ||
            widget.model.shutterMechanism == 'مانيفر';
        List<String> activeKitKeys = [];
        if (isMotor) {
          activeKitKeys.add('كيت فولي موتور (Kit Volet Moteur)');
        } else if (isCrank) {
          activeKitKeys.addAll([
            'كيت فولي مانيفر (Kit Volet Manivelle)',
            'كيت مانيفر (Kit Manivelle)',
          ]);
        } else {
          // حزام
          activeKitKeys.add('كيت فولي (Kit Volet)');
        }

        for (var kitKey in activeKitKeys) {
          final kit = widget.model.componentOverrides[kitKey];
          if (caisson != null && kit != null) {
            final caissonDigits = getComponentSize(caisson);
            final kitDigits = getComponentSize(kit);
            if (caissonDigits != null &&
                kitDigits != null &&
                caissonDigits != kitDigits) {
              final compRes = await db.query(
                'ShutterComponents',
                where:
                    "(LOWER(name) LIKE '%kit%' OR name LIKE '%كيت%') AND (is_active = 1 OR is_active IS NULL)",
              );
              for (var row in compRes) {
                final rowSize = getComponentSize(row);
                bool isSameSize(String? size1, String? size2) {
                  if (size1 == null || size2 == null) return false;
                  final s1 = size1.replaceAll(RegExp(r'[^0-9]'), '').trim();
                  final s2 = size2.replaceAll(RegExp(r'[^0-9]'), '').trim();
                  if (s1.length >= 2 && s2.length >= 2) {
                    return s1.substring(0, 2) == s2.substring(0, 2);
                  }
                  return s1 == s2;
                }

                bool matches = isSameSize(rowSize, caissonDigits);
                if (matches) {
                  final matchedKit = Map<String, dynamic>.from(row);
                  matchedKit['calculated_price'] = _safeDouble(
                    matchedKit['price_dzd'] ?? matchedKit['price'],
                  );
                  widget.model.componentOverrides[kitKey] = matchedKit;
                  break;
                }
              }
            }
          }
        }

        final lames = widget.model.componentOverrides['الشرائح (Lames)'];
        final coulisses = widget.model.componentOverrides['السكك (Coulisses)'];
        if (lames != null && coulisses != null) {
          final lamesDigits = getComponentSize(lames);
          final coulissesDigits = getComponentSize(coulisses);
          if (lamesDigits != null &&
              coulissesDigits != null &&
              lamesDigits != coulissesDigits) {
            final compRes = await db.query(
              'ShutterComponents',
              where:
                  "(LOWER(name) LIKE '%coulisse%' OR name LIKE '%سك%') AND (is_active = 1 OR is_active IS NULL)",
            );
            for (var row in compRes) {
              if (getComponentSize(row) == lamesDigits) {
                final matchedCoulisse = Map<String, dynamic>.from(row);
                matchedCoulisse['calculated_price'] = _safeDouble(
                  matchedCoulisse['price_dzd'] ?? matchedCoulisse['price'],
                );
                widget.model.componentOverrides['السكك (Coulisses)'] =
                    matchedCoulisse;
                break;
              }
            }
          }
        }

        final finale =
            widget.model.componentOverrides['الشريحة النهائية (Lame Finale)'];
        if (lames != null) {
          final targetSubtype =
              lames['shutter_subtype']?.toString() ?? 'normal';
          final currentLameKey =
              "${lames['id']}_${getComponentSize(lames)}_$targetSubtype";

          if (finale == null ||
              finale['shutter_subtype']?.toString() != targetSubtype ||
              currentLameKey != _lastAlignedLameKey) {
            final lamesSizeStr = getComponentSize(lames) ?? '';
            final lamesSize = double.tryParse(lamesSizeStr) ?? 0.0;
            if (lamesSize > 0) {
              final matchedFinale = await _findClosestFinalBlade(
                db,
                lamesSize,
                targetSubtype,
              );
              if (matchedFinale != null) {
                widget
                        .model
                        .componentOverrides['الشريحة النهائية (Lame Finale)'] =
                    matchedFinale;
              }
            } else {
              final matched = await _findShutterComponent(
                'final_blade',
                targetSubtype,
              );
              if (matched != null) {
                widget
                        .model
                        .componentOverrides['الشريحة النهائية (Lame Finale)'] =
                    matched;
              }
            }
            _lastAlignedLameKey = currentLameKey;
          }

          Future<void> alignComponent(String uiKey, String dbType) async {
            final comp = widget.model.componentOverrides[uiKey];
            if (comp == null ||
                comp['shutter_subtype']?.toString() != targetSubtype) {
              final matched = await _findShutterComponent(
                dbType,
                targetSubtype,
              );
              if (matched != null) {
                widget.model.componentOverrides[uiKey] = matched;
              }
            }
          }

          await alignComponent('المحور (Axe)', 'laxe');

          await alignComponent('أطاش (Attache)', 'attache');
          await alignComponent(
            'سيبور موتور (Support Moteur)',
            'support_moteur',
          );
          await alignComponent('الامبو (Embout)', 'embout');
          await alignComponent(
            'سيبور رولمو (Support Roulement)',
            'support_roulement',
          );
          await alignComponent('طانديم (Tandem)', 'tandem');
          await alignComponent(
            'أغطية الشفرات (Bouchons Lames)',
            'bouchon_lame',
          );

          if (widget.model.shutterMechanism == 'محرك') {
            // 1. Calculate weight
            final bladeSubtype =
                lames['shutter_subtype']?.toString() ?? 'normal';
            final isExtruded = bladeSubtype == 'extruded';

            final bladeSizeStr = getComponentSize(lames) ?? '';
            final bladeSize = double.tryParse(bladeSizeStr) ?? 0.0;
            final is55OrMore = bladeSize >= 55.0;

            double weightCoef = 3.0;
            if (isExtruded) {
              weightCoef = 12.0; // Extruded is 12
            } else if (is55OrMore) {
              weightCoef = 4.0; // Injected >= 55 is 4
            } else {
              weightCoef = 3.0; // Injected < 55 is 3
            }

            final double widthM = widget.model.width / 1000.0;
            final double heightM = widget.model.height / 1000.0;
            final double shutterWeight = widthM * heightM * weightCoef;
            final double requiredNm = shutterWeight / 1.5;

            // 2. Query all active motors
            final motorRes = await db.query(
              'ShutterComponents',
              where:
                  "(component_type = 'Moteur' OR name LIKE '%moteur%' OR name LIKE '%محرك%') AND (is_active = 1 OR is_active IS NULL)",
            );

            Map<String, dynamic>? selectedMotor;
            double bestNmDifference = double.infinity;

            double? parseTorque(Map<String, dynamic> item) {
              final name = item['name']?.toString() ?? '';
              final measurement = item['measurement']?.toString() ?? '';
              final measNum = double.tryParse(measurement);
              if (measNum != null) return measNum;
              final match = RegExp(
                r'(\d+)\s*(?:Nm|nm|N|n|نيوتن)',
              ).firstMatch(name);
              if (match != null) return double.tryParse(match.group(1)!);
              final numMatch = RegExp(r'\d+').firstMatch(name);
              if (numMatch != null) return double.tryParse(numMatch.group(0)!);
              return null;
            }

            for (final row in motorRes) {
              final nm = parseTorque(row);
              if (nm != null) {
                if (nm >= requiredNm) {
                  final diff = nm - requiredNm;
                  if (diff < bestNmDifference) {
                    bestNmDifference = diff;
                    selectedMotor = row;
                  }
                }
              }
            }

            // Fallback: if no motor is strong enough, pick the strongest available
            if (selectedMotor == null && motorRes.isNotEmpty) {
              double maxNm = -1;
              for (final row in motorRes) {
                final nm = parseTorque(row) ?? 0.0;
                if (nm > maxNm) {
                  maxNm = nm;
                  selectedMotor = row;
                }
              }
            }

            if (selectedMotor != null) {
              final matchedMotor = Map<String, dynamic>.from(selectedMotor);
              matchedMotor['calculated_price'] = _safeDouble(
                matchedMotor['price_dzd'] ?? matchedMotor['price'],
              );
              widget.model.componentOverrides['المحرك (Moteur)'] = matchedMotor;

              // 3. Find matching Axis (Axe) with the same diameter
              final motorDiameter = (matchedMotor['motor_diameter'] ?? '')
                  .toString()
                  .trim();
              final motorName = matchedMotor['name'].toString();

              String targetDia = motorDiameter;
              if (targetDia.isEmpty) {
                final diaMatch = RegExp(
                  r'(\d+)\s*(?:mm|ملم)',
                ).firstMatch(motorName);
                if (diaMatch != null) {
                  targetDia = diaMatch.group(1)!;
                } else {
                  if (motorName.contains('60')) {
                    targetDia = '60';
                  } else if (motorName.contains('40')) {
                    targetDia = '40';
                  }
                }
              }

              if (targetDia.isNotEmpty) {
                final axeRes = await db.query(
                  'ShutterComponents',
                  where:
                      "(component_type = 'Axe' OR name LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
                );

                Map<String, dynamic>? selectedAxe;
                for (final row in axeRes) {
                  final axeName = row['name'].toString();
                  final axeDiameter = (row['motor_diameter'] ?? '')
                      .toString()
                      .trim();

                  if (axeDiameter == targetDia || axeName.contains(targetDia)) {
                    selectedAxe = row;
                    break;
                  }
                }

                if (selectedAxe == null && axeRes.isNotEmpty) {
                  selectedAxe = axeRes.first;
                }

                if (selectedAxe != null) {
                  final matchedAxe = Map<String, dynamic>.from(selectedAxe);
                  matchedAxe['calculated_price'] = _safeDouble(
                    matchedAxe['price_dzd'] ?? matchedAxe['price'],
                  );
                  widget.model.componentOverrides['المحور (Axe)'] = matchedAxe;
                }
              }
            }
          }
        }
      } catch (e) {
        print("Error in self-healing alignment: $e");
      }

      // 0. Update color-specific prices for current selections
      if (widget.model.frameOverride != null) {
        final fId = widget.model.frameOverride!['id'];
        double price = await sqlDb.getSectionPrice(fId, colorId);
        widget.model.frameOverride!['calculated_price'] = price;
      }
      if (widget.model.sashOverride != null) {
        final sId = widget.model.sashOverride!['id'];
        double price = await sqlDb.getSectionPrice(sId, colorId);
        widget.model.sashOverride!['calculated_price'] = price;
      }
      if (widget.model.sideCoverOverride != null) {
        final scId = widget.model.sideCoverOverride!['id'];
        double price = await sqlDb.getSectionPrice(scId, colorId);
        widget.model.sideCoverOverride!['calculated_price'] = price;
      }

      // Update color-specific prices for existing overrides in componentOverrides
      for (var key in widget.model.componentOverrides.keys) {
        final override = widget.model.componentOverrides[key];
        if (override != null && override is Map) {
          final id = override['id'];
          if (id != null && colorId != null) {
            final mutable = Map<String, dynamic>.from(override);
            // Try AccessoryColorPrices
            final accPrice = await db.query(
              'AccessoryColorPrices',
              where: 'accessory_id = ? AND color_id = ?',
              whereArgs: [id, colorId],
            );
            if (accPrice.isNotEmpty) {
              final double p = _safeDouble(accPrice.first['price']);
              if (p > 0) {
                mutable['calculated_price'] = p;
                widget.model.componentOverrides[key] = mutable;
                continue;
              }
            }
            // Try ShutterColorPrices
            final shutPrice = await db.query(
              'ShutterColorPrices',
              where: 'shutter_component_id = ? AND color_id = ?',
              whereArgs: [id, colorId],
            );
            if (shutPrice.isNotEmpty) {
              mutable['calculated_price'] = _safeDouble(
                shutPrice.first['price'],
              );
              widget.model.componentOverrides[key] = mutable;
              continue;
            }
            // Try Sections (if profile)
            final secRes = await db.query(
              'Sections',
              where: 'id = ?',
              whereArgs: [id],
            );
            if (secRes.isNotEmpty) {
              double price = await sqlDb.getSectionPrice(id, colorId);
              if (price > 0) {
                mutable['calculated_price'] = price;
                widget.model.componentOverrides[key] = mutable;
              }
            }
          }
        }
      }

      bool isLinked(String key) {
        final val = widget.model.componentOverrides[key];
        return val != null && val is Map && val['id'] != null;
      }

      // 1. جلب حديد الإطار الافتراضي المرتبط
      if (!isLinked('حديد الإطار (Renfort Frame)')) {
        if (widget.model.frameOverride != null &&
            widget.model.frameOverride!['linked_renfort_id'] != null) {
          int rId = widget.model.frameOverride!['linked_renfort_id'] as int;
          final res = await db.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [rId],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            double price = 0.0;
            if (colorId != null) {
              price = await sqlDb.getSectionPrice(rId, colorId);
            } else {
              price = _safeDouble(rMap['price_dzd'] ?? rMap['price']);
            }
            rMap['calculated_price'] = price;
            widget.model.componentOverrides['حديد الإطار (Renfort Frame)'] =
                rMap;
            if (mounted) setState(() {}); // تحديث فوري
          }
        }
      }

      // 2. جلب حديد الظلفة الافتراضي المرتبط
      if (!isLinked('حديد الظلفة (Renfort Sash)')) {
        if (widget.model.sashOverride != null &&
            widget.model.sashOverride!['linked_renfort_id'] != null) {
          int rId = widget.model.sashOverride!['linked_renfort_id'] as int;
          final res = await db.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [rId],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            double price = 0.0;
            if (colorId != null) {
              price = await sqlDb.getSectionPrice(rId, colorId);
            } else {
              price = _safeDouble(rMap['price_dzd'] ?? rMap['price']);
            }
            rMap['calculated_price'] = price;
            widget.model.componentOverrides['حديد الظلفة (Renfort Sash)'] =
                rMap;

            // Look up Mifsal renfort in the database
            final mifsalRes = await db.query(
              'Sections',
              where:
                  'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
              whereArgs: [
                widget.model.activeSeries?.id,
                '%مفصل%',
                '%مفصل%',
                '%مفاصل%',
                '%مفاصل%',
                '%mifsal%',
                '%mifsal%',
                '%paumelle%',
                '%paumelle%',
                '%pomelle%',
                '%pomelle%',
              ],
              limit: 1,
            );
            if (mifsalRes.isNotEmpty) {
              final mifsalMap = Map<String, dynamic>.from(mifsalRes.first);
              double mPrice = 0.0;
              if (colorId != null) {
                mPrice = await sqlDb.getSectionPrice(
                  mifsalMap['id'] as int,
                  colorId,
                );
              } else {
                mPrice = _safeDouble(
                  mifsalMap['price_dzd'] ?? mifsalMap['price'],
                );
              }
              mifsalMap['calculated_price'] = mPrice;
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  mifsalMap;
            } else {
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  rMap;
            }
            if (mounted) setState(() {}); // تحديث فوري
          }
        }
      }

      // 3. البراغي (تحديث الشاشة فوراً بمجرد إيجاد البرغي)
      Future<void> assignScrew(String key, String dbColumn) async {
        if (!isLinked(key)) {
          try {
            List<Map<String, dynamic>> res = [];
            try {
              res = await db.query(
                'Accessories',
                where: '$dbColumn = 1 AND (is_active = 1 OR is_active IS NULL)',
                limit: 1,
              );
            } catch (_) {}

            // لا نستخدم بحثاً احتياطياً عشوائياً للبراغي حتى لا يختلط مع إكسسوارات أخرى

            if (res.isNotEmpty) {
              final mutableItem = Map<String, dynamic>.from(res.first);
              double price = 0.0;
              if (colorId != null) {
                final colorPriceRes = await db.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [res.first['id'], colorId],
                );
                if (colorPriceRes.isNotEmpty &&
                    _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
              } else {
                price = _safeDouble(
                  res.first['price_dzd'] ??
                      res.first['price_per_meter'] ??
                      res.first['price'],
                );
              }
              mutableItem['calculated_price'] = price;
              widget.model.componentOverrides[key] = mutableItem;
              if (mounted) {
                setState(() {}); // إجبار الخانة على الظهور بدون تدخلك
              }
            }
          } catch (e) {
            print('');
          }
        }
      }

      await assignScrew('براغي المحرك', 'is_moteur_screw');
      await assignScrew('براغي الصندوق', 'is_caisson_screw');
      await assignScrew('براغي الباتمو', 'is_batmo_screw');
      await assignScrew('براغي بوشون باتمو', 'is_bouchon_batmo_screw');
      await assignScrew('براغي حديد الدعم', 'is_renfort_screw');
      await assignScrew('براغي المانيفال', 'is_manivelle_screw');
      await assignScrew('براغي التجميع', 'is_assembly_screw');
      await assignScrew('براغي الإكسسوارات', 'is_accessory_screw');
      await assignScrew('براغي التركيب', 'is_installation_screw');
      await assignScrew('براغي الكيت', 'is_kit_screw');

      // 4. الأقفال والقاش
      Future<void> assignGache(String key, String dbColumn) async {
        if (!isLinked(key)) {
          try {
            var res = await db.query(
              'Accessories',
              where: '$dbColumn = 1 AND (is_active = 1 OR is_active IS NULL)',
              limit: 1,
            );

            if (res.isEmpty) {
              String kw = '';
              if (key.contains('سامبل') || key.contains('Simple')) {
                kw = 'simple';
              } else if (key.contains('دوبل') || key.contains('Double'))
                kw = 'double';
              else if (key.contains('بورت') || key.contains('Porte'))
                kw = 'porte';
              else if (key.contains('مفتاح') || key.contains('Clef'))
                kw = 'clef';
              else if (key.contains('Condamnation'))
                kw = 'condamnation';

              if (kw.isNotEmpty) {
                res = await db.query(
                  'Accessories',
                  where:
                      "(LOWER(name) LIKE '%gache%' OR name LIKE '%قاش%') AND LOWER(name) LIKE '%$kw%' AND (is_active = 1 OR is_active IS NULL)",
                  limit: 1,
                );
              }
            }

            if (res.isNotEmpty) {
              final mutableItem = Map<String, dynamic>.from(res.first);
              double price = 0.0;
              if (colorId != null) {
                final colorPriceRes = await db.query(
                  'AccessoryColorPrices',
                  where: 'accessory_id = ? AND color_id = ?',
                  whereArgs: [res.first['id'], colorId],
                );
                if (colorPriceRes.isNotEmpty &&
                    _safeDouble(colorPriceRes.first['price']) > 0) {
                  price = _safeDouble(colorPriceRes.first['price']);
                } else {
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
              } else {
                price = _safeDouble(
                  res.first['price_dzd'] ??
                      res.first['price_per_meter'] ??
                      res.first['price'],
                );
              }
              mutableItem['calculated_price'] = price;
              widget.model.componentOverrides[key] = mutableItem;
              if (mounted) setState(() {}); // إجبار الخانة على الظهور
            }
          } catch (e) {}
        }
      }

      await assignGache('قاش سامبل (Gache Simple Ouvrant)', 'is_gache_simple');
      await assignGache('قاش دوبل (Gache Double Ouvrant)', 'is_gache_double');
      await assignGache('قاش بورت (Gache Porte)', 'is_gache_porte');
      await assignGache('قفل بمفتاح (Clef)', 'is_lock_clef');
      await assignGache('قفل Condamnation', 'is_lock_condamnation');

      // 5. جلب Joint Brosse تلقائياً
      if (!isLinked('جوان بروس (Joint Brosse)')) {
        try {
          var jointRes = await db.query(
            'Joints',
            where:
                "(LOWER(name) LIKE '%bross%' OR name LIKE '%بروس%' OR name LIKE '%برش%')",
            limit: 1,
          );
          if (jointRes.isEmpty) {
            jointRes = await db.query(
              'Accessories',
              where:
                  "(LOWER(name) LIKE '%bross%' OR name LIKE '%بروس%' OR name LIKE '%برش%') AND (is_active = 1 OR is_active IS NULL)",
              limit: 1,
            );
          }
          if (jointRes.isNotEmpty) {
            final mutableJoint = Map<String, dynamic>.from(jointRes.first);
            double jPrice = _safeDouble(
              mutableJoint['price_per_meter'] ??
                  mutableJoint['price_dzd'] ??
                  mutableJoint['price'],
            );
            mutableJoint['calculated_price'] = jPrice;
            widget.model.componentOverrides['جوان بروس (Joint Brosse)'] =
                mutableJoint;
            if (mounted) setState(() {});
          }
        } catch (e) {
          print('');
        }
      }

      // 5.5 جلب الطاسو (Tasso) تلقائياً
      if (!isLinked('الطاسو (Tasso)')) {
        try {
          final tRes = await db.query(
            'Accessories',
            where:
                "(LOWER(name) LIKE '%tasso%' OR LOWER(name) LIKE '%tasseau%' OR name LIKE '%طاسو%' OR name LIKE '%طاصو%' OR LOWER(name) LIKE '%equerre%' OR LOWER(name) LIKE '%équerre%') AND (is_active = 1 OR is_active IS NULL)",
            limit: 1,
          );
          if (tRes.isNotEmpty) {
            final mutableItem = Map<String, dynamic>.from(tRes.first);
            double price = _safeDouble(
              mutableItem['price_dzd'] ?? mutableItem['price'],
            );
            mutableItem['calculated_price'] = price;
            widget.model.componentOverrides['الطاسو (Tasso)'] = mutableItem;
            if (mounted) setState(() {});
          }
        } catch (e) {}
      }

      // 6. تحميل بيانات Kit Bundles من قاعدة البيانات
      final kitBundleData = <String, List<Map<String, dynamic>>>{};
      final kitPerLeafMap = <String, bool>{};
      try {
        final kits = await sqlDb.readKitBundles();
        for (final kit in kits) {
          final kitName = kit['name'] as String? ?? '';
          final kitId = kit['id'] as int;
          final details = await sqlDb.readKitBundleItemsWithDetails(kitId);

          final mutableDetails = <Map<String, dynamic>>[];
          for (final item in details) {
            final mutableItem = Map<String, dynamic>.from(item);

            final ranges = item['ranges'] as List? ?? [];
            final mutableRanges = <Map<String, dynamic>>[];
            for (final range in ranges) {
              final rangeMap = Map<String, dynamic>.from(range);
              final prodName = rangeMap['product_name'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  rangeMap['price'] = resolvedPrice;
                }
              }
              mutableRanges.add(rangeMap);
            }
            mutableItem['ranges'] = mutableRanges;

            final variants = item['variants'] as List? ?? [];
            final mutableVariants = <Map<String, dynamic>>[];
            for (final variant in variants) {
              final variantMap = Map<String, dynamic>.from(variant);
              final prodName = variantMap['product_name'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  variantMap['price'] = resolvedPrice;
                }
              }
              mutableVariants.add(variantMap);
            }
            mutableItem['variants'] = mutableVariants;

            if (item['qty_mode'] == 'fixed') {
              final prodName = item['component_type'] as String? ?? '';
              if (prodName.isNotEmpty) {
                final resolvedPrice = await _resolveDynamicProductPrice(
                  db,
                  prodName,
                  colorId,
                );
                if (resolvedPrice != null) {
                  mutableItem['price'] = resolvedPrice;
                }
              }
            }

            mutableDetails.add(mutableItem);
          }

          kitBundleData[kitName] = mutableDetails;
          kitPerLeafMap[kitName] = (kit['per_leaf'] ?? 0) == 1;
        }
      } catch (_) {}
      _kitBundleData = kitBundleData;
      _kitPerLeafMap = kitPerLeafMap;

      // 7. الإسبانيوليت وبقية الإكسسوارات
      final bomItems = ComponentCalculator.generateBom(
        widget.model,
        activeVariants,
        kitBundleData: kitBundleData,
        kitPerLeafMap: kitPerLeafMap,
      );
      for (var item in bomItems) {
        if (item.isMissing &&
            !widget.model.componentOverrides.containsKey(item.originalName)) {
          try {
            // حل مشكلة الإسبانيوليت
            // ---- حل مشكلة الإسبانيوليت النهائي (بناءً على النوع الموجود في قاعدة بياناتك) ----
            if (item.originalName.contains('إسبانيوليت') ||
                item.originalName.contains('Espagnolette')) {
              try {
                // 1. استخراج المقاس المطلوب من الاسم (مثلاً 180)
                final match = RegExp(r'\d+').firstMatch(item.originalName);
                String targetSize = match != null ? match.group(0)! : '';

                // 2. جلب كل الإسبانيوليت من قاعدة البيانات (بحث واسع جداً يشمل النوع الذي ذكرته)
                var allEsp = await db.query(
                  'Accessories',
                  where:
                      "(type LIKE '%إسبانيوليت%'  OR LOWER(name) LIKE '%eEsp%') AND (is_active = 1 OR is_active IS NULL)",
                );

                if (allEsp.isNotEmpty) {
                  Map<String, dynamic>? selectedEsp;

                  // 3. محاولة العثور على إسبانيوليت بنفس المقاس (إذا كان المقاس مكتوباً في الاسم أو النوع)
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

                  // 4. إذا لم يجد نفس المقاس، نختار أول خيار متاح (سيلتقط "إسبانيوليت|جودة قياسية" مباشرة)
                  selectedEsp ??= allEsp.first;

                  // 5. حفظ المكون وتحديث الشاشة فوراً
                  final mutableItem = Map<String, dynamic>.from(selectedEsp);
                  double price = 0.0;
                  if (colorId != null) {
                    final colorPriceRes = await db.query(
                      'AccessoryColorPrices',
                      where: 'accessory_id = ? AND color_id = ?',
                      whereArgs: [selectedEsp['id'], colorId],
                    );
                    if (colorPriceRes.isNotEmpty &&
                        _safeDouble(colorPriceRes.first['price']) > 0) {
                      price = _safeDouble(colorPriceRes.first['price']);
                    } else {
                      price = _safeDouble(
                        selectedEsp['price_dzd'] ?? selectedEsp['price'],
                      );
                    }
                  } else {
                    price = _safeDouble(
                      selectedEsp['price_dzd'] ?? selectedEsp['price'],
                    );
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] =
                      mutableItem;
                  if (mounted) setState(() {});
                }
              } catch (e) {}
              continue;
            }

            String? table;
            String keywordAr = '';
            String keywordFr = '';

            if (item.category == 'shutter') {
              table = 'ShutterComponents';
              if (item.originalName.contains('Lames') ||
                  item.originalName.contains('الشرائح')) {
                keywordFr = 'lame';
                keywordAr = 'شريح';
              } else if (item.originalName.contains('Coulisses') ||
                  item.originalName.contains('السكك')) {
                keywordFr = 'coulisse';
                keywordAr = 'سك';
              } else if (item.originalName.contains('Axe') ||
                  item.originalName.contains('المحور')) {
                keywordFr = 'axe';
                keywordAr = 'محور';
              } else if (item.originalName.contains('Caisson') ||
                  item.originalName.contains('الصندوق')) {
                keywordFr = 'caisson';
                keywordAr = 'صندوق';
              } else if (item.originalName.contains('Moteur') ||
                  item.originalName.contains('المحرك')) {
                keywordFr = 'moteur';
                keywordAr = 'محرك';
              } else if (item.originalName.contains('Manivelle') ||
                  item.originalName.contains('المانيفال')) {
                keywordFr = 'manivelle';
                keywordAr = 'مانيفال';
              } else if (item.originalName.contains('Tandem') ||
                  item.originalName.contains('طانديم')) {
                keywordFr = 'tandem';
                keywordAr = 'طانديم';
              } else if (item.originalName.contains('Lame Finale') ||
                  item.originalName.contains('الشريحة النهائية')) {
                keywordFr = 'finale';
                keywordAr = 'نهائي';
              } else if (item.originalName.contains('Joint Brosse') ||
                  item.originalName.contains('Joint bross') ||
                  item.originalName.contains('جوان بروس')) {
                keywordFr = 'bross';
                keywordAr = 'بروس';
              } else if (item.originalName.contains('Kit') ||
                  item.originalName.contains('كيت')) {
                keywordFr = 'kit';
                keywordAr = 'كيت';
              } else if (item.originalName.contains('Attache') ||
                  item.originalName.contains('أطاش')) {
                keywordFr = 'attache';
                keywordAr = 'أطاش';
              } else if (item.originalName.contains('Support Moteur') ||
                  item.originalName.contains('سيبور موتور')) {
                keywordFr = 'support_moteur';
                keywordAr = 'سيبور موتور';
              } else if (item.originalName.contains('Embout') ||
                  item.originalName.contains('الامبو')) {
                keywordFr = 'embout';
                keywordAr = 'امبو';
              } else if (item.originalName.contains('Support Roulement') ||
                  item.originalName.contains('سيبور رولمو')) {
                keywordFr = 'support_roulement';
                keywordAr = 'سيبور رولمو';
              } else if (item.originalName.contains('Bouchons Lames') ||
                  item.originalName.contains('أغطية الشفرات')) {
                keywordFr = 'bouchon_lame';
                keywordAr = 'أغطية الشفرات';
              }
            } else if (item.category == 'accessory') {
              table = 'Accessories';
              if (item.originalName.contains('المقبض') ||
                  item.originalName.contains('Handle')) {
                keywordFr = 'poign';
                keywordAr = 'مقبض';
              } else if (item.originalName.contains('المفاصل') ||
                  item.originalName.contains('Hinges')) {
                keywordFr = 'paumel';
                keywordAr = 'مفصل';
              } else if (item.originalName.contains('System OB')) {
                keywordFr = 'ob';
                keywordAr = 'ob';
              } else if ((item.originalName.contains('الفيرو') ||
                      item.originalName.contains('Verrou')) &&
                  !item.originalName.contains('Central')) {
                keywordFr = 'verrou';
                keywordAr = 'فيرو';
              } else if (item.originalName.contains('براغي') ||
                  item.originalName.toLowerCase().contains('screw')) {
                keywordFr = 'vis';
                keywordAr = 'براغي';
              }
            } else if (item.category == 'joint') {
              table = 'Joints';
              if (item.originalName.contains('Joint Brosse') ||
                  item.originalName.contains('Joint bross') ||
                  item.originalName.contains('جوان بروس')) {
                keywordFr = 'bross';
                keywordAr = 'بروس';
              } else {
                keywordFr = 'joint';
                keywordAr = 'جوان';
              }
            } else if (item.category == 'profile') {
              table = 'Sections';
              if (item.originalName.contains('Batmo') ||
                  item.originalName.contains('الباتمو')) {
                keywordFr = 'batmo';
                keywordAr = 'باتمو';
              } else if (item.originalName.contains('Mullion') ||
                  item.originalName.contains('تقسيم الزجاج')) {
                // Special search for Mullion/Traverse within active series
                final mullRes = await db.query(
                  'Sections',
                  where:
                      'series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ? OR type LIKE ?)',
                  whereArgs: [
                    widget.model.activeSeries?.id,
                    '%mullion%',
                    '%mullion%',
                    '%traverse%',
                    '%traverse%',
                    '%تقسيم%',
                    '%تقسيم%',
                  ],
                  limit: 1,
                );
                if (mullRes.isNotEmpty) {
                  final mutableItem = Map<String, dynamic>.from(mullRes.first);
                  double price = 0.0;
                  if (colorId != null) {
                    price = await sqlDb.getSectionPrice(
                      mullRes.first['id'] as int,
                      colorId,
                    );
                  } else {
                    price = _safeDouble(
                      mullRes.first['price_dzd'] ?? mullRes.first['price'],
                    );
                  }
                  mutableItem['calculated_price'] = price;
                  widget.model.componentOverrides[item.originalName] =
                      mutableItem;
                  if (mounted) setState(() {});
                  continue; // Skip the generic lookup below
                } else {
                  keywordFr = 'mullion';
                  keywordAr = 'تقسيم';
                }
              } else if (item.originalName.contains('Renfort') ||
                  item.originalName.contains('حديد')) {
                keywordFr = 'renfort';
                keywordAr = 'حديد';
              }
            }

            if (table != null) {
              List<Map<String, Object?>> res = [];
              if (keywordFr.isNotEmpty || keywordAr.isNotEmpty) {
                String sizeFilter = '';
                if (item.originalName.contains('Caisson') ||
                    item.originalName.contains('الصندوق') ||
                    item.originalName.contains('Kit') ||
                    item.originalName.contains('كيت')) {
                  String size = widget.model.shutterBoxHeight
                      .toInt()
                      .toString();
                  String sizeDot = size.length == 3
                      ? "${size.substring(0, 2)}.${size.substring(2)}"
                      : size;
                  String sizeComma = size.length == 3
                      ? "${size.substring(0, 2)},${size.substring(2)}"
                      : size;
                  String shortSize = size.length == 3
                      ? size.substring(0, 2)
                      : size;
                  sizeFilter =
                      " AND (name LIKE '%$size%' OR type LIKE '%$size%' OR name LIKE '%$sizeDot%' OR type LIKE '%$sizeDot%' OR name LIKE '%$sizeComma%' OR type LIKE '%$sizeComma%' OR name LIKE '%$shortSize%' OR type LIKE '%$shortSize%')";
                }
                res = await db.query(
                  table,
                  where:
                      '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) $sizeFilter AND (is_active = 1 OR is_active IS NULL)',
                  whereArgs: [
                    '%$keywordFr%',
                    '%$keywordFr%',
                    '%$keywordAr%',
                    '%$keywordAr%',
                  ],
                  limit: 1,
                );
                if (res.isEmpty && sizeFilter.isNotEmpty) {
                  res = await db.query(
                    table,
                    where:
                        '((LOWER(name) LIKE ? OR LOWER(type) LIKE ?) OR (name LIKE ? OR type LIKE ?)) AND (is_active = 1 OR is_active IS NULL)',
                    whereArgs: [
                      '%$keywordFr%',
                      '%$keywordFr%',
                      '%$keywordAr%',
                      '%$keywordAr%',
                    ],
                    limit: 1,
                  );
                }
              }
              if (res.isNotEmpty) {
                final mutableItem = Map<String, dynamic>.from(res.first);
                double price = 0.0;
                if (table == 'Sections' && colorId != null) {
                  price = await SqlDatabase().getSectionPrice(
                    res.first['id'],
                    colorId,
                  );
                } else if (table == 'Accessories' && colorId != null) {
                  final colorPriceRes = await db.query(
                    'AccessoryColorPrices',
                    where: 'accessory_id = ? AND color_id = ?',
                    whereArgs: [res.first['id'], colorId],
                  );
                  if (colorPriceRes.isNotEmpty &&
                      _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(
                      res.first['price_dzd'] ??
                          res.first['price_per_meter'] ??
                          res.first['price'],
                    );
                    if (price == 0) {
                      final anyColorRes = await db.query(
                        'AccessoryColorPrices',
                        where: 'accessory_id = ? AND price > 0',
                        whereArgs: [res.first['id']],
                        limit: 1,
                      );
                      if (anyColorRes.isNotEmpty)
                        price = _safeDouble(anyColorRes.first['price']);
                    }
                  }
                } else if (table == 'ShutterComponents' && colorId != null) {
                  final colorPriceRes = await db.query(
                    'ShutterColorPrices',
                    where: 'shutter_component_id = ? AND color_id = ?',
                    whereArgs: [res.first['id'], colorId],
                  );
                  if (colorPriceRes.isNotEmpty &&
                      _safeDouble(colorPriceRes.first['price']) > 0) {
                    price = _safeDouble(colorPriceRes.first['price']);
                  } else {
                    price = _safeDouble(
                      res.first['price_dzd'] ??
                          res.first['price_per_meter'] ??
                          res.first['price'],
                    );
                    if (price == 0) {
                      final anyColorRes = await db.query(
                        'ShutterColorPrices',
                        where: 'shutter_component_id = ? AND price > 0',
                        whereArgs: [res.first['id']],
                        limit: 1,
                      );
                      if (anyColorRes.isNotEmpty)
                        price = _safeDouble(anyColorRes.first['price']);
                    }
                  }
                } else {
                  price = _safeDouble(
                    res.first['price_dzd'] ??
                        res.first['price_per_meter'] ??
                        res.first['price'],
                  );
                }
                mutableItem['calculated_price'] = price;
                widget.model.componentOverrides[item.originalName] =
                    mutableItem;
                if (mounted) setState(() {}); // إجبار الخانة على الظهور
              }
            }
          } catch (e) {}
        }
      }
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _profitMarginController = TextEditingController();
    _pricePerSqmController = TextEditingController();
    _pricePerLinearMeterController = TextEditingController();
    _loadCostSettings();

    final isTunnel = widget.model.isCaissonTunnel;
    final isMotor = widget.model.shutterMechanism == 'محرك';
    final isCrankInit =
        widget.model.shutterMechanism == 'منايفال' ||
        widget.model.shutterMechanism == 'مانيفال' ||
        widget.model.shutterMechanism == 'مانيفر';
    activeVariants = {
      'Verrou Central': widget.model.useVerrouCentral,
      'System OB': widget.model.useSystemOB,
      'Demi System OB': widget.model.useDemiOB,
      'كيت (Kit)': false,
      'كيت فولي موتور (Kit Volet Moteur)': isTunnel ? false : isMotor,
      'كيت فولي مانيفر (Kit Volet Manivelle)': isTunnel ? false : isCrankInit,
      'كيت مانيفر (Kit Manivelle)': isTunnel ? false : isCrankInit,
      'كيت فولي (Kit Volet)': isTunnel ? false : (!isMotor && !isCrankInit),
      'كيت حزام (Kit Sangle)': false,
      'طانديم (Tandem)': isTunnel || isMotor,
      'الامبو (Embout)': false,
      'سيبور رولمو (Support Roulement)': false,
      'سيبور موتور (Support Moteur)': isTunnel || isMotor,
      'أغطية الشفرات (Bouchons Lames)': isTunnel || isMotor,
    };
    // استدعاء دالة الجلب فور فتح الشاشة
    _fetchDefaults();

    // الاستماع لتغييرات الـ model (تغيير القياسات مثلاً)
    widget.model.addListener(_onModelChanged);

    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 150;
      if (isScrolled != _isScrolled) {
        setState(() {
          _isScrolled = isScrolled;
        });
      }
    });
  }

  void _onModelChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_onModelChanged);
    _scrollController.dispose();
    _profitMarginController.dispose();
    _pricePerSqmController.dispose();
    _pricePerLinearMeterController.dispose();
    super.dispose();
  }

  Future<void> _loadCostSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _profitMargin = prefs.getDouble('app_profit_margin') ?? 20.0;
      _pricePerSqm = prefs.getDouble('app_price_per_sqm') ?? 12000.0;
      _pricePerLinearMeter =
          prefs.getDouble('app_price_per_linear_meter') ?? 8000.0;
      final methodIndex =
          prefs.getInt('app_cost_method') ?? CostMethod.percentage.index;
      _costMethod = CostMethod.values[methodIndex];

      _profitMarginController.text = _profitMargin.toStringAsFixed(1);
      _pricePerSqmController.text = _pricePerSqm.toStringAsFixed(0);
      _pricePerLinearMeterController.text = _pricePerLinearMeter
          .toStringAsFixed(0);
    });
  }

  Future<double?> _resolveDynamicProductPrice(
    Database db,
    String productName,
    int? colorId,
  ) async {
    // 1. البحث في جدول Accessories
    final accRows = await db.query(
      'Accessories',
      columns: ['id', 'price'],
      where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [productName],
      limit: 1,
    );
    if (accRows.isNotEmpty) {
      final accId = accRows.first['id'] as int;
      final defaultPrice = _safeDouble(accRows.first['price']);
      if (colorId != null) {
        final colorPriceRes = await db.query(
          'AccessoryColorPrices',
          columns: ['price'],
          where: 'accessory_id = ? AND color_id = ?',
          whereArgs: [accId, colorId],
          limit: 1,
        );
        if (colorPriceRes.isNotEmpty) {
          final p = _safeDouble(colorPriceRes.first['price']);
          if (p > 0) return p;
        }
      }
      return defaultPrice;
    }

    // 2. البحث في جدول ShutterComponents
    final shutRows = await db.query(
      'ShutterComponents',
      columns: ['id', 'price'],
      where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
      whereArgs: [productName],
      limit: 1,
    );
    if (shutRows.isNotEmpty) {
      final shutId = shutRows.first['id'] as int;
      final defaultPrice = _safeDouble(shutRows.first['price']);
      if (colorId != null) {
        final colorPriceRes = await db.query(
          'ShutterColorPrices',
          columns: ['price'],
          where: 'shutter_component_id = ? AND color_id = ?',
          whereArgs: [shutId, colorId],
          limit: 1,
        );
        if (colorPriceRes.isNotEmpty) {
          final p = _safeDouble(colorPriceRes.first['price']);
          if (p > 0) return p;
        }
      }
      return defaultPrice;
    }

    return null;
  }

  Future<void> _saveCostSetting(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveCostMethod(CostMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_cost_method', method.index);
  }

  void _handleVariantToggle(String name, String? group, bool value) {
    setState(() {
      activeVariants[name] = value;
      final isTunnel = widget.model.isCaissonTunnel;

      final isAnyKitKey =
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';

      if (name == 'Verrou Central') {
        widget.model.toggleVerrouCentral(value);
      } else if (name == 'System OB') {
        widget.model.toggleSystemOB(value);
      } else if (name == 'Demi System OB') {
        widget.model.toggleDemiOB(value);
      } else if (isAnyKitKey) {
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['سيبور موتور (Support Moteur)'] = false;
          activeVariants['طانديم (Tandem)'] = false;
        }
      } else if (name == 'طانديم (Tandem)') {
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      } else if (name == 'الامبو (Embout)' ||
          name == 'سيبور رولمو (Support Roulement)') {
        if (value) {
          activeVariants['الامبو (Embout)'] = true;
          activeVariants['سيبور رولمو (Support Roulement)'] = true;
          activeVariants['طانديم (Tandem)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        } else {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
        }
      } else if (name == 'سيبور موتور (Support Moteur)') {
        if (value) {
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      } else if (name == 'أغطية الشفرات (Bouchons Lames)') {
        if (isTunnel) {
          activeVariants['أغطية الشفرات (Bouchons Lames)'] = true;
        }
      }

      // Sync activeVariants back to the model's new state
      activeVariants['Verrou Central'] = widget.model.useVerrouCentral;
      activeVariants['System OB'] = widget.model.useSystemOB;
      activeVariants['Demi System OB'] = widget.model.useDemiOB;
      if (isTunnel) {
        activeVariants['أغطية الشفرات (Bouchons Lames)'] = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ComponentCalculator.generateBom(
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('الكمية والتكلفة')),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: CustomPaint(
                      painter: WindowPainter(model: widget.model),
                      size: Size(
                        widget.model.width.toDouble(),
                        widget.model.height.toDouble(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            // Light Kit availability indicator
            (() {
              final hasLightKitSystem = _kitBundleData.keys.any(
                (key) =>
                    key.toLowerCase().contains('light') ||
                    key.contains('لايت') ||
                    key.contains('ليت'),
              );

              final activeKits = items
                  .where((i) => i.isActive && i.kitGroupName != null)
                  .map((i) => i.kitGroupName!)
                  .toSet();
              final isLightKitSystemActive = activeKits.any(
                (name) =>
                    name.toLowerCase().contains('light') ||
                    name.contains('لايت') ||
                    name.contains('ليت'),
              );

              bool isShutterKitLight = false;
              bool isShutterKitActive = false;
              final isMotor = widget.model.shutterMechanism == 'محرك';
              final kitKeysToCheck = isMotor
                  ? ['كيت فولي موتور (Kit Volet Moteur)']
                  : [
                      'كيت فولي مانيفر (Kit Volet Manivelle)',
                      'كيت مانيفر (Kit Manivelle)',
                    ];
              for (var key in kitKeysToCheck) {
                final shutterKit = widget.model.componentOverrides[key];
                if (shutterKit != null) {
                  final shutterKitName = shutterKit['name']?.toString() ?? '';
                  if (shutterKitName.toLowerCase().contains('light') ||
                      shutterKitName.contains('لايت') ||
                      shutterKitName.contains('ليت')) {
                    isShutterKitLight = true;
                  }
                }
                if (activeVariants[key] == true) {
                  isShutterKitActive = true;
                }
              }

              final isLightKitActive =
                  isLightKitSystemActive ||
                  (isShutterKitActive && isShutterKitLight);
              final hasLightKit = hasLightKitSystem || isShutterKitLight;

              return Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: isLightKitActive
                      ? Colors.green.shade50
                      : (hasLightKit
                            ? Colors.blue.shade50
                            : Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLightKitActive
                        ? Colors.green.shade200
                        : (hasLightKit
                              ? Colors.blue.shade200
                              : Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLightKitActive
                          ? Icons.check_circle
                          : (hasLightKit
                                ? Icons.info_outline
                                : Icons.help_outline),
                      color: isLightKitActive
                          ? Colors.green
                          : (hasLightKit ? Colors.blue : Colors.grey),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isLightKitActive ? '' : (hasLightKit ? 'ً' : ''),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLightKitActive
                              ? Colors.green.shade800
                              : (hasLightKit
                                    ? Colors.blue.shade800
                                    : Colors.grey.shade700),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            })(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 8.0,
              ),
              child: _buildUnifiedTable(items),
            ),
            _buildCostMethodSelector(),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(items),
    );
  }

  Widget _buildCostMethodSelector() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    // يُحسب هنا لإظهار الأسعار بشكل حي داخل الكارت
    final items = ComponentCalculator.generateBom(
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
    );
    final double totalCostNoWaste = items
        .where((i) => i.isActive)
        .fold(0.0, (s, i) => s + i.total);
    // تكلفة مع هدر 10%
    final double totalCostWithWaste = totalCostNoWaste * 1.10;

    double sellingPrice = totalCostNoWaste;
    if (_costMethod == CostMethod.percentage) {
      sellingPrice = totalCostNoWaste * (1 + _profitMargin / 100);
    } else if (_costMethod == CostMethod.squareMeter) {
      double areaSqm =
          (widget.model.width / 1000.0) * (widget.model.height / 1000.0);
      sellingPrice = _pricePerSqm * areaSqm * widget.model.quantity;
    } else if (_costMethod == CostMethod.linearMeter) {
      double linearM = 2 * (widget.model.width + widget.model.height) / 1000.0;
      sellingPrice = _pricePerLinearMeter * linearM * widget.model.quantity;
    }

    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localization.translate('cost_calculation_method', lang),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              children: CostMethod.values.map((method) {
                final isSelected = _costMethod == method;
                String label = '';
                if (method == CostMethod.percentage) {
                  label = Localization.translate('percentage', lang);
                } else if (method == CostMethod.squareMeter) {
                  label = Localization.translate('square_meter', lang);
                } else if (method == CostMethod.linearMeter) {
                  label = Localization.translate('linear_meter', lang);
                }
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _costMethod = method);
                      _saveCostMethod(method);
                    }
                  },
                  selectedColor: Colors.blue.shade100,
                  checkmarkColor: Colors.blue.shade800,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.blue.shade900 : Colors.black87,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            if (_costMethod == CostMethod.percentage)
              TextField(
                controller: _profitMarginController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'نسبة الربح (%)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.percent),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  setState(() => _profitMargin = parsed);
                  _saveCostSetting('app_profit_margin', parsed);
                },
              )
            else if (_costMethod == CostMethod.squareMeter)
              TextField(
                controller: _pricePerSqmController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر المتر المربع (دج)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.aspect_ratio),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  setState(() => _pricePerSqm = parsed);
                  _saveCostSetting('app_price_per_sqm', parsed);
                },
              )
            else if (_costMethod == CostMethod.linearMeter)
              TextField(
                controller: _pricePerLinearMeterController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر المتر الخطي (دج)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.linear_scale),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  setState(() => _pricePerLinearMeter = parsed);
                  _saveCostSetting('app_price_per_linear_meter', parsed);
                },
              ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            // ── حقل الكمية ────────────────────────────────────────────
            Row(
              children: [
                const Icon(
                  Icons.format_list_numbered,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'الكمية:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: '${widget.model.quantity}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        setState(() => widget.model.quantity = parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'نافذة',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ── ملخص الأسعار ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ملخص التسعير',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _priceRow(
                    Icons.monetization_on_outlined,
                    'سعر التكلفة (بدون هدر)',
                    '${totalCostNoWaste.toStringAsFixed(0)} دج',
                    Colors.orange.shade700,
                  ),
                  const SizedBox(height: 8),
                  _priceRow(
                    Icons.warning_amber_rounded,
                    'سعر التكلفة (مع هدر 10%)',
                    '${totalCostWithWaste.toStringAsFixed(0)} دج',
                    Colors.deepOrange,
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _priceRow(
                    Icons.sell_rounded,
                    'سعر البيع المقترح',
                    '${sellingPrice.toStringAsFixed(0)} دج',
                    Colors.green.shade700,
                    isBig: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceRow(
    IconData icon,
    String label,
    String value,
    Color color, {
    bool isBig = false,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: isBig ? 22 : 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBig ? 14 : 12,
              fontWeight: isBig ? FontWeight.bold : FontWeight.normal,
              color: Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBig ? 18 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildKitDropdown(BomItem item) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        final dbInstance = await SqlDatabase().db;
        if (dbInstance == null) return <Map<String, dynamic>>[];
        final rows = await dbInstance.query(
          'ShutterComponents',
          where:
              "(LOWER(name) LIKE '%kit%' OR name LIKE '%كيت%') AND (is_active = 1 OR is_active IS NULL)",
        );
        return rows.map((r) => Map<String, dynamic>.from(r)).toList();
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        final allKits = snapshot.data!;

        // Filter kits based on the window height rule
        final double currentHeight = widget.model.height;
        double minAllowedSize = 155.0;
        if (currentHeight > 1600 && currentHeight <= 2400) {
          minAllowedSize = 185.0;
        } else if (currentHeight > 2400) {
          minAllowedSize = 205.0;
        }

        final currentKit = widget.model.componentOverrides[item.originalName];
        double currentKitSize = 0.0;
        if (currentKit != null) {
          final currentSizeStr = getComponentSize(currentKit);
          if (currentSizeStr != null) {
            currentKitSize = double.tryParse(currentSizeStr) ?? 0.0;
            if (currentKitSize == 15.5) currentKitSize = 155.0;
            if (currentKitSize == 18.5) currentKitSize = 185.0;
            if (currentKitSize == 20.5) currentKitSize = 205.0;
            if (currentKitSize == 15.0) currentKitSize = 150.0;
            if (currentKitSize == 18.0) currentKitSize = 180.0;
            if (currentKitSize == 20.0) currentKitSize = 200.0;
            if (currentKitSize < 100.0) {
              currentKitSize = currentKitSize * 10.0;
            }
          }
        }

        final double finalMinSize = currentKitSize > minAllowedSize
            ? currentKitSize
            : minAllowedSize;

        final allowedKits = allKits.where((k) {
          final sizeDigits = getComponentSize(k);
          if (sizeDigits != null) {
            double compSize = double.tryParse(sizeDigits) ?? 0.0;
            if (compSize == 15.5) compSize = 155.0;
            if (compSize == 18.5) compSize = 185.0;
            if (compSize == 20.5) compSize = 205.0;
            if (compSize == 15.0) compSize = 150.0;
            if (compSize == 18.0) compSize = 180.0;
            if (compSize == 20.0) compSize = 200.0;
            if (compSize < 100.0) {
              compSize = compSize * 10.0;
            }
            return compSize >= finalMinSize;
          }
          return true;
        }).toList();

        final currentKitId = currentKit?['id'];

        return PopupMenuButton<Map<String, dynamic>>(
          icon: const Icon(
            Icons.arrow_drop_down_circle_outlined,
            color: Colors.blue,
            size: 20,
          ),
          tooltip: 'تغيير كيت الستار (ترقية فقط)',
          onSelected: (selectedKit) {
            setState(() {
              final mutableSelected = Map<String, dynamic>.from(selectedKit);
              mutableSelected['calculated_price'] = _safeDouble(
                mutableSelected['price_dzd'] ?? mutableSelected['price'],
              );
              widget.model.componentOverrides[item.originalName] =
                  mutableSelected;
              widget.model.refreshUI();
            });
          },
          itemBuilder: (context) {
            return allowedKits.map((k) {
              final isCurrent = currentKitId == k['id'];
              return PopupMenuItem<Map<String, dynamic>>(
                value: k,
                child: Row(
                  children: [
                    if (isCurrent)
                      const Icon(Icons.check, color: Colors.green, size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${k['name']} (${k['price']} دج)',
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
        );
      },
    );
  }

  // ===== عرض Kit groups قابلة للطي =====
  List<Widget> _buildKitGroups(List<BomItem> kitItems) {
    if (kitItems.isEmpty) return [];
    final Map<String, List<BomItem>> grouped = {};
    for (final item in kitItems) {
      final group = item.kitGroupName ?? '';
      grouped.putIfAbsent(group, () => []);
      grouped[group]!.add(item);
    }
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final kitName = entry.key;
      final children = entry.value;
      final isExpanded = _kitGroupExpanded[kitName] ?? false;
      final totalPrice = children.fold<double>(0, (sum, i) => sum + i.total);
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';

      final visibleCount = children
          .where(
            (c) =>
                !isKitItem(c.originalName) &&
                c.originalName != 'System OB' &&
                c.originalName != 'Demi System OB' &&
                c.originalName != 'Verrou Central',
          )
          .length;

      bool isMatch(String baseName, List<String> aliases) {
        final normalizedKitName = kitName.toLowerCase().replaceAll(
          RegExp(r'[\s_-]'),
          '',
        );
        for (final alias in aliases) {
          final normalizedAlias = alias.toLowerCase().replaceAll(
            RegExp(r'[\s_-]'),
            '',
          );
          if (normalizedKitName == normalizedAlias) {
            return true;
          }
        }
        return false;
      }

      final isDemiOb = isMatch('Demi System OB', [
        'demi system ob',
        'demi_system_ob',
        'system_dim_ob',
        'system dim ob',
        'systemdimob',
        'demisystemob',
        'demisystemeob',
        'systemedimob',
      ]);
      final isSystemOb =
          !isDemiOb &&
          isMatch('System OB', ['system ob', 'system_ob', 'systemob']);
      final isVerrouCentral = isMatch('Verrou Central', [
        'verrou central',
        'verrou_central',
        'vero_central',
        'vero central',
        'verroucentral',
        'verocentral',
      ]);
      final isShutterKit = !isSystemOb && !isDemiOb && !isVerrouCentral;

      final kitItem = children.firstWhere(
        (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );

      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          : (activeVariants[kitItem.originalName] ?? false);

      // إخفاء الكيت تماماً إذا كان غير مفعل وكان من نوع System OB, Demi OB أو Verrou Central
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }

      // رأس Kit — قابل للنقر وتنسيقه مطابق تماماً لصفوف الجدول
      widgets.add(
        InkWell(
          onTap: () => setState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cell(
                    Container(
                      height: 28,
                      color: Colors.grey.shade200,
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: Colors.grey,
                        size: 16,
                      ),
                    ),
                    _wImg,
                  ),
                  _cell(
                    Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: Colors.deepPurple,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            isShutterKit
                                ? '📦 ${widget.model.componentOverrides[kitItem.originalName]?['name'] ?? kitName}'
                                : '📦 $kitName',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.deepPurple,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isShutterKit && isGroupActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: _buildKitDropdown(kitItem),
                          ),
                      ],
                    ),
                    _wName,
                    backgroundColor: Colors.deepPurple.shade100.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  _cell(
                    Text(
                      visibleCount == 1
                          ? 'عنصر واحد'
                          : visibleCount == 2
                          ? 'عنصران'
                          : (visibleCount >= 3 && visibleCount <= 10)
                          ? '$visibleCount عناصر'
                          : '$visibleCount عنصر',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wQty,
                  ),
                  _cell(
                    const Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wPrice,
                  ),
                  _cell(
                    Text(
                      '${totalPrice.toStringAsFixed(1)} دج',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        decoration: !isGroupActive
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    _wTotal,
                  ),
                  _cell(
                    const Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wLen,
                  ),
                  _cell(
                    const Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wColor,
                  ),
                  _cell(
                    Checkbox(
                      value: isGroupActive,
                      onChanged: (v) {
                        if (isSystemOb) {
                          _handleVariantToggle(
                            'System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isDemiOb) {
                          _handleVariantToggle(
                            'Demi System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isVerrouCentral) {
                          _handleVariantToggle(
                            'Verrou Central',
                            'verrou_group',
                            v ?? false,
                          );
                        } else {
                          _handleVariantToggle(
                            kitItem.originalName,
                            null,
                            v ?? false,
                          );
                        }
                      },
                    ),
                    _wCheck,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // مركبات Kit — تظهر فقط إذا مفتوح
      if (isExpanded) {
        bool isKitItem(String name) =>
            name == 'كيت (Kit)' ||
            name == 'كيت فولي موتور (Kit Volet Moteur)' ||
            name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
            name == 'كيت مانيفر (Kit Manivelle)';

        final visibleChildren = children
            .where(
              (c) =>
                  !isKitItem(c.originalName) &&
                  c.originalName != 'System OB' &&
                  c.originalName != 'Demi System OB' &&
                  c.originalName != 'Verrou Central',
            )
            .toList();
        widgets.addAll(visibleChildren.map(_row));
      }
    }
    return widgets;
  }

  Widget _buildUnifiedTable(List<BomItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    // أغطية الشفرات تنتقل من accessory إلى shutter
    bool isBouchonLame(BomItem i) =>
        i.originalName.contains('أغطية الشفرات') ||
        i.originalName.toLowerCase().contains('bouchons lames') ||
        i.originalName.toLowerCase().contains('bouchon lame');

    final Map<String, List<BomItem>> groups = {
      'profile': items.where((i) => i.category == 'profile').toList(),
      'accessory': items
          .where((i) => i.category == 'accessory' && !isBouchonLame(i))
          .toList(),
      // joint items + bouchons lames تظهر ضمن قسم الستار
      'shutter': items
          .where(
            (i) =>
                i.category == 'shutter' ||
                i.category == 'joint' ||
                (i.category == 'accessory' && isBouchonLame(i)),
          )
          .toList(),
      'glass': items.where((i) => i.category == 'glass').toList(),
    };

    // حساب الإجماليات لكل قسم
    double sectionTotal(String key) =>
        groups[key]!.fold(0.0, (sum, i) => sum + (i.isActive ? i.total : 0.0));

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _minW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  if (groups['profile']!.isNotEmpty) ...[
                    _sectionTitle(
                      'البروفيلات',
                      Colors.blue.shade100,
                      total: sectionTotal('profile'),
                    ),
                    ...groups['profile']!.map(_row),
                  ],
                  if (groups['accessory']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الإكسسوارات',
                      Colors.orange.shade100,
                      total: sectionTotal('accessory'),
                    ),
                    // عناصر Kit — مجمّعة وقابلة للطي
                    ..._buildKitGroups(
                      groups['accessory']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    // عناصر عادية (بدون Kit)
                    ...groups['accessory']!
                        .where((i) => i.kitGroupName == null)
                        .map(_row),
                  ],
                  if (groups['shutter']!.isNotEmpty) ...[
                    _sectionTitle(
                      'مكوّنات الستار',
                      Colors.purple.shade100,
                      total: sectionTotal('shutter'),
                    ),
                    // عناصر Kit — مجمّعة وقابلة للطي
                    ..._buildKitGroups(
                      groups['shutter']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    // عناصر عادية (بدون Kit)
                    ...groups['shutter']!
                        .where((i) => i.kitGroupName == null)
                        .map(_row),
                  ],
                  if (groups['glass']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الزجاج',
                      Colors.teal.shade100,
                      total: sectionTotal('glass'),
                    ),
                    ...groups['glass']!.map(_row),
                  ],
                ],
              ),
            ),
          ),
        ),

        if (_isScrolled)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: _buildMinimalOverlay(groups),
          ),
      ],
    );
  }

  Widget _buildMinimalOverlay(Map<String, List<BomItem>> groups) {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(
          right: BorderSide(color: Colors.grey.shade400, width: 2),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: _rowHeight, color: Colors.blueGrey.shade800),
          if (groups['profile']!.isNotEmpty) ...[
            _minimalSectionTitle('البروفيلات', Colors.blue.shade100),
            ...groups['profile']!.map(_minimalRow),
          ],
          if (groups['accessory']!.isNotEmpty) ...[
            _minimalSectionTitle('الإكسسوارات', Colors.orange.shade100),
            ...groups['accessory']!.map(_minimalRow),
          ],
          if (groups['shutter']!.isNotEmpty) ...[
            _minimalSectionTitle('ستار', Colors.purple.shade100),
            ...groups['shutter']!.map(_minimalRow),
          ],
          if (groups['glass']!.isNotEmpty) ...[
            _minimalSectionTitle('الزجاج', Colors.teal.shade100),
            ...groups['glass']!.map(_minimalRow),
          ],
        ],
      ),
    );
  }

  Widget _minimalSectionTitle(String title, Color color) {
    return Container(
      height: 35,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _minimalRow(BomItem item) {
    final isScrews =
        item.name.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');
    return Container(
      constraints: const BoxConstraints(minHeight: _rowHeight),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.originalName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isScrews ? Colors.orange : Colors.black87,
              decoration: !item.isActive ? TextDecoration.lineThrough : null,
            ),
          ),
          if (item.name != item.originalName)
            Text(
              item.name,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade600,
                decoration: !item.isActive ? TextDecoration.lineThrough : null,
              ),
            ),
          if (item.cuttingList != null && item.cuttingList!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                item.cuttingList!,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Future<int?> _showQuantityDialog(BuildContext context, int currentQty) async {
    final controller = TextEditingController(text: '$currentQty');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('تعديل كمية النوافذ'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'الكمية المطلوبة',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final int? val = int.tryParse(controller.text);
                if (val != null && val > 0) {
                  Navigator.pop(dialogContext, val);
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(List<BomItem> items) {
    final double totalCost = items
        .where((i) => i.isActive)
        .fold(0.0, (sum, i) => sum + i.total);
    double sellingPrice = totalCost;
    if (_costMethod == CostMethod.percentage) {
      sellingPrice = totalCost * (1 + _profitMargin / 100);
    } else if (_costMethod == CostMethod.squareMeter) {
      double areaSqm =
          (widget.model.width / 1000.0) * (widget.model.height / 1000.0);
      sellingPrice = _pricePerSqm * areaSqm * widget.model.quantity;
    } else if (_costMethod == CostMethod.linearMeter) {
      double linearM = 2 * (widget.model.width + widget.model.height) / 1000.0;
      sellingPrice = _pricePerLinearMeter * linearM * widget.model.quantity;
    }

    return SafeArea(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── شريط التحكم (زر الإخفاء/الإظهار + زر الإضافة) ──────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // زر toggle
                  GestureDetector(
                    onTap: () => setState(
                      () => _isBottomBarExpanded = !_isBottomBarExpanded,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isBottomBarExpanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_up,
                            size: 18,
                            color: Colors.grey.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isBottomBarExpanded ? 'إخفاء' : 'تفاصيل',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // عرض سعر البيع مختصر دائماً
                  Expanded(
                    child: Text(
                      'سعر البيع: ${sellingPrice.toStringAsFixed(0)} دج  ×${widget.model.quantity}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // زر إضافة الطلبية
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.model.totalCost = sellingPrice;
                      Navigator.pop(context, true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 18,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text(
                      'إضافة الطلبية',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    const s = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Colors.white,
    );
    return Container(
      color: Colors.blueGrey.shade800,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(const Text('الصورة', style: s), _wImg),
            _cell(const Text('البيان', style: s), _wName),
            _cell(const Text('الكمية', style: s), _wQty),
            _cell(const Text('سعر الوحدة', style: s), _wPrice),
            _cell(const Text('التكلفة', style: s), _wTotal),
            _cell(const Text('الطول', style: s), _wLen),
            _cell(const Text('اللون', style: s), _wColor),
            _cell(const Text('تفعيل', style: s), _wCheck, isLast: true),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, Color color, {double? total}) {
    return Container(
      color: color,
      width: double.infinity,
      height: 35,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          if (total != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'المجموع: ${total.toStringAsFixed(0)} دج',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(
    Widget child,
    double width, {
    bool isLast = false,
    Color? backgroundColor,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: _rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : BorderDirectional(end: BorderSide(color: Colors.grey.shade300)),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _row(BomItem item) {
    final inactive = !item.isActive;
    final warning = item.isMissing && item.isActive;
    final isScrews =
        item.originalName.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');

    final bool isKitElement = item.kitGroupName != null;

    return Container(
      decoration: BoxDecoration(
        color: inactive
            ? Colors.red.shade50
            : (isKitElement
                  ? Colors.blue.shade50.withValues(alpha: 0.5)
                  : Colors.white),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _cell(
              Container(
                height: isKitElement ? 32 : 28,
                color: isKitElement
                    ? Colors.blue.shade100.withValues(alpha: 0.5)
                    : Colors.grey.shade200,
                child: Icon(
                  isKitElement ? Icons.extension : Icons.image,
                  color: isKitElement ? Colors.blue.shade700 : Colors.grey,
                  size: isKitElement ? 18 : 16,
                ),
              ),
              _wImg,
            ),
            _cell(
              Row(
                children: [
                  if (warning)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 14,
                    ),
                  if (warning) const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isKitElement ? item.name : item.originalName,
                          style: TextStyle(
                            fontSize: isKitElement ? 13.5 : 12,
                            fontWeight: FontWeight.bold,
                            color: isScrews
                                ? Colors.orange
                                : (isKitElement
                                      ? Colors.blue.shade900
                                      : Colors.black87),
                            decoration: inactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (isKitElement)
                          Text(
                            'الكمية: ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          )
                        else if (item.name != item.originalName)
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: item.category == 'glass'
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: item.category == 'glass'
                                  ? Colors.black87
                                  : Colors.grey.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        if (item.cuttingList != null &&
                            item.cuttingList!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              item.cuttingList!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (item.isActive && !isKitElement)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: item.originalName == 'كيت (Kit)'
                          ? _buildKitDropdown(item)
                          : GestureDetector(
                              onTap: () => _showSwapDialog(item),
                              child: const Icon(
                                Icons.swap_horiz,
                                color: Colors.orange,
                                size: 18,
                              ),
                            ),
                    ),
                ],
              ),
              _wName,
            ),
            _cell(
              Text(
                '${item.quantity} ${item.unit}',
                style: const TextStyle(fontSize: 12),
              ),
              _wQty,
            ),
            _cell(
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.unitPrice} دج',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  if (item.isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => _showEditPriceDialog(item),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
              _wPrice,
            ),
            _cell(
              Text(
                '${item.total.toStringAsFixed(2)} دج',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              _wTotal,
            ),
            _cell(
              Text(
                item.category == 'glass'
                    ? '${item.length?.toStringAsFixed(0)} × ${item.glassHeight?.toStringAsFixed(0)}'
                    : (item.length != null ? '${item.length}m' : '-'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: item.category == 'glass'
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
              _wLen,
            ),
            _cell(
              Text(
                item.category == 'glass' ? '-' : (item.colorName ?? '-'),
                style: const TextStyle(fontSize: 12),
              ),
              _wColor,
            ),
            _cell(
              item.isInteractive
                  ? Checkbox(
                      value: item.isActive,
                      onChanged:
                          (widget.model.isCaissonTunnel &&
                              item.originalName ==
                                  'أغطية الشفرات (Bouchons Lames)')
                          ? null
                          : (v) => _handleVariantToggle(
                              item.originalName,
                              item.exclusionGroup,
                              v ?? false,
                            ),
                    )
                  : const SizedBox.shrink(),
              _wCheck,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  // --- دالة تعديل العناصر والبحث الذكي ---
  void _showSwapDialog(BomItem item) async {
    String pType = item.originalName;
    String pCategory = item.category;

    bool isFrameClicked = false;
    bool isSashClicked = false;
    bool isSideCoverClicked = false;

    // التعرف على الإطار
    if (pType == 'الإطار (Frame)' || pType == 'الإطار (Cadre)') {
      isFrameClicked = true;
    } else if (widget.model.frameOverride != null) {
      String frameDisplay =
          '${widget.model.frameOverride!['code'] ?? ''} - ${widget.model.frameOverride!['name']}'
              .trim();
      if (frameDisplay.startsWith('- ')) {
        frameDisplay = frameDisplay.substring(2);
      }
      if (pType == frameDisplay) isFrameClicked = true;
    }

    // التعرف على الظلفة
    if (pType == 'الظلفة (Sash)') {
      isSashClicked = true;
    } else if (widget.model.sashOverride != null) {
      String sashDisplay =
          '${widget.model.sashOverride!['code'] ?? ''} - ${widget.model.sashOverride!['name']}'
              .trim();
      if (sashDisplay.startsWith('- ')) sashDisplay = sashDisplay.substring(2);
      if (pType == sashDisplay) isSashClicked = true;
    }

    // التعرف على الغطاء الجانبي
    if (pType == 'الغطاء الجانبي (Side Cover)') {
      isSideCoverClicked = true;
    } else if (widget.model.sideCoverOverride != null) {
      String sideCoverDisplay =
          '${widget.model.sideCoverOverride!['code'] ?? ''} - ${widget.model.sideCoverOverride!['name']}'
              .trim();
      if (sideCoverDisplay.startsWith('- ')) {
        sideCoverDisplay = sideCoverDisplay.substring(2);
      }
      if (pType == sideCoverDisplay) isSideCoverClicked = true;
    }

    // --- ضغطة زر الإطار ---
    if (isFrameClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'frame',
          category: 'profile',
          seriesId: widget.model.activeSeries?.id,
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;

        // جلب الحديد المرتبط بالإطار الجديد
        if (mutableSelected['linked_renfort_id'] != null) {
          final dbInstance = await SqlDatabase().db;
          final rRes = await dbInstance!.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [mutableSelected['linked_renfort_id']],
          );
          if (rRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(rRes.first);
            final rPrice = await SqlDatabase().getSectionPrice(
              rMap['id'] as int,
              widget.model.selectedDbColor?['id'],
            );
            rMap['calculated_price'] = rPrice > 0
                ? rPrice
                : _safeDouble(rMap['price_dzd'] ?? rMap['price']);
            widget.model.componentOverrides['حديد الإطار (Renfort Frame)'] =
                rMap;
          }
        } else {
          widget.model.componentOverrides.remove('حديد الإطار (Renfort Frame)');
        }

        setState(() {
          widget.model.frameOverride = mutableSelected;
          widget.model.updateProfileThickness();
          widget.model.refreshUI();
        });
      }
      return;
    }

    // --- ضغطة زر الظلفة ---
    if (isSashClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'sash',
          category: 'profile',
          seriesId: widget.model.activeSeries?.id,
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;

        // جلب الحديد المرتبط بالظلفة الجديدة
        if (mutableSelected['linked_renfort_id'] != null) {
          final dbInstance = await SqlDatabase().db;
          final rRes = await dbInstance!.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [mutableSelected['linked_renfort_id']],
          );
          if (rRes.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(rRes.first);
            rMap['calculated_price'] = _safeDouble(
              rMap['price_dzd'] ?? rMap['price'],
            );
            widget.model.componentOverrides['حديد الظلفة (Renfort Sash)'] =
                rMap;

            // Look up Mifsal renfort in the database
            final mifsalRes = await dbInstance.query(
              'Sections',
              where:
                  'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
              whereArgs: [
                widget.model.activeSeries?.id,
                '%مفصل%',
                '%مفصل%',
                '%مفاصل%',
                '%مفاصل%',
                '%mifsal%',
                '%mifsal%',
                '%paumelle%',
                '%paumelle%',
                '%pomelle%',
                '%pomelle%',
              ],
              limit: 1,
            );
            if (mifsalRes.isNotEmpty) {
              final mifsalMap = Map<String, dynamic>.from(mifsalRes.first);
              mifsalMap['calculated_price'] = _safeDouble(
                mifsalMap['price_dzd'] ?? mifsalMap['price'],
              );
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  mifsalMap;
            } else {
              widget.model.componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  rMap;
            }
          }
        } else {
          widget.model.componentOverrides.remove('حديد الظلفة (Renfort Sash)');
          widget.model.componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
        }

        setState(() {
          widget.model.sashOverride = mutableSelected;
          widget.model.updateAllSashThicknesses();
          widget.model.refreshUI();
        });
      }
      return;
    }

    // --- ضغطة زر الغطاء الجانبي ---
    if (isSideCoverClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'side_cover',
          category: 'profile',
          seriesId: widget.model.activeSeries?.id,
        ),
      );
      if (selected != null && mounted) {
        double price = 0.0;
        if (widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(selected['id'], colorId);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;

        setState(() {
          widget.model.sideCoverOverride = mutableSelected;
          widget.model.refreshUI();
        });
      }
      return;
    }

    // --- ضغطة الجوانات (Joints) ---
    if (pType.contains('جوان') || pType.toLowerCase().contains('joint')) {
      pCategory = 'joint';
      if (pType.contains('بروس') || pType.toLowerCase().contains('bross')) {
        pType = ('Joint bross');
      }
    } else if (pType.contains('براغي')) {
      pCategory = 'accessory';
      if (pType.contains('براغي حديد الدعم')) {
        pType = 'is_renfort_screw';
      } else if (pType.contains('براغي بوشون باتمو')) {
        pType = 'is_bouchon_batmo_screw';
      } else if (pType.contains('براغي الباتمو')) {
        pType = 'is_batmo_screw';
      } else if (pType.contains('براغي الكيت'))
        pType = 'is_kit_screw';
      else if (pType.contains('براغي المانيفال'))
        pType = 'is_manivelle_screw';
      else if (pType.contains('براغي المحرك'))
        pType = 'is_moteur_screw';
      else if (pType.contains('براغي الصندوق')) {
        pType = 'is_caisson_screw';
      } else if (pType.contains('براغي التجميع'))
        pType = 'is_assembly_screw';
      else if (pType.contains('براغي التركيب'))
        pType = 'is_installation_screw';
      else if (pType.contains('براغي الإكسسوارات'))
        pType = 'is_accessory_screw';
    } else if (pCategory == 'accessory') {
      if (pType.contains('قاش دوبل')) {
        pType = 'is_gache_double';
      } else if (pType.contains('اسبانيوليت') || pType.contains('إسبانيوليت')) {
        pType = 'اسبانيوليت';
      } else if (pType.contains('مفاصل') || pType.contains('Hinges')) {
        pType = 'مفاصل';
      } else if ((pType.contains('فيرو') || pType.contains('Verrou')) &&
          !pType.contains('Central')) {
        pType = 'فيرو';
      } else if (pType.contains('مقبض') ||
          pType.contains('Handle') ||
          pType.contains('Poignée')) {
        pType = 'مقبض';
      } else if (pType.contains('الطاسو') ||
          pType.toLowerCase().contains('tasso')) {
        pType = 'tasso';
      }
    } else if (pCategory == 'profile') {
      if (pType.toLowerCase().contains('renfort') ||
          pType.contains('renfore') ||
          pType.contains('الدعم') ||
          pType.contains('حديد')) {
        pType = 'renfort';
      } else if (pType.toLowerCase().contains('traverse') ||
          pType.contains('التقسيم')) {
        pType = 'mullion';
      } else if (pType.toLowerCase().contains('bouchon') ||
          pType.contains('بوشون') ||
          pType.toLowerCase().contains('bochon')) {
        pType = 'bouchon batmo';
      } else if (pType.toLowerCase().contains('batmo') ||
          pType.contains('باتمو')) {
        pType = 'batmo';
      }
    } else if (pCategory == 'shutter') {
      if (pType.contains('مانيفال') ||
          pType.toLowerCase().contains('manivelle')) {
        pType = 'مانيفال';
      } else if (pType.contains('محرك') ||
          pType.toLowerCase().contains('moteur')) {
        pType = 'محرك';
      } else if (pType.contains('صندوق') ||
          pType.toLowerCase().contains('caisson')) {
        pType = 'صندوق';
      } else if (pType.contains('كيت') || pType.toLowerCase().contains('kit')) {
        pType = 'كيت';
      } else if (pType.contains('سكك') ||
          pType.toLowerCase().contains('coulisse')) {
        pType = 'سكك';
      } else if (pType.toLowerCase().contains('lame finale') ||
          pType.contains('النهائية') ||
          pType.contains('نهائية')) {
        pType = 'شريحة نهائية';
      } else if (pType.contains('شرائح') ||
          pType.toLowerCase().contains('lame')) {
        pType = 'شريحة';
      } else if (pType.contains('محور') ||
          pType.toLowerCase().contains('axe')) {
        pType = 'محور';
      } else if (pType.contains('أطاش') ||
          pType.toLowerCase().contains('attache')) {
        pType = 'أطاش';
      } else if (pType.contains('سيبور موتور') ||
          pType.toLowerCase().contains('support_moteur') ||
          pType.toLowerCase().contains('support moteur')) {
        pType = 'سيبور موتور';
      } else if (pType.contains('الامبو') ||
          pType.toLowerCase().contains('embout')) {
        pType = 'الامبو';
      } else if (pType.contains('سيبور رولمو') ||
          pType.toLowerCase().contains('support_roulement') ||
          pType.toLowerCase().contains('support roulement')) {
        pType = 'سيبور رولمو';
      } else if (pType.contains('أغطية الشفرات') ||
          pType.toLowerCase().contains('bouchons lames') ||
          pType.toLowerCase().contains('bouchon lame')) {
        pType = 'أغطية الشفرات';
      }
    }

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProfileSelectorDialog(
        profileType: pType,
        category: pCategory,
        seriesId: widget.model.activeSeries?.id,
        windowHeight: widget.model.height,
        targetSize: widget.model.shutterBoxHeight,
      ),
    );

    if (selected != null && mounted) {
      try {
        double price = 0.0;
        final db = SqlDatabase();
        if (pCategory == 'profile' && widget.model.selectedDbColor != null) {
          int colorId = widget.model.selectedDbColor!['id'];
          price = await db.getSectionPrice(selected['id'], colorId);
        } else {
          price = _safeDouble(selected['price_dzd'] ?? selected['price']);
        }

        final mutableSelected = Map<String, dynamic>.from(selected);
        if (price > 0) mutableSelected['calculated_price'] = price;

        final isKitItem =
            item.originalName.contains('Kit') ||
            item.originalName.contains('كيت');
        final isCaisson = item.originalName == 'الصندوق (Caisson)';

        Map<String, dynamic>? companionCaissonToSet;

        if (isCaisson || isKitItem) {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              if (isCaisson) {
                // Find and set active kits companion
                final isMotor = widget.model.shutterMechanism == 'محرك';
                final isCrankSwap =
                    widget.model.shutterMechanism == 'منايفال' ||
                    widget.model.shutterMechanism == 'مانيفال' ||
                    widget.model.shutterMechanism == 'مانيفر';
                final List<String> activeKitKeys;
                if (isMotor) {
                  activeKitKeys = ['كيت فولي موتور (Kit Volet Moteur)'];
                } else if (isCrankSwap) {
                  activeKitKeys = [
                    'كيت فولي مانيفر (Kit Volet Manivelle)',
                    'كيت مانيفر (Kit Manivelle)',
                  ];
                } else {
                  activeKitKeys = ['كيت حزام (Kit Sangle)'];
                }

                for (var kitKey in activeKitKeys) {
                  List<String> keywords = [];
                  if (kitKey == 'كيت فولي موتور (Kit Volet Moteur)') {
                    keywords = [
                      'kit_moteur',
                      'Kit Moteur',
                      'kit moteur',
                      'كيت محرك',
                    ];
                  } else if (kitKey ==
                      'كيت فولي مانيفر (Kit Volet Manivelle)') {
                    keywords = [
                      'kit volet',
                      'Kit Volet',
                      'Kit Volée',
                      'Kit Shutter',
                      'كيت الستار',
                      'Kit',
                    ];
                  } else if (kitKey == 'كيت مانيفر (Kit Manivelle)') {
                    keywords = [
                      'kit_manivelle',
                      'Kit Manivelle',
                      'كيت مانيفال',
                      'kit manivelle',
                    ];
                  } else if (kitKey == 'كيت حزام (Kit Sangle)') {
                    keywords = [
                      'kit_sangle',
                      'Kit Sangle',
                      'kit sangle',
                      'كيت حزام',
                      'kit volet',
                      'Kit Volet',
                      'Kit',
                    ];
                  }

                  String whereClause = keywords
                      .map((_) => 'name LIKE ? OR component_type LIKE ?')
                      .join(' OR ');
                  List<String> args = [];
                  for (var kw in keywords) {
                    args.addAll(['%$kw%', '%$kw%']);
                  }

                  final compRes = await dbInstance.query(
                    'ShutterComponents',
                    where:
                        "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
                    whereArgs: args,
                  );
                  for (var row in compRes) {
                    if (getComponentSize(row) == selectedDigits) {
                      final matchedCompanion = Map<String, dynamic>.from(row);
                      matchedCompanion['calculated_price'] = _safeDouble(
                        matchedCompanion['price_dzd'] ??
                            matchedCompanion['price'],
                      );
                      widget.model.componentOverrides[kitKey] =
                          matchedCompanion;
                      break;
                    }
                  }
                }
              } else {
                // The item selected is a kit. Find companion caisson
                final compRes = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "(LOWER(name) LIKE '%box%' OR name LIKE '%صندوق%' OR LOWER(name) LIKE '%caisson%') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in compRes) {
                  if (getComponentSize(row) == selectedDigits) {
                    companionCaissonToSet = Map<String, dynamic>.from(row);
                    companionCaissonToSet['calculated_price'] = _safeDouble(
                      companionCaissonToSet['price_dzd'] ??
                          companionCaissonToSet['price'],
                    );
                    break;
                  }
                }
              }
            }
          }
        }

        Map<String, dynamic>? companionLame;
        Map<String, dynamic>? companionCoulisse;
        Map<String, dynamic>? companionFinale;

        if (item.originalName == 'الشرائح (Lames)' ||
            item.originalName == 'السكك (Coulisses)' ||
            item.originalName == 'الشريحة النهائية (Lame Finale)') {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              // 1. Find Slat (Lame) companion if not selected (using closest size and matching subtype)
              if (item.originalName != 'الشرائح (Lames)') {
                final targetSubtype =
                    (item.originalName == 'الشريحة النهائية (Lame Finale)')
                    ? (mutableSelected['shutter_subtype']?.toString() ??
                          'normal')
                    : (widget
                              .model
                              .componentOverrides['الشرائح (Lames)']?['shutter_subtype']
                              ?.toString() ??
                          'normal');
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "(LOWER(name) LIKE '%lame%' OR name LIKE '%شريح%') AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: [targetSubtype],
                );
                final targetSize = double.tryParse(selectedDigits) ?? 0.0;
                if (res.isNotEmpty && targetSize > 0) {
                  Map<String, dynamic>? closestLame;
                  double minDiff = double.infinity;
                  for (var row in res) {
                    final rowName = row['name'].toString();
                    if (rowName.toLowerCase().contains('final') ||
                        rowName.toLowerCase().contains('finale') ||
                        rowName.contains('نهائي')) {
                      continue;
                    }
                    final szStr = getComponentSize(row) ?? '';
                    final sz = double.tryParse(szStr) ?? 0.0;
                    if (sz > 0) {
                      final diff = (sz - targetSize).abs();
                      if (diff < minDiff) {
                        minDiff = diff;
                        closestLame = row;
                      }
                    }
                  }
                  if (closestLame != null) {
                    companionLame = Map<String, dynamic>.from(closestLame);
                    companionLame['calculated_price'] = _safeDouble(
                      companionLame['price_dzd'] ?? companionLame['price'],
                    );
                  }
                }
                if (companionLame == null) {
                  final resFallback = await dbInstance.query(
                    'ShutterComponents',
                    where:
                        "(LOWER(name) LIKE '%lame%' OR name LIKE '%شريح%') AND (is_active = 1 OR is_active IS NULL)",
                  );
                  for (var row in resFallback) {
                    final rowName = row['name'].toString();
                    if (rowName.toLowerCase().contains('final') ||
                        rowName.toLowerCase().contains('finale') ||
                        rowName.contains('نهائي')) {
                      continue;
                    }
                    if (getComponentSize(row) == selectedDigits) {
                      companionLame = Map<String, dynamic>.from(row);
                      companionLame['calculated_price'] = _safeDouble(
                        companionLame['price_dzd'] ?? companionLame['price'],
                      );
                      break;
                    }
                  }
                }
              }

              // 2. Find Rail (Coulisse) companion if not selected
              if (item.originalName != 'السكك (Coulisses)') {
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "(LOWER(name) LIKE '%coulisse%' OR name LIKE '%سك%') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in res) {
                  if (getComponentSize(row) == selectedDigits) {
                    companionCoulisse = Map<String, dynamic>.from(row);
                    companionCoulisse['calculated_price'] = _safeDouble(
                      companionCoulisse['price_dzd'] ??
                          companionCoulisse['price'],
                    );
                    break;
                  }
                }
              }

              // 3. Find Lame Finale companion if not selected
              if (item.originalName != 'الشريحة النهائية (Lame Finale)') {
                final targetSubtype = (item.originalName == 'الشرائح (Lames)')
                    ? (mutableSelected['shutter_subtype']?.toString() ??
                          'normal')
                    : (widget
                              .model
                              .componentOverrides['الشرائح (Lames)']?['shutter_subtype']
                              ?.toString() ??
                          'normal');
                final targetSize = double.tryParse(selectedDigits) ?? 0.0;
                if (targetSize > 0) {
                  companionFinale = await _findClosestFinalBlade(
                    dbInstance,
                    targetSize,
                    targetSubtype,
                  );
                }
              }
            }
          }
        }

        Map<String, dynamic>? companionAxe;
        Map<String, dynamic>? companionAttache;
        Map<String, dynamic>? companionSupportMoteur;
        Map<String, dynamic>? companionEmbout;
        Map<String, dynamic>? companionSupportRoulement;
        Map<String, dynamic>? companionTandem;
        Map<String, dynamic>? companionBouchonLame;

        if (item.originalName == 'الشرائح (Lames)') {
          final targetSubtype =
              mutableSelected['shutter_subtype']?.toString() ?? 'normal';
          companionAxe = await _findShutterComponent('laxe', targetSubtype);
          if (companionFinale == null) {
            companionFinale = await _findShutterComponent(
              'final_blade',
              targetSubtype,
            );
          }
          companionAttache = await _findShutterComponent(
            'attache',
            targetSubtype,
          );
          companionSupportMoteur = await _findShutterComponent(
            'support_moteur',
            targetSubtype,
          );
          companionEmbout = await _findShutterComponent(
            'embout',
            targetSubtype,
          );
          companionSupportRoulement = await _findShutterComponent(
            'support_roulement',
            targetSubtype,
          );
          companionTandem = await _findShutterComponent(
            'tandem',
            targetSubtype,
          );
          companionBouchonLame = await _findShutterComponent(
            'bouchon_lame',
            targetSubtype,
          );
        }

        if (item.originalName == 'المحرك (Moteur)') {
          final motorDiameter = (mutableSelected['motor_diameter'] ?? '')
              .toString()
              .trim();
          final motorName = mutableSelected['name']?.toString() ?? '';

          String targetDia = motorDiameter;
          if (targetDia.isEmpty) {
            final diaMatch = RegExp(
              r'(\d+)\s*(?:mm|ملم)',
            ).firstMatch(motorName);
            if (diaMatch != null) {
              targetDia = diaMatch.group(1)!;
            } else {
              if (motorName.contains('60')) {
                targetDia = '60';
              } else if (motorName.contains('40')) {
                targetDia = '40';
              }
            }
          }

          if (targetDia.isNotEmpty) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              final axeRes = await dbInstance.query(
                'ShutterComponents',
                where:
                    "(component_type = 'Axe' OR name LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
              );
              for (final row in axeRes) {
                final axeName = row['name'].toString();
                final axeDiameter = (row['motor_diameter'] ?? '')
                    .toString()
                    .trim();
                if (axeDiameter == targetDia || axeName.contains(targetDia)) {
                  companionAxe = Map<String, dynamic>.from(row);
                  companionAxe['calculated_price'] = _safeDouble(
                    companionAxe['price_dzd'] ?? companionAxe['price'],
                  );
                  break;
                }
              }
            }
          }
        }

        setState(() {
          widget.model.componentOverrides[item.originalName] = mutableSelected;
          if (companionCaissonToSet != null) {
            widget.model.componentOverrides['الصندوق (Caisson)'] =
                companionCaissonToSet;
          }
          if (companionLame != null) {
            widget.model.componentOverrides['الشرائح (Lames)'] = companionLame;
          }
          if (companionCoulisse != null) {
            widget.model.componentOverrides['السكك (Coulisses)'] =
                companionCoulisse;
          }
          if (companionFinale != null) {
            widget.model.componentOverrides['الشريحة النهائية (Lame Finale)'] =
                companionFinale;
          }
          if (companionAxe != null) {
            widget.model.componentOverrides['المحور (Axe)'] = companionAxe;
          }
          if (companionAttache != null) {
            widget.model.componentOverrides['أطاش (Attache)'] =
                companionAttache;
          }
          if (companionSupportMoteur != null) {
            widget.model.componentOverrides['سيبور موتور (Support Moteur)'] =
                companionSupportMoteur;
          }
          if (companionEmbout != null) {
            widget.model.componentOverrides['الامبو (Embout)'] =
                companionEmbout;
          }
          if (companionSupportRoulement != null) {
            widget.model.componentOverrides['سيبور رولمو (Support Roulement)'] =
                companionSupportRoulement;
          }
          if (companionTandem != null) {
            widget.model.componentOverrides['طانديم (Tandem)'] =
                companionTandem;
          }
          if (companionBouchonLame != null) {
            widget.model.componentOverrides['أغطية الشفرات (Bouchons Lames)'] =
                companionBouchonLame;
          }
          final lames = widget.model.componentOverrides['الشرائح (Lames)'];
          if (lames != null) {
            final targetSubtype =
                lames['shutter_subtype']?.toString() ?? 'normal';
            _lastAlignedLameKey =
                "${lames['id']}_${getComponentSize(lames)}_$targetSubtype";
          }
        });

        // Recalculate defaults and weight/torque-based motor selection
        await _fetchDefaults();
      } catch (e) {
        print("Error handling swap selection: $e");
      }
    }
  }

  Future<void> _updatePriceInDatabase(BomItem item, double newPrice) async {
    final db = await SqlDatabase().db;
    if (db == null) return;

    final override = widget.model.componentOverrides[item.originalName];
    final int? dbId = override?['id'];
    final colorId = widget.model.selectedDbColor?['id'];

    String? errorMsg;
    bool success = false;

    try {
      if (item.category == 'profile') {
        if (dbId != null && colorId != null) {
          await SqlDatabase().setSectionColorPrice(dbId, colorId, newPrice);
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات أو لم يتم تحديد لون';
        }
      } else if (item.category == 'accessory') {
        if (dbId != null) {
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM AccessoryColorPrices WHERE accessory_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            await db.insert('AccessoryColorPrices', {
              'accessory_id': dbId,
              'color_id': colorId,
              'price': newPrice,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            await db.update(
              'Accessories',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'shutter') {
        if (dbId != null) {
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM ShutterColorPrices WHERE shutter_component_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            await db.insert('ShutterColorPrices', {
              'shutter_component_id': dbId,
              'color_id': colorId,
              'price': newPrice,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            await db.update(
              'ShutterComponents',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'joint') {
        if (dbId != null) {
          await db.update(
            'Joints',
            {'price_per_meter': newPrice},
            where: 'id = ?',
            whereArgs: [dbId],
          );
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'glass') {
        if (widget.model.zones.isNotEmpty) {
          final glassSpec = widget.model.zones.first.glass;
          if (glassSpec.structure == GlassStructure.simple) {
            final finishKws = widget.model.getFinishKeywords(
              glassSpec.finishOuter,
            );
            final colorKws = widget.model.getColorKeywords(
              glassSpec.colorOuter,
            );
            final glassList = await db.query('Glass');
            int? matchedGlassId;
            for (var g in glassList) {
              String t = g['type'].toString().toLowerCase();
              String n = g['name'].toString().toLowerCase();
              String c = (g['color'] ?? '').toString().toLowerCase();
              bool matchesFinish = finishKws.any(
                (kw) => t.contains(kw) || n.contains(kw),
              );
              bool matchesColor = colorKws.any(
                (kw) => kw.isEmpty ? c.isEmpty : (c == kw || c.contains(kw)),
              );
              if (matchesFinish && matchesColor) {
                matchedGlassId = g['id'] as int?;
                break;
              }
            }
            if (matchedGlassId == null) {
              for (var g in glassList) {
                String t = g['type'].toString().toLowerCase();
                String n = g['name'].toString().toLowerCase();
                bool matchesFinish = finishKws.any(
                  (kw) => t.contains(kw) || n.contains(kw),
                );
                if (matchesFinish) {
                  matchedGlassId = g['id'] as int?;
                  break;
                }
              }
            }
            if (matchedGlassId != null) {
              await db.update(
                'Glass',
                {'price_per_sqm': newPrice},
                where: 'id = ?',
                whereArgs: [matchedGlassId],
              );
              success = true;
            } else {
              errorMsg = 'لم يتم العثور على زجاج مطابق في قاعدة البيانات';
            }
          } else {
            errorMsg =
                'لأن هذا زجاج مزدوج، يرجى تعديل أسعار مكوناته في إدارة الأسعار لتحديث قاعدة البيانات بشكل دائم';
          }
        } else {
          errorMsg = 'لا توجد مواصفات زجاج';
        }
      }
    } catch (e) {
      errorMsg = 'خطأ أثناء التحديث: $e';
    }

    if (mounted) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? Localization.translate(
                    'تم تحديث السعر بنجاح في قاعدة البيانات',
                    lang,
                  )
                : Localization.translate(errorMsg ?? 'فشل التحديث', lang),
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _showEditPriceDialog(BomItem item) {
    final controller = TextEditingController(text: '${item.unitPrice}');
    bool saveToDb = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text('تعديل سعر ${item.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'السعر الجديد (دج)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text(
                      'حفظ في قاعدة البيانات أيضاً',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: saveToDb,
                    onChanged: (val) {
                      setStateDialog(() {
                        saveToDb = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newPrice = double.tryParse(controller.text);
                    if (newPrice != null) {
                      setState(() {
                        if (!widget.model.componentOverrides.containsKey(
                          item.originalName,
                        )) {
                          widget.model.componentOverrides[item.originalName] = {
                            'name': item.name,
                            'price': newPrice,
                            'calculated_price': newPrice,
                          };
                        } else {
                          final Map<String, dynamic> clone = Map.from(
                            widget.model.componentOverrides[item.originalName],
                          );
                          clone['price'] = newPrice;
                          clone['calculated_price'] = newPrice;
                          widget.model.componentOverrides[item.originalName] =
                              clone;
                        }
                      });

                      if (saveToDb) {
                        await _updatePriceInDatabase(item, newPrice);
                      }
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

double _safeDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0.0;
}

String? extractSizeDigits(String name) {
  final regExp = RegExp(r'\d+(\.\d+)?');
  final match = regExp.firstMatch(name);
  if (match == null) return null;
  return match.group(0)!.replaceAll('.', '');
}

String? getComponentSize(Map<String, dynamic> component) {
  final meas = (component['measurement'] ?? '').toString().trim();
  if (meas.isNotEmpty) {
    return meas.replaceAll('.', '').replaceAll(',', '');
  }
  return extractSizeDigits(component['name'].toString());
}
