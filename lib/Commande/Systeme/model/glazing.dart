part of '../model.dart';

/// Glass, panels, glazing beads, spacers and gaskets of [WindowModel].
extension WindowModelGlazing on WindowModel {
  double _glassPaneThicknessOrDefault(double? value) =>
      value != null && value > 0 ? value : kDefaultGlassPaneThickness;

  Map<String, dynamic>? selectedVitrageJointOverride() {
    final exact = componentOverrides['جوان الزجاج (Joint Vitrage)'];
    if (exact is Map) return Map<String, dynamic>.from(exact);
    for (final entry in componentOverrides.entries) {
      final key = entry.key.toLowerCase();
      if (entry.value is Map &&
          (key.contains('joint vitrage') ||
              key.contains('joint de vitrage') ||
              key.contains('جوان الزجاج') ||
              key.contains('فيتراج'))) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return null;
  }

  double selectedVitrageJointThickness({double fallback = 0.0}) {
    if (isPVC) return fallback;
    final selected = selectedVitrageJointOverride();
    final thickness = _readPositiveDouble(selected?['thickness']);
    if (thickness > 0) return thickness;
    if (_lastResolvedVitrageJointThickness > 0) {
      return _lastResolvedVitrageJointThickness;
    }
    return fallback;
  }

  Map<String, dynamic>? selectedBourrageJointOverride({
    bool doubleGlass = true,
  }) {
    final preferredKeys = doubleGlass
        ? const [
            'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
            'جوان البوراج (Joint Bourrage)',
          ]
        : const [
            'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
            'جوان البوراج (Joint Bourrage)',
          ];
    for (final key in preferredKeys) {
      final value = componentOverrides[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  double selectedBourrageJointThickness({
    bool doubleGlass = true,
    double fallback = 0.0,
  }) {
    final thickness = _readPositiveDouble(
      selectedBourrageJointOverride(doubleGlass: doubleGlass)?['thickness'],
    );
    return thickness > 0 ? thickness : fallback;
  }

  double vitrageJointAllowanceForGlass(
    GlassSpecification specification, {
    bool? sliding,
  }) {
    if (specification.fittedJoints.isNotEmpty) {
      return specification.fittedJoints.fold<double>(
        0.0,
        (sum, joint) => sum + _readPositiveDouble(joint['thickness']),
      );
    }
    final jointThickness = selectedVitrageJointThickness();
    if (jointThickness <= 0) return 0.0;
    final usesSliding = sliding ?? systemMode == 'sliding';
    if (usesSliding) {
      return jointThickness * (specification.jointTwoSides ? 2.0 : 1.0);
    }
    return jointThickness +
        selectedBourrageJointThickness(
          doubleGlass: specification.structure == GlassStructure.double,
          fallback: 2.0,
        );
  }

  double glassPackThicknessIncludingVitrageJoint(
    GlassSpecification specification, {
    bool? sliding,
  }) {
    return specification.totalThickness(allGlassCache) +
        vitrageJointAllowanceForGlass(specification, sliding: sliding);
  }

  List<int> _availableIntercallThicknesses() {
    final values =
        availableIntercalls
            .map((item) => _readPositiveDouble(item['thickness']).round())
            .where((thickness) => thickness > 0)
            .toSet()
            .toList()
          ..sort();
    if (values.isNotEmpty) return values;
    return const [6, 8, 10, 12, 14, 16, 18, 20, 22, 24];
  }

  bool get hasSimpleGlassForReducer {
    if (zones.isEmpty) {
      return defaultGlass.structure == GlassStructure.simple;
    }
    for (final zone in zones) {
      for (final spec in _effectiveGlassSpecificationsForZone(zone)) {
        if (spec.structure == GlassStructure.simple) return true;
      }
    }
    return false;
  }

  bool get hasDoubleGlassForRules {
    if (zones.isEmpty) {
      return defaultGlass.structure == GlassStructure.double;
    }
    for (final zone in zones) {
      for (final spec in _effectiveGlassSpecificationsForZone(zone)) {
        if (spec.structure == GlassStructure.double) return true;
      }
    }
    return false;
  }

  /// Resolves the colour actually used by a bardage cell. In automatic mode
  /// it always follows the current frame/series colour; an explicit override
  /// is accepted only when it belongs to the active series colour list.
  Map<String, dynamic>? getBardageColorForSpec(GlassSpecification glass) {
    if (glass.bardageUsesFrameColor) return selectedDbColor;

    final requested = _normalizedProfileColorName(glass.panneauColor ?? '');
    if (requested.isNotEmpty) {
      for (final color in availableColors) {
        if (_normalizedProfileColorName(_profileColorName(color)) ==
            requested) {
          return color;
        }
      }
    }
    return selectedDbColor;
  }

  String getBardageColorNameForSpec(GlassSpecification glass) {
    final resolved = _profileColorName(getBardageColorForSpec(glass));
    if (resolved.isNotEmpty) return resolved;
    final fallback = _profileColorName(selectedDbColor);
    return fallback.isNotEmpty
        ? fallback
        : frameColor.toString().split('.').last;
  }

  /// Returns the physical stock profile used for bardage. New catalogues may
  /// assign it through the generic panneau role, while older ones use the
  /// dedicated bardage role.
  Map<String, dynamic>? getBardageProfileOverride() {
    final specific = componentOverrides['البارداج (Bardage)'];
    if (specific is Map) return Map<String, dynamic>.from(specific);
    final panneau = componentOverrides['البانو (Panneau)'];
    if (panneau is Map &&
        (isBardagePanelSubtype(panneau['type']?.toString()) ||
            isBardagePanelSubtype(panneau['name']?.toString()))) {
      return Map<String, dynamic>.from(panneau);
    }
    for (final series in <AluminumSeries?>[activeSeries, activeSlidingSeries]) {
      if (series == null) continue;
      for (final section in series.sections) {
        if (isBardagePanelSubtype(section.type) ||
            isBardagePanelSubtype(section.name)) {
          return section.toMap();
        }
      }
    }
    return null;
  }

  double get bardageVisibleWidth {
    final profile = getBardageProfileOverride();
    final raw = profile?['visible_width'];
    return raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  /// Reads the price attached to the resolved bardage colour. The complete
  /// colour-price map is cached on the selected bardage profile because BOM
  /// generation is synchronous and may contain several bardage colours.
  double getBardagePriceForColor(
    Map<String, dynamic>? colorData,
    String colorName,
  ) {
    final rawOverride = componentOverrides['البارداج (Bardage)'];
    if (rawOverride is! Map) return 0.0;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawPrices = override['color_prices'];
    if (rawPrices is Map) {
      final colorId = colorData?['id'];
      final keys = <String>[
        if (colorId != null) 'id:$colorId',
        'name:${_normalizedProfileColorName(colorName)}',
      ];
      for (final key in keys) {
        final rawPrice = rawPrices[key];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');
        if (price != null && price >= 0) return price;
      }
    }

    final rawFallback =
        override['calculated_price'] ??
        override['price_dzd'] ??
        override['price'] ??
        0.0;
    return rawFallback is num
        ? rawFallback.toDouble()
        : double.tryParse(rawFallback.toString()) ?? 0.0;
  }

  double getPanneauProfilePriceForColor(
    Map<String, dynamic>? colorData,
    String colorName,
  ) {
    final rawOverride = componentOverrides['البانو (Panneau)'];
    if (rawOverride is! Map) return 0.0;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawPrices = override['color_prices'];
    if (rawPrices is Map) {
      final colorId = colorData?['id'];
      for (final key in <String>[
        if (colorId != null) 'id:$colorId',
        'name:${_normalizedProfileColorName(colorName)}',
      ]) {
        final rawPrice = rawPrices[key];
        final price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');
        if (price != null && price >= 0) return price;
      }
    }
    final rawFallback =
        override['calculated_price'] ??
        override['price_dzd'] ??
        override['price'] ??
        0.0;
    return rawFallback is num
        ? rawFallback.toDouble()
        : double.tryParse(rawFallback.toString()) ?? 0.0;
  }

  Future<void> refreshBardageColorPrices({bool notify = true}) async {
    final rawOverride = componentOverrides['البارداج (Bardage)'];
    if (rawOverride is! Map) return;
    final override = Map<String, dynamic>.from(rawOverride);
    final rawId = override['id'];
    final sectionId = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    if (sectionId == null) return;

    final fallbackRaw = override['price_dzd'] ?? override['price'] ?? 0.0;
    final fallbackPrice = fallbackRaw is num
        ? fallbackRaw.toDouble()
        : double.tryParse(fallbackRaw.toString()) ?? 0.0;
    final prices = <String, double>{};
    for (final color in availableColors) {
      final rawColorId = color['id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse(rawColorId?.toString() ?? '');
      if (colorId == null) continue;
      var price = await db.getSectionPrice(sectionId, colorId);
      if (price <= 0) price = fallbackPrice;
      prices['id:$colorId'] = price;
      final name = _normalizedProfileColorName(_profileColorName(color));
      if (name.isNotEmpty) prices['name:$name'] = price;
    }
    override['color_prices'] = prices;

    final selectedName = _profileColorName(selectedDbColor);
    final selectedId = selectedDbColor?['id'];
    if (selectedId != null && prices.containsKey('id:$selectedId')) {
      override['calculated_price'] = prices['id:$selectedId'];
    } else {
      final selectedKey = 'name:${_normalizedProfileColorName(selectedName)}';
      override['calculated_price'] = prices[selectedKey] ?? fallbackPrice;
    }
    componentOverrides['البارداج (Bardage)'] = override;
    if (notify) _notifyModelListeners();
  }

  Future<void> loadGlassProducts({bool forceRefresh = false}) async {
    if (!forceRefresh && allGlassCache.isNotEmpty) return;
    try {
      final list = await db.readGlass();
      final dbInstance = await db.db;
      List<Map<String, dynamic>> colorPrices = [];
      try {
        colorPrices = await dbInstance!.query('GlassColorPrices');
      } catch (error) {
        reportCatalogIssue('GlassColorPrices', error);
      }

      allGlassCache = [];
      for (var g in list) {
        final typeLower = g['type'].toString().toLowerCase();
        if (typeLower == 'panneau' ||
            typeLower == 'baguette' ||
            typeLower == 'rosette') {
          final colorsStr = g['color']?.toString() ?? '';
          if (colorsStr.isNotEmpty) {
            final colorsList = colorsStr.split(',');
            for (var col in colorsList) {
              final trimmedCol = col.trim();
              if (trimmedCol.isEmpty) continue;
              double specificPrice = 0.0;
              final match = colorPrices.firstWhere(
                (cp) =>
                    cp['glass_id'] == g['id'] &&
                    cp['color_name'].toString().toLowerCase() ==
                        trimmedCol.toLowerCase(),
                orElse: () => <String, dynamic>{},
              );
              if (match.isNotEmpty) {
                specificPrice = (match['price'] as num).toDouble();
              } else {
                specificPrice = (g['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
              }

              final virtualG = Map<String, dynamic>.from(g);
              virtualG['color'] = trimmedCol;
              virtualG['price_per_sqm'] = specificPrice;
              allGlassCache.add(virtualG);
            }
          } else {
            allGlassCache.add(g);
          }
        } else {
          allGlassCache.add(g);
        }
      }

      availableIntercalls = allGlassCache
          .where((g) => g['type'].toString().toLowerCase() == 'intercall')
          .toList();
      availableGases = allGlassCache
          .where((g) => g['type'].toString().toLowerCase() == 'gas')
          .toList();
      _notifyModelListeners();
    } catch (e) {
      debugPrint("Error loading glass products: $e");
    }
  }

  double getPriceForIntercall(int thickness) {
    if (availableIntercalls.isEmpty) return 0.0;
    try {
      final interMatch = availableIntercalls.firstWhere((item) {
        final rawThickness = item['thickness'];
        final itemThickness = rawThickness is num
            ? rawThickness.toInt()
            : int.tryParse(rawThickness?.toString() ?? '');
        return itemThickness == thickness ||
            item['name'].toString().contains(thickness.toString());
      });
      final price = interMatch['price_per_sqm'] ?? interMatch['price'] ?? 0.0;
      return price is num ? price.toDouble() : double.tryParse('$price') ?? 0.0;
    } catch (_) {
      return 0.0; // No match found
    }
  }

  double calculateTotalGlassPricePerSqm() {
    GlassSpecification glass = zones.isNotEmpty
        ? zones.first.glass
        : GlassSpecification();
    return calculateTotalGlassPricePerSqmForZoneGlass(glass);
  }

  double calculateTotalGlassPricePerSqmForZone(WindowZone zone) {
    return calculateTotalGlassPricePerSqmForZoneGlass(zone.glass);
  }

  double calculateTotalGlassPricePerSqmForZoneGlass(GlassSpecification glass) {
    double price = 0.0;
    if (glass.structure == GlassStructure.simple) {
      final thick = glass.thicknessOuter ?? kDefaultGlassPaneThickness;
      if (glass.processingOuter == GlassProcessing.laminated) {
        price = getLaminatedPrice(thick, glass.laminatedColorOuter);
      } else {
        price = getPriceForFinish(
          glass.finishOuter,
          glass.colorOuter,
          chosenThickness: thick,
        );
      }

      // Add tempering price if enabled
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        price += getTemperingPricePerSqm(thick);
      }
    } else if (glass.structure == GlassStructure.double) {
      final thickInner = glass.thicknessInner ?? kDefaultGlassPaneThickness;
      final thickOuter = glass.thicknessOuter ?? kDefaultGlassPaneThickness;

      double innerPrice = 0.0;
      if (glass.processingInner == GlassProcessing.laminated) {
        innerPrice = getLaminatedPrice(thickInner, glass.laminatedColorInner);
      } else {
        innerPrice = getPriceForFinish(
          glass.finishInner,
          glass.colorInner,
          chosenThickness: thickInner,
        );
      }
      if (glass.processingInner == GlassProcessing.tempered ||
          glass.temperedInner) {
        innerPrice += getTemperingPricePerSqm(thickInner);
      }

      double outerPrice = 0.0;
      if (glass.processingOuter == GlassProcessing.laminated) {
        outerPrice = getLaminatedPrice(thickOuter, glass.laminatedColorOuter);
      } else {
        outerPrice = getPriceForFinish(
          glass.finishOuter,
          glass.colorOuter,
          chosenThickness: thickOuter,
        );
      }
      if (glass.processingOuter == GlassProcessing.tempered ||
          glass.temperedOuter) {
        outerPrice += getTemperingPricePerSqm(thickOuter);
      }

      double intercallPrice = getPriceForIntercall(glass.intercallThickness);

      double gasPrice = 0.0;
      if (glass.hasGas) {
        gasPrice = getPriceForGas(glass.intercallThickness);
      }

      price = innerPrice + outerPrice + intercallPrice + gasPrice;
    } else if (glass.structure == GlassStructure.closed) {
      final sub = glass.panneauSubtype ?? '';
      final col = glass.panneauColor ?? '';

      final match = allGlassCache.firstWhere((g) {
        final t = g['type'].toString().toLowerCase();
        final s = (g['subtype'] ?? '').toString().toLowerCase();
        final c = (g['color'] ?? '').toString().toLowerCase();
        final sameSelectedProduct =
            glass.panneauProductId != null &&
            g['id']?.toString() == glass.panneauProductId.toString() &&
            s == sub.toLowerCase();

        return t == 'panneau' &&
            (sameSelectedProduct || s == sub.toLowerCase()) &&
            c == col.toLowerCase();
      }, orElse: () => <String, dynamic>{});

      if (match.isNotEmpty) {
        price = (match['price_per_sqm'] ?? 0.0).toDouble();
      } else {
        final baseMatch = allGlassCache.firstWhere((g) {
          final t = g['type'].toString().toLowerCase();
          final s = (g['subtype'] ?? '').toString().toLowerCase();
          final sameSelectedProduct =
              glass.panneauProductId != null &&
              g['id']?.toString() == glass.panneauProductId.toString() &&
              s == sub.toLowerCase();
          return t == 'panneau' &&
              (sameSelectedProduct || s == sub.toLowerCase());
        }, orElse: () => <String, dynamic>{});
        if (baseMatch.isNotEmpty) {
          price = (baseMatch['price_per_sqm'] ?? 0.0).toDouble();
        }
      }
    }
    return price;
  }

  Map<String, dynamic>? getPanneauProductForSpec(GlassSpecification glass) {
    final selectedId = glass.panneauProductId;
    final selectedColor = (glass.panneauColor ?? '').trim().toLowerCase();
    final subtype = (glass.panneauSubtype ?? '').trim().toLowerCase();
    if (selectedId != null) {
      Map<String, dynamic>? idFallback;
      for (final product in allGlassCache) {
        if (product['type'].toString().toLowerCase() != 'panneau' ||
            product['id']?.toString() != selectedId.toString() ||
            (product['subtype'] ?? '').toString().trim().toLowerCase() !=
                subtype) {
          continue;
        }
        idFallback ??= product;
        final color = (product['color'] ?? '').toString().trim().toLowerCase();
        if (selectedColor.isEmpty || color == selectedColor) return product;
      }
      if (idFallback != null) return idFallback;
    }

    Map<String, dynamic>? subtypeFallback;
    for (final product in allGlassCache) {
      if (product['type'].toString().toLowerCase() != 'panneau' ||
          (product['subtype'] ?? '').toString().trim().toLowerCase() !=
              subtype) {
        continue;
      }
      subtypeFallback ??= product;
      final color = (product['color'] ?? '').toString().trim().toLowerCase();
      if (selectedColor.isEmpty || color == selectedColor) return product;
    }
    return subtypeFallback;
  }

  GlassSpecification _decorSplitFallback(GlassSpecification source) {
    Map<String, dynamic>? resinProduct;
    for (final product in allGlassCache) {
      if ((product['type'] ?? '').toString().trim().toLowerCase() !=
          'panneau') {
        continue;
      }
      final searchable = '${product['name'] ?? ''} ${product['subtype'] ?? ''}'
          .trim()
          .toLowerCase();
      if (searchable.contains('sample resin') ||
          searchable.contains('résine') ||
          searchable.contains('resine') ||
          searchable.contains('ريزين') ||
          searchable.contains('ارزين') ||
          searchable.contains('أرزين')) {
        resinProduct = product;
        break;
      }
    }
    if (resinProduct == null) return const GlassSpecification();

    final rawId = resinProduct['id'];
    final productId = rawId is int ? rawId : int.tryParse('$rawId');
    final subtype = (resinProduct['subtype'] ?? 'résine').toString();
    final availableColors = (resinProduct['color'] ?? '')
        .toString()
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final sourceColor = (source.panneauColor ?? '').trim();
    final color =
        sourceColor.isNotEmpty && availableColors.contains(sourceColor)
        ? sourceColor
        : (availableColors.isEmpty ? sourceColor : availableColors.first);
    final thickness = _catalogDimension(resinProduct, 'thickness');
    return GlassSpecification(
      structure: GlassStructure.closed,
      finishOuter: GlassFinish.resine,
      finishInner: GlassFinish.resine,
      panneauSubtype: subtype,
      panneauColor: color,
      panneauProductId: productId,
      thicknessOuter: thickness > 0 ? thickness : source.thicknessOuter,
      thicknessInner: thickness > 0 ? thickness : source.thicknessInner,
    );
  }

  void _normalizeDecorAfterSplit(
    WindowZone source,
    List<WindowZone> splitZones,
  ) {
    if (splitZones.isEmpty ||
        (!isDecorPanelSubtype(source.glass.panneauSubtype) &&
            source.glass.finishOuter != GlassFinish.paneauSandwitchDecore &&
            (source.glass.decorDesignCode ?? '').trim().isEmpty)) {
      return;
    }
    final product = getPanneauProductForSpec(source.glass);
    if (product == null) {
      final fallback = _decorSplitFallback(source.glass);
      for (final zone in splitZones) {
        zone.glass = fallback.clone();
      }
      return;
    }

    final decorWidth = _catalogDimension(product, 'visible_width');
    final decorHeight = _catalogDimension(product, 'height');
    final panelWidth = _catalogDimension(product, 'panel_width');
    final panelHeight = _catalogDimension(product, 'panel_height');
    final candidates =
        splitZones.where((zone) {
          final width = zone.boundary.width;
          final height = zone.boundary.height;
          final containsDecor =
              decorWidth > 0 &&
              decorHeight > 0 &&
              width + 0.01 >= decorWidth &&
              height + 0.01 >= decorHeight;
          final fitsPanel =
              (panelWidth <= 0 || width <= panelWidth + 0.01) &&
              (panelHeight <= 0 || height <= panelHeight + 0.01);
          return containsDecor && fitsPanel;
        }).toList()..sort(
          (a, b) => (b.boundary.width * b.boundary.height).compareTo(
            a.boundary.width * a.boundary.height,
          ),
        );

    final keeper = candidates.isEmpty ? null : candidates.first;
    final fallback = _decorSplitFallback(source.glass);
    for (final zone in splitZones) {
      zone.glass = identical(zone, keeper)
          ? source.glass.clone()
          : fallback.clone();
    }
  }

  bool _isParcloseSection(AluminumSection section) {
    final type = section.type.toLowerCase();
    final name = section.name.toLowerCase();
    return section.code.trim() == '514' ||
        type.contains('parclose') ||
        name.contains('parclose') ||
        type.contains('باكيت') ||
        name.contains('باكيت');
  }

  /// The cut rule of the opening parclose: the one the user chose, else the
  /// rule every parclose of the series shares, else every cut is possible.
  /// Read from the current catalogue so older saved selections without the
  /// rule columns still follow it.
  ParcloseCutRule get parcloseCutRule {
    final series = activeSeries;
    if (series == null) return const ParcloseCutRule();
    var beads = getConfiguredSectionsForRole('glazing_bead');
    if (beads.isEmpty && !seriesHasConfiguredRoles(series)) {
      beads = series.sections.where(_isParcloseSection).toList();
    }
    final chosen = componentOverrides['باكيت الزجاج (Parclose)'];
    final chosenId = chosen is Map
        ? int.tryParse('${chosen['id'] ?? ''}')
        : null;
    if (chosenId != null) {
      for (final section in [...beads, ...series.sections]) {
        if (section.id == chosenId) return section.parcloseCutRule;
      }
    }
    final rules = beads.map((bead) => bead.parcloseCutRule).toSet();
    return rules.length == 1 ? rules.first : const ParcloseCutRule();
  }

  /// Whether this catalogue actually retains glazing with a parclose.  A
  /// configured (but empty) glazing-bead role means that the sash itself is
  /// the glazing pocket; never fall back to an unrelated legacy parclose.
  bool hasGlazingBeadForContext({bool? sliding}) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return false;
    final configured = getConfiguredSectionsForRole(
      'glazing_bead',
      useSlidingSeries: useSliding,
    );
    if (configured.isNotEmpty) return true;
    if (seriesHasConfiguredRoles(series)) return false;
    return series.sections.any(_isParcloseSection);
  }

  double? sashGlassCapacityForContext({bool? sliding}) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final sash = useSliding
        ? slidingSashOverride ??
              getSlidingSectionByType('sash_sliding')?.toMap() ??
              getSlidingSectionByType('sash')?.toMap()
        : sashOverride ?? getSectionByType('sash')?.toMap();
    // Saved drawings contain a snapshot of the section. Capacity is catalogue
    // metadata, not a drawing override: refresh it by the same section ID.
    final series = useSliding ? effectiveSlidingSeries : activeSeries;
    final selectedId = int.tryParse('${sash?['id'] ?? ''}');
    AluminumSection? currentSection;
    if (selectedId != null && series != null) {
      for (final section in series.sections) {
        if (section.id == selectedId) {
          currentSection = section;
          break;
        }
      }
    }
    final raw =
        currentSection?.maxGlassThickness ?? sash?['max_glass_thickness'];
    final capacity = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    return capacity != null && capacity > 0 ? capacity : null;
  }

  /// The usable glazing pocket.  With a real parclose its capacity wins; in
  /// series without parclose the selected sash's max-glass field is the sole
  /// source of truth.
  double? glazingCapacityForStructure(
    GlassStructure structure, {
    bool? sliding,
    GlassSpecification? glass,
  }) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    if (hasGlazingBeadForContext(sliding: useSliding)) {
      return parcloseCapacityForStructure(
        structure,
        sliding: useSliding,
        glass: glass,
      );
    }
    return sashGlassCapacityForContext(sliding: useSliding);
  }

  /// The thinnest pack this glass can be glazed with: its panes (double
  /// glazing with the thinnest spacer, since the spacer adapts to the bead)
  /// plus the vitrage/bourrage gaskets for aluminium. A PVC bead holds the
  /// glass without separate gaskets.
  ///
  /// [glassThickness], when given, is the measured glass (or panel) thickness
  /// of a drawn pane and replaces the estimate from [spec].
  double minimumGlazingPack(
    GlassSpecification spec, {
    required bool sliding,
    double? glassThickness,
  }) {
    final double glass = glassThickness != null && glassThickness > 0
        ? glassThickness
        : spec.structure == GlassStructure.double
        ? _glassPaneThicknessOrDefault(spec.thicknessOuter) +
              _glassPaneThicknessOrDefault(spec.thicknessInner) +
              _availableIntercallThicknesses().first
        : spec.totalThickness(allGlassCache);
    final pvc = sliding ? isSlidingPVC : isPVC;
    if (pvc) return glass;
    final joint = selectedVitrageJointThickness(fallback: 2.0);
    return glass + joint * (spec.jointTwoSides ? 2 : 1);
  }

  /// The thickest pack this glass can be glazed with: the largest spacer for
  /// double glazing and the thickest gaskets. A bead beyond it cannot be
  /// filled (a simple pane in a double bead).
  double maximumGlazingPack(
    GlassSpecification spec, {
    required bool sliding,
    double? glassThickness,
  }) {
    final measured = glassThickness != null && glassThickness > 0
        ? glassThickness
        : 0.0;
    final double glass = spec.structure == GlassStructure.double
        ? math.max(
            measured,
            _glassPaneThicknessOrDefault(spec.thicknessOuter) +
                _glassPaneThicknessOrDefault(spec.thicknessInner) +
                _availableIntercallThicknesses().last,
          )
        : (measured > 0 ? measured : spec.totalThickness(allGlassCache));
    // The gasket allowance also bounds PVC: a bead slightly larger than the
    // pane is reported with a pane suggestion, a double bead is never used
    // for a simple pane.
    return glass + kMaxGlazingGasketMm * (spec.jointTwoSides ? 2 : 1);
  }

  /// The parclose (glazing bead) that holds [spec]: a bead the user chose for
  /// this glass type while the pack fits it, otherwise the smallest bead of
  /// the series that can hold the pack. Simple and double beads are told apart
  /// by their catalogue rule and their capacity, never by a fixed threshold,
  /// so a simple bead that also counts its gaskets is not taken for a double.
  AluminumSection? glazingBeadForGlass(
    GlassSpecification spec, {
    required bool sliding,
    double? glassThickness,
  }) {
    final series = sliding ? activeSlidingSeries : activeSeries;
    if (series == null || !hasGlazingBeadForContext(sliding: sliding)) {
      return null;
    }
    final glassRule = switch (spec.structure) {
      GlassStructure.double => 'double',
      GlassStructure.simple => 'simple',
      GlassStructure.closed => null,
    };
    var beads = getConfiguredSectionsForRole(
      'glazing_bead',
      useSlidingSeries: sliding,
      showWhenGlass: glassRule,
    );
    if (beads.isEmpty && !seriesHasConfiguredRoles(series)) {
      beads = series.sections.where(_isParcloseSection).toList();
    }
    beads = beads.where((bead) => bead.maxGlassThickness > 0).toList();
    if (beads.isEmpty) return null;
    final requiredPack = minimumGlazingPack(
      spec,
      sliding: sliding,
      glassThickness: glassThickness,
    );
    bool holds(AluminumSection bead) =>
        bead.maxGlassThickness + 1.000001 >= requiredPack;
    int? idOf(dynamic row) =>
        row is Map ? int.tryParse('${row['id'] ?? ''}') : null;
    AluminumSection? beadWithId(int? id) {
      if (id == null) return null;
      for (final bead in beads) {
        if (bead.id == id) return bead;
      }
      return null;
    }

    final specificKey = switch ((spec.structure, sliding)) {
      (GlassStructure.double, false) => 'باكيت زجاج مزدوج (Parclose Double)',
      (GlassStructure.double, true) =>
        'باكيت زجاج منزلق مزدوج (Parclose Double Coulissant)',
      (GlassStructure.simple, false) => 'باكيت زجاج مفرد (Parclose Simple)',
      (GlassStructure.simple, true) =>
        'باكيت زجاج منزلق مفرد (Parclose Simple Coulissant)',
      _ => null,
    };
    final chosen = beadWithId(
      specificKey == null ? null : idOf(componentOverrides[specificKey]),
    );
    if (chosen != null && holds(chosen)) return chosen;

    final generic = componentOverrides['باكيت الزجاج (Parclose)'];
    if (spec.structure == GlassStructure.double && generic is Map) {
      final linked = beadWithId(
        int.tryParse('${generic['linked_parclose_double_id'] ?? ''}'),
      );
      if (linked != null && holds(linked)) return linked;
    }
    final genericId = idOf(generic);
    return smallestFittingGlazingBead(
      beads,
      (bead) => bead.maxGlassThickness,
      requiredPack: requiredPack,
      maximumPack: maximumGlazingPack(
        spec,
        sliding: sliding,
        glassThickness: glassThickness,
      ),
      preferred: (bead) => bead.id == genericId,
    );
  }

  double? parcloseCapacityForStructure(
    GlassStructure structure, {
    bool? sliding,
    GlassSpecification? glass,
  }) {
    final useSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone?.content == ZoneContent.slidingSash));
    final current =
        glass ?? selectedZone?.getGlassForCell(activeSubZone);
    final spec = current != null && current.structure == structure
        ? current
        : GlassSpecification(structure: structure);
    return glazingBeadForGlass(spec, sliding: useSliding)?.maxGlassThickness;
  }

  /// The selected parclose defines the usable thickness of the glazing pack.
  /// If the user has not selected one explicitly, the first double-glazing
  /// parclose configured for the active frame series is the catalogue
  /// default.  This keeps the glass drawer and the material calculation on
  /// the same default profile.
  double? get selectedParcloseMaxGlassThickness {
    double? capacityOf(Map<String, dynamic> parclose) {
      final rawValue = parclose['max_glass_thickness'];
      final maximum = rawValue is num
          ? rawValue.toDouble()
          : double.tryParse(rawValue?.toString() ?? '');
      return maximum != null && maximum > 0 ? maximum : null;
    }

    final series = activeFrameSeries;
    var requiredDoubleThickness = 0.0;
    for (final zone in zones) {
      for (final glass in [zone.glass, ...zone.cellGlassSpec.values]) {
        if (glass.structure != GlassStructure.double) continue;
        // Parclose capacity describes the sealed unit itself. Vitrage and
        // bourrage joints retain it, but are not part of its thickness.
        final paneThickness =
            _glassPaneThicknessOrDefault(glass.thicknessOuter) +
            _glassPaneThicknessOrDefault(glass.thicknessInner);
        requiredDoubleThickness = math.max(
          requiredDoubleThickness,
          paneThickness + _availableIntercallThicknesses().first,
        );
      }
    }
    final bool needsDoubleParclose = requiredDoubleThickness > 0;
    final double minimumDoubleCapacity = math.max(
      10.0,
      requiredDoubleThickness,
    );

    // First use a real, explicitly selected parclose only when it can hold
    // the current glazing.  A stale 5 mm single-glazing parclose must not
    // make the drawer hide the spacer after the user switches to double
    // glazing; the quantity table already resolves a double parclose in this
    // situation.
    for (final entry in componentOverrides.entries) {
      if (!entry.key.toLowerCase().contains('parclose') ||
          entry.value is! Map) {
        continue;
      }
      final selected = Map<String, dynamic>.from(entry.value as Map);
      final capacity = capacityOf(selected);
      if (capacity != null &&
          (!needsDoubleParclose || capacity >= minimumDoubleCapacity)) {
        return capacity;
      }

      if (needsDoubleParclose && series != null) {
        final rawLinkedId = selected['linked_parclose_double_id'];
        final linkedId = rawLinkedId is num
            ? rawLinkedId.toInt()
            : int.tryParse(rawLinkedId?.toString() ?? '');
        if (linkedId != null) {
          for (final section in series.sections) {
            if (section.id == linkedId &&
                section.maxGlassThickness >= minimumDoubleCapacity) {
              return section.maxGlassThickness;
            }
          }
        }
      }
    }

    if (series == null) return null;
    // With double glazing use the smallest parclose that can contain the
    // current glazing pack. If the glass grows past the selected parclose, it
    // moves to the next larger catalogue capacity.
    if (needsDoubleParclose) {
      final candidates =
          series.sections.where((section) {
            final type = section.type.toLowerCase();
            final name = section.name.toLowerCase();
            final isParclose =
                type.contains('parclose') ||
                name.contains('parclose') ||
                name.contains('باكيت');
            return isParclose &&
                section.maxGlassThickness >= minimumDoubleCapacity;
          }).toList()..sort(
            (a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness),
          );
      return candidates.isEmpty ? null : candidates.first.maxGlassThickness;
    }

    // No double glazing: use the smallest parclose that fits the glass/panel.
    final allParcloses =
        series.sections.where((s) {
            final type = s.type.toLowerCase();
            final name = s.name.toLowerCase();
            return (type.contains('parclose') ||
                    name.contains('parclose') ||
                    name.contains('باكيت')) &&
                s.maxGlassThickness > 0;
          }).toList()
          ..sort((a, b) => a.maxGlassThickness.compareTo(b.maxGlassThickness));

    final activeGlass = selectedZone?.glass;
    final double requiredThick = activeGlass != null
        ? activeGlass.totalThickness(allGlassCache)
        : 5.0;

    for (final s in allParcloses) {
      if (s.maxGlassThickness >= requiredThick) {
        return s.maxGlassThickness;
      }
    }
    return allParcloses.isNotEmpty
        ? allParcloses.first.maxGlassThickness
        : null;
  }

  /// Calculates the spacer that makes a double-glazing pack fit the selected
  /// parclose exactly. It intentionally returns null when the two panes alone
  /// already fill or exceed the capacity, so an impossible spacer is never
  /// written silently.
  int? suggestedIntercallThicknessForDoubleGlass({
    required double thicknessOuter,
    required double thicknessInner,
    bool jointTwoSides = true,
    double? jointThickness,
    bool? sliding,
  }) {
    final selectedUsesSliding =
        sliding ??
        (systemMode == 'sliding' ||
            (selectedZone != null
                ? selectedZone!.content == ZoneContent.slidingSash
                : usesSlidingPrimaryProfiles));
    final maximum = glazingCapacityForStructure(
      GlassStructure.double,
      sliding: selectedUsesSliding,
    );
    if (maximum == null) return null;
    // The capacity holds the whole pack: in aluminium the vitrage and
    // bourrage gaskets sit in it beside the panes; a PVC bead has none.
    final pvc = selectedUsesSliding ? isSlidingPVC : isPVC;
    final joints = pvc
        ? 0.0
        : (jointThickness ?? selectedVitrageJointThickness(fallback: 2.0)) *
              (jointTwoSides ? 2 : 1);
    return _spacerFillingGap(
      maximum - thicknessOuter - thicknessInner - joints,
    );
  }

  /// Recalculates each double-glazing spacer after the user selects another
  /// parclose. The spacer is a consequence of the glazing panes and the
  /// parclose capacity, rather than a free manual choice.
  void fitDoubleGlassIntercallsToSelectedParclose() {
    var changed = false;

    GlassSpecification fit(
      GlassSpecification specification, {
      required bool sliding,
    }) {
      if (specification.structure != GlassStructure.double ||
          specification.manualIntercall) {
        return specification;
      }
      final suggested = suggestedIntercallThicknessForDoubleGlass(
        thicknessOuter:
            specification.thicknessOuter ?? kDefaultGlassPaneThickness,
        thicknessInner:
            specification.thicknessInner ?? kDefaultGlassPaneThickness,
        jointTwoSides: specification.jointTwoSides,
        sliding: sliding,
      );
      if (suggested == null || suggested == specification.intercallThickness) {
        return specification;
      }
      changed = true;
      return specification.copyWith(intercallThickness: suggested);
    }

    for (final zone in zones) {
      final zoneUsesSliding =
          systemMode == 'sliding' || zone.content == ZoneContent.slidingSash;
      zone.glass = fit(zone.glass, sliding: zoneUsesSliding);
      if (zone.cellGlassSpec.isNotEmpty) {
        zone.cellGlassSpec = zone.cellGlassSpec.map(
          (key, value) => MapEntry(key, fit(value, sliding: zoneUsesSliding)),
        );
      }
    }

    if (changed) _notifyModelListeners();
  }

  double? _parcloseCapacity(Map<String, dynamic>? parclose) {
    if (parclose == null) return null;
    final rawValue = parclose['max_glass_thickness'];
    final value = rawValue is num
        ? rawValue.toDouble()
        : double.tryParse(rawValue?.toString() ?? '');
    return value != null && value > 0 ? value : null;
  }

  bool _isVitrageJointRow(Map<String, dynamic> joint) {
    final text =
        '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
            .toLowerCase();
    return text.contains('vitrage') ||
        text.contains('فيتراج') ||
        text.contains('زجاج') ||
        text.contains('glass');
  }

  Future<double> _resolveVitrageJointThicknessForRules({
    required bool jointTwoSides,
  }) async {
    final selectedThickness = selectedVitrageJointThickness();
    if (selectedThickness > 0) {
      _lastResolvedVitrageJointThickness = selectedThickness;
      return selectedThickness;
    }

    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final activeSeriesForSash = useSliding ? activeSlidingSeries : activeSeries;
    final activeSashMap = useSliding
        ? slidingSashOverride ??
              getSlidingSectionByType('sash_sliding')?.toMap() ??
              getSlidingSectionByType('sash')?.toMap()
        : sashOverride ?? getSectionByType('sash')?.toMap();
    final rawActiveSashId = activeSashMap?['id'];
    final activeSashId = rawActiveSashId is num
        ? rawActiveSashId.toInt()
        : int.tryParse(rawActiveSashId?.toString() ?? '');

    final dbInstance = SqlDatabase();
    if (activeSeriesForSash != null && activeSashId != null) {
      final positions = jointTwoSides
          ? const ['sash_inner', 'sash_outer', 'sash_glass', 'all']
          : const ['sash_inner', 'sash_glass', 'all'];
      final linkedRows = await dbInstance.getDefaultJointsForSection(
        seriesId: activeSeriesForSash.id,
        sectionId: activeSashId,
        positionKeys: positions,
      );
      for (final row in linkedRows) {
        final joint = Map<String, dynamic>.from(row);
        final thickness = _readPositiveDouble(joint['thickness']);
        if (thickness > 0 && _isVitrageJointRow(joint)) {
          _lastResolvedVitrageJointThickness = thickness;
          return thickness;
        }
      }
    }

    final joints = await dbInstance.readJoints();
    final candidates =
        joints
            .map((row) => Map<String, dynamic>.from(row))
            .where(_isVitrageJointRow)
            .where(
              (joint) =>
                  _catalogRowMatchesSeriesScope(joint, activeSeriesForSash),
            )
            .map((joint) => _readPositiveDouble(joint['thickness']))
            .where((thickness) => thickness > 0)
            .toList()
          ..sort();
    final resolved = candidates.isEmpty ? 0.0 : candidates.first;
    _lastResolvedVitrageJointThickness = resolved;
    return resolved;
  }

  /// Ensures that double glazing is paired with a parclose that can contain
  /// both panes and a real spacer. This is deliberately called from the data
  /// model (not only from the drawer), so painting, imports and future screens
  /// cannot save an incompatible glazing combination.
  Future<bool> _ensureParcloseForGlass({
    required GlassStructure structure,
    required double glassThickness,
    bool jointTwoSides = true,
    double? jointThickness,
  }) async {
    final current = componentOverrides['باكيت الزجاج (Parclose)'];
    final currentParclose = current is Map
        ? Map<String, dynamic>.from(current)
        : null;
    final currentCapacity = _parcloseCapacity(currentParclose);

    final needsDoubleParclose = structure == GlassStructure.double;
    if (!needsDoubleParclose && structure != GlassStructure.simple) {
      return false;
    }
    final currentCode = currentParclose?['code']?.toString().trim();
    final effectiveJointThickness =
        jointThickness ??
        await _resolveVitrageJointThicknessForRules(
          jointTwoSides: jointTwoSides,
        );
    final selectedUsesSliding =
        systemMode == 'sliding' ||
        (selectedZone != null
            ? selectedZone!.content == ZoneContent.slidingSash
            : usesSlidingPrimaryProfiles);
    // A sash-only series has no parclose to select. Its own max-glass
    // thickness is enforced by the drawer/calculation, without mutating the
    // catalogue selection or inserting a phantom glazing bead.
    if (!hasGlazingBeadForContext(sliding: selectedUsesSliding)) {
      return false;
    }
    final jointAllowance = selectedUsesSliding
        ? effectiveJointThickness * (jointTwoSides ? 2.0 : 1.0)
        : effectiveJointThickness +
              selectedBourrageJointThickness(
                doubleGlass: needsDoubleParclose,
                fallback: 2.0,
              );
    final glassPackWithJoint = glassThickness + jointAllowance;
    final requiredCapacity = needsDoubleParclose
        ? math.max(10.0, glassPackWithJoint)
        : glassPackWithJoint;
    final currentTooSmall =
        currentCapacity == null || currentCapacity < requiredCapacity;
    final needsReplacement = needsDoubleParclose
        ? currentTooSmall || currentCapacity <= 10.0
        : currentTooSmall ||
              (requiredCapacity <= 10.0 &&
                  (currentCapacity > 10.0 || currentCode != '514'));
    if (!needsReplacement) return false;

    final seriesId = activeFrameSeries?.id;
    if (seriesId == null) return false;

    final dbInstance = SqlDatabase();
    final database = await dbInstance.db;
    if (database == null) return false;

    Future<void> selectParclose(Map<String, dynamic> row) async {
      final selected = Map<String, dynamic>.from(row);
      final id = selected['id'] as int?;
      if (id != null) {
        selected['calculated_price'] = await dbInstance.getSectionPrice(
          id,
          selectedDbColor?['id'],
        );
      }
      componentOverrides['باكيت الزجاج (Parclose)'] = selected;
    }

    if (needsDoubleParclose) {
      // Prefer the explicitly linked double parclose of the current profile
      // when it is large enough for the selected panes.
      final rawLinkedId = currentParclose?['linked_parclose_double_id'];
      final linkedId = rawLinkedId is num
          ? rawLinkedId.toInt()
          : int.tryParse(rawLinkedId?.toString() ?? '');
      if (linkedId != null && linkedId > 0) {
        final linkedRows = await database.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [linkedId],
          limit: 1,
        );
        if (linkedRows.isNotEmpty) {
          final linked = Map<String, dynamic>.from(linkedRows.first);
          if ((_parcloseCapacity(linked) ?? 0) >= requiredCapacity) {
            await selectParclose(linked);
            return true;
          }
        }
      }

      final rows = await database.query(
        'Sections',
        where:
            'series_id = ? AND (LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ?) AND max_glass_thickness > ?',
        whereArgs: [
          seriesId,
          'parclose',
          '%parclose%',
          '%باكيت%',
          requiredCapacity - 0.001,
        ],
        // Pick the next larger capacity, not the largest available profile.
        orderBy: 'max_glass_thickness ASC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        await selectParclose(Map<String, dynamic>.from(rows.first));
        return true;
      }
      return false;
    }

    // Keep the existing simple-glass behaviour, but return from a double
    // parclose to a compatible single one when the glazing becomes simple.
    final rows = await database.query(
      'Sections',
      where:
          "series_id = ? AND (LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR TRIM(code) = ?) AND (COALESCE(max_glass_thickness, 0) >= ? OR (TRIM(code) = '514' AND ? <= 10.0))",
      whereArgs: [
        seriesId,
        'parclose',
        '%parclose%',
        '%باكيت%',
        '514',
        requiredCapacity,
        requiredCapacity,
      ],
      orderBy:
          "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, max_glass_thickness ASC",
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await selectParclose(Map<String, dynamic>.from(rows.first));
      return true;
    }
    return false;
  }

  Future<bool> _ensureParcloseForCurrentGlass() async {
    if (seriesHasConfiguredRoles(activeFrameSeries)) {
      return false;
    }

    GlassStructure? targetStructure;
    double targetThickness = 0.0;
    bool targetJointTwoSides = true;

    for (final zone in zones) {
      if (zone.content == ZoneContent.empty) continue;
      for (final specification in _effectiveGlassSpecificationsForZone(zone)) {
        if (specification.structure == GlassStructure.closed) continue;
        if (specification.structure == GlassStructure.double) {
          targetStructure = GlassStructure.double;
          targetThickness = math.max(
            targetThickness,
            specification.totalThickness(allGlassCache),
          );
          targetJointTwoSides = specification.jointTwoSides;
        } else if (targetStructure != GlassStructure.double &&
            specification.structure == GlassStructure.simple) {
          targetStructure = GlassStructure.simple;
          targetThickness = math.max(
            targetThickness,
            specification.thicknessOuter ?? kDefaultGlassPaneThickness,
          );
          targetJointTwoSides = specification.jointTwoSides;
        }
      }
    }

    if (targetStructure == null) return false;
    final changed = await _ensureParcloseForGlass(
      structure: targetStructure,
      glassThickness: targetThickness,
      jointTwoSides: targetJointTwoSides,
    );
    if (changed && targetStructure == GlassStructure.double) {
      fitDoubleGlassIntercallsToSelectedParclose();
    }
    return changed;
  }

  /// Returns the configuration to preselect in the glass drawer.
  ///
  /// This checks the effective glass of every visible cell, including per-cell
  /// overrides. A null result means the drawing has different glass types (or
  /// no glass), so the drawer must remain at its neutral default state.
  GlassSpecification? getUniformGlassSpecification() {
    GlassSpecification? firstSpecification;

    for (final zone in zones) {
      if (zone.content == ZoneContent.empty) continue;

      for (final specification in _effectiveGlassSpecificationsForZone(zone)) {
        if (firstSpecification == null) {
          firstSpecification = specification;
        } else if (!firstSpecification.hasSameConfigurationAs(specification)) {
          return null;
        }
      }
    }

    return firstSpecification?.clone();
  }

  List<GlassSpecification> _effectiveGlassSpecificationsForZone(
    WindowZone zone,
  ) {
    final cellKeys = <String>[];

    if (zone.content == ZoneContent.slidingSash) {
      final sashCount = zone.slidingSashesCount.clamp(2, 4).toInt();
      for (var sashIndex = 0; sashIndex < sashCount; sashIndex++) {
        cellKeys.add('main_cell_0_$sashIndex');
      }
    } else if (zone.content == ZoneContent.doubleSash) {
      for (var row = 0; row <= zone.innerH; row++) {
        for (var column = 0; column <= zone.innerV; column++) {
          cellKeys.add('left_cell_${row}_$column');
        }
      }
      for (var row = 0; row <= zone.rightInnerH; row++) {
        for (var column = 0; column <= zone.rightInnerV; column++) {
          cellKeys.add('right_cell_${row}_$column');
        }
      }
    } else {
      for (var row = 0; row <= zone.innerH; row++) {
        for (var column = 0; column <= zone.innerV; column++) {
          cellKeys.add('main_cell_${row}_$column');
        }
      }
    }

    return cellKeys
        .map((cellKey) {
          final specification = zone.getGlassForCell(cellKey);
          // Older drawings can mark a cell as a panel separately from its glass
          // specification. Treat that marker as a closed/panel choice here too,
          // so it never appears in the drawer as ordinary glass.
          if (zone.cellIsPanel[cellKey] == true &&
              specification.structure != GlassStructure.closed) {
            return specification.copyWith(structure: GlassStructure.closed);
          }
          return specification;
        })
        .toList(growable: false);
  }

  void setSelectedZonePanelFinish(GlassFinish finish) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    zone.glass = zone.glass.copyWith(
      finishOuter: finish,
      finishInner: finish,
      structure: GlassStructure.closed,
    );
    _notifyModelListeners();
  }

