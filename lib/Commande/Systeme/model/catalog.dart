part of '../model.dart';

/// Series, sections, catalogue roles, colours and prices of [WindowModel].
extension WindowModelCatalog on WindowModel {
  void reportCatalogIssue(String source, Object error) {
    debugPrint('Catalogue read failed ($source): $error');
    if (catalogIssues.contains(source)) return;
    if (catalogIssues.length >= 20) catalogIssues.removeAt(0);
    catalogIssues.add(source);
  }

  bool _isPvcSeries(AluminumSeries? series) {
    if (series == null) return false;
    final seriesType = (series.type).trim().toLowerCase();
    final seriesName = series.name.trim().toLowerCase();
    if (seriesType == 'pvc' || seriesName.contains('pvc')) return true;
    try {
      final system = availableSystems.firstWhere(
        (s) => s.id == series.profileId,
      );
      return system.type.trim().toLowerCase() == 'pvc';
    } catch (_) {
      return false;
    }
  }

  void _rememberSeriesRoleKeys(
    AluminumSeries series,
    List<Map<String, dynamic>> rows,
  ) {
    _seriesDesignRoleKeys[series.id] = rows
        .map((row) => normalizeSeriesDesignRoleKey(row['role_key']))
        .where((role) => role.isNotEmpty)
        .toSet();
    final roleIds = <String, Set<int>>{};
    final roleScopes = <String, Map<int, String>>{};
    final roleAllowsSideCover = <String, Map<int, bool>>{};
    final roleIntegratedSideCover = <String, Map<int, bool>>{};
    final roleOptions = <String, Map<int, Map<String, dynamic>>>{};
    bool? readBool(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
          return true;
        }
        if (normalized == '0' || normalized == 'false' || normalized == 'no') {
          return false;
        }
      }
      return null;
    }

    for (final row in rows) {
      final role = normalizeSeriesDesignRoleKey(row['role_key']);
      final rawId = row['section_id'];
      final sectionId = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (role.isEmpty || sectionId == null) continue;
      roleIds.putIfAbsent(role, () => <int>{}).add(sectionId);
      roleOptions.putIfAbsent(role, () => {})[sectionId] =
          Map<String, dynamic>.from(row);
      roleScopes.putIfAbsent(role, () => {})[sectionId] =
          row['usage_scope']?.toString().trim().toLowerCase() ?? 'auto';
      final allowsSideCover = readBool(row['allows_side_cover']);
      if (allowsSideCover != null) {
        roleAllowsSideCover.putIfAbsent(role, () => {})[sectionId] =
            allowsSideCover;
      }
      final integratedSideCover = readBool(row['integrated_side_cover']);
      if (integratedSideCover != null) {
        roleIntegratedSideCover.putIfAbsent(role, () => {})[sectionId] =
            integratedSideCover;
      }
    }
    _seriesDesignRoleSectionIds[series.id] = roleIds;
    _seriesDesignRoleUsageScopes[series.id] = roleScopes;
    _seriesDesignRoleAllowsSideCover[series.id] = roleAllowsSideCover;
    _seriesDesignRoleIntegratedSideCover[series.id] = roleIntegratedSideCover;
    _seriesDesignRoleOptions[series.id] = roleOptions;
  }

  bool _roleScopeMatches(String? scope, {required bool sliding}) {
    final normalized = scope?.trim().toLowerCase() ?? 'auto';
    return normalized.isEmpty ||
        normalized == 'auto' ||
        normalized == 'both' ||
        normalized == (sliding ? 'sliding' : 'opening');
  }

  bool _configuredSectionMatchesScope(
    AluminumSeries series,
    String roleKey,
    int sectionId, {
    required bool sliding,
  }) {
    final scope =
        _seriesDesignRoleUsageScopes[series.id]?[roleKey.trim()]?[sectionId];
    return _roleScopeMatches(scope, sliding: sliding);
  }

  AluminumSection _sectionWithConfiguredRoleOptions(
    AluminumSeries series,
    Iterable<String> roleKeys,
    AluminumSection section,
  ) {
    for (final rawRoleKey in roleKeys) {
      final roleKey = rawRoleKey.trim();
      if (roleKey.isEmpty ||
          _seriesDesignRoleSectionIds[series.id]?[roleKey]?.contains(
                section.id,
              ) !=
              true) {
        continue;
      }
      final allowsSideCover =
          _seriesDesignRoleAllowsSideCover[series.id]?[roleKey]?[section.id];
      final integratedSideCover =
          _seriesDesignRoleIntegratedSideCover[series.id]?[roleKey]?[section
              .id];
      if (allowsSideCover == null && integratedSideCover == null) {
        return section;
      }
      final map = section.toMap();
      if (allowsSideCover != null) {
        map['allows_side_cover'] = allowsSideCover ? 1 : 0;
        map['design_allows_side_cover'] = allowsSideCover ? 1 : 0;
      }
      if (integratedSideCover != null) {
        map['design_integrated_side_cover'] = integratedSideCover ? 1 : 0;
      }
      return AluminumSection.fromMap(map);
    }
    return section;
  }

  bool seriesHasConfiguredRoles(AluminumSeries? series) {
    if (series == null) return false;
    return _seriesDesignRoleKeys[series.id]?.isNotEmpty == true;
  }

  /// Returns whether the catalogue explicitly assigned this series to the
  /// opening or sliding drawing scope.  Names such as PBC or Anime are
  /// commercial system names and cannot reliably classify a series.
  bool seriesSupportsDrawingScope(
    AluminumSeries series,
    String scope, {
    AluminumProfileSystem? profile,
  }) {
    final normalizedScope = scope.trim().toLowerCase();
    final configuredScopes = <String>{};
    final roleScopes = _seriesDesignRoleUsageScopes[series.id];
    if (roleScopes != null) {
      for (final sectionScopes in roleScopes.values) {
        for (final value in sectionScopes.values) {
          final normalized = value.trim().toLowerCase();
          if (normalized == 'opening' ||
              normalized == 'sliding' ||
              normalized == 'both') {
            configuredScopes.add(normalized);
          }
        }
      }
    }

    if (configuredScopes.isNotEmpty) {
      return configuredScopes.contains(normalizedScope) ||
          configuredScopes.contains('both');
    }

    // Older catalogues have no explicit scope. Preserve their legacy
    // classifier as a fallback until the series is configured.
    return normalizedScope == 'sliding'
        ? isSlidingSeriesForDrawing(series)
        : profile != null && isOpeningSeriesForDrawing(series, profile);
  }

  /// Applies the drawing scope to the whole catalogue system, not only to
  /// the individual series that happen to have role rows. Older catalogues
  /// commonly configured roles for one representative series while keeping
  /// several other active series in the same opening/sliding family.
  bool seriesSupportsDrawingScopeInSystem(
    AluminumSeries series,
    String scope, {
    AluminumProfileSystem? profile,
  }) {
    final normalizedScope = scope.trim().toLowerCase();
    final system = profile ?? profileSystemForSeries(availableSystems, series);
    if (system == null) {
      return seriesSupportsDrawingScope(series, normalizedScope);
    }
    if (seriesSupportsDrawingScope(series, normalizedScope, profile: system)) {
      return true;
    }

    final oppositeScope = normalizedScope == 'sliding' ? 'opening' : 'sliding';
    if (seriesSupportsDrawingScope(series, oppositeScope, profile: system)) {
      return false;
    }

    // If at least one series in this system identifies the requested scope,
    // an otherwise unlabelled active series belongs to that family unless it
    // is recognizably from the opposite drawing.
    final hasSystemScope = system.series.any(
      (candidate) => seriesSupportsDrawingScope(
        candidate,
        normalizedScope,
        profile: system,
      ),
    );
    if (!hasSystemScope) return false;
    return normalizedScope == 'sliding'
        ? !isOpeningSeriesForDrawing(series, system)
        : !isSlidingSeriesForDrawing(series);
  }

  bool _hasLoadedRoleMetadata(AluminumSeries? series) {
    return series != null && _seriesDesignRoleSectionIds.containsKey(series.id);
  }

  AluminumSeries? _seriesForConfiguredRole({bool? useSlidingSeries}) {
    if (useSlidingSeries == true) {
      return activeSlidingSeries ??
          (systemMode == 'sliding' || usesSlidingPrimaryProfiles
              ? activeSeries
              : null);
    }
    if (useSlidingSeries == false) return activeSeries;
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    return useSliding ? (activeSlidingSeries ?? activeSeries) : activeSeries;
  }

  /// Resolves all profiles assigned to a catalogue design role.
  List<AluminumSection> getConfiguredSectionsForRole(
    String roleKey, {
    bool? useSlidingSeries,
    String? showWhenGlass,
  }) {
    final series = _seriesForConfiguredRole(useSlidingSeries: useSlidingSeries);
    if (series == null) return const <AluminumSection>[];
    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?[roleKey.trim()] ??
        const <int>{};
    if (configuredIds.isEmpty) {
      if (roleKey.trim() == 'face_to_face') {
        return series.sections
            .where((section) {
              final type = section.type.trim().toLowerCase();
              final name = section.name.trim().toLowerCase();
              return type == 'face_to_face' ||
                  type == 'face to face' ||
                  name.contains('face to face') ||
                  name.contains('face-to-face');
            })
            .toList(growable: false);
      }
      return const <AluminumSection>[];
    }
    final sliding =
        useSlidingSeries ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles);
    final requestedGlass = showWhenGlass?.trim().toLowerCase();
    bool matchesGlassRule(int sectionId) {
      if (requestedGlass == null || requestedGlass.isEmpty) return true;
      final configuredRule =
          _seriesDesignRoleOptions[series.id]?[roleKey
                  .trim()]?[sectionId]?['show_when_glass']
              ?.toString()
              .trim()
              .toLowerCase() ??
          'any';
      if (configuredRule.isEmpty || configuredRule == 'any') return true;
      if (requestedGlass == 'simple' || requestedGlass == 'single') {
        return configuredRule == 'simple' || configuredRule == 'single';
      }
      if (requestedGlass == 'double') return configuredRule == 'double';
      return configuredRule == requestedGlass;
    }

    return series.sections
        .where(
          (section) =>
              configuredIds.contains(section.id) &&
              matchesGlassRule(section.id) &&
              _configuredSectionMatchesScope(
                series,
                roleKey,
                section.id,
                sliding: sliding,
              ),
        )
        .map(
          (section) =>
              _sectionWithConfiguredRoleOptions(series, [roleKey], section),
        )
        .toList(growable: false);
  }

  bool seriesUsesReducer(AluminumSeries? series) {
    if (series == null) return false;
    return _seriesDesignRoleKeys[series.id]?.contains('reducer') == true;
  }

  void clearReducerOverride() {
    componentOverrides.remove('ريديكتور (Réducteur)');
    componentOverrides.remove('مخفض الزجاج (Réducteur)');
  }

  double _sectionVisibleWidth(Map<String, dynamic>? section) {
    if (section == null) return 0.0;
    for (final field in const ['visible_width', 'thickness']) {
      final value = section[field];
      if (value is num && value > 0) return value.toDouble();
    }
    return 0.0;
  }

  String _profileColorName(Map<String, dynamic>? colorData) {
    return (colorData?['name'] ?? colorData?['color_name'] ?? '')
        .toString()
        .trim();
  }

  String _profileColorHex(Map<String, dynamic>? colorData) {
    return (colorData?['hex_code'] ?? colorData?['hex'] ?? '')
        .toString()
        .replaceAll('#', '')
        .toLowerCase()
        .trim();
  }

  String _normalizedProfileColorName(String value) {
    return value
        .toLowerCase()
        .trim()
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ô', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String? _profileColorAliasKey(String rawValue) {
    final value = _normalizedProfileColorName(rawValue);
    if (value.isEmpty) return null;
    if (value.contains('white') ||
        value.contains('blanc') ||
        value.contains('ابيض')) {
      return 'white';
    }
    if (value.contains('gris') ||
        value.contains('gray') ||
        value.contains('grey') ||
        value.contains('رمادي')) {
      return 'gray';
    }
    if (value.contains('black') ||
        value.contains('noir') ||
        value.contains('اسود')) {
      return 'black';
    }
    if (value.contains('wood') ||
        value.contains('bois') ||
        value.contains('fbm') ||
        value.contains('خشبي')) {
      return 'wood';
    }
    if (value.contains('brown') ||
        value.contains('marron') ||
        value.contains('بني')) {
      return 'brown';
    }
    if (value.contains('beige') ||
        value.contains('بيج') ||
        value.contains('باج')) {
      return 'beige';
    }
    return null;
  }

  Map<String, dynamic>? _findAvailableColorByName(String rawName) {
    final name = _normalizedProfileColorName(rawName);
    if (name.isEmpty) return null;

    for (final color in availableColors) {
      final colorName = _normalizedProfileColorName(_profileColorName(color));
      if (colorName == name) return color;
    }

    for (final color in availableColors) {
      final colorName = _normalizedProfileColorName(_profileColorName(color));
      if (colorName.isEmpty) continue;
      if (colorName.contains(name) || name.contains(colorName)) return color;
    }

    final alias = _profileColorAliasKey(rawName);
    if (alias != null) {
      for (final color in availableColors) {
        final colorAlias = _profileColorAliasKey(_profileColorName(color));
        if (colorAlias == alias) return color;
      }
    }

    return null;
  }

  Map<String, dynamic>? _findAvailableColorByHex(String rawHex) {
    final hex = rawHex.replaceAll('#', '').toLowerCase().trim();
    if (hex.isEmpty) return null;
    for (final color in availableColors) {
      if (_profileColorHex(color) == hex) return color;
    }
    return null;
  }

  bool _isWhiteProfileColor(Map<String, dynamic>? colorData) {
    final name = _normalizedProfileColorName(_profileColorName(colorData));
    final hex = (colorData?['hex_code'] ?? colorData?['hex'] ?? '')
        .toString()
        .replaceAll('#', '')
        .toLowerCase()
        .trim();
    return name.contains('white') ||
        name.contains('blanc') ||
        name.contains('ابيض') ||
        (name.isEmpty && (hex == 'ffffff' || hex == 'fff'));
  }

  Color get accessoryColor {
    if (_selectedAccessoryColor != null) {
      return getEffectiveGradientColors(
        frameColor,
        _selectedAccessoryColor,
      ).last;
    }
    final colors = getEffectiveGradientColors(frameColor, selectedDbColor);
    return colors.last;
  }

  Future<void> _loadColorsForProfile(int profileId) async {
    if (_loadedColorsProfileId == profileId && availableColors.isNotEmpty) {
      colorsLoading = false;
      return;
    }
    final loadGeneration = ++_colorsLoadGeneration;
    final preferredColor = _preferredDbColorForCatalogLoad ?? _selectedDbColor;
    final previousColorId = preferredColor?['id'];
    final previousColorName =
        (preferredColor?['name'] ?? preferredColor?['color_name'])
            ?.toString()
            .toLowerCase()
            .trim();
    final previousColorHex = _profileColorHex(preferredColor);
    colorsLoading = true;
    availableColors = [];
    // Keep the current colour painted while the palette loads. Clearing it
    // here drew the item white for a moment, and every catalogue reload made
    // an edited item blink between its real colour and white.
    _notifyModelListeners();

    List<Map<String, dynamic>> loadedColors;
    try {
      loadedColors = (await db.getColorsForProfile(
        profileId,
      )).map((color) => Map<String, dynamic>.from(color)).toList();
    } catch (_) {
      if (loadGeneration == _colorsLoadGeneration) {
        availableColors = [];
        colorsLoading = false;
        _notifyModelListeners();
      }
      return;
    }
    if (loadGeneration != _colorsLoadGeneration) return;
    availableColors = loadedColors;
    _loadedColorsProfileId = profileId;
    Map<String, dynamic>? selectedColor;

    // A saved order can travel between devices whose local colour IDs differ.
    // Resolve by stable identity first: name, then hex.  Use the numeric id
    // only when no stable identity was saved.
    if (previousColorName != null && previousColorName.isNotEmpty) {
      selectedColor = _findAvailableColorByName(previousColorName);
    }
    // Many catalogue colours keep the placeholder #FFFFFF. A named colour
    // ("Gris") must not be swapped for another one ("Gris 7024") only
    // because both carry that placeholder.
    final hexIsPlaceholder =
        (previousColorHex == 'ffffff' || previousColorHex == 'fff') &&
        previousColorName != null &&
        previousColorName.isNotEmpty &&
        !_isWhiteProfileColor(preferredColor);
    if (selectedColor == null &&
        previousColorHex.isNotEmpty &&
        !hexIsPlaceholder) {
      selectedColor = _findAvailableColorByHex(previousColorHex);
    }
    if (selectedColor == null &&
        previousColorId != null &&
        (previousColorName == null || previousColorName.isEmpty) &&
        previousColorHex.isEmpty) {
      for (final color in availableColors) {
        if (color['id']?.toString() == previousColorId.toString()) {
          selectedColor = color;
          break;
        }
      }
    }
    // Preserve the user's/order's colour only when the newly selected series
    // really supports it. Otherwise choose a valid colour for that series.
    selectedColor ??= _defaultFrameColor();
    if (selectedColor == null) _frameColor = FrameColor.white;

    _selectedDbColor = selectedColor == null
        ? null
        : Map<String, dynamic>.from(selectedColor);
    for (final zone in zones) {
      zone.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
    colorsLoading = false;
    _notifyModelListeners();
  }

  String getClosedColoreName(ClosedGlassColor d) {
    switch (d) {
      case ClosedGlassColor.transparent:
        return 'شفاف';
      case ClosedGlassColor.white:
        return 'ابيض';
      case ClosedGlassColor.grisClair:
        return 'رمادي فاتح';
      case ClosedGlassColor.fbmfonce:
        return 'خشبي داكن';
      case ClosedGlassColor.grissoris:
        return 'رمادي داكن';
      case ClosedGlassColor.black:
        return 'اسود';
      case ClosedGlassColor.beige:
        return 'باج';
      case ClosedGlassColor.fbmClair:
        return 'خشبي فاتح';
      case ClosedGlassColor.opaque:
        return 'عاتم';
      case ClosedGlassColor.marberier:
        return 'رخامي';
    }
  }

  String getArabicColorName(GlassColor color) {
    switch (color) {
      case GlassColor.transparent:
        return 'شفاف';
      case GlassColor.blue:
        return 'أزرق';
      case GlassColor.brown:
        return 'بني';
      case GlassColor.green:
        return 'أخضر';
      case GlassColor.gray:
        return 'رمادي';
      case GlassColor.grayAgc:
        return 'رمادي';
      case GlassColor.blueAgc:
        return 'أزرق';
    }
  }

  List<String> getColorKeywords(GlassColor color) {
    switch (color) {
      case GlassColor.transparent:
        return [
          'شفاف',
          'transparent',
          'بدون لون',
          'clair',
          'clear',
          'صافي',
          '',
        ];
      case GlassColor.blue:
        return ['أزرق', 'ازرق', 'azur', 'bleu', 'blue'];
      case GlassColor.brown:
        return [
          'بني',
          'marron',
          'brun',
          'brown',
          'bronze',
          'برونز',
          'كوكو',
          'coco',
        ];
      case GlassColor.green:
        return ['أخضر', 'اخضر', 'vert', 'green'];
      case GlassColor.gray:
        return ['رمادي', 'gris', 'gray', 'grey', 'falken', 'فالكن'];
      case GlassColor.grayAgc:
        return [
          'رمادي agc',
          'رمادي بلجيكي',
          'gris agc',
          'gris belge',
          'grey agc',
          'agc',
        ];
      case GlassColor.blueAgc:
        return [
          'أزرق بلجيكي',
          'ازرق بلجيكي',
          'بلجيكي أزرق',
          'بلجيكي ازرق',
          'بلجيكي',
          'أزرق agc',
          'bleu agc',
          'bleu belge',
          'blue belge',
          'belge',
        ];
    }
  }

  bool hasExactColorForFinish(GlassFinish finish, GlassColor color) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    return allGlassCache.any((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      return matchesFinish && matchesColor;
    });
  }

  double getPriceForFinish(
    GlassFinish finish,
    GlassColor color, {
    double? chosenThickness,
  }) {
    List<String> finishKws = getFinishKeywords(finish);
    List<String> colorKws = getColorKeywords(color);

    // 1. Try matching both finish, color, and thickness if specified
    final exactMatch = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      String c = (g['color'] ?? '').toString().toLowerCase();
      double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;

      bool matchesFinish = finishKws.any(
        (kw) => t.contains(kw) || n.contains(kw),
      );
      bool matchesColor = colorKws.any((kw) {
        if (kw.isEmpty) {
          return c.isEmpty ||
              c.contains('clair') ||
              c.contains('transparent') ||
              n.contains('clair') ||
              n.contains('transparent');
        }
        return c == kw || c.contains(kw) || n.contains(kw);
      });
      bool matchesThickness =
          chosenThickness == null || thick == chosenThickness;
      return matchesFinish && matchesColor && matchesThickness;
    }, orElse: () => <String, dynamic>{});

    if (exactMatch.isNotEmpty) {
      return (exactMatch['price_per_sqm'] ?? 0.0).toDouble();
    }

    // 2. Try matching finish only
    final match = allGlassCache.firstWhere((g) {
      String t = g['type'].toString().toLowerCase();
      String n = g['name'].toString().toLowerCase();
      return finishKws.any((kw) => t.contains(kw) || n.contains(kw));
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['price_per_sqm'] ?? 0.0).toDouble();
    }

    // 3. Fallback for clair
    if (finish == GlassFinish.clair) {
      final clairMatch = allGlassCache.firstWhere((g) {
        String t = g['type'].toString().toLowerCase();
        return t == 'simple' || t == 'clair' || t == 'glass';
      }, orElse: () => <String, dynamic>{});
      if (clairMatch.isNotEmpty) {
        return (clairMatch['price_per_sqm'] ?? 0.0).toDouble();
      }
    }
    return 0.0;
  }

  double getPriceForGas(int thickness) {
    if (availableGases.isEmpty) return 0.0;
    try {
      final gasMatch = availableGases.firstWhere(
        (g) =>
            g['thickness'] == thickness ||
            g['name'].toString().contains(thickness.toString()),
      );
      return (gasMatch['price_per_sqm'] ?? 0.0).toDouble();
    } catch (_) {
      return 0.0; // No match found
    }
  }

  double getLaminatedPrice(double thickness, String laminatedColor) {
    if (allGlassCache.isEmpty) return 0.0;
    // Search for a laminated glass product matching the thickness and color
    final match = allGlassCache.firstWhere((g) {
      final t = g['type'].toString().toLowerCase();
      final n = g['name'].toString().toLowerCase();
      final c = (g['color'] ?? '').toString().toLowerCase();
      final double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;

      final isLaminatedProduct =
          t.contains('مورق') ||
          t.contains('laminated') ||
          t.contains('strat') ||
          n.contains('مورق') ||
          n.contains('laminated') ||
          n.contains('strat');
      if (!isLaminatedProduct) return false;

      if (thick != thickness) return false;

      // Color mapping: transparent/clair, white/opale/opaque/milky, blue
      bool matchesColor = false;
      if (laminatedColor == 'transparent') {
        matchesColor =
            c.isEmpty ||
            c.contains('clair') ||
            c.contains('transparent') ||
            n.contains('clair') ||
            n.contains('transparent');
      } else if (laminatedColor == 'white') {
        matchesColor =
            c.contains('blanc') ||
            c.contains('أبيض') ||
            c.contains('opale') ||
            c.contains('opaque') ||
            n.contains('blanc') ||
            n.contains('أبيض');
      } else if (laminatedColor == 'blue') {
        matchesColor =
            c.contains('bleu') ||
            c.contains('أزرق') ||
            n.contains('bleu') ||
            n.contains('أزرق');
      }

      return matchesColor;
    }, orElse: () => <String, dynamic>{});

    if (match.isNotEmpty) {
      return (match['price_per_sqm'] ?? 0.0).toDouble();
    }
    // Fallback: search by thickness only
    final thickMatch = allGlassCache.firstWhere((g) {
      final t = g['type'].toString().toLowerCase();
      final n = g['name'].toString().toLowerCase();
      final double thick = (g['thickness'] as num?)?.toDouble() ?? 0.0;
      final isLaminatedProduct =
          t.contains('مورق') ||
          t.contains('laminated') ||
          t.contains('strat') ||
          n.contains('مورق') ||
          n.contains('laminated') ||
          n.contains('strat');
      return isLaminatedProduct && thick == thickness;
    }, orElse: () => <String, dynamic>{});

    if (thickMatch.isNotEmpty) {
      return (thickMatch['price_per_sqm'] ?? 0.0).toDouble();
    }
    return 0.0;
  }

  double getTemperingPricePerSqm(double thickness) {
    // Tempering is managed in the Glass catalogue as its own service, one
    // price per glass thickness (for example: Trempé 4 mm, Trempé 6 mm).
    // This makes the price available to every drawing without requiring an
    // unrelated component override.
    double? readPrice(Map<String, dynamic> item) {
      final raw =
          item['price_per_sqm'] ??
          item['pricePerSqm'] ??
          item['calculated_price'] ??
          item['price'] ??
          item['prix'];
      return raw is num
          ? raw.toDouble()
          : double.tryParse(
              raw?.toString().trim().replaceAll(' ', '').replaceAll(',', '.') ??
                  '',
            );
    }

    bool isTemperingItem(Map<String, dynamic> item) {
      final type = item['type']?.toString().toLowerCase() ?? '';
      final name = item['name']?.toString().toLowerCase() ?? '';
      return type == 'tempering' ||
          type.contains('tremp') ||
          type.contains('tempering') ||
          name.contains('trempé') ||
          name.contains('trempe') ||
          name.contains('تقسية');
    }

    double itemThickness(Map<String, dynamic> item) {
      final raw = item['thickness'];
      if (raw is num) return raw.toDouble();
      final text = raw?.toString().trim() ?? '';
      final direct = double.tryParse(text.replaceAll(',', '.'));
      if (direct != null) return direct;
      final number = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(text)?.group(0);
      return double.tryParse(number?.replaceAll(',', '.') ?? '') ?? 0.0;
    }

    final matchingItems = allGlassCache.where(
      (item) =>
          isTemperingItem(item) &&
          (itemThickness(item) - thickness).abs() < 0.01,
    );
    // Old synchronisations can leave an earlier zero-priced duplicate beside
    // the priced catalogue item. Prefer the first actual price, rather than
    // returning the first matching row blindly.
    double? fallbackPrice;
    for (final item in matchingItems) {
      final price = readPrice(item);
      if (price == null) continue;
      fallbackPrice ??= price;
      if (price != 0) return price;
    }
    if (fallbackPrice != null) return fallbackPrice;

    // Compatibility with any older catalogues that stored the service as a
    // component override rather than a Glass catalogue item.
    final thickStr = thickness.toStringAsFixed(0);
    for (var entry in componentOverrides.entries) {
      final name = entry.key.toLowerCase();
      final isTempering =
          name.contains('تقسية') ||
          name.contains('tempering') ||
          name.contains('trempe');
      if (isTempering && name.contains(thickStr)) {
        final val = entry.value;
        if (val is Map) {
          return readPrice(Map<String, dynamic>.from(val)) ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  double _catalogDimension(Map<String, dynamic> product, String key) {
    final value = product[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<void> loadCatalogData([String systemMode = '']) {
    final next = _catalogLoadChain.then((_) => _loadCatalogData(systemMode));
    _catalogLoadChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _loadCatalogData([String systemMode = '']) async {
    // A fresh catalogue load replaces the data earlier failures affected.
    catalogIssues.clear();
    colorsLoading = true;
    _notifyModelListeners();
    try {
      if (systemMode.isNotEmpty) {
        this.systemMode = systemMode;
      }

      // Put the palette on screen before the slower catalogue/role pass. The
      // selected product already knows its active profile when editing an
      // order, so there is no reason to wait for every catalogue table first.
      _loadedColorsProfileId = null;
      final earlyColorSeries = this.systemMode == 'sliding'
          ? activeSlidingSeries
          : activeSeries;
      if (earlyColorSeries != null) {
        await _loadColorsForProfile(earlyColorSeries.profileId);
      }
      await loadGlassProducts();

      // Load KitBundles is_selling_calculated settings
      // Only set if not already loaded from saved data (to preserve user overrides)
      try {
        final kitBundles = await db.readKitBundles();
        for (var kb in kitBundles) {
          final kbName = kb['name']?.toString() ?? '';
          if (kbName.isNotEmpty) {
            if (componentOverrides.containsKey(kbName)) {
              // Preserve existing saved data, only update is_selling_calculated
              final existing = componentOverrides[kbName];
              if (existing is Map<String, dynamic>) {
                existing['is_selling_calculated'] =
                    kb['is_selling_calculated'] ?? 1;
              }
            } else {
              componentOverrides[kbName] = {
                'id': kb['id'],
                'name': kb['name'],
                'is_selling_calculated': kb['is_selling_calculated'] ?? 1,
              };
            }
          }
        }
      } catch (error) {
        reportCatalogIssue('KitBundles', error);
      }

      final profilesData = await db.readProfile();
      // Keep the early palette visible while the remaining catalogue tables
      // are being resolved. Clearing it here brought back the white/default
      // state and made colours appear to load much later than they did.
      availableAccessoryColors = await db.readAccessoryColors();
      final newAvailableSystems = <AluminumProfileSystem>[];
      bool foundValidSeries = false;
      final selectedSeriesIds = <int>{
        if (loadedSeriesId != null) loadedSeriesId!,
        if (loadedSlidingSeriesId != null) loadedSlidingSeriesId!,
        if (activeSeries != null) activeSeries!.id,
        if (activeSlidingSeries != null) activeSlidingSeries!.id,
      };
      final selectedSeriesNames = <String>{
        if (loadedSeriesName != null && loadedSeriesName!.trim().isNotEmpty)
          loadedSeriesName!.trim().toLowerCase(),
        if (loadedSlidingSeriesName != null &&
            loadedSlidingSeriesName!.trim().isNotEmpty)
          loadedSlidingSeriesName!.trim().toLowerCase(),
        if (activeSeries != null && activeSeries!.name.trim().isNotEmpty)
          activeSeries!.name.trim().toLowerCase(),
        if (activeSlidingSeries != null &&
            activeSlidingSeries!.name.trim().isNotEmpty)
          activeSlidingSeries!.name.trim().toLowerCase(),
      };

      for (var pData in profilesData) {
        var system = AluminumProfileSystem.fromMap(pData);
        final seriesData = <Map<String, dynamic>>[
          ...(await db.readSeriesByProfile(system.id)),
        ];

        // Keep an explicitly selected series visible even if it was marked
        // inactive after the drawing was saved. Do not expose every inactive
        // catalogue row; restore only the row(s) already selected by the
        // drawing/order.
        if (selectedSeriesIds.isNotEmpty || selectedSeriesNames.isNotEmpty) {
          final allSeriesData = await db.readAllSeriesByProfile(system.id);
          for (final candidate in allSeriesData) {
            final rawId = candidate['id'];
            final candidateId = rawId is int
                ? rawId
                : int.tryParse(rawId?.toString() ?? '');
            final candidateName = (candidate['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final selectedById =
                candidateId != null && selectedSeriesIds.contains(candidateId);
            final selectedByName =
                candidateName.isNotEmpty &&
                selectedSeriesNames.contains(candidateName);
            if (selectedById || selectedByName) {
              final alreadyLoaded = seriesData.any((row) {
                final rowId = row['id'];
                return rowId?.toString() == rawId?.toString();
              });
              if (!alreadyLoaded) seriesData.add(candidate);
            }
          }
        }

        for (var sData in seriesData) {
          var series = AluminumSeries.fromMap(sData);
          final sectionsData = await db.readAvailableSectionsBySeries(
            series.id,
          );
          series.sections = sectionsData
              .map((e) => AluminumSection.fromMap(e))
              .toList();
          // Cache role ownership for every loaded series. This lets shared
          // components such as couvre-joint be collected across series while
          // keeping frames and sashes tied to their own role rows.
          _rememberSeriesRoleKeys(
            series,
            await db.getSeriesDesignRoles(series.id),
          );

          // Keep every active catalogue row available to the drawing page.
          // Opening/sliding classification is used later to resolve the
          // correct role and calculation path; it must never remove an
          // enabled system from the selector. This is especially important
          // for commercial/legacy types such as TPR whose type field may not
          // contain an exact opening/sliding label.
          system.series.add(series);
        }
        if (system.series.isNotEmpty) newAvailableSystems.add(system);
      }
      if (newAvailableSystems.isNotEmpty) {
        availableSystems = newAvailableSystems;
      }

      if (availableSystems.isNotEmpty) {
        final bool hasSlidingZones =
            usesSlidingPrimaryProfiles ||
            zones.any((z) => z.content == ZoneContent.slidingSash) ||
            loadedSlidingSeriesId != null ||
            (loadedSlidingSeriesName != null &&
                loadedSlidingSeriesName!.trim().isNotEmpty);

        final bool hasOpeningZones =
            zones.any(
              (z) =>
                  z.content == ZoneContent.singleSash ||
                  z.content == ZoneContent.doubleSash ||
                  z.content == ZoneContent.fixedGlass ||
                  z.content == ZoneContent.empty,
            ) ||
            loadedSeriesId != null ||
            (loadedSeriesName != null && loadedSeriesName!.trim().isNotEmpty);

        bool isOpeningCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          if (systemMode == 'sliding' && !hasOpeningZones) return false;
          if (systemMode == 'mixed' ||
              systemMode == 'french' ||
              hasOpeningZones) {
            return seriesSupportsDrawingScopeInSystem(
              series,
              'opening',
              profile: profile,
            );
          }
          return true;
        }

        bool isSlidingCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          if (systemMode == 'french' && !hasSlidingZones) return false;
          if (systemMode == 'mixed' ||
              systemMode == 'sliding' ||
              hasSlidingZones) {
            return seriesSupportsDrawingScopeInSystem(
              series,
              'sliding',
              profile: profile,
            );
          }
          return true;
        }

        bool isPrimarySeriesCandidate(
          AluminumSeries series,
          AluminumProfileSystem profile,
        ) {
          // In a sliding drawing activeSeries is the primary sliding series;
          // in the other drawing modes it is the opening series.
          return systemMode == 'sliding'
              ? isSlidingCandidate(series, profile)
              : isOpeningCandidate(series, profile);
        }

        AluminumSeries? resolvedActive;
        String? activeNameToResolve = loadedSeriesName;
        if (activeNameToResolve == null || activeNameToResolve.isEmpty) {
          activeNameToResolve = activeSeries?.name;
        }

        // Priority 0: Direct DB match by loadedSeriesId — most reliable,
        // bypasses all mode/name filtering. Guarantees saved series is restored.
        if (loadedSeriesId != null) {
          // First check availableSystems (already loaded)
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              // A saved series id is an explicit user choice.  Do not reject
              // it because a legacy or partially configured series cannot
              // yet be classified as opening/sliding; rejecting it here made
              // the product silently fall back to the first default series.
              if (s.id == loadedSeriesId) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
          // If not found in filtered list, search ALL profiles/series in DB
          if (resolvedActive == null) {
            final allProfilesData0 = await db.readProfile();
            outer0:
            for (var pData in allProfilesData0) {
              final sourceSystem = AluminumProfileSystem.fromMap(pData);
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == loadedSeriesId) {
                  final sectionsData = await db.readAvailableSectionsBySeries(
                    s.id,
                  );
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  // Inject into the matching system only. Never attach a
                  // restored series to the first unrelated profile row.
                  final targetSystem = availableSystems.where(
                    (sys) => sys.id == sourceSystem.id,
                  );
                  final alreadyIn = targetSystem.any(
                    (sys) => sys.series.any((sr) => sr.id == s.id),
                  );
                  if (!alreadyIn) {
                    if (targetSystem.isNotEmpty) {
                      targetSystem.first.series.add(s);
                    } else {
                      sourceSystem.series.add(s);
                      availableSystems.add(sourceSystem);
                    }
                  }
                  break outer0;
                }
              }
            }
          }
        }

        // Priority 1: Match by activeSeries ID (in-memory user choice)
        if (resolvedActive == null && activeSeries != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == activeSeries!.id) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
          if (resolvedActive == null) {
            // Search globally if not in filtered list
            final allProfilesDataP1 = await db.readProfile();
            outerP1:
            for (var pData in allProfilesDataP1) {
              final sourceSystem = AluminumProfileSystem.fromMap(pData);
              final seriesData = await db.readSeriesByProfile(pData['id']);
              for (var sData in seriesData) {
                final s = AluminumSeries.fromMap(sData);
                if (s.id == activeSeries!.id) {
                  final sectionsData = await db.readAvailableSectionsBySeries(
                    s.id,
                  );
                  s.sections = sectionsData
                      .map((e) => AluminumSection.fromMap(e))
                      .toList();
                  resolvedActive = s;
                  final targetSystem = availableSystems.where(
                    (sys) => sys.id == sourceSystem.id,
                  );
                  final alreadyIn = targetSystem.any(
                    (sys) => sys.series.any((sr) => sr.id == s.id),
                  );
                  if (!alreadyIn) {
                    if (targetSystem.isNotEmpty) {
                      targetSystem.first.series.add(s);
                    } else {
                      sourceSystem.series.add(s);
                      availableSystems.add(sourceSystem);
                    }
                  }
                  break outerP1;
                }
              }
            }
          }
        }

        if (resolvedActive == null &&
            activeNameToResolve != null &&
            activeNameToResolve.isNotEmpty) {
          final query = activeNameToResolve.toLowerCase().trim();
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (!isPrimarySeriesCandidate(s, sys)) continue;
              final sName = s.name.toLowerCase().trim();
              final sType = s.type.toLowerCase().trim();
              if (sName == query ||
                  sType == query ||
                  sName.contains(query) ||
                  query.contains(sName)) {
                resolvedActive = s;
                break;
              }
            }
            if (resolvedActive != null) break;
          }
        }

        final int? savedSlidingIdBeforeActive =
            loadedSlidingSeriesId ?? activeSlidingSeries?.id;
        final String? savedSlidingNameBeforeActive =
            loadedSlidingSeriesName ?? activeSlidingSeries?.name;

        if (resolvedActive != null) {
          await setActiveSeries(resolvedActive);
          foundValidSeries = true;
        } else {
          AluminumSeries? firstFrench;
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (isPrimarySeriesCandidate(s, sys)) {
                firstFrench = s;
                break;
              }
            }
            if (firstFrench != null) break;
          }
          if (firstFrench != null) {
            await setActiveSeries(firstFrench);
          }
          foundValidSeries = firstFrench != null;
        }

        if (savedSlidingIdBeforeActive != null) {
          loadedSlidingSeriesId = savedSlidingIdBeforeActive;
        }
        if (savedSlidingNameBeforeActive != null &&
            savedSlidingNameBeforeActive.trim().isNotEmpty) {
          loadedSlidingSeriesName = savedSlidingNameBeforeActive;
        }

        final pairedSystem = systemMode == 'mixed'
            ? profileSystemForSeries(availableSystems, activeSeries)
            : null;
        final selectedPairedSystem = pairedSystem;
        bool belongsToPairedSystem(AluminumProfileSystem system) =>
            selectedPairedSystem == null ||
            profileSystemsShareMaterial(system, selectedPairedSystem);

        AluminumSeries? resolvedSliding;
        String? slidingNameToResolve = loadedSlidingSeriesName;
        if (slidingNameToResolve == null || slidingNameToResolve.isEmpty) {
          slidingNameToResolve = activeSlidingSeries?.name;
        }

        // A saved sliding-series id is an explicit product choice. It may
        // legitimately belong to a different catalogue system than the
        // opening series (for example Bennia 40000 + BS 90). Resolving it
        // only inside the paired system made the restore fail and then
        // silently replace it with that system's first sliding series.
        if (loadedSlidingSeriesId != null) {
          for (final sys in availableSystems) {
            for (final series in sys.series) {
              if (series.id == loadedSlidingSeriesId) {
                resolvedSliding = series;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        // If not found in availableSystems, search all profiles/series in DB
        if (resolvedSliding == null && loadedSlidingSeriesId != null) {
          final allProfilesDataSliding = await db.readProfile();
          outerSliding:
          for (var pData in allProfilesDataSliding) {
            final sourceSystem = AluminumProfileSystem.fromMap(pData);
            final seriesData = await db.readSeriesByProfile(pData['id']);
            for (var sData in seriesData) {
              final s = AluminumSeries.fromMap(sData);
              if (s.id == loadedSlidingSeriesId) {
                final sectionsData = await db.readAvailableSectionsBySeries(
                  s.id,
                );
                s.sections = sectionsData
                    .map((e) => AluminumSection.fromMap(e))
                    .toList();
                resolvedSliding = s;
                final targetSystem = availableSystems.where(
                  (sys) => sys.id == sourceSystem.id,
                );
                final alreadyIn = targetSystem.any(
                  (sys) => sys.series.any((sr) => sr.id == s.id),
                );
                if (!alreadyIn) {
                  if (targetSystem.isNotEmpty) {
                    targetSystem.first.series.add(s);
                  } else {
                    sourceSystem.series.add(s);
                    availableSystems.add(sourceSystem);
                  }
                }
                break outerSliding;
              }
            }
          }
        }

        if (resolvedSliding == null && activeSlidingSeries != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == activeSlidingSeries!.id) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null && loadedSlidingSeriesId != null) {
          for (var sys in availableSystems) {
            for (var s in sys.series) {
              if (s.id == loadedSlidingSeriesId) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null &&
            slidingNameToResolve != null &&
            slidingNameToResolve.isNotEmpty) {
          final query = slidingNameToResolve.toLowerCase().trim();
          for (var sys in availableSystems) {
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (!isSlidingCandidate(s, sys)) continue;
              final sName = s.name.toLowerCase().trim();
              final sType = s.type.toLowerCase().trim();
              if (sName == query ||
                  sType == query ||
                  sName.contains(query) ||
                  query.contains(sName)) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        // Keep the selected system as the only source. Never restore a saved
        // sliding id from another system just because its material is equal.
        if (resolvedSliding == null) {
          for (var sys in availableSystems) {
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              final matchesSavedId =
                  loadedSlidingSeriesId != null &&
                  s.id == loadedSlidingSeriesId;
              final matchesActiveId =
                  activeSlidingSeries != null &&
                  s.id == activeSlidingSeries!.id;
              if (matchesSavedId ||
                  (matchesActiveId && isSlidingCandidate(s, sys))) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding == null &&
            slidingNameToResolve != null &&
            slidingNameToResolve.isNotEmpty) {
          final query = slidingNameToResolve.toLowerCase().trim();
          for (var sys in availableSystems) {
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (!isSlidingCandidate(s, sys)) continue;
              final sName = s.name.toLowerCase().trim();
              final sType = s.type.toLowerCase().trim();
              if (sName == query ||
                  sType == query ||
                  sName.contains(query) ||
                  query.contains(sName)) {
                resolvedSliding = s;
                break;
              }
            }
            if (resolvedSliding != null) break;
          }
        }

        if (resolvedSliding != null) {
          await setActiveSlidingSeries(resolvedSliding);
          if (systemMode == 'sliding') {
            await setActiveSeries(resolvedSliding);
          }
        } else {
          AluminumSeries? firstSliding;
          for (var sys in availableSystems) {
            if (!belongsToPairedSystem(sys)) continue;
            for (var s in sys.series) {
              if (isSlidingCandidate(s, sys)) {
                firstSliding = s;
                break;
              }
            }
            if (firstSliding != null) break;
          }
          if (firstSliding != null) {
            await setActiveSlidingSeries(firstSliding);
            if (systemMode == 'sliding') {
              await setActiveSeries(firstSliding);
            }
          }
        }

        if (systemMode == 'mixed') {
          if (resolvedSliding != null) {
            await setActiveSlidingSeries(resolvedSliding);
          } else {
            AluminumSeries? firstSliding;
            final activeSystem = profileSystemForSeries(
              availableSystems,
              activeSeries,
            );
            if (activeSystem != null) {
              for (var ser in activeSystem.series) {
                if (isSlidingCandidate(ser, activeSystem)) {
                  firstSliding = ser;
                  break;
                }
              }
            }
            if (firstSliding != null) {
              await setActiveSlidingSeries(firstSliding);
            } else {
              // A mixed drawing may keep the sliding family in another
              // profile row. Use the first actual sliding series, never the
              // opening series as a substitute, but keep the same material.
              for (var sys in availableSystems) {
                if (!belongsToPairedSystem(sys)) continue;
                for (var ser in sys.series) {
                  if (isSlidingCandidate(ser, sys)) {
                    firstSliding = ser;
                    break;
                  }
                }
                if (firstSliding != null) break;
              }
              if (firstSliding != null) {
                await setActiveSlidingSeries(firstSliding);
              } else {
                activeSlidingSeries = null;
              }
            }
          }
        }
      }
      if (!foundValidSeries && activeSeries != null) {
        foundValidSeries = true;
      }
      if (!foundValidSeries) {
        activeSeries = null;
        availableColors = [];
        _selectedDbColor = null;
        for (final zone in zones) {
          zone.selectedDbColor = null;
        }
      }
      // Restore the cover selected by the frame-owning series as soon as all
      // series roles are known. A saved enabled cover must be drawable on the
      // first frame; it must never wait for the user to toggle its button.
      _synchronizeSharedSideCover();
      colorsLoading = false;
      _notifyModelListeners();
    } catch (e) {
      colorsLoading = false;
      _notifyModelListeners();
      debugPrint("Error loading catalog data: $e");
    }
  }

  void copyCatalogRuntimeFrom(
    WindowModel source, {
    bool preserveCurrentSelections = true,
  }) {
    Map<String, dynamic>? cloneMap(Map<String, dynamic>? value) =>
        value == null ? null : Map<String, dynamic>.from(value);
    dynamic cloneOverrideValue(Object? value) {
      if (value is Map<String, dynamic>) {
        return Map<String, dynamic>.from(value);
      }
      if (value is Map) {
        return Map<String, dynamic>.from(value);
      }
      return value;
    }

    final currentDbColor = _selectedDbColor == null
        ? null
        : Map<String, dynamic>.from(_selectedDbColor!);
    final currentAccessoryColor = _selectedAccessoryColor == null
        ? null
        : Map<String, dynamic>.from(_selectedAccessoryColor!);
    final currentFrameOverride = cloneMap(frameOverride);
    final currentSideCoverOverride = cloneMap(sideCoverOverride);
    final currentSashOverride = cloneMap(sashOverride);
    final currentSlidingFrameOverride = cloneMap(slidingFrameOverride);
    final currentSlidingSashOverride = cloneMap(slidingSashOverride);
    final currentInternalSlidingSideCoverOverride = cloneMap(
      internalSlidingSideCoverOverride,
    );
    final currentSelectedSideCover = selectedSideCover;
    final currentSelectedInternalSlidingSideCover =
        selectedInternalSlidingSideCover;
    final currentComponentOverrides = componentOverrides.map(
      (key, value) => MapEntry(key, cloneOverrideValue(value)),
    );

    availableSystems = source.availableSystems;
    activeSeries = source.activeSeries;
    activeSlidingSeries = source.activeSlidingSeries;
    systemMode = systemMode ?? source.systemMode;
    allGlassCache = source.allGlassCache
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableIntercalls = source.availableIntercalls
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableGases = source.availableGases
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableColors = source.availableColors
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    availableAccessoryColors = source.availableAccessoryColors
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    seriesDesignConfig = source.seriesDesignConfig == null
        ? null
        : Map<String, dynamic>.from(source.seriesDesignConfig!);
    seriesTableConfig = source.seriesTableConfig == null
        ? null
        : Map<String, dynamic>.from(source.seriesTableConfig!);
    slidingSeriesTableConfig = source.slidingSeriesTableConfig == null
        ? null
        : Map<String, dynamic>.from(source.slidingSeriesTableConfig!);

    _seriesDesignRoleKeys
      ..clear()
      ..addAll(
        source._seriesDesignRoleKeys.map(
          (seriesId, roles) => MapEntry(seriesId, Set<String>.from(roles)),
        ),
      );
    _seriesDesignRoleSectionIds
      ..clear()
      ..addAll(
        source._seriesDesignRoleSectionIds.map(
          (seriesId, roles) => MapEntry(
            seriesId,
            roles.map((role, ids) => MapEntry(role, Set<int>.from(ids))),
          ),
        ),
      );
    _seriesDesignRoleUsageScopes
      ..clear()
      ..addAll(
        source._seriesDesignRoleUsageScopes.map(
          (seriesId, roles) => MapEntry(
            seriesId,
            roles.map(
              (role, scopes) => MapEntry(role, Map<int, String>.from(scopes)),
            ),
          ),
        ),
      );
    sectionPricesForSelectedColor
      ..clear()
      ..addAll(source.sectionPricesForSelectedColor);
    if (preserveCurrentSelections) {
      frameOverride = currentFrameOverride ?? cloneMap(source.frameOverride);
      sideCoverOverride =
          currentSideCoverOverride ?? cloneMap(source.sideCoverOverride);
      sashOverride = currentSashOverride ?? cloneMap(source.sashOverride);
      slidingFrameOverride =
          currentSlidingFrameOverride ?? cloneMap(source.slidingFrameOverride);
      slidingSashOverride =
          currentSlidingSashOverride ?? cloneMap(source.slidingSashOverride);
      internalSlidingSideCoverOverride =
          currentInternalSlidingSideCoverOverride ??
          cloneMap(source.internalSlidingSideCoverOverride);
      selectedSideCover = currentSelectedSideCover ?? source.selectedSideCover;
      selectedInternalSlidingSideCover =
          currentSelectedInternalSlidingSideCover ??
          source.selectedInternalSlidingSideCover;
      componentOverrides = source.componentOverrides.map(
        (key, value) => MapEntry(key, cloneOverrideValue(value)),
      );
      currentComponentOverrides.forEach((key, value) {
        componentOverrides[key] = cloneOverrideValue(value);
      });
    } else {
      frameOverride = cloneMap(source.frameOverride);
      sideCoverOverride = cloneMap(source.sideCoverOverride);
      sashOverride = cloneMap(source.sashOverride);
      slidingFrameOverride = cloneMap(source.slidingFrameOverride);
      slidingSashOverride = cloneMap(source.slidingSashOverride);
      internalSlidingSideCoverOverride = cloneMap(
        source.internalSlidingSideCoverOverride,
      );
      selectedSideCover = source.selectedSideCover;
      selectedInternalSlidingSideCover =
          source.selectedInternalSlidingSideCover;
      componentOverrides = source.componentOverrides.map(
        (key, value) => MapEntry(key, cloneOverrideValue(value)),
      );
    }

    if (preserveCurrentSelections) {
      _selectedDbColor =
          currentDbColor ??
          (source.selectedDbColor == null
              ? null
              : Map<String, dynamic>.from(source.selectedDbColor!));
      _selectedAccessoryColor =
          currentAccessoryColor ??
          (source.selectedAccessoryColor == null
              ? null
              : Map<String, dynamic>.from(source.selectedAccessoryColor!));
    } else {
      _selectedDbColor = source.selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedDbColor!);
      _selectedAccessoryColor = source.selectedAccessoryColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedAccessoryColor!);
    }
    if (!preserveCurrentSelections || selectedShutterColor == null) {
      selectedShutterColor = source.selectedShutterColor == null
          ? null
          : Map<String, dynamic>.from(source.selectedShutterColor!);
    }
    for (final zone in zones) {
      zone.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
  }

  double getSectionThickness(String type, {double fallback = 45.0}) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding
        ? (activeSlidingSeries ?? activeSeries)
        : activeSeries;
    final sash = useSliding ? slidingSashOverride : sashOverride;
    if (series == null) return fallback;
    if (type.toLowerCase() == 'sash' && sash != null) {
      double t = (sash['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
      t = (sash['thickness'] as num?)?.toDouble() ?? 0.0;
      if (t > 0 && t <= 80.0) return t;
    }
    if (!useSliding &&
        type.toLowerCase() == 'sash' &&
        selectedSashCode.isNotEmpty) {
      for (var sec in series.sections) {
        if (sec.type.toLowerCase() == 'sash' && sec.code == selectedSashCode) {
          return sec.visibleWidth;
        }
      }
    }
    for (var sec in series.sections) {
      if (sec.type.toLowerCase() == type.toLowerCase()) {
        return sec.visibleWidth;
      }
    }
    return fallback;
  }

  AluminumSection? getSectionByType(String type) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    AluminumSection? result;
    if (normalizedType == 'sash') {
      final ov = useSliding ? slidingSashOverride : sashOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    } else if (normalizedType == 'plinthe' ||
        normalizedType == 'plinth' ||
        normalizedType == 'plant') {
      final ov = componentOverrides['بلانت (Plinthe)'];
      if (ov is Map) {
        result = AluminumSection.fromMap(Map<String, dynamic>.from(ov));
      }
    } else if (normalizedType == 'frame') {
      final ov = useSliding ? slidingFrameOverride : frameOverride;
      if (ov != null) result = AluminumSection.fromMap(ov);
    }

    // Once role metadata is loaded, a frame exists only when the current
    // series assigns one to the frame role. Never fall back to a frame found
    // by name/type, which is how opening frames leaked into sliding drawings.
    if (normalizedType == 'frame' && _hasLoadedRoleMetadata(series)) {
      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
      if (configuredIds.isEmpty) return null;
      if (result != null) {
        final rawId = result.id;
        if (configuredIds.contains(rawId) &&
            _configuredSectionMatchesScope(
              series,
              'frame',
              rawId,
              sliding: useSliding,
            )) {
          return result;
        }
        result = null;
      }
      for (final section in series.sections) {
        if (configuredIds.contains(section.id) &&
            _configuredSectionMatchesScope(
              series,
              'frame',
              section.id,
              sliding: useSliding,
            )) {
          return section;
        }
      }
      return null;
    }

    if (result == null) {
      if (normalizedType == 'sash' && selectedSashCode.isNotEmpty) {
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'sash' &&
              sec.code == selectedSashCode) {
            result = sec;
            break;
          }
        }
      }
      if (result == null &&
          normalizedType == 'frame' &&
          selectedFrameCode != null) {
        for (var sec in series.sections) {
          if ((sec.type.toLowerCase() == 'frame' || sec.isFrame) &&
              sec.code == selectedFrameCode) {
            result = sec;
            break;
          }
        }
      }
      if (result == null) {
        for (var sec in series.sections) {
          final sectionType = sec.type.toLowerCase();
          final sectionName = sec.name.toLowerCase();
          final isMullion =
              normalizedType == 'mullion' &&
              (sectionType == 'mullion' ||
                  sectionType.contains('traverse') ||
                  sectionType.contains('meneau') ||
                  sectionType.contains('montant') ||
                  sectionType.contains('تقسيم') ||
                  sectionName.contains('mullion') ||
                  sectionName.contains('traverse') ||
                  sectionName.contains('meneau') ||
                  sectionName.contains('montant') ||
                  sectionName.contains('تقسيم')) &&
              !sectionType.contains('sash') &&
              !sectionType.contains('ouvrant') &&
              !sectionType.contains('ضلفة');
          final isPlinthe =
              (normalizedType == 'plinthe' ||
                  normalizedType == 'plinth' ||
                  normalizedType == 'plant') &&
              (sectionType.contains('plinthe') ||
                  sectionType.contains('plinth') ||
                  sectionType.contains('plant') ||
                  sectionType.contains('بلانت') ||
                  sectionName.contains('plinthe') ||
                  sectionName.contains('plinth') ||
                  sectionName.contains('plant') ||
                  sectionName.contains('بلانت'));
          final isCremoneTringle =
              normalizedType == 'triangle' &&
              (sectionType == 'tringle' ||
                  sectionType.contains('tringle') ||
                  sectionName.contains('tringle') ||
                  sectionName.contains('ترينجل') ||
                  sectionName.contains('تراينغل') ||
                  sectionName.contains('تريانغل'));
          if (sectionType == normalizedType ||
              isPlinthe ||
              isMullion ||
              isCremoneTringle ||
              (normalizedType == 'frame' && sec.isFrame)) {
            result = sec;
            break;
          }
        }
      }
    }

    // Swapping logic for multi-frame (coupled windows)
    if (normalizedType == 'frame' && result != null && zones.length > 1) {
      // If the matched frame is integrated, swap it with the non-integrated frame
      // of the same profile family (same thickness first, then any non-integrated)
      bool isIntegrated =
          result.couvreJointWidth > 0 ||
          result.name.toLowerCase().contains('cadre cj') ||
          result.code.toLowerCase().contains('103');
      if (isIntegrated) {
        // Pass 1: look for a non-integrated frame with same thickness (same family/body)
        AluminumSection? sameFamily;
        for (var sec in series.sections) {
          if (sec.type.toLowerCase() == 'frame' || sec.isFrame) {
            bool secIntegrated =
                sec.couvreJointWidth > 0 ||
                sec.name.toLowerCase().contains('cadre cj') ||
                sec.code.toLowerCase().contains('103');
            if (!secIntegrated && sec.thickness == result.thickness) {
              sameFamily = sec;
              break;
            }
          }
        }
        // Pass 2: if no same-thickness match, fall back to any non-integrated frame
        if (sameFamily == null) {
          for (var sec in series.sections) {
            if (sec.type.toLowerCase() == 'frame' || sec.isFrame) {
              bool secIntegrated =
                  sec.couvreJointWidth > 0 ||
                  sec.name.toLowerCase().contains('cadre cj') ||
                  sec.code.toLowerCase().contains('103');
              if (!secIntegrated) {
                sameFamily = sec;
                break;
              }
            }
          }
        }
        if (sameFamily != null) {
          result = sameFamily;
        }
      }
    }

    return result;
  }

  double getSectionThicknessByCode(String code, {double fallback = 45.0}) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return fallback;
    for (var sec in series.sections) {
      if (sec.code.toLowerCase() == code.toLowerCase() ||
          sec.name.toLowerCase().contains(code.toLowerCase())) {
        if (sec.visibleWidth > 0) return sec.visibleWidth;
        if (sec.thickness > 0 && sec.thickness <= 80.0) return sec.thickness;
        return fallback;
      }
    }
    return fallback;
  }

  AluminumSection? getSectionByCode(String code) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final series = useSliding ? activeSlidingSeries : activeSeries;
    if (series == null) return null;
    for (var sec in series.sections) {
      if (sec.code.toLowerCase() == code.toLowerCase() ||
          sec.name.toLowerCase().contains(code.toLowerCase())) {
        return sec;
      }
    }
    return null;
  }

  /// Applies an order-level selection to both the drawing and its saved state.
  Future<void> setOrderSeries(AluminumSeries series) async {
    // Use the same catalogue scopes as the drawing selectors. Numeric names
    // such as 40000 do not describe whether a series is opening or sliding.
    final roles = await db.getSeriesDesignRoles(series.id);
    _rememberSeriesRoleKeys(series, roles);
    final supportsSliding = seriesSupportsDrawingScopeInSystem(
      series,
      'sliding',
    );
    final supportsOpening = seriesSupportsDrawingScopeInSystem(
      series,
      'opening',
    );
    final useSliding =
        supportsSliding && !supportsOpening ||
        usesSlidingPrimaryProfiles && !supportsOpening;
    if (useSliding) {
      await setActiveSlidingSeries(series);
      if (systemMode == 'sliding') {
        await setActiveSeries(series);
      }
    } else {
      await setActiveSeries(series);
    }
  }

  Future<void> setActiveSeries(AluminumSeries series) {
    final next = _seriesUpdateChain.then((_) => _setActiveSeries(series));
    _seriesUpdateChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _setActiveSeries(AluminumSeries series) async {
    _saveSnapshot();
    // Capture the old plinthe geometry before switching activeSeries. Once
    // the new series is assigned, plintheHeight would be read from the new
    // catalogue and the old sash bottom could no longer be recognised.
    final previousPlintheHeight = plintheHeight;
    final previousPlintheZoneIds = zones
        .where((zone) => zone.hasSashPlintheBottom)
        .map((zone) => zone.id)
        .toSet();
    final hadPreviousFramePlinthe = hasFramePlintheBottom;
    final hadPreviousPlinthe =
        hasFramePlintheBottom || previousPlintheZoneIds.isNotEmpty;
    final double previousFrameThickness = profileThickness;
    final double previousMullionThickness = mullionThickness;
    final bool affectsVisibleDivisions = !usesSlidingPrimaryProfiles;
    final bool seriesChanged =
        (activeSeries != null && activeSeries!.id != series.id) ||
        (activeSeries == null && loadedSeriesId == null) ||
        (activeSeries == null &&
            loadedSeriesId != null &&
            loadedSeriesId != series.id);
    activeSeries = series;
    loadedSeriesId = series.id;
    loadedSeriesName = series.name;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    seriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    await reloadFrameJoinRules();
    _rememberSeriesRoleKeys(series, configuredRoleRows);
    final bool isSliding =
        systemMode == 'sliding' ||
        usesSlidingPrimaryProfiles ||
        isSlidingSeriesForDrawing(series);
    final strictProfileRoles = configuredRoleRows.isNotEmpty;
    bool configuredRoleRowAllowed(Map<String, dynamic> row) {
      if (row['is_visible'] == 0 || row['show_in_quantity'] == 0) {
        return false;
      }
      if (!_roleScopeMatches(
        row['usage_scope']?.toString(),
        sliding: isSliding,
      )) {
        return false;
      }
      final glassRule = row['show_when_glass']?.toString().trim() ?? 'any';
      if (glassRule == 'simple' && !hasSimpleGlassForReducer) {
        return false;
      }
      if (glassRule == 'double' && !hasDoubleGlassForRules) return false;
      if (hasShutter && row['allowed_with_shutter'] == 0) return false;
      return true;
    }

    List<AluminumSection> configuredSectionsFor(Iterable<String> roleKeys) {
      final ids = configuredRoleRows
          .where(
            (row) =>
                roleKeys.contains(
                  normalizeSeriesDesignRoleKey(row['role_key']),
                ) &&
                configuredRoleRowAllowed(row),
          )
          .map((row) {
            final rawId = row['section_id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse(rawId?.toString() ?? '');
          })
          .whereType<int>()
          .toSet();
      if (ids.isEmpty) return <AluminumSection>[];
      return series.sections
          .where((section) => ids.contains(section.id))
          .map(
            (section) =>
                _sectionWithConfiguredRoleOptions(series, roleKeys, section),
          )
          .toList();
    }

    if (systemMode == 'sliding' || isSliding) {
      activeSlidingSeries ??= series;
      slidingSeriesTableConfig = seriesTableConfig;
    }

    if (seriesChanged) {
      if (systemMode == 'sliding' || isSliding) {
        activeSlidingSeries = series;
        // Availability in a newly selected sliding series starts enabled.
        // Loading a saved drawing can still restore an explicit false value
        // afterwards through model serialization.
        if (getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) !=
            null) {
          useOptionalCacheRail = true;
        }
        slidingFrameOverride = null;
        slidingSashOverride = null;
      }
      frameOverride = null;
      sashOverride = null;
      componentOverrides.remove('تقسيم الزجاج (Mullion)');
      componentOverrides.remove('باكيت الزجاج (Parclose)');
      componentOverrides.remove('الباتمو (Batmo)');
      componentOverrides.remove('بوشون باتمو (Bouchon Batmo)');
      componentOverrides.remove('حديد الإطار (Renfort Frame)');
      componentOverrides.remove('حديد الظلفة (Renfort Sash)');
      componentOverrides.remove('حديد الظلفة الخاص بالمفاصل');
      componentOverrides.remove('البارداج (Bardage)');
      componentOverrides.remove('البانو (Panneau)');
      _clearAccessoryOverrides();
      removeOverridesFromForeignSeries();

      // Section identifiers from another series (for example TPR) cannot be
      // reused safely. Preserve the user's mullion type, then resolve its
      // concrete frame section from the newly selected series.
      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Reset plinthe state: check if new series has a plinthe section
      // If it doesn't, disable plinthe and restore hasBottomFrame
      componentOverrides.remove('بلانت (Plinthe)');
      final configuredPlinthes = configuredSectionsFor(const ['plant']);
      final hasPlintheInNewSeries = configuredRoleRows.isNotEmpty
          ? configuredPlinthes.isNotEmpty
          : series.sections.any((s) {
              final t = s.type.toLowerCase().trim();
              final n = s.name.toLowerCase().trim();
              return t.contains('plinthe') ||
                  n.contains('plinthe') ||
                  t.contains('plinth') ||
                  n.contains('plinth');
            });
      if (!hasPlintheInNewSeries) {
        // New series has no plinthe — reset plinthe flags and restore bottom frame
        if (hadPreviousPlinthe) {
          hasFramePlintheBottom = false;
          hasBottomFrame = true;
          showBottomWall = true;
          for (var z in zones) {
            z.hasSashPlintheBottom = false;
            if (hadPreviousFramePlinthe ||
                previousPlintheZoneIds.contains(z.id) ||
                (z.boundary.bottom - (height - previousPlintheHeight)).abs() <
                    5.0) {
              z.boundary = Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                height - profileThickness,
              );
            }
          }
        }
      }

      // Initialize the counterpart from the same system, but never replace
      // an explicitly chosen or saved sliding series.
      final hasPreservedSlidingChoice =
          activeSlidingSeries != null ||
          loadedSlidingSeriesId != null ||
          (loadedSlidingSeriesName != null &&
              loadedSlidingSeriesName!.trim().isNotEmpty);
      if (systemMode == 'mixed' &&
          !hasPreservedSlidingChoice &&
          !zones.any((zone) => zone.content == ZoneContent.slidingSash)) {
        final currentSystem = profileSystemForSeries(availableSystems, series);
        if (currentSystem != null) {
          AluminumSeries? newSliding;
          for (final candidate in currentSystem.series) {
            if (candidate.id != series.id &&
                seriesSupportsDrawingScope(
                  candidate,
                  'sliding',
                  profile: currentSystem,
                )) {
              newSliding = candidate;
              break;
            }
          }

          // If only one series has explicit sliding role metadata, use it
          // before the system-wide fallback. This prevents an unlabelled
          // opening sibling from being selected as the automatic counterpart.
          if (newSliding == null) {
            for (final candidate in currentSystem.series) {
              if (candidate.id != series.id &&
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'sliding',
                    profile: currentSystem,
                  )) {
                newSliding = candidate;
                break;
              }
            }
          }

          // Imported catalogues may contain a multi-series system without
          // role metadata or recognizable names. In that case, use the first
          // series other than the selected opening series as the counterpart.
          if (newSliding == null && currentSystem.series.length > 1) {
            final hasKnownRole = currentSystem.series.any(
              (candidate) =>
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'opening',
                    profile: currentSystem,
                  ) ||
                  seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'sliding',
                    profile: currentSystem,
                  ),
            );
            if (!hasKnownRole) {
              for (final candidate in currentSystem.series) {
                if (candidate.id != series.id) {
                  newSliding = candidate;
                  break;
                }
              }
            }
          }

          if (newSliding == null) {
            for (final sys in availableSystems) {
              if (sys.id == currentSystem.id) continue;
              if (!profileSystemsShareMaterial(currentSystem, sys)) continue;
              for (final candidate in sys.series) {
                if (seriesSupportsDrawingScopeInSystem(
                  candidate,
                  'sliding',
                  profile: sys,
                )) {
                  newSliding = candidate;
                  break;
                }
              }
              if (newSliding != null) break;
            }
          }

          if (newSliding != null) {
            if (activeSlidingSeries?.id != newSliding.id) {
              await _setActiveSlidingSeries(newSliding);
            }
          } else if (activeSlidingSeries == null) {
            slidingFrameOverride = null;
            slidingSashOverride = null;
            _clearSlidingProfileOverrides();
          }
        }
      }
    }

    // Set default frame and sash if they are null
    if (isSliding) {
      if (slidingFrameOverride == null) {
        final frames = configuredSectionsFor(const ['frame']);
        if (frames.isNotEmpty) {
          final candidates = hasShutter
              ? _compatibleFrameCandidatesForSeries(series, frames)
              : (!_isPvcSeries(series)
                    ? frames
                          .where(
                            (frame) => !_sectionHasIntegratedSideCover(frame),
                          )
                          .toList()
                    : frames);
          if (candidates.isNotEmpty) {
            final selected = _preferredSlidingFrameForTrackCount(
              candidates,
              series,
              _requestedSlidingTrackCount(),
            );
            slidingFrameOverride = _slidingFrameMapWithRoleOptions(
              selected,
              series,
            );
          }
        }
      }
      if (slidingSashOverride == null) {
        final sashes = configuredSectionsFor(const ['sash', 'sash_extension']);
        if (sashes.isNotEmpty) {
          slidingSashOverride = sashes.first.toMap();
        }
      }
    }

    if (frameOverride == null) {
      final frames = configuredSectionsFor(const ['frame']);

      if (frames.isNotEmpty) {
        // Only a regular box above an aluminium window requires a plain
        // frame. A tunnel box permits the frame's integrated couvre-joint.
        final candidates = _compatibleFrameCandidatesForSeries(series, frames);
        if (candidates.isNotEmpty) {
          frameOverride = _preferredFrameForSeries(candidates, series).toMap();
        }
      }
    }

    if (sashOverride == null) {
      final sashes = configuredSectionsFor(const ['sash', 'sash_extension']);

      if (sashes.isNotEmpty) {
        sashOverride = sashes.first.toMap();
      }
    }

    // Plant/Plinthe is an independent series role. Do not derive it from
    // the selected sash: a thin or thick sash may use the same plant.
    final configuredPlinthes = configuredSectionsFor(const ['plant']);
    if (configuredPlinthes.isNotEmpty &&
        !componentOverrides.containsKey('بلانت (Plinthe)')) {
      componentOverrides['بلانت (Plinthe)'] = configuredPlinthes.first.toMap();
    }

    final reducers = configuredSectionsFor(const ['reducer']);
    if (reducers.isNotEmpty && hasSimpleGlassForReducer) {
      final rMap = Map<String, dynamic>.from(reducers.first.toMap());
      final rId = rMap['id'] as int?;
      if (rId != null) {
        final colorId = selectedDbColor?['id'] as int?;
        double price = await db.getSectionPrice(rId, colorId);
        if (price <= 0) {
          price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num)
              .toDouble();
        }
        rMap['calculated_price'] = price;
      }
      componentOverrides['ريديكتور (Réducteur)'] = rMap;
      componentOverrides.remove('مخفض الزجاج (Réducteur)');
    } else if (seriesHasConfiguredRoles(series)) {
      clearReducerOverride();
    }

    // Fetch linked renforts for the overrides
    final d = await db.db;
    final rawColorId = selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse('${rawColorId ?? ''}');
    if (d != null) {
      // 🟢 جلب سعر الإطار (frameOverride) من قاعدة البيانات
      if (frameOverride != null) {
        final rawFId = frameOverride!['id'];
        final fId = rawFId is num ? rawFId.toInt() : int.tryParse('${rawFId ?? ''}');
        if (fId != null) {
          double fPrice = await db.getSectionPrice(fId, colorId);
          if (fPrice == 800.0) fPrice = 0.0;
          frameOverride = Map<String, dynamic>.from(frameOverride!);
          frameOverride!['calculated_price'] = fPrice;
        }
      }

      // 🟢 جلب سعر الظلفة (sashOverride) من قاعدة البيانات
      if (sashOverride != null) {
        final rawSId = sashOverride!['id'];
        final sId = rawSId is num ? rawSId.toInt() : int.tryParse('${rawSId ?? ''}');
        if (sId != null) {
          double sPrice = await db.getSectionPrice(sId, colorId);
          if (sPrice == 800.0) sPrice = 0.0;
          sashOverride = Map<String, dynamic>.from(sashOverride!);
          sashOverride!['calculated_price'] = sPrice;
          for (final z in zones) {
            if (z.sashOverride != null) {
              z.sashOverride = Map<String, dynamic>.from(z.sashOverride!);
              z.sashOverride!['calculated_price'] = sPrice;
            }
          }
        }
      }

      // 🟢 جلب سعر التغطية الجانبية (sideCoverOverride) من قاعدة البيانات
      if (sideCoverOverride != null) {
        final rawScId = sideCoverOverride!['id'];
        final scId = rawScId is num ? rawScId.toInt() : int.tryParse('${rawScId ?? ''}');
        if (scId != null) {
          double scPrice = await db.getSectionPrice(scId, colorId);
          if (scPrice == 800.0) scPrice = 0.0;
          sideCoverOverride = Map<String, dynamic>.from(sideCoverOverride!);
          sideCoverOverride!['calculated_price'] = scPrice;
        }
      }

      if (frameOverride != null) {
        final fRes = await d.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [frameOverride!['id']],
        );
        if (fRes.isNotEmpty && fRes.first['linked_renfort_id'] != null) {
          final res = await d.query(
            'Sections',
            where: 'id = ?',
            whereArgs: [fRes.first['linked_renfort_id']],
          );
          if (res.isNotEmpty) {
            final rMap = Map<String, dynamic>.from(res.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الإطار (Renfort Frame)'] = rMap;
          }
        }
      }
      if (sashOverride != null) {
        final sRes = await d.query(
          'Sections',
          where: 'id = ?',
          whereArgs: [sashOverride!['id']],
        );
        if (sRes.isNotEmpty) {
          // 1. Get the linked normal renfort sash
          if (sRes.first['linked_renfort_id'] != null) {
            final res = await d.query(
              'Sections',
              where: 'id = ?',
              whereArgs: [sRes.first['linked_renfort_id']],
            );
            if (res.isNotEmpty) {
              final rMap = Map<String, dynamic>.from(res.first);
              final rId = rMap['id'] as int;
              double price = await db.getSectionPrice(rId, colorId);
              if (price == 800.0) price = 0.0;
              rMap['calculated_price'] = price;
              componentOverrides['حديد الظلفة (Renfort Sash)'] = rMap;
            }
          }

          // 2. Look for the hinge renfort sash (حديد الظلفة الخاص بالمفاصل) in the same series
          final mifsalRes = await d.query(
            'Sections',
            where:
                'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
            whereArgs: [
              series.id,
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
            final rMap = Map<String, dynamic>.from(mifsalRes.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الظلفة الخاص بالمفاصل'] = rMap;
          } else {
            if (componentOverrides.containsKey('حديد الظلفة (Renfort Sash)')) {
              componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  componentOverrides['حديد الظلفة (Renfort Sash)'];
            }
          }
        } else {
          // Fallback if no linked renfort is set for the sash
          final seriesRenforts = await d.query(
            'Sections',
            where:
                'series_id = ? AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
            whereArgs: [
              series.id,
              '%renfort%',
              '%renfort%',
              '%حديد%',
              '%حديد%',
            ],
            orderBy: 'id ASC',
          );
          if (seriesRenforts.length >= 4) {
            // Option 4 (index 3)
            componentOverrides['حديد الظلفة (Renfort Sash)'] =
                Map<String, dynamic>.from(seriesRenforts[3]);
          } else if (seriesRenforts.isNotEmpty) {
            componentOverrides['حديد الظلفة (Renfort Sash)'] =
                Map<String, dynamic>.from(seriesRenforts.last);
          }

          // Look for the hinge renfort sash (حديد الظلفة الخاص بالمفاصل) in the same series
          final mifsalRes = await d.query(
            'Sections',
            where:
                'series_id = ? AND (name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?)',
            whereArgs: [
              series.id,
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
            final rMap = Map<String, dynamic>.from(mifsalRes.first);
            final rId = rMap['id'] as int;
            final colorId = selectedDbColor?['id'] as int?;
            double price = await db.getSectionPrice(rId, colorId);
            if (price == 800.0) price = 0.0;
            rMap['calculated_price'] = price;
            componentOverrides['حديد الظلفة الخاص بالمفاصل'] = rMap;
          } else {
            if (componentOverrides.containsKey('حديد الظلفة (Renfort Sash)')) {
              componentOverrides['حديد الظلفة الخاص بالمفاصل'] =
                  componentOverrides['حديد الظلفة (Renfort Sash)'];
            }
          }
        }
      }

      // 🟢 تحميل تقسيم الزجاج الافتراضي (Mullion/Traverse) مع سعره
      if (!strictProfileRoles &&
          !componentOverrides.containsKey('تقسيم الزجاج (Mullion)')) {
        final mullRes = await d.query(
          'Sections',
          where:
              'series_id = ? AND (LOWER(type) = ? OR LOWER(type) = ? OR LOWER(type) LIKE ? OR LOWER(name) LIKE ?)',
          whereArgs: [series.id, 'mullion', 'traverse', '%mullion%', '%تقسيم%'],
          limit: 1,
        );
        if (mullRes.isNotEmpty) {
          final rMap = Map<String, dynamic>.from(mullRes.first);
          final rId = rMap['id'] as int;
          final colorId = selectedDbColor?['id'] as int?;
          double price = await db.getSectionPrice(rId, colorId);
          if (price == 800.0) price = 0.0;
          rMap['calculated_price'] = price;
          componentOverrides['تقسيم الزجاج (Mullion)'] = rMap;

          // 🟢 تحميل حديد التقسيم الافتراضي (Renfort Mullion) مع سعره
          if (!componentOverrides.containsKey(
            'حديد التقسيم (Renfort Mullion)',
          )) {
            if (rMap['linked_renfort_id'] != null) {
              final renRes = await d.query(
                'Sections',
                where: 'id = ?',
                whereArgs: [rMap['linked_renfort_id']],
              );
              if (renRes.isNotEmpty) {
                final renMap = Map<String, dynamic>.from(renRes.first);
                final renId = renMap['id'] as int;
                double renPrice = await db.getSectionPrice(renId, colorId);
                if (renPrice == 800.0) renPrice = 0.0;
                renMap['calculated_price'] = renPrice;
                componentOverrides['حديد التقسيم (Renfort Mullion)'] = renMap;
              }
            } else {
              // Fallback search
              final renRes = await d.query(
                'Sections',
                where:
                    'series_id = ? AND (type LIKE ? OR name LIKE ?) AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
                whereArgs: [
                  series.id,
                  '%renfort%',
                  '%حديد%',
                  '%mullion%',
                  '%mullion%',
                  '%تقسيم%',
                  '%تقسيم%',
                ],
                limit: 1,
              );
              if (renRes.isNotEmpty) {
                final renMap = Map<String, dynamic>.from(renRes.first);
                final renId = renMap['id'] as int;
                double renPrice = await db.getSectionPrice(renId, colorId);
                if (renPrice == 800.0) renPrice = 0.0;
                renMap['calculated_price'] = renPrice;
                componentOverrides['حديد التقسيم (Renfort Mullion)'] = renMap;
              }
            }
          }
        }
      }

      // 🟢 تحميل باكيت الزجاج الافتراضي (Parclose) مع سعره
      if (!strictProfileRoles &&
          !componentOverrides.containsKey('باكيت الزجاج (Parclose)')) {
        final parRes = await d.query(
          'Sections',
          where:
              'series_id = ? AND (LOWER(type) = ? OR name LIKE ? OR type LIKE ? OR TRIM(code) = ?)',
          whereArgs: [series.id, 'parclose', '%باكيت%', '%parclose%', '514'],
          orderBy: "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, id",
          limit: 1,
        );
        if (parRes.isNotEmpty) {
          final rMap = Map<String, dynamic>.from(parRes.first);
          final rId = rMap['id'] as int;
          final colorId = selectedDbColor?['id'] as int?;
          double price = await db.getSectionPrice(rId, colorId);
          if (price == 800.0) price = 0.0;
          rMap['calculated_price'] = price;
          componentOverrides['باكيت الزجاج (Parclose)'] = rMap;
        }
      }

      // Load default accessories
      await _loadAccessoryDefaults(d, series.id);
    }

    // Set Batmo
    if (!strictProfileRoles &&
        !componentOverrides.containsKey('الباتمو (Batmo)')) {
      var batmos = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return (t.contains('batmo') ||
                n.contains('batmo') ||
                t.contains('باتمو') ||
                n.contains('باتمو')) &&
            !(t.contains('bouchon') ||
                n.contains('bouchon') ||
                t.contains('بوشون') ||
                n.contains('بوشون'));
      }).toList();
      if (batmos.isNotEmpty) {
        final bMap = Map<String, dynamic>.from(batmos.first.toMap());
        final bId = bMap['id'] as int?;
        if (bId != null) {
          double bPrice = await db.getSectionPrice(bId, colorId);
          if (bPrice == 800.0) bPrice = 0.0;
          bMap['calculated_price'] = bPrice;
        }
        componentOverrides['الباتمو (Batmo)'] = bMap;
      } else if (d != null) {
        final res = await d.query(
          'Sections',
          where:
              'series_id = ? AND (type LIKE ? OR name LIKE ? OR type LIKE ? OR name LIKE ?)',
          whereArgs: [series.id, '%batmo%', '%batmo%', '%باتمو%', '%باتمو%'],
        );
        if (res.isNotEmpty) {
          final bMap = Map<String, dynamic>.from(res.first);
          final bId = bMap['id'] as int?;
          if (bId != null) {
            double bPrice = await db.getSectionPrice(bId, colorId);
            if (bPrice == 800.0) bPrice = 0.0;
            bMap['calculated_price'] = bPrice;
          }
          componentOverrides['الباتمو (Batmo)'] = bMap;
        }
      }
    }

    // Bouchon Batmo is deliberately never inferred from a section name. It
    // is loaded only from the explicit `bouchon_batmo` role of this series.

    // Set Default Shutter Components
    if (d != null) {
      Future<void> assignShutterDefault(
        String overrideName,
        List<String> keywords,
      ) async {
        bool needsReassign = true;
        if (componentOverrides.containsKey(overrideName)) {
          needsReassign = false;
          if (overrideName == 'الصندوق (Caisson)' ||
              overrideName.contains('Kit') ||
              overrideName.contains('كيت')) {
            final currentComp = componentOverrides[overrideName];
            if (currentComp != null) {
              final currentSizeStr = getComponentSize(currentComp);
              if (currentSizeStr != null) {
                final cleanSize = currentSizeStr
                    .replaceAll(RegExp(r'[\s.,]'), '')
                    .trim();
                final targetDigits = shutterBoxHeight.toStringAsFixed(0);
                bool matches = cleanSize == targetDigits;
                // Check shorthand for all known sizes
                if (targetDigits == "105" &&
                    (cleanSize == "10" ||
                        cleanSize == "100" ||
                        cleanSize == "105")) {
                  matches = true;
                }
                if (targetDigits == "155" &&
                    (cleanSize == "15" ||
                        cleanSize == "150" ||
                        cleanSize == "155")) {
                  matches = true;
                }
                if (targetDigits == "185" &&
                    (cleanSize == "18" ||
                        cleanSize == "180" ||
                        cleanSize == "185")) {
                  matches = true;
                }
                if (targetDigits == "205" &&
                    (cleanSize == "20" ||
                        cleanSize == "200" ||
                        cleanSize == "205")) {
                  matches = true;
                }
                if (!matches) {
                  needsReassign = true;
                }
              } else {
                needsReassign = true;
              }
            } else {
              needsReassign = true;
            }
          }
        }

        if (needsReassign) {
          try {
            List<Map<String, dynamic>> res = [];
            if (overrideName == 'الشرائح (Lames)' && shutterLame.isNotEmpty) {
              try {
                res = await d.query(
                  'ShutterComponents',
                  where: "name = ? AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: [shutterLame],
                );
              } catch (e) {
                print('Error query exact shutterLame: $e');
              }
            }
            if (res.isEmpty) {
              String whereClause = keywords
                  .map((_) => 'name LIKE ? OR component_type LIKE ?')
                  .join(' OR ');
              List<String> args = [];
              for (var kw in keywords) {
                args.addAll(['%$kw%', '%$kw%']);
              }
              try {
                res = await d.query(
                  'ShutterComponents',
                  where:
                      "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
                  whereArgs: args,
                );
              } catch (error) {
                reportCatalogIssue('ShutterComponents (blade)', error);
              }
            }
            if (overrideName == 'الشرائح (Lames)') {
              res = res.where(WindowModel.isShutterBladeComponent).toList();
            }
            if (res.isNotEmpty) {
              Map<String, dynamic>? bestMatch;

              if (overrideName == 'الشرائح (Lames)') {
                // Search for 43 or x
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('43') || name.contains('x')) {
                    if (!name.contains('final') &&
                        !name.contains('finale') &&
                        !name.contains('نهائي')) {
                      bestMatch = row;
                      break;
                    }
                  }
                }
              } else if (overrideName == 'السكك (Coulisses)') {
                // Search for 25
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('25')) {
                    bestMatch = row;
                    break;
                  }
                }
              } else if (overrideName == 'الشريحة النهائية (Lame Finale)' ||
                  overrideName.contains('نهائ')) {
                // Search for 45
                for (var row in res) {
                  final name = row['name'].toString().toLowerCase();
                  if (name.contains('45')) {
                    bestMatch = row;
                    break;
                  }
                }
              } else if (overrideName == 'المحور (Axe)' ||
                  overrideName.contains('محور')) {
                bestMatch = _selectCompatibleShutterAxis(res);
              } else if (overrideName == 'الصندوق (Caisson)' ||
                  overrideName.contains('Kit') ||
                  overrideName.contains('كيت')) {
                final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
                final targetDigits = targetSize.toStringAsFixed(0);
                for (var row in res) {
                  final rowSize = getComponentSize(row);
                  if (rowSize != null) {
                    final cleanRowSize = rowSize
                        .replaceAll(RegExp(r'[\s.,]'), '')
                        .trim();
                    if (cleanRowSize == targetDigits) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "105" &&
                        (cleanRowSize == "10" ||
                            cleanRowSize == "100" ||
                            cleanRowSize == "105")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "155" &&
                        (cleanRowSize == "15" ||
                            cleanRowSize == "150" ||
                            cleanRowSize == "155")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "185" &&
                        (cleanRowSize == "18" ||
                            cleanRowSize == "180" ||
                            cleanRowSize == "185")) {
                      bestMatch = row;
                      break;
                    }
                    if (targetDigits == "205" &&
                        (cleanRowSize == "20" ||
                            cleanRowSize == "200" ||
                            cleanRowSize == "205")) {
                      bestMatch = row;
                      break;
                    }
                  }
                }
              }

              final isAxis =
                  overrideName == 'المحور (Axe)' ||
                  overrideName.contains('محور');
              if (!isAxis || bestMatch != null) {
                componentOverrides[overrideName] = Map<String, dynamic>.from(
                  bestMatch ?? res.first,
                );
              }
            }
          } catch (e) {
            print('Error assigning shutter default for $overrideName: $e');
          }
        }
      }

      await assignShutterDefault('الصندوق (Caisson)', [
        'box',
        'صندوق',
        'caisson',
      ]);
      await assignShutterDefault('الشرائح (Lames)', ['blade', 'شريح', 'lame']);
      await assignShutterDefault('الشريحة النهائية (Lame Finale)', [
        'final_blade',
        'lame final',
        'نهائي',
      ]);
      await assignShutterDefault('السكك (Coulisses)', [
        'track',
        'سك',
        'coulisse',
      ]);
      await assignShutterDefault('المحور (Axe)', ['laxe', 'axe', 'محور']);

      // Kits are loaded exclusively from KitBundles by the quantity table.
      // Never create a kit override from ShutterComponents here: that could
      // turn an unrelated shutter part into a false "Kit volet moteur".
    }

    var bouchons2 = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      return t.contains('bouchon batmo') ||
          t.contains('bouchon batment') ||
          t.contains('غطاء الباتمو');
    }).toList();
    if (!strictProfileRoles &&
        bouchons2.isNotEmpty &&
        !componentOverrides.containsKey('غطاء الباتمو (Bouchon Batment)')) {
      componentOverrides['غطاء الباتمو (Bouchon Batment)'] = bouchons2.first
          .toMap();
    }

    var parcloses = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      return s.code.trim() == '514' ||
          t.contains('parclose') ||
          n.contains('parclose') ||
          t.contains('باكيت') ||
          n.contains('باكيت');
    }).toList();
    parcloses.sort((a, b) {
      final aPriority = a.code.trim() == '514' ? 0 : 1;
      final bPriority = b.code.trim() == '514' ? 0 : 1;
      return aPriority.compareTo(bPriority);
    });
    if (!strictProfileRoles && parcloses.isNotEmpty) {
      const key = 'باكيت الزجاج (Parclose)';
      final current = componentOverrides[key];
      final currentMax = current is Map
          ? (current['max_glass_thickness'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      final preferred514 = parcloses.where((s) => s.code.trim() == '514');
      if (current == null || (preferred514.isNotEmpty && currentMax <= 10.0)) {
        componentOverrides[key] = preferred514.isNotEmpty
            ? preferred514.first.toMap()
            : parcloses.first.toMap();
      }
    }

    var mullions = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      if (t.contains('sash') || t.contains('ouvrant') || t.contains('ظلفة')) {
        return false;
      }
      if (n.contains('sash') || n.contains('ouvrant') || n.contains('ظلفة')) {
        return false;
      }
      return t.contains('mullion') ||
          t.contains('traverse') ||
          t.contains('تقسيم');
    }).toList();
    if (!strictProfileRoles &&
        mullions.isNotEmpty &&
        !componentOverrides.containsKey('تقسيم الزجاج (Mullion)')) {
      componentOverrides['تقسيم الزجاج (Mullion)'] = mullions.first.toMap();
    }

    var rails = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      return t == 'rail' ||
          t.contains('rail') ||
          t == 'الري' ||
          t.contains('الري') ||
          t == 'راي' ||
          t.contains('راي');
    }).toList();
    if (!strictProfileRoles &&
        rails.isNotEmpty &&
        !componentOverrides.containsKey('الري (Rail)')) {
      final rMap = Map<String, dynamic>.from(rails.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الري (Rail)'] = rMap;
    }

    var chicanes = series.sections.where((s) {
      final t = s.type.toLowerCase().trim();
      final n = s.name.toLowerCase().trim();
      return t.contains('chicane') ||
          n.contains('chicane') ||
          t.contains('شيكان') ||
          n.contains('شيكان');
    }).toList();
    if (!strictProfileRoles &&
        chicanes.isNotEmpty &&
        !componentOverrides.containsKey('الشيكان (Chicane)')) {
      final rMap = Map<String, dynamic>.from(chicanes.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['الشيكان (Chicane)'] = rMap;
    }

    var bardages = configuredSectionsFor(const ['bardage']);
    if (bardages.isEmpty && !strictProfileRoles) {
      bardages = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return isBardagePanelSubtype(t) || isBardagePanelSubtype(n);
      }).toList();
    }
    if (bardages.isNotEmpty &&
        !componentOverrides.containsKey('البارداج (Bardage)')) {
      final rMap = Map<String, dynamic>.from(bardages.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['البارداج (Bardage)'] = rMap;
    }

    final panneaux = configuredSectionsFor(const ['panneau']);
    if (panneaux.isNotEmpty &&
        !componentOverrides.containsKey('البانو (Panneau)')) {
      final rMap = Map<String, dynamic>.from(panneaux.first.toMap());
      final rId = rMap['id'] as int;
      final colorId = selectedDbColor?['id'] as int?;
      double price = await db.getSectionPrice(rId, colorId);
      if (price <= 0) {
        price = ((rMap['price_dzd'] ?? rMap['price'] ?? 0.0) as num).toDouble();
      }
      rMap['calculated_price'] = price;
      componentOverrides['البانو (Panneau)'] = rMap;
    }

    updateProfileThickness();
    if (seriesChanged && affectsVisibleDivisions) {
      _synchronizeDivisionGapsForSeries(
        previousFrameThickness,
        previousMullionThickness,
      );
    }
    updateAllSashThicknesses();
    _synchronizeSharedSideCover();
    await _loadColorsForProfile(series.profileId);
    await _ensureParcloseForCurrentGlass();
    await refreshSectionPricesForSelectedColor(notify: false);
    await refreshBardageColorPrices(notify: false);
    availableAccessoryColors = await db.readAccessoryColors();

    // فلترة أي إكسسوار متبقٍ غير مربوط بهذه السلسلة حتى عند فتح طلب قديم.
    if (d != null) {
      await _filterComponentsByActiveSeries(series, d);
      // إعادة ملء ما أزيل بالاختيار الافتراضي المفلتر للسلسلة نفسها.
      await _loadAccessoryDefaults(d, series.id);
    }

    _notifyModelListeners();
  }

  bool _catalogRowMatchesSeriesScope(
    Map<String, dynamic> row,
    AluminumSeries? series,
  ) {
    if (series == null) return true;
    final directId = int.tryParse((row['series_id'] ?? '').toString().trim());
    final linkedIds = (row['series_ids'] ?? '')
        .toString()
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .where((id) => id > 0)
        .toSet();
    if ((directId == null || directId <= 0) && linkedIds.isEmpty) return true;
    return directId == series.id || linkedIds.contains(series.id);
  }

  void toggleWallColor(String value) {
    _saveSnapshot();
    wallColor = value;
    _notifyModelListeners();
  }

  void updateProfileThickness() {
    double oldThickness = profileThickness;
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final activeFrame = useSliding
        ? (slidingFrameOverride ??
              getConfiguredSectionForRole(
                'frame',
                useSlidingSeries: true,
              )?.toMap() ??
              getSlidingBaseFrameSection()?.toMap())
        : (activeFrameOverride ??
              getConfiguredSectionForRole(
                'frame',
                useSlidingSeries: false,
              )?.toMap() ??
              frameOverride);
    final series = useSliding ? activeSlidingSeries : activeSeries;

    if (activeFrame != null) {
      double t = (activeFrame['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) {
        profileThickness = t;
      } else {
        profileThickness =
            (activeFrame['thickness'] as num?)?.toDouble() ?? profileThickness;
      }
    } else if (series != null && series.sections.isNotEmpty) {
      final frames = series.sections
          .where((s) => s.isFrame || s.type.toLowerCase() == 'frame')
          .toList();
      if (frames.isNotEmpty) {
        AluminumSection targetFrame;
        if (!useSliding &&
            selectedFrameCode != null &&
            selectedFrameCode!.isNotEmpty) {
          targetFrame = frames.firstWhere(
            (s) => s.code == selectedFrameCode,
            orElse: () => frames.first,
          );
        } else {
          targetFrame = frames.firstWhere(
            (s) => isFrame140 ? s.code.contains('140') : s.code.contains('103'),
            orElse: () => frames.first,
          );
        }
        profileThickness = targetFrame.visibleWidth > 0
            ? targetFrame.visibleWidth
            : (targetFrame.thickness > 0 ? targetFrame.thickness : 40.0);
      } else {
        profileThickness = isFrame140 ? 70.0 : 40.0;
      }
    }
    // Without any frame data (no series yet, e.g. while the catalogue is
    // loading) the current thickness is kept. Forcing 40 mm here moved the
    // zones of a drawing on every undo made before the catalogue was ready.

    if (oldThickness != profileThickness) {
      double topOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
          ? shutterBoxHeight
          : 0.0;
      bool isSameEdge(double value, double expected) =>
          (value - expected).abs() <= 1.0;
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          isSameEdge(z.boundary.left, oldThickness)
              ? profileThickness
              : z.boundary.left,
          isSameEdge(z.boundary.top, topOffset + oldThickness)
              ? (topOffset + profileThickness)
              : z.boundary.top,
          isSameEdge(z.boundary.right, width - oldThickness)
              ? width - profileThickness
              : z.boundary.right,
          isSameEdge(z.boundary.bottom, height - oldThickness)
              ? height - profileThickness
              : z.boundary.bottom,
        );
      }
    }
    _synchronizeSingleZoneWithOuterFrame();
  }

  int? _catalogueId(Map<String, dynamic>? value) {
    final raw = value?['id'];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  }

  /// Series whose catalogue profiles this drawing may currently use.
  Set<AluminumSeries> get _seriesInDrawingContext {
    final usesSliding =
        systemMode == 'sliding' ||
        systemMode == 'mixed' ||
        zones.any((zone) => zone.content == ZoneContent.slidingSash);
    return {
      if (activeSeries != null) activeSeries!,
      if (usesSliding && activeSlidingSeries != null) activeSlidingSeries!,
    };
  }

  /// Whether a stored profile row (a section map with a `code`) may be used
  /// by the series of this drawing. Sections shared into the series, and
  /// sibling series of the same profile system, stay valid; a profile from
  /// another system (for example BS 90 kept after switching to PVC) does not.
  bool isSectionOverrideInDrawingContext(Map<dynamic, dynamic> section) {
    final contextSeries = _seriesInDrawingContext;
    if (contextSeries.isEmpty) return true;
    int? readId(Object? raw) =>
        raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}'.trim());

    final sectionId = readId(section['id']);
    if (sectionId != null &&
        contextSeries.any(
          (series) => series.sections.any((s) => s.id == sectionId),
        )) {
      return true;
    }
    final ownerSeriesId =
        readId(section['series_id']) ?? readId(section['source_series_id']);
    // Rows without a catalogue owner (manual or legacy data) cannot be
    // checked here and are left to the existing per-role resolution.
    if (ownerSeriesId == null || ownerSeriesId == 0) return true;
    if (contextSeries.any((series) => series.id == ownerSeriesId)) return true;
    final sharedTarget = readId(section['sharing_target_id']);
    if (sharedTarget != null &&
        contextSeries.any((series) => series.id == sharedTarget)) {
      return true;
    }

    int? ownerProfileId = readId(section['source_profile_id']);
    if (ownerProfileId == null) {
      for (final system in availableSystems) {
        if (system.series.any((series) => series.id == ownerSeriesId)) {
          ownerProfileId = system.id;
          break;
        }
      }
    }
    return ownerProfileId != null &&
        contextSeries.any((series) => series.profileId == ownerProfileId);
  }

  /// Stored profile choices that belong to a series outside this drawing's
  /// context. The BOM must not be trusted while this list is not empty.
  List<String> get overridesFromForeignSeries =>
      _overridesFromForeignSeries(remove: false);

  /// Removes every stored profile choice that belongs to a series outside
  /// this drawing's context. Removing overrides by their (translated) key
  /// name missed every role added later; this check uses catalogue identity.
  /// Returns the removed component keys.
  List<String> removeOverridesFromForeignSeries() {
    final removed = _overridesFromForeignSeries(remove: true);
    if (removed.isNotEmpty) {
      debugPrint('Removed profiles from another series: ${removed.join(', ')}');
    }
    return removed;
  }

  List<String> _overridesFromForeignSeries({required bool remove}) {
    final found = <String>[];
    bool foreign(Map<dynamic, dynamic>? section) =>
        section != null && !isSectionOverrideInDrawingContext(section);

    for (final key in componentOverrides.keys.toList()) {
      final value = componentOverrides[key];
      if (value is! Map || !value.containsKey('code') || !foreign(value)) {
        continue;
      }
      found.add(key);
      if (remove) componentOverrides.remove(key);
    }
    for (final key in mullionSectionOverrides.keys.toList()) {
      if (!foreign(mullionSectionOverrides[key])) continue;
      found.add('mullionSectionOverrides:$key');
      if (remove) mullionSectionOverrides.remove(key);
    }
    if (foreign(sideCoverOverride)) {
      found.add('sideCoverOverride');
      if (remove) sideCoverOverride = null;
    }
    if (foreign(internalSlidingSideCoverOverride)) {
      found.add('internalSlidingSideCoverOverride');
      if (remove) internalSlidingSideCoverOverride = null;
    }
    for (final zone in zones) {
      if (foreign(zone.sashOverride)) {
        found.add('zone:${zone.id}:sashOverride');
        if (remove) zone.sashOverride = null;
      }
      if (foreign(zone.slidingSashOverride)) {
        found.add('zone:${zone.id}:slidingSashOverride');
        if (remove) zone.slidingSashOverride = null;
      }
      final foreignCells = zone.cellSashOverrides.entries
          .where((entry) => foreign(entry.value))
          .map((entry) => entry.key)
          .toList();
      if (foreignCells.isEmpty) continue;
      found.addAll(foreignCells.map((key) => 'zone:${zone.id}:$key'));
      if (remove) {
        zone.cellSashOverrides = Map<String, Map<String, dynamic>>.from(
          zone.cellSashOverrides,
        )..removeWhere((key, _) => foreignCells.contains(key));
      }
    }
    return found;
  }

  void _clearAccessoryOverrides() {
    componentOverrides.remove('المقبض (Handle)');
    componentOverrides.remove('مقبض نافذة (Poignée Fenêtre)');
    componentOverrides.remove('كومباس (Compas)');
    componentOverrides.remove('عجلات المنزلق (Roulettes)');
    componentOverrides.remove('اسبانيولات المنزلق (Espagnolette)');
    componentOverrides.remove('إسبانيوليت (Espagnolette)');
    componentOverrides.remove('المفاصل (Hinges)');
    componentOverrides.remove('الفيرو (Verrou)');
    componentOverrides.remove('كاش كوليسون (Gache coulissant)');
    componentOverrides.remove('Gâche coulissant TPR');
    componentOverrides.remove('قاش بورت (Gache Porte)');
    componentOverrides.remove('مقبض الباب (Poignée Porte à Clé)');
    componentOverrides.remove('الأسطوانة (Canon)');
    componentOverrides.remove('قفل الباب (Serrure)');
    componentOverrides.remove('كريمون (Cremone)');
    componentOverrides.remove('تراينغل الكريمون (Triangle)');
    componentOverrides.remove('بوشون بارك لوز (Bouchon Parclose)');
    componentOverrides.remove('أونتروماتيك (Entrematique)');
    componentOverrides.remove('كيت 67000 (Kit 67000)');
    componentOverrides.remove('كيت 76000 (Kit 76000)');
    componentOverrides.remove('كيت 40000 (Kit 40000)');
    componentOverrides.remove('قاش (Gache)');
    componentOverrides.remove('جوان بروس للظلفة (Joint Brosse Sash)');
    componentOverrides.remove('جوان بروس للستار (Joint Brosse Shutter)');
    componentOverrides.remove('الطاسو (Tasso)');
    componentOverrides.remove('جوان الزجاج (Joint Vitrage)');
  }

  /// فلترة الإكسسوارات حسب السلسلة الحالية.
  /// تحذف أي إكسسوار غير مربوط صراحةً بالسلسلة ولا تمس البروفيلات أو الستار.
  Future<void> _filterComponentsByActiveSeries(
    AluminumSeries series,
    dynamic db,
  ) async {
    if (db == null || activeSeries == null) return;

    final seriesId = series.id;
    final keysToCheck = List<String>.from(componentOverrides.keys);

    for (final key in keysToCheck) {
      final component = componentOverrides[key];
      // Drawing-state overrides (for example `frame-bottom:<zoneId>`) are
      // booleans, while catalogue components are maps. Series changes must
      // ignore non-catalogue state instead of attempting component['id'].
      if (component is! Map) continue;
      final componentMap = Map<String, dynamic>.from(component);

      // تجاهل المكونات التي تأتي من البيانات المحلية وليست من قاعدة البيانات
      if (componentMap['id'] == null) continue;

      // تجاهل الأقسام، مكونات الستار، والجوانات. الحقول المتشابهة بين الجداول
      // كانت تجعل القسم يُفحص خطأً داخل Accessories ثم يُحذف.
      final isSection = componentMap.containsKey('code');
      final isShutter = componentMap.containsKey('component_type');
      final isJoint = componentMap.containsKey('gasket_type');
      final isAccessory =
          componentMap.containsKey('material_type') ||
          componentMap.containsKey('screw_count');
      final tableToCheck = isAccessory && !isSection && !isShutter && !isJoint
          ? 'Accessories'
          : null;

      if (tableToCheck != null) {
        try {
          // البحث عن المكون في قاعدة البيانات
          final result = await db.query(
            tableToCheck,
            where: 'id = ?',
            whereArgs: [componentMap['id']],
            limit: 1,
          );

          if (result.isEmpty) {
            componentOverrides.remove(key);
            continue;
          }

          final dbComponent = result.first;
          final componentSeriesId = dbComponent['series_id'];
          final componentSeriesIds =
              dbComponent['series_ids']?.toString() ?? '';
          final materialType = (dbComponent['material_type'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final seriesIsPvc = _isPvcSeries(series);
          final materialMatches = seriesIsPvc
              ? (materialType == 'pvc' || materialType == 'both')
              : (materialType == 'aluminium' ||
                    materialType == 'aluminum' ||
                    materialType == 'both' ||
                    materialType.isEmpty);

          bool belongsToCurrentSeries = false;

          // إذا كان series_id متطابقاً
          if (componentSeriesId == seriesId) {
            belongsToCurrentSeries = true;
          }
          // أو إذا كان series_ids يحتوي على series_id الحالي
          else if (componentSeriesIds.isNotEmpty) {
            final ids = componentSeriesIds
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (ids.contains(seriesId.toString())) {
              belongsToCurrentSeries = true;
            }
          }

          if (!materialMatches || !belongsToCurrentSeries) {
            componentOverrides.remove(key);
          }
        } catch (e) {
          // في حالة الخطأ، نحتفظ بالمكون
          print('Error filtering component $key: $e');
        }
      }
    }
  }

  Future<void> _loadAccessoryDefaults(dynamic d, int seriesId) async {
    await _loadJointRuleDefaults(d, seriesId);
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

    final matType = isPVC ? 'PVC' : 'Aluminium';

    String sName = '';
    try {
      final List<Map<String, dynamic>> seriesRes = await d.query(
        'Series',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [seriesId],
      );
      if (seriesRes.isNotEmpty) {
        sName = (seriesRes.first['name'] ?? '').toString().toLowerCase();
      }
    } catch (e) {
      sName = (activeSlidingSeries?.name ?? activeSeries?.name ?? '')
          .toLowerCase();
    }
    final bool isTPRSeries =
        sName.contains('tpr') ||
        sName.contains('tpi') ||
        sName.contains('67000');

    double readPrice(dynamic value) {
      final price = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
      return price.isFinite && price >= 0 ? price : 0.0;
    }

    // An accessory either uses its raw/base price or a color-price list.
    // Once color prices exist, only the selected color is valid: there must
    // be no fallback to the base price or to another color's price.
    Future<double> resolveAccessoryPrice(Map<String, dynamic> accessory) async {
      final accessoryId = accessory['id'];
      if (accessoryId == null) return 0.0;

      try {
        final colorPrices = await d.query(
          'AccessoryColorPrices',
          columns: ['color_id', 'price'],
          where: 'accessory_id = ?',
          whereArgs: [accessoryId],
        );
        if (colorPrices.isEmpty) {
          return readPrice(accessory['price_dzd'] ?? accessory['price']);
        }

        final selectedColorId = selectedAccessoryColor?['id'];
        // No accessory colour means a genuinely colourless accessory. Its
        // base price remains authoritative; profile colour is unrelated.
        if (selectedColorId == null) {
          return readPrice(accessory['price_dzd'] ?? accessory['price']);
        }
        for (final colorPrice in colorPrices) {
          if (colorPrice['color_id']?.toString() ==
              selectedColorId.toString()) {
            return readPrice(colorPrice['price']);
          }
        }
        return 0.0;
      } catch (_) {
        // Preserve the base price only for legacy databases where the
        // color-price table is not available yet.
        return readPrice(accessory['price_dzd'] ?? accessory['price']);
      }
    }

    String? ruleKeyForAccessoryDefault(String key) {
      final lower = key.toLowerCase();
      if (lower.contains('tringle') ||
          lower.contains('tangle') ||
          lower.contains('triangle') ||
          key.contains('تراينغل') ||
          key.contains('تريانغل')) {
        return 'tringle';
      }
      if (key == 'كريمون (Cremone)' ||
          lower.contains('cremone') ||
          lower.contains('crémone') ||
          key.contains('كريمون')) {
        return 'cremone';
      }
      if (key == 'الفيرو (Verrou)' ||
          (lower.contains('verrou') && !lower.contains('central')) ||
          key.contains('فيرو')) {
        return 'verrou';
      }
      if (key == 'كاش كوليسون (Gache coulissant)' ||
          key == 'Gâche coulissant TPR') {
        return 'sliding_lock';
      }
      if (key.contains('قاش دوبل')) return 'gache_double';
      if (key.contains('قاش بورت')) return 'gache_door';
      if (key.contains('قاش') || lower.contains('gache')) {
        return 'gache_simple';
      }
      if (lower.contains('espagnolette') ||
          key.contains('اسبانيول') ||
          key.contains('إسبانيول')) {
        return 'espagnolette';
      }
      if (lower.contains('poignée porte') || lower.contains('poignee porte')) {
        return lower.contains('condamnation')
            ? 'door_handle_condamnation'
            : 'door_handle_key';
      }
      if ((lower.contains('poignée') || lower.contains('poignee')) &&
          lower.contains('condamnation')) {
        return 'door_handle_condamnation';
      }
      if (lower.contains('condamnation')) return 'lock_condamnation';
      if (lower.contains('encastr') || key.contains('مدمج')) {
        return 'poignee_encastree';
      }
      if (lower.contains('poignée') ||
          lower.contains('poignee') ||
          lower.contains('handle') ||
          key.contains('مقبض')) {
        return 'handle';
      }
      if (lower.contains('paumelle') || key.contains('مفاصل')) return 'hinge';
      if (lower.contains('canon') || key.contains('أسطوانة')) return 'canon';
      if (lower.contains('serrure') || key.contains('قفل')) return 'lock_clef';
      if (lower.contains('roulette') || key.contains('عجلات')) {
        return 'roulette';
      }
      if (lower.contains('tasso') || key.contains('الطاسو')) return 'tasso';
      if (lower.contains('ekar') ||
          lower.contains('ikar') ||
          key.contains('إيكار') ||
          key.contains('ايكار')) {
        return 'ekar';
      }
      if (lower.contains('entrematique') || key.contains('أونتروماتيك')) {
        return 'entrematique';
      }
      if ((lower.contains('40000') || key.contains('40000')) &&
          (lower.contains('kit') || key.contains('كيت'))) {
        return 'sliding_kit_40000';
      }
      if ((lower.contains('67000') || key.contains('67000')) &&
          (lower.contains('kit') || key.contains('كيت'))) {
        return 'sliding_kit_67000';
      }
      if (lower.contains('kit') || key.contains('كيت')) return 'sliding_kit';
      if (lower.contains('clam') || key.contains('كلام')) {
        return 'clam';
      }
      return null;
    }

    Future<void> loadAccessory(String key, List<String> searchPatterns) async {
      if (componentOverrides.containsKey(key)) return;

      Future<Map<String, dynamic>?> loadRelatedAccessory(dynamic rawId) async {
        final relatedId = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        if (relatedId == null) return null;
        try {
          final related = await d.query(
            'Accessories',
            where: '(is_active = 1 OR is_active IS NULL) AND id = ?',
            whereArgs: [relatedId],
            limit: 1,
          );
          return related.isEmpty
              ? null
              : Map<String, dynamic>.from(related.first);
        } catch (_) {
          return null;
        }
      }

      bool isAccessoryValid(Map<String, dynamic> acc) {
        final n = acc['name'].toString().toLowerCase();
        final ty = (acc['type'] ?? '').toString().toLowerCase();

        // 1. Material Exclusions
        if (matType == 'PVC') {
          if (n.contains('aluminium') ||
              n.contains('aluminum') ||
              n.contains('alu') ||
              n.contains('ألمنيوم') ||
              ty.contains('aluminium') ||
              ty.contains('aluminum') ||
              ty.contains('alu') ||
              ty.contains('ألمنيوم')) {
            return false;
          }
        } else {
          // Aluminium
          if (n.contains('pvc') ||
              ty.contains('pvc') ||
              n.contains('clan') ||
              ty.contains('clan') ||
              n.contains('clane') ||
              ty.contains('clane') ||
              n.contains('كلان') ||
              ty.contains('كلان')) {
            return false;
          }
        }

        // 2. Series Name Exclusions
        if (sName.isNotEmpty) {
          if (sName.contains('67000') || sName.contains('67')) {
            if (n.contains('76000') ||
                n.contains('76') ||
                ty.contains('76000') ||
                ty.contains('76') ||
                n.contains('60000') ||
                n.contains('60') ||
                ty.contains('60000') ||
                ty.contains('60') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('76000') || sName.contains('76')) {
            if (n.contains('67000') ||
                n.contains('67') ||
                ty.contains('67000') ||
                ty.contains('67') ||
                n.contains('60000') ||
                n.contains('60') ||
                ty.contains('60000') ||
                ty.contains('60') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          } else if (sName.contains('60000') || sName.contains('60')) {
            if (n.contains('67000') ||
                n.contains('67') ||
                ty.contains('67000') ||
                ty.contains('67') ||
                n.contains('76000') ||
                n.contains('76') ||
                ty.contains('76000') ||
                ty.contains('76') ||
                n.contains('52000') ||
                n.contains('52') ||
                ty.contains('52000') ||
                ty.contains('52') ||
                n.contains('45000') ||
                n.contains('45') ||
                ty.contains('45000') ||
                ty.contains('45')) {
              return false;
            }
          }

          // 3. System Mode Exclusions
          final isSliding = systemMode == 'sliding';
          if (isSliding) {
            if (n.contains('paumelle') ||
                ty.contains('paumelle') ||
                n.contains('mifsal') ||
                ty.contains('mifsal') ||
                n.contains('مفاصل') ||
                ty.contains('مفاصل') ||
                n.contains('مفصل') ||
                ty.contains('مفصل') ||
                n.contains('system ob') ||
                ty.contains('system ob') ||
                n.contains('demi system ob') ||
                ty.contains('demi system ob') ||
                n.contains('verrou central') ||
                ty.contains('verrou central') ||
                n.contains('gache simple') ||
                ty.contains('gache simple') ||
                n.contains('gache double') ||
                ty.contains('gache double') ||
                n.contains('قاش دوبل') ||
                ty.contains('قاش دوبل') ||
                n.contains('قاش سامبل') ||
                ty.contains('قاش سامبل') ||
                n.contains('فتح') ||
                ty.contains('فتح') ||
                n.contains('ouvrant') ||
                ty.contains('ouvrant')) {
              return false;
            }
          } else {
            if (n.contains('couliss') ||
                ty.contains('couliss') ||
                n.contains('roulette') ||
                ty.contains('roulette') ||
                n.contains('عجلات') ||
                ty.contains('عجلات') ||
                n.contains('منزلق') ||
                ty.contains('منزلق')) {
              return false;
            }
          }
        }

        // 4. Kit Clamp/Clan Exclusions (Exclude clamp from kit matching, and vice versa)
        final isKitKey =
            key.toLowerCase().contains('kit') || key.contains('كيت');
        final isClampKey =
            key.toLowerCase().contains('clamp') ||
            key.toLowerCase().contains('clam') ||
            key.contains('كلامب') ||
            key.contains('كلام') ||
            key.contains('كلان');

        final hasKitName =
            n.contains('kit') ||
            ty.contains('kit') ||
            n.contains('كيت') ||
            ty.contains('كيت');
        final hasClampName =
            n.contains('clamp') ||
            n.contains('clam') ||
            ty.contains('clamp') ||
            ty.contains('clam') ||
            n.contains('كلامب') ||
            n.contains('كلام') ||
            n.contains('كلان') ||
            ty.contains('كلامب') ||
            ty.contains('كلام') ||
            ty.contains('كلان') ||
            n.contains('clan') ||
            ty.contains('clan');

        if (isKitKey && hasClampName) return false;
        if (isClampKey && hasKitName) return false;

        // المقابض العادية للنوافذ لا تقبل مقابض الأبواب أو المقابض الخاصة.
        // الفلتر النصي العام كان يلتقط Rotax وCalimaster رغم عدم صلاحيتهما
        // لنافذة PVC عادية.
        final isWindowHandleKey =
            key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)';
        if (isWindowHandleKey) {
          final category = ty.split('|').first.trim();
          final isExplicitWindowHandle =
              category.contains('poignée fenêtre') ||
              category.contains('poignee fenetre') ||
              category.contains('window handle') ||
              category.contains('مقبض نافذة');
          if (isExplicitWindowHandle) return true;

          final isExplicitDoorHandle =
              category.contains('poignée porte') ||
              category.contains('poignee porte') ||
              category.contains('door handle') ||
              category.contains('مقبض باب') ||
              category.contains('condamnation');
          if (isExplicitDoorHandle) return false;

          final hasHandle =
              n.contains('poignée') ||
              ty.contains('poignée') ||
              n.contains('poignee') ||
              ty.contains('poignee') ||
              n.contains('handle') ||
              ty.contains('handle') ||
              n.contains('مقبض') ||
              ty.contains('مقبض');
          final isDoorOrSpecial =
              n.contains('porte') ||
              ty.contains('porte') ||
              n.contains('door') ||
              ty.contains('door') ||
              n.contains('clé') ||
              ty.contains('clé') ||
              n.contains('clef') ||
              ty.contains('clef') ||
              n.contains('condamnation') ||
              ty.contains('condamnation') ||
              n.contains('rotax') ||
              ty.contains('rotax') ||
              n.contains('calimaster') ||
              ty.contains('calimaster') ||
              n.contains('maréchal') ||
              ty.contains('maréchal') ||
              n.contains('marechal') ||
              ty.contains('marechal');
          if (!hasHandle || isDoorOrSpecial) return false;
        }

        return true;
      }

      final ruleKey = ruleKeyForAccessoryDefault(key);
      if (ruleKey != null) {
        final ruleKeys = <String>[ruleKey];
        if (ruleKey == 'sliding_kit_40000' || ruleKey == 'sliding_kit_67000') {
          // Keep generic rules created before the series-specific roles.
          ruleKeys.add('sliding_kit');
        }
        final ruleRows = await db.getCatalogItemRules(
          itemTable: 'Accessories',
          seriesId: seriesId,
          roleKeys: ruleKeys,
          exactSeriesOnly: true,
        );
        final effectiveEspagnoletteHeight = effectiveEspagnoletteHeightMm;
        bool ruleMatchesEspagnoletteRange(Map<String, dynamic> rule) {
          if (ruleKey != 'espagnolette') return true;
          return catalogEspagnoletteRuleMatches(
            rule,
            effectiveHeightMm: effectiveEspagnoletteHeight,
          );
        }

        for (final rule in ruleRows) {
          if (rule['show_in_quantity'] == 0) continue;
          if (!ruleScopeMatches(rule)) continue;
          if (!ruleMatchesEspagnoletteRange(rule)) continue;
          final itemId = (rule['item_id'] as num?)?.toInt();
          if (itemId == null) continue;
          final rows = await d.query(
            'Accessories',
            where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
            whereArgs: [itemId],
            limit: 1,
          );
          if (rows.isEmpty) continue;
          if (!isAccessoryValid(rows.first)) continue;
          final selected = Map<String, dynamic>.from(rows.first);
          selected['calculated_price'] = await resolveAccessoryPrice(selected);
          final linkedGache = await loadRelatedAccessory(
            selected['linked_accessory_id'] ?? selected['gache_accessory_id'],
          );
          if (linkedGache != null) {
            selected['linked_accessory'] = linkedGache;
            selected['gache_accessory'] = linkedGache;
          }
          selected['linked_accessories'] = await db
              .readAccessoryLinksWithDetails(itemId);
          componentOverrides[key] = selected;
          return;
        }
        if (ruleKey == 'espagnolette' && ruleRows.isNotEmpty) return;
      }

      String kitClampExclude = '';
      if (key.toLowerCase().contains('kit') || key.contains('كيت')) {
        kitClampExclude =
            " AND (LOWER(name) NOT LIKE '%clamp%' AND LOWER(name) NOT LIKE '%clam%' AND LOWER(name) NOT LIKE '%clomp%' AND LOWER(name) NOT LIKE '%clom%' AND name NOT LIKE '%كلامب%' AND name NOT LIKE '%كلام%' AND name NOT LIKE '%كلان%' AND LOWER(type) NOT LIKE '%clamp%' AND LOWER(type) NOT LIKE '%clam%' AND LOWER(type) NOT LIKE '%clomp%' AND LOWER(type) NOT LIKE '%clom%' AND type NOT LIKE '%كلامب%' AND type NOT LIKE '%كلام%' AND type NOT LIKE '%كلان%')";
      } else if (key.toLowerCase().contains('clamp') ||
          key.toLowerCase().contains('clam') ||
          key.contains('كلامب') ||
          key.contains('كلام') ||
          key.contains('كلان')) {
        kitClampExclude =
            " AND (LOWER(name) NOT LIKE '%kit%' AND name NOT LIKE '%كيت%' AND LOWER(type) NOT LIKE '%kit%' AND type NOT LIKE '%كيت%')";
      }

      String? exactTypeOverride;
      if (isTPRSeries) {
        if (key == 'المقبض (Handle)' || key == 'مقبض نافذة (Poignée Fenêtre)') {
          exactTypeOverride = 'Poignée TPR';
        } else if (key == 'إسبانيوليت (Espagnolette)' ||
            key == 'اسبانيولات المنزلق (Espagnolette)') {
          exactTypeOverride = 'Espagnolette TPR';
        }
      }

      // فلتر نوع المادة متطابق تماماً مع ProfileSelectorDialog
      String matFilter = '';
      if (matType == 'PVC') {
        matFilter =
            " AND (LOWER(material_type) = 'pvc' OR LOWER(material_type) = 'both')";
      } else {
        matFilter =
            " AND (LOWER(material_type) = 'aluminium' OR LOWER(material_type) = 'aluminum' OR LOWER(material_type) = 'both' OR material_type IS NULL OR material_type = '')$kitClampExclude";
      }

      // فلتر السلاسل متطابق تماماً مع ProfileSelectorDialog
      String seriesFilter =
          ' AND ('
          'series_id = ? '
          'OR (series_ids IS NOT NULL AND TRIM(series_ids) != \'\' AND \',\' || REPLACE(series_ids, \' \', \'\') || \',\' LIKE ?)'
          ')';

      final String orderBy =
          'CASE WHEN series_id = $seriesId OR (series_ids IS NOT NULL AND TRIM(series_ids) != \'\' AND \',\' || REPLACE(series_ids, \' \', \'\') || \',\' LIKE \'%,$seriesId,%\') THEN 0 ELSE 1 END ASC, id ASC';

      List<Map<String, dynamic>> res = [];

      // 1. إذا كانت السلسلة TPR، جرب البحث المرن عن TPR أولاً لضمان انتقاء إكسسوار TPR الصحيح
      List<String> tprPatterns = [];
      if (isTPRSeries) {
        if (key == 'إسبانيوليت (Espagnolette)' ||
            key == 'اسبانيولات المنزلق (Espagnolette)') {
          tprPatterns = [
            '%tpr%espagnolette%',
            '%espagnolette%tpr%',
            '%tpr%سبانيوليت%',
            '%سبانيوليت%tpr%',
            '%tpr%إسبانيوليت%',
            '%إسبانيوليت%tpr%',
          ];
        } else if (key == 'المقبض (Handle)' ||
            key == 'مقبض نافذة (Poignée Fenêtre)') {
          tprPatterns = [
            '%tpr%poign%',
            '%poign%tpr%',
            '%tpr%مقبض%',
            '%مقبض%tpr%',
            '%tpr%handle%',
            '%handle%tpr%',
          ];
        }
      }

      if (tprPatterns.isNotEmpty) {
        String tprClause = tprPatterns
            .map((_) => 'name LIKE ? OR type LIKE ?')
            .join(' OR ');
        String tprWhereClause = '($tprClause) $seriesFilter $matFilter';
        List<dynamic> tprArgs = [];
        for (var pattern in tprPatterns) {
          tprArgs.addAll([pattern, pattern]);
        }
        tprArgs.addAll([seriesId, '%,$seriesId,%']);
        final rawRows = await d.query(
          'Accessories',
          where: tprWhereClause,
          whereArgs: tprArgs,
          orderBy: orderBy,
        );
        res = rawRows.where(isAccessoryValid).toList();
      }

      // 2. إذا لم يكن TPR أو لم نجد نتيجة بالبحث المرن الخاص بـ TPR، نجري الاستعلام المعتاد
      if (res.isEmpty) {
        String nameClause = exactTypeOverride != null
            ? 'LOWER(type) = ?'
            : searchPatterns
                  .map((_) => 'name LIKE ? OR type LIKE ?')
                  .join(' OR ');

        String whereClause = '($nameClause) $seriesFilter $matFilter';
        List<dynamic> args = [];
        if (exactTypeOverride != null) {
          args.add(exactTypeOverride.toLowerCase());
        } else {
          for (var pattern in searchPatterns) {
            args.addAll([pattern, pattern]);
          }
        }
        args.addAll([seriesId, '%,$seriesId,%']);

        final rawRows = await d.query(
          'Accessories',
          where: whereClause,
          whereArgs: args,
          orderBy: orderBy,
        );
        res = rawRows.where(isAccessoryValid).toList();

        // Fallback: If exact type search for TPR returned empty, retry with loose patterns
        if (res.isEmpty && exactTypeOverride != null) {
          String nameClauseLoose = searchPatterns
              .map((_) => 'name LIKE ? OR type LIKE ?')
              .join(' OR ');
          String fallbackWhereClause =
              '($nameClauseLoose) $seriesFilter $matFilter';
          List<dynamic> fallbackArgs = [];
          for (var pattern in searchPatterns) {
            fallbackArgs.addAll([pattern, pattern]);
          }
          fallbackArgs.addAll([seriesId, '%,$seriesId,%']);

          final rawFallbackRows = await d.query(
            'Accessories',
            where: fallbackWhereClause,
            whereArgs: fallbackArgs,
            orderBy: orderBy,
          );
          res = rawFallbackRows.where(isAccessoryValid).toList();
        }
      }

      if (res.isNotEmpty) {
        // The administrator's default is an explicit catalogue choice. It
        // wins over the old "first row" behaviour and over automatic length
        // guessing, so every drawing uses the value entered in Accessories.
        final defaults = res.where((accessory) {
          final value = accessory['is_default'];
          if (value is num) return value != 0;
          final text = value?.toString().trim().toLowerCase();
          return text == '1' ||
              text == 'true' ||
              text == 'yes' ||
              text == 'oui';
        }).toList();
        Map<String, dynamic> selected = Map<String, dynamic>.from(
          defaults.isNotEmpty ? defaults.first : res.first,
        );
        if (defaults.isEmpty &&
            (key == 'إسبانيوليت (Espagnolette)' ||
                key == 'اسبانيولات المنزلق (Espagnolette)')) {
          // اختَر أطول إسبانيوليت لا تتجاوز الطول المطلوب، لا أول نتيجة في
          // الجدول. هذا هو نفس قانون نافذة «تغيير».
          final heightCm = height / 10.0;
          final targetHeight = hasShutter ? heightCm - 35.0 : heightCm - 20.0;
          final requiredLength = targetHeight >= 180
              ? 180.0
              : targetHeight >= 140
              ? 140.0
              : targetHeight >= 100
              ? 100.0
              : targetHeight >= 60
              ? 60.0
              : 30.0;
          double? getLength(Map<String, dynamic> accessory) {
            final measurement = (accessory['measurement'] ?? '').toString();
            final source = measurement.isNotEmpty
                ? measurement
                : '${accessory['name'] ?? ''} ${accessory['type'] ?? ''}';
            final match = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(source);
            return match == null
                ? null
                : double.tryParse(match.group(1)!.replaceAll(',', '.'));
          }

          final compatible = res.where((accessory) {
            final length = getLength(accessory);
            return length != null && length <= requiredLength;
          }).toList()..sort((a, b) => getLength(b)!.compareTo(getLength(a)!));
          if (compatible.isNotEmpty) selected = compatible.first;
        }
        final m = Map<String, dynamic>.from(selected);
        m['calculated_price'] = await resolveAccessoryPrice(m);
        final linkedGache = await loadRelatedAccessory(
          m['linked_accessory_id'] ?? m['gache_accessory_id'],
        );
        if (linkedGache != null) {
          m['linked_accessory'] = linkedGache;
          m['gache_accessory'] = linkedGache;
        }
        final linkedScrew = await loadRelatedAccessory(m['screw_accessory_id']);
        if (linkedScrew != null) m['screw_accessory'] = linkedScrew;
        final selectedId = (m['id'] as num?)?.toInt();
        if (selectedId != null) {
          m['linked_accessories'] = await db.readAccessoryLinksWithDetails(
            selectedId,
          );
        }
        componentOverrides[key] = m;
      }
    }

    // Exact series rules are authoritative. Other roles can still use the
    // legacy catalogue fallback when this series has no explicit rules.
    await loadAccessory('قاش دوبل (Gache Double Ouvrant)', [
      '%قاش دوبل%',
      '%gache double%',
    ]);
    await loadAccessory('إسبانيوليت (Espagnolette)', [
      '%سبانيوليت%',
      '%espagnolette%',
    ]);
    await loadAccessory('المفاصل (Hinges)', ['%مفاصل%', '%paumelle%']);
    await loadAccessory('الفيرو (Verrou)', [
      '%فيرو%',
      '%verrou%',
      '%verro%',
      '%viro%',
    ]);
    await loadAccessory('المقبض (Handle)', [
      '%مقبض%',
      '%poignée fenêtre%',
      '%poignée fenetre%',
      '%poignee fenetre%',
      '%handle%',
    ]);
    await loadAccessory('مقبض نافذة (Poignée Fenêtre)', [
      '%مقبض%',
      '%poignée fenêtre%',
      '%poignée fenetre%',
      '%poignee fenetre%',
      '%handle%',
    ]);
    await loadAccessory('مقبض أوكتو (Octo)', ['%أوكتو%', '%اوكتو%', '%octo%']);
    await loadAccessory('مقبض نافذة بي في سي (Poignée Fenêtre PVC)', [
      '%مقبض نافذة بي في سي%',
      '%poignée fenêtre pvc%',
      '%poignee fenetre pvc%',
    ]);
    await loadAccessory('كومباس (Compas)', ['%كومباس%', '%compas%']);
    await loadAccessory('عجلات المنزلق (Roulettes)', ['%رول%', '%roulette%']);
    await loadAccessory('اسبانيولات المنزلق (Espagnolette)', [
      '%اسبانيوليت%',
      '%espagnolette%',
    ]);
    await loadAccessory('كاش كوليسون (Gache coulissant)', [
      '%كاش كوليسون%',
      '%كاش كوليس%',
      '%cache coulisson%',
      '%cache coulisse%',
      '%gâche coulisse%',
      '%gache coulisse%',
      '%gâche coulissante%',
      '%gache coulissante%',
    ]);
    await loadAccessory('قاش بورت (Gache Porte)', [
      '%كاش بورت%',
      '%cache porte%',
      '%gâche porte%',
      '%gache porte%',
    ]);
    await loadAccessory('مقبض الباب (Poignée Porte à Clé)', [
      '%مقبض بمفتاح%',
      '%مقبض باب%',
      '%handle key%',
      '%handle porte%',
      '%poignée porte%',
      '%poignee porte%',
      '%poignée de porte%',
      '%poignee de porte%',
    ]);
    await loadAccessory('مقبض الباب عادي (Poignée Porte)', [
      '%مقبض باب عادي%',
      '%مقبض باب%',
      '%poignée porte%',
      '%poignee porte%',
    ]);
    await loadAccessory('مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)', [
      '%ماريشال%1.25%',
      '%ماريشال%125%',
      '%marechal%1.25%',
      '%marechal%125%',
      '%maréchal%1.25%',
      '%maréchal%125%',
    ]);
    if (!componentOverrides.containsKey(
      'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
    )) {
      await loadAccessory(
        'مقبض كبير ماريشال 1.25 متر (Poignée Maréchal 1.25m)',
        ['%ماريشال%', '%marechal%', '%maréchal%'],
      );
    }

    await loadAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', [
      '%ماريشال%2%',
      '%ماريشال%200%',
      '%marechal%2%',
      '%marechal%200%',
      '%maréchal%2%',
      '%maréchal%200%',
    ]);
    if (!componentOverrides.containsKey(
      'مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)',
    )) {
      await loadAccessory('مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)', [
        '%ماريشال%',
        '%marechal%',
        '%maréchal%',
      ]);
    }
    await loadAccessory('قفل رولون (Serrure à Rouleau)', [
      '%رولون%',
      '%rouleau%',
    ]);
    await loadAccessory('مقبض الباب Condamnation (Poignée Condamnation)', [
      '%حمام%',
      '%condamnation%',
    ]);
    await loadAccessory('قفل الباب Condamnation (Serrure Condamnation)', [
      '%قفل حمام%',
      '%serrure condamnation%',
    ]);
    await loadAccessory('الأسطوانة (Canon)', [
      '%canon%',
      '%الأسطوانة%',
      '%الاسطوانة%',
      '%قفل أسطواني%',
      '%barillet%',
    ]);
    await loadAccessory('قفل الباب (Serrure)', [
      '%قفل%',
      '%serrure%',
      '%lock%',
    ]);
    await loadAccessory('كريمون (Cremone)', ['%كريمون%', '%cremone%']);
    await loadAccessory('تراينغل الكريمون (Triangle)', [
      '%tringle%',
      '%tangle%',
      '%triangle%',
      '%تراينغل%',
      '%تريانغل%',
    ]);
    await loadAccessory('بوشون بارك لوز (Bouchon Parclose)', [
      '%بوشون بارك لوز%',
      '%bouchon parclose%',
      '%بوشون باكيت%',
    ]);
    await loadAccessory('بوشون الكانيفو (Bouchon Caniveau)', [
      '%بوشون كانيفو%',
      '%بوشون الكانيفو%',
      '%bouchon caniveau%',
      '%cache caniveau bouchon%',
    ]);
    await loadAccessory('أونتروماتيك (Entrematique)', [
      '%entrematique%',
      '%أونتروماتيك%',
      '%اونتروماتيك%',
      '%انتروماتيك%',
      '%أندراماتيك%',
      '%أندرماتيك%',
      '%اندريمانتيك%',
      '%اندروماتيك%',
      '%andramatique%',
      '%andrematique%',
    ]);
    await loadAccessory('كيت 67000 (Kit 67000)', [
      '%67000%kit%',
      '%67000%KIT%',
      '%kit%67000%',
      '%KIT%67000%',
      '%كيت%67000%',
      '%67000%كيت%',
    ]);
    await loadAccessory('كيت 40000 (Kit 40000)', [
      '%40000%kit%',
      '%40000%KIT%',
      '%kit%40000%',
      '%KIT%40000%',
      '%كيت%40000%',
      '%40000%كيت%',
    ]);
    await loadAccessory('كيت 76000 (Kit 76000)', [
      '%76000%kit%',
      '%76000%KIT%',
      '%kit%76000%',
      '%KIT%76000%',
      '%كيت%76000%',
      '%76000%كيت%',
    ]);
    await loadAccessory('قاش (Gache)', ['%قاش%', '%gâche%', '%gache%']);
    await loadAccessory('الطاسو (Tasso)', ['%طاسو%', '%tasso%']);
    await loadAccessory('الإيكار (Ekar)', [
      '%إيكار%',
      '%ايكار%',
      '%ekar%',
      '%ikar%',
    ]);
    // Default Manivelle
    if (!componentOverrides.containsKey('المانيفال (Manivelle)')) {
      try {
        final res = await d.query(
          'ShutterComponents',
          where: 'name LIKE ? OR component_type LIKE ?',
          whereArgs: ['%مانيفال%', '%مانيفال%'],
        );
        if (res.isNotEmpty) {
          final m = Map<String, dynamic>.from(res.first);
          m['calculated_price'] = (m['price_dzd'] ?? m['price'] ?? 0.0)
              .toDouble();
          componentOverrides['المانيفال (Manivelle)'] = m;
        }
      } catch (error) {
        reportCatalogIssue('ShutterComponents (Ekar)', error);
      }
    }

    // Migration for backward compatibility
    if (componentOverrides.containsKey('جوان بروس (Joint Brosse)')) {
      final oldVal = componentOverrides['جوان بروس (Joint Brosse)'];
      if (!componentOverrides.containsKey(
        'جوان بروس للظلفة (Joint Brosse Sash)',
      )) {
        componentOverrides['جوان بروس للظلفة (Joint Brosse Sash)'] = oldVal;
      }
      if (!componentOverrides.containsKey(
        'جوان بروس للستار (Joint Brosse Shutter)',
      )) {
        componentOverrides['جوان بروس للستار (Joint Brosse Shutter)'] = oldVal;
      }
    }

    // Default Joint Brosse for Sash and Shutter
    Future<void> assignBrosseDefault(String key) async {
      if (!componentOverrides.containsKey(key)) {
        try {
          List<Map<String, Object?>> res = [];

          // 1. البحث أولاً عن جوان بروس المربوط خصيصاً بهذه السلسلة
          res = await d.query(
            'Joints',
            where:
                '(name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?) AND (series_id = ? OR (series_ids IS NOT NULL AND \',\' || series_ids || \',\' LIKE ?))',
            whereArgs: [
              '%brosse%',
              '%brosse%',
              '%بروس%',
              '%بروس%',
              seriesId,
              '%,$seriesId,%',
            ],
            limit: 1,
          );

          // 2. إذا لم يجد، يبحث عن جوان بروس TPR للظلفة خصيصاً كخيار احتياطي
          if (res.isEmpty && key == 'جوان بروس للظلفة (Joint Brosse Sash)') {
            res = await d.query(
              'Joints',
              where: 'name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?',
              whereArgs: [
                '%brosse%tpr%',
                '%brosse%tpr%',
                '%بروس%tpr%',
                '%بروس%tpr%',
              ],
              limit: 1,
            );
          }

          // 3. تراجع أخير: البحث عن جوان بروس العام
          if (res.isEmpty) {
            res = await d.query(
              'Joints',
              where: 'name LIKE ? OR type LIKE ? OR name LIKE ? OR type LIKE ?',
              whereArgs: ['%brosse%', '%brosse%', '%بروس%', '%بروس%'],
              limit: 1,
            );
          }

          if (res.isNotEmpty) {
            final m = Map<String, dynamic>.from(res.first);
            m['calculated_price'] = (m['price_per_meter'] ?? 0.0).toDouble();
            componentOverrides[key] = m;
          }
        } catch (error) {
          reportCatalogIssue('Joints (brush seal)', error);
        }
      }
    }

    await assignBrosseDefault('جوان بروس للظلفة (Joint Brosse Sash)');
    await assignBrosseDefault('جوان بروس للستار (Joint Brosse Shutter)');

    // Dynamic Joint Bourrage matching based on closest real thickness in DB
    try {
      final rawBourrageRows = await d.query(
        'Joints',
        where: 'type LIKE ? OR name LIKE ? OR gasket_type LIKE ?',
        whereArgs: ['%bourrage%', '%bourrage%', '%bourrage%'],
      );
      if (rawBourrageRows.isNotEmpty) {
        final bourrageRows = rawBourrageRows.map((r) {
          final m = Map<String, dynamic>.from(r);
          m['calculated_price'] = (m['price_per_meter'] ?? 0.0).toDouble();
          return m;
        }).toList();

        Map<String, dynamic>? findClosest(double target) {
          if (bourrageRows.isEmpty) return null;
          Map<String, dynamic>? best;
          double minDiff = double.infinity;
          for (final row in bourrageRows) {
            double thick = _readPositiveDouble(row['thickness']);
            if (thick <= 0) {
              final code = (row['code'] ?? '').toString().trim();
              if (code.contains('52034'))
                thick = 2.0;
              else if (code.contains('52035'))
                thick = 4.0;
              else if (code.contains('52036'))
                thick = 6.0;
            }
            if (thick <= 0) continue;
            final diff = (thick - target).abs();
            if (diff < minDiff) {
              minDiff = diff;
              best = row;
            }
          }
          return best ?? bourrageRows.first;
        }

        final bestForDouble = findClosest(2.0);
        if (bestForDouble != null &&
            !componentOverrides.containsKey(
              'جوان البوراج للزجاج المزدوج (Joint Bourrage Double)',
            )) {
          componentOverrides['جوان البوراج للزجاج المزدوج (Joint Bourrage Double)'] =
              bestForDouble;
        }

        final bestForSimple = findClosest(4.0);
        if (bestForSimple != null &&
            !componentOverrides.containsKey(
              'جوان البوراج للزجاج المفرد (Joint Bourrage Simple)',
            )) {
          componentOverrides['جوان البوراج للزجاج المفرد (Joint Bourrage Simple)'] =
              bestForSimple;
        }

        final bestGeneral = findClosest(6.0);
        if (bestGeneral != null &&
            !componentOverrides.containsKey('جوان البوراج (Joint Bourrage)')) {
          componentOverrides['جوان البوراج (Joint Bourrage)'] = bestGeneral;
        }
      }
    } catch (error) {
      reportCatalogIssue('Joints (bourrage)', error);
    }
    await _enrichAccessoryRelations(d);
  }

  Future<void> _enrichAccessoryRelations(dynamic d) async {
    Future<Map<String, dynamic>?> findAccessory(dynamic rawId) async {
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null) return null;
      try {
        final rows = await d.query(
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

    for (final entry in componentOverrides.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final accessory = Map<String, dynamic>.from(value);
      if (accessory['linked_accessory'] == null &&
          accessory['gache_accessory'] == null) {
        final linked = await findAccessory(
          accessory['linked_accessory_id'] ?? accessory['gache_accessory_id'],
        );
        if (linked != null) {
          accessory['linked_accessory'] = linked;
          accessory['gache_accessory'] = linked;
        }
      }
      if (accessory['screw_accessory'] == null) {
        final linked = await findAccessory(accessory['screw_accessory_id']);
        if (linked != null) accessory['screw_accessory'] = linked;
      }
      componentOverrides[entry.key] = accessory;
    }
  }

  void _ensureActiveOpeningSeries() {
    if (activeSeries != null && !isSlidingSeriesForDrawing(activeSeries!)) {
      return;
    }
    final currentSys =
        system ??
        (activeSlidingSeries != null
            ? profileSystemForSeries(availableSystems, activeSlidingSeries!)
            : null);
    if (currentSys != null) {
      for (final candidate in currentSys.series) {
        if (!isSlidingSeriesForDrawing(candidate)) {
          activeSeries = candidate;
          return;
        }
      }
      if (currentSys.series.isNotEmpty &&
          (activeSeries == null || activeSeries!.profileId != currentSys.id)) {
        activeSeries = currentSys.series.first;
        return;
      }
    }
    for (final profileSystem in availableSystems) {
      for (final candidate in profileSystem.series) {
        if (!isSlidingSeriesForDrawing(candidate)) {
          activeSeries = candidate;
          return;
        }
      }
    }
  }

  /// يطبق نظاماً ونموذجاً جاهزاً للرسم السريع بالأبعاد المحددة
  Future<void> applyPresetTemplate({
    required WindowPresetType preset,
    required double newWidth,
    required double newHeight,
  }) async {
    _saveSnapshot();

    // 1. ستار وحده (Volet seul)
    if (preset == WindowPresetType.shutterOnly) {
      prepareShutterOnlyDrawing();
      width = newWidth.clamp(200.0, maximumShutterBarLengthMm).toDouble();
      height = newHeight.clamp(100.0, 10000.0).toDouble();
      isShutterOnly = true;
      hasShutter = true;
      drawNextShapeAsShutterOnly = false;
      isDrawingMode = true;
      drawingMode = 'shutter_only';
      drawnLeft = null;
      drawnTop = null;
      lastLayoutSize = null;
      await updateShutterDefaultsIfNeeded();
      _notifyModelListeners();
      return;
    }

    // 2. أنظمة النوافذ والأبواب الأخرى
    clearAll();
    isShutterOnly = false;
    drawNextShapeAsShutterOnly = false;
    isDrawingMode = true;
    drawingMode = 'new_frame';
    drawnLeft = null;
    drawnTop = null;
    lastLayoutSize = null;

    final isSliding =
        preset == WindowPresetType.slidingNoShutter ||
        preset == WindowPresetType.slidingWithShutter;
    final withShutter =
        preset == WindowPresetType.windowWithShutter ||
        preset == WindowPresetType.slidingWithShutter;
    final isDoor =
        preset == WindowPresetType.singleDoor ||
        preset == WindowPresetType.doubleDoor;

    if (isSliding) {
      _ensureActiveSlidingSeries();
    } else {
      _ensureActiveOpeningSeries();
    }

    hasShutter = withShutter;
    isCaissonTunnel = false;

    if (isDoor) {
      hasBottomFrame = false;
      showBottomWall = false;
    } else {
      hasBottomFrame = true;
      showBottomWall = true;
    }

    final limitedPreset = _limitFrameSize(newWidth, newHeight);
    width = limitedPreset.width;
    height = limitedPreset.height;

    if (withShutter) {
      await updateShutterDefaultsIfNeeded();
    }

    final double topOffset = (withShutter && !hasArchOrSlant)
        ? shutterBoxHeight
        : 0.0;
    final double bottomOffset = hasBottomFrame ? profileThickness : 0.0;

    final initialRect = Rect.fromLTRB(
      profileThickness,
      topOffset + profileThickness,
      width - profileThickness,
      height - bottomOffset,
    );

    final zone = WindowZone(
      id: UniqueKey().toString(),
      glass: defaultGlass.clone(),
      boundary: initialRect,
      sashThickness: _calculateSashThickness(isDoor),
      sashColor: FrameColor.white,
      selectedDbColor: _selectedDbColor,
    );
    zones.add(zone);

    switch (preset) {
      case WindowPresetType.windowNoShutter:
      case WindowPresetType.windowWithShutter:
        final ZoneContent content = width >= 900.0
            ? ZoneContent.doubleSash
            : ZoneContent.singleSash;
        paintZoneContent(zone.id, content);
        zone.useClassicHandle = isPVC;
        break;

      case WindowPresetType.slidingNoShutter:
      case WindowPresetType.slidingWithShutter:
        paintZoneContent(
          zone.id,
          ZoneContent.slidingSash,
          slidingSashesCount: 2,
        );
        break;

      case WindowPresetType.singleDoor:
        paintZoneContent(zone.id, ZoneContent.singleSash);
        zone.isSash105 = true;
        if (activeSeries != null) {
          AluminumSection? doorSashSec;
          for (final sec in activeSeries!.sections) {
            final lwr = '${sec.code} ${sec.name}'.toLowerCase();
            if (sec.type.toLowerCase() == 'sash' &&
                (lwr.contains('105') ||
                    lwr.contains('port') ||
                    lwr.contains('باب'))) {
              doorSashSec = sec;
              break;
            }
          }
          if (doorSashSec != null) {
            zone.sashOverride = doorSashSec.toMap();
            sashOverride = doorSashSec.toMap();
          }
        }
        zone.sashThickness = _calculateSashThickness(
          true,
          override: zone.sashOverride,
        );
        zone.lockType = LockType.clef;
        _hideBottomCoverWhenBottomFrameIsMissing();
        updateBottomZoneBoundaries();
        await _loadDoorKeyLockAccessories();
        break;

      case WindowPresetType.doubleDoor:
        paintZoneContent(zone.id, ZoneContent.doubleSash);
        zone.isSash105 = true;
        if (activeSeries != null) {
          AluminumSection? doorSashSec;
          for (final sec in activeSeries!.sections) {
            final lwr = '${sec.code} ${sec.name}'.toLowerCase();
            if (sec.type.toLowerCase() == 'sash' &&
                (lwr.contains('105') ||
                    lwr.contains('port') ||
                    lwr.contains('باب'))) {
              doorSashSec = sec;
              break;
            }
          }
          if (doorSashSec != null) {
            zone.sashOverride = doorSashSec.toMap();
            sashOverride = doorSashSec.toMap();
          }
        }
        zone.sashThickness = _calculateSashThickness(
          true,
          override: zone.sashOverride,
        );
        zone.lockType = LockType.clef;
        _hideBottomCoverWhenBottomFrameIsMissing();
        updateBottomZoneBoundaries();
        await _loadDoorKeyLockAccessories();
        break;

      case WindowPresetType.topOpeningSmallWindow:
        paintZoneContent(zone.id, ZoneContent.singleSash);
        zone.openDirection = OpenDirection.bottom;
        zone.useClassicHandle = isPVC;
        break;

      case WindowPresetType.shutterOnly:
        break;
    }

    selection = SelectionInfo(type: SelectionType.zone, zoneId: zone.id);
    updatePrimaryMullionAxis();
    updateProfileThickness();
    _notifyModelListeners();
  }
}
