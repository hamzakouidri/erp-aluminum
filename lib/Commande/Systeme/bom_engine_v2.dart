import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Rule-first resolver for the material table.
///
/// This engine deliberately does not search catalogue names. It resolves an
/// item through its explicit selector type, then through the administrator's
/// rules or typed database columns.
class BomEngineV2 {
  BomEngineV2({SqlDatabase? database}) : _db = database ?? SqlDatabase();

  final SqlDatabase _db;

  Future<void> stabilizeSelections({
    required WindowModel window,
    required List<BomItem> items,
  }) async {
    final database = await _db.db;
    if (database == null) return;

    for (final item in items) {
      if (!item.isMissing) continue;
      final overrideKey = item.overrideKey ?? item.originalName;
      if (window.componentOverrides.containsKey(overrideKey) ||
          window.componentOverrides.containsKey(item.originalName)) {
        continue;
      }

      switch (item.selectorCategory ?? item.category) {
        case 'profile':
          await _resolveProfile(window, item);
          break;
        case 'accessory':
        case 'other':
          await _resolveAccessory(database, window, item);
          break;
        case 'joint':
          await _resolveJoint(database, window, item);
          break;
      }
    }
  }

  Future<void> _resolveProfile(WindowModel window, BomItem item) async {
    final selectorType = item.selectorType?.trim() ?? '';
    final roleKeys = <String>{
      if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
      ...seriesRoleKeysForProfileSelectorType(selectorType),
    }.toList();
    if (roleKeys.isEmpty) return;
    if (roleKeys.contains('reducer') &&
        (!window.hasSimpleGlassForReducer || window.hasDoubleGlassForRules)) {
      window.clearReducerOverride();
      return;
    }

    final seriesId = _seriesIdForItem(window, item);
    if (seriesId == null) return;
    final sections = await _db.getDesignSectionsForRoles(
      seriesId,
      roleKeys,
      requireDialog: false,
      requireQuantity: true,
    );
    if (sections.isEmpty) return;

    final selected = Map<String, dynamic>.from(sections.first);
    final colorId = _catalogInt(window.selectedDbColor?['id']);
    selected['calculated_price'] = colorId == null
        ? _safeDouble(selected['price_dzd'] ?? selected['price'])
        : await _db.getSectionPrice(selected['id'], colorId);

    final lowerType = selectorType.toLowerCase();
    if (lowerType.contains('lateral')) {
      window.applySlidingMontantOverride(selected, central: false);
    } else if (lowerType.contains('central')) {
      window.applySlidingMontantOverride(selected, central: true);
    } else if (lowerType == 'frame') {
      window.applyFrameOverride(
        selected,
        sliding:
            _drawingModeForItem(window, item) == AccessoryDrawingMode.sliding,
      );
    } else if (lowerType == 'sash') {
      window.applySashOverride(
        selected,
        sliding:
            _drawingModeForItem(window, item) == AccessoryDrawingMode.sliding,
      );
    } else if (lowerType == 'side_cover') {
      window.sideCoverOverride = selected;
      window.componentOverrides[item.overrideKey ?? item.originalName] =
          selected;
    } else {
      window.componentOverrides[item.overrideKey ?? item.originalName] =
          selected;
    }
  }