  /// A painted glass keeps its panes but its spacer and gaskets follow the
  /// bead of the zone it lands on (a 5/12/5 brush on an 18 mm bead => 5/8/5).
  Future<void> _refitPaintedGlass(WindowZone zone, String? cellId) async {
    try {
      final sliding = zone.content == ZoneContent.slidingSash;
      final cell = cellId != null && cellId.contains('cell_') ? cellId : null;
      final current = cell == null ? zone.glass : zone.getGlassForCell(cell);
      final fitted = await fitGlazingByRules(current, sliding: sliding);
      if (!zones.contains(zone)) return;
      if (cell == null) {
        if (!identical(zone.glass, current)) return;
        zone.glass = fitted;
      } else {
        if (!identical(zone.cellGlassSpec[cell], current)) return;
        zone.cellGlassSpec = {...zone.cellGlassSpec, cell: fitted};
      }
      _notifyModelListeners();
    } catch (_) {
      // The catalogue may be unavailable; the painted glass stays as drawn.
    }
  }

  /// Applies a bulk glazing choice through the same model path used by the
  /// drawing screen, including automatic parclose and spacer compatibility.
  Future<void> applyGlassSpecificationToAllZones(
    GlassSpecification spec,
  ) async {
    paintAllZonesSpec(spec);
    for (final zone in List<WindowZone>.from(zones)) {
      zone.glass = await fitGlazingByRules(
        zone.glass,
        sliding: zone.content == ZoneContent.slidingSash,
      );
      for (final key in zone.cellGlassSpec.keys.toList()) {
        zone.cellGlassSpec[key] = await fitGlazingByRules(
          zone.cellGlassSpec[key]!,
          sliding: zone.content == ZoneContent.slidingSash,
        );
      }
    }
    _notifyModelListeners();
  }

