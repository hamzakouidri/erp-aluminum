import 'calculate_component.dart';
import 'model.dart';
import 'profile_selector_dialog.dart';
import '../../sql_database.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'accessory_assembly.dart';

/// Rule-first resolver for the material table.
///
/// This engine deliberately does not search catalogue names. It resolves an
/// item through its explicit selector type, then through the administrator's
/// Catalog Item Rules.
class BomEngineV2 {
  BomEngineV2({SqlDatabase? database}) : _db = database ?? SqlDatabase();

  final SqlDatabase _db;
  String _catalogLabel(String value) => value
      .replaceAll(
        RegExp(
          r'\s*\([^)]*(?:جودة|رفيعة|رديئة|تجارية|قياسية|qualit[ée]|quality|premium|standard|commercial)[^)]*\)',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  bool _looksLikeAlignmentSquare(Map<String, dynamic> item) {
    final text =
        '${item['name'] ?? ''} ${item['type'] ?? ''} ${item['code'] ?? ''}'
            .toLowerCase();
    return text.contains('alignement') ||
        text.contains('alignment') ||
        text.contains('d align') ||
        text.contains("d'align") ||
        text.contains('دالينمو') ||
        text.contains('دالينيمو') ||
        text.contains('ekd');
  }

  final Map<String, Future<List<Map<String, dynamic>>>> _candidatesCache = {};

  Future<void> stabilizeSelections({
    required WindowModel window,
    required List<BomItem> items,
  }) async {
    final database = await _db.db;
    if (database == null) return;
    await Future.wait(
      items.map((item) async {
        // A screw/accessory explicitly linked from its parent is already the
        // exact catalogue product to use. Do not replace it with the first
        // standalone rule candidate during stabilization.
        if ((item.overrideKey ?? '').startsWith('linked-accessory:')) {
          return;
        }
        // Kit children are owned by the kit definition. They do not need an
        // independent CatalogItemRules row and must not be resolved as if they
        // were standalone components.
        if (item.isActive && item.kitGroupName != null) {
          return;
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
      }),
    );
  }

  Future<List<BomItem>> filterItemsByAvailableCandidates({
    required WindowModel window,
    required List<BomItem> items,
  }) async {
    final calculatedRoles = <String>{};
    for (final role in const ['installation_screw', 'bouchon_batmo_screw']) {
      if (await _calculatedMaterialRoleEnabled(window, role)) {
        calculatedRoles.add(role);
      }
    }
    final resolved = await Future.wait(
      items.map((item) async {
        final role = (item.roleKey ?? item.selectorType ?? '')
            .trim()
            .toLowerCase();
        // Assembly hardware is additive and bound to physical frames/sashes.
        // Rebuild it from rules instead of selecting just the first screw.
        if (item.originalName == 'براغي التجميع' ||
            (item.overrideKey ?? '').startsWith('assembly:') ||
            assemblyAccessoryRoles.contains(role)) {
          return null;
        }
        // An accessory dependency was explicitly linked from its parent in the
        // catalogue. It does not need a second standalone series rule.
        if ((item.overrideKey ?? '').startsWith('linked-accessory:')) {
          return item;
        }
        // A configured Kit is authoritative: its active child rows are the
        // complete list saved on the Kits page. They must remain available for
        // the expandable Kit row even when a child has no standalone rule row.
        if (item.isActive && item.kitGroupName != null) {
          return item;
        }
        // Series kits are also additive rule rows. Legacy BOM generation still
        // creates placeholder kit rows, sometimes without a catalogue id. If
        // retained, the rule row below is displayed a second time and may carry
        // stale linked-accessory data from another hardware family.
        if (const {
          'kit',
          'sliding_kit',
          'sliding_kit_40000',
          'sliding_kit_67000',
        }.contains(role)) {
          return null;
        }
        if (calculatedRoles.contains(role)) return item;
        if (await _itemHasRuleCandidate(window, item)) {
          return item;
        }
        return null;
      }),
    );
    final kept = resolved.whereType<BomItem>().toList();
    kept.addAll(await _assemblyItems(window, kept));
    kept.addAll(await _linkedAccessoryItems(window, kept));
    final existingIds = kept
        .map((item) => item.catalogItemId)
        .whereType<int>()
        .toSet();
    kept.addAll(
      (await _seriesKitItems(window, kept)).where(
        (item) =>
            item.catalogItemId == null ||
            !existingIds.contains(item.catalogItemId),
      ),
    );
    kept.addAll(await _frameRoleJoints(kept));
    final visibleItems = _deduplicateRoleAccessories(kept);
    // Rebuild accessory screws only after every rule, Kit and linked
    // accessory has been resolved and duplicate visible rows have been
    // removed. The screw calculation must use exactly the quantities shown
    // to the user, otherwise a hidden duplicate is counted twice.
    visibleItems.removeWhere(_isAccessoryScrewRow);
    visibleItems.addAll(await _accessoryScrewItems(window, visibleItems));
    return visibleItems;
  }

  Future<bool> _calculatedMaterialRoleEnabled(
    WindowModel window,
    String role,
  ) async {
    final seriesIds = <int>{
      if (window.activeSeries?.id != null) window.activeSeries!.id,
      if (window.activeSlidingSeries?.id != null)
        window.activeSlidingSeries!.id,
    };
    for (final seriesId in seriesIds) {
      final rules = await _db.getCatalogItemRules(
        itemTable: 'Accessories',
        seriesId: seriesId,
        roleKeys: [role],
      );
      if (rules.any((rule) => _catalogInt(rule['show_in_quantity']) != 0)) {
        return true;
      }
      final flagColumn = switch (role) {
        'accessory_screw' => 'is_accessory_screw',
        'installation_screw' => 'is_installation_screw',
        'bouchon_batmo_screw' => 'is_bouchon_batmo_screw',
        _ => null,
      };
      final database = await _db.db;
      if (database != null && flagColumn != null) {
        final flaggedRules = await database.rawQuery(
          '''
          SELECT r.show_in_quantity
          FROM CatalogItemRules r
          INNER JOIN Accessories a ON a.id = r.item_id
          WHERE r.item_table = 'Accessories'
            AND r.is_active = 1
            AND r.series_id = ?
            AND a.$flagColumn = 1
          ''',
          [seriesId],
        );
        if (flaggedRules.any(
          (rule) => _catalogInt(rule['show_in_quantity']) != 0,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isAccessoryScrewRow(BomItem item) {
    final role = (item.roleKey ?? item.selectorType ?? '').toLowerCase();
    return role == 'accessory_screw' ||
        role == 'is_accessory_screw' ||
        (item.overrideKey ?? '').startsWith('linked-accessory:screw:');
  }

  Future<List<BomItem>> _accessoryScrewItems(
    WindowModel window,
    List<BomItem> sourceItems,
  ) async {
    final showAccessoryScrews = await _calculatedMaterialRoleEnabled(
      window,
      'accessory_screw',
    );
    // Accessory-screw relations remain stored on each accessory. The role
    // only controls whether their calculated, grouped result is published in
    // the quantity table, just like the other rule-driven materials.
    if (!showAccessoryScrews) return const [];

    final database = await _db.db;
    if (database == null) return const [];

    final quantitiesByAccessoryId = <int, double>{};
    final sourceSeriesByAccessoryId = <int, int?>{};
    final materialByAccessoryId = <int, String?>{};
    for (final item in sourceItems) {
      final id = item.catalogItemId;
      if (item.category != 'accessory' ||
          !item.isActive ||
          item.quantity <= 0 ||
          id == null ||
          _isAccessoryScrewRow(item)) {
        continue;
      }
      quantitiesByAccessoryId[id] =
          (quantitiesByAccessoryId[id] ?? 0.0) + item.quantity;
      sourceSeriesByAccessoryId[id] = item.sourceSeriesId;
      materialByAccessoryId[id] = item.materialType;
    }
    if (quantitiesByAccessoryId.isEmpty) return const [];

    final totalsByScrewId = <int, double>{};
    final screwSeries = <int, int?>{};
    final screwMaterials = <int, String?>{};
    final sourcesUsingRoleLinks = <int>{};

    // New rules store "this accessory uses N accessory screws" as a role
    // link. Resolve that role to the real screw product selected for the
    // series. These links are authoritative over the legacy columns below.
    for (final sourceId in quantitiesByAccessoryId.keys) {
      final links = await _db.readAccessoryLinksWithDetails(sourceId);
      for (final link in links) {
        final targetRole = '${link['target_role_key'] ?? ''}'
            .trim()
            .toLowerCase();
        final isScrewRelation =
            targetRole == 'accessory_screw' || targetRole.endsWith('_screw');
        if (!isScrewRelation) {
          continue;
        }
        final count =
            _catalogInt(link['linked_quantity'] ?? link['quantity']) ?? 0;
        if (count <= 0) continue;
        final seriesId =
            sourceSeriesByAccessoryId[sourceId] ?? window.activeSeries?.id;
        if (seriesId == null) continue;
        final candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'accessory',
            selectorType: 'is_accessory_screw',
            roleKeys: const ['accessory_screw'],
            seriesId: seriesId,
            materialType: materialByAccessoryId[sourceId],
            requireDialog: false,
            requireQuantity: true,
          ),
        );
        Map<String, dynamic>? selectedScrew = candidates.isEmpty
            ? null
            : Map<String, dynamic>.from(candidates.first);
        // Older catalogues often marked the physical screw with
        // is_accessory_screw while its single CatalogItemRules row carried
        // another screw role (box/bouchon/assembly). A role link from a
        // Paumelle must still resolve that explicitly flagged product.
        if (selectedScrew == null) {
          final flagged = await database.query(
            'Accessories',
            where:
                'is_accessory_screw = 1 AND (is_active = 1 OR is_active IS NULL)',
            orderBy: 'is_default DESC, id ASC',
          );
          final expectedMaterial = (materialByAccessoryId[sourceId] ?? '')
              .trim()
              .toLowerCase();
          selectedScrew = flagged
              .map((row) => Map<String, dynamic>.from(row))
              .where((row) {
                final material = '${row['material_type'] ?? ''}'
                    .trim()
                    .toLowerCase();
                return expectedMaterial.isEmpty ||
                    material.isEmpty ||
                    material == 'both' ||
                    material == expectedMaterial;
              })
              .firstOrNull;
        }
        if (selectedScrew == null) continue;
        final screwId = _catalogInt(selectedScrew['id']);
        if (screwId == null) continue;
        sourcesUsingRoleLinks.add(sourceId);
        totalsByScrewId[screwId] =
            (totalsByScrewId[screwId] ?? 0.0) +
            ((quantitiesByAccessoryId[sourceId] ?? 0.0) * count);
        screwSeries[screwId] = seriesId;
        screwMaterials[screwId] = materialByAccessoryId[sourceId];
      }
    }

    final sourceIds = quantitiesByAccessoryId.keys
        .where((id) => !sourcesUsingRoleLinks.contains(id))
        .toList();
    if (sourceIds.isEmpty && totalsByScrewId.isEmpty) return const [];
    final sourceRows = sourceIds.isEmpty
        ? const <Map<String, Object?>>[]
        : await database.query(
            'Accessories',
            columns: const ['id', 'screw_count', 'screw_accessory_id'],
            where: 'id IN (${List.filled(sourceIds.length, '?').join(',')})',
            whereArgs: sourceIds,
          );
    for (final row in sourceRows) {
      final sourceId = _catalogInt(row['id']);
      final screwId = _catalogInt(row['screw_accessory_id']);
      final screwCount = _catalogInt(row['screw_count']) ?? 0;
      if (sourceId == null || screwId == null || screwCount <= 0) continue;
      final sourceQuantity = quantitiesByAccessoryId[sourceId] ?? 0.0;
      if (sourceQuantity <= 0) continue;
      totalsByScrewId[screwId] =
          (totalsByScrewId[screwId] ?? 0.0) + (sourceQuantity * screwCount);
      screwSeries[screwId] = sourceSeriesByAccessoryId[sourceId];
      screwMaterials[screwId] = materialByAccessoryId[sourceId];
    }
    if (totalsByScrewId.isEmpty) return const [];

    final screwIds = totalsByScrewId.keys.toList();
    final screwRows = await database.query(
      'Accessories',
      where: 'id IN (${List.filled(screwIds.length, '?').join(',')})',
      whereArgs: screwIds,
    );
    final screwsById = <int, Map<String, dynamic>>{
      for (final row in screwRows)
        if (_catalogInt(row['id']) != null)
          _catalogInt(row['id'])!: Map<String, dynamic>.from(row),
    };

    final result = <BomItem>[];
    for (final entry in totalsByScrewId.entries) {
      final screw = screwsById[entry.key];
      if (screw == null || entry.value <= 0) continue;
      final productName = '${screw['name'] ?? 'Vis ${entry.key}'}'.trim();
      final code = '${screw['code'] ?? ''}'.trim();
      result.add(
        BomItem(
          category: 'accessory',
          originalName: 'براغي الإكسسوارات',
          name: code.isEmpty ? productName : '$code - $productName',
          profileCode: code.isEmpty ? null : code,
          imagePath: screw['image_path']?.toString(),
          quantity: entry.value,
          unit: 'حبة',
          unitPrice: _safeDouble(
            screw['calculated_price'] ?? screw['price_dzd'] ?? screw['price'],
          ),
          catalogItemId: entry.key,
          inventoryItemType: 'Accessory',
          overrideKey: 'linked-accessory:screw:${entry.key}',
          selectorCategory: 'accessory',
          selectorType: 'is_accessory_screw',
          roleKey: 'accessory_screw',
          sourceSeriesId: screwSeries[entry.key] ?? window.activeSeries?.id,
          materialType:
              screwMaterials[entry.key] ?? (window.isPVC ? 'pvc' : 'aluminium'),
        ),
      );
    }
    return result;
  }

  List<BomItem> _deduplicateRoleAccessories(List<BomItem> items) {
    const singularRoles = {
      'espagnolette',
      'gache_simple',
      'gache_double',
      'gache_door',
    };
    final result = <BomItem>[];
    final indexes = <String, int>{};
    for (final item in items) {
      final role = (item.roleKey ?? '').trim().toLowerCase();
      if (!singularRoles.contains(role) || item.catalogItemId == null) {
        result.add(item);
        continue;
      }
      final key = '${item.sourceSeriesId ?? 0}:$role:${item.catalogItemId}';
      final previousIndex = indexes[key];
      if (previousIndex == null) {
        indexes[key] = result.length;
        result.add(item);
        continue;
      }
      final previous = result[previousIndex];
      final itemIsRoleLink = (item.overrideKey ?? '').startsWith(
        'linked-accessory:',
      );
      final previousIsRoleLink = (previous.overrideKey ?? '').startsWith(
        'linked-accessory:',
      );
      // A role link is the authoritative strike row. For two copies from the
      // same path keep one calculated quantity instead of adding it twice.
      if (itemIsRoleLink && !previousIsRoleLink) {
        result[previousIndex] = item;
      } else if (item.quantity > previous.quantity) {
        result[previousIndex] = item;
      }
    }
    return result;
  }

  Future<List<BomItem>> _linkedAccessoryItems(
    WindowModel window,
    List<BomItem> sourceItems,
  ) async {
    final seriesId = window.activeSeries?.id;
    if (seriesId == null) return const [];
    final presentSections = drawingSectionIds(window);
    final totals = <int, double>{};
    final targets = <int, Map<String, dynamic>>{};
    final sourceSeries = <int, int?>{};
    final sourceMaterial = <int, String?>{};
    final expandedSources = <String>{};

    bool roleMatchesDrawing(String role) {
      final normalized = role.trim().toLowerCase();
      if (normalized == 'gache_simple') {
        return window.zones.any((z) => z.content == ZoneContent.singleSash);
      }
      if (normalized == 'gache_double') {
        return window.zones.any((z) => z.content == ZoneContent.doubleSash);
      }
      if (normalized == 'gache_door') {
        return window.zones.any(
          (z) => z.content == ZoneContent.singleSash && z.isSash105,
        );
      }
      return true;
    }

    for (final source in sourceItems) {
      if (source.category != 'accessory' ||
          source.catalogItemId == null ||
          source.quantity <= 0 ||
          (source.overrideKey ?? '').startsWith('linked-accessory:')) {
        continue;
      }
      final sourceKey = [
        source.sourceSeriesId ?? seriesId,
        source.roleKey ?? source.selectorType ?? '',
        source.catalogItemId,
        source.quantity,
      ].join(':');
      if (!expandedSources.add(sourceKey)) continue;
      final links = await _db.readAccessoryLinksWithDetails(
        source.catalogItemId!,
      );
      for (final link in links) {
        final targetRole = '${link['target_role_key'] ?? ''}'.trim();
        final count = _catalogInt(link['linked_quantity'] ?? link['quantity']);
        if (targetRole.isEmpty || count == null || count <= 0) continue;
        final targetSeriesId = source.sourceSeriesId ?? seriesId;
        final candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'accessory',
            selectorType: targetRole,
            roleKeys: [targetRole],
            seriesId: targetSeriesId,
            materialType: source.materialType,
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            effectiveHeightMm: window.effectiveEspagnoletteHeightMm,
          ),
        );
        final validCandidates = candidates.where((candidate) {
          final rawRule = candidate['catalog_rule'];
          if (rawRule is! Map) return false;
          final rule = Map<String, dynamic>.from(rawRule);
          if (!roleMatchesDrawing('${rule['role_key'] ?? ''}')) return false;
          final requiredSections = assemblySectionIds(rule);
          return requiredSections.isEmpty ||
              requiredSections.any(presentSections.contains);
        }).toList();
        if (validCandidates.isEmpty) continue;
        // Resolver ordering puts the role's default rule first. The remaining
        // candidates stay available through the ordinary selector dialog.
        final target = Map<String, dynamic>.from(validCandidates.first);
        final targetId = _catalogInt(target['id']);
        if (targetId == null) continue;
        totals[targetId] =
            (totals[targetId] ?? 0.0) + (count * source.quantity);
        targets[targetId] = target;
        sourceSeries[targetId] = targetSeriesId;
        sourceMaterial[targetId] = source.materialType;
      }
    }

    final database = await _db.db;
    if (database == null) return const [];
    return totals.entries.map((entry) {
      final target = targets[entry.key]!;
      final name = '${target['name'] ?? 'Accessory ${entry.key}'}';
      final role = '${target['catalog_rule']?['role_key'] ?? ''}'.trim();
      return BomItem(
        category: 'accessory',
        originalName: name,
        name: name,
        profileCode: target['code']?.toString(),
        imagePath: target['image_path']?.toString(),
        quantity: entry.value,
        unit: 'حبة',
        unitPrice: _safeDouble(
          target['calculated_price'] ?? target['price_dzd'] ?? target['price'],
        ),
        catalogItemId: entry.key,
        inventoryItemType: 'Accessory',
        overrideKey: 'linked-accessory:${entry.key}',
        selectorCategory: 'accessory',
        selectorType: role,
        roleKey: role,
        sourceSeriesId: sourceSeries[entry.key],
        materialType: sourceMaterial[entry.key],
      );
    }).toList();
  }

  Future<List<BomItem>> _frameRoleJoints(List<BomItem> items) async {
    final result = <BomItem>[];
    for (final profile in items.where(
      (item) =>
          const ['cache_rail', 'seuil', 'cache_dormant'].contains(item.roleKey),
    )) {
      final series = profile.sourceSeriesId;
      final section = profile.catalogItemId;
      final metres = profile.actualUsedMeters ?? 0;
      if (series == null || section == null || metres <= 0) continue;
      final rows = await _db.getDefaultJointsForSection(
        seriesId: series,
        sectionId: section,
        positionKeys: const [
          'cache_rail_inner',
          'cache_rail_outer',
          'profile_gasket_1',
          'profile_gasket_2',
        ],
      );
      // A link can return several products in the same gasket family.
      // The database sorts the default first: use one product per position.
      final positions = <String>{};
      for (final row in rows) {
        final position = '${row['position_key']}';
        if (!positions.add(position)) continue;
        final name = '${row['name'] ?? 'Joint Cache-rail'}';
        result.add(
          BomItem(
            category: 'joint',
            originalName: 'Joint ${profile.roleKey} ($position)',
            name: name,
            profileCode: row['code']?.toString(),
            quantity: metres,
            unit: 'متر',
            unitPrice: _safeDouble(
              row['price_per_meter'] ?? row['price_dzd'] ?? row['price'],
            ),
            catalogItemId: _catalogInt(row['id']),
            sourceSeriesId: series,
            materialType: profile.materialType,
            selectorCategory: 'joint',
            overrideKey:
                'frame-role-joint:${profile.roleKey}:$series:$section:$position',
          ),
        );
      }
    }
    return result;
  }

  Future<List<BomItem>> _seriesKitItems(
    WindowModel window,
    Iterable<BomItem> selectedProfiles,
  ) async {
    final result = <BomItem>[];
    final actualProfileIds = selectedProfiles
        .where((item) => (item.selectorCategory ?? item.category) == 'profile')
        .map((item) => item.catalogItemId)
        .whereType<int>()
        .toSet();
    final hasOpeningSashPlant = selectedProfiles.any((item) {
      final role = (item.roleKey ?? item.selectorType ?? '')
          .trim()
          .toLowerCase();
      return (item.selectorCategory ?? item.category) == 'profile' &&
          role == 'plant' &&
          item.sourceSeriesId == window.activeSeries?.id;
    });
    final slidingZones = window.zones.where(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final slidingKitCount = slidingZones.fold<int>(0, (sum, zone) {
      final leaves = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
      return sum + leaves ~/ 2;
    });
    // Equerre d'alignement is a 45-degree assembly corner for one opening
    // sash, not a sliding-kit supplement. A sash closed by a bottom plinthe
    // does not use these four corners.
    final openingAlignmentSquareCount = hasOpeningSashPlant
        ? 0
        : window.zones
                  .where((zone) => zone.content == ZoneContent.singleSash)
                  .length *
              4;
    final openingLeaves = window.zones
        .where(
          (zone) =>
              zone.content == ZoneContent.singleSash ||
              zone.content == ZoneContent.doubleSash,
        )
        .fold<int>(0, (sum, zone) {
          final leaves = zone.content == ZoneContent.doubleSash
              ? 2
              : (zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 1);
          return sum + leaves;
        });
    // An opening-series kit serves a complete pair of leaves. Never create a
    // kit for zero or one opening sash.
    final openingKitCount = openingLeaves ~/ 2;
    final contexts =
        <
          ({int id, bool sliding, String material, int kitCount, int ekarCount})
        >{
          if (window.activeSeries != null && !window.isShutterOnly)
            (
              id: window.activeSeries!.id,
              sliding: window.usesSlidingPrimaryProfiles,
              material: window.isPVC ? 'pvc' : 'aluminium',
              kitCount: window.usesSlidingPrimaryProfiles
                  ? slidingKitCount
                  : openingKitCount,
              ekarCount: window.usesSlidingPrimaryProfiles
                  ? 0
                  : openingAlignmentSquareCount,
            ),
          if (window.activeSlidingSeries != null &&
              !window.isShutterOnly &&
              window.zones.any(
                (zone) => zone.content == ZoneContent.slidingSash,
              ) &&
              window.activeSlidingSeries!.id != window.activeSeries?.id)
            (
              id: window.activeSlidingSeries!.id,
              sliding: true,
              material: window.isSlidingPVC ? 'pvc' : 'aluminium',
              kitCount: slidingKitCount,
              ekarCount: 0,
            ),
        };
    final database = await _db.db;
    if (database == null) return result;
    final addedAlignmentSquareIds = <int>{};
    for (final context in contexts) {
      final seriesLabel = window.activeSeries?.name.toLowerCase() ?? '';
      final isTpr40000 =
          !context.sliding &&
          (seriesLabel.contains('tpr') || seriesLabel.contains('tp')) &&
          (seriesLabel.contains('40000') || seriesLabel.contains('4000'));
      final roleKeys = context.sliding
          ? const ['sliding_kit', 'sliding_kit_40000', 'sliding_kit_67000']
          : isTpr40000
          ? const ['kit', 'sliding_kit_40000']
          : const ['kit'];
      var candidates = context.kitCount <= 0
          ? const <Map<String, dynamic>>[]
          : await _resolveCandidates(
              CatalogCandidateQuery(
                category: 'accessory',
                selectorType: context.sliding ? 'sliding_kit' : 'kit',
                roleKeys: roleKeys,
                seriesId: context.id,
                materialType: context.material,
                drawingMode: context.sliding
                    ? AccessoryDrawingMode.sliding
                    : AccessoryDrawingMode.opening,
                requireDialog: false,
                requireQuantity: true,
                hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
                hasDoubleGlassForRules: window.hasDoubleGlassForRules,
              ),
            );
      // Some catalogues configure the ordinary `kit` role for a sliding
      // series (notably TPR 40000). Prefer a dedicated sliding-kit rule, but
      // do not make an explicitly enabled generic kit disappear when no
      // dedicated rule exists for that same series.
      if (context.sliding && context.kitCount > 0 && candidates.isEmpty) {
        candidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'accessory',
            selectorType: 'kit',
            roleKeys: const ['kit'],
            seriesId: context.id,
            materialType: context.material,
            drawingMode: AccessoryDrawingMode.sliding,
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
          ),
        );
      }
      for (final candidate in candidates) {
        final rule = Map<String, dynamic>.from(
          candidate['catalog_rule'] as Map,
        );
        final linkedProfiles = assemblySectionIds(rule);
        // A linked profile is a presence condition, not merely editor
        // metadata. In particular, a 4NF kit linked to Batmo must disappear
        // when that Batmo profile is not part of the actual BOM.
        if (linkedProfiles.isNotEmpty &&
            !linkedProfiles.any(actualProfileIds.contains)) {
          continue;
        }
        final id = _catalogInt(candidate['id']);
        // Repair legacy catalogues where Ekar d'alignement was saved under
        // `kit`. It remains a piece-counted assembly corner and must never be
        // displayed as "Kit de série".
        if (_looksLikeAlignmentSquare(candidate)) {
          if (!context.sliding &&
              context.ekarCount > 0 &&
              id != null &&
              addedAlignmentSquareIds.add(id)) {
            final label = _catalogLabel(
              candidate['name']?.toString() ?? "Equerre d'alignement",
            );
            result.add(
              BomItem(
                category: 'accessory',
                originalName: label,
                name: label,
                quantity: (context.ekarCount * window.quantity).toDouble(),
                unit: 'حبة',
                unitPrice: await _accessoryPrice(database, candidate),
                catalogItemId: id,
                inventoryItemType: 'Accessory',
                profileCode: candidate['code']?.toString(),
                imagePath: candidate['image_path']?.toString(),
                overrideKey: 'opening-alignment-square:${context.id}:$id',
                selectorCategory: 'accessory',
                selectorType: 'alignment_square',
                roleKey: 'alignment_square',
                sourceSeriesId: context.id,
                materialType: context.material,
              ),
            );
          }
          continue;
        }
        final kitRole = rule['role_key']?.toString() ?? 'kit';
        final selectedName = _catalogLabel(
          candidate['name']?.toString() ?? 'Kit',
        );
        final selectedCode = candidate['code']?.toString().trim() ?? '';
        final heading = context.sliding ? 'كيت المنزلق' : 'كيت السلسلة';
        final details = [
          if (selectedName.isNotEmpty && selectedName != heading) selectedName,
          if (selectedCode.isNotEmpty && selectedCode != selectedName)
            selectedCode,
        ].join('\n');
        result.add(
          BomItem(
            category: 'accessory',
            originalName: heading,
            name: details.isEmpty ? heading : '$heading\n$details',
            quantity: (context.kitCount * window.quantity).toDouble(),
            unit: 'kit',
            unitPrice: await _accessoryPrice(database, candidate),
            catalogItemId: id,
            inventoryItemType: 'Accessory',
            profileCode: candidate['code']?.toString(),
            imagePath: candidate['image_path']?.toString(),
            overrideKey: 'series-kit:${context.id}:${id ?? 0}',
            selectorCategory: 'accessory',
            selectorType: kitRole,
            roleKey: kitRole,
            sourceSeriesId: context.id,
            materialType: context.material,
          ),
        );
      }
      if (!context.sliding && context.ekarCount > 0) {
        final ekarCandidates = await _resolveCandidates(
          CatalogCandidateQuery(
            category: 'accessory',
            selectorType: 'alignment_square',
            roleKeys: const ['alignment_square'],
            seriesId: context.id,
            materialType: context.material,
            drawingMode: AccessoryDrawingMode.opening,
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
          ),
        );
        for (final candidate in ekarCandidates) {
          final id = _catalogInt(candidate['id']);
          if (id == null || !addedAlignmentSquareIds.add(id)) continue;
          result.add(
            BomItem(
              category: 'accessory',
              originalName: _catalogLabel(
                candidate['name']?.toString() ?? "Equerre d'alignement",
              ),
              name: _catalogLabel(
                candidate['name']?.toString() ?? "Equerre d'alignement",
              ),
              quantity: (context.ekarCount * window.quantity).toDouble(),
              unit: 'حبة',
              unitPrice: await _accessoryPrice(database, candidate),
              catalogItemId: id,
              inventoryItemType: 'Accessory',
              profileCode: candidate['code']?.toString(),
              imagePath: candidate['image_path']?.toString(),
              overrideKey: 'opening-alignment-square:${context.id}:$id',
              selectorCategory: 'accessory',
              selectorType: 'alignment_square',
              roleKey: 'alignment_square',
              sourceSeriesId: context.id,
              materialType: context.material,
            ),
          );
        }
      }
    }
    return result;
  }

  List<AssemblyDemand> _selectedProfileAssemblyDemands(
    WindowModel window,
    Iterable<BomItem> items,
  ) {
    final demands = <AssemblyDemand>[];
    final orderQuantity = window.quantity <= 0 ? 1 : window.quantity;
    for (final item in items) {
      if ((item.selectorCategory ?? item.category) != 'profile') continue;
      final sectionId = item.catalogItemId;
      final pieces = item.pieces;
      if (sectionId == null || pieces == null || pieces.isEmpty) continue;

      final role = (item.roleKey ?? item.selectorType ?? '')
          .trim()
          .toLowerCase();
      // Outer frames and ordinary sash rectangles already have exact corner
      // demands from drawing geometry. The remaining profile rows represent
      // plinthes, mullions and the individual members of sliding sashes.
      if (role == 'frame' || role == 'sash') continue;

      final pieceCount = (pieces.length / orderQuantity).round();
      if (pieceCount <= 0) continue;
      final sliding =
          item.sourceSeriesId != null &&
          item.sourceSeriesId == window.activeSlidingSeries?.id &&
          (window.systemMode == 'sliding' ||
              item.sourceSeriesId != window.activeSeries?.id);
      demands.add(
        AssemblyDemand(
          target: 'profile',
          sliding: sliding,
          // A plinthe, traverse or sliding-sash member has two ends. The
          // catalogue rule independently defines the screw count at each end.
          topCorners: pieceCount,
          bottomCorners: pieceCount,
          sectionId: sectionId,
        ),
      );
    }
    return demands;
  }

  Future<List<BomItem>> _assemblyItems(
    WindowModel window,
    Iterable<BomItem> selectedProfiles,
  ) async {
    final selectedProfileList = selectedProfiles.toList(growable: false);
    final geometricDemands = assemblyDemands(window);
    _reconcileBaseAssemblySectionIds(
      window,
      geometricDemands,
      selectedProfileList,
    );
    final demands = [
      ...geometricDemands,
      ..._selectedProfileAssemblyDemands(window, selectedProfileList),
    ];
    if (demands.isEmpty) return [];
    final database = await _db.db;
    if (database == null) return [];
    final items = <BomItem>[];
    final assemblyScrewIndexByCatalogId = <int, int>{};
    for (final sliding in [false, true]) {
      final contextDemands = demands
          .where((d) => d.sliding == sliding)
          .toList();
      if (contextDemands.isEmpty) continue;
      final seriesId = sliding
          ? window.activeSlidingSeries?.id ?? window.activeSeries?.id
          : window.activeSeries?.id;
      final material = (sliding ? window.isSlidingPVC : window.isPVC)
          ? 'pvc'
          : 'aluminium';
      final candidates = <Map<String, dynamic>>[];
      // The picker deduplicates by accessory ID. Resolve each role separately
      // so one accessory can supply both frame and sash corners.
      for (final assemblyRole in assemblyAccessoryRoles) {
        candidates.addAll(
          await _resolveCandidates(
            CatalogCandidateQuery(
              category: 'accessory',
              selectorType: '',
              roleKeys: [assemblyRole],
              seriesId: seriesId,
              materialType: material,
              drawingMode: sliding
                  ? AccessoryDrawingMode.sliding
                  : AccessoryDrawingMode.opening,
              requireDialog: false,
              requireQuantity: true,
              hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
              hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            ),
          ),
        );
      }
      final addedRules = <String>{};
      for (final candidate in candidates) {
        final rule = Map<String, dynamic>.from(
          candidate['catalog_rule'] as Map,
        );
        final quantity =
            assemblyQuantity(rule, contextDemands) * window.quantity;
        if (quantity <= 0) continue;
        final id = _catalogInt(candidate['id']);
        final role = rule['role_key'].toString();
        final key = 'assembly:$seriesId:$sliding:$role:$id';
        // Frame, sash and support rules are additive, even for one accessory.
        // Suppress only a repeated candidate for the same rule.
        final ruleKey = '$key:${rule['id'] ?? ''}';
        if (!addedRules.add(ruleKey)) continue;
        final seriesName = sliding
            ? window.activeSlidingSeries?.name ??
                  window.activeSeries?.name ??
                  ''
            : window.activeSeries?.name ?? '';
        final isClam = const {
          'clam',
          'clamp',
          'sliding_clamp',
          'frame_clamp',
          'sash_clamp',
        }.contains(role);
        // Keep existing headings unchanged, except the dedicated assembly
        // screw heading; the selected catalog item is shown as its detail.
        final displayName = isClam
            ? 'Clam ${_catalogLabel(seriesName)}'.trim()
            : (role == 'assembly_screw'
                  ? 'براغي التجميع'
                  : candidate['name']?.toString() ?? role);
        final selectedName = candidate['name']?.toString().trim() ?? '';
        final selectedCode = candidate['code']?.toString().trim() ?? '';
        final details = [
          if (selectedName.isNotEmpty && selectedName != displayName)
            selectedName,
          if (selectedCode.isNotEmpty && selectedCode != selectedName)
            selectedCode,
        ].join('\n');
        final item = BomItem(
          category: 'accessory',
          originalName: displayName,
          name: details.isEmpty ? displayName : '$displayName\n$details',
          quantity: quantity.toDouble(),
          unit: 'حبة',
          unitPrice: await _accessoryPrice(database, candidate),
          catalogItemId: id,
          inventoryItemType: 'Accessory',
          profileCode: candidate['code']?.toString(),
          imagePath: candidate['image_path']?.toString(),
          overrideKey: key,
          selectorCategory: 'accessory',
          selectorType: role,
          roleKey: role,
          sourceSeriesId: seriesId,
          materialType: material,
        );
        if (role == 'assembly_screw' && id != null) {
          final existingIndex = assemblyScrewIndexByCatalogId[id];
          if (existingIndex != null) {
            final existing = items[existingIndex];
            items[existingIndex] = _bomItemWithQuantity(
              existing,
              existing.quantity + item.quantity,
              overrideKey: 'assembly:combined:assembly_screw:$id',
            );
            continue;
          }
          assemblyScrewIndexByCatalogId[id] = items.length;
        }
        items.add(item);
      }
    }
    return items;
  }

  void _reconcileBaseAssemblySectionIds(
    WindowModel window,
    List<AssemblyDemand> demands,
    Iterable<BomItem> selectedProfiles,
  ) {
    for (final profile in selectedProfiles) {
      if ((profile.selectorCategory ?? profile.category) != 'profile') {
        continue;
      }
      final sectionId = profile.catalogItemId;
      final role = (profile.roleKey ?? profile.selectorType ?? '')
          .trim()
          .toLowerCase();
      if (sectionId == null || (role != 'frame' && role != 'sash')) continue;
      final sliding =
          profile.sourceSeriesId != null &&
          profile.sourceSeriesId == window.activeSlidingSeries?.id &&
          (window.systemMode == 'sliding' ||
              profile.sourceSeriesId != window.activeSeries?.id);
      final target = role == 'frame' ? 'frame' : 'sash';
      for (var index = 0; index < demands.length; index++) {
        final demand = demands[index];
        if (demand.sliding != sliding || demand.target != target) continue;
        // The strictly resolved BOM row is the actual profile selected for
        // this series. In mixed drawings the model-level shortcut may still
        // be null or point at the opening profile, causing a linked sliding
        // assembly rule to calculate zero.
        demands[index] = AssemblyDemand(
          target: demand.target,
          sliding: demand.sliding,
          topCorners: demand.topCorners,
          bottomCorners: demand.bottomCorners,
          sectionId: sectionId,
        );
      }
    }
  }

  BomItem _bomItemWithQuantity(
    BomItem item,
    double quantity, {
    String? overrideKey,
  }) {
    return BomItem(
      category: item.category,
      originalName: item.originalName,
      profileCode: item.profileCode,
      name: item.name,
      imagePath: item.imagePath,
      colorName: item.colorName,
      length: item.length,
      glassHeight: item.glassHeight,
      pieceCount: item.pieceCount,
      quantity: quantity,
      unit: item.unit,
      unitPrice: item.unitPrice,
      isMissing: item.isMissing,
      isInteractive: item.isInteractive,
      isActive: item.isActive,
      exclusionGroup: item.exclusionGroup,
      pieces: item.pieces,
      cuttingList: item.cuttingList,
      kitGroupName: item.kitGroupName,
      exactQuantity: item.exactQuantity == null ? null : quantity,
      catalogItemId: item.catalogItemId,
      inventoryItemType: item.inventoryItemType,
      colorId: item.colorId,
      overrideKey: overrideKey ?? item.overrideKey,
      selectorCategory: item.selectorCategory,
      selectorType: item.selectorType,
      roleKey: item.roleKey,
      sourceSeriesId: item.sourceSeriesId,
      materialType: item.materialType,
      targetThicknessMm: item.targetThicknessMm,
    );
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
        if (roleKeys.contains('reducer') && !window.hasSimpleGlassForReducer) {
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
            isCaissonTunnel: window.isCaissonTunnel,
            drawingMode: _drawingModeForItem(window, item),
            // Quantity visibility is independent of replacement-dialog visibility.
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            targetThicknessMm: item.targetThicknessMm,
            effectiveHeightMm: window.effectiveEspagnoletteHeightMm,
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
        if (_isShutterScrewRole(roleKeys) && item.catalogItemId != null) {
          return true;
        }
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
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
            hasDoubleGlassForRules: window.hasDoubleGlassForRules,
            targetThicknessMm: item.targetThicknessMm,
            effectiveHeightMm: window.effectiveEspagnoletteHeightMm,
          ),
        );
        return candidates.any(
          (candidate) => _accessoryMatchesLinkedSections(
            candidate,
            window,
            allowLegacyShutter: _isShutterScrewRole(roleKeys),
          ),
        );
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
            requireDialog: false,
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
    if (roleKeys.contains('reducer') && !window.hasSimpleGlassForReducer) {
      window.clearReducerOverride();
      return;
    }
    if (roleKeys.contains('reducer') &&
        (item.pieces?.isNotEmpty ?? false) &&
        window.hasSimpleGlassForReducer &&
        item.catalogItemId == null) {
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
        isCaissonTunnel: window.isCaissonTunnel,
        drawingMode: _drawingModeForItem(window, item),
        requireDialog: false,
        requireQuantity: true,
        hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: window.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
        effectiveHeightMm: window.effectiveEspagnoletteHeightMm,
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
    var resolvedCandidates = await _resolveCandidates(
      CatalogCandidateQuery(
        category: 'accessory',
        selectorType: selectorType,
        roleKeys: ruleKeys,
        seriesId: seriesId,
        materialType: materialType,
        drawingMode: _drawingModeForItem(window, item),
        requireDialog: false,
        requireQuantity: true,
        hasSimpleGlassForReducer: window.hasSimpleGlassForReducer,
        hasDoubleGlassForRules: window.hasDoubleGlassForRules,
        targetThicknessMm: item.targetThicknessMm,
        effectiveHeightMm: window.effectiveEspagnoletteHeightMm,
      ),
    );
    if (resolvedCandidates.isEmpty && _isShutterScrewRole(ruleKeys)) {
      resolvedCandidates = await _legacyShutterScrewCandidates(
        database,
        ruleKeys,
      );
    }
    final candidates = resolvedCandidates
        .where(
          (candidate) => _accessoryMatchesLinkedSections(
            candidate,
            window,
            allowLegacyShutter: _isShutterScrewRole(ruleKeys),
          ),
        )
        .toList();
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
    final selectedId = _catalogInt(selected['id']);
    if (selectedId != null) {
      selected['linked_accessories'] = await _db.readAccessoryLinksWithDetails(
        selectedId,
      );
    }
    final key = item.overrideKey ?? item.originalName;
    window.componentOverrides[key] = selected;
    if (key != item.originalName) {
      window.componentOverrides[item.originalName] = selected;
    }
  }

  bool _accessoryMatchesLinkedSections(
    Map<String, dynamic> candidate,
    WindowModel window, {
    bool allowLegacyShutter = false,
  }) {
    final rawRule = candidate['catalog_rule'];
    // Every non-shutter accessory must come from a persisted active rule.
    // The only permitted legacy source is the explicit shutter-screw path.
    if (rawRule is! Map) return allowLegacyShutter;
    final rule = Map<String, dynamic>.from(rawRule);
    final linkedSections = assemblySectionIds(rule);
    if (linkedSections.isEmpty) return true;
    return linkedSections.any(drawingSectionIds(window).contains);
  }

  bool _isShutterScrewRole(Iterable<String> roles) {
    const shutterScrewRoles = {
      'kit_screw',
      'box_screw',
      'motor_screw',
      'manivelle_screw',
    };
    return roles.any(shutterScrewRoles.contains);
  }

  Future<List<Map<String, dynamic>>> _legacyShutterScrewCandidates(
    Database database,
    Iterable<String> roles,
  ) async {
    final roleSet = roles.toSet();
    final flag = roleSet.contains('kit_screw')
        ? 'is_kit_screw'
        : roleSet.contains('box_screw')
        ? 'is_caisson_screw'
        : roleSet.contains('motor_screw')
        ? 'is_moteur_screw'
        : 'is_manivelle_screw';
    final rows = await database.query(
      'Accessories',
      where: '($flag = 1) AND (is_active = 1 OR is_active IS NULL)',
      orderBy: 'id ASC',
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
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
        requireDialog: false,
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
      query.isCaissonTunnel ? '1' : '0',
      query.drawingMode?.name ?? '',
      query.requireDialog ? '1' : '0',
      query.requireQuantity ? '1' : '0',
      query.hasSimpleGlassForReducer == true ? '1' : '0',
      query.hasDoubleGlassForRules == true ? '1' : '0',
      query.targetThicknessMm?.toStringAsFixed(3) ?? '',
      query.effectiveHeightMm?.toStringAsFixed(3) ?? '',
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
    if (materialType == 'shutter') return 'shutter';
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

    // Batmo is always sourced from the opening series.  This explicit rule is
    // required for mixed drawings where opening and sliding zones coexist.
    if (roleKey == 'batmo' ||
        roleKey == 'bouchon_batmo' ||
        selectorType == 'batmo' ||
        selectorType == 'bouchon_batmo') {
      return AccessoryDrawingMode.opening;
    }

    // In a mixed drawing, the presence of both sash families is not enough
    // to infer the source of generic hardware. BOM rows created for a sliding
    // zone carry either a sliding role/name or the sliding series id; resolve
    // those rows against the sliding catalogue explicitly.
    final isSlidingRole =
        const {
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
