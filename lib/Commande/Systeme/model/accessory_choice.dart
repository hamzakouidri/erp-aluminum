part of '../model.dart';

/// Accessory categories as saved in the products page (the part of
/// `Accessories.type` before "|", the part after it being the quality). A
/// part is offered for a drawing accessory only when its category is exactly
/// the one of that accessory, never by guessing from its name.
abstract final class AccessoryCategory {
  static const windowHandle = 'Poignée Fenêtre';
  static const doorHandle = 'Poignée Porte';
  static const doorHandleKey = 'Poignée Porte à Clé';
  static const doorHandleCondamnation = 'Poignée Porte Condamnation';
  static const marechalHandle = 'Poignée Maréchal';
  static const octoHandle = 'octo';
  static const hinges = 'Paumelles';
  static const verrou = 'Verrou';
  static const cremone = 'Crémone';
  static const canon = 'Canon';

  /// The category of an `Accessories.type` value ("category|quality").
  static String of(dynamic type) =>
      (type?.toString() ?? '').split('|').first.trim();

  /// The quality of an `Accessories.type` value, empty when none was saved.
  static String qualityOf(dynamic type) {
    final parts = (type?.toString() ?? '').split('|');
    return parts.length > 1 ? parts[1].trim() : '';
  }
}

/// One accessory of the cost table that can be chosen from the drawing:
/// its cost-table key and the category of the parts that may replace it.
class DrawingAccessorySlot {
  final String bomKey;
  final String category;

  const DrawingAccessorySlot(this.bomKey, this.category);
}

/// Choosing a specific accessory part for the drawing. The choice lives in
/// [WindowModel.componentOverrides] under the cost-table key, so the drawing
/// page and the cost table read and write the same value: whichever changed
/// it last wins.
extension WindowModelAccessoryChoice on WindowModel {
  static const hingesSlot = DrawingAccessorySlot(
    'المفاصل (Hinges)',
    AccessoryCategory.hinges,
  );
  static const verrouSlot = DrawingAccessorySlot(
    'الفيرو (Verrou)',
    AccessoryCategory.verrou,
  );
  static const cremoneSlot = DrawingAccessorySlot(
    'كريمون (Cremone)',
    AccessoryCategory.cremone,
  );
  static const canonSlot = DrawingAccessorySlot(
    'الأسطوانة (Canon)',
    AccessoryCategory.canon,
  );
  static const doorHandleSlot = DrawingAccessorySlot(
    'مقبض الباب عادي (Poignée Porte)',
    AccessoryCategory.doorHandle,
  );
  static const doorHandleKeySlot = DrawingAccessorySlot(
    'مقبض الباب (Poignée Porte à Clé)',
    AccessoryCategory.doorHandleKey,
  );
  static const doorHandleCondamnationSlot = DrawingAccessorySlot(
    'مقبض الباب Condamnation (Poignée Condamnation)',
    AccessoryCategory.doorHandleCondamnation,
  );
  static const marechal125Slot = DrawingAccessorySlot(
    'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
    AccessoryCategory.marechalHandle,
  );
  static const marechal2mSlot = DrawingAccessorySlot(
    'مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)',
    AccessoryCategory.marechalHandle,
  );

  /// The window handle row: the cost table names it differently for PVC and
  /// aluminium (see calculate_component), and writing the other name would
  /// make an aluminium crémone window count a separate handle too.
  DrawingAccessorySlot get windowHandleSlot => DrawingAccessorySlot(
    isPVC
        ? 'مقبض نافذة (Poignée Fenêtre)'
        : (componentOverrides.containsKey('مقبض نافذة (Poignée)')
              ? 'مقبض نافذة (Poignée)'
              : 'المقبض (Handle)'),
    AccessoryCategory.windowHandle,
  );