  Future<void> _resolveAccessory(
    Database database,
    WindowModel window,
    BomItem item,
  ) async {
    final selectorType = item.selectorType?.trim() ?? '';
    final ruleKeys = <String>{
      if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
      ...catalogRuleKeysForAccessorySelectorType(selectorType),
    }.toList();
    final typedColumns = catalogFlagColumnsForAccessorySelectorType(
      selectorType,
    );
    if (ruleKeys.isEmpty && typedColumns.isEmpty) return;

    final seriesId = _seriesIdForItem(window, item);
    final materialType = _materialTypeForItem(window, item);
    final isShutterScrew = _isShutterScrewSelectorType(selectorType);
    Map<String, dynamic>? selected;

    if (ruleKeys.isNotEmpty) {
      final rules = await _db.getCatalogItemRules(
        itemTable: 'Accessories',
        seriesId: seriesId,
        roleKeys: ruleKeys,
      );
      for (final rule in rules) {
        if (rule['show_in_quantity'] == 0) continue;
        final itemId = _catalogInt(rule['item_id']);
        if (itemId == null) continue;
        selected = await _firstAccessory(
          database: database,
          seriesId: seriesId,
          materialType: materialType,
          applyMaterialFilter: !isShutterScrew,
          predicate: (row) => _catalogInt(row['id']) == itemId,
        );
        if (selected != null) break;
      }
    }

    if (selected == null && typedColumns.isNotEmpty) {
      selected = await _firstAccessory(
        database: database,
        seriesId: seriesId,
        materialType: materialType,
        applyMaterialFilter: !isShutterScrew,
        predicate: (row) => typedColumns.any((column) => _flag(row[column])),
      );
    }

    if (selected == null) return;
    selected['calculated_price'] = await _accessoryPrice(database, selected);
    final key = item.overrideKey ?? item.originalName;
    window.componentOverrides[key] = selected;
    if (key != item.originalName)
      window.componentOverrides[item.originalName] = selected;
  }

  Future<void> _resolveJoint(
    Database database,
    WindowModel window,
    BomItem item,
  ) async {
    final selectorType = item.selectorType?.trim() ?? '';
    final roleKeys = <String>{
      if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
      ...catalogRuleKeysForJointSelectorType(selectorType),
    }.toList();
    if (roleKeys.isEmpty) return;

    final seriesId = _seriesIdForItem(window, item);
    if (seriesId == null) return;

    Map<String, dynamic>? selected;
    final rules = await _db.getCatalogItemRules(
      itemTable: 'Joints',
      seriesId: seriesId,
      roleKeys: roleKeys,
    );
    for (final rule in rules) {
      if (rule['show_in_quantity'] == 0) continue;
      final itemId = _catalogInt(rule['item_id']);
      if (itemId == null) continue;
      selected = await _firstJoint(
        database: database,
        seriesId: seriesId,
        predicate: (row) => _catalogInt(row['id']) == itemId,
      );
      if (selected != null) break;
    }

    selected ??= await _firstJoint(
      database: database,
      seriesId: seriesId,
      predicate: (row) =>
          roleKeys.any((roleKey) => jointCatalogItemMatchesRole(row, roleKey)),
    );

    if (selected == null) return;
    selected['calculated_price'] = _safeDouble(
      selected['price_per_meter'] ?? selected['price_dzd'] ?? selected['price'],
    );
    final key = item.overrideKey ?? item.originalName;
    window.componentOverrides[key] = selected;
    if (key != item.originalName)
      window.componentOverrides[item.originalName] = selected;
  }

