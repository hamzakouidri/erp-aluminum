part of '../material_consumption_screen.dart';

/// Building and matching the BOM rows of the material table.
extension _MaterialBom on _MaterialConsumptionScreenState {
  String _canonicalStockType(String? value) {
    final normalized = (value ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[ _-]+'),
      '',
    );
    if (const {
      'profile',
      'profiles',
      'section',
      'sections',
    }.contains(normalized)) {
      return 'Section';
    }
    if (const {'accessory', 'accessories'}.contains(normalized)) {
      return 'Accessory';
    }
    if (const {'shuttercomponent', 'shuttercomponents'}.contains(normalized)) {
      return 'ShutterComponent';
    }
    if (const {'joint', 'joints'}.contains(normalized)) return 'Joints';
    if (normalized == 'glass') return 'Glass';
    return value?.trim() ?? '';
  }

  String _stockKey(String? itemType, int itemId, int? colorId) =>
      '${_canonicalStockType(itemType)}|$itemId|${colorId ?? 0}';

  double? _mainStockFor(BomItem item) {
    final id = item.catalogItemId;
    final type = item.inventoryItemType;
    if (id == null || type == null || type.trim().isEmpty) return null;
    final colorId = _itemColorId(item);
    return _mainWarehouseStock[_stockKey(type, id, colorId)] ??
        _mainWarehouseStock[_stockKey(type, id, null)];
  }