  /// The handle row of [zone] in the cost table, following the counting of
  /// calculate_component (door lock types first, then the window handle
  /// kinds). Null for a zone without an opening sash or with a handle kind
  /// that has no category yet (point lock, recessed PVC handle).
  DrawingAccessorySlot? handleSlotFor(WindowZone zone) {
    if (zone.content != ZoneContent.singleSash &&
        zone.content != ZoneContent.doubleSash) {
      return null;
    }
    final isTprThinSash =
        (activeSeries?.name.toLowerCase() ?? '').contains('tpr') &&
        !zone.isSash105;
    const doorLocks = {
      LockType.clef,
      LockType.condamnation,
      LockType.rouleau,
      LockType.rouleau2000,
    };
    final hasDoorLock = doorLocks.contains(zone.lockType) && !isTprThinSash;
    final isDoor =
        (zone.isSash105 || hasDoorLock) &&
        zone.lockType != LockType.none &&
        zone.useOctoHandle != true &&
        zone.usePvcHandleOnAlu != true;
    if (isDoor) {
      return switch (zone.lockType) {
        LockType.rouleau => marechal125Slot,
        LockType.rouleau2000 => marechal2mSlot,
        LockType.condamnation => doorHandleCondamnationSlot,
        LockType.clef => doorHandleKeySlot,
        _ => doorHandleSlot,
      };
    }
    final windowHandleOnDoor = zone.isSash105 && zone.usePvcHandleOnAlu;
    if (zone.content == ZoneContent.singleSash &&
        zone.lockType == LockType.point) {
      return null;
    }
    if (zone.usePvcHandleOnAlu && !windowHandleOnDoor) {
      return const DrawingAccessorySlot(
        'مقبض نافذة بي في سي (Poignée Fenêtre PVC)',
        AccessoryCategory.windowHandle,
      );
    }
    if (isPVC && zone.useEncastreeHandle) return null;
    if (zone.useOctoHandle) {
      return const DrawingAccessorySlot(
        'مقبض أوكتو (Octo)',
        AccessoryCategory.octoHandle,
      );
    }
    // An aluminium opening counts its ordinary handle as a crémone.
    return isPVC ? windowHandleSlot : cremoneSlot;
  }

  /// How many parts of [slot] the opening sashes of this drawing use, for
  /// the window quantity: the stock a choice must cover.
  int handlesNeeded(DrawingAccessorySlot slot) {
    var count = 0;
    for (final zone in zones) {
      if (handleSlotFor(zone)?.bomKey != slot.bomKey) continue;
      count += zone.content == ZoneContent.doubleSash &&
              zone.doubleSashHasTwoHandles
          ? 2
          : 1;
    }
    return count * math.max(1, quantity);
  }

  /// The accessories of the accessories tab this drawing uses, each with the
  /// parts it needs for the window quantity, counted like calculate_component.
  /// Empty for a drawing without an opening sash. The crémone is not listed:
  /// it belongs to the handles tab.
  List<({DrawingAccessorySlot slot, int needed})> drawingAccessorySlots() {
    if (systemMode == 'sliding') return const [];
    final windows = math.max(1, quantity);
    var hinges = 0;
    var doubleSashes = 0;
    var canons = 0;
    final usesOb = effectiveUseSystemOB || effectiveUseDemiOB;
    for (final zone in zones) {
      if (zone.content != ZoneContent.singleSash &&
          zone.content != ZoneContent.doubleSash) {
        continue;
      }
      final leaves = zone.content == ZoneContent.doubleSash ? 2 : 1;
      if (leaves == 2) doubleSashes++;
      // With OB the handle leaf's hinges come in its kit.
      final obLeaf = isHandleLeaf(zone, 0) ? 0 : 1;
      for (var leaf = 0; leaf < leaves; leaf++) {
        if (usesOb && leaf == obLeaf) continue;
        hinges += hingeCountForLeaf(zone, leaf);
      }
      for (final key in zone.cellIsSash.keys) {
        if (zone.cellIsSash[key] == true) hinges += 2;
      }
      for (final key in zone.cellIsDoubleSash.keys) {
        if (zone.cellIsDoubleSash[key] == true) hinges += 4;
      }
      if (handleSlotFor(zone)?.bomKey == doorHandleKeySlot.bomKey) canons++;
    }
    final verrouCentral = canUseOpeningOnlyOptions && useVerrouCentral;
    return [
      if (hinges > 0) (slot: hingesSlot, needed: hinges * windows),
      if (doubleSashes > 0 && !verrouCentral)
        (slot: verrouSlot, needed: doubleSashes * 2 * windows),
      if (canons > 0) (slot: canonSlot, needed: canons * windows),
    ];
  }

  /// Whether [accessory] (an `Accessories` row) may replace an accessory of
  /// [category] in this drawing: same category, active, the drawing's
  /// material, and global or linked to [seriesId].
  bool accessoryFitsDrawing(
    Map<String, dynamic> accessory,
    String category, {
    int? seriesId,
  }) {
    final active = accessory['is_active'];
    if (active != null && active.toString() != '1' && active != true) {
      return false;
    }
    if (AccessoryCategory.of(accessory['type']).toLowerCase() !=
        category.toLowerCase()) {
      return false;
    }
    final material = (accessory['material_type'] ?? 'Aluminium')
        .toString()
        .trim()
        .toLowerCase();
    if (material != 'both' && (material == 'pvc') != isPVC) return false;
    final scope = (accessory['scope'] ?? 'Global').toString().trim();
    if (scope.toLowerCase() == 'global') return true;
    final series = seriesId ?? activeSeries?.id;
    if (series == null) return false;
    final ids = (accessory['series_ids'] ?? '').toString();
    return ids.contains(',$series,') ||
        accessory['series_id']?.toString() == series.toString();
  }