  Future<Map<String, dynamic>?> _firstAccessory({
    required Database database,
    required int? seriesId,
    required String materialType,
    required bool applyMaterialFilter,
    required bool Function(Map<String, dynamic> row) predicate,
  }) async {
    final where = <String>['is_active = 1 OR is_active IS NULL'];
    final args = <Object?>[];
    if (seriesId != null) {
      where.add(
        "((series_id = ?) OR (series_ids IS NOT NULL AND TRIM(series_ids) != '' AND ',' || REPLACE(series_ids, ' ', '') || ',' LIKE ?) OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = '')))",
      );
      args.add(seriesId);
      args.add('%,$seriesId,%');
    }
    if (applyMaterialFilter) {
      if (materialType == 'pvc') {
        where.add("TRIM(LOWER(material_type)) IN ('pvc', 'both')");
      } else {
        where.add(
          "(TRIM(LOWER(material_type)) IN ('aluminium', 'aluminum', 'both') OR material_type IS NULL OR TRIM(material_type) = '')",
        );
      }
    }

    final rows = (await database.query(
      'Accessories',
      where: where.map((part) => '($part)').join(' AND '),
      whereArgs: args,
      orderBy: 'id ASC',
    )).map((row) => Map<String, dynamic>.from(row)).where(predicate).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final scoped = _seriesPriority(
        a,
        seriesId,
      ).compareTo(_seriesPriority(b, seriesId));
      if (scoped != 0) return scoped;
      return (_catalogInt(a['id']) ?? 0).compareTo(_catalogInt(b['id']) ?? 0);
    });
    return Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> _firstJoint({
    required Database database,
    required int seriesId,
    required bool Function(Map<String, dynamic> row) predicate,
  }) async {
    final rows = (await database.query(
      'Joints',
      where:
          "((series_id = ?) OR (series_ids IS NOT NULL AND TRIM(series_ids) != '' AND ',' || REPLACE(series_ids, ' ', '') || ',' LIKE ?) OR ((series_id IS NULL OR series_id = 0) AND (series_ids IS NULL OR TRIM(series_ids) = ''))) AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [seriesId, '%,$seriesId,%'],
      orderBy: 'id ASC',
    )).map((row) => Map<String, dynamic>.from(row)).where(predicate).toList();
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final scoped = _seriesPriority(
        a,
        seriesId,
      ).compareTo(_seriesPriority(b, seriesId));
      if (scoped != 0) return scoped;
      return (_catalogInt(a['id']) ?? 0).compareTo(_catalogInt(b['id']) ?? 0);
    });
    return Map<String, dynamic>.from(rows.first);
  }

  Future<double> _accessoryPrice(
    Database database,
    Map<String, dynamic> item,
  ) async {
    final id = _catalogInt(item['id']);
    if (id == null) return _safeDouble(item['price_dzd'] ?? item['price']);
    final prices = await database.query(
      'AccessoryColorPrices',
      where: 'accessory_id = ?',
      whereArgs: [id],
      orderBy: 'price DESC',
      limit: 1,
    );
    if (prices.isNotEmpty) {
      final price = _safeDouble(prices.first['price']);
      if (price > 0) return price;
    }
    return _safeDouble(item['price_dzd'] ?? item['price']);
  }

  int? _seriesIdForItem(WindowModel window, BomItem item) {
    if (item.sourceSeriesId != null) return item.sourceSeriesId;
    final mode = _drawingModeForItem(window, item);
    if (mode == AccessoryDrawingMode.sliding) {
      return window.activeSlidingSeries?.id ?? window.activeSeries?.id;
    }
    if (mode == AccessoryDrawingMode.opening) return window.activeSeries?.id;
    return window.systemMode == 'sliding'
        ? window.activeSlidingSeries?.id
        : window.activeSeries?.id;
  }

  String _materialTypeForItem(WindowModel window, BomItem item) {
    final materialType = item.materialType?.toLowerCase().trim();
    if (materialType == 'pvc' ||
        materialType == 'aluminium' ||
        materialType == 'aluminum') {
      return materialType == 'aluminum' ? 'aluminium' : materialType!;
    }
    return _drawingModeForItem(window, item) == AccessoryDrawingMode.sliding
        ? (window.isSlidingPVC ? 'pvc' : 'aluminium')
        : (window.isPVC ? 'pvc' : 'aluminium');
  }

  AccessoryDrawingMode? _drawingModeForItem(WindowModel window, BomItem item) {
    final selectorType = item.selectorType?.toLowerCase().trim() ?? '';
    if (selectorType.contains('lateral') ||
        selectorType.contains('central') ||
        selectorType.contains('sash_traverse') ||
        selectorType == 'rail') {
      return AccessoryDrawingMode.sliding;
    }
    final hasSliding = window.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpening = window.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );
    if (hasSliding && !hasOpening) return AccessoryDrawingMode.sliding;
    if (hasOpening && !hasSliding) return AccessoryDrawingMode.opening;
    return null;
  }

  int _seriesPriority(Map<String, dynamic> row, int? seriesId) {
    if (seriesId == null) return 1;
    if (_catalogInt(row['series_id']) == seriesId) return 0;
    final ids = (row['series_ids'] ?? '').toString().replaceAll(' ', '');
    return ids.split(',').contains(seriesId.toString()) ? 0 : 1;
  }

  bool _isShutterScrewSelectorType(String selectorType) {
    final lower = selectorType.toLowerCase();
    return lower == 'is_kit_screw' ||
        lower == 'is_caisson_screw' ||
        lower == 'is_moteur_screw' ||
        lower == 'is_manivelle_screw';
  }

  bool _flag(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  int? _catalogInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim());
  }

  double _safeDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.replaceAll(',', '.')) ?? 0.0;
  }
}