  Future<Map<String, double>> _loadMainWarehouseStock() async {
    final database = SqlDatabase();
    final sqlite = await database.db;
    if (sqlite == null) return const {};
    final rows = await sqlite.query('CurrentStock');
    final result = <String, double>{};
    for (final row in rows) {
      final rawItemId = row['item_id'];
      final itemId = rawItemId is num
          ? rawItemId.toInt()
          : int.tryParse('${rawItemId ?? ''}');
      if (itemId == null) continue;
      final rawColorId = row['color_id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('${rawColorId ?? ''}');
      final rawQuantity = row['quantity'];
      final quantity = rawQuantity is num
          ? rawQuantity.toDouble()
          : double.tryParse('${rawQuantity ?? ''}') ?? 0.0;
      final key = _stockKey(row['item_type']?.toString(), itemId, colorId);
      result[key] = (result[key] ?? 0.0) + quantity;
      // Also accumulate to general key (null color) so items with or without
      // explicit colors match seamlessly in consumption view.
      if (colorId != null && colorId != 0) {
        final totalKey = _stockKey(row['item_type']?.toString(), itemId, null);
        result[totalKey] = (result[totalKey] ?? 0.0) + quantity;
      }
    }
    return result;
  }

  String _localizedBomUnit(String unit, AppLanguage language) {
    final trimmed = unit.trim();
    if (trimmed.isEmpty) return trimmed;
    if (language == AppLanguage.french) {
      if (trimmed == 'بارة' || trimmed == 'قطاع') return 'bar';
      if (trimmed == 'متر') return 'm';
      if (trimmed == 'قطعة') return 'pièce';
      if (trimmed == 'طقم') return 'kit';
    } else if (language == AppLanguage.english) {
      if (trimmed == 'بارة' || trimmed == 'قطاع') return 'bar';
      if (trimmed == 'متر') return 'm';
      if (trimmed == 'قطعة') return 'pcs';
      if (trimmed == 'طقم') return 'kit';
    }
    return Localization.translate(trimmed, language);
  }

  // دالة مساعدة: تتحقق إذا كان النص يحتوي حروف عربية (لتقرير هل نعرض الاسم الثانوي أو لا)
  bool _hasArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  int? _catalogInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}'.trim());
  }

  int? _catalogSeriesId(Map<String, dynamic>? item) =>
      item == null ? null : _catalogInt(item['series_id']);

  String _catalogSearchText(Map<String, dynamic>? item) {
    if (item == null) return '';
    return '${item['code'] ?? ''} ${item['name'] ?? ''} ${item['type'] ?? ''}'
        .toLowerCase();
  }

  bool _textLooksSlidingProfile(String text) {
    final lower = text.toLowerCase();
    return const [
      'couliss',
      'sliding',
      '2rail',
      '3rail',
      '2 rail',
      '3 rail',
      'monorail',
      'galandage',
      'sash lateral',
      'sash central',
      'sash traverse',
      'chicane',
      'rail',
      'منزلق',
      'جرار',
      'كوليس',
      'جانبي',
      'وسطي',
      'سكة',
      'ريديكتور',
    ].any(lower.contains);
  }

  bool _textLooksOpeningProfile(String text) {
    final lower = text.toLowerCase();
    return const [
      'ouvrant',
      'battant',
      'opening',
      'mifsal',
      'paumelle',
      'hinge',
      'system ob',
      'demi ob',
      'مفتح',
      'فتح',
      'ظلفة',
      'مفصل',
      'مفاصل',
      'سيستم',
    ].any(lower.contains);
  }

  AccessoryDrawingMode? _drawingModeFromProfileText(String text) {
    if (_textLooksSlidingProfile(text)) return AccessoryDrawingMode.sliding;
    if (_textLooksOpeningProfile(text)) return AccessoryDrawingMode.opening;
    return null;
  }

  AccessoryDrawingMode? _drawingModeFromCatalogMap(Map<String, dynamic>? item) {
    if (item == null) return null;
    return _drawingModeFromProfileText(_catalogSearchText(item));
  }

  AccessoryDrawingMode? _profileDrawingModeForItem(
    BomItem item, {
    bool isFrame = false,
    bool isSash = false,
    bool isSideCover = false,
  }) {
    final rowText =
        '${item.originalName} ${item.selectorType ?? ''} ${item.roleKey ?? ''}'
            .toLowerCase();
    if (_containsAny(rowText, const [
      'bouchon batmo',
      'bochon batmo',
      'بوشون باتمو',
      'بوشون الباتمو',
    ])) {
      // Bouchon Batmo is an opening-system profile even when the same
      // drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }
    if (_containsAny(rowText, const ['batmo', 'باتمو'])) {
      // Batmo belongs to the opening series and is only valid for a pair of
      // opening sashes, even when the drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }
    if (rowText.contains('plinthe') || rowText.contains('بلانت')) {
      // A sash plinthe belongs to the opening sash catalogue even when the
      // drawing also contains sliding zones.
      return AccessoryDrawingMode.opening;
    }

    final rowMode = isSideCover
        ? null
        : _drawingModeFromProfileText(_bomRowSearchText(item));
    if (rowMode != null) return rowMode;

    if (isFrame) {
      // The BOM source series is authoritative for a frame. This protects
      // the quantity/cost table from an old generic name such as "Frame"
      // after the drawing has selected the sliding series.
      final sourceSeriesId = item.sourceSeriesId;
      final slidingSeriesId = widget.model.activeSlidingSeries?.id;
      final openingSeriesId = widget.model.activeSeries?.id;
      if (sourceSeriesId != null &&
          sourceSeriesId == slidingSeriesId &&
          sourceSeriesId != openingSeriesId) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingFrameOverride)) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.frameOverride)) {
        return _drawingModeFromCatalogMap(widget.model.frameOverride) ??
            AccessoryDrawingMode.opening;
      }
      final activeFrameMode = _drawingModeFromCatalogMap(
        widget.model.activeFrameOverride,
      );
      if (activeFrameMode != null) return activeFrameMode;
      if (widget.model.usesSlidingPrimaryProfiles) {
        return AccessoryDrawingMode.sliding;
      }
    }

    if (isSash) {
      if (_bomRowMentionsCatalog(item, widget.model.slidingSashOverride)) {
        return AccessoryDrawingMode.sliding;
      }
      if (_bomRowMentionsCatalog(item, widget.model.sashOverride)) {
        return _drawingModeFromCatalogMap(widget.model.sashOverride) ??
            AccessoryDrawingMode.opening;
      }
      final slidingSashMode = _drawingModeFromCatalogMap(
        widget.model.slidingSashOverride,
      );
      if (slidingSashMode != null) return slidingSashMode;
    }

    if (isSideCover) {
      final sideCoverMode = _drawingModeFromCatalogMap(
        widget.model.sideCoverOverride,
      );
      if (sideCoverMode != null) return sideCoverMode;
      if (widget.model.usesSlidingPrimaryProfiles) {
        return AccessoryDrawingMode.sliding;
      }
    }

    final hasSlidingSash = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );
    if (hasSlidingSash && !hasOpeningSash) {
      return AccessoryDrawingMode.sliding;
    }
    if (hasOpeningSash && !hasSlidingSash) {
      return AccessoryDrawingMode.opening;
    }

    if (widget.model.systemMode == 'sliding') {
      return AccessoryDrawingMode.sliding;
    }
    return null;
  }

  Map<String, dynamic>? _selectedProfileMapForTarget(
    BomItem item,
    AccessoryDrawingMode? mode, {
    bool isFrame = false,
    bool isSash = false,
    bool isSideCover = false,
  }) {
    if (isFrame) {
      if (mode == AccessoryDrawingMode.sliding) {
        return widget.model.slidingFrameOverride ??
            widget.model.activeFrameOverride;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingFrameOverride)) {
        return widget.model.slidingFrameOverride;
      }
      return widget.model.frameOverride ?? widget.model.activeFrameOverride;
    }

    if (isSash) {
      if (mode == AccessoryDrawingMode.sliding) {
        return widget.model.slidingSashOverride;
      }
      if (_bomRowMentionsCatalog(item, widget.model.slidingSashOverride)) {
        return widget.model.slidingSashOverride;
      }
      return widget.model.sashOverride;
    }

    if (isSideCover) {
      return widget.model.sideCoverOverride;
    }

    return _componentOverrideForBom(item);
  }

  /// The BOM tells us which sash owns each hardware row.  This must take
  /// precedence over [WindowModel.systemMode], because a mixed PVC drawing
  /// has opening and sliding components at the same time.
  AccessoryDrawingMode? _accessoryDrawingModeForItem(BomItem item) {
    final name = _bomRowSearchText(item);
    if (item.category == 'profile') {
      return _profileDrawingModeForItem(item) ?? AccessoryDrawingMode.opening;
    }
    if (item.category != 'accessory' && item.category != 'other') return null;

    final isExplicitSliding = [
      'منزلق',
      'جرار',
      'كوليس',
      'كوريس',
      'couliss',
      'sliding',
      'roulette',
      'عجلات',
      'entrematique',
      'انتراميتيك',
    ].any(name.contains);
    if (isExplicitSliding) return AccessoryDrawingMode.sliding;

    final hasSlidingSash = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    // All hinge rows and unqualified espagnolettes/window handles belong to
    // opening sashes.  Sliding alternatives carry an explicit sliding label.
    final isOpeningHardware = [
      'مفاصل',
      'hinges',
      'mifsal',
      'paumelle',
      'إسبانيوليت',
      'اسبانيوليت',
      'espagnolette',
      'مقبض نافذة',
      'المقبض (handle)',
      'poignée fenêtre',
      'poignee fenetre',
    ].any(name.contains);
    if (isOpeningHardware && (hasOpeningSash || !hasSlidingSash)) {
      return AccessoryDrawingMode.opening;
    }
    if (hasSlidingSash && !hasOpeningSash) {
      return AccessoryDrawingMode.sliding;
    }
    if (hasOpeningSash && !hasSlidingSash) {
      return AccessoryDrawingMode.opening;
    }
    return null;
  }

  String _materialTypeForItem(BomItem item) {
    final explicitMaterial = (item.materialType ?? '').toLowerCase().trim();
    if (explicitMaterial == 'pvc') return 'PVC';
    if (explicitMaterial == 'aluminium' ||
        explicitMaterial == 'aluminum' ||
        explicitMaterial == 'alu') {
      return 'Aluminium';
    }
    if (explicitMaterial == 'shutter') return 'Shutter';
    return _accessoryDrawingModeForItem(item) == AccessoryDrawingMode.sliding
        ? (widget.model.isSlidingPVC ? 'PVC' : 'Aluminium')
        : (widget.model.isPVC ? 'PVC' : 'Aluminium');
  }

  bool _containsAny(String value, Iterable<String> tokens) {
    final lower = value.toLowerCase();
    return tokens.any((token) => lower.contains(token.toLowerCase()));
  }

  bool _isScrewBomName(String name) {
    final lower = name.toLowerCase();
    return name.contains('براغي') ||
        name.contains('برغي') ||
        lower.contains('screw') ||
        lower.contains('vis');
  }

  bool _matchesDisplayedOverride(String text, Map<String, dynamic>? override) {
    if (override == null) return false;
    var display = '${override['code'] ?? ''} - ${override['name'] ?? ''}'
        .trim();
    if (display.startsWith('- ')) display = display.substring(2);
    return text == display;
  }

  Map<String, dynamic>? _componentOverrideForBom(BomItem item) {
    final primaryKey = item.overrideKey ?? item.originalName;
    final direct = widget.model.componentOverrides[primaryKey];
    if (direct is Map) return Map<String, dynamic>.from(direct);
    final fallback = widget.model.componentOverrides[item.originalName];
    return fallback is Map ? Map<String, dynamic>.from(fallback) : null;
  }

  String _actualRequirementFor(BomItem item, AppLanguage lang) {
    final usedMeters = _actualUsedMetersFor(item);
    if (usedMeters == null || usedMeters <= 0) return '-';

    final barLength = item.length ?? 0.0;
    if (item.category != 'profile' || barLength <= 0) {
      final formatted = usedMeters % 1 == 0
          ? usedMeters.toInt().toString()
          : usedMeters.toStringAsFixed(2);
      return '${formatted}m';
    }

    final exactBars = usedMeters / barLength;
    var fullBars = exactBars.floor();
    var remainingCm = ((usedMeters - (fullBars * barLength)) * 100).round();
    final barLengthCm = (barLength * 100).round();
    if (remainingCm >= barLengthCm) {
      fullBars++;
      remainingCm = 0;
    }

    final barLabel = Localization.translate('بار', lang);
    final cmLabel = Localization.translate('سم', lang);
    final detail = remainingCm > 0
        ? '$fullBars $barLabel + $remainingCm $cmLabel'
        : '$fullBars $barLabel';
    final exactLabel = exactBars
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
    return '$exactLabel $barLabel\n$detail';
  }

  _BomSwapTarget _resolveBomSwapTarget(BomItem item) {
    final original = item.originalName;
    final lower = original.toLowerCase();
    var drawingMode = _accessoryDrawingModeForItem(item);
    final explicitCategory = item.selectorCategory?.trim();
    final explicitType = item.selectorType?.trim();
    if ((explicitCategory != null && explicitCategory.isNotEmpty) ||
        (explicitType != null && explicitType.isNotEmpty)) {
      final type = explicitType == null || explicitType.isEmpty
          ? original
          : explicitType;
      final category = explicitCategory == null || explicitCategory.isEmpty
          ? item.category
          : explicitCategory;
      final isExplicitFrame = category == 'profile' && type == 'frame';
      final isExplicitSash = category == 'profile' && type == 'sash';
      final isExplicitSideCover = category == 'profile' && type == 'side_cover';
      final originalLooksPlinthe =
          lower.contains('plinthe') || lower.contains('بلانت');
      final isExplicitPlinthe =
          category == 'profile' &&
          (originalLooksPlinthe ||
              type.toLowerCase() == 'plant' ||
              type.toLowerCase().contains('plinthe') ||
              type.contains('بلانت'));
      if (isExplicitFrame || isExplicitSash || isExplicitSideCover) {
        drawingMode = _profileDrawingModeForItem(
          item,
          isFrame: isExplicitFrame,
          isSash: isExplicitSash,
          isSideCover: isExplicitSideCover,
        );
      }
      if (isExplicitPlinthe) {
        drawingMode = AccessoryDrawingMode.opening;
      }
      return _BomSwapTarget(
        profileType: isExplicitPlinthe ? 'plant' : type,
        category: category,
        drawingMode: drawingMode,
        isFrame: isExplicitFrame,
        isSash: isExplicitSash,
        isSideCover: isExplicitSideCover,
        seriesId: _seriesIdForItem(item),
        overrideKey: isExplicitPlinthe
            ? 'بلانت (Plinthe)'
            : item.overrideKey ?? original,
      );
    }

    final isFrame =
        original == 'الإطار (Frame)' ||
        original == 'الإطار (Cadre)' ||
        _matchesDisplayedOverride(original, widget.model.frameOverride) ||
        _matchesDisplayedOverride(original, widget.model.slidingFrameOverride);
    if (isFrame) {
      drawingMode = _profileDrawingModeForItem(item, isFrame: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isFrame: true,
      );
      return _BomSwapTarget(
        profileType: 'frame',
        category: 'profile',
        drawingMode: drawingMode,
        isFrame: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    final isSash =
        original == 'الظلفة (Sash)' ||
        original == 'الظلفة المنزلقة (Sliding Sash)' ||
        lower.contains('sliding sash') ||
        _matchesDisplayedOverride(original, widget.model.sashOverride) ||
        _matchesDisplayedOverride(original, widget.model.slidingSashOverride);
    if (isSash) {
      drawingMode = _profileDrawingModeForItem(item, isSash: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isSash: true,
      );
      return _BomSwapTarget(
        profileType: 'sash',
        category: 'profile',
        drawingMode: drawingMode,
        isSash: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    final isSideCover =
        original == 'الغطاء الجانبي (Side Cover)' ||
        _matchesDisplayedOverride(original, widget.model.sideCoverOverride);
    if (isSideCover) {
      drawingMode = _profileDrawingModeForItem(item, isSideCover: true);
      final selectedMap = _selectedProfileMapForTarget(
        item,
        drawingMode,
        isSideCover: true,
      );
      return _BomSwapTarget(
        profileType: 'side_cover',
        category: 'profile',
        drawingMode: drawingMode,
        isSideCover: true,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    if (_containsAny(original, const ['جوان', 'joint'])) {
      final isShutterJoint = _containsAny(original.toLowerCase(), const [
        'للستار',
        'shutter',
        'volet',
      ]);
      final explicitJointRole = item.roleKey?.trim();
      return _BomSwapTarget(
        profileType: explicitJointRole != null && explicitJointRole.isNotEmpty
            ? explicitJointRole
            : isShutterJoint
            ? 'Joint bross shutter'
            : _containsAny(original, const ['بروس', 'bross'])
            ? 'Joint bross'
            : original,
        category: 'joint',
        drawingMode: drawingMode,
        seriesId: isShutterJoint ? null : item.sourceSeriesId,
      );
    }

    if (_containsAny(original, const [
      'clamp',
      'clam',
      'كلامب',
      'كلام',
      'كلان',
    ])) {
      return _BomSwapTarget(
        profileType: 'clamp',
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (original.contains('براغي')) {
      final type = switch (original) {
        final s when s.contains('براغي حديد الدعم') => 'is_renfort_screw',
        final s when s.contains('براغي بوشون باتمو') =>
          'is_bouchon_batmo_screw',
        final s when s.contains('براغي الباتمو') => 'is_batmo_screw',
        final s when s.contains('براغي الكيت') => 'is_kit_screw',
        final s when s.contains('براغي المانيفال') => 'is_manivelle_screw',
        final s when s.contains('براغي المحرك') => 'is_moteur_screw',
        final s when s.contains('براغي الصندوق') => 'is_caisson_screw',
        final s when s.contains('براغي التجميع') => 'is_assembly_screw',
        final s when s.contains('براغي التركيب') => 'is_installation_screw',
        final s when s.contains('براغي الإكسسوارات') => 'is_accessory_screw',
        _ => 'is_accessory_screw',
      };
      return _BomSwapTarget(
        profileType: type,
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (item.category == 'accessory' || item.category == 'other') {
      var type = original;
      if (_containsAny(original, const ['قاش دوبل', 'Gache Double'])) {
        type = 'is_gache_double';
      } else if (_containsAny(original, const ['قاش سامبل', 'Gache Simple'])) {
        type = 'is_gache_simple';
      } else if (_containsAny(original, const [
        'قاش بورت',
        'Gache Porte',
        'Gâche Porte',
      ])) {
        type = 'is_gache_porte';
      } else if (_containsAny(original, const [
        'كاش كوليسون',
        'gache coulisse',
        'gâche coulisse',
        'gache coulissant',
        'gâche coulissant',
      ])) {
        type = 'كاش كوليسون';
      } else if (_containsAny(original, const [
        'poignée coulissante',
        'poignee coulissante',
        'مقبض منزلق',
      ])) {
        type = 'poignee coulissante';
      } else if (original.contains('مقبض الباب (Poignée Porte à Clé)')) {
        type = 'is_poign_clef';
      } else if (original.contains('مقبض الباب Condamnation')) {
        type = 'is_poign_condamnation';
      } else if (_containsAny(original, const ['الأسطوانة', 'Canon'])) {
        type = 'is_canon';
      } else if (_containsAny(original, const ['قفل بمفتاح', 'Clef'])) {
        type = 'is_lock_clef';
      } else if (_containsAny(original, const [
        'Serrure Condamnation',
        'قفل الباب Condamnation',
        'Condamnation',
      ])) {
        type = 'is_lock_condamnation';
      } else if (_containsAny(original, const ['قفل الباب', 'Serrure'])) {
        type = 'is_lock_clef';
      } else if (_containsAny(original, const ['اسبانيوليت', 'إسبانيوليت'])) {
        type = 'اسبانيوليت';
      } else if (_containsAny(original, const ['مفاصل', 'Hinges'])) {
        type = 'مفاصل';
      } else if (_containsAny(original, const ['فيرو', 'Verrou']) &&
          !original.contains('Central')) {
        type = 'فيرو';
      } else if (_containsAny(original, const [
        'تراينغل',
        'تريانغل',
        'Tringle',
        'Tangle',
        'Triangle',
      ])) {
        type = 'tringle';
      } else if (_containsAny(original, const ['كيت', 'kit'])) {
        type = 'kit';
        drawingMode ??= AccessoryDrawingMode.sliding;
      } else if (_containsAny(original, const ['encastr', 'Encastr', 'مدمج'])) {
        type = 'poignee_encastree';
      } else if (_containsAny(original, const [
        'المقبض (Handle)',
        'مقبض نافذة',
        'poignée fenêtre',
        'poignee fenetre',
      ])) {
        type = 'is_window_handle';
      } else if (_containsAny(original, const ['مقبض', 'Handle', 'Poignée'])) {
        type = 'مقبض';
      } else if (_containsAny(original, const ['الطاسو', 'tasso'])) {
        type = 'tasso';
      } else if (_containsAny(original, const ['عجلات', 'roulette'])) {
        type = 'roulette';
      } else if (_containsAny(original, const [
        'أونتروماتيك',
        'Entrematique',
        'انتراميتيك',
        'intra',
      ])) {
        type = 'entrematique';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'accessory',
        drawingMode: drawingMode,
      );
    }

    if (item.category == 'profile') {
      var type = original;
      final selectedMap = _selectedProfileMapForTarget(item, drawingMode);
      if (_containsAny(original, const [
        'renfort',
        'renfore',
        'الدعم',
        'حديد',
      ])) {
        type = 'renfort';
      } else if (_containsAny(original, const [
        'sash traverse',
        'سكة الظلفة',
        'traverse haut',
        'traverse bas',
      ])) {
        type = 'sash_traverse';
      } else if (_containsAny(original, const ['traverse', 'التقسيم'])) {
        type = 'mullion';
      } else if (_containsAny(original, const ['bouchon', 'بوشون', 'bochon'])) {
        type = 'bouchon batmo';
      } else if (_containsAny(original, const ['batmo', 'باتمو'])) {
        type = 'batmo';
      } else if (_containsAny(original, const [
        'reducteur',
        'réducteur',
        'ريديكتور',
        'مخفض',
      ])) {
        type = '67114';
      } else if (_containsAny(original, const [
        'parclose',
        'باكيت',
        'بيركلوز',
      ])) {
        type = 'parclose';
      } else if (_containsAny(original, const ['rail', 'الري', 'سكة'])) {
        type = 'rail';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'profile',
        drawingMode: drawingMode,
        seriesId:
            _catalogSeriesId(selectedMap) ??
            (drawingMode == AccessoryDrawingMode.sliding
                ? widget.model.activeSlidingSeries?.id
                : widget.model.activeSeries?.id),
      );
    }

    if (item.category == 'shutter') {
      var type = original;
      if (_containsAny(original, const ['مانيفال', 'manivelle'])) {
        type = 'مانيفال';
      } else if (_containsAny(original, const ['محرك', 'moteur'])) {
        type = 'محرك';
      } else if (_containsAny(original, const ['صندوق', 'caisson'])) {
        type = 'صندوق';
      } else if (_containsAny(original, const ['كيت', 'kit'])) {
        type = 'كيت';
      } else if (_containsAny(original, const ['سكك', 'coulisse'])) {
        type = 'سكك';
      } else if (_containsAny(original, const [
        'lame finale',
        'النهائية',
        'نهائية',
      ])) {
        type = 'شريحة نهائية';
      } else if (_containsAny(original, const ['شرائح', 'lame'])) {
        type = 'شريحة';
      } else if (_containsAny(original, const ['محور', 'axe'])) {
        type = 'محور';
      } else if (_containsAny(original, const ['أطاش', 'attache'])) {
        type = 'أطاش';
      } else if (_containsAny(original, const [
        'سيبور موتور',
        'support_moteur',
        'support moteur',
      ])) {
        type = 'سيبور موتور';
      } else if (_containsAny(original, const ['الامبو', 'embout'])) {
        type = 'الامبو';
      } else if (_containsAny(original, const [
        'سيبور رولمو',
        'support_roulement',
        'support roulement',
      ])) {
        type = 'سيبور رولمو';
      } else if (_containsAny(original, const [
        'أغطية الشفرات',
        'bouchons lames',
        'bouchon lame',
      ])) {
        type = 'أغطية الشفرات';
      }
      return _BomSwapTarget(
        profileType: type,
        category: 'shutter',
        drawingMode: drawingMode,
      );
    }

    return _BomSwapTarget(
      profileType: original,
      category: item.category,
      drawingMode: drawingMode,
    );
  }

  bool _swapSelectionNeedsDefaultRefresh(BomItem item, _BomSwapTarget target) {
    if (target.category != 'shutter') return false;
    return _containsAny(item.originalName, const [
      'الشرائح',
      'Lames',
      'السكك',
      'Coulisses',
      'الشريحة النهائية',
      'Lame Finale',
      'المحرك',
      'Moteur',
      'الصندوق',
      'Caisson',
      'كيت',
      'Kit',
    ]);
  }

  int? _seriesIdForSwapTarget(BomItem item, _BomSwapTarget target) {
    if (target.drawingMode == AccessoryDrawingMode.sliding) {
      return widget.model.activeSlidingSeries?.id ??
          widget.model.activeSeries?.id ??
          target.seriesId;
    }
    if (target.drawingMode == AccessoryDrawingMode.opening) {
      return widget.model.activeSeries?.id ?? target.seriesId;
    }
    final activeSeriesId = widget.model.systemMode == 'sliding'
        ? widget.model.activeSlidingSeries?.id
        : widget.model.activeSeries?.id;
    return activeSeriesId ?? target.seriesId ?? _seriesIdForItem(item);
  }

  String _materialTypeForSwapTarget(BomItem item, _BomSwapTarget target) {
    if (target.drawingMode == AccessoryDrawingMode.sliding) {
      return widget.model.isSlidingPVC ? 'PVC' : 'Aluminium';
    }
    if (target.drawingMode == AccessoryDrawingMode.opening) {
      return widget.model.isPVC ? 'PVC' : 'Aluminium';
    }
    return _materialTypeForItem(item);
  }

  bool _overrideLooksResolved(Object? value) {
    if (value is! Map) return false;
    final rawId = value['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse('${rawId ?? ''}'.trim()) ?? 0;
    if (id > 0) return true;
    return '${value['code'] ?? ''}'.trim().isNotEmpty ||
        '${value['name'] ?? ''}'.trim().isNotEmpty;
  }

  bool _bomItemHasResolvedSelection(BomItem item) {
    final catalogId = item.catalogItemId ?? 0;
    if (catalogId > 0) return true;

    final target = _resolveBomSwapTarget(item);
    if (target.isFrame) {
      if (target.drawingMode == AccessoryDrawingMode.sliding) {
        return _overrideLooksResolved(widget.model.slidingFrameOverride);
      }
      if (target.drawingMode == AccessoryDrawingMode.opening) {
        return _overrideLooksResolved(widget.model.frameOverride);
      }
      return _overrideLooksResolved(widget.model.frameOverride) ||
          _overrideLooksResolved(widget.model.slidingFrameOverride);
    }

    if (target.isSash) {
      if (target.drawingMode == AccessoryDrawingMode.sliding) {
        return _overrideLooksResolved(widget.model.slidingSashOverride);
      }
      if (target.drawingMode == AccessoryDrawingMode.opening) {
        return _overrideLooksResolved(widget.model.sashOverride);
      }
      return _overrideLooksResolved(widget.model.sashOverride) ||
          _overrideLooksResolved(widget.model.slidingSashOverride);
    }

    if (target.isSideCover) {
      return _overrideLooksResolved(widget.model.sideCoverOverride);
    }

    if (_overrideLooksResolved(_componentOverrideForBom(item))) {
      return true;
    }

    if (item.originalName.contains('قائم جانبي') ||
        item.originalName.contains('Sash Lateral')) {
      return _overrideLooksResolved(
            widget.model.componentOverrides['قائم جانبي (Sash Lateral)'],
          ) ||
          _overrideLooksResolved(
            widget
                .model
                .componentOverrides['قائم جانبي معزز (Sash Lateral Renforcé)'],
          ) ||
          _overrideLooksResolved(
            widget.model.componentOverrides['قائم جانبي (Lateral)'],
          );
    }

    if (item.originalName.contains('قائم وسطي') ||
        item.originalName.contains('Sash Central')) {
      return _overrideLooksResolved(
            widget.model.componentOverrides['قائم وسطي (Sash Central)'],
          ) ||
          _overrideLooksResolved(
            widget
                .model
                .componentOverrides['قائم وسطي معزز (Sash Central Renforcé)'],
          ) ||
          _overrideLooksResolved(
            widget.model.componentOverrides['قائم وسطي (Central)'],
          );
    }

    return false;
  }

  int? _selectedAccessoryColorId() {
    final rawId = widget.model.selectedAccessoryColor?['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  List<BomItem> _generateRawBomItems() {
    return ComponentCalculator.generateBom(
      widget.model,
      activeVariants,
      kitBundleData: _kitBundleData,
      kitPerLeafMap: _kitPerLeafMap,
      kitBundlePrices: _kitBundlePrices,
      kitBundleMetadata: _kitBundleMetadata,
    );
  }

  /// Safe local fallback while the catalogue database is opening. Catalogue
  /// products are intentionally withheld until their active-series rule has
  /// been verified; only non-catalogue calculated materials may appear here.
  List<BomItem> _resolvedFallbackBomItems(Iterable<BomItem> items) {
    return items
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          if (!item.isActive || (!hasPieces && qty <= 0)) return false;
          final category = item.selectorCategory ?? item.category;
          final requiresCatalogueIdentity = const {
            'profile',
            'accessory',
            'other',
            'joint',
          }.contains(category);
          return !requiresCatalogueIdentity;
        })
        .toList(growable: false);
  }

  Future<List<BomItem>> _generateStrictVisibleBomItems(
    BomEngineV2 engine,
  ) async {
    final rawItems = _generateRawBomItems();
    final items = await engine.filterItemsByAvailableCandidates(
      window: widget.model,
      items: rawItems,
    );
    return items
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          return hasPieces || qty > 0;
        })
        .toList(growable: false);
  }

  Future<void> _refreshVisibleBomItems() async {
    if (_isRefreshingVisibleBom || _isFetchingDefaults) return;
    _isRefreshingVisibleBom = true;
    try {
      final refreshGeneration = ++_bomRefreshGeneration;
      final engine = BomEngineV2(database: SqlDatabase());
      // Revalidate saved selections whenever the window/series changes. Without
      // this pass, a selection resolved for the previous series could remain
      // visible until the screen was recreated.
      final rawBomItems = _generateRawBomItems();
      var visibleBomItems = _resolvedFallbackBomItems(rawBomItems);
      try {
        await engine.stabilizeSelections(
          window: widget.model,
          items: rawBomItems,
        );
        final dbReady = await SqlDatabase().db != null;
        if (dbReady) {
          final strictItems = await _generateStrictVisibleBomItems(engine);
          if (strictItems.isNotEmpty || visibleBomItems.isEmpty) {
            visibleBomItems = strictItems;
          }
        }
      } catch (error, stackTrace) {
        // Keep resolved rows visible without restoring unlinked placeholders.
        visibleBomItems = _resolvedFallbackBomItems(_generateRawBomItems());
        debugPrint(
          'Material BOM refresh failed; showing resolved rows: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      final refreshedStock = await _loadMainWarehouseStock();
      if (!mounted || refreshGeneration != _bomRefreshGeneration) return;
      final stockChanged =
          refreshedStock.length != _mainWarehouseStock.length ||
          refreshedStock.entries.any(
            (e) => _mainWarehouseStock[e.key] != e.value,
          );
      if (stockChanged ||
          _bomItemsSignature(_visibleBomItems) !=
              _bomItemsSignature(visibleBomItems)) {
        _setScreenState(() {
          _mainWarehouseStock = refreshedStock;
          _visibleBomItems = visibleBomItems;
        });
      }
    } finally {
      _isRefreshingVisibleBom = false;
    }
  }

  void _updateRequestedQuantity(int quantity) {
    if (quantity <= 0 || quantity == widget.model.quantity) return;

    // Rebuild immediately so the quantity/cost rows and totals react in the
    // same frame as the Parameters field. The async refresh below then
    // reapplies strict catalogue selections, purchase prices and stock data.
    widget.model.quantity = quantity;
    final immediateItems = _resolvedFallbackBomItems(_generateRawBomItems());
    _setScreenState(() {
      _visibleBomItems = immediateItems;
    });

    _scheduleQuantityRefresh();
  }

  void _scheduleQuantityRefresh() {
    _modelRefreshDebounce?.cancel();
    _modelRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (_isRefreshingVisibleBom || _isFetchingDefaults) {
        _scheduleQuantityRefresh();
        return;
      }
      unawaited(_refreshVisibleBomItems());
    });
  }

  String _bomItemsSignature(Iterable<BomItem> items) => items
      .map(
        (item) => [
          item.catalogItemId,
          item.originalName,
          item.name,
          item.category,
          item.colorId,
          item.quantity,
          item.unitPrice,
          item.isActive,
        ].join('|'),
      )
      .join('||');

  void _setFetchProgress(double value) {
    if (!mounted || !_isFetchingDefaults) return;
    _setScreenState(() => _fetchProgress = value.clamp(0.0, 1.0).toDouble());
  }

  Future<void> _fetchDefaults() async {
    if (_isFetchingDefaults) return;
    // Catalogue restoration runs asynchronously when an order is reopened.
    // Remember its current series so a fetch that started before restoration
    // can transparently repeat once the real drawing series is available.
    final seriesIdAtFetchStart =
        widget.model.activeFrameSeries?.id ??
        widget.model.effectiveSlidingSeries?.id ??
        widget.model.activeSeries?.id;
    if (mounted) {
      _setScreenState(() {
        _isFetchingDefaults = true;
        _fetchProgress = 0.20;
      });
    }
    _accessoryPriceCache.clear();
    // Never publish the preliminary/raw BOM. The table is published only
    // after defaults, catalogue links and the strict visibility check finish.
    var visibleBomItems = const <BomItem>[];
    var mustRepeatForRestoredSeries = false;
    try {
      final sqlDb = SqlDatabase();

      // Run prerequisites sequentially with timeouts to avoid database lock contention.
      try {
        await widget.model.loadGlassProducts().timeout(
          const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint('loadGlassProducts error/timeout: $e');
      }
      _setFetchProgress(0.30);

      try {
        await widget.model.updateShutterDefaultsIfNeeded().timeout(
          const Duration(seconds: 4),
        );
      } catch (e) {
        debugPrint('updateShutterDefaultsIfNeeded error/timeout: $e');
      }
      _setFetchProgress(0.40);

      try {
        await _loadPricesFromDb().timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('_loadPricesFromDb error/timeout: $e');
      }
      _setFetchProgress(0.50);

      _refreshStrictActiveVariants();
      if (!widget.model.hasSimpleGlassForReducer ||
          widget.model.hasDoubleGlassForRules) {
        widget.model.clearReducerOverride();
      }

      final dbInstance = await sqlDb.db;
      if (dbInstance != null) {
        try {
          await _loadStrictKitBundles(
            dbInstance,
            sqlDb,
          ).timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('_loadStrictKitBundles error/timeout: $e');
        }
        _setFetchProgress(0.65);

        try {
          final stock = await _loadMainWarehouseStock().timeout(
            const Duration(seconds: 4),
          );
          if (mounted) _setScreenState(() => _mainWarehouseStock = stock);
        } catch (e) {
          debugPrint('_loadMainWarehouseStock error/timeout: $e');
        }
      }
      _setFetchProgress(0.75);

      final engine = BomEngineV2(database: sqlDb);
      var bomItems = _generateRawBomItems();
      try {
        await engine
            .stabilizeSelections(window: widget.model, items: bomItems)
            .timeout(const Duration(seconds: 4));
        // Stabilization can select catalogue components. Rebuild and run one
        // more pass so quick "Ajouter" and the manually opened quantity table
        // price the exact same final BOM rather than two successive states.
        bomItems = _generateRawBomItems();
        await engine
            .stabilizeSelections(window: widget.model, items: bomItems)
            .timeout(const Duration(seconds: 4));
        bomItems = _generateRawBomItems();
      } catch (e) {
        debugPrint('stabilizeSelections error/timeout: $e');
      }

      if (dbInstance == null) {
        visibleBomItems = _resolvedFallbackBomItems(bomItems);
      } else {
        try {
          final strictItems = await _generateStrictVisibleBomItems(
            engine,
          ).timeout(const Duration(seconds: 5));
          final resolvedItems = _resolvedFallbackBomItems(bomItems);
          visibleBomItems = strictItems.isEmpty && resolvedItems.isNotEmpty
              ? resolvedItems
              : strictItems;
        } catch (e) {
          debugPrint('_generateStrictVisibleBomItems error/timeout: $e');
          visibleBomItems = _resolvedFallbackBomItems(bomItems);
        }
      }
      _setFetchProgress(0.95);
    } catch (error, stackTrace) {
      // A later pricing failure must not erase additive rule rows (Clam,
      // assembly screws, kits) already calculated successfully above.
      if (visibleBomItems.isEmpty) {
        visibleBomItems = _resolvedFallbackBomItems(_generateRawBomItems());
      }
      debugPrint(
        'Material defaults load failed; showing resolved rows: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        _setScreenState(() {
          _visibleBomItems = visibleBomItems;
          _fetchProgress = 1.0;
          _isFetchingDefaults = false;
          _hasFetchedDefaults = true;
        });
      }
      final seriesIdAfterFetch =
          widget.model.activeFrameSeries?.id ??
          widget.model.effectiveSlidingSeries?.id ??
          widget.model.activeSeries?.id;
      if (seriesIdAfterFetch != null &&
          seriesIdAfterFetch != seriesIdAtFetchStart &&
          !_hasRepeatedForRestoredSeries) {
        _hasRepeatedForRestoredSeries = true;
        mustRepeatForRestoredSeries = true;
        unawaited(_fetchDefaults());
      }
      if (_pricePerLinearMeterFromDb == 0 ||
          (widget.model.hasShutter && _shutterSqmPriceFromDb == 0) ||
          (widget.model.hasMoustiquaireAddon &&
              _moustiquaireSqmPriceFromDb <= 0)) {
        _scheduleInitialPriceRetries();
      }
    }
    if (widget.autoCalculateAndSave &&
        !mustRepeatForRestoredSeries &&
        !_automaticCompletionStarted &&
        mounted) {
      // The manual table remains open long enough for its price retry to
      // finish. The quick Ajouter path must not save an earlier zero/default
      // tariff, otherwise both buttons calculate the same BOM differently.
      if (_pricePerLinearMeterFromDb == 0 ||
          (widget.model.hasShutter && _shutterSqmPriceFromDb == 0) ||
          (widget.model.hasMoustiquaireAddon &&
              _moustiquaireSqmPriceFromDb <= 0)) {
        try {
          await _loadPricesFromDb().timeout(const Duration(seconds: 8));
        } catch (e) {
          debugPrint('Final automatic price load error/timeout: $e');
        }
      }
      _automaticCompletionStarted = true;
      final pricedItems = _visibleBomItems
          .where((item) {
            final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
            final qty = item.requiredQuantity > 0
                ? item.requiredQuantity
                : item.quantity;
            return hasPieces || qty > 0;
          })
          .toList(growable: false);
      final totals = _calculateTotals(pricedItems);
      final sellingPrice = totals['total']?['selling'] ?? 0.0;
      final quantity = math.max(1, widget.model.quantity);
      final unitPrice = sellingPrice / quantity;
      if (unitPrice.isFinite && unitPrice > 0) {
        widget.model.totalCost = unitPrice;
        widget.model.manualPriceOverride = unitPrice;
        Navigator.pop(context, true);
      } else {
        _automaticCompletionStarted = false;
        Navigator.pop(context, false);
      }
    }
  }

  Widget _buildFetchProgress(AppLanguage lang) {
    final progress = _fetchProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  value: progress < 1 ? null : 1,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  Localization.translate(
                    'جاري تجهيز الكميات والأسعار...',
                    lang,
                  ),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$percent%',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.14),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshFromDatabaseUpdate() async {
    // Synced catalogue/price rows may change the kit options.
    _shutterKitOptionsFuture = null;
    final newStock = await _loadMainWarehouseStock();
    if (mounted) {
      _setScreenState(() => _mainWarehouseStock = newStock);
      await _refreshVisibleBomItems();
    }
  }

  // دالة تُستدعى عند تغيّر النموذج من خارج هذه الشاشة، فقط تعيد بناء الواجهة
  void _onModelChanged() {
    if (_isFetchingDefaults || _isRefreshingVisibleBom) return;
    final priceContext = _priceContextSignature();
    if (priceContext != _lastPriceContextSignature) {
      _lastPriceContextSignature = priceContext;
      // Model restoration may assign the actual BS90/shutter data after this
      // screen has already started its first query. Reload just the dynamic
      // prices for that new context immediately.
      unawaited(_loadPricesFromDb());
    }
    final rawColorId = widget.model.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse('${rawColorId ?? ''}');
    final colorChanged = colorId != _lastBomColorId;
    _lastBomColorId = colorId;
    // Catalogue stabilization mutates resolved selections and notifies the
    // model. Ignore those internal notifications; treating them as a fresh
    // user edit created a self-sustaining refresh loop.
    if (_isFetchingDefaults || _isRefreshingVisibleBom) return;
    _modelRefreshDebounce?.cancel();
    if (colorChanged && _hasFetchedDefaults && !_isFetchingDefaults) {
      // A colour changes section prices, shutter colour prices and accessory
      // prices; refreshing only the existing rows leaves stale/empty totals.
      unawaited(_fetchDefaults());
      return;
    }
    if (_hasFetchedDefaults) {
      _modelRefreshDebounce = Timer(const Duration(milliseconds: 180), () {
        if (mounted) unawaited(_refreshVisibleBomItems());
      });
    }
  }

  // ==========================================================================
  // build: الدالة الرئيسية لبناء واجهة الشاشة كاملة
  // ==========================================================================
  /// Catalogue reads that failed while resolving this drawing: some prices
  /// or components below may be defaults rather than catalogue values.
  Widget _buildCatalogIssuesWarning(AppLanguage lang) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, color: Colors.orange.shade800, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${Localization.translate('تعذرت قراءة بعض بيانات الكتالوج؛ قد تكون بعض الأسعار أو المكونات ناقصة', lang)}: ${widget.model.catalogIssues.join('، ')}',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A profile kept from another series (for example BS 90 in a PVC
  /// drawing) makes every quantity and cost below unreliable.
  Widget _buildForeignSeriesWarning(AppLanguage lang, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${Localization.translate('يحتوي الرسم على مقاطع من سلسلة أخرى؛ الكميات والتكلفة غير موثوقة', lang)} ($count)',
              style: TextStyle(
                color: Colors.red.shade900,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: Text(
              Localization.translate('إزالة المقاطع غير المتوافقة', lang),
            ),
            onPressed: () async {
              widget.model.removeOverridesFromForeignSeries();
              await _fetchDefaults();
              if (mounted) _setScreenState(() {});
            },
          ),
        ],
      ),
    );
  }

  Future<int?> _showQuantityDialog(BuildContext context, int currentQty) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final controller = TextEditingController(text: '$currentQty');
    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(Localization.translate('تعديل كمية النوافذ', lang)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: Localization.translate('الكمية المطلوبة', lang),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () {
                final int? val = int.tryParse(controller.text);
                if (val != null && val > 0) {
                  Navigator.pop(dialogContext, val);
                }
              },
              child: Text(Localization.translate('تأكيد', lang)),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================================
  // دالة: _showSwapDialog ⭐ (دالة ضخمة ومعقدة)
  // الغرض: عند الضغط على زر التبديل بجانب أي عنصر، تفتح نافذة اختيار بديل
  // (ProfileSelectorDialog) بالنوع المناسب، وبعد الاختيار تُحدّث النموذج مع
  // كل "المكونات المرافقة" (companion components) التي يجب أن تتغيّر معها
  // تلقائيًا (مثل: تغيير الشريحة يستدعي تغيير المحور، الأطاش، السيبورات...).
  // ==========================================================================
  void _showParcloseCutModeDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: AnimatedBuilder(
          animation: widget.model,
          builder: (_, __) => ParcloseCutModeSelector(model: widget.model),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_lang == 'ar' ? 'إغلاق' : 'Fermer'),
          ),
        ],
      ),
    );
  }

  void _showSwapDialog(BomItem item) async {
    final swapTarget = _resolveBomSwapTarget(item);
    String pType = swapTarget.profileType;
    String pCategory = swapTarget.category;
    final explicitRoleKey = (item.roleKey ?? '').trim();
    final explicitSelectorType = (item.selectorType ?? '').trim();
    final usesExplicitCatalogSelector =
        pCategory != 'shutter' &&
        (explicitRoleKey.isNotEmpty || explicitSelectorType.isNotEmpty);
    final rowLooksPlinthe =
        item.originalName.toLowerCase().contains('plinthe') ||
        item.originalName.contains('بلانت') ||
        pType.toLowerCase().contains('plinthe') ||
        pType.contains('بلانت');
    final rowRoleText =
        '${item.originalName} ${item.roleKey ?? ''} ${item.selectorType ?? ''}'
            .toLowerCase();
    final isSlidingLateralRow = explicitRoleKey.isNotEmpty
        ? explicitRoleKey.startsWith('sash_lateral') ||
              explicitRoleKey == 'lateral'
        : rowRoleText.contains('sash_lateral') ||
              rowRoleText.contains('sash lateral') ||
              rowRoleText.contains('قائم جانبي');
    final isSlidingCentralRow = explicitRoleKey.isNotEmpty
        ? explicitRoleKey.startsWith('sash_central') ||
              explicitRoleKey == 'central'
        : rowRoleText.contains('sash_central') ||
              rowRoleText.contains('sash central') ||
              rowRoleText.contains('قائم وسطي');
    final isSlidingSlimRow =
        explicitRoleKey == 'montant_central_slim' ||
        explicitRoleKey == 'sash_central_slim' ||
        explicitSelectorType == 'montant_central_slim' ||
        rowRoleText.contains('montant slim') ||
        rowRoleText.contains('montant_central_slim') ||
        rowRoleText.contains('مونتوسليم') ||
        rowRoleText.contains('قائم وسطي سليم');
    final isSlidingSlimComplementRow =
        explicitRoleKey == 'complement_haut_base' ||
        explicitSelectorType == 'complement_haut_base' ||
        rowRoleText.contains('complement_haut_base') ||
        rowRoleText.contains('complément haut') ||
        rowRoleText.contains('complement haut') ||
        rowRoleText.contains('مكمل علوي') ||
        rowRoleText.contains('taquet slim');
    // A montant can be changed in both directions. Restricting a reinforced
    // row to the reinforced role made the regular profile disappear from the
    // selector, so the user could never switch it back to normal.
    final dialogRoleKeys = rowLooksPlinthe
        ? const <String>['plant']
        // A complement name can include "Slim", but it is a different
        // profile role. It must win over the Slim montant test so its change
        // dialog never lists central-montant candidates.
        : isSlidingSlimComplementRow
        ? const <String>['complement_haut_base']
        : isSlidingSlimRow
        // Some existing series were saved under the original alias
        // `sash_central_slim`; both names represent the same selectable Slim
        // montant and must therefore resolve in the replacement dialog.
        ? const <String>['montant_central_slim', 'sash_central_slim']
        : isSlidingLateralRow
        ? const <String>['sash_lateral', 'sash_lateral_reinforced']
        : isSlidingCentralRow
        ? const <String>['sash_central', 'sash_central_reinforced']
        : explicitRoleKey.isEmpty
        ? const <String>[]
        : <String>[explicitRoleKey];
    final espagnoletteLengthMatch = RegExp(
      r'(\d+(?:[.,]\d+)?)',
    ).firstMatch(item.originalName);
    final double? maxEspagnoletteLength = espagnoletteLengthMatch == null
        ? null
        : double.tryParse(
            espagnoletteLengthMatch.group(1)!.replaceAll(',', '.'),
          );
    bool isFrameClicked = swapTarget.isFrame;
    bool isSashClicked = swapTarget.isSash;
    bool isSideCoverClicked = swapTarget.isSideCover;
    // ---- التعرف على الإطار: إما بالاسم الثابت أو بمطابقة الاسم المعروض الحالي ----
    if (pType == 'الإطار (Frame)' || pType == 'الإطار (Cadre)') {
      isFrameClicked = true;
    } else if (widget.model.frameOverride != null) {
      String frameDisplay =
          '${widget.model.frameOverride!['code'] ?? ''} - ${widget.model.frameOverride!['name']}'
              .trim();
      if (frameDisplay.startsWith('- ')) {
        frameDisplay = frameDisplay.substring(
          2,
        ); // إزالة "- " إذا لم يكن هناك كود
      }
      if (pType == frameDisplay) isFrameClicked = true;
    }
    // ---- نفس المنطق للظلفة ----
    final pTypeLower = pType.toLowerCase();
    if (pType == 'الظلفة (Sash)' ||
        pType == 'الظلفة المنزلقة (Sliding Sash)' ||
        pTypeLower.contains('sliding sash')) {
      isSashClicked = true;
    } else if (widget.model.sashOverride != null) {
      String sashDisplay =
          '${widget.model.sashOverride!['code'] ?? ''} - ${widget.model.sashOverride!['name']}'
              .trim();
      if (sashDisplay.startsWith('- ')) sashDisplay = sashDisplay.substring(2);
      if (pType == sashDisplay) isSashClicked = true;
    }
    if (!isSashClicked && widget.model.slidingSashOverride != null) {
      String sashDisplay =
          '${widget.model.slidingSashOverride!['code'] ?? ''} - ${widget.model.slidingSashOverride!['name']}'
              .trim();
      if (sashDisplay.startsWith('- ')) sashDisplay = sashDisplay.substring(2);
      if (pType == sashDisplay) isSashClicked = true;
    }
    // ---- نفس المنطق للغطاء الجانبي ----
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
    // ===================== حالة: ضغطة زر الإطار =====================
    if (isFrameClicked) {
      final isSlidingFrameSelection =
          swapTarget.drawingMode == AccessoryDrawingMode.sliding ||
          (swapTarget.drawingMode == null &&
              widget.model.usesSlidingPrimaryProfiles);
      // فتح نافذة اختيار بروفيل من نوع "frame" ضمن السلسلة النشطة والمادة الصحيحة (PVC/ألمنيوم)
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'frame',
          category: 'profile',
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          hasShutter: widget.model.hasShutter,
          isCaissonTunnel: widget.model.isCaissonTunnel,
          hasSideCovers: widget.model.hasSideCovers,
          multiFrameDrawing: widget.model.getFrameRects().length > 1,
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
        ),
      );
      if (selected != null && mounted) {
        final rawCId = widget.model.selectedDbColor?['id'];
        final colorId = rawCId is num ? rawCId.toInt() : int.tryParse('${rawCId ?? ''}');
          final db = SqlDatabase();
        final price = await db.getSectionPrice(selected['id'], colorId);
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        _setScreenState(() {
          // تحديث الإطار حسب وضع النظام (منزلق/عادي)
          widget.model.applyFrameOverride(
            mutableSelected,
            sliding: isSlidingFrameSelection,
            manualSelection: true,
          );
          widget.model.refreshUI();
        });
        await widget.model.syncFrameReinforcement();
        await _refreshVisibleBomItems();
      }
      return; // إنهاء الدالة هنا (لا تكمل باقي منطق التبديل العام)
    }
    // ===================== حالة: ضغطة زر الظلفة =====================
    if (isSashClicked) {
      final isSlidingSelection =
          swapTarget.drawingMode == AccessoryDrawingMode.sliding ||
          item.originalName.toLowerCase().contains('sliding sash') ||
          item.originalName.contains('منزلقة');
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'sash',
          category: 'profile',
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
        ),
      );
      if (selected != null && mounted) {
        final rawCId = widget.model.selectedDbColor?['id'];
        final colorId = rawCId is num ? rawCId.toInt() : int.tryParse('${rawCId ?? ''}');
          final db = SqlDatabase();
        final price = await db.getSectionPrice(selected['id'], colorId);
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        // إذا كانت الظلفة الجديدة مرتبطة بحديد دعم، اجلبه + ابحث عن حديد مفصل خاص (Mifsal) كما في _fetchDefaults
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
            // بحث عن حديد المفاصل الخاص ضمن نفس السلسلة
            final mifsalRes = await dbInstance.query(
              'Sections',
              where:
                  'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
              whereArgs: [
                _seriesIdForSwapTarget(item, swapTarget),
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
          // إزالة أي حديد ظلفة قديم إذا الظلفة الجديدة لا تحتاجه
          widget.model.componentOverrides.remove('حديد الظلفة (Renfort Sash)');
          widget.model.componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
        }
        _setScreenState(() {
          widget.model.applySashOverride(
            mutableSelected,
            sliding: isSlidingSelection,
            manualSelection: true,
          );
          widget.model.refreshUI();
        });
        await _refreshVisibleBomItems();
      }
      return;
    }
    // ===================== حالة: ضغطة زر الغطاء الجانبي =====================
    if (isSideCoverClicked) {
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => ProfileSelectorDialog(
          profileType: 'side_cover',
          category: 'profile',
          seriesId: _seriesIdForSwapTarget(item, swapTarget),
          materialType: _materialTypeForSwapTarget(item, swapTarget),
          accessoryDrawingMode: swapTarget.drawingMode,
          roleKeys: dialogRoleKeys,
          hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
          hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
          targetThicknessMm: item.targetThicknessMm,
          mainWarehouseStock: _mainWarehouseStock,
          stockColorId: _itemColorId(item),
        ),
      );
      if (selected != null && mounted) {
        final rawCId = widget.model.selectedDbColor?['id'];
        final colorId = rawCId is num ? rawCId.toInt() : int.tryParse('${rawCId ?? ''}');
          final db = SqlDatabase();
        final price = await db.getSectionPrice(selected['id'], colorId);
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['calculated_price'] = price;
        _setScreenState(() {
          widget.model.sideCoverOverride = mutableSelected;
          widget.model.selectedSideCover = AluminumSection.fromMap(
            mutableSelected,
          );
          widget.model.componentOverrides['الغطاء الجانبي (Side Cover)'] =
              mutableSelected;
          if (item.originalName != 'الغطاء الجانبي (Side Cover)') {
            widget.model.componentOverrides[item.originalName] =
                mutableSelected;
          }
          widget.model.refreshUI();
        });
        await _refreshVisibleBomItems();
      }
      return;
    }
    // ===================== الحالة العامة: تحويل اسم العنصر إلى "نوع بحث" (pType) مناسب =====================
    // كل الحالات التالية تُغيّر pType/pCategory إلى صيغة يفهمها ProfileSelectorDialog للبحث
    // الجوانات (Joints)
    if (!usesExplicitCatalogSelector) {
      if (pType.contains('جوان') || pType.toLowerCase().contains('joint')) {
        pCategory = 'joint';
        if (pType.contains('بروس') || pType.toLowerCase().contains('bross')) {
          pType = ('Joint bross');
        }
      } else if (pType.toLowerCase().contains('clamp') ||
          pType.toLowerCase().contains('clam') ||
          pType.contains('كلامب') ||
          pType.contains('كلام') ||
          pType.contains('كلان')) {
        pCategory = 'accessory';
        pType = 'clamp';
      } else if (pType.contains('براغي')) {
        pCategory = 'accessory';
        if (pType.contains('براغي حديد الدعم')) {
          pType = 'is_renfort_screw';
        } else if (pType.contains('براغي بوشون باتمو')) {
          pType = 'is_bouchon_batmo_screw';
        } else if (pType.contains('براغي الباتمو')) {
          pType = 'is_batmo_screw';
        } else if (pType.contains('براغي الكيت')) {
          pType = 'is_kit_screw';
        } else if (pType.contains('براغي المانيفال')) {
          pType = 'is_manivelle_screw';
        } else if (pType.contains('براغي المحرك')) {
          pType = 'is_moteur_screw';
        } else if (pType.contains('براغي الصندوق')) {
          pType = 'is_caisson_screw';
        } else if (pType.contains('براغي التجميع')) {
          pType = 'is_assembly_screw';
        } else if (pType.contains('براغي التركيب')) {
          pType = 'is_installation_screw';
        } else if (pType.contains('براغي الإكسسوارات')) {
          pType = 'is_accessory_screw';
        }
      } else if (pCategory == 'accessory') {
        if (pType.contains('قاش دوبل') || pType.contains('Gache Double')) {
          pType = 'is_gache_double';
        } else if (pType.contains('قاش سامبل') ||
            pType.contains('Gache Simple')) {
          pType = 'is_gache_simple';
        } else if (pType.contains('قاش بورت') ||
            pType.contains('Gache Porte') ||
            pType.contains('Gâche Porte')) {
          pType = 'is_gache_porte';
        } else if (pType.contains('كاش كوليسون') ||
            pType.toLowerCase().contains('gache coulisse') ||
            pType.toLowerCase().contains('gâche coulisse') ||
            pType.toLowerCase().contains('gache coulissant') ||
            pType.toLowerCase().contains('gâche coulissant')) {
          pType = 'كاش كوليسون';
        } else if (pType.toLowerCase().contains('clamp') ||
            pType.toLowerCase().contains('clam') ||
            pType.contains('كلامب') ||
            pType.contains('كلام') ||
            pType.contains('كلان')) {
          pType = 'clamp';
        } else if (pType.contains('مقبض الباب (Poignée Porte à Clé)')) {
          pType = 'is_poign_clef';
        } else if (pType.contains('مقبض الباب Condamnation')) {
          pType = 'is_poign_condamnation';
        } else if (pType.contains('الأسطوانة') || pType.contains('Canon')) {
          pType = 'is_canon';
        } else if (pType.contains('قفل بمفتاح') || pType.contains('Clef')) {
          pType = 'is_lock_clef';
        } else if (pType.contains('Serrure Condamnation') ||
            pType.contains('قفل الباب Condamnation') ||
            pType.contains('Condamnation')) {
          pType = 'is_lock_condamnation';
        } else if (pType.contains('قفل الباب') || pType.contains('Serrure')) {
          pType = 'is_lock_clef';
        } else if (pType.contains('اسبانيوليت') ||
            pType.contains('إسبانيوليت')) {
          pType = 'اسبانيوليت';
        } else if (pType.contains('مفاصل') || pType.contains('Hinges')) {
          pType = 'مفاصل';
        } else if ((pType.contains('فيرو') || pType.contains('Verrou')) &&
            !pType.contains('Central')) {
          pType = 'فيرو';
        } else if (pType.toLowerCase().contains('poignée coulissante') ||
            pType.toLowerCase().contains('poignee coulissante') ||
            pType.contains('مقبض منزلق')) {
          pType = 'poignee coulissante';
        } else if (pType.toLowerCase().contains('encastr') ||
            pType.contains('مدمج')) {
          pType = 'poignee_encastree';
        } else if (pType.contains('المقبض (Handle)') ||
            pType.contains('مقبض نافذة') ||
            pType.toLowerCase().contains('poignée fenêtre') ||
            pType.toLowerCase().contains('poignee fenetre')) {
          pType = 'is_window_handle';
        } else if (pType.contains('مقبض') ||
            pType.contains('Handle') ||
            pType.contains('Poignée')) {
          pType = 'مقبض';
        } else if (pType.contains('الطاسو') ||
            pType.toLowerCase().contains('tasso')) {
          pType = 'tasso';
        } else if (pType.contains('عجلات') ||
            pType.toLowerCase().contains('roulette')) {
          pType = 'roulette';
        } else if (pType.contains('أونتروماتيك') ||
            pType.contains('Entrematique') ||
            pType.contains('انتراميتيك') ||
            pType.toLowerCase().contains('intra')) {
          pType = 'entrematique';
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
        } else if (pType.toLowerCase().contains('reducteur') ||
            pType.toLowerCase().contains('réducteur') ||
            pType.contains('ريديكتور') ||
            pType.contains('مخفض')) {
          pType = '67114';
        } else if (pType.toLowerCase().contains('parclose') ||
            pType.contains('باكيت') ||
            pType.contains('بيركلوز')) {
          pType = 'parclose';
        } else if (pType.toLowerCase().contains('rail') ||
            pType.contains('الري') ||
            pType.contains('سكة')) {
          pType = 'rail';
        }
      }
    }
    if (pCategory == 'shutter') {
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
    // إذا كانت الشريحة (Lames) مختارة، نمرر معرّفها (bladeId) لنافذة الاختيار لفلترة الخيارات المتوافقة معها
    final bladeObj = widget.model.componentOverrides['الشرائح (Lames)'];
    final int? bladeId = bladeObj != null ? bladeObj['id'] as int? : null;
    final selectedBladeName = bladeObj?['name']?.toString();
    final selectedBladeIsX3d = _isX3dBlade(bladeObj);
    final selectedMotor = widget.model.componentOverrides['المحرك (Moteur)'];
    final motorDiameter = selectedMotor == null
        ? null
        : shutterComponentDiameter(selectedMotor);
    final accessoryDrawingMode = swapTarget.drawingMode;
    final functionalSlidingProfile =
        isSlidingSlimRow || isSlidingSlimComplementRow;
    // فتح نافذة الاختيار العامة بالمعطيات المحسوبة أعلاه
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => ProfileSelectorDialog(
        profileType: pType,
        category: pCategory,
        seriesId: functionalSlidingProfile
            ? (widget.model.activeSlidingSeries?.id ??
                  _seriesIdForSwapTarget(item, swapTarget))
            : _seriesIdForSwapTarget(item, swapTarget),
        materialType: _materialTypeForSwapTarget(item, swapTarget),
        hasShutter: widget.model.hasShutter,
        isCaissonTunnel: widget.model.isCaissonTunnel,
        hasSideCovers: widget.model.hasSideCovers,
        // The explicit role already fixes this to the active sliding series.
        // Do not additionally reject a legacy role row whose old scope field
        // was saved as opening/auto.
        accessoryDrawingMode: functionalSlidingProfile
            ? null
            : accessoryDrawingMode,
        roleKeys: dialogRoleKeys,
        windowHeight: widget.model.height,
        targetSize: widget.model.shutterBoxHeight,
        kitDescriptionCode: pCategory == 'shutter' && pType == 'كيت'
            ? shutterKitCodeForMechanism(widget.model.shutterMechanism)
            : null,
        maxAccessoryLength: pType == 'اسبانيوليت'
            ? maxEspagnoletteLength
            : null,
        bladeId: bladeId,
        selectedBladeName: selectedBladeName,
        selectedBladeIsX3d: selectedBladeIsX3d,
        motorDiameter: motorDiameter,
        hasSimpleGlassForReducer: widget.model.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: widget.model.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
        mainWarehouseStock: _mainWarehouseStock,
        stockColorId: _itemColorId(item),
      ),
    );
    if (selected != null && mounted) {
      try {
        double price = 0.0;
        final db = SqlDatabase();
        // حساب السعر: بروفيل حسب اللون، وإلا السعر العام المباشر.
        // سعر الشراء مُدمج مسبقاً فيه (المتوسط المرجّح عند كل شراء).
        if (pCategory == 'profile') {
          final rawCId = widget.model.selectedDbColor?['id'];
          final colorId = rawCId is num ? rawCId.toInt() : int.tryParse('${rawCId ?? ''}');
          price = await db.getSectionPrice(selected['id'], colorId);
          if (price <= 0) {
            price = _safeDouble(selected['price_dzd'] ?? selected['price']);
          }
        } else if (pCategory == 'accessory') {
          final dbInstance = await db.db;
          price = dbInstance == null
              ? _safeDouble(selected['price_dzd'] ?? selected['price'])
              : await _resolveSelectedAccessoryPrice(dbInstance, selected);
        } else {
          price = _safeDouble(selected['price_dzd'] ?? selected['price']);
        }
        final mutableSelected = Map<String, dynamic>.from(selected);
        mutableSelected['manual_selection'] = true;
        mutableSelected['user_selected'] = true;
        mutableSelected['automatic_selection'] = false;
        if (price > 0) mutableSelected['calculated_price'] = price;
        final isKitItem =
            !_isScrewBomName(item.originalName) &&
            (item.originalName.contains('Kit') ||
                item.originalName.contains('كيت'));
        final isCaisson = item.originalName == 'الصندوق (Caisson)';
        // إذا كان العنصر المُبدَّل هو "الصندوق"، حدد وضع التونيل حسب id خاص (-999 يعني تونيل)
        if (isCaisson) {
          if (mutableSelected['id'] == -999) {
            widget.model.toggleCaissonTunnel(true);
          } else {
            widget.model.toggleCaissonTunnel(false);
            final selectedBoxSize = double.tryParse(
              getComponentSize(mutableSelected) ?? '',
            );
            if (selectedBoxSize != null && selectedBoxSize > 0) {
              mutableSelected['manual_override'] = true;
              widget.model.setManualShutterBoxHeight(selectedBoxSize);
            }
          }
        }
        Map<String, dynamic>?
        companionCaissonToSet; // صندوق مرافق يجب ضبطه إذا اخترنا كيتًا
        // ---- محاذاة الصندوق مع الكيت المناسب (بالاتجاهين: صندوق→كيت أو كيت→صندوق) ----
        if (isCaisson || isKitItem) {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              if (isCaisson) {
                // اخترنا صندوقًا جديدًا: ابحث عن الكيتات النشطة حسب الآلية الحالية وحدّثها لتطابق مقاس الصندوق
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
                  activeKitKeys = ['كيت فولي (Kit Volet)'];
                }
                for (var kitKey in activeKitKeys) {
                  final compRes = await dbInstance.query(
                    'KitBundles',
                    where: 'is_active = 1 OR is_active IS NULL',
                  );
                  for (var row in compRes) {
                    final rowMap = Map<String, dynamic>.from(row);
                    if (!isShutterKitForMechanism(
                      rowMap,
                      widget.model.shutterMechanism,
                    )) {
                      continue;
                    }
                    final selectedSize = double.tryParse(selectedDigits);
                    final kitSize = kitBundleSizeMm(rowMap);
                    if (selectedSize != null &&
                        kitSize != null &&
                        (kitSize - selectedSize).abs() <= 0.5) {
                      // Found a KitBundles row matching the new caisson size.
                      final matchedCompanion = await _withShutterKitPrice(
                        dbInstance,
                        rowMap,
                      );
                      matchedCompanion['catalog_source'] = 'KitBundles';
                      widget.model.componentOverrides[kitKey] =
                          matchedCompanion;
                      break;
                    }
                  }
                }
              } else {
                // اخترنا كيتًا جديدًا: ابحث عن الصندوق المرافق بنفس مقاسه
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
        // متغيرات المكونات المرافقة للشرائح/السكك/الشريحة النهائية
        Map<String, dynamic>? companionLame;
        Map<String, dynamic>? companionCoulisse;
        Map<String, dynamic>? companionFinale;
        // إذا كان العنصر المُبدَّل هو الشريحة أو السكة أو الشريحة النهائية، احسب البقية تلقائيًا
        if (item.originalName == 'الشرائح (Lames)' ||
            item.originalName == 'السكك (Coulisses)' ||
            item.originalName == 'الشريحة النهائية (Lame Finale)') {
          final selectedDigits = getComponentSize(mutableSelected);
          if (selectedDigits != null) {
            final dbInstance = await db.db;
            if (dbInstance != null) {
              // 1. إيجاد "شريحة" مرافقة (بأقرب مقاس ونفس subtype) إذا لم يكن العنصر المُبدَّل هو الشريحة نفسها
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
                    // استبعاد الشرائح النهائية من البحث عن شريحة عادية
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
                // خطة بديلة: بحث بالمقاس الدقيق بدون شرط subtype
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
              // 2. إيجاد سكة (Coulisse) مرافقة إذا العنصر المُبدَّل ليس السكة نفسها
              if (item.originalName == 'الشرائح (Lames)') {
                final requiredTrackSize = getBladeTrackSize(mutableSelected);
                final res = await dbInstance.query(
                  'ShutterComponents',
                  where:
                      "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
                );
                for (var row in res) {
                  if (requiredTrackSize != null &&
                      getComponentMeasurementKey(row) == requiredTrackSize) {
                    companionCoulisse = Map<String, dynamic>.from(row);
                    companionCoulisse['calculated_price'] = _safeDouble(
                      companionCoulisse['price_dzd'] ??
                          companionCoulisse['price'],
                    );
                    break;
                  }
                }
              }
              // 3. إيجاد شريحة نهائية مرافقة إذا العنصر المُبدَّل ليس الشريحة النهائية نفسها
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
        // متغيرات مكونات مرافقة إضافية عند تغيير الشريحة أو المحرك
        Map<String, dynamic>? companionAxe;
        Map<String, dynamic>? companionAttache;
        Map<String, dynamic>? companionSupportMoteur;
        Map<String, dynamic>? companionEmbout;
        Map<String, dynamic>? companionSupportRoulement;
        Map<String, dynamic>? companionTandem;
        Map<String, dynamic>? companionBouchonLame;
        // إذا تم تغيير "الشرائح" تحديدًا، أعد حساب كل القطع المرتبطة بها دفعة واحدة
        if (item.originalName == 'الشرائح (Lames)') {
          final targetSubtype =
              mutableSelected['shutter_subtype']?.toString() ?? 'normal';
          companionAxe = await _findCompatibleShutterAxis(
            blade: mutableSelected,
            motor: widget.model.componentOverrides['المحرك (Moteur)'],
          );
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
          companionBouchonLame = await _findBladeEndCap(mutableSelected);
        }
        // Changing the motor can change which axis is compatible.  The blade
        // relation remains the first filter, before the motor diameter.
        if (item.originalName == 'المحرك (Moteur)') {
          companionAxe = await _findCompatibleShutterAxis(
            blade: widget.model.componentOverrides['الشرائح (Lames)'],
            motor: mutableSelected,
          );
        }
        // ---- تطبيق كل التغييرات: إما مسار الكيت (معالجة خاصة) أو المسار العام لتحديث componentOverrides ----
        if (isKitItem) {
          await _handleKitSelection(
            mutableSelected,
          ); // كيت: نمرر المعالجة كاملة لدالة مخصصة
        } else {
          final overrideKey =
              swapTarget.overrideKey ?? item.overrideKey ?? item.originalName;
          _setScreenState(() {
            // Bidirectional synchronization between B.O.M. profile selection and drawer stiles/montants checkboxes
            final selectedType = swapTarget.profileType.toLowerCase();
            final selectionHint = [
              selectedType,
              item.originalName,
              item.overrideKey ?? '',
              swapTarget.overrideKey ?? '',
            ].join(' ').toLowerCase();
            if (isSlidingSlimComplementRow) {
              // This is the dedicated 10 cm top/bottom Slim complement, not
              // the Slim central montant. Store its choice under the stable
              // calculation key used when the BOM is rebuilt.
              widget
                      .model
                      .componentOverrides['مكمل علوي وسفلي للمونتوسليم 10 سم (Complément haut et bas)'] =
                  mutableSelected;
              widget
                      .model
                      .componentOverrides['قطاع وصلة المونتوسليم 10 سم (Taquet Slim 10cm)'] =
                  mutableSelected;
              widget.model.componentOverrides[overrideKey] = mutableSelected;
            } else if (isSlidingSlimRow) {
              // Slim is its own selected profile. Treating it as the normal
              // central montant overwrote the regular override and made the
              // Slim row vanish after the next BOM refresh.
              widget.model.applySlidingMontantSlimOverride(
                mutableSelected,
                manualSelection: true,
              );
            } else if (isSlidingLateralRow ||
                (!isSlidingCentralRow &&
                    (selectedType.contains('lateral') ||
                        selectionHint.contains('montant lateral') ||
                        selectionHint.contains('sash lateral') ||
                        item.originalName.contains('Sash Lateral') ||
                        item.originalName.contains('قائم جانبي') ||
                        item.originalName == 'قائم جانبي (Lateral)'))) {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: false,
                manualSelection: true,
              );
            } else if (isSlidingCentralRow ||
                selectedType.contains('central') ||
                selectionHint.contains('montant central') ||
                selectionHint.contains('sash central') ||
                item.originalName.contains('Sash Central') ||
                item.originalName.contains('قائم وسطي') ||
                item.originalName == 'قائم وسطي (Central)') {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: true,
                manualSelection: true,
              );
            } else {
              final normalizedPType = pType.toLowerCase();
              final isParcloseSelection =
                  pCategory == 'profile' &&
                  (normalizedPType == 'parclose' ||
                      normalizedPType.contains('parclose') ||
                      normalizedPType.contains('باكيت') ||
                      normalizedPType.contains('بيركلوز'));
              if (isParcloseSelection) {
                // A BOM row represents the profile family, not one physical
                // occurrence. Replace the old simple/double/sliding aliases
                // so every matching parclose in the drawing uses the choice.
                for (final key in widget.model.componentOverrides.keys.where((
                  key,
                ) {
                  final lower = key.toLowerCase();
                  return lower.contains('parclose') ||
                      key.contains('باكيت') ||
                      key.contains('بيركلوز');
                }).toList()) {
                  widget.model.componentOverrides.remove(key);
                }
                widget.model.componentOverrides['باكيت الزجاج (Parclose)'] =
                    mutableSelected;
              } else {
                widget.model.componentOverrides[overrideKey] =
                    mutableSelected; // حفظ الاختيار الجديد كـ override
              }
            }
            widget.model
                .updateGlassGasket(); // تحديث جوان الزجاج (إن كان مرتبطًا بتغييرات البروفيل)
            // إذا كانت الشريحة الجديدة "extruded"، فرض الآلية على محرك (لأن الإكسترودي ثقيل ويحتاج محركًا)
            if (item.originalName == 'الشرائح (Lames)') {
              widget.model.shutterLame =
                  mutableSelected['name']?.toString() ?? '';
              final bladeSubtype =
                  (mutableSelected['shutter_subtype']?.toString() ?? '')
                      .toLowerCase();
              final bladeName = (mutableSelected['name']?.toString() ?? '')
                  .toLowerCase();
              if (bladeSubtype == 'extruded' ||
                  bladeName.contains('extruded') ||
                  bladeName.contains('إكسترودي')) {
                widget.model.shutterMechanism = 'محرك';
              }
            }
            // تطبيق كل المكونات المرافقة المحسوبة أعلاه (إن وُجدت) على النموذج
            if (companionCaissonToSet != null) {
              widget.model.componentOverrides['الصندوق (Caisson)'] =
                  companionCaissonToSet;
            }
            if (companionLame != null) {
              widget.model.componentOverrides['الشرائح (Lames)'] =
                  companionLame;
            }
            if (companionCoulisse != null) {
              widget.model.componentOverrides['السكك (Coulisses)'] =
                  companionCoulisse;
            }
            if (companionFinale != null) {
              widget
                      .model
                      .componentOverrides['الشريحة النهائية (Lame Finale)'] =
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
              widget
                      .model
                      .componentOverrides['سيبور رولمو (Support Roulement)'] =
                  companionSupportRoulement;
            }
            if (companionTandem != null) {
              widget.model.componentOverrides['طانديم (Tandem)'] =
                  companionTandem;
            }
            if (item.originalName == 'الشرائح (Lames)') {
              if (companionBouchonLame == null) {
                widget.model.componentOverrides.remove(
                  'أغطية الشفرات (Bouchons Lames)',
                );
              } else {
                widget
                        .model
                        .componentOverrides['أغطية الشفرات (Bouchons Lames)'] =
                    companionBouchonLame;
              }
            }
            widget.model.refreshUI();
          });
          if (_swapSelectionNeedsDefaultRefresh(item, swapTarget)) {
            // Only shutter families need a companion/default refresh. Profile
            // and accessory swaps must remain immediate and user-owned.
            await _fetchDefaults();
          } else {
            await _refreshVisibleBomItems();
          }
        }
      } catch (e) {
        print(
          "Error handling swap selection: $e",
        ); // تسجيل الخطأ دون كسر الشاشة
      }
    }
  }
}
