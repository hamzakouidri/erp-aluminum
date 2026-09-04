import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:database_data/sql_database.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Rule-first resolver for the material table.
///
/// This engine deliberately does not search catalogue names. It resolves an
/// item through its explicit selector type, then through the administrator's
/// Catalog Item Rules.
class BomEngineV2 {
  BomEngineV2({SqlDatabase? database}) : _db = database ?? SqlDatabase();

  final SqlDatabase _db;
  final Map<String, Future<List<Map<String, dynamic>>>> _candidatesCache = {};

  Future<void> stabilizeSelections({
    required WindowModel window,
    required List<BomItem> items,
  }) async {
    final database = await _db.db;
    if (database == null) return;
    for (final item in items) {
      // The selected catalogue item is the administrator's explicit role
      // assignment. Do not clear it merely because an older or incomplete
      // rule row does not qualify for the quantity-table query.
      if (item.isActive && item.catalogItemId != null && !item.isMissing) {
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

  Future<List<BomItem>> filterItemsByAvailableCandidates({
    required WindowModel window,
    required List<BomItem> items,
  }) async {
    final kept = <BomItem>[];
    for (final item in items) {
      // A configured Kit is authoritative: its active child rows are the
      // complete list saved on the Kits page. They must remain available for
      // the expandable Kit row even when a child has no standalone rule row.
      if (item.isActive && item.kitGroupName != null) {
        kept.add(item);
        continue;
      }
      // A profile/accessory that is already linked to a concrete catalogue
      // item is a valid selected role. Keep it in the quantity table even if
      // an old/incomplete CatalogItemRules row still has show_in_quantity=0
      // or is missing altogether. The administrator's selected role and the
      // saved section are the authoritative association in that case.
      if (item.isActive && item.catalogItemId != null && !item.isMissing) {
        kept.add(item);
        continue;
      }
      if (await _itemHasRuleCandidate(window, item)) {
        kept.add(item);
      }
    }
    return kept;
  }

  Future<bool> _itemHasRuleCandidate(WindowModel window, BomItem item) async {
    final category = item.selectorCategory ?? item.category;
    switch (category) {
      case 'profile':
        final selectorType = item.selectorType?.trim() ?? '';
        final roleKeys = <String>{
          if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
          ...seriesRoleKeysForProfileSelectorType(selectorType),
        }.toList();
        if (roleKeys.isEmpty) return false;
        if (roleKeys.contains('reducer') &&
            (!window.hasSimpleGlassForReducer ||
                window.hasDoubleGlassForRules)) {
          return false;
        }
        if (_requiresDoubleSash(roleKeys) && !_hasDoubleSash(window)) {
          return false;
        }
        final seriesId = _seriesIdForItem(window, item);
        if (seriesId == null) return false;
        final candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'profile',
            selectorType: selectorType,
            roleKeys: roleKeys,
            seriesId: seriesId,
            materialType: _materialTypeForItem(window, item),
            hasShutter: window.hasShutter,
            drawingMode: _drawingModeForItem(window, item),
            requireDialog: true,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            targetThicknessMm: item.targetThicknessMm,
          ),
        );
        return candidates.isNotEmpty;
      case 'accessory':
      case 'other':
        final selectorType = item.selectorType?.trim() ?? '';
        final roleKeys = <String>{
          if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
          ...catalogRuleKeysForAccessorySelectorType(selectorType),
        }.toList();
        if (roleKeys.isEmpty) return false;
        if (_requiresDoubleSash(roleKeys) && !_hasDoubleSash(window)) {
          return false;
        }
        final candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'accessory',
            selectorType: selectorType,
            roleKeys: roleKeys,
            seriesId: _seriesIdForItem(window, item),
            materialType: _materialTypeForItem(window, item),
            drawingMode: _drawingModeForItem(window, item),
            requireDialog: true,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            targetThicknessMm: item.targetThicknessMm,
          ),
        );
        return candidates.isNotEmpty;
      case 'joint':
        final selectorType = item.selectorType?.trim() ?? '';
        final roleKeys = <String>{
          if ((item.roleKey ?? '').trim().isNotEmpty) item.roleKey!.trim(),
          ...catalogRuleKeysForJointSelectorType(selectorType),
        }.toList();
        if (roleKeys.isEmpty) return false;
        final seriesId = _seriesIdForItem(window, item);
        if (seriesId == null && !roleKeys.contains('shutter_joint_brosse')) {
          return false;
        }
        final candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'joint',
            selectorType: selectorType,
            roleKeys: roleKeys,
            seriesId: seriesId,
            materialType: _materialTypeForItem(window, item),
            drawingMode: _drawingModeForItem(window, item),
            requireDialog: true,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            targetThicknessMm: item.targetThicknessMm,
          ),
        );
        return candidates.isNotEmpty;
    }

    return true;
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
    if (_requiresDoubleSash(roleKeys) && !_hasDoubleSash(window)) {
      _clearInvalidProfileSelection(window, item, roleKeys);
      return;
    }

    final seriesId = _seriesIdForItem(window, item);
    if (seriesId == null) return;
    final sections = await _resolveCandidates(
      CatalogCandidateQuery(
        category: 'profile',
        selectorType: selectorType,
        roleKeys: roleKeys,
        seriesId: seriesId,
        materialType: _materialTypeForItem(window, item),
        hasShutter: window.hasShutter,
        drawingMode: _drawingModeForItem(window, item),
        requireDialog: true,
        requireQuantity: true,
        hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: window.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
      ),
    );
    if (sections.isEmpty) {
      _clearInvalidProfileSelection(window, item, roleKeys);
      return;
    }
    final currentProfile = _currentProfileSelection(
      window,
      item,
      roleKeys,
      selectorType,
    );
    final matchingCurrent = _matchingCandidate(sections, currentProfile);
    if (matchingCurrent != null && _hasDesignMetadata(currentProfile)) {
      return;
    }

    final selected = Map<String, dynamic>.from(
      matchingCurrent ?? sections.first,
    );
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
    if (ruleKeys.isEmpty) return;
    if (_requiresDoubleSash(ruleKeys) && !_hasDoubleSash(window)) {
      _clearComponentSelection(window, item);
      return;
    }

    final seriesId = _seriesIdForItem(window, item);
    final materialType = _materialTypeForItem(window, item);
    final candidates = await _resolveCandidates(
      CatalogCandidateQuery(
        category: 'accessory',
        selectorType: selectorType,
        roleKeys: ruleKeys,
        seriesId: seriesId,
        materialType: materialType,
        drawingMode: _drawingModeForItem(window, item),
        requireDialog: true,
        requireQuantity: true,
        hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: window.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
      ),
    );
    if (candidates.isEmpty) {
      _clearComponentSelection(window, item);
      return;
    }
    if (_candidateContainsCurrent(
      candidates,
      _currentComponentSelection(window, item),
    )) {
      return;
    }
    final selected = Map<String, dynamic>.from(candidates.first);
    selected['calculated_price'] = await _accessoryPrice(database, selected);
    final key = item.overrideKey ?? item.originalName;
    window.componentOverrides[key] = selected;
    if (key != item.originalName) {
      window.componentOverrides[item.originalName] = selected;
    }
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
    if (seriesId == null && !roleKeys.contains('shutter_joint_brosse')) {
      return;
    }

    final candidates = await _resolveCandidates(
      CatalogCandidateQuery(
        category: 'joint',
        selectorType: selectorType,
        roleKeys: roleKeys,
        seriesId: seriesId,
        materialType: _materialTypeForItem(window, item),
        drawingMode: _drawingModeForItem(window, item),
        requireDialog: true,
        requireQuantity: true,
        hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: window.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
      ),
    );
    if (candidates.isEmpty) {
      _clearComponentSelection(window, item);
      return;
    }
    final matchingCurrent = _matchingCandidate(
      candidates,
      _currentComponentSelection(window, item),
    );
    final sortedFirstId = _catalogInt(candidates.first['id']);
    final matchingCurrentId = _catalogInt(matchingCurrent?['id']);
    if (matchingCurrent != null &&
        (item.targetThicknessMm == null ||
            item.targetThicknessMm! <= 0 ||
            sortedFirstId == matchingCurrentId)) {
      return;
    }
    final selected = Map<String, dynamic>.from(candidates.first);
    selected['calculated_price'] = _safeDouble(
      selected['price_per_meter'] ?? selected['price_dzd'] ?? selected['price'],
    );
    final key = item.overrideKey ?? item.originalName;
    window.componentOverrides[key] = selected;
    if (key != item.originalName) {
      window.componentOverrides[item.originalName] = selected;
    }
  }

  Future<List<Map<String, dynamic>>> _resolveCandidates(
    CatalogCandidateQuery query,
  ) {
    final key = [
      query.category,
      query.selectorType.toLowerCase().trim(),
      query.roleKeys
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(','),
      query.seriesId ?? '',
      (query.materialType ?? '').toLowerCase().trim(),
      query.hasShutter ? '1' : '0',
      query.drawingMode?.name ?? '',
      query.requireDialog ? '1' : '0',
      query.requireQuantity ? '1' : '0',
      query.hasSimpleGlassForReducer == true ? '1' : '0',
      query.hasDoubleGlassForRules == true ? '1' : '0',
      query.targetThicknessMm?.toStringAsFixed(3) ?? '',
    ].join('|');
    return _candidatesCache.putIfAbsent(
      key,
      () => CatalogCandidateResolver(database: _db).resolve(query),
    );
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
    if ((item.roleKey ?? '').trim() == 'shutter_joint_brosse' ||
        (item.materialType ?? '').toLowerCase().trim() == 'shutter') {
      return item.sourceSeriesId;
    }
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
    final originalName = item.originalName.toLowerCase().trim();
    final roleKey = item.roleKey?.toLowerCase().trim() ?? '';

    // In a mixed drawing, the presence of both sash families is not enough
    // to infer the source of generic hardware. BOM rows created for a sliding
    // zone carry either a sliding role/name or the sliding series id; resolve
    // those rows against the sliding catalogue explicitly.
    final isSlidingRole = const {
      'roulette',
      'sliding_kit',
      'sliding_clamp',
      'sliding_lock',
    }.contains(roleKey) ||
        const {
          'roulette',
          'sliding_kit',
          'sliding_clamp',
          'sliding_lock',
        }.contains(selectorType) ||
        originalName.contains('منزلق') ||
        originalName.contains('couliss') ||
        originalName.contains('sliding');
    if (isSlidingRole ||
        (item.sourceSeriesId != null &&
            item.sourceSeriesId == window.activeSlidingSeries?.id)) {
      return AccessoryDrawingMode.sliding;
    }
    if (item.sourceSeriesId != null &&
        item.sourceSeriesId == window.activeSeries?.id) {
      return AccessoryDrawingMode.opening;
    }

    if (selectorType.contains('lateral') ||
        selectorType.contains('central') ||
        selectorType.contains('sash_traverse') ||
        selectorType.contains('sliding_parclose') ||
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

  bool _hasDoubleSash(WindowModel window) =>
      window.zones.any((zone) => zone.content == ZoneContent.doubleSash);

  bool _requiresDoubleSash(Iterable<String> roleKeys) {
    return roleKeys.any(
      (role) =>
          role == 'batmo' ||
          role == 'bouchon_batmo' ||
          role == 'batmo_screw' ||
          role == 'bouchon_batmo_screw',
    );
  }

  Map<String, dynamic>? _currentProfileSelection(
    WindowModel window,
    BomItem item,
    List<String> roleKeys,
    String selectorType,
  ) {
    final lowerType = selectorType.toLowerCase().trim();
    final mode = _drawingModeForItem(window, item);
    if (roleKeys.contains('frame') || lowerType == 'frame') {
      if (mode == AccessoryDrawingMode.sliding) {
        return _asMap(window.slidingFrameOverride);
      }
      if (mode == AccessoryDrawingMode.opening) {
        return _asMap(window.frameOverride);
      }
      return _asMap(window.frameOverride) ??
          _asMap(window.slidingFrameOverride);
    }
    if (roleKeys.contains('sash') || lowerType == 'sash') {
      if (mode == AccessoryDrawingMode.sliding) {
        return _asMap(window.slidingSashOverride);
      }
      if (mode == AccessoryDrawingMode.opening) {
        return _asMap(window.sashOverride);
      }
      return _asMap(window.sashOverride) ?? _asMap(window.slidingSashOverride);
    }
    if (roleKeys.contains('side_cover') || lowerType == 'side_cover') {
      return _asMap(window.sideCoverOverride);
    }
    return _currentComponentSelection(window, item);
  }

  Map<String, dynamic>? _currentComponentSelection(
    WindowModel window,
    BomItem item,
  ) {
    final overrideKey = item.overrideKey ?? item.originalName;
    return _asMap(window.componentOverrides[overrideKey]) ??
        _asMap(window.componentOverrides[item.originalName]);
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  bool _candidateContainsCurrent(
    List<Map<String, dynamic>> candidates,
    Map<String, dynamic>? current,
  ) {
    return _matchingCandidate(candidates, current) != null;
  }

  Map<String, dynamic>? _matchingCandidate(
    List<Map<String, dynamic>> candidates,
    Map<String, dynamic>? current,
  ) {
    final currentId = _catalogInt(current?['id']);
    if (currentId == null) return null;
    for (final row in candidates) {
      if (_catalogInt(row['id']) == currentId) return row;
    }
    return null;
  }

  bool _hasDesignMetadata(Map<String, dynamic>? current) {
    if (current == null) return false;
    return current.keys.any((key) => key.toString().startsWith('design_'));
  }

  void _clearInvalidProfileSelection(
    WindowModel window,
    BomItem item,
    List<String> roleKeys,
  ) {
    if (roleKeys.contains('side_cover')) {
      window.sideCoverOverride = null;
      window.selectedSideCover = null;
    }
    if (roleKeys.contains('reducer')) {
      window.clearReducerOverride();
    }
    _clearComponentSelection(window, item);
  }

  void _clearComponentSelection(WindowModel window, BomItem item) {
    final overrideKey = item.overrideKey ?? item.originalName;
    window.componentOverrides.remove(overrideKey);
    window.componentOverrides.remove(item.originalName);
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