  /// Every part of [category] that fits this drawing, by name.
  Future<List<Map<String, dynamic>>> accessoryCandidates(
    String category, {
    int? seriesId,
  }) async {
    final database = await db.db;
    if (database == null) return const [];
    final rows = await database.query('Accessories', orderBy: 'name');
    return [
      for (final row in rows)
        if (accessoryFitsDrawing(row, category, seriesId: seriesId))
          Map<String, dynamic>.from(row),
    ];
  }

  /// Price of [accessory] for this drawing. Once an accessory has colour
  /// prices, only the drawing's accessory colour is valid (no fallback to
  /// the base price); a colourless accessory keeps its base price.
  Future<double> accessoryPriceForDrawing(Map<String, dynamic> accessory) async {
    double readPrice(dynamic value) {
      final price = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
      return price.isFinite && price >= 0 ? price : 0.0;
    }

    final basePrice = readPrice(accessory['price_dzd'] ?? accessory['price']);
    final accessoryId = accessory['id'];
    final database = await db.db;
    if (accessoryId == null || database == null) return basePrice;
    try {
      final colorPrices = await database.query(
        'AccessoryColorPrices',
        columns: const ['color_id', 'price'],
        where: 'accessory_id = ?',
        whereArgs: [accessoryId],
      );
      final colorId = selectedAccessoryColor?['id'];
      if (colorPrices.isEmpty || colorId == null) return basePrice;
      for (final row in colorPrices) {
        if (row['color_id']?.toString() == colorId.toString()) {
          return readPrice(row['price']);
        }
      }
      return 0.0;
    } catch (_) {
      // Legacy databases without the colour-price table.
      return basePrice;
    }
  }

  /// [accessory] ready to be stored as a choice: its price for the drawing's
  /// accessory colour and the parts that come with it (gâche, screws, linked
  /// accessories), which the cost table reads from the stored row.
  Future<Map<String, dynamic>> prepareAccessoryChoice(
    Map<String, dynamic> accessory,
  ) async {
    final choice = Map<String, dynamic>.from(accessory);
    choice['calculated_price'] = await accessoryPriceForDrawing(choice);
    choice['manual_selection'] = true;
    choice['user_selected'] = true;
    choice['automatic_selection'] = false;

    final database = await db.db;
    if (database == null) return choice;
    Future<Map<String, dynamic>?> related(dynamic rawId) async {
      final id = rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
      if (id == null) return null;
      try {
        final rows = await database.query(
          'Accessories',
          where: '(is_active = 1 OR is_active IS NULL) AND id = ?',
          whereArgs: [id],
          limit: 1,
        );
        return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
      } catch (_) {
        return null;
      }
    }

    for (final key in const [
      'linked_accessory',
      'gache_accessory',
      'screw_accessory',
      'linked_accessories',
    ]) {
      choice.remove(key);
    }
    final gache = await related(
      choice['linked_accessory_id'] ?? choice['gache_accessory_id'],
    );
    if (gache != null) {
      choice['linked_accessory'] = gache;
      choice['gache_accessory'] = gache;
    }
    final screw = await related(choice['screw_accessory_id']);
    if (screw != null) choice['screw_accessory'] = screw;
    final id = choice['id'];
    final accessoryId = id is num ? id.toInt() : int.tryParse('${id ?? ''}');
    if (accessoryId != null) {
      choice['linked_accessories'] = await db.readAccessoryLinksWithDetails(
        accessoryId,
      );
    }
    return choice;
  }

  /// Uses [accessory] for the cost-table row [bomKey] of this drawing.
  Future<void> setAccessoryChoice(
    String bomKey,
    Map<String, dynamic> accessory, {
    bool notify = true,
  }) async {
    final choice = await prepareAccessoryChoice(accessory);
    componentOverrides[bomKey] = choice;
    if (notify) _notifyModelListeners();
  }

  /// Whether the user chose the part of [bomKey] (from the drawing or the
  /// cost table) rather than receiving the series default.
  bool isAccessoryChosen(String bomKey) {
    final choice = componentOverrides[bomKey];
    return choice != null &&
        (choice['manual_selection'] == true || choice['user_selected'] == true);
  }

  /// Drops the choice of [bomKey] and loads the series default again.
  Future<void> clearAccessoryChoice(String bomKey, {bool notify = true}) async {
    componentOverrides.remove(bomKey);
    final series = systemMode == 'sliding'
        ? (activeSlidingSeries ?? activeSeries)
        : activeSeries;
    final database = await db.db;
    if (series != null && database != null) {
      await _loadAccessoryDefaults(database, series.id);
    }
    if (notify) _notifyModelListeners();
  }
}