  GlassColor _resolveGlassColorAfterEdit({
    required GlassStructure targetStructure,
    required GlassFinish targetFinish,
    required GlassColor currentColor,
    required GlassStructure? requestedStructure,
    required GlassFinish? requestedFinish,
    required GlassColor? requestedColor,
  }) {
    if (requestedColor != null) return requestedColor;
    if (targetStructure == GlassStructure.closed) return currentColor;
    if (requestedFinish != null && requestedFinish != GlassFinish.stopSol) {
      return GlassColor.transparent;
    }
    if (requestedStructure != null && targetFinish != GlassFinish.stopSol) {
      return GlassColor.transparent;
    }
    return currentColor;
  }

  void toggleSelectedCellPanel() {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlyPanel = zone.cellIsPanel[activeSubZone!] ?? false;
      Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
      updatedCells[activeSubZone!] = !isCurrentlyPanel;
      zone.cellIsPanel = updatedCells;

      // If it becomes a panel, it cannot be a sash or double sash
      if (updatedCells[activeSubZone!] == true) {
        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[activeSubZone!] = false;
        zone.cellIsSash = updatedSashes;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[activeSubZone!] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
    } else if (zone.content == ZoneContent.empty ||
        zone.content == ZoneContent.fixedGlass) {
      if (zone.glass.structure == GlassStructure.closed) {
        zone.glass = zone.glass.copyWith(structure: GlassStructure.simple);
      } else {
        zone.content = ZoneContent.fixedGlass;
        final currentFinish = zone.glass.finishOuter;
        final GlassFinish targetFinish =
            (currentFinish == GlassFinish.paneauSandwitch ||
                currentFinish == GlassFinish.resine ||
                currentFinish == GlassFinish.paneauSandwitchDecore ||
                currentFinish == GlassFinish.bardage ||
                currentFinish == GlassFinish.plexyGlass)
            ? currentFinish
            : GlassFinish.paneauSandwitch;

        zone.glass = zone.glass.copyWith(
          structure: GlassStructure.closed,
          finishInner: targetFinish,
          finishOuter: targetFinish,
          colorP: ClosedGlassColor.white,
        );
      }
    }
    _notifyModelListeners();
  }

  void paintCellPanel(String zoneId, String cellId, bool isPanel) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
      updatedCells[cellId] = isPanel;
      zone.cellIsPanel = updatedCells;

      if (isPanel) {
        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[cellId] = false;
        zone.cellIsSash = updatedSashes;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[cellId] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
      _notifyModelListeners();
    } catch (_) {}
  }

  Future<void> updateSelectedZoneGlass({
    GlassStructure? structure,
    GlassFinish? finishOuter,
    GlassFinish? finishInner,
    GlassColor? colorOuter,
    GlassColor? colorInner,
    GlassProcessing? processingOuter,
    GlassProcessing? processingInner,
    ClosedGlassColor? colorP,
    bool? hasGas,
    int? intercallThickness,
    String? panneauSubtype,
    String? panneauColor,
    bool? isVerticalBardage,
    bool? bardageUsesFrameColor,
    int? panneauProductId,
    String? decorDesignCode,
    double? thicknessOuter,
    double? thicknessInner,
    String? laminatedColorOuter,
    String? laminatedColorInner,
    bool? temperedOuter,
    bool? temperedInner,
    bool manualIntercall = false,
  }) async {
    // Keep a stable target while selecting a compatible parclose performs its
    // asynchronous catalogue lookup.  The drawer may rebuild during that
    // lookup, but changing glass must never make the selected zone disappear.
    final zone = selectedZone;
    if (zone == null) return;
    final selectedZoneId = zone.id;
    _saveSnapshot();

    final targetCellKey = activeSubZone;
    final baseSpec = (targetCellKey != null && targetCellKey.isNotEmpty)
        ? zone.getGlassForCell(targetCellKey)
        : zone.glass;

    final targetStructure = structure ?? baseSpec.structure;
    final targetFinishOuter = finishOuter ?? baseSpec.finishOuter;
    final targetFinishInner = finishInner ?? baseSpec.finishInner;
    final resolvedColorOuter = _resolveGlassColorAfterEdit(
      targetStructure: targetStructure,
      targetFinish: targetFinishOuter,
      currentColor: baseSpec.colorOuter,
      requestedStructure: structure,
      requestedFinish: finishOuter,
      requestedColor: colorOuter,
    );
    final resolvedColorInner = _resolveGlassColorAfterEdit(
      targetStructure: targetStructure,
      targetFinish: targetFinishInner,
      currentColor: baseSpec.colorInner,
      requestedStructure: structure,
      requestedFinish: finishInner,
      requestedColor: colorInner,
    );
    double? resolvedThicknessOuter = thicknessOuter;
    double? resolvedThicknessInner = thicknessInner;
    final switchingToDouble =
        targetStructure == GlassStructure.double &&
        baseSpec.structure != GlassStructure.double;

    if (targetStructure == GlassStructure.double) {
      resolvedThicknessOuter ??=
          (switchingToDouble ? kDefaultGlassPaneThickness : null) ??
          baseSpec.thicknessOuter ??
          getThicknessForFinish(targetFinishOuter, resolvedColorOuter);
      resolvedThicknessInner ??=
          (switchingToDouble ? kDefaultGlassPaneThickness : null) ??
          baseSpec.thicknessInner ??
          getThicknessForFinish(targetFinishInner, resolvedColorInner);
    } else {
      resolvedThicknessOuter ??=
          baseSpec.thicknessOuter ??
          getThicknessForFinish(targetFinishOuter, resolvedColorOuter);
    }
    final effectiveThicknessOuter = resolvedThicknessOuter;
    final effectiveThicknessInner =
        resolvedThicknessInner ?? kDefaultGlassPaneThickness;

    // The pane selection controls the parclose and normally suggests an
    // Intercall. A spacer explicitly chosen by the user is preserved and is
    // shown with a compatibility warning in the drawing drawer.

    // Gas is part of the usual double-glazing pack. It starts enabled when
    // the user changes a cell to double glass, while an explicit switch-off
    // remains untouched on later edits.
    final resolvedHasGas =
        hasGas ??
        (structure == GlassStructure.double &&
                baseSpec.structure != GlassStructure.double
            ? true
            : null);
    int? resolvedIntercallThickness = intercallThickness;
    // A spacer picked by the user stays (with a warning when it does not
    // fit); new panes or another glass type hand it back to the automatic
    // choice.
    final bool? resolvedManualIntercall = manualIntercall
        ? true
        : (structure != null ||
                  thicknessOuter != null ||
                  thicknessInner != null
              ? false
              : null);
    if (resolvedIntercallThickness == null &&
        targetStructure == GlassStructure.double) {
      final isSliding =
          zone.content == ZoneContent.slidingSash || systemMode == 'sliding';
      final maxCap = glazingCapacityForStructure(
        GlassStructure.double,
        sliding: isSliding,
      );
      final tOuter = effectiveThicknessOuter ?? kDefaultGlassPaneThickness;
      final tInner = effectiveThicknessInner;
      final currentTotal = tOuter + baseSpec.intercallThickness + tInner;
      final keepsManualSpacer =
          resolvedManualIntercall ?? baseSpec.manualIntercall;
      if (!keepsManualSpacer &&
          (baseSpec.structure != GlassStructure.double ||
              resolvedManualIntercall == false ||
              (maxCap != null && currentTotal > maxCap))) {
        final suggested = suggestedIntercallThicknessForDoubleGlass(
          thicknessOuter: tOuter,
          thicknessInner: tInner,
          jointTwoSides: baseSpec.jointTwoSides,
          sliding: isSliding,
        );
        if (suggested != null) {
          resolvedIntercallThickness = suggested;
        }
      }
    }

    // Baguettes and rosettes exist only inside a double-glazing unit. Clear
    // their active drawing data as soon as this pane becomes simple or a
    // panel, so an old decoration can never remain in the cost table.
    final bool clearGlassDecor = targetStructure != GlassStructure.double;

    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      final GlassSpecification updatedSpec = baseSpec.copyWith(
        structure: structure,
        finishOuter: finishOuter,
        finishInner: finishInner,
        colorOuter: resolvedColorOuter,
        colorInner: resolvedColorInner,
        processingOuter: processingOuter,
        processingInner: processingInner,
        temperedOuter: temperedOuter,
        temperedInner: temperedInner,
        colorP: colorP,
        hasGas: resolvedHasGas,
        intercallThickness: resolvedIntercallThickness,
        manualIntercall: resolvedManualIntercall,
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        bardageUsesFrameColor: bardageUsesFrameColor,
        panneauProductId: panneauProductId,
        decorDesignCode: decorDesignCode,
        thicknessOuter: effectiveThicknessOuter,
        thicknessInner: effectiveThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
        decorH: clearGlassDecor ? 0 : null,
        decorV: clearGlassDecor ? 0 : null,
        decorHPositions: clearGlassDecor ? const [] : null,
        decorVPositions: clearGlassDecor ? const [] : null,
        hasRosettes: clearGlassDecor ? false : null,
      );
      final updatedCellGlass = Map<String, GlassSpecification>.from(
        zone.cellGlassSpec,
      );
      updatedCellGlass[targetCellKey] = updatedSpec;
      zone.cellGlassSpec = updatedCellGlass;
    } else {
      zone.glass = zone.glass.copyWith(
        structure: structure,
        finishOuter: finishOuter,
        finishInner: finishInner,
        colorOuter: resolvedColorOuter,
        colorInner: resolvedColorInner,
        processingOuter: processingOuter,
        processingInner: processingInner,
        temperedOuter: temperedOuter,
        temperedInner: temperedInner,
        colorP: colorP,
        hasGas: resolvedHasGas,
        intercallThickness: resolvedIntercallThickness,
        manualIntercall: resolvedManualIntercall,
        panneauSubtype: panneauSubtype,
        panneauColor: panneauColor,
        isVerticalBardage: isVerticalBardage,
        bardageUsesFrameColor: bardageUsesFrameColor,
        panneauProductId: panneauProductId,
        decorDesignCode: decorDesignCode,
        thicknessOuter: effectiveThicknessOuter,
        thicknessInner: effectiveThicknessInner,
        laminatedColorOuter: laminatedColorOuter,
        laminatedColorInner: laminatedColorInner,
        decorH: clearGlassDecor ? 0 : null,
        decorV: clearGlassDecor ? 0 : null,
        decorHPositions: clearGlassDecor ? const [] : null,
        decorVPositions: clearGlassDecor ? const [] : null,
        hasRosettes: clearGlassDecor ? false : null,
      );
      if (zone.cellGlassSpec.isNotEmpty) {
        final updatedCellGlass = <String, GlassSpecification>{};
        zone.cellGlassSpec.forEach((key, val) {
          final cellTargetStructure = structure ?? val.structure;
          final cellFinishOuter = finishOuter ?? val.finishOuter;
          final cellFinishInner = finishInner ?? val.finishInner;
          updatedCellGlass[key] = val.copyWith(
            structure: structure,
            finishOuter: finishOuter,
            finishInner: finishInner,
            colorOuter: _resolveGlassColorAfterEdit(
              targetStructure: cellTargetStructure,
              targetFinish: cellFinishOuter,
              currentColor: val.colorOuter,
              requestedStructure: structure,
              requestedFinish: finishOuter,
              requestedColor: colorOuter,
            ),
            colorInner: _resolveGlassColorAfterEdit(
              targetStructure: cellTargetStructure,
              targetFinish: cellFinishInner,
              currentColor: val.colorInner,
              requestedStructure: structure,
              requestedFinish: finishInner,
              requestedColor: colorInner,
            ),
            processingOuter: processingOuter,
            processingInner: processingInner,
            temperedOuter: temperedOuter,
            temperedInner: temperedInner,
            colorP: colorP,
            hasGas: resolvedHasGas,
            intercallThickness: resolvedIntercallThickness,
            manualIntercall: resolvedManualIntercall,
            panneauSubtype: panneauSubtype,
            panneauColor: panneauColor,
            isVerticalBardage: isVerticalBardage,
            bardageUsesFrameColor: bardageUsesFrameColor,
            panneauProductId: panneauProductId,
            decorDesignCode: decorDesignCode,
            thicknessOuter: effectiveThicknessOuter,
            thicknessInner: effectiveThicknessInner,
            laminatedColorOuter: laminatedColorOuter,
            laminatedColorInner: laminatedColorInner,
            decorH: clearGlassDecor ? 0 : null,
            decorV: clearGlassDecor ? 0 : null,
            decorHPositions: clearGlassDecor ? const [] : null,
            decorVPositions: clearGlassDecor ? const [] : null,
            hasRosettes: clearGlassDecor ? false : null,
          );
        });
        zone.cellGlassSpec = updatedCellGlass;
      }
      defaultGlass = zone.glass;
    }
    if (!hasSimpleGlassForReducer) {
      clearReducerOverride();
    }
    final requested = targetCellKey != null && targetCellKey.isNotEmpty
        ? zone.getGlassForCell(targetCellKey)
        : zone.glass;
    final fitted = await fitGlazingByRules(
      requested,
      sliding: zone.content == ZoneContent.slidingSash,
    );
    if (!zones.contains(zone)) return;
    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      zone.cellGlassSpec = {...zone.cellGlassSpec, targetCellKey: fitted};
    } else {
      zone.glass = fitted;
      for (final key in zone.cellGlassSpec.keys.toList()) {
        zone.cellGlassSpec[key] = await fitGlazingByRules(
          zone.cellGlassSpec[key]!,
          sliding: zone.content == ZoneContent.slidingSash,
        );
      }
    }
    if (zones.any((candidate) => candidate.id == selectedZoneId)) {
      selection = SelectionInfo.zone(selectedZoneId);
      activeSubZone = targetCellKey;
    }
    _notifyModelListeners();
  }

  /// Fits a glazing pack to its bead (or sash) capacity. The capacity holds
  /// the whole pack: in aluminium the vitrage gasket, the panes and spacer,
  /// then the bourrage gasket; a PVC bead holds the panes alone. The pack may
  /// exceed the capacity by 1 mm at most and never fall short of it.
  ///
  /// The panes are what the user asked for and are never changed silently.
  /// The gaskets adapt first, then the spacer (unless the user picked it);
  /// when no combination fits, the report suggests another spacer or panes.
  Future<GlassSpecification> fitGlazingByRules(
    GlassSpecification spec, {
    required bool sliding,
  }) async {
    final usesBead = hasGlazingBeadForContext(sliding: sliding);
    final bead = usesBead ? glazingBeadForGlass(spec, sliding: sliding) : null;
    final capacity = glazingCapacityForStructure(
      spec.structure,
      sliding: sliding,
      glass: spec,
    );
    final outer = spec.thicknessOuter ?? kDefaultGlassPaneThickness;
    final inner = spec.thicknessInner ?? kDefaultGlassPaneThickness;
    final doubleGlass = spec.structure == GlassStructure.double;
    if (capacity == null) {
      glazingFitReport = GlazingFitReport(
        structure: spec.structure,
        usesBead: usesBead,
        sliding: sliding,
        capacity: null,
        outer: outer,
        inner: inner,
        spacer: spec.intercallThickness.toDouble(),
        valid: false,
      );
      return spec;
    }
    final pvc = sliding ? isSlidingPVC : isPVC;
    final series = sliding ? effectiveSlidingSeries : activeSeries;
    final resolver = CatalogCandidateResolver(database: db);
    Future<List<Map<String, dynamic>>> candidates(String role) =>
        resolver.resolve(
          CatalogCandidateQuery(
            category: 'joint',
            selectorType: role,
            roleKeys: [role],
            seriesId: series?.id,
            materialType: pvc ? 'pvc' : 'aluminium',
            drawingMode: sliding
                ? AccessoryDrawingMode.sliding
                : AccessoryDrawingMode.opening,
            requireDialog: false,
            requireQuantity: true,
            hasSimpleGlassForReducer:
                spec.structure == GlassStructure.simple ||
                spec.structure == GlassStructure.closed,
            hasDoubleGlassForRules: doubleGlass,
          ),
        );
    final vitrage = pvc
        ? <Map<String, dynamic>>[]
        : await candidates('joint_vitrage');
    final bourrage = pvc
        ? <Map<String, dynamic>>[]
        : await candidates('joint_bourrage');
    final choices = <List<Map<String, dynamic>>>[];
    if (pvc) {
      choices.add([]);
    } else if (!spec.jointTwoSides) {
      choices.addAll((vitrage.isNotEmpty ? vitrage : bourrage).map((r) => [r]));
    } else {
      // Vitrage goes in before the glass, bourrage closes the pack after it.
      final firstSide = vitrage.isNotEmpty ? vitrage : bourrage;
      final secondSide = bourrage.isNotEmpty ? bourrage : vitrage;
      for (final first in firstSide) {
        for (final second in secondSide) {
          choices.add([first, second]);
        }
      }
    }
    final spacers = spec.structure == GlassStructure.closed
        ? const [0.0]
        : _availableIntercallThicknesses().map((v) => v.toDouble()).toList();
    final lockSpacer = doubleGlass && spec.manualIntercall;
    GlassPackFit? solve({required bool fixedPanes, required bool lock}) =>
        fitGlassPack(
          capacity: capacity,
          outer: outer,
          inner: inner,
          spacer: spec.intercallThickness.toDouble(),
          doubleGlass: doubleGlass,
          jointChoices: choices,
          spacers: spacers,
          outerPanes: fixedPanes || spec.structure == GlassStructure.closed
              ? [outer]
              : getAvailableThicknesses(spec.finishOuter, spec.colorOuter),
          innerPanes: fixedPanes || !doubleGlass
              ? [doubleGlass ? inner : 0.0]
              : getAvailableThicknesses(spec.finishInner, spec.colorInner),
          lockSpacer: lock,
        );

    final result = solve(fixedPanes: true, lock: lockSpacer);
    if (result == null) {
      // Suggest what would fit: another spacer first, then other panes.
      final suggestion =
          solve(fixedPanes: true, lock: false) ??
          solve(fixedPanes: false, lock: false);
      glazingFitReport = GlazingFitReport(
        structure: spec.structure,
        usesBead: usesBead,
        sliding: sliding,
        beadName: bead?.name,
        capacity: capacity,
        outer: outer,
        inner: inner,
        spacer: spec.intercallThickness.toDouble(),
        valid: false,
        manualSpacer: lockSpacer,
        suggestion: suggestion,
      );
      return spec.copyWith(fittedJoints: const [], glazingFitValid: false);
    }
    glazingFitReport = GlazingFitReport(
      structure: spec.structure,
      usesBead: usesBead,
      sliding: sliding,
      beadName: bead?.name,
      capacity: capacity,
      outer: result.outer,
      inner: result.inner,
      spacer: result.spacer,
      valid: true,
      manualSpacer: lockSpacer,
      fit: result,
    );
    return spec.copyWith(
      thicknessOuter: result.outer,
      thicknessInner: result.inner,
      intercallThickness: doubleGlass
          ? result.spacer.round()
          : spec.intercallThickness,
      fittedJoints: result.joints,
      glazingFitValid: true,
    );
  }

  Future<void> updateGlassGasket({bool recalculateIntercall = true}) async {
    if (isPVC) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      _notifyModelListeners();
      return;
    }

    final parclose = componentOverrides['باكيت الزجاج (Parclose)'];

    // Find active sash profile based on the system mode
    Map<String, dynamic>? activeSashMap;
    if (systemMode == 'sliding') {
      activeSashMap = slidingSashOverride;
      if (activeSashMap == null && activeSlidingSeries != null) {
        try {
          final defaultSash = activeSlidingSeries!.sections.firstWhere(
            (s) => s.isSash || s.type.toLowerCase().contains('sash'),
          );
          activeSashMap = defaultSash.toMap();
        } catch (_) {}
      }
    } else {
      activeSashMap = sashOverride;
      if (activeSashMap == null && activeSeries != null) {
        try {
          final defaultSash = activeSeries!.sections.firstWhere(
            (s) => s.isSash || s.type.toLowerCase().contains('sash'),
          );
          activeSashMap = defaultSash.toMap();
        } catch (_) {}
      }
    }

    double maxGlass = 0.0;
    if (parclose != null) {
      maxGlass = _readPositiveDouble(parclose['max_glass_thickness']);
    } else if (activeSashMap != null) {
      maxGlass = _readPositiveDouble(activeSashMap['max_glass_thickness']);
    }

    if (maxGlass <= 0) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      _notifyModelListeners();
      return;
    }

    if (zones.isEmpty) return;

    GlassSpecification? activeGlass;
    final zone = selectedZone;
    if (zone != null) {
      activeGlass = zone.getGlassForCell(activeSubZone);
    }
    activeGlass ??= zones
        .expand((z) => [z.glass, ...z.cellGlassSpec.values])
        .firstWhere(
          (glass) => glass.structure != GlassStructure.closed,
          orElse: () => const GlassSpecification(),
        );

    if (activeGlass.structure == GlassStructure.closed) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      _notifyModelListeners();
      return;
    }

    final dbInstance = SqlDatabase();
    final rawJoints = await dbInstance.readJoints();
    final joints = rawJoints
        .map((row) => Map<String, dynamic>.from(row))
        .where((joint) => _readPositiveDouble(joint['thickness']) > 0)
        .toList();
    if (joints.isEmpty) {
      componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
      _notifyModelListeners();
      return;
    }

    bool isVitrageJoint(Map<String, dynamic> joint) {
      final text =
          '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
              .toLowerCase();
      return text.contains('vitrage') ||
          text.contains('فيتراج') ||
          text.contains('زجاج') ||
          text.contains('glass');
    }

    bool isBourrageJoint(Map<String, dynamic> joint) {
      final text =
          '${joint['name'] ?? ''} ${joint['type'] ?? ''} ${joint['gasket_type'] ?? ''}'
              .toLowerCase();
      return text.contains('bourrage') ||
          text.contains('بوراج') ||
          text.contains('حشو');
    }

    final vitrageJoints = joints.where(isVitrageJoint).toList();
    final bourrageJoints = joints.where(isBourrageJoint).toList();
    final jointSides = activeGlass.jointTwoSides ? 2 : 1;
    final useSliding =
        systemMode == 'sliding' ||
        (selectedZone != null
            ? selectedZone!.content == ZoneContent.slidingSash
            : usesSlidingPrimaryProfiles);
    final activeSeriesForSash = useSliding ? activeSlidingSeries : activeSeries;
    final rawActiveSashId = activeSashMap?['id'];
    final activeSashId = rawActiveSashId is num
        ? rawActiveSashId.toInt()
        : int.tryParse(rawActiveSashId?.toString() ?? '');
    final linkedJoints = <Map<String, dynamic>>[];
    if (activeSeriesForSash != null && activeSashId != null) {
      final positions = activeGlass.jointTwoSides
          ? const ['sash_inner', 'sash_outer', 'sash_glass', 'all']
          : const ['sash_inner', 'sash_glass', 'all'];
      final linkedRows = await dbInstance.getDefaultJointsForSection(
        seriesId: activeSeriesForSash.id,
        sectionId: activeSashId,
        positionKeys: positions,
      );
      for (final row in linkedRows) {
        final joint = Map<String, dynamic>.from(row);
        if (_readPositiveDouble(joint['thickness']) <= 0) continue;
        if (!isVitrageJoint(joint)) continue;
        linkedJoints.add(joint);
      }
    }
    final candidateJoints = linkedJoints.isNotEmpty
        ? linkedJoints
        : (vitrageJoints.isNotEmpty ? vitrageJoints : joints);
    Map<String, dynamic>? bestJoint;
    Map<String, dynamic>? bestBourrageJoint;
    int? bestIntercall;
    var bestScore = double.infinity;

    if (activeGlass.structure == GlassStructure.double) {
      final paneThickness =
          _glassPaneThicknessOrDefault(activeGlass.thicknessOuter) +
          _glassPaneThicknessOrDefault(activeGlass.thicknessInner);
      // The double-glazing bead, not whichever parclose was saved last.
      final doubleCapacity =
          glazingCapacityForStructure(
            GlassStructure.double,
            sliding: useSliding,
            glass: activeGlass,
          ) ??
          maxGlass;
      if (doubleCapacity - paneThickness <= 0) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        _notifyModelListeners();
        return;
      }
      // The spacer is chosen once the gaskets are known (below).
      bestIntercall = activeGlass.intercallThickness;

      if (useSliding) {
        // Sliding uses the same glazing gasket on one or two sides. Keep the
        // thinnest valid gasket independently of the sealed-unit thickness.
        for (final joint in candidateJoints) {
          final jointThickness = _readPositiveDouble(joint['thickness']);
          final score = jointThickness;
          if (score < bestScore) {
            bestScore = score;
            bestJoint = joint;
          }
        }
      } else {
        // Opening aluminium keeps its Vitrage and Bourrage gaskets, but they
        // are selected independently from the sealed glass-unit thickness.
        final selectedVitrage = selectedVitrageJointOverride();
        bestJoint = linkedJoints.isNotEmpty
            ? linkedJoints.first
            : (selectedVitrage ??
                  (vitrageJoints.isNotEmpty
                      ? (vitrageJoints.toList()..sort(
                              (a, b) => _readPositiveDouble(
                                a['thickness'],
                              ).compareTo(_readPositiveDouble(b['thickness'])),
                            ))
                            .first
                      : null));
        if (bestJoint != null) {
          final scopedBourrage = bourrageJoints
              .where(
                (joint) =>
                    _catalogRowMatchesSeriesScope(joint, activeSeriesForSash),
              )
              .toList();
          final candidates = scopedBourrage.isNotEmpty
              ? scopedBourrage
              : bourrageJoints;
          final selectedBourrage = selectedBourrageJointOverride(
            doubleGlass: true,
          );
          if (selectedBourrage != null) {
            bestBourrageJoint = selectedBourrage;
          } else if (candidates.isNotEmpty) {
            candidates.sort(
              (a, b) => _readPositiveDouble(
                a['thickness'],
              ).compareTo(_readPositiveDouble(b['thickness'])),
            );
            bestBourrageJoint = candidates.first;
          }
        }
      }
      if (bestJoint == null) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        _notifyModelListeners();
        return;
      }

      // Order of a glazing pack: vitrage gasket, panes and spacer, then the
      // bourrage gasket. The capacity holds all of them, so the spacer gets
      // what remains after both gaskets.
      final vitrage = _readPositiveDouble(bestJoint['thickness']);
      final secondSide = !activeGlass.jointTwoSides
          ? 0.0
          : (!useSliding && bestBourrageJoint != null
                ? _readPositiveDouble(bestBourrageJoint['thickness'])
                : vitrage);
      final recalculate = recalculateIntercall && !activeGlass.manualIntercall;
      if (recalculate) {
        bestIntercall =
            _spacerFillingGap(doubleCapacity - paneThickness - vitrage - secondSide) ??
            bestIntercall;
      }

      final targetZone = selectedZone;
      if (recalculate && targetZone != null) {
        final targetCellKey = activeSubZone;
        if (targetCellKey != null && targetCellKey.isNotEmpty) {
          final current = targetZone.getGlassForCell(targetCellKey);
          // Refit so the stored gaskets follow the new spacer.
          final fitted = await fitGlazingByRules(
            current.copyWith(intercallThickness: bestIntercall),
            sliding: useSliding,
          );
          targetZone.cellGlassSpec =
              Map<String, GlassSpecification>.from(targetZone.cellGlassSpec)
                ..[targetCellKey] = fitted;
        } else {
          targetZone.glass = await fitGlazingByRules(
            targetZone.glass.copyWith(intercallThickness: bestIntercall),
            sliding: useSliding,
          );
        }
      }
    } else {
      final glassThickness = _glassPaneThicknessOrDefault(
        activeGlass.thicknessOuter,
      );
      final targetJointThickness = (maxGlass - glassThickness) / jointSides;
      if (targetJointThickness <= 0) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        _notifyModelListeners();
        return;
      }
      for (final joint in candidateJoints) {
        final jointThickness = _readPositiveDouble(joint['thickness']);
        final diff = (jointThickness - targetJointThickness).abs();
        final score = diff * 100 + jointThickness * 0.01;
        if (diff <= 1.0 && score < bestScore) {
          bestScore = score;
          bestJoint = joint;
        }
      }
      if (bestJoint == null) {
        componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
        _notifyModelListeners();
        return;
      }
    }

    componentOverrides['جوان الزجاج (Joint Vitrage)'] =
        Map<String, dynamic>.from(bestJoint);
    if (!useSliding && bestBourrageJoint != null) {
      componentOverrides['جوان البوراج للزجاج المزدوج (Joint Bourrage Double)'] =
          Map<String, dynamic>.from(bestBourrageJoint);
    }
    _lastResolvedVitrageJointThickness = _readPositiveDouble(
      bestJoint['thickness'],
    );
    _notifyModelListeners();
  }

  Future<void> _loadJointRuleDefaults(dynamic d, int seriesId) async {
    final rules = await db.getCatalogItemRules(
      itemTable: 'Joints',
      seriesId: seriesId,
    );
    if (rules.isEmpty) return;

    final isSlidingSeriesContext =
        systemMode == 'sliding' ||
        (activeSlidingSeries?.id == seriesId && activeSeries?.id != seriesId);
    bool ruleScopeMatches(Map<String, dynamic> rule) {
      final scope = (rule['usage_scope'] ?? 'global')
          .toString()
          .trim()
          .toLowerCase();
      return scope.isEmpty ||
          scope == 'global' ||
          scope == 'auto' ||
          scope == 'both' ||
          scope == (isSlidingSeriesContext ? 'sliding' : 'opening');
    }

    Future<void> loadJoint(
      String overrideKey,
      String roleKey, {
      List<String> aliases = const [],
    }) async {
      if (componentOverrides.containsKey(overrideKey)) return;
      final acceptedRoles = {roleKey, ...aliases};
      final matchingRules = rules.where((rule) {
        if (rule['show_in_quantity'] == 0) return false;
        if (!ruleScopeMatches(rule)) return false;
        final currentRole = rule['role_key']?.toString().trim();
        return currentRole != null && acceptedRoles.contains(currentRole);
      });

      for (final rule in matchingRules) {
        final itemId = (rule['item_id'] as num?)?.toInt();
        if (itemId == null) continue;
        final rows = await d.query(
          'Joints',
          where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
          whereArgs: [itemId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final selected = Map<String, dynamic>.from(rows.first);
        final rawPrice = selected['price_per_meter'] ?? selected['price'];
        selected['calculated_price'] = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
        componentOverrides[overrideKey] = selected;
        return;
      }
    }

    // These keys are the exact keys consumed by ComponentCalculator. Keeping
    // the mapping here makes the Joints rules page affect the quantity table
    // without coupling the catalogue UI to the calculation formulas.
    await loadJoint('جوان الزجاج (Joint Vitrage)', 'joint_vitrage');
    await loadJoint('جوان البوراج (Joint Bourrage)', 'joint_bourrage');
    await loadJoint(
      'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
      'joint_bourrage',
    );
    await loadJoint(
      'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
      'joint_bourrage',
    );
    await loadJoint('جوان الضرب (Joint Frappe)', 'joint_frappe');
    await loadJoint('N 245', 'joint_central');
    await loadJoint('جوان بروس للظلفة (Joint Brosse Sash)', 'joint_brosse');
    await loadJoint(
      'جوان بروس للستار (Joint Brosse Shutter)',
      'shutter_joint_brosse',
      aliases: const ['joint_brosse'],
    );
    await loadJoint('جوان برونز (Joint Bronze)', 'joint_bronze');
  }

  void updateAllSlidingJointSides(bool twoSides) {
    final targets = zones.where((z) => z.content == ZoneContent.slidingSash);
    if (isPVC || targets.isEmpty) return;
    _saveSnapshot();
    for (final zone in targets) {
      zone.glass = zone.glass.copyWith(jointTwoSides: twoSides);
      zone.cellGlassSpec = zone.cellGlassSpec.map(
        (key, value) => MapEntry(key, value.copyWith(jointTwoSides: twoSides)),
      );
    }
    unawaited(updateGlassGasket());
    _notifyModelListeners();
  }

  void updateSelectedZoneGlassDecor({
    int? decorH,
    int? decorV,
    List<double>? decorHPositions,
    List<double>? decorVPositions,
    String? decorColor,
    double? decorThickness,
    bool? hasRosettes,
    int? decorBaguetteId,
    int? decorRosetteId,
    int? rosetteShape,
    bool? jointTwoSides,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final targetCellKey = activeSubZone;
    if (targetCellKey != null && targetCellKey.isNotEmpty) {
      final GlassSpecification currentSpec = selectedZone!.getGlassForCell(
        targetCellKey,
      );
      final GlassSpecification updatedSpec = currentSpec.copyWith(
        decorH: decorH,
        decorV: decorV,
        decorHPositions: decorHPositions,
        decorVPositions: decorVPositions,
        decorColor: decorColor,
        decorThickness: decorThickness,
        hasRosettes: hasRosettes,
        decorBaguetteId: decorBaguetteId,
        decorRosetteId: decorRosetteId,
        rosetteShape: rosetteShape,
        jointTwoSides: jointTwoSides,
      );
      final updatedCellGlass = Map<String, GlassSpecification>.from(
        selectedZone!.cellGlassSpec,
      );
      updatedCellGlass[targetCellKey] = updatedSpec;
      selectedZone!.cellGlassSpec = updatedCellGlass;
    } else {
      selectedZone!.glass = selectedZone!.glass.copyWith(
        decorH: decorH,
        decorV: decorV,
        decorHPositions: decorHPositions,
        decorVPositions: decorVPositions,
        decorColor: decorColor,
        decorThickness: decorThickness,
        hasRosettes: hasRosettes,
        decorBaguetteId: decorBaguetteId,
        decorRosetteId: decorRosetteId,
        rosetteShape: rosetteShape,
        jointTwoSides: jointTwoSides,
      );
    }
    if (jointTwoSides != null) {
      unawaited(updateGlassGasket());
    }
    _notifyModelListeners();
  }

  void updateZoneGlassDecorHPos(String zoneId, int index, double ratio) {
    _saveSnapshot();
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      final spec = zones[idx].glass;
      final mutable = List<double>.from(spec.decorHPositions);
      if (index >= 0 && index < mutable.length) {
        mutable[index] = ratio;
        zones[idx].glass = spec.copyWith(decorHPositions: mutable);
        _notifyModelListeners();
      }
    }
  }

  void updateZoneGlassDecorVPos(String zoneId, int index, double ratio) {
    _saveSnapshot();
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      final spec = zones[idx].glass;
      final mutable = List<double>.from(spec.decorVPositions);
      if (index >= 0 && index < mutable.length) {
        mutable[index] = ratio;
        zones[idx].glass = spec.copyWith(decorVPositions: mutable);
        _notifyModelListeners();
      }
    }
  }

  Rect getSafeGlassRect(Rect sashRect, double sashT) {
    double finalT = sashT;
    if (sashRect.width <= finalT * 2 + 10) {
      finalT = math.max(1.0, (sashRect.width - 10) / 2);
    }
    if (sashRect.height <= finalT * 2 + 10) {
      finalT = math.max(1.0, math.min(finalT, (sashRect.height - 10) / 2));
    }
    return sashRect.deflate(finalT);
  }

  void _restoreGlassOnBothSidesOfMullion(bool isHorizontal, double position) {
    for (final (negative, positive) in _mullionAdjacentPairs(
      isHorizontal,
      position,
    )) {
      final hasGlass =
          negative.content == ZoneContent.fixedGlass ||
          positive.content == ZoneContent.fixedGlass;
      if (!hasGlass) continue;
      negative.content = ZoneContent.fixedGlass;
      positive.content = ZoneContent.fixedGlass;
    }
  }

  void _enforceGroovedMullionGlassSide(bool isHorizontal, double position) {
    final holderOnPositiveSide = isGroovedMullionCavityOnPositiveSide(
      isHorizontal,
      position,
    );

    for (final (negative, positive) in _mullionAdjacentPairs(
      isHorizontal,
      position,
    )) {
      final hasGlass =
          negative.content == ZoneContent.fixedGlass ||
          positive.content == ZoneContent.fixedGlass;
      if (!hasGlass) continue;

      final holder = holderOnPositiveSide ? positive : negative;
      final emptySide = holderOnPositiveSide ? negative : positive;
      holder.content = ZoneContent.fixedGlass;
      emptySide.content = ZoneContent.empty;
    }
  }

  List<double> getVerticalFrameJoints() {
    if (!coupleFrames) return [];
    final joints = <double>[];
    final jointT = profileThickness * 2;
    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];
        if (((z1.boundary.right - z2.boundary.left).abs() - jointT).abs() <=
            2.0) {
          double xCenter = (z1.boundary.right + z2.boundary.left) / 2;
          if (!joints.contains(xCenter)) {
            joints.add(xCenter);
          }
        } else if (((z2.boundary.right - z1.boundary.left).abs() - jointT)
                .abs() <=
            2.0) {
          double xCenter = (z2.boundary.right + z1.boundary.left) / 2;
          if (!joints.contains(xCenter)) {
            joints.add(xCenter);
          }
        }
      }
    }
    joints.sort();
    return joints;
  }

  List<double> getHorizontalFrameJoints() {
    if (!coupleFrames) return [];
    final joints = <double>[];
    final jointT = profileThickness * 2;
    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];
        if (((z1.boundary.bottom - z2.boundary.top).abs() - jointT).abs() <=
            2.0) {
          double yCenter = (z1.boundary.bottom + z2.boundary.top) / 2;
          if (!joints.contains(yCenter)) {
            joints.add(yCenter);
          }
        } else if (((z2.boundary.bottom - z1.boundary.top).abs() - jointT)
                .abs() <=
            2.0) {
          double yCenter = (z2.boundary.bottom + z1.boundary.top) / 2;
          if (!joints.contains(yCenter)) {
            joints.add(yCenter);
          }
        }
      }
    }
    joints.sort();
    return joints;
  }
}
