part of '../model.dart';

/// Zones, cells, mullions, sashes and hardware of [WindowModel].
extension WindowModelZones on WindowModel {
  bool get isDoor => zones.any(
    (z) => z.lockType == LockType.clef || z.lockType == LockType.condamnation,
  );

  bool get hasOpeningSashZones => zones.any(
    (z) =>
        z.content == ZoneContent.singleSash ||
        z.content == ZoneContent.doubleSash,
  );

  bool _isSashZone(WindowZone zone) =>
      zone.content == ZoneContent.singleSash ||
      zone.content == ZoneContent.doubleSash ||
      zone.content == ZoneContent.slidingSash;

  /// Whether a long press selected every sash of the drawing.
  bool get allSashesSelected {
    final anchor = allSashesAnchorZoneId;
    final zone = selectedZone;
    return anchor != null &&
        zone != null &&
        zone.id == anchor &&
        _isSashZone(zone);
  }

  /// The sashes a sash setting applies to: the selected sash, or every sash
  /// of the same kind (opening or sliding) after a long press.
  List<WindowZone> get selectedSashZones {
    final zone = selectedZone;
    if (zone == null) return const [];
    if (!allSashesSelected) return [zone];
    final sliding = zone.content == ZoneContent.slidingSash;
    return zones
        .where(
          (z) =>
              _isSashZone(z) &&
              (z.content == ZoneContent.slidingSash) == sliding,
        )
        .toList();
  }

  void applySashOverride(
    Map<String, dynamic> sash, {
    required bool sliding,
    bool manualSelection = false,
    WindowZone? targetZone,
  }) {
    _saveSnapshot();
    final mutable = Map<String, dynamic>.from(sash);
    if (manualSelection) {
      mutable['manual_selection'] = true;
    }

    final is105 = _isSash105Profile(mutable);
    final widthVal = (mutable['visible_width'] as num?)?.toDouble() ?? 0.0;
    // Only the drawing passes a target: the consumption table changes the
    // whole drawing whatever is selected.
    final target = targetZone;

    // A sash selected alone takes its own profile; after a long press every
    // sash does, and without a sash selection the whole drawing.
    bool ofKind(WindowZone z) => sliding
        ? z.content == ZoneContent.slidingSash
        : z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash;
    final targets = target == null || !_isSashZone(target)
        ? zones.where(ofKind).toList()
        : (allSashesSelected && target.id == selectedZone?.id
                  ? selectedSashZones
                  : [target])
              .where(ofKind)
              .toList();
    for (final z in targets) {
      if (sliding) {
        z.slidingSashOverride = mutable;
        if (widthVal > 0) z.sashThickness = widthVal;
      } else {
        z.sashOverride = mutable;
        z.isSash105 = is105;
        z.sashThickness = widthVal > 0
            ? widthVal
            : _calculateSashThickness(is105, override: mutable);
      }
    }
    // The drawing's own sash follows once every sash of this kind has it.
    final allOfKind = zones.where(ofKind);
    if (allOfKind.every(
      (z) => identical(sliding ? z.slidingSashOverride : z.sashOverride, mutable),
    )) {
      if (sliding) {
        slidingSashOverride = mutable;
      } else {
        sashOverride = mutable;
        selectedSashCode = mutable['code']?.toString() ?? selectedSashCode;
      }
    }

    updateAllSashThicknesses();
    _notifyModelListeners();
  }

  double get divisionThickness {
    if (coupleFrames) {
      return profileThickness * 2;
    }
    return mullionThickness;
  }

  double get mullionThickness {
    final s = getSectionByType('mullion');
    if (s != null) {
      if (s.visibleWidth > 0) return s.visibleWidth;
      if (s.thickness > 0) return s.thickness;
    }
    return profileThickness;
  }

  String _mullionKey(bool isHorizontal, double position) =>
      '${isHorizontal ? 'H' : 'V'}_${position.toStringAsFixed(1)}';

  bool _divisionKeyBelongsToSide(String key, {required bool isRightSash}) {
    final isRightKey = key.startsWith('right_');
    return isRightSash ? isRightKey : !isRightKey;
  }

  void _keepPrimaryInnerDivisionsContinuous(
    WindowZone zone, {
    required bool isRightSash,
  }) {
    final primaryAxis = isRightSash
        ? zone.rightPrimaryDivisionAxis
        : zone.primaryDivisionAxis;
    if (primaryAxis == 'h') {
      zone.disabledHorizontalDivisions =
          Map<String, bool>.from(zone.disabledHorizontalDivisions)..removeWhere(
            (key, value) =>
                _divisionKeyBelongsToSide(key, isRightSash: isRightSash),
          );
    } else if (primaryAxis == 'v') {
      zone.disabledVerticalDivisions =
          Map<String, bool>.from(zone.disabledVerticalDivisions)..removeWhere(
            (key, value) =>
                _divisionKeyBelongsToSide(key, isRightSash: isRightSash),
          );
    }
  }

  /// Returns the selected profile for a mullion. A null result intentionally
  /// means that the standard mullion profile should be used.
  Map<String, dynamic>? effectiveMullionSectionAt(
    bool isHorizontal,
    double position,
  ) {
    final key = _mullionKey(isHorizontal, position);
    final override = mullionSectionOverrides[key];
    if (override != null) return Map<String, dynamic>.from(override);

    final profileType = mullionProfiles[key] ?? MullionProfileType.standard;
    if (profileType == MullionProfileType.standard) {
      return null;
    }

    if (profileType == MullionProfileType.flat && activeFrameOverride != null) {
      return Map<String, dynamic>.from(activeFrameOverride!);
    }

    return _frameForMullion(profileType)?.toMap();
  }

  /// For a grooved frame, false means the cavity faces left/top and true
  /// means it faces right/bottom.
  bool isGroovedMullionCavityOnPositiveSide(
    bool isHorizontal,
    double position,
  ) =>
      groovedMullionCavityOnPositiveSide[_mullionKey(isHorizontal, position)] ??
      false;

  void recordMullionCreation(bool isHorizontal, double position) {
    for (final entry in mullionCreationOrder.entries) {
      if (entry.key.startsWith(isHorizontal ? 'H_' : 'V_')) {
        final posStr = entry.key.substring(2);
        final p = double.tryParse(posStr);
        if (p != null && (p - position).abs() < 5.0) {
          return;
        }
      }
    }
    final key = _mullionKey(isHorizontal, position);
    mullionCreationOrder[key] = ++mullionStepCounter;
  }

  /// Determines the creation order of a mullion. A lower number means it was created earlier.
  int getMullionCreationOrder(bool isHorizontal, double position) {
    final key = _mullionKey(isHorizontal, position);
    if (mullionCreationOrder.containsKey(key)) {
      return mullionCreationOrder[key]!;
    }
    for (final entry in mullionCreationOrder.entries) {
      if (entry.key.startsWith(isHorizontal ? 'H_' : 'V_')) {
        final posStr = entry.key.substring(2);
        final p = double.tryParse(posStr);
        if (p != null && (p - position).abs() < 6.0) {
          return entry.value;
        }
      }
    }
    return 999999;
  }

  /// Uses the widest selected mullion while finding adjoining zones. This
  /// keeps a custom frame-140 or double-frame selection from being skipped.
  double get maximumMullionThickness {
    var maximum = mullionThickness;
    for (final section in mullionSectionOverrides.values) {
      final width = _sectionVisibleWidth(section);
      final isDoubleFrame =
          _isEnabledFlag(section['is_double_frame']) ||
          _isEnabledFlag(section['isDoubleFrame']) ||
          _isEnabledFlag(section['double_frame']) ||
          _isEnabledFlag(section['doubleFrame']);
      final effectiveWidth = isDoubleFrame ? width * 2.0 : width;
      if (effectiveWidth > maximum) maximum = effectiveWidth;
    }
    for (final profileType in mullionProfiles.values) {
      if (profileType == MullionProfileType.standard) {
        continue;
      }
      final width = _sectionVisibleWidth(
        profileType == MullionProfileType.flat ? activeFrameOverride : null,
      );
      final frameWidth = _frameForMullion(profileType)?.visibleWidth ?? 0.0;
      final effectiveOverrideWidth = profileType == MullionProfileType.flat
          ? width * 2.0
          : width;
      if (effectiveOverrideWidth > maximum) maximum = effectiveOverrideWidth;
      final effectiveFrameWidth = profileType == MullionProfileType.flat
          ? frameWidth * 2.0
          : frameWidth;
      if (effectiveFrameWidth > maximum) maximum = effectiveFrameWidth;
    }
    return maximum;
  }

  bool _componentWasManuallySelected(Map<String, dynamic>? component) {
    if (component == null) return false;

    bool enabled(Object? value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    return enabled(component['manual_selection']) ||
        enabled(component['is_manual_selection']) ||
        enabled(component['user_selected']);
  }

  /// Actual height available to an opening sash in the drawing.
  ///
  /// A fixed-light partition above or below the sash must reduce this value;
  /// using the outer-frame height would select an espagnolette that is too
  /// long. During early catalogue loading (before zones exist), fall back to
  /// the frame opening below the shutter box.
  double get openingSashHeightMm {
    final openingHeights = zones
        .where(
          (zone) =>
              zone.content == ZoneContent.singleSash ||
              zone.content == ZoneContent.doubleSash,
        )
        .map((zone) => zone.boundary.height)
        .where((zoneHeight) => zoneHeight > 0)
        .toList(growable: false);
    if (openingHeights.isNotEmpty) return openingHeights.reduce(math.max);
    return math.max(
      0.0,
      height.toDouble() - (hasShutter ? shutterBoxHeight : 0.0),
    );
  }

  /// Height passed unchanged to the catalogue min/max rules. The configured
  /// rule ranges decide which espagnolette fits this sash; no hidden
  /// deduction is applied here.
  double get effectiveEspagnoletteHeightMm => openingSashHeightMm;

  int get gachePerEspagnolette {
    int len = cremoneLengthCm;
    if (len < 100) return 2;
    if (len <= 140) return 3;
    return 4;
  }

  Map<String, dynamic>? get selectedDbColor => _selectedDbColor;

  set selectedDbColor(Map<String, dynamic>? colorData) {
    _saveSnapshot();
    _selectedDbColor = colorData == null
        ? null
        : Map<String, dynamic>.from(colorData);
    _preferredDbColorForCatalogLoad = _selectedDbColor == null
        ? null
        : Map<String, dynamic>.from(_selectedDbColor!);
    for (var z in zones) {
      z.selectedDbColor = _selectedDbColor == null
          ? null
          : Map<String, dynamic>.from(_selectedDbColor!);
    }
    unawaited(refreshSectionPricesForSelectedColor());
    unawaited(refreshBardageColorPrices());
    _notifyModelListeners();
  }

  /// Adds the current colour price to an in-memory catalogue section before
  /// it enters the synchronous BOM calculation.
  Map<String, dynamic> sectionMapWithSelectedColorPrice(
    AluminumSection section,
  ) {
    final result = Map<String, dynamic>.from(section.toMap());
    double? price = sectionPricesForSelectedColor[section.id];
    if (price == null) {
      for (final rawOverride in componentOverrides.values) {
        if (rawOverride is! Map ||
            rawOverride['id']?.toString() != section.id.toString()) {
          continue;
        }
        final rawPrice = rawOverride['calculated_price'];
        price = rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '');
        if (price != null) break;
      }
    }
    if (price != null) result['calculated_price'] = price;
    return result;
  }

  Future<void> refreshSectionPricesForSelectedColor({
    bool notify = true,
  }) async {
    // The BOM is built synchronously from this cache.  Limiting it to
    // parcloses made ordinary linear-metre profiles start at 0 until the
    // user pressed the manual refresh button, which happens to reload their
    // prices later in the workflow.
    final sections = <int, AluminumSection>{};
    for (final series in <AluminumSeries?>[activeSeries, activeSlidingSeries]) {
      if (series == null) continue;
      for (final section in series.sections) {
        sections[section.id] = section;
      }
    }
    if (sections.isEmpty) return;

    final rawColorId = selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse(rawColorId?.toString() ?? '');
    try {
      for (final section in sections.values) {
        sectionPricesForSelectedColor[section.id] = await db.getSectionPrice(
          section.id,
          colorId,
        );
      }
      for (final entry in componentOverrides.entries.toList()) {
        final rawOverride = entry.value;
        if (rawOverride is! Map) continue;
        final rawId = rawOverride['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        final price = id == null ? null : sectionPricesForSelectedColor[id];
        if (price == null) continue;
        final updated = Map<String, dynamic>.from(rawOverride);
        updated['calculated_price'] = price;
        componentOverrides[entry.key] = updated;
      }
      // The selected frame, sash and cover profiles carry their own
      // `calculated_price`, which the BOM reads before the colour cache. They
      // must follow the new colour too, otherwise they keep the old tariff.
      Map<String, dynamic>? repriced(Map<String, dynamic>? selection) {
        if (selection == null) return null;
        final rawId = selection['id'];
        final id = rawId is num
            ? rawId.toInt()
            : int.tryParse(rawId?.toString() ?? '');
        final price = id == null ? null : sectionPricesForSelectedColor[id];
        if (price == null) return selection;
        return Map<String, dynamic>.from(selection)
          ..['calculated_price'] = price;
      }

      frameOverride = repriced(frameOverride);
      sashOverride = repriced(sashOverride);
      slidingFrameOverride = repriced(slidingFrameOverride);
      slidingSashOverride = repriced(slidingSashOverride);
      sideCoverOverride = repriced(sideCoverOverride);
      for (final zone in zones) {
        zone.sashOverride = repriced(zone.sashOverride);
        zone.slidingSashOverride = repriced(zone.slidingSashOverride);
      }
      for (final entry in mullionSectionOverrides.entries.toList()) {
        mullionSectionOverrides[entry.key] = repriced(entry.value)!;
      }
      if (notify) _notifyModelListeners();
    } catch (error) {
      debugPrint('Unable to refresh parclose prices: $error');
    }
  }

  /// An explicit profile-colour choice resets both dependent colours.
  /// Loading a saved drawing must not call this: its independent choices stay.
  void selectProfileColorWithDefaults(Map<String, dynamic> color) {
    selectedDbColor = color;
    selectedShutterColor = Map<String, dynamic>.from(color);
    selectedAccessoryColor = Map<String, dynamic>.from(color);
    _notifyModelListeners();
  }

  Map<String, dynamic>? get selectedAccessoryColor => _selectedAccessoryColor;

  set selectedAccessoryColor(Map<String, dynamic>? colorData) {
    _saveSnapshot();
    _selectedAccessoryColor = colorData;
    _notifyModelListeners();
  }

  double _calculateSashThickness(bool is105, {Map<String, dynamic>? override}) {
    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final selectedOverride =
        override ?? (useSliding ? slidingSashOverride : sashOverride);
    final selectedSeries = useSliding ? activeSlidingSeries : activeSeries;

    // إذا كان هناك ضلفة مخصصة مختارة، نستخدم العرض الظاهر لها
    if (selectedOverride != null) {
      double t = (selectedOverride['visible_width'] as num?)?.toDouble() ?? 0.0;
      if (t > 0) return t;
      double th = (selectedOverride['thickness'] as num?)?.toDouble() ?? 0.0;
      if (th > 0) return th;
    }

    if (selectedSeries == null || selectedSeries.sections.isEmpty) {
      return is105 ? 70.0 : 50.0;
    }

    // محاولة إيجاد الضلفة الافتراضية
    String targetCode = is105 ? '105' : '104';
    try {
      final sashSection = selectedSeries.sections.firstWhere(
        (s) => s.type.toLowerCase() == 'sash' && s.code.contains(targetCode),
      );
      if (sashSection.visibleWidth > 0) return sashSection.visibleWidth;
      if (sashSection.thickness > 0) return sashSection.thickness;
    } catch (_) {
      // إذا لم يجد ضلفة بالكود 104/105، يبحث عن أي ضلفة أخرى في السلسلة
      try {
        final anySash = selectedSeries.sections.firstWhere(
          (s) => s.isSash || s.type.toLowerCase() == 'sash',
        );
        if (anySash.visibleWidth > 0) return anySash.visibleWidth;
      } catch (_) {}
    }
    return is105 ? 70.0 : 50.0;
  }

  /// The opening overlap belongs to the series geometry. Some catalogues keep
  /// it on the normal sash while other sash variants leave their field at
  /// zero, so never let a zero-valued first row erase the configured value.
  /// No global default is applied: an unconfigured series intentionally
  /// returns zero until its overlap is entered in the catalogue.
  double get openingSashOverlap {
    double readOverlap(dynamic value) {
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    final useSliding = systemMode == 'sliding' || usesSlidingPrimaryProfiles;
    final selectedOverride = useSliding ? slidingSashOverride : sashOverride;

    // The sash explicitly selected in the drawing is the source of truth.
    final overrideOverlap = readOverlap(selectedOverride?['sash_overlap']);
    if (overrideOverlap > 0) return overrideOverlap;

    final series = useSliding
        ? (activeSlidingSeries ?? activeSeries)
        : activeSeries;
    if (series != null) {
      final overrideId = selectedOverride?['id']?.toString();
      final overrideCode = selectedOverride?['code']?.toString().trim();
      for (final sash in series.sections) {
        final matchesSelected =
            (overrideId != null && sash.id.toString() == overrideId) ||
            (overrideCode != null &&
                overrideCode.isNotEmpty &&
                sash.code.trim() == overrideCode) ||
            (selectedSashCode.isNotEmpty && sash.code == selectedSashCode);
        if (matchesSelected && sash.sashOverlap > 0) {
          return sash.sashOverlap;
        }
      }

      final sashes =
          series.sections.where((section) {
            final type = section.type.toLowerCase();
            final name = section.name.toLowerCase();
            return section.isSash ||
                type.contains('sash') ||
                type.contains('ouvrant') ||
                name.contains('sash') ||
                name.contains('ouvrant');
          }).toList()..sort((a, b) {
            final aWidth = a.visibleWidth > 0 ? a.visibleWidth : a.thickness;
            final bWidth = b.visibleWidth > 0 ? b.visibleWidth : b.thickness;
            return aWidth.compareTo(bWidth);
          });
      for (final sash in sashes) {
        if (sash.sashOverlap > 0) return sash.sashOverlap;
      }
    }
    return 0.0;
  }

  WindowZone? get selectedZone {
    if (selection.type == SelectionType.zone && selection.zoneId != null) {
      try {
        return zones.firstWhere((z) => z.id == selection.zoneId);
      } catch (_) {}
    }
    return null;
  }

  DrawingCatalogSelection _captureCatalogSelection() {
    Map<String, dynamic>? copy(Map<String, dynamic>? value) =>
        value == null ? null : Map<String, dynamic>.from(value);
    return DrawingCatalogSelection(
      activeSeries: activeSeries,
      activeSlidingSeries: activeSlidingSeries,
      loadedSeriesId: loadedSeriesId,
      loadedSeriesName: loadedSeriesName,
      loadedSlidingSeriesId: loadedSlidingSeriesId,
      loadedSlidingSeriesName: loadedSlidingSeriesName,
      sashOverride: copy(sashOverride),
      slidingSashOverride: copy(slidingSashOverride),
      seriesDesignConfig: copy(seriesDesignConfig),
      seriesTableConfig: copy(seriesTableConfig),
      slidingSeriesTableConfig: copy(slidingSeriesTableConfig),
      defaultGlass: defaultGlass,
    );
  }

  void _restoreCatalogSelection(DrawingCatalogSelection? selection) {
    if (selection == null) return;
    Map<String, dynamic>? copy(Map<String, dynamic>? value) =>
        value == null ? null : Map<String, dynamic>.from(value);
    activeSeries = selection.activeSeries;
    activeSlidingSeries = selection.activeSlidingSeries;
    loadedSeriesId = selection.loadedSeriesId;
    loadedSeriesName = selection.loadedSeriesName;
    loadedSlidingSeriesId = selection.loadedSlidingSeriesId;
    loadedSlidingSeriesName = selection.loadedSlidingSeriesName;
    sashOverride = copy(selection.sashOverride);
    slidingSashOverride = copy(selection.slidingSashOverride);
    seriesDesignConfig = copy(selection.seriesDesignConfig);
    seriesTableConfig = copy(selection.seriesTableConfig);
    slidingSeriesTableConfig = copy(selection.slidingSeriesTableConfig);
    defaultGlass = selection.defaultGlass;
  }

  void validateAndSanitizeAllZonesHandles() {
    for (var zone in zones) {
      if (zone.content != ZoneContent.singleSash &&
          zone.content != ZoneContent.doubleSash &&
          zone.content != ZoneContent.slidingSash) {
        // Reset handle settings for non-sash content types (fixed, slant, etc.)
        zone.lockType = LockType.none;
        zone.useOctoHandle = false;
        zone.usePvcHandleOnAlu = false;
        zone.useClassicHandle = false;
        zone.slidingFaceToFace = false;
        zone.slidingCentralHandle = false;
        zone.slidingSecondCentralHandle = false;
        continue;
      }

      if (zone.content == ZoneContent.slidingSash) {
        zone.lockType = LockType.none;
        zone.useOctoHandle = false;
        zone.usePvcHandleOnAlu = false;
        if (!isSlidingFaceToFaceLayout(
          trackCount: zone.slidingTrackCount,
          sashCount: zone.slidingSashesCount,
        )) {
          zone.slidingFaceToFace = false;
          zone.slidingCentralHandle = false;
          zone.slidingSecondCentralHandle = false;
        } else if (!zone.slidingCentralHandle) {
          zone.slidingSecondCentralHandle = false;
        }
        if (isPVC) {
          zone.useClassicHandle = false;
        }
        continue;
      }

      // Swing Sashes (singleSash or doubleSash)
      // A sash can be made thick from the profile selector, including inside
      // a divided cell.  Do not rely only on the legacy `isSash105` flag here:
      // it may still be false while the selected profile is already a door
      // sash.  Otherwise a notify immediately removes the key/bathroom/
      // Marechal choice that the user has just selected.
      final isDoorSash = _zoneUsesSash105(zone);
      if (isPVC) {
        zone.useClassicHandle = false;

        if (isDoorSash) {
          // PVC door, whether it has one sash or two: a double door still
          // supports the key, bathroom and Maréchal handle choices.  The old
          // double-sash branch reset every lock to `none` during notify(), so
          // the user could press the button but never see the selected handle.
          // A shutter does not invalidate a key or bathroom handle on a
          // thick door sash. Keep the explicit user selection intact.

          if (zone.lockType == LockType.rouleau ||
              zone.lockType == LockType.rouleau2000) {
            final doorHeight = zone.boundary.height;
            if (hasBottomFrame == true ||
                hasShutter == true ||
                doorHeight < 1250.0) {
              zone.lockType = LockType.none;
            } else if (doorHeight <= 2000.0 &&
                zone.lockType == LockType.rouleau2000) {
              zone.lockType = LockType.rouleau;
            }
          }

          if (zone.lockType != LockType.none &&
              zone.lockType != LockType.clef &&
              zone.lockType != LockType.condamnation &&
              zone.lockType != LockType.rouleau &&
              zone.lockType != LockType.rouleau2000) {
            zone.lockType = LockType.none;
          }
          zone.useOctoHandle = false;
        } else {
          // PVC window: a double sash has the normal window handle only;
          // a single sash may also use the Octo handle.
          zone.usePvcHandleOnAlu = false;
          if (zone.lockType != LockType.none) {
            zone.lockType = LockType.none;
          }
          if (zone.content == ZoneContent.doubleSash) {
            zone.useOctoHandle = false;
          }
        }
      } else {
        // Aluminium swing sashes
        zone.useClassicHandle = false;

        if (isDoorSash) {
          // Thick sash (Door)
          if (zone.content == ZoneContent.doubleSash) {
            // Double sash door: Cremone (none), Window handle, Key,
            // Bathroom and Maréchal.
            zone.useOctoHandle = false;
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          } else {
            // Single sash door: Cremone (none), Window handle, Key,
            // Bathroom, Octo and Maréchal.
            if (zone.lockType == LockType.point) {
              zone.lockType = LockType.none;
            }
          }

          // A shutter does not invalidate a key or bathroom handle on a
          // thick aluminium door sash. Keep the explicit user selection.

          // Maréchal height and constraint checks
          if (zone.lockType == LockType.rouleau ||
              zone.lockType == LockType.rouleau2000) {
            if (hasBottomFrame == true || hasShutter == true) {
              zone.lockType = LockType.none;
            } else {
              final double doorHeight = zone.boundary.height;
              if (doorHeight < 1250.0) {
                zone.lockType = LockType.none;
              } else if (doorHeight <= 2000.0 &&
                  zone.lockType == LockType.rouleau2000) {
                // Downgrade 2m handle to 1.25m handle if door height is <= 2m
                zone.lockType = LockType.rouleau;
              }
            }
          }

          if (zone.lockType != LockType.none &&
              zone.lockType != LockType.clef &&
              zone.lockType != LockType.condamnation &&
              zone.lockType != LockType.rouleau &&
              zone.lockType != LockType.rouleau2000) {
            zone.lockType = LockType.none;
          }
        } else {
          // Thin sash (Window)
          if (zone.content == ZoneContent.doubleSash) {
            // Double sash thin: Cremone or the selected window handle.  The
            // latter is still drawn on only one leaf unless the explicit
            // two-handle option is enabled.
            zone.lockType = LockType.none;
            zone.useOctoHandle = false;
          } else {
            // Single sash thin: Cremone (none), Octo (useOctoHandle), Point Lock (point)
            zone.usePvcHandleOnAlu = false;
            if (zone.lockType != LockType.none &&
                zone.lockType != LockType.point) {
              zone.lockType = LockType.none;
            }
          }
        }
      }
    }
  }

  void _rescaleZonesInternal(
    double oldW,
    double oldH,
    double newW,
    double newH,
  ) {
    // Calculate topOffset for old height and new height correctly by temporarily setting height
    final double originalHeight = height;

    height = oldH;
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    height = newH;
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    height = originalHeight;

    double bottomOffset = hasBottomFrame ? profileThickness : 0.0;
    const double pHeight = 0.0;

    if (zones.isEmpty) {
      zones.add(
        WindowZone(
          id: UniqueKey().toString(),
          glass: defaultGlass.clone(),
          boundary: Rect.fromLTRB(
            profileThickness,
            newTopOffset + profileThickness,
            newW - profileThickness,
            newH - bottomOffset - pHeight,
          ),
          sashThickness: _calculateSashThickness(false),
          useClassicHandle: isPVC,
        ),
      );
      return;
    }

    final double oldInnerLeft = profileThickness;
    final double oldInnerRight = oldW - profileThickness;
    final double newInnerLeft = profileThickness;
    final double newInnerRight = newW - profileThickness;

    final double oldInnerTop = oldTopOffset + profileThickness;
    final double oldInnerBottom = oldH - bottomOffset - pHeight;
    final double newInnerTop = newTopOffset + profileThickness;
    final double newInnerBottom = newH - bottomOffset - pHeight;

    List<double> normalizeGridCoordinates(
      Iterable<double> rawCoordinates,
      double minValue,
      double maxValue,
    ) {
      const tolerance = 2.0;
      final values = <double>[minValue, maxValue];
      values.addAll(
        rawCoordinates.map((value) => value.clamp(minValue, maxValue)),
      );
      values.sort();

      final normalized = <double>[];
      for (final value in values) {
        if (normalized.isEmpty) {
          normalized.add(value);
          continue;
        }

        final last = normalized.last;
        if ((value - last).abs() <= tolerance) {
          if ((last - minValue).abs() <= tolerance ||
              (value - minValue).abs() <= tolerance) {
            normalized[normalized.length - 1] = minValue;
          } else if ((last - maxValue).abs() <= tolerance ||
              (value - maxValue).abs() <= tolerance) {
            normalized[normalized.length - 1] = maxValue;
          } else {
            normalized[normalized.length - 1] = (last + value) / 2.0;
          }
        } else {
          normalized.add(value);
        }
      }
      return normalized;
    }

    // Collect and sort unique X coordinates
    final List<double> xCoords = normalizeGridCoordinates(
      zones.expand((z) => [z.boundary.left, z.boundary.right]),
      oldInnerLeft,
      oldInnerRight,
    );

    // Collect and sort unique Y coordinates
    final List<double> yCoords = normalizeGridCoordinates(
      zones.expand((z) => [z.boundary.top, z.boundary.bottom]),
      oldInnerTop,
      oldInnerBottom,
    );

    if (xCoords.length < 2 || yCoords.length < 2) {
      // Fallback: standard linear scaling factor
      final scaleX = newW / oldW;
      final scaleY = newH / oldH;
      for (var z in zones) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left * scaleX,
          z.boundary.top * scaleY,
          z.boundary.right * scaleX,
          z.boundary.bottom * scaleY,
        );
      }
      return;
    }

    // Classify X spans
    List<bool> isZoneSpanX = [];
    double totalZoneSpanOldW = 0.0;
    double totalMullionSpanOldW = 0.0;
    for (int i = 0; i < xCoords.length - 1; i++) {
      final double left = xCoords[i];
      final double right = xCoords[i + 1];
      final double spanW = right - left;
      final double mid = (left + right) / 2.0;
      bool isZone = false;
      for (var z in zones) {
        if (z.boundary.left <= mid && mid <= z.boundary.right) {
          isZone = true;
          break;
        }
      }
      isZoneSpanX.add(isZone);
      if (isZone) {
        totalZoneSpanOldW += spanW;
      } else {
        totalMullionSpanOldW += spanW;
      }
    }

    // Solve for X scaling factor
    double newInnerW = newInnerRight - newInnerLeft;
    double totalZoneSpanNewW = newInnerW - totalMullionSpanOldW;
    double scaleX = 1.0;
    if (totalZoneSpanOldW > 0 && totalZoneSpanNewW > 0) {
      scaleX = totalZoneSpanNewW / totalZoneSpanOldW;
    } else {
      scaleX = newInnerW / (oldInnerRight - oldInnerLeft);
    }

    // Map X coordinates
    Map<double, double> mapX = {};
    mapX[xCoords[0]] = newInnerLeft;
    double currentNewX = newInnerLeft;
    for (int i = 0; i < xCoords.length - 1; i++) {
      final double spanW = xCoords[i + 1] - xCoords[i];
      final double newSpanW = isZoneSpanX[i] ? (spanW * scaleX) : spanW;
      currentNewX += newSpanW;
      mapX[xCoords[i + 1]] = currentNewX;
    }

    double getMappedX(double oldX) {
      double closestKey = xCoords[0];
      double minDiff = (oldX - closestKey).abs();
      for (var k in xCoords) {
        final diff = (oldX - k).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestKey = k;
        }
      }
      if (minDiff < 1.0) {
        return mapX[closestKey]!;
      }
      int idx = 0;
      while (idx < xCoords.length - 1 && xCoords[idx + 1] < oldX) {
        idx++;
      }
      if (idx >= xCoords.length - 1) return mapX[xCoords.last]!;
      final double x0 = xCoords[idx];
      final double x1 = xCoords[idx + 1];
      final double y0 = mapX[x0]!;
      final double y1 = mapX[x1]!;
      final double t = (oldX - x0) / (x1 - x0);
      return y0 + t * (y1 - y0);
    }

    // Classify Y spans
    List<bool> isZoneSpanY = [];
    double totalZoneSpanOldH = 0.0;
    double totalMullionSpanOldH = 0.0;
    for (int i = 0; i < yCoords.length - 1; i++) {
      final double top = yCoords[i];
      final double bottom = yCoords[i + 1];
      final double spanH = bottom - top;
      final double mid = (top + bottom) / 2.0;
      bool isZone = false;
      for (var z in zones) {
        if (z.boundary.top <= mid && mid <= z.boundary.bottom) {
          isZone = true;
          break;
        }
      }
      isZoneSpanY.add(isZone);
      if (isZone) {
        totalZoneSpanOldH += spanH;
      } else {
        totalMullionSpanOldH += spanH;
      }
    }

    // Solve for Y scaling factor
    double newInnerH = newInnerBottom - newInnerTop;
    double totalZoneSpanNewH = newInnerH - totalMullionSpanOldH;
    double scaleY = 1.0;
    if (totalZoneSpanOldH > 0 && totalZoneSpanNewH > 0) {
      scaleY = totalZoneSpanNewH / totalZoneSpanOldH;
    } else {
      scaleY = newInnerH / (oldInnerBottom - oldInnerTop);
    }

    // Map Y coordinates
    Map<double, double> mapY = {};
    mapY[yCoords[0]] = newInnerTop;
    double currentNewY = newInnerTop;
    for (int i = 0; i < yCoords.length - 1; i++) {
      final double spanH = yCoords[i + 1] - yCoords[i];
      final double newSpanH = isZoneSpanY[i] ? (spanH * scaleY) : spanH;
      currentNewY += newSpanH;
      mapY[yCoords[i + 1]] = currentNewY;
    }

    double getMappedY(double oldY) {
      double closestKey = yCoords[0];
      double minDiff = (oldY - closestKey).abs();
      for (var k in yCoords) {
        final diff = (oldY - k).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestKey = k;
        }
      }
      if (minDiff < 1.0) {
        return mapY[closestKey]!;
      }
      int idx = 0;
      while (idx < yCoords.length - 1 && yCoords[idx + 1] < oldY) {
        idx++;
      }
      if (idx >= yCoords.length - 1) return mapY[yCoords.last]!;
      final double y0 = yCoords[idx];
      final double y1 = yCoords[idx + 1];
      final double z0 = mapY[y0]!;
      final double z1 = mapY[y1]!;
      final double t = (oldY - y0) / (y1 - y0);
      return z0 + t * (z1 - z0);
    }

    // Apply mapping to all zone boundaries
    for (var z in zones) {
      double left = getMappedX(z.boundary.left);
      double top = getMappedY(z.boundary.top);
      double right = getMappedX(z.boundary.right);
      double bottom = getMappedY(z.boundary.bottom);
      z.boundary = Rect.fromLTRB(left, top, right, bottom);
    }
  }

  void rescaleZones(double oldW, double oldH, double newW, double newH) {
    if (oldW <= 0 || oldH <= 0 || newW <= 0 || newH <= 0) return;
    final limited = _limitFrameSize(newW, newH);
    newW = limited.width;
    newH = limited.height;
    _saveSnapshot();
    _rescaleZonesInternal(oldW, oldH, newW, newH);
    width = newW;
    height = newH;
    _resizeSideCoverSegments(oldW, oldH, newW, newH);
    synchronizeShutterAfterFrameResize(oldW, oldH);
    updateShutterDefaultsIfNeeded();
    _notifyModelListeners();
  }

  void selectAt(Offset pos, {bool isLongPress = false}) {
    // Use actual frame profile thickness so we don't eat into zone area
    double borderSlop = profileThickness.clamp(20.0, 60.0);
    double topOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    double topY = topOffset;
    if (pos.dx >= 0 && pos.dx <= width) {
      // Outer edge of the (possibly slanted or arched) head at this x.
      topY = headEdgeY(pos.dx, 0, topOffset: topOffset);
    }

    // Check if clicked in empty space outside the window bounds
    if (pos.dx < 0 || pos.dx > width || pos.dy < topY || pos.dy > height) {
      selection = SelectionInfo.none;
      showZoneMenu = false;
      activeSubZone = null;
      _notifySelectionChanged();
      return;
    }

    // Now if it is close to the boundary, it's on the frame
    if (pos.dx < borderSlop ||
        pos.dx > width - borderSlop ||
        pos.dy < topY + borderSlop ||
        pos.dy > height - borderSlop) {
      final frames = getFrameRects();
      if (frames.isNotEmpty) {
        // The frame under the press (or the nearest one), never simply the
        // first: a long press on the right frame deleted the left one.
        var index = 0;
        var nearest = double.infinity;
        for (var i = 0; i < frames.length; i++) {
          final r = frames[i];
          final gap = Offset(
            math.max(0.0, math.max(r.left - pos.dx, pos.dx - r.right)),
            math.max(0.0, math.max(r.top - pos.dy, pos.dy - r.bottom)),
          ).distance;
          if (gap < nearest) {
            nearest = gap;
            index = i;
          }
        }
        selectFrameByIndex(index);
      } else {
        selection = SelectionInfo(type: SelectionType.frame);
        showZoneMenu = false;
        activeSubZone = null;
        _notifySelectionChanged();
      }
      return;
    }

    double hitSlop = 40.0;
    final mullionT = mullionThickness;

    List<double> findContinuousMullionSpan({
      required bool isHorizontal,
      required double position,
      required double initialStart,
      required double initialEnd,
    }) {
      double fullStart = initialStart;
      double fullEnd = initialEnd;
      bool expanded = true;
      while (expanded) {
        expanded = false;
        for (int a = 0; a < zones.length; a++) {
          for (int b = a + 1; b < zones.length; b++) {
            final za = zones[a].boundary;
            final zb = zones[b].boundary;
            if (isHorizontal) {
              double? ym;
              if ((za.bottom - zb.top).abs() <= mullionT + 4) {
                ym = (za.bottom + zb.top) / 2;
              } else if ((zb.bottom - za.top).abs() <= mullionT + 4) {
                ym = (zb.bottom + za.top) / 2;
              }
              if (ym != null && (ym - position).abs() <= 4.0) {
                final segL = math.max(za.left, zb.left);
                final segR = math.min(za.right, zb.right);
                if (segL < segR - 2.0) {
                  if (segL <= fullEnd + mullionT + 6.0 &&
                      segR >= fullStart - mullionT - 6.0) {
                    if (segL < fullStart) {
                      fullStart = segL;
                      expanded = true;
                    }
                    if (segR > fullEnd) {
                      fullEnd = segR;
                      expanded = true;
                    }
                  }
                }
              }
            } else {
              double? xm;
              if ((za.right - zb.left).abs() <= mullionT + 4) {
                xm = (za.right + zb.left) / 2;
              } else if ((zb.right - za.left).abs() <= mullionT + 4) {
                xm = (zb.right + za.left) / 2;
              }
              if (xm != null && (xm - position).abs() <= 4.0) {
                final segT = math.max(za.top, zb.top);
                final segB = math.min(za.bottom, zb.bottom);
                if (segT < segB - 2.0) {
                  if (segT <= fullEnd + mullionT + 6.0 &&
                      segB >= fullStart - mullionT - 6.0) {
                    if (segT < fullStart) {
                      fullStart = segT;
                      expanded = true;
                    }
                    if (segB > fullEnd) {
                      fullEnd = segB;
                      expanded = true;
                    }
                  }
                }
              }
            }
          }
        }
      }
      return [fullStart, fullEnd];
    }

    // A completed divider remains selectable even after drawing mode is
    // switched off. Drawing mode controls creation only, never selection.
    if (zones.length > 1) {
      for (int i = 0; i < zones.length; i++) {
        for (int j = i + 1; j < zones.length; j++) {
          final z1 = zones[i].boundary;
          final z2 = zones[j].boundary;
          if ((z1.bottom - z2.top).abs() <= mullionT + 4 ||
              (z2.bottom - z1.top).abs() <= mullionT + 4) {
            double yCenter = (z1.bottom + z2.top) / 2;
            if ((z2.bottom - z1.top).abs() <= mullionT + 4) {
              yCenter = (z2.bottom + z1.top) / 2;
            }
            double overlapLeft = math.max(z1.left, z2.left);
            double overlapRight = math.min(z1.right, z2.right);
            if (overlapLeft < overlapRight &&
                pos.dx >= overlapLeft - 10 &&
                pos.dx <= overlapRight + 10 &&
                (pos.dy - yCenter).abs() < hitSlop) {
              final span = findContinuousMullionSpan(
                isHorizontal: true,
                position: yCenter,
                initialStart: overlapLeft,
                initialEnd: overlapRight,
              );
              selection = SelectionInfo(
                type: SelectionType.mullion,
                isHorizontalMullion: true,
                mullionPosition: yCenter,
                mullionStart: span[0],
                mullionEnd: span[1],
              );
              showZoneMenu = false;
              activeSubZone = null;
              _notifySelectionChanged();
              return;
            }
          }
          if ((z1.right - z2.left).abs() <= mullionT + 4 ||
              (z2.right - z1.left).abs() <= mullionT + 4) {
            double xCenter = (z1.right + z2.left) / 2;
            if ((z2.right - z1.left).abs() <= mullionT + 4) {
              xCenter = (z2.right + z1.left) / 2;
            }
            double overlapTop = math.max(z1.top, z2.top);
            double overlapBottom = math.min(z1.bottom, z2.bottom);
            if (overlapTop < overlapBottom &&
                pos.dy >= overlapTop - 10 &&
                pos.dy <= overlapBottom + 10 &&
                (pos.dx - xCenter).abs() < hitSlop) {
              final span = findContinuousMullionSpan(
                isHorizontal: false,
                position: xCenter,
                initialStart: overlapTop,
                initialEnd: overlapBottom,
              );
              selection = SelectionInfo(
                type: SelectionType.mullion,
                isHorizontalMullion: false,
                mullionPosition: xCenter,
                mullionStart: span[0],
                mullionEnd: span[1],
              );
              showZoneMenu = false;
              activeSubZone = null;
              _notifySelectionChanged();
              return;
            }
          }
        }
      }
    }
    for (var z in zones) {
      if (z.boundary.contains(pos)) {
        final sashT =
            (z.content == ZoneContent.singleSash ||
                z.content == ZoneContent.doubleSash)
            ? (z.sashThickness ?? _calculateSashThickness(z.isSash105))
            : 0.0;
        final isDouble = z.content == ZoneContent.doubleSash;

        SelectionInfo? checkSashDivisions(Rect sashRect, bool isRight) {
          final glassR = sashT > 0
              ? getSafeGlassRect(sashRect, sashT)
              : sashRect;
          final hPositions = isRight
              ? z.rightInnerHPositions
              : z.innerHPositions;
          final vPositions = isRight
              ? z.rightInnerVPositions
              : z.innerVPositions;
          final innerH = isRight ? z.rightInnerH : z.innerH;
          final innerV = isRight ? z.rightInnerV : z.innerV;

          List<double> finalHPos = List.from(hPositions);
          if (finalHPos.isEmpty && innerH > 0) {
            double stepY = 1.0 / (innerH + 1);
            for (int i = 1; i <= innerH; i++) {
              finalHPos.add(stepY * i);
            }
          }
          List<double> finalVPos = List.from(vPositions);
          if (finalVPos.isEmpty && innerV > 0) {
            double stepX = 1.0 / (innerV + 1);
            for (int i = 1; i <= innerV; i++) {
              finalVPos.add(stepX * i);
            }
          }

          final double hitThreshold = 30.0;
          String getVKey(int r, int v) => isRight ? 'right_${r}_$v' : '${r}_$v';
          String getHKey(int c, int h) => isRight ? 'right_${c}_$h' : '${c}_$h';

          for (int i = 0; i < finalHPos.length; i++) {
            double y = glassR.top + glassR.height * finalHPos[i];
            if ((pos.dy - y).abs() >= hitThreshold) continue;
            for (int c = 0; c < finalVPos.length + 1; c++) {
              if (z.disabledHorizontalDivisions[getHKey(c, i)] == true) {
                continue;
              }
              final leftRatio = c == 0 ? 0.0 : finalVPos[c - 1];
              final rightRatio = c == finalVPos.length ? 1.0 : finalVPos[c];
              final left = glassR.left + glassR.width * leftRatio;
              final right = glassR.left + glassR.width * rightRatio;
              if (pos.dx < left - 10 || pos.dx > right + 10) continue;
              return SelectionInfo(
                type: SelectionType.innerDivision,
                zoneId: z.id,
                isHorizontalInnerDivision: true,
                isRightSashInnerDivision: isRight,
                innerDivisionIndex: i,
              );
            }
          }

          for (int i = 0; i < finalVPos.length; i++) {
            double x = glassR.left + glassR.width * finalVPos[i];
            if ((pos.dx - x).abs() >= hitThreshold) continue;
            for (int r = 0; r < finalHPos.length + 1; r++) {
              if (z.disabledVerticalDivisions[getVKey(r, i)] == true) {
                continue;
              }
              final topRatio = r == 0 ? 0.0 : finalHPos[r - 1];
              final bottomRatio = r == finalHPos.length ? 1.0 : finalHPos[r];
              final top = glassR.top + glassR.height * topRatio;
              final bottom = glassR.top + glassR.height * bottomRatio;
              if (pos.dy < top - 10 || pos.dy > bottom + 10) continue;
              return SelectionInfo(
                type: SelectionType.innerDivision,
                zoneId: z.id,
                isHorizontalInnerDivision: false,
                isRightSashInnerDivision: isRight,
                innerDivisionIndex: i,
              );
            }
          }
          return null;
        }

        final doubleSashSplitX =
            z.boundary.left + z.boundary.width * z.doubleSashRatio;
        final isRightClick = isDouble && (pos.dx > doubleSashSplitX);

        SelectionInfo? hit;
        if (isDouble) {
          final sep = 4.0;
          final leftR = Rect.fromLTRB(
            z.boundary.left,
            z.boundary.top,
            doubleSashSplitX - sep / 2,
            z.boundary.bottom,
          );
          final rightR = Rect.fromLTRB(
            doubleSashSplitX + sep / 2,
            z.boundary.top,
            z.boundary.right,
            z.boundary.bottom,
          );
          hit = isRightClick
              ? checkSashDivisions(rightR, true)
              : checkSashDivisions(leftR, false);
        } else {
          hit = checkSashDivisions(z.boundary, false);
        }

        if (hit != null) {
          selection = hit;
          showZoneMenu = false;
          activeSubZone = null;
          _notifySelectionChanged();
          return;
        }
        selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
        // A tap selects this sash alone; a long press selects every sash.
        allSashesAnchorZoneId = isLongPress && _isSashZone(z) ? z.id : null;
        selectedSlidingLeaf = null;
        bool isSingle = z.content == ZoneContent.singleSash;
        bool isSliding = z.content == ZoneContent.slidingSash;
        if (isSliding) {
          showZoneMenu = isLongPress ? false : true;
          final count = z.slidingSashesCount;

          double getSlidingSectionWidth(
            String typeName,
            String fallbackName,
            double defaultVal,
          ) {
            final series = activeSlidingSeries;
            if (series == null) return defaultVal;
            final String tName = typeName.toLowerCase();
            String? altType;
            if (tName == 'traverse') {
              altType = 'sash_traverse';
            } else if (tName == 'chicane' ||
                tName == 'central' ||
                tName == 'centrale') {
              altType = 'sash_central';
            } else if (tName == 'lateral') {
              altType = 'sash_lateral';
            }
            for (var sec in series.sections) {
              final secType = sec.type.toLowerCase();
              if (secType == tName || (altType != null && secType == altType)) {
                if (sec.visibleWidth > 0) return sec.visibleWidth;
                if (sec.thickness > 0) return sec.thickness;
              }
            }
            for (var sec in series.sections) {
              final name = sec.name.toLowerCase();
              if (name.contains(tName) || name.contains(fallbackName)) {
                if (sec.visibleWidth > 0) return sec.visibleWidth;
                if (sec.thickness > 0) return sec.thickness;
              }
            }
            return defaultVal;
          }

          final double chicaneT = getSlidingSectionWidth(
            'chicane',
            'centrale',
            45.0,
          );
          final double sashWidth =
              (z.boundary.width + (count - 1) * chicaneT) / count;

          int selectedSashIndex = -1;
          List<int> tracks;
          if (count == 2) {
            tracks = (z.openDirection == OpenDirection.left) ? [1, 0] : [0, 1];
          } else if (count == 3) {
            tracks = [0, 1, 0];
          } else if (count == 4) {
            tracks = [0, 1, 1, 0];
          } else {
            tracks = List.generate(count, (i) => i % 2);
          }

          bool clickedInsideGlass = false;
          final sashT = z.sashThickness ?? _calculateSashThickness(z.isSash105);

          for (int tg = 1; tg >= 0; tg--) {
            for (int i = 0; i < count; i++) {
              if (tracks[i] == tg) {
                double left = z.boundary.left + i * (sashWidth - chicaneT);
                Rect sashRect = Rect.fromLTRB(
                  left,
                  z.boundary.top,
                  left + sashWidth,
                  z.boundary.bottom,
                );
                if (sashRect.contains(pos)) {
                  selectedSashIndex = i;
                  Rect glassR = sashRect.deflate(sashT);
                  if (glassR.contains(pos)) {
                    clickedInsideGlass = true;
                  }
                  break;
                }
              }
            }
            if (selectedSashIndex != -1) break;
          }

          if (selectedSashIndex == -1) {
            double tX = (pos.dx - z.boundary.left) / z.boundary.width;
            selectedSashIndex = (tX * count).floor().clamp(0, count - 1);
          }

          if (clickedInsideGlass) {
            activeSubZone = 'main_cell_0_$selectedSashIndex';
          } else {
            activeSubZone = null;
          }
          // A tap selects this leaf alone, wherever it lands on the leaf; a
          // long press selects every sash.
          selectedSlidingLeaf = isLongPress ? null : selectedSashIndex;
          selection = SelectionInfo(type: SelectionType.zone, zoneId: z.id);
          _notifySelectionChanged();
          return;
        }

        if (isDouble || isSingle) {
          showZoneMenu = isLongPress ? false : true;
          if (isLongPress && isDouble) {
            activeSubZone = 'all';
          } else {
            double splitX =
                z.boundary.left + z.boundary.width * z.doubleSashRatio;
            bool isRight = isDouble && (pos.dx > splitX);
            Rect sashR = z.boundary;
            if (isDouble) {
              final sep = 4.0;
              sashR = isRight
                  ? Rect.fromLTRB(
                      splitX + sep / 2,
                      z.boundary.top,
                      z.boundary.right,
                      z.boundary.bottom,
                    )
                  : Rect.fromLTRB(
                      z.boundary.left,
                      z.boundary.top,
                      splitX - sep / 2,
                      z.boundary.bottom,
                    );
            }
            final sashT =
                z.sashThickness ?? _calculateSashThickness(z.isSash105);
            final glassR = sashR.deflate(sashT);
            if (glassR.contains(pos)) {
              int currentInnerH = isRight ? z.rightInnerH : z.innerH;
              int currentInnerV = isRight ? z.rightInnerV : z.innerV;

              List<double> vPositions = List.from(
                isRight ? z.rightInnerVPositions : z.innerVPositions,
              )..sort();
              if (vPositions.isEmpty && currentInnerV > 0) {
                double stepX = 1.0 / (currentInnerV + 1);
                for (int i = 1; i <= currentInnerV; i++) {
                  vPositions.add(stepX * i);
                }
              }
              List<double> hPositions = List.from(
                isRight ? z.rightInnerHPositions : z.innerHPositions,
              )..sort();
              if (hPositions.isEmpty && currentInnerH > 0) {
                double stepY = 1.0 / (currentInnerH + 1);
                for (int i = 1; i <= currentInnerH; i++) {
                  hPositions.add(stepY * i);
                }
              }

              double xRatio = ((pos.dx - glassR.left) / glassR.width).clamp(
                0.0,
                1.0,
              );
              double yRatio = ((pos.dy - glassR.top) / glassR.height).clamp(
                0.0,
                1.0,
              );

              int col = 0;
              for (int i = 0; i < vPositions.length; i++) {
                if (xRatio > vPositions[i]) col = i + 1;
              }
              int row = 0;
              for (int i = 0; i < hPositions.length; i++) {
                if (yRatio > hPositions[i]) row = i + 1;
              }

              final mergedMap = z.getMergedCellMap(
                isRightSash: isRight,
                isDouble: isDouble,
              );
              final targetKey = mergedMap["${row}_$col"] ?? "${row}_$col";
              final parts = targetKey.split('_');
              int finalRow = int.parse(parts[0]);
              int finalCol = int.parse(parts[1]);

              String sidePrefix = isDouble
                  ? (isRight ? 'right' : 'left')
                  : 'main';
              activeSubZone = '${sidePrefix}_cell_${finalRow}_$finalCol';
            } else {
              activeSubZone = isDouble ? (isRight ? 'right' : 'left') : 'main';
            }
          }
        } else {
          showZoneMenu = isLongPress ? false : true;
          activeSubZone = 'all';
        }
        _notifySelectionChanged();
        return;
      }
    }
    selection = SelectionInfo.none;
    activeSubZone = null;
    showZoneMenu = false;
    _notifySelectionChanged();
  }

  void clearSelection() {
    selection = SelectionInfo.none;
    frameShapeMode = false;
    selectedHinge = null;
    activeSubZone = null;
    showZoneMenu = false;
    _notifySelectionChanged();
  }

  int? checkMullionDimensionTap(Offset pos) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return null;
    }
    bool isH = selection.isHorizontalMullion!;
    double mPos = selection.mullionPosition!;
    double hitW = 400.0;
    double hitH = 200.0;
    if (isH) {
      if (Rect.fromCenter(
        center: Offset(width / 2, mPos / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 1;
      }
      if (Rect.fromCenter(
        center: Offset(width / 2, mPos + (height - mPos) / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 2;
      }
    } else {
      if (Rect.fromCenter(
        center: Offset(mPos / 2, height / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 1;
      }
      if (Rect.fromCenter(
        center: Offset(mPos + (width - mPos) / 2, height / 2),
        width: hitW,
        height: hitH,
      ).contains(pos)) {
        return 2;
      }
    }
    return null;
  }

  void resizeMullionDimension(int section, double newVal) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    bool isH = selection.isHorizontalMullion!;
    double oldPos = selection.mullionPosition!;
    final t = profileThickness;
    final isDouble = isDoubleFrameMullionAt(isH, oldPos);
    final profileW = frameProfileWidthAt(isH, oldPos);
    final effectiveThickness = isDouble ? profileW * 2.0 : mullionThickness;
    final sep = effectiveThickness / 2;

    double newPos = (section == 1)
        ? newVal + t + sep
        : (isH ? height : width) - newVal - t - sep;

    // محاذاة كل التقسيمات التي تقع على نفس المستوى (كالعلوية والسفلية)
    const alignThreshold = 100.0;
    final matchingDividers = <double>{oldPos};
    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final za = zones[i].boundary;
        final zb = zones[j].boundary;
        if (isH) {
          if ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0 ||
              (zb.bottom - za.top).abs() <= maximumMullionThickness + 8.0) {
            final yMid =
                ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0)
                ? (za.bottom + zb.top) / 2
                : (zb.bottom + za.top) / 2;
            if ((yMid - oldPos).abs() <= alignThreshold) {
              matchingDividers.add(yMid);
            }
          }
        } else {
          if ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0 ||
              (zb.right - za.left).abs() <= maximumMullionThickness + 8.0) {
            final xMid =
                ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0)
                ? (za.right + zb.left) / 2
                : (zb.right + za.left) / 2;
            if ((xMid - oldPos).abs() <= alignThreshold) {
              matchingDividers.add(xMid);
            }
          }
        }
      }
    }

    if (isH) {
      double minAllowedY = t * 2;
      double maxAllowedY = height - t * 2;
      for (var z in zones) {
        for (final divY in matchingDividers) {
          if ((z.boundary.bottom - divY).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.top + minimumZoneSpanMm(z, isWidth: false) > minAllowedY) {
              minAllowedY = z.boundary.top + minimumZoneSpanMm(z, isWidth: false);
            }
          }
          if ((z.boundary.top - divY).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false) < maxAllowedY) {
              maxAllowedY = z.boundary.bottom - minimumZoneSpanMm(z, isWidth: false);
            }
          }
        }
      }
      // No legal position: the neighbouring zones are already at their minimum.
      if (minAllowedY + sep > maxAllowedY - sep) return;
      if (newPos - sep < minAllowedY) newPos = minAllowedY + sep;
      if (newPos + sep > maxAllowedY) newPos = maxAllowedY - sep;

      for (int i = 0; i < zones.length; i++) {
        var z = zones[i];
        for (final divY in matchingDividers) {
          if (z.boundary.bottom <= divY + 4.0 &&
              (divY - z.boundary.bottom).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                newPos - sep,
              ),
            );
            z = zones[i];
          } else if (z.boundary.top >= divY - 4.0 &&
              (z.boundary.top - divY).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                newPos + sep,
                z.boundary.right,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          }
        }
      }
    } else {
      double minAllowedX = t * 2;
      double maxAllowedX = width - t * 2;
      for (var z in zones) {
        for (final divX in matchingDividers) {
          if ((z.boundary.right - divX).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.left + minimumZoneSpanMm(z, isWidth: true) > minAllowedX) {
              minAllowedX = z.boundary.left + minimumZoneSpanMm(z, isWidth: true);
            }
          }
          if ((z.boundary.left - divX).abs() <= effectiveThickness + 8.0) {
            if (z.boundary.right - minimumZoneSpanMm(z, isWidth: true) < maxAllowedX) {
              maxAllowedX = z.boundary.right - minimumZoneSpanMm(z, isWidth: true);
            }
          }
        }
      }
      // No legal position: the neighbouring zones are already at their minimum.
      if (minAllowedX + sep > maxAllowedX - sep) return;
      if (newPos - sep < minAllowedX) newPos = minAllowedX + sep;
      if (newPos + sep > maxAllowedX) newPos = maxAllowedX - sep;

      for (int i = 0; i < zones.length; i++) {
        var z = zones[i];
        for (final divX in matchingDividers) {
          if (z.boundary.right <= divX + 4.0 &&
              (divX - z.boundary.right).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                newPos - sep,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          } else if (z.boundary.left >= divX - 4.0 &&
              (z.boundary.left - divX).abs() <= effectiveThickness + 8.0) {
            zones[i] = z.copyWith(
              boundary: Rect.fromLTRB(
                newPos + sep,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom,
              ),
            );
            z = zones[i];
          }
        }
      }
    }

    for (final oldDiv in matchingDividers) {
      _moveMullionMetadata(_mullionKey(isH, oldDiv), _mullionKey(isH, newPos));
    }

    selection = SelectionInfo(
      type: SelectionType.mullion,
      isHorizontalMullion: isH,
      mullionPosition: newPos,
      mullionStart: selection.mullionStart,
      mullionEnd: selection.mullionEnd,
    );
    _snapNearbyParallelMullions(isHorizontal: isH, targetPos: newPos);
    _notifyModelListeners();
  }

  void paintZoneOrCellSpec(
    String zoneId, {
    required GlassSpecification spec,
    String? cellId,
  }) {
    _saveSnapshot();
    // The last glazing choice in the current order becomes the default for
    // the next drawing added to that order, including a cell-level choice.
    defaultGlass = spec;
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);

      if (cellId != null && cellId.contains('cell_')) {
        // Store per-cell spec override
        final updatedCellGlass = Map<String, GlassSpecification>.from(
          zone.cellGlassSpec,
        );
        updatedCellGlass[cellId] = spec.clone();
        zone.cellGlassSpec = updatedCellGlass;

        if (spec.structure == GlassStructure.closed) {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = true;
          zone.cellIsPanel = updatedCells;

          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          updatedSashes[cellId] = false;
          zone.cellIsSash = updatedSashes;
        } else {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = false;
          zone.cellIsPanel = updatedCells;

          // إذا كانت الخلية زجاجاً في زون من نوع ضلفة → نعود للمحتوى الأصلي
          final updatedCellGlass2 = Map<String, GlassSpecification>.from(
            zone.cellGlassSpec,
          );
          updatedCellGlass2[cellId] = spec.clone();
          zone.cellGlassSpec = updatedCellGlass2;
        }
      } else {
        // لا توجد خلية محددة → تطبيق على الزون كلها
        zone.glass = spec.clone();
        zone.cellGlassSpec = {};
        defaultGlass = zone.glass;

        if (spec.structure == GlassStructure.closed) {
          // تحويل الزون إلى زجاج ثابت (fixedGlass) حتى يظهر البانو
          final previousContent = zone.content;
          zone.content = ZoneContent.fixedGlass;
          if (previousContent != ZoneContent.fixedGlass) {
            _restoreBottomFrameForContent(zone);
          }
          // وضع علامة على جميع الخلايا الداخلية كبانو
          final updatedPanels = Map<String, bool>.from(zone.cellIsPanel);
          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          for (int r = 0; r <= zone.innerH; r++) {
            for (int c = 0; c <= zone.innerV; c++) {
              final key = 'main_cell_${r}_$c';
              updatedPanels[key] = true;
              updatedSashes[key] = false;
            }
          }
          zone.cellIsPanel = updatedPanels;
          zone.cellIsSash = updatedSashes;
        }
      }
      _notifyModelListeners();
      unawaited(_refitPaintedGlass(zone, cellId));
    } catch (_) {}
  }

  void paintAllZonesSpec(GlassSpecification spec) {
    _saveSnapshot();
    for (var z in zones) {
      z.glass = spec.clone();
      z.cellGlassSpec = {}; // clear all per-cell overrides
      if (spec.structure == GlassStructure.closed) {
        final previousContent = z.content;
        z.content = ZoneContent.fixedGlass;
        if (previousContent != ZoneContent.fixedGlass) {
          _restoreBottomFrameForContent(z);
        }
        final updatedPanels = Map<String, bool>.from(z.cellIsPanel);
        final updatedSashes = Map<String, bool>.from(z.cellIsSash);
        for (int r = 0; r <= z.innerH; r++) {
          for (int c = 0; c <= z.innerV; c++) {
            updatedPanels['main_cell_${r}_$c'] = true;
            updatedSashes['main_cell_${r}_$c'] = false;
          }
        }
        if (z.content == ZoneContent.doubleSash) {
          for (int r = 0; r <= z.rightInnerH; r++) {
            for (int c = 0; c <= z.rightInnerV; c++) {
              updatedPanels['right_cell_${r}_$c'] = true;
              updatedSashes['right_cell_${r}_$c'] = false;
            }
          }
        }
        z.cellIsPanel = updatedPanels;
        z.cellIsSash = updatedSashes;
      }
    }
    defaultGlass = spec;
    updateGlassGasket();
    _notifyModelListeners();
  }

  void paintZoneOrCell(
    String zoneId, {
    required GlassFinish finish,
    required GlassStructure structure,
    String? cellId,
    ClosedGlassColor? colorP,
    GlassColor? color,
  }) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      final resolvedColor =
          color ??
          (structure == GlassStructure.closed || finish == GlassFinish.stopSol
              ? zone.glass.colorOuter
              : GlassColor.transparent);

      zone.glass = zone.glass.copyWith(
        structure: structure,
        finishOuter: finish,
        finishInner: finish,
        colorP: colorP ?? zone.glass.colorP,
        colorOuter: resolvedColor,
        colorInner: resolvedColor,
      );
      defaultGlass = zone.glass;

      if (cellId != null && cellId.contains('cell_')) {
        if (structure == GlassStructure.closed) {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = true;
          zone.cellIsPanel = updatedCells;

          final updatedSashes = Map<String, bool>.from(zone.cellIsSash);
          updatedSashes[cellId] = false;
          zone.cellIsSash = updatedSashes;
        } else {
          final updatedCells = Map<String, bool>.from(zone.cellIsPanel);
          updatedCells[cellId] = false;
          zone.cellIsPanel = updatedCells;
        }
      } else {
        if (structure == GlassStructure.closed) {
          final previousContent = zone.content;
          zone.content = ZoneContent.fixedGlass;
          if (previousContent != ZoneContent.fixedGlass) {
            _restoreBottomFrameForContent(zone);
          }
        }
      }
      _notifyModelListeners();
    } catch (_) {}
  }

  void paintZoneContent(
    String zoneId,
    ZoneContent content, {
    int? slidingSashesCount,
    bool? cutSlidingGlassRebate,
  }) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      final previousContent = zone.content;
      zone.content = content;
      // Slanted divisions exist only in fixed zones (no shaped sashes).
      if (content != ZoneContent.fixedGlass && content != ZoneContent.empty) {
        zone.slantedDividers = [];
      }
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.clear();
      zone.cellIsSash.clear();
      zone.cellIsDoubleSash.clear();
      zone.cellGlassSpec = {};

      // When converting a fixed frame to sashes, clear old fixed-glass décor
      if (previousContent == ZoneContent.fixedGlass &&
          (content == ZoneContent.singleSash ||
              content == ZoneContent.doubleSash ||
              content == ZoneContent.slidingSash)) {
        if (zone.glass.decorH > 0 ||
            zone.glass.decorV > 0 ||
            zone.glass.hasRosettes) {
          zone.glass = zone.glass.copyWith(
            decorH: 0,
            decorV: 0,
            decorHPositions: const [],
            decorVPositions: const [],
            hasRosettes: false,
          );
        }
      }

      // Fixed, empty and sliding content all sit on a real lower frame.
      // Discard the old local hide flag so the frame corners and bottom cover
      // return together when the drawing leaves an open-bottom state.
      if ((content == ZoneContent.fixedGlass ||
              content == ZoneContent.empty ||
              content == ZoneContent.slidingSash) &&
          previousContent != content) {
        _restoreBottomFrameForContent(zone);
      }

      if (slidingSashesCount != null) {
        zone.slidingSashesCount = slidingSashesCount;
      }
      if (content == ZoneContent.slidingSash) {
        zone.cutSlidingGlassRebate =
            cutSlidingGlassRebate ?? zone.cutSlidingGlassRebate;
        _activateSlidingProfilesForDrawing();
      }

      bool is105 = _determineIsSash105FromSashOverride();
      zone.isSash105 = is105;
      zone.sashThickness = _calculateSashThickness(is105);
      if (content == ZoneContent.doubleSash ||
          content == ZoneContent.singleSash ||
          content == ZoneContent.slidingSash) {
        zone.openDirection = OpenDirection.right;
      } else {
        zone.openDirection = null;
        zone.doubleSashHasTwoHandles = false;
      }
      _notifyModelListeners();
    } catch (_) {}
  }

  void toggleSelectedCellSash() {
    if (selectedZone == null || selectedZone!.id.contains('_nested_')) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlySash = zone.cellIsSash[activeSubZone!] ?? false;
      Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
      updatedSashes[activeSubZone!] = !isCurrentlySash;
      zone.cellIsSash = updatedSashes;

      // If it becomes a sash, it cannot be a panel or double sash
      if (updatedSashes[activeSubZone!] == true) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[activeSubZone!] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[activeSubZone!] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
    }
    _notifyModelListeners();
  }

  void toggleSelectedCellDoubleSash() {
    if (selectedZone == null || selectedZone!.id.contains('_nested_')) return;
    _saveSnapshot();
    final zone = selectedZone!;
    if (activeSubZone != null && activeSubZone!.contains('cell_')) {
      bool isCurrentlyDoubleSash =
          zone.cellIsDoubleSash[activeSubZone!] ?? false;
      Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
      updatedDoubleSashes[activeSubZone!] = !isCurrentlyDoubleSash;
      zone.cellIsDoubleSash = updatedDoubleSashes;

      // If it becomes a double sash, it cannot be a panel or single sash
      if (updatedDoubleSashes[activeSubZone!] == true) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[activeSubZone!] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[activeSubZone!] = false;
        zone.cellIsSash = updatedSashes;
      }
    }
    _notifyModelListeners();
  }

  void paintCellSash(String zoneId, String cellId, bool isSash) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
      updatedSashes[cellId] = isSash;
      zone.cellIsSash = updatedSashes;

      if (isSash) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[cellId] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
        updatedDoubleSashes[cellId] = false;
        zone.cellIsDoubleSash = updatedDoubleSashes;
      }
      _notifyModelListeners();
    } catch (_) {}
  }

  void paintCellDoubleSash(String zoneId, String cellId, bool isDoubleSash) {
    _saveSnapshot();
    try {
      final zone = zones.firstWhere((z) => z.id == zoneId);
      Map<String, bool> updatedDoubleSashes = Map.from(zone.cellIsDoubleSash);
      updatedDoubleSashes[cellId] = isDoubleSash;
      zone.cellIsDoubleSash = updatedDoubleSashes;

      if (isDoubleSash) {
        Map<String, bool> updatedCells = Map.from(zone.cellIsPanel);
        updatedCells[cellId] = false;
        zone.cellIsPanel = updatedCells;

        Map<String, bool> updatedSashes = Map.from(zone.cellIsSash);
        updatedSashes[cellId] = false;
        zone.cellIsSash = updatedSashes;
      }
      _notifyModelListeners();
    } catch (_) {}
  }

  double? _clampInnerDivisionRatio({
    required WindowZone zone,
    required bool isRightSash,
    required bool isHorizontal,
    required int index,
    required double ratio,
    required List<double> positions,
  }) {
    if (index < 0 || index >= positions.length) return null;

    final sashT =
        zone.sashThickness ??
        getSectionThickness('sash', fallback: profileThickness);
    Rect sashR = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      const sep = 4.0;
      final midX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      sashR = isRightSash
          ? Rect.fromLTRB(
              midX + sep / 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              midX - sep / 2,
              zone.boundary.bottom,
            );
    }

    final glassR = getSafeGlassRect(sashR, sashT);
    final physicalSize = math.max(
      1.0,
      isHorizontal ? glassR.height : glassR.width,
    );
    // Every glazed cell keeps at least [minimumSashCellMm] of clear glass
    // between two dividers (or a divider and the sash); numeric editing and
    // pointer dragging share this rule.
    final dividerT = getSectionThickness('mullion', fallback: sashT);
    final edgeMin = ((WindowModel.minimumSashCellMm + dividerT / 2) / physicalSize)
        .clamp(0.02, 0.45)
        .toDouble();
    final gapMin = ((WindowModel.minimumSashCellMm + dividerT) / physicalSize)
        .clamp(0.02, 0.45)
        .toDouble();
    final minVal = index == 0 ? edgeMin : positions[index - 1] + gapMin;
    final maxVal = index == positions.length - 1
        ? 1.0 - edgeMin
        : positions[index + 1] - gapMin;
    if (minVal > maxVal) return null;
    return ratio.clamp(minVal, maxVal).toDouble();
  }

  void updateZoneInnerHDivisionRatio(
    String zoneId,
    bool isRightSash,
    int index,
    double ratio, {
    bool saveHistory = true,
  }) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    if (saveHistory) _saveSnapshot();
    final zone = zones[idx];
    if (isRightSash) {
      if (zone.rightInnerHPositions.length != zone.rightInnerH) {
        zone.rightInnerHPositions = List.generate(
          zone.rightInnerH,
          (i) => (i + 1) / (zone.rightInnerH + 1),
        );
      }
      final mutable = List<double>.from(zone.rightInnerHPositions);
      if (index >= 0 && index < mutable.length) {
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: true,
          isHorizontal: true,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
        zone.rightInnerHPositions = mutable;
      }
    } else {
      if (zone.innerHPositions.length != zone.innerH) {
        zone.innerHPositions = List.generate(
          zone.innerH,
          (i) => (i + 1) / (zone.innerH + 1),
        );
      }
      final mutable = List<double>.from(zone.innerHPositions);
      if (index >= 0 && index < mutable.length) {
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: false,
          isHorizontal: true,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
        zone.innerHPositions = mutable;
      }
    }
    _notifyModelListeners();
  }

  void updateZoneInnerVDivisionRatio(
    String zoneId,
    bool isRightSash,
    int index,
    double ratio, {
    bool saveHistory = true,
  }) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    if (saveHistory) _saveSnapshot();
    final zone = zones[idx];
    if (isRightSash) {
      if (zone.rightInnerVPositions.length != zone.rightInnerV) {
        zone.rightInnerVPositions = List.generate(
          zone.rightInnerV,
          (i) => (i + 1) / (zone.rightInnerV + 1),
        );
      }
      final mutable = List<double>.from(zone.rightInnerVPositions);
      if (index >= 0 && index < mutable.length) {
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: true,
          isHorizontal: false,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
        zone.rightInnerVPositions = mutable;
      }
    } else {
      if (zone.innerVPositions.length != zone.innerV) {
        zone.innerVPositions = List.generate(
          zone.innerV,
          (i) => (i + 1) / (zone.innerV + 1),
        );
      }
      final mutable = List<double>.from(zone.innerVPositions);
      if (index >= 0 && index < mutable.length) {
        final nextRatio = _clampInnerDivisionRatio(
          zone: zone,
          isRightSash: false,
          isHorizontal: false,
          index: index,
          ratio: ratio,
          positions: mutable,
        );
        if (nextRatio == null) return;
        mutable[index] = nextRatio;
        zone.innerVPositions = mutable;
      }
    }
    _notifyModelListeners();
  }

  /// Moves one handle of a sliding zone alone ([key]: left, right, center,
  /// center2).
  void updateSlidingHandlePosition(String zoneId, String key, double ratio) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    zones[idx].handleRatios[key] = ratio;
    _notifyModelListeners();
  }

  /// Moves every handle of the window holding [zoneId] together.
  void updateWindowHandlePositions(String zoneId, double ratio) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    for (final zone in zonesInFrameOf(zones[idx])) {
      if (!_isSashZone(zone)) continue;
      zone.handlePositionRatio = ratio;
      zone.handleRatios.clear();
    }
    _notifyModelListeners();
  }

  void updateHandlePosition(String zoneId, double ratio) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      zones[idx].handlePositionRatio = ratio;
      _notifyModelListeners();
    }
  }

  void updateHingePosition(String zoneId, double offset) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      zones[idx] = zones[idx].copyWith(middleHingeDragOffset: offset);
      _notifyModelListeners();
    }
  }

  // --- Hinges ---------------------------------------------------------------

  /// Leaves of a hinged zone: one for a single sash, two for a double sash
  /// (0 is the leaf on the left seen from inside).
  int hingedLeafCount(WindowZone zone) {
    if (zone.openDirection == null) return 0;
    if (zone.content == ZoneContent.singleSash) return 1;
    if (zone.content == ZoneContent.doubleSash) return 2;
    return 0;
  }

  /// Whether [leaf] carries the handle (same rule as the painter).
  bool isHandleLeaf(WindowZone zone, int leaf) {
    if (zone.content != ZoneContent.doubleSash) return true;
    if (zone.doubleSashHasTwoHandles) return true;
    final leftActive = zone.openDirection == OpenDirection.left;
    return leaf == 0 ? leftActive : !leftActive;
  }

  /// The handle leaf of a full OB system gets the two hinges of its kit.
  bool sashLeafUsesObKit(WindowZone zone, int leaf) =>
      useSystemOB && isHandleLeaf(zone, leaf);

  /// Top- or bottom-hung single sashes carry their hinges along the width.
  bool hingesAreHorizontal(WindowZone zone) =>
      zone.content == ZoneContent.singleSash &&
      (zone.openDirection == OpenDirection.top ||
          zone.openDirection == OpenDirection.bottom);

  int automaticHingeCount(WindowZone zone) => standardHingeCountForSash(
    sashHeight: hingesAreHorizontal(zone)
        ? zone.boundary.width
        : zone.boundary.height,
    glassStructure: zone.glass.structure,
  );

  SashHingeLayout? _customHingeLayout(WindowZone zone, int leaf) {
    final layout = zone.customHinges[leaf];
    if (layout == null || layout.horizontal != hingesAreHorizontal(zone)) {
      return null;
    }
    return layout;
  }

  bool hasCustomHinges(WindowZone zone, int leaf) =>
      _customHingeLayout(zone, leaf) != null;

  /// Hinge centres of [leaf] in mm from the start of its hinged edge of
  /// [length] mm. The single source for the drawing, the BOM and the PDF.
  List<double> hingePositionsFor(WindowZone zone, int leaf, double length) {
    if (sashLeafUsesObKit(zone, leaf)) {
      return SashHingeRules.automatic(
        length,
        2,
        endInset: SashHingeRules.obEndInsetMm,
      );
    }
    final custom = _customHingeLayout(zone, leaf);
    if (custom != null) return SashHingeRules.fitToLength(custom, length);
    final auto = SashHingeRules.automatic(
      length,
      automaticHingeCount(zone),
      middleOffset: zone.middleHingeDragOffset,
    );
    // The legacy middle-hinge offset was measured from the left on a
    // horizontal edge, not from the head.
    if (!hingesAreHorizontal(zone)) return auto;
    return [for (final p in auto.reversed) length - p];
  }

  /// Hinges [leaf] needs in the BOM.
  int hingeCountForLeaf(WindowZone zone, int leaf) {
    final custom = _customHingeLayout(zone, leaf);
    if (custom == null) return automaticHingeCount(zone);
    final length = hingeEdgeLengthEstimate(zone, leaf);
    return math.min(
      custom.positions.length,
      SashHingeRules.maxCountFor(length),
    );
  }

  /// The hinged edge length of [leaf]: as painted when the editor recorded
  /// it, otherwise from the zone (the head shape only matters to the top
  /// zones, where the placed layout keeps the length it was drawn on).
  double hingeEdgeLengthEstimate(WindowZone zone, int leaf) {
    for (final edge in hingeEdges) {
      if (edge.zoneId == zone.id && edge.leaf == leaf) return edge.length;
    }
    final custom = _customHingeLayout(zone, leaf);
    final shapedHead =
        archHeight != 0 || topSlantLeftY != 0 || topSlantRightY != 0;
    if (custom != null && shapedHead && !hingesAreHorizontal(zone)) {
      return custom.referenceLength;
    }
    return hingesAreHorizontal(zone)
        ? zone.boundary.width
        : zone.boundary.height;
  }

  /// Hinge positions of every hinged leaf, ordered left to right as seen
  /// from inside, for the cutting sheet.
  List<({int sashNumber, bool horizontal, List<double> positions})>
  hingeSummaries() {
    final hinged = zones.where((z) => hingedLeafCount(z) > 0).toList()
      ..sort(
        (a, b) => (a.boundary.left - b.boundary.left).abs() > 1
            ? a.boundary.left.compareTo(b.boundary.left)
            : a.boundary.top.compareTo(b.boundary.top),
      );
    final result =
        <({int sashNumber, bool horizontal, List<double> positions})>[];
    var number = 0;
    for (final zone in hinged) {
      for (var leaf = 0; leaf < hingedLeafCount(zone); leaf++) {
        number++;
        final length = hingeEdgeLengthEstimate(zone, leaf);
        result.add((
          sashNumber: number,
          horizontal: hingesAreHorizontal(zone),
          positions: hingePositionsFor(zone, leaf, length),
        ));
      }
    }
    return result;
  }

  SashHingeEdge? hingeEdgeOf(String zoneId, int leaf) {
    for (final edge in hingeEdges) {
      if (edge.zoneId == zoneId && edge.leaf == leaf) return edge;
    }
    return null;
  }

  void selectHinge(SelectedHinge? hinge) {
    selectedHinge = hinge;
    _notifyModelListeners();
  }

  /// Stores [positions] as the hand-placed layout of [leaf]. Both leaves of
  /// a double sash hang at the same height, so the facing leaf gets the same
  /// layout (moving, adding or removing a hinge on one moves its partner),
  /// unless that leaf carries an OB kit with its own fixed hinges.
  void _storeHinges(
    WindowZone zone,
    int leaf,
    List<double> positions,
    double length,
  ) {
    final layout = SashHingeLayout(
      positions: positions,
      referenceLength: length,
      horizontal: hingesAreHorizontal(zone),
    );
    final partner = 1 - leaf;
    final mirrored =
        zone.content == ZoneContent.doubleSash &&
        !sashLeafUsesObKit(zone, partner);
    zone.customHinges = {
      ...zone.customHinges,
      leaf: layout,
      if (mirrored) partner: layout,
    };
  }

  /// Moves hinge [index] of [leaf] to [target] mm (snapped to 10 mm, kept
  /// between its neighbours and the ends). Returns an error key or null.
  String? moveHinge(
    String zoneId,
    int leaf,
    int index,
    double target,
    double length, {
    bool saveHistory = false,
    bool snapToGrid = true,
  }) {
    final zone = _zoneById(zoneId);
    if (zone == null) return null;
    if (sashLeafUsesObKit(zone, leaf)) return WindowModel.hingeObLockedKey;
    final positions = hingePositionsFor(zone, leaf, length);
    if (index < 0 || index >= positions.length) return null;
    final value = SashHingeRules.clampMove(
      positions,
      index,
      target,
      length,
      snapToGrid: snapToGrid,
    );
    if ((value - positions[index]).abs() < 0.01 &&
        hasCustomHinges(zone, leaf)) {
      return null;
    }
    if (saveHistory) _saveSnapshot();
    positions[index] = value;
    _storeHinges(zone, leaf, positions, length);
    _notifyModelListeners();
    return null;
  }

  /// Adds a hinge to [leaf], as close to [near] as the rules allow (in the
  /// largest gap when null), and selects it. Returns an error key or null.
  String? addHinge(String zoneId, int leaf, double length, {double? near}) {
    final zone = _zoneById(zoneId);
    if (zone == null) return null;
    if (sashLeafUsesObKit(zone, leaf)) return WindowModel.hingeObLockedKey;
    final positions = hingePositionsFor(zone, leaf, length);
    final at = SashHingeRules.insertionPoint(positions, length, near: near);
    if (at == null) return WindowModel.hingeNoRoomKey;
    _saveSnapshot();
    positions
      ..add(at)
      ..sort();
    _storeHinges(zone, leaf, positions, length);
    selectedHinge = SelectedHinge(zoneId, leaf, positions.indexOf(at));
    _notifyModelListeners();
    return null;
  }

  /// Removes hinge [index] of [leaf]; a sash keeps at least two hinges.
  String? removeHinge(String zoneId, int leaf, int index, double length) {
    final zone = _zoneById(zoneId);
    if (zone == null) return null;
    if (sashLeafUsesObKit(zone, leaf)) return WindowModel.hingeObLockedKey;
    final positions = hingePositionsFor(zone, leaf, length);
    if (index < 0 || index >= positions.length) return null;
    if (positions.length <= SashHingeRules.minCount) return WindowModel.hingeMinCountKey;
    _saveSnapshot();
    positions.removeAt(index);
    _storeHinges(zone, leaf, positions, length);
    selectedHinge = null;
    _notifyModelListeners();
    return null;
  }

  /// Returns [leaf] (or every leaf when null) to the automatic layout.
  void resetHinges(String zoneId, {int? leaf}) {
    final zone = _zoneById(zoneId);
    if (zone == null) return;
    if (zone.customHinges.isEmpty && zone.middleHingeDragOffset == 0) return;
    _saveSnapshot();
    // The two leaves of a double sash always share one layout.
    zone.customHinges = leaf == null || zone.content == ZoneContent.doubleSash
        ? {}
        : ({...zone.customHinges}..remove(leaf));
    if (leaf == null || zone.customHinges.isEmpty) {
      zone.middleHingeDragOffset = 0;
    }
    _notifyModelListeners();
  }

  void updateZoneDoubleSashRatio(
    String zoneId,
    double ratio, {
    bool saveHistory = true,
  }) {
    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx != -1) {
      // Same 15–85 % range as every editor: each leaf keeps its own bars.
      ratio = ratio.clamp(0.15, 0.85).toDouble();
      if (saveHistory) _saveSnapshot();
      final zone = zones[idx];
      OpenDirection? newDir = zone.openDirection;
      if (ratio > 0.5) {
        newDir = OpenDirection.left;
      } else if (ratio < 0.5) {
        newDir = OpenDirection.right;
      }
      zones[idx] = zone.copyWith(doubleSashRatio: ratio, openDirection: newDir);
      _notifyModelListeners();
    }
  }

  InnerDimensionHit? _checkSashDivisionHit(
    String zoneId,
    bool isRightSash,
    bool isSash,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    Offset pos,
  ) {
    if (innerH == 0 && innerV == 0) return null;

    List<double> hPositions = List.from(innerHPos);
    if (hPositions.isEmpty && innerH > 0) {
      double stepY = 1.0 / (innerH + 1);
      for (int i = 1; i <= innerH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(innerVPos);
    if (vPositions.isEmpty && innerV > 0) {
      double stepX = 1.0 / (innerV + 1);
      for (int i = 1; i <= innerV; i++) {
        vPositions.add(stepX * i);
      }
    }

    int rows = hPositions.length + 1;
    int cols = vPositions.length + 1;

    // 🟢 التحقق من الضغط على أرقام العرض (الأفقية)
    if (cols > 1) {
      for (int col = 0; col < cols; col++) {
        double leftRatio = col == 0 ? 0.0 : vPositions[col - 1];
        double rightRatio = col == cols - 1 ? 1.0 : vPositions[col];
        double left = glassR.left + (glassR.width * leftRatio);
        double right = glassR.left + (glassR.width * rightRatio);
        double cellW = right - left;

        final leftX = left + cellW / 2;
        // تكبير مساحة الضغط لتسهيل النقر على الرقم
        if (Rect.fromCenter(
          center: Offset(leftX, glassR.top + 25),
          width: 120,
          height: 80,
        ).contains(pos)) {
          return InnerDimensionHit(
            zoneId,
            true, // isWidth
            isDoubleSashLeft: !isRightSash,
            isDoubleSashRight: isRightSash,
            isSashDivision: isSash,
            isHorizontalDivision: false,
            divisionIndex: col,
          );
        }
      }
    }

    // 🟢 التحقق من الضغط على أرقام الارتفاع (العمودية)
    if (rows > 1) {
      for (int row = 0; row < rows; row++) {
        double topRatio = row == 0 ? 0.0 : hPositions[row - 1];
        double bottomRatio = row == rows - 1 ? 1.0 : hPositions[row];
        double top = glassR.top + (glassR.height * topRatio);
        double bottom = glassR.top + (glassR.height * bottomRatio);
        double cellH = bottom - top;

        final topY = top + cellH / 2;
        // تكبير مساحة الضغط لتسهيل النقر على الرقم
        if (Rect.fromCenter(
          center: Offset(glassR.left + 25, topY),
          width: 80,
          height: 120,
        ).contains(pos)) {
          return InnerDimensionHit(
            zoneId,
            false, // isHeight
            isDoubleSashLeft: !isRightSash,
            isDoubleSashRight: isRightSash,
            isSashDivision: isSash,
            isHorizontalDivision: true,
            divisionIndex: row,
          );
        }
      }
    }

    return null;
  }

  void resizeZoneInner(String zoneId, bool isWidth, double newVal) {
    final zIdx = zones.indexWhere((z) => z.id == zoneId);
    if (zIdx == -1) return;
    // An undivided zone has no neighbour to give or take the difference;
    // its size comes from the frame, so only the outer size may change it.
    final limits = innerSizeLimits(zoneId, isWidth);
    if (limits == null) return;
    final r = zones[zIdx].boundary;
    newVal = newVal.clamp(limits.min, limits.max).toDouble();
    if ((newVal - (isWidth ? r.width : r.height)).abs() < 0.001) return;
    _saveSnapshot();
    if (isWidth) {
      double diff = newVal - r.width;
      final bool isRightmost = !zones.any((z) => z.boundary.left > r.right - 2);
      if (isRightmost) {
        _moveInternalBoundaryX(r.left, -diff);
      } else {
        _moveInternalBoundaryX(r.right, diff);
      }
    } else {
      double diff = newVal - r.height;
      final bool isBottommost = !zones.any(
        (z) => z.boundary.top > r.bottom - 2,
      );
      if (isBottommost) {
        _moveInternalBoundaryY(r.top, -diff);
      } else {
        _moveInternalBoundaryY(r.bottom, diff);
      }
    }
    _notifyModelListeners();
  }

  String? removeSashDivisions({
    WindowZone? zoneOverride,
    String? targetCellKey,
  }) {
    final zone = zoneOverride ?? selectedZone;
    if (zone == null) return null;
    _saveSnapshot();
    final selectedCell = targetCellKey ?? activeSubZone;

    // Fresh zones use immutable empty-map defaults. Make every collection
    // mutable before removing the divisions and their obsolete cell data.
    zone.cellIsPanel = Map<String, bool>.from(zone.cellIsPanel);
    zone.cellIsSash = Map<String, bool>.from(zone.cellIsSash);
    zone.cellIsDoubleSash = Map<String, bool>.from(zone.cellIsDoubleSash);
    zone.cellSashOverrides = Map<String, Map<String, dynamic>>.from(
      zone.cellSashOverrides,
    );
    zone.cellGlassSpec = Map<String, GlassSpecification>.from(
      zone.cellGlassSpec,
    );
    zone.disabledVerticalDivisions = Map<String, bool>.from(
      zone.disabledVerticalDivisions,
    );
    zone.disabledHorizontalDivisions = Map<String, bool>.from(
      zone.disabledHorizontalDivisions,
    );

    void clearCellData(bool Function(String key) matches) {
      zone.cellIsPanel.removeWhere((key, value) => matches(key));
      zone.cellIsSash.removeWhere((key, value) => matches(key));
      zone.cellIsDoubleSash.removeWhere((key, value) => matches(key));
      zone.cellSashOverrides.removeWhere((key, value) => matches(key));
      zone.cellGlassSpec.removeWhere((key, value) => matches(key));
    }

    String? normalizedCell;
    if (selectedCell != null && selectedCell.startsWith('right')) {
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.rightPrimaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('right'));
      normalizedCell = 'right_cell_0_0';
    } else if (selectedCell != null && selectedCell.startsWith('left')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('left'));
      normalizedCell = 'left_cell_0_0';
    } else if (selectedCell != null && selectedCell.startsWith('main')) {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.disabledVerticalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      zone.disabledHorizontalDivisions.removeWhere(
        (key, value) => !key.startsWith('right_'),
      );
      clearCellData((key) => key.startsWith('main'));
      normalizedCell = 'main_cell_0_0';
    } else {
      zone.innerH = 0;
      zone.innerV = 0;
      zone.rightInnerH = 0;
      zone.rightInnerV = 0;
      zone.innerHPositions = const [];
      zone.innerVPositions = const [];
      zone.rightInnerHPositions = const [];
      zone.rightInnerVPositions = const [];
      zone.primaryDivisionAxis = null;
      zone.rightPrimaryDivisionAxis = null;
      zone.cellIsPanel.clear();
      zone.cellIsSash.clear();
      zone.cellIsDoubleSash.clear();
      zone.cellSashOverrides.clear();
      zone.cellGlassSpec.clear();
      zone.disabledVerticalDivisions.clear();
      zone.disabledHorizontalDivisions.clear();
    }
    if (identical(zone, selectedZone)) activeSubZone = normalizedCell;
    _notifyModelListeners();
    return normalizedCell;
  }

  void updatePrimaryMullionAxis() {
    bool hasHorizontalBoundaries = false;
    bool hasVerticalBoundaries = false;

    for (int i = 0; i < zones.length; i++) {
      final z1 = zones[i];
      for (int j = i + 1; j < zones.length; j++) {
        final z2 = zones[j];

        double overlapLeft = math.max(z1.boundary.left, z2.boundary.left);
        double overlapRight = math.min(z1.boundary.right, z2.boundary.right);
        if (overlapLeft < overlapRight - 5.0) {
          if ((z1.boundary.bottom - z2.boundary.top).abs() <=
                  divisionThickness + 2.0 ||
              (z2.boundary.bottom - z1.boundary.top).abs() <=
                  divisionThickness + 2.0) {
            hasHorizontalBoundaries = true;
          }
        }

        double overlapTop = math.max(z1.boundary.top, z2.boundary.top);
        double overlapBottom = math.min(z1.boundary.bottom, z2.boundary.bottom);
        if (overlapTop < overlapBottom - 5.0) {
          if ((z1.boundary.right - z2.boundary.left).abs() <=
                  divisionThickness + 2.0 ||
              (z2.boundary.right - z1.boundary.left).abs() <=
                  divisionThickness + 2.0) {
            hasVerticalBoundaries = true;
          }
        }
      }
    }

    if (!hasHorizontalBoundaries && !hasVerticalBoundaries) {
      // لا توجد أي تقسيمات — إعادة التعيين لتبدأ النافذة من جديد
      primaryMullionAxis = null;
      mullionCreationOrder.clear();
      mullionStepCounter = 0;
    } else if (!hasHorizontalBoundaries) {
      primaryMullionAxis = 'v';
    } else if (!hasVerticalBoundaries) {
      primaryMullionAxis = 'h';
    } else {
      // 🟢 إذا وُجد كلاهما: الحفاظ التام على التقسيم الأول الذي بدأ به المستخدم وعدم تغييره
      primaryMullionAxis ??= 'v';
    }
  }

  void splitSelectedZoneHorizontal({
    int parts = 2,
    List<double>? customSizes,
    bool fromTop = true,
  }) {
    if (selectedZone == null) return;
    primaryMullionAxis ??= 'h'; // 🟢 يثبت أول تقسيم أفقي إذا كانت النافذة فارغة
    _saveSnapshot();
    final zone = selectedZone!;
    final previousZoneIds = zones.map((item) => item.id).toSet();
    final index = zones.indexOf(zone);
    final sep = mullionThickness / 2;
    zones.removeAt(index);
    if (customSizes != null && customSizes.isNotEmpty) {
      if (parts == 2) {
        double splitY = fromTop
            ? zone.boundary.top + customSizes[0]
            : zone.boundary.bottom - customSizes[0];
        if (splitY > zone.boundary.top + 20 &&
            splitY < zone.boundary.bottom - 20) {
          recordMullionCreation(true, splitY);
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY + sep,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                zone.boundary.right,
                splitY - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      } else if (parts == 3 && customSizes.length >= 2) {
        double splitY1 = zone.boundary.top + customSizes[0];
        double splitY2 = zone.boundary.bottom - customSizes[1];
        if (splitY2 > splitY1 + 40) {
          recordMullionCreation(true, splitY1);
          recordMullionCreation(true, splitY2);
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY2 + sep,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                splitY1 + sep,
                zone.boundary.right,
                splitY2 - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                zone.boundary.right,
                splitY1 - sep,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      // الحجم المتاح بعد خصم جميع الفواصل بين الأجزاء
      final totalMullions = (parts - 1) * mullionThickness;
      final availableHeight = zone.boundary.height - totalMullions;
      final stepY = availableHeight / parts;
      for (int i = 0; i < parts; i++) {
        double top = zone.boundary.top + (i * stepY) + (i * mullionThickness);
        double bottom = top + stepY;
        if (i < parts - 1) {
          recordMullionCreation(true, bottom + mullionThickness / 2);
        }
        zones.insert(
          index + i,
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              zone.boundary.left,
              top,
              zone.boundary.right,
              bottom,
            ),
            sashColor: zone.sashColor,
            content: zone.content,
            glass: zone.glass.clone(),
            openDirection: zone.openDirection,
            sashThickness: zone.sashThickness,
            isSash105: zone.isSash105,
            lockType: zone.lockType,
            hasSashPlintheBottom: zone.hasSashPlintheBottom,
          ),
        );
      }
    }
    final splitZones = zones
        .where((item) => !previousZoneIds.contains(item.id))
        .toList();
    _normalizeDecorAfterSplit(zone, splitZones);
    _carrySlantedDividers(zone, splitZones);
    updatePrimaryMullionAxis();
    selection = SelectionInfo.none;
    showZoneMenu = false;
    activeSubZone = null;
    _notifyModelListeners();
  }

  /// Applies a regular/custom division pattern inside sash glass without
  /// replacing the sash with new outer-frame zones.
  void configureSelectedSashDivisions({
    required bool horizontal,
    int parts = 2,
    List<double>? customSizes,
    bool fromStart = true,
    bool applyToAllSashes = false,
  }) {
    final selected = selectedZone;
    if (selected == null ||
        (selected.content != ZoneContent.singleSash &&
            selected.content != ZoneContent.doubleSash)) {
      return;
    }
    _saveSnapshot();

    final targets = <(WindowZone, bool, Rect)>[];
    void addZoneSashes(WindowZone zone, {bool allSides = true}) {
      if (zone.content == ZoneContent.singleSash) {
        targets.add((zone, false, zone.boundary));
        return;
      }
      if (zone.content != ZoneContent.doubleSash) return;
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      const gap = 4.0;
      final left = Rect.fromLTRB(
        zone.boundary.left,
        zone.boundary.top,
        splitX - gap / 2,
        zone.boundary.bottom,
      );
      final right = Rect.fromLTRB(
        splitX + gap / 2,
        zone.boundary.top,
        zone.boundary.right,
        zone.boundary.bottom,
      );
      if (allSides) {
        targets.add((zone, false, left));
        targets.add((zone, true, right));
      } else {
        final selectedRight = activeSubZone?.startsWith('right') == true;
        targets.add((zone, selectedRight, selectedRight ? right : left));
      }
    }

    if (applyToAllSashes) {
      for (final zone in zones) {
        addZoneSashes(zone);
      }
    } else {
      addZoneSashes(selected, allSides: false);
    }

    List<double> positionsFor(Rect sashRect, WindowZone zone) {
      final sashThickness =
          zone.sashThickness ??
          getSectionThickness('sash', fallback: profileThickness);
      final glass = getSafeGlassRect(sashRect, sashThickness);
      final extent = horizontal ? glass.height : glass.width;
      if (extent <= 0 || parts < 2) return const [];
      if (customSizes == null || customSizes.isEmpty) {
        return List.generate(parts - 1, (index) => (index + 1) / parts);
      }
      if (parts == 2) {
        final size = customSizes.first.clamp(0.0, extent);
        final ratio = fromStart ? size / extent : 1.0 - (size / extent);
        return [ratio.clamp(0.01, 0.99)];
      }
      if (parts == 3 && customSizes.length >= 2) {
        final first = (customSizes[0] / extent).clamp(0.01, 0.98);
        final second = (1.0 - customSizes[1] / extent).clamp(0.02, 0.99);
        if (second <= first) return const [];
        return [first, second];
      }
      return const [];
    }

    for (final target in targets) {
      final zone = target.$1;
      final isRight = target.$2;
      final positions = positionsFor(target.$3, zone);
      if (positions.isEmpty) continue;
      if (horizontal) {
        if (isRight) {
          zone.rightInnerHPositions = positions;
          zone.rightInnerH = positions.length;
          zone.rightPrimaryDivisionAxis ??= 'h';
          zone.disabledHorizontalDivisions = Map<String, bool>.from(
            zone.disabledHorizontalDivisions,
          )..removeWhere((key, _) => key.startsWith('right_'));
        } else {
          zone.innerHPositions = positions;
          zone.innerH = positions.length;
          zone.primaryDivisionAxis ??= 'h';
          zone.disabledHorizontalDivisions = Map<String, bool>.from(
            zone.disabledHorizontalDivisions,
          )..removeWhere((key, _) => !key.startsWith('right_'));
        }
      } else {
        if (isRight) {
          zone.rightInnerVPositions = positions;
          zone.rightInnerV = positions.length;
          zone.rightPrimaryDivisionAxis ??= 'v';
          zone.disabledVerticalDivisions = Map<String, bool>.from(
            zone.disabledVerticalDivisions,
          )..removeWhere((key, _) => key.startsWith('right_'));
        } else {
          zone.innerVPositions = positions;
          zone.innerV = positions.length;
          zone.primaryDivisionAxis ??= 'v';
          zone.disabledVerticalDivisions = Map<String, bool>.from(
            zone.disabledVerticalDivisions,
          )..removeWhere((key, _) => !key.startsWith('right_'));
        }
      }
    }
    selection = SelectionInfo(type: SelectionType.zone, zoneId: selected.id);
    showZoneMenu = false;
    _notifyModelListeners();
  }

  void splitSelectedZoneVertical({
    int parts = 2,
    List<double>? customSizes,
    bool fromLeft = true,
  }) {
    if (selectedZone == null) return;
    primaryMullionAxis ??= 'v'; // 🟢 يثبت أول تقسيم رأسي إذا كانت النافذة فارغة
    _saveSnapshot();
    final zone = selectedZone!;
    final previousZoneIds = zones.map((item) => item.id).toSet();
    final index = zones.indexOf(zone);
    final sep = mullionThickness / 2;
    zones.removeAt(index);
    if (customSizes != null && customSizes.isNotEmpty) {
      if (parts == 2) {
        double splitX = fromLeft
            ? zone.boundary.left + customSizes[0]
            : zone.boundary.right - customSizes[0];
        if (splitX > zone.boundary.left + 20 &&
            splitX < zone.boundary.right - 20) {
          recordMullionCreation(false, splitX);
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX + sep,
                zone.boundary.top,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                splitX - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      } else if (parts == 3 && customSizes.length >= 2) {
        double splitX1 = zone.boundary.left + customSizes[0];
        double splitX2 = zone.boundary.right - customSizes[1];
        if (splitX2 > splitX1 + 40) {
          recordMullionCreation(false, splitX1);
          recordMullionCreation(false, splitX2);
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX2 + sep,
                zone.boundary.top,
                zone.boundary.right,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                splitX1 + sep,
                zone.boundary.top,
                splitX2 - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
          zones.insert(
            index,
            WindowZone(
              id: UniqueKey().toString(),
              boundary: Rect.fromLTRB(
                zone.boundary.left,
                zone.boundary.top,
                splitX1 - sep,
                zone.boundary.bottom,
              ),
              sashColor: zone.sashColor,
              content: zone.content,
              glass: zone.glass.clone(),
              openDirection: zone.openDirection,
              sashThickness: zone.sashThickness,
              isSash105: zone.isSash105,
              lockType: zone.lockType,
              hasSashPlintheBottom: zone.hasSashPlintheBottom,
            ),
          );
        } else {
          zones.insert(index, zone);
        }
      }
    } else {
      // الحجم المتاح بعد خصم جميع الفواصل بين الأجزاء
      final totalMullions = (parts - 1) * mullionThickness;
      final availableWidth = zone.boundary.width - totalMullions;
      final stepX = availableWidth / parts;
      for (int i = 0; i < parts; i++) {
        double left = zone.boundary.left + (i * stepX) + (i * mullionThickness);
        double right = left + stepX;
        if (i < parts - 1) {
          recordMullionCreation(false, right + mullionThickness / 2);
        }
        zones.insert(
          index + i,
          WindowZone(
            id: UniqueKey().toString(),
            boundary: Rect.fromLTRB(
              left,
              zone.boundary.top,
              right,
              zone.boundary.bottom,
            ),
            sashColor: zone.sashColor,
            content: zone.content,
            glass: zone.glass.clone(),
            openDirection: zone.openDirection,
            sashThickness: zone.sashThickness,
            isSash105: zone.isSash105,
            lockType: zone.lockType,
            hasSashPlintheBottom: zone.hasSashPlintheBottom,
          ),
        );
      }
    }
    final splitZones = zones
        .where((item) => !previousZoneIds.contains(item.id))
        .toList();
    _normalizeDecorAfterSplit(zone, splitZones);
    _carrySlantedDividers(zone, splitZones);
    selection = SelectionInfo.none;
    showZoneMenu = false;
    activeSubZone = null;
    updatePrimaryMullionAxis();
    _notifyModelListeners();
  }

  bool canZoneHaveSash(WindowZone zone) {
    return true;
  }

  /// Returns an explicit 104/105 classification from catalogue metadata.
  /// A null result means that this series uses neutral names and must be
  /// classified from its visible dimensions.
  bool? _explicitSash105FromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return null;
    final code = profile['code']?.toString().toLowerCase() ?? '';
    final name = profile['name']?.toString().toLowerCase() ?? '';
    final type = profile['type']?.toString().toLowerCase() ?? '';
    final description = '$code $name $type';

    if (description.contains('104') ||
        description.contains('fenetre') ||
        description.contains('window')) {
      return false;
    }
    if (description.contains('105') ||
        description.contains('porte') ||
        description.contains('door')) {
      return true;
    }
    return null;
  }

  /// Determines whether a selected sash profile is a 105/door sash.  The
  /// profile controls, the handle controls and the validator all use this
  /// same rule so that they never disagree after a profile is selected.
  bool _isSash105Profile(
    Map<String, dynamic>? profile, {
    double fallbackWidth = 0.0,
  }) {
    if (profile == null) return false;

    final explicit = _explicitSash105FromProfile(profile);
    if (explicit != null) return explicit;

    final double currentWidth =
        (profile['visible_width'] as num?)?.toDouble() ??
        (profile['thickness'] as num?)?.toDouble() ??
        fallbackWidth;
    final series = activeSeries;
    if (series != null) {
      final sashSections = series.sections.where((section) {
        final type = section.type.toLowerCase().trim();
        final name = section.name.toLowerCase().trim();
        return type.contains('sash') ||
            type.contains('ouvrant') ||
            type.contains('ضلفة') ||
            type.contains('ساش') ||
            name.contains('sash') ||
            name.contains('ouvrant') ||
            name.contains('ضلفة') ||
            name.contains('ساش');
      }).toList();

      if (sashSections.isNotEmpty) {
        final widths = sashSections
            .map((section) => section.visibleWidth)
            .where((width) => width > 0)
            .toList();
        if (widths.length > 1) {
          final maxWidth = widths.reduce(math.max);
          final minWidth = widths.reduce(math.min);
          if (maxWidth > minWidth) {
            return (currentWidth - maxWidth).abs() <
                (currentWidth - minWidth).abs();
          }
        }
      }
    }

    // Single-entry catalogues often have neither 104 nor 105 in their name.
    // This is the same practical width rule used by the renderer.
    return currentWidth > (isPVC ? 60.0 : 50.0);
  }

  bool _zoneUsesSash105(WindowZone zone) {
    if (zone.isSash105) return true;

    if (zone.sashOverride != null) {
      return _isSash105Profile(
        zone.sashOverride,
        fallbackWidth: zone.sashThickness ?? 0.0,
      );
    }

    // A divided sash may have its own profile.  Handle state is stored on its
    // parent zone, so keep door-handle options available when such a cell is
    // thick even if the parent was created as a normal window sash.
    for (final cellProfile in zone.cellSashOverrides.values) {
      if (_isSash105Profile(cellProfile)) return true;
    }

    return _isSash105Profile(
      sashOverride,
      fallbackWidth: zone.sashThickness ?? 0.0,
    );
  }

  /// Whether the current selection effectively uses a thick/door sash.
  bool get selectedZoneUsesSash105 {
    final zone = selectedZone;
    return zone != null && _zoneUsesSash105(zone);
  }

  bool _determineIsSash105FromSashOverride() {
    return _isSash105Profile(sashOverride);
  }

  void updateAllSashThicknesses() {
    bool globalIs105 = _determineIsSash105FromSashOverride();

    for (var z in zones) {
      if (z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash ||
          z.content == ZoneContent.slidingSash) {
        if (z.sashOverride != null) {
          z.isSash105 = _isSash105Profile(
            z.sashOverride,
            fallbackWidth: z.sashThickness ?? 0.0,
          );
          z.sashThickness = _calculateSashThickness(
            z.isSash105,
            override: z.sashOverride,
          );
        } else if (z.slidingSashOverride != null &&
            z.content == ZoneContent.slidingSash) {
          z.sashThickness = _calculateSashThickness(
            false,
            override: z.slidingSashOverride,
          );
        } else {
          if (sashOverride != null) {
            z.isSash105 = globalIs105;
          }
          z.sashThickness = _calculateSashThickness(
            z.isSash105,
            override: sashOverride,
          );
        }
      }
    }
  }

  /// Keeps the empty space between two zones equal to the profile that is
  /// actually drawn after a series switch.  Otherwise the canvas retains the
  /// old gap while the painter uses the new series' profile width, which makes
  /// TPR (and other series) mullions look clipped, too wide, or disappear.
  void _synchronizeDivisionGapsForSeries(
    double previousFrameThickness,
    double previousMullionThickness,
  ) {
    if (zones.length < 2 ||
        previousFrameThickness <= 0 ||
        profileThickness <= 0) {
      return;
    }

    final oldMullion = previousMullionThickness > 0
        ? previousMullionThickness
        : previousFrameThickness;
    final newMullion = mullionThickness > 0
        ? mullionThickness
        : profileThickness;
    _synchronizeAxisDivisionGaps(
      isVertical: true,
      oldFrameGap: previousFrameThickness * 2,
      newFrameGap: profileThickness * 2,
      oldMullionGap: oldMullion,
      newMullionGap: newMullion,
    );
    _synchronizeAxisDivisionGaps(
      isVertical: false,
      oldFrameGap: previousFrameThickness * 2,
      newFrameGap: profileThickness * 2,
      oldMullionGap: oldMullion,
      newMullionGap: newMullion,
    );
  }

  void _synchronizeAxisDivisionGaps({
    required bool isVertical,
    required double oldFrameGap,
    required double newFrameGap,
    required double oldMullionGap,
    required double newMullionGap,
  }) {
    final Map<double, double> replacements = {};

    void registerGap(double firstEdge, double secondEdge) {
      final gap = secondEdge - firstEdge;
      if (gap <= 0.0) return;

      double? targetGap;
      if (coupleFrames && (gap - oldFrameGap).abs() <= 3.0) {
        targetGap = newFrameGap;
      } else if ((gap - oldMullionGap).abs() <= 3.0) {
        targetGap = newMullionGap;
      }
      if (targetGap == null || (targetGap - gap).abs() < 0.1) return;

      final center = (firstEdge + secondEdge) / 2.0;
      replacements[firstEdge] = center - targetGap / 2.0;
      replacements[secondEdge] = center + targetGap / 2.0;
    }

    for (var i = 0; i < zones.length; i++) {
      final first = zones[i].boundary;
      for (var j = i + 1; j < zones.length; j++) {
        final second = zones[j].boundary;
        if (isVertical) {
          final overlap =
              math.min(first.bottom, second.bottom) -
              math.max(first.top, second.top);
          if (overlap <= 5.0) continue;
          if (first.right <= second.left) {
            registerGap(first.right, second.left);
          } else if (second.right <= first.left) {
            registerGap(second.right, first.left);
          }
        } else {
          final overlap =
              math.min(first.right, second.right) -
              math.max(first.left, second.left);
          if (overlap <= 5.0) continue;
          if (first.bottom <= second.top) {
            registerGap(first.bottom, second.top);
          } else if (second.bottom <= first.top) {
            registerGap(second.bottom, first.top);
          }
        }
      }
    }

    if (replacements.isEmpty) return;

    double replacementFor(double value) {
      for (final entry in replacements.entries) {
        if ((entry.key - value).abs() <= 0.5) return entry.value;
      }
      return value;
    }

    for (final zone in zones) {
      final boundary = zone.boundary;
      final left = isVertical ? replacementFor(boundary.left) : boundary.left;
      final right = isVertical
          ? replacementFor(boundary.right)
          : boundary.right;
      final top = isVertical ? boundary.top : replacementFor(boundary.top);
      final bottom = isVertical
          ? boundary.bottom
          : replacementFor(boundary.bottom);
      if (right > left + 1.0 && bottom > top + 1.0) {
        zone.boundary = Rect.fromLTRB(left, top, right, bottom);
      }
    }
  }

  void toggleSelectedZoneClassicHandle() {
    if (selectedZone == null) return;
    if (isPVC) {
      selectedZone!.useClassicHandle = true;
      return;
    }
    _saveSnapshot();
    selectedZone!.useClassicHandle = !selectedZone!.useClassicHandle;
    _notifyModelListeners();
  }

  void setSelectedZoneClassicHandle(bool value) {
    if (selectedZone == null) return;
    _saveSnapshot();
    for (final zone in selectedSashZones) {
      zone.useClassicHandle = value;
    }
    _notifyModelListeners();
  }

  void toggleSelectedZoneOctoHandle() {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.useOctoHandle = !selectedZone!.useOctoHandle;
    _notifyModelListeners();
  }

  void setSelectedZoneContent(ZoneContent content) {
    if (selectedZone == null) return;
    final zone = selectedZone!;
    // Keep one canonical transition path.  The drawing-screen menu used to
    // mutate this field directly, which skipped lower-frame restoration.
    paintZoneContent(zone.id, content);
    if (content == ZoneContent.doubleSash ||
        content == ZoneContent.singleSash ||
        content == ZoneContent.slidingSash) {
      zone.useClassicHandle = isPVC;
    } else {
      zone.doubleSashHasTwoHandles = false;
    }
    _clearOpeningOnlyOptionsIfUnavailable();
    updateProfileThickness();
    _notifyModelListeners();
  }

  void setSelectedZoneOpenDirection(OpenDirection dir) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.openDirection = dir;
    _notifyModelListeners();
  }

  void setSelectedZoneLockType(LockType lock) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.lockType = lock;
    _notifyModelListeners();
  }

  /// Applies one complete handle choice in a single update.  Previously the
  /// interface changed the lock then each handle flag separately; every step
  /// notified listeners and the validation layer could restore the preceding
  /// choice before the new one was fully applied.
  void setSelectedZoneHandle({
    LockType lockType = LockType.none,
    bool useOctoHandle = false,
    bool usePvcHandleOnAlu = false,
    bool useClassicHandle = false,
    bool useEncastreeHandle = false,
  }) {
    if (selectedZone == null) return;
    _saveSnapshot();
    // The selected sash, or every sash after a long press.
    for (final zone in selectedSashZones) {
      // Choosing a door-specific handle is an explicit confirmation that the
      // selected sash is the thick/door variant.  Persist it on the zone too
      // so reopening a saved drawing cannot make the selection disappear
      // before its profile metadata is loaded.
      if (lockType == LockType.clef ||
          lockType == LockType.condamnation ||
          lockType == LockType.rouleau ||
          lockType == LockType.rouleau2000) {
        zone.isSash105 = true;
      }
      zone.lockType = lockType;
      zone.useOctoHandle = useOctoHandle;
      zone.usePvcHandleOnAlu = usePvcHandleOnAlu;
      zone.useClassicHandle = useClassicHandle;
      // The recessed handle exists in PVC only.
      zone.useEncastreeHandle = useEncastreeHandle && isPVC;
    }
    _notifyModelListeners();
  }

  /// A double sash uses one handle by default.  This option is reserved for
  /// the rare case where the customer explicitly requests a handle on both
  /// leaves.
  void setSelectedZoneDoubleHandles(bool enabled) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.doubleSash) return;
    _saveSnapshot();
    zone.doubleSashHasTwoHandles = enabled;
    _notifyModelListeners();
  }

  void setSelectedZonePvcHandleOnAlu(bool useIt) {
    if (selectedZone == null) return;
    _saveSnapshot();
    selectedZone!.usePvcHandleOnAlu = useIt;
    _notifyModelListeners();
  }

  Future<void> toggleSashType104105({WindowZone? targetZone}) async {
    final target = targetZone ?? selectedZone;
    if (target == null) return;
    _saveSnapshot();

    bool currentIs105 = target.isSash105;
    if (target.sashOverride != null) {
      final code = target.sashOverride!['code']?.toString().toLowerCase() ?? '';
      final name = target.sashOverride!['name']?.toString().toLowerCase() ?? '';
      if (code.contains('104') || name.contains('104')) {
        currentIs105 = false;
      } else if (code.contains('105') ||
          code.contains('porte') ||
          code.contains('ouvr') ||
          name.contains('105') ||
          name.contains('porte') ||
          name.contains('ouvr') ||
          name.contains('بورت')) {
        currentIs105 = true;
      }
    }

    final targetIs105 = !currentIs105;

    Map<String, dynamic>? matchingSection;
    if (activeSeries != null) {
      final targetCode = targetIs105 ? '105' : '104';
      AluminumSection? foundSection;
      for (final sec in activeSeries!.sections) {
        if (sec.type.toLowerCase() == 'sash' &&
            (sec.code.contains(targetCode) || sec.name.contains(targetCode))) {
          foundSection = sec;
          break;
        }
      }
      if (foundSection != null) {
        double price = 0.0;
        if (selectedDbColor != null) {
          final colorId = selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(foundSection.id, colorId);
        }
        matchingSection = foundSection.toMap();
        matchingSection['calculated_price'] = price;
        matchingSection['manual_selection'] = true;
      }
    }

    // The selected sash, or every sash after a long press.
    final zonesToUpdate = target.id == selectedZone?.id
        ? selectedSashZones
        : [target];

    for (final z in zonesToUpdate) {
      if (z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash) {
        z.isSash105 = targetIs105;
        if (matchingSection != null) {
          z.sashOverride = Map<String, dynamic>.from(matchingSection);
        }
        final widthVal =
            (z.sashOverride?['visible_width'] as num?)?.toDouble() ?? 0.0;
        z.sashThickness = widthVal > 0
            ? widthVal
            : _calculateSashThickness(targetIs105, override: z.sashOverride);
        if (!targetIs105) {
          if (z.lockType == LockType.clef ||
              z.lockType == LockType.condamnation) {
            z.lockType = LockType.none;
          }
        }
      }
    }

    final everySash = zones
        .where(
          (z) =>
              z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash,
        )
        .every(zonesToUpdate.contains);
    if (everySash && matchingSection != null) {
      sashOverride = Map<String, dynamic>.from(matchingSection);
      selectedSashCode =
          matchingSection['code']?.toString() ?? selectedSashCode;
    }

    _notifyModelListeners();
  }

  Future<void> toggleCellSashType104105(String cellKey) async {
    if (selectedZone == null) return;
    _saveSnapshot();

    bool currentIs105 = false;
    final currentOverride = selectedZone!.cellSashOverrides[cellKey];
    if (currentOverride != null) {
      final code = currentOverride['code']?.toString().toLowerCase() ?? '';
      final name = currentOverride['name']?.toString().toLowerCase() ?? '';
      if (code.contains('104') || name.contains('104')) {
        currentIs105 = false;
      } else if (code.contains('105') ||
          code.contains('porte') ||
          code.contains('ouvr') ||
          name.contains('105') ||
          name.contains('porte') ||
          name.contains('ouvr') ||
          name.contains('بورت')) {
        currentIs105 = true;
      } else {
        currentIs105 = false;
      }
    } else {
      currentIs105 = selectedZone!.isSash105;
    }

    bool targetIs105 = !currentIs105;

    if (activeSeries != null) {
      String targetCode = targetIs105 ? '105' : '104';
      AluminumSection? foundSection;
      for (var sec in activeSeries!.sections) {
        if (sec.type.toLowerCase() == 'sash' &&
            (sec.code.contains(targetCode) || sec.name.contains(targetCode))) {
          foundSection = sec;
          break;
        }
      }

      if (foundSection != null) {
        double price = 0.0;
        if (selectedDbColor != null) {
          int colorId = selectedDbColor!['id'];
          final db = SqlDatabase();
          price = await db.getSectionPrice(foundSection.id, colorId);
        }

        final mutableMap = foundSection.toMap();
        mutableMap['calculated_price'] = price;

        final newOverrides = Map<String, Map<String, dynamic>>.from(
          selectedZone!.cellSashOverrides,
        );
        newOverrides[cellKey] = mutableMap;
        selectedZone!.cellSashOverrides = newOverrides;
      } else {
        final newOverrides = Map<String, Map<String, dynamic>>.from(
          selectedZone!.cellSashOverrides,
        );
        newOverrides.remove(cellKey);
        selectedZone!.cellSashOverrides = newOverrides;
      }
      _notifyModelListeners();
    }
  }

  void setCellSashOpenDirection(String cellKey, OpenDirection dir) {
    if (selectedZone == null) return;
    _saveSnapshot();

    final newOverrides = Map<String, Map<String, dynamic>>.from(
      selectedZone!.cellSashOverrides,
    );
    final cellOverride = Map<String, dynamic>.from(newOverrides[cellKey] ?? {});
    cellOverride['openDirection'] = dir.name;
    newOverrides[cellKey] = cellOverride;
    selectedZone!.cellSashOverrides = newOverrides;

    _notifyModelListeners();
  }

  Future<void> _loadDoorKeyLockAccessories() async {
    final d = await db.db;
    if (d == null) return;
    final seriesId = activeSeries?.id;

    Future<Map<String, dynamic>?> findAccessory(
      List<String> keywords,
      String roleKey,
    ) async {
      try {
        if (seriesId != null) {
          final ruleRows = await d.rawQuery(
            '''
            SELECT a.*, c.name as category_name FROM CatalogItemRules r
            JOIN Accessory a ON r.item_id = a.id
            LEFT JOIN AccessoryCategories c ON a.category_id = c.id
            WHERE r.target_table = 'Accessories' AND r.series_id = ? AND r.role_key = ? AND r.is_active = 1
            LIMIT 1
          ''',
            [seriesId, roleKey],
          );
          if (ruleRows.isNotEmpty) return ruleRows.first;

          final keywordConditions = keywords
              .map((k) => 'a.name LIKE ?')
              .join(' OR ');
          final keywordArgs = keywords.map((k) => '%$k%').toList();
          final seriesRows = await d.rawQuery(
            '''
            SELECT a.*, c.name as category_name FROM Accessory a
            LEFT JOIN AccessoryCategories c ON a.category_id = c.id
            WHERE ($keywordConditions)
              AND (a.series_id = ? OR (a.series_ids IS NOT NULL AND ',' || REPLACE(a.series_ids, ' ', '') || ',' LIKE ?))
              AND (a.is_active = 1 OR a.is_active IS NULL)
            LIMIT 1
          ''',
            [...keywordArgs, seriesId, '%,$seriesId,%'],
          );
          if (seriesRows.isNotEmpty) return seriesRows.first;
        }

        final keywordConditions = keywords
            .map((k) => 'a.name LIKE ?')
            .join(' OR ');
        final keywordArgs = keywords.map((k) => '%$k%').toList();
        final fallbackRows = await d.rawQuery('''
          SELECT a.*, c.name as category_name FROM Accessory a
          LEFT JOIN AccessoryCategories c ON a.category_id = c.id
          WHERE ($keywordConditions) AND (a.is_active = 1 OR a.is_active IS NULL)
          LIMIT 1
        ''', keywordArgs);
        if (fallbackRows.isNotEmpty) return fallbackRows.first;
      } catch (error) {
        reportCatalogIssue('Accessories (door lock)', error);
      }
      return null;
    }

    if (!componentOverrides.containsKey('مقبض الباب (Poignée Porte à Clé)')) {
      final acc = await findAccessory([
        'مقبض بمفتاح',
        'مقبض باب',
        'poignée porte',
        'poignee porte',
      ], 'door_handle_key');
      if (acc != null)
        componentOverrides['مقبض الباب (Poignée Porte à Clé)'] = acc;
    }
    if (!componentOverrides.containsKey('قفل الباب (Serrure)')) {
      final acc = await findAccessory([
        'قفل',
        'serrure',
        'سرير',
        'verrou',
      ], 'lock_clef');
      if (acc != null) componentOverrides['قفل الباب (Serrure)'] = acc;
    }
    if (!componentOverrides.containsKey('الأسطوانة (Canon)')) {
      final acc = await findAccessory([
        'canon',
        'الأسطوانة',
        'الاسطوانة',
        'barillet',
      ], 'canon');
      if (acc != null) componentOverrides['الأسطوانة (Canon)'] = acc;
    }
  }

  /// A straight division must not erase the slanted ones: each slanted
  /// division of [source] is carried into the [parts] it was split into,
  /// every part keeping the piece of the line that crosses it.
  void _carrySlantedDividers(WindowZone source, List<WindowZone> parts) {
    if (source.slantedDividers.isEmpty) return;
    for (final part in parts) {
      part.slantedDividers = slantedDividersInPart(
        source.slantedDividers,
        source.boundary,
        part.boundary,
      );
    }
  }

  void _splitIntersectingZonesSmart(Offset start, Offset end, bool horizontal) {
    _saveSnapshot();
    // 🟢 تثبيت أولوية التقسيم الأول (إذا كان أول تقسيم عمودياً يثبت كـ v ولا يتغير)
    if (horizontal) {
      primaryMullionAxis ??= 'h';
    } else {
      primaryMullionAxis ??= 'v';
    }
    final List<WindowZone> newZones = [];
    final sep = mullionThickness / 2;
    double minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    double maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    double cutLine = _snapCutLineToNearbyMullion(start, end, horizontal);
    recordMullionCreation(horizontal, cutLine);

    for (var z in zones) {
      bool intersects = false;
      if (horizontal) {
        if (cutLine > z.boundary.top + 20 && cutLine < z.boundary.bottom - 20) {
          if (maxPath > z.boundary.left && minPath < z.boundary.right) {
            intersects = true;
          }
        }
      } else {
        if (cutLine > z.boundary.left + 20 && cutLine < z.boundary.right - 20) {
          if (maxPath > z.boundary.top && minPath < z.boundary.bottom) {
            intersects = true;
          }
        }
      }
      if (intersects) {
        final splitZones = <WindowZone>[];
        if (horizontal) {
          splitZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                cutLine + sep,
                z.boundary.right,
                z.boundary.bottom,
              ),
            ),
          );
          splitZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                z.boundary.right,
                cutLine - sep,
              ),
            ),
          );
        } else {
          splitZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                cutLine + sep,
                z.boundary.top,
                z.boundary.right,
                z.boundary.bottom,
              ),
            ),
          );
          splitZones.add(
            _splitClone(
              z,
              Rect.fromLTRB(
                z.boundary.left,
                z.boundary.top,
                cutLine - sep,
                z.boundary.bottom,
              ),
            ),
          );
        }
        _normalizeDecorAfterSplit(z, splitZones);
        _carrySlantedDividers(z, splitZones);
        newZones.addAll(splitZones);
      } else {
        newZones.add(z);
      }
    }
    zones = newZones;
    updatePrimaryMullionAxis();
  }

  double _snapCutLineToNearbyMullion(
    Offset start,
    Offset end,
    bool horizontal,
  ) {
    const snapDistance = 100.0;
    final rawCutLine = horizontal ? start.dy : start.dx;
    final minPath = horizontal
        ? math.min(start.dx, end.dx)
        : math.min(start.dy, end.dy);
    final maxPath = horizontal
        ? math.max(start.dx, end.dx)
        : math.max(start.dy, end.dy);
    final candidates = <double>{};

    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final a = zones[i].boundary;
        final b = zones[j].boundary;
        if (horizontal) {
          final aBelowB = (a.bottom - b.top).abs() <= mullionThickness + 4.0;
          final bBelowA = (b.bottom - a.top).abs() <= mullionThickness + 4.0;
          if (!aBelowB && !bBelowA) continue;
          final overlap = math.min(a.right, b.right) - math.max(a.left, b.left);
          if (overlap <= 5.0) continue;
          candidates.add(
            aBelowB ? (a.bottom + b.top) / 2 : (b.bottom + a.top) / 2,
          );
        } else {
          final aLeftOfB = (a.right - b.left).abs() <= mullionThickness + 4.0;
          final bLeftOfA = (b.right - a.left).abs() <= mullionThickness + 4.0;
          if (!aLeftOfB && !bLeftOfA) continue;
          final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
          if (overlap <= 5.0) continue;
          candidates.add(
            aLeftOfB ? (a.right + b.left) / 2 : (b.right + a.left) / 2,
          );
        }
      }
    }

    double? best;
    double bestDistance = snapDistance + 0.001;
    for (final candidate in candidates) {
      final distance = (candidate - rawCutLine).abs();
      if (distance > snapDistance || distance >= bestDistance) continue;
      final cutsAtLeastOneDraggedZone = zones.any((zone) {
        final r = zone.boundary;
        if (horizontal) {
          return candidate > r.top + 20 &&
              candidate < r.bottom - 20 &&
              maxPath > r.left &&
              minPath < r.right;
        }
        return candidate > r.left + 20 &&
            candidate < r.right - 20 &&
            maxPath > r.top &&
            minPath < r.bottom;
      });
      if (!cutsAtLeastOneDraggedZone) continue;
      best = candidate;
      bestDistance = distance;
    }

    return best ?? rawCutLine;
  }

  void moveSelectedMullion(double deltaPixels) {
    moveSelectedMullionWithHistory(deltaPixels);
  }

  /// محاذاة تلقائية للتقسيمات المتوازية المجاورة عندما تكون في مجال 10 سم (100 ملم)
  void _snapNearbyParallelMullions({
    required bool isHorizontal,
    required double targetPos,
  }) {
    const double snapThreshold = 100.0; // 10 سم
    // Use the actual selected divider width.  A flat/double-frame mullion is
    // wider than the catalogue's ordinary mullion; using the ordinary half
    // width here shifted the two neighbouring zones apart after every drag
    // and made frame grouping classify them as two physical frames.
    final effectiveThickness = isDoubleFrameMullionAt(isHorizontal, targetPos)
        ? frameProfileWidthAt(isHorizontal, targetPos) * 2.0
        : math.max(
            mullionThickness,
            _sectionVisibleWidth(
              effectiveMullionSectionAt(isHorizontal, targetPos),
            ),
          );
    final sep = effectiveThickness / 2;

    final candidates = <double>{};
    for (var z in zones) {
      if (isHorizontal) {
        final bottomPos = z.boundary.bottom + sep;
        final topPos = z.boundary.top - sep;
        if (z.boundary.top > profileThickness + 1) candidates.add(topPos);
        if (z.boundary.bottom < height - profileThickness - 1) {
          candidates.add(bottomPos);
        }
      } else {
        final rightPos = z.boundary.right + sep;
        final leftPos = z.boundary.left - sep;
        if (z.boundary.left > profileThickness + 1) candidates.add(leftPos);
        if (z.boundary.right < width - profileThickness - 1) {
          candidates.add(rightPos);
        }
      }
    }

    for (final candidatePos in candidates) {
      final distance = (candidatePos - targetPos).abs();
      if (distance < 1.0 || distance > snapThreshold) continue;

      final diff = targetPos - candidatePos;
      if (isHorizontal) {
        _moveInternalBoundaryY(candidatePos - sep, diff);
      } else {
        _moveInternalBoundaryX(candidatePos - sep, diff);
      }
    }
  }

  void _moveMullionMetadata(String oldKey, String newKey) {
    if (oldKey == newKey) return;
    final profile = mullionProfiles.remove(oldKey);
    if (profile != null) {
      mullionProfiles[newKey] = profile;
    }
    final cavity = groovedMullionCavityOnPositiveSide.remove(oldKey);
    if (cavity != null) {
      groovedMullionCavityOnPositiveSide[newKey] = cavity;
    }
    final section = mullionSectionOverrides.remove(oldKey);
    if (section != null) {
      mullionSectionOverrides[newKey] = section;
    }
  }

  void _shiftMullionMetadata(double dx, double dy) {
    if (dx == 0.0 && dy == 0.0) return;

    String shiftedKey(String key) {
      if (key.length < 3 || key[1] != '_') return key;
      final position = double.tryParse(key.substring(2));
      if (position == null) return key;
      final shifted = position + (key.startsWith('H_') ? dy : dx);
      return '${key.substring(0, 2)}${shifted.toStringAsFixed(1)}';
    }

    final shiftedProfiles = <String, MullionProfileType>{};
    for (final entry in mullionProfiles.entries) {
      shiftedProfiles[shiftedKey(entry.key)] = entry.value;
    }
    mullionProfiles = shiftedProfiles;

    final shiftedCavities = <String, bool>{};
    for (final entry in groovedMullionCavityOnPositiveSide.entries) {
      shiftedCavities[shiftedKey(entry.key)] = entry.value;
    }
    groovedMullionCavityOnPositiveSide = shiftedCavities;

    final shiftedSections = <String, Map<String, dynamic>>{};
    for (final entry in mullionSectionOverrides.entries) {
      shiftedSections[shiftedKey(entry.key)] = entry.value;
    }
    mullionSectionOverrides = shiftedSections;

    if (selection.type == SelectionType.mullion &&
        selection.mullionPosition != null) {
      final horizontal = selection.isHorizontalMullion == true;
      selection = SelectionInfo(
        type: SelectionType.mullion,
        isHorizontalMullion: horizontal,
        mullionPosition: selection.mullionPosition! + (horizontal ? dy : dx),
        mullionStart: selection.mullionStart == null
            ? null
            : selection.mullionStart! + (horizontal ? dx : dy),
        mullionEnd: selection.mullionEnd == null
            ? null
            : selection.mullionEnd! + (horizontal ? dx : dy),
      );
    }
  }

  void setMullionProfile(MullionProfileType type) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    final isHorizontal = selection.isHorizontalMullion!;
    final position = selection.mullionPosition!;

    // تعيين النوع لكل التقسيمات التي تقع على نفس المستوى (كالعلوية والسفلية)
    final collinearPositions = <double>{position};
    for (var i = 0; i < zones.length; i++) {
      for (var j = i + 1; j < zones.length; j++) {
        final za = zones[i].boundary;
        final zb = zones[j].boundary;
        if (isHorizontal) {
          if ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0 ||
              (zb.bottom - za.top).abs() <= maximumMullionThickness + 8.0) {
            final yMid =
                ((za.bottom - zb.top).abs() <= maximumMullionThickness + 8.0)
                ? (za.bottom + zb.top) / 2
                : (zb.bottom + za.top) / 2;
            if ((yMid - position).abs() <= 100.0) collinearPositions.add(yMid);
          }
        } else {
          if ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0 ||
              (zb.right - za.left).abs() <= maximumMullionThickness + 8.0) {
            final xMid =
                ((za.right - zb.left).abs() <= maximumMullionThickness + 8.0)
                ? (za.right + zb.left) / 2
                : (zb.right + za.left) / 2;
            if ((xMid - position).abs() <= 100.0) collinearPositions.add(xMid);
          }
        }
      }
    }

    final previousGap = maximumMullionThickness;
    final wasDoubleFrame = {
      for (final pos in collinearPositions)
        pos: isDoubleFrameMullionAt(isHorizontal, pos),
    };
    for (final pos in collinearPositions) {
      final key = _mullionKey(isHorizontal, pos);
      mullionProfiles[key] = type;
      mullionSectionOverrides.remove(key);
      if (type != MullionProfileType.grooved) {
        groovedMullionCavityOnPositiveSide.remove(key);
        _restoreGlassOnBothSidesOfMullion(isHorizontal, pos);
      } else {
        _enforceGroovedMullionGlassSide(isHorizontal, pos);
      }
    }
    for (final pos in collinearPositions) {
      if (type == MullionProfileType.flat || wasDoubleFrame[pos]!) {
        _respaceZonesAroundMullion(
          isHorizontal,
          pos,
          previousGap: previousGap,
        );
      }
    }
    _notifyModelListeners();
  }

  List<(WindowZone, WindowZone)> _mullionAdjacentPairs(
    bool isHorizontal,
    double position,
  ) {
    final tolerance = math.max(maximumMullionThickness, profileThickness) + 8.0;

    bool isManaged(WindowZone zone) =>
        zone.content == ZoneContent.fixedGlass ||
        zone.content == ZoneContent.empty;

    bool touchesNegativeSide(WindowZone zone) => isHorizontal
        ? (zone.boundary.bottom <= position &&
              (zone.boundary.bottom - position).abs() <= tolerance)
        : (zone.boundary.right <= position &&
              (zone.boundary.right - position).abs() <= tolerance);

    bool touchesPositiveSide(WindowZone zone) => isHorizontal
        ? (zone.boundary.top >= position &&
              (zone.boundary.top - position).abs() <= tolerance)
        : (zone.boundary.left >= position &&
              (zone.boundary.left - position).abs() <= tolerance);

    double overlap(WindowZone a, WindowZone b) {
      if (isHorizontal) {
        return math.min(a.boundary.right, b.boundary.right) -
            math.max(a.boundary.left, b.boundary.left);
      }
      return math.min(a.boundary.bottom, b.boundary.bottom) -
          math.max(a.boundary.top, b.boundary.top);
    }

    final negativeZones = zones
        .where((zone) => isManaged(zone) && touchesNegativeSide(zone))
        .toList();
    final positiveZones = zones
        .where((zone) => isManaged(zone) && touchesPositiveSide(zone))
        .toList();

    final pairs = <(WindowZone, WindowZone)>[];
    for (final negative in negativeZones) {
      for (final positive in positiveZones) {
        if (overlap(negative, positive) > 5.0) {
          pairs.add((negative, positive));
        }
      }
    }
    return pairs;
  }

  /// Reverses the cavity direction of a Cadre 140.  The direction is stored
  /// per mullion, so it stays unchanged after saving or reopening the order.
  bool toggleGroovedMullionCavity(bool isHorizontal, double position) {
    if (!isGroovedFrameMullionAt(isHorizontal, position)) return false;

    _saveSnapshot();
    final key = _mullionKey(isHorizontal, position);
    groovedMullionCavityOnPositiveSide[key] =
        !(groovedMullionCavityOnPositiveSide[key] ?? false);
    _enforceGroovedMullionGlassSide(isHorizontal, position);
    _notifyModelListeners();
    return true;
  }

  void deleteSelectedMullion() {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    _saveSnapshot();
    final bool isH = selection.isHorizontalMullion!;
    final double pos = selection.mullionPosition!;
    final double sep = mullionThickness / 2;
    final double selectedStart =
        selection.mullionStart ?? double.negativeInfinity;
    final double selectedEnd = selection.mullionEnd ?? double.infinity;

    bool overlapsSelectedSpan(WindowZone zone) {
      final spanStart = isH ? zone.boundary.left : zone.boundary.top;
      final spanEnd = isH ? zone.boundary.right : zone.boundary.bottom;
      return math.max(spanStart, selectedStart) <
          math.min(spanEnd, selectedEnd) - 2.0;
    }

    final List<WindowZone> newZones = [];
    final Set<String> processedZoneIds = {};

    if (isH) {
      // ── تقسيم أفقي: دمج كل زوج متقابل (أعلى / أسفل) ──
      final topZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.bottom - (pos - sep)).abs() < 4.0,
          )
          .toList();
      final bottomZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.top - (pos + sep)).abs() < 4.0,
          )
          .toList();

      for (final topZ in topZones) {
        WindowZone? matchingBottom;
        double maxOverlap = 0.0;

        for (final botZ in bottomZones) {
          if (processedZoneIds.contains(botZ.id)) continue;
          final overlapL = math.max(topZ.boundary.left, botZ.boundary.left);
          final overlapR = math.min(topZ.boundary.right, botZ.boundary.right);
          final overlap = overlapR - overlapL;
          if (overlap > 5.0 && overlap > maxOverlap) {
            maxOverlap = overlap;
            matchingBottom = botZ;
          }
        }

        if (matchingBottom != null) {
          processedZoneIds.add(topZ.id);
          processedZoneIds.add(matchingBottom.id);

          final mergedRect = Rect.fromLTRB(
            math.min(topZ.boundary.left, matchingBottom.boundary.left),
            topZ.boundary.top,
            math.max(topZ.boundary.right, matchingBottom.boundary.right),
            matchingBottom.boundary.bottom,
          );

          final primaryZone = topZ.content != ZoneContent.empty
              ? topZ
              : matchingBottom;
          newZones.add(primaryZone.copyWith(boundary: mergedRect));
        }
      }
    } else {
      // ── تقسيم عمودي: دمج كل زوج متقابل (يسار / يمين) ──
      final leftZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.right - (pos - sep)).abs() < 4.0,
          )
          .toList();
      final rightZones = zones
          .where(
            (z) =>
                overlapsSelectedSpan(z) &&
                (z.boundary.left - (pos + sep)).abs() < 4.0,
          )
          .toList();

      for (final leftZ in leftZones) {
        WindowZone? matchingRight;
        double maxOverlap = 0.0;

        for (final rightZ in rightZones) {
          if (processedZoneIds.contains(rightZ.id)) continue;
          final overlapT = math.max(leftZ.boundary.top, rightZ.boundary.top);
          final overlapB = math.min(
            leftZ.boundary.bottom,
            rightZ.boundary.bottom,
          );
          final overlap = overlapB - overlapT;
          if (overlap > 5.0 && overlap > maxOverlap) {
            maxOverlap = overlap;
            matchingRight = rightZ;
          }
        }

        if (matchingRight != null) {
          processedZoneIds.add(leftZ.id);
          processedZoneIds.add(matchingRight.id);

          final mergedRect = Rect.fromLTRB(
            leftZ.boundary.left,
            math.min(leftZ.boundary.top, matchingRight.boundary.top),
            matchingRight.boundary.right,
            math.max(leftZ.boundary.bottom, matchingRight.boundary.bottom),
          );

          final primaryZone = leftZ.content != ZoneContent.empty
              ? leftZ
              : matchingRight;
          newZones.add(primaryZone.copyWith(boundary: mergedRect));
        }
      }
    }

    // إضافة جميع المناطق التي لم تتأثر بالحذف كما هي تماماً
    for (final z in zones) {
      if (!processedZoneIds.contains(z.id)) {
        newZones.add(z);
      }
    }

    zones = newZones;
    selection = SelectionInfo.none;

    final key = _mullionKey(isH, pos);
    mullionProfiles.remove(key);
    groovedMullionCavityOnPositiveSide.remove(key);
    mullionSectionOverrides.remove(key);

    updatePrimaryMullionAxis();
    _notifyModelListeners();
  }

  void deleteSelectedInnerDivision() {
    if (selection.type != SelectionType.innerDivision ||
        selection.zoneId == null ||
        selection.innerDivisionIndex == null) {
      return;
    }
    _saveSnapshot();
    final zoneId = selection.zoneId!;
    final index = selection.innerDivisionIndex!;
    final isH = selection.isHorizontalInnerDivision ?? true;
    final isRight = selection.isRightSashInnerDivision ?? false;

    final idx = zones.indexWhere((z) => z.id == zoneId);
    if (idx == -1) return;
    final zone = zones[idx];

    if (isH) {
      if (isRight) {
        if (zone.rightInnerH > 0) {
          zone.rightInnerH -= 1;
          if (zone.rightInnerHPositions.isNotEmpty) {
            List<double> pos = List.from(zone.rightInnerHPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.rightInnerHPositions = pos;
          }
        }
      } else {
        if (zone.innerH > 0) {
          zone.innerH -= 1;
          if (zone.innerHPositions.isNotEmpty) {
            List<double> pos = List.from(zone.innerHPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.innerHPositions = pos;
          }
        }
      }
    } else {
      if (isRight) {
        if (zone.rightInnerV > 0) {
          zone.rightInnerV -= 1;
          if (zone.rightInnerVPositions.isNotEmpty) {
            List<double> pos = List.from(zone.rightInnerVPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.rightInnerVPositions = pos;
          }
        }
      } else {
        if (zone.innerV > 0) {
          zone.innerV -= 1;
          if (zone.innerVPositions.isNotEmpty) {
            List<double> pos = List.from(zone.innerVPositions);
            if (index < pos.length) pos.removeAt(index);
            zone.innerVPositions = pos;
          }
        }
      }
    }
    selection = SelectionInfo.none;

    // Update primary axes for the zone
    if (zone.innerH == 0 && zone.innerV == 0) {
      zone.primaryDivisionAxis = null;
    } else if (zone.innerH == 0) {
      zone.primaryDivisionAxis = 'v';
    } else if (zone.innerV == 0) {
      zone.primaryDivisionAxis = 'h';
    }
    _keepPrimaryInnerDivisionsContinuous(zone, isRightSash: false);

    if (zone.rightInnerH == 0 && zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = null;
    } else if (zone.rightInnerH == 0) {
      zone.rightPrimaryDivisionAxis = 'v';
    } else if (zone.rightInnerV == 0) {
      zone.rightPrimaryDivisionAxis = 'h';
    }
    _keepPrimaryInnerDivisionsContinuous(zone, isRightSash: true);

    _notifyModelListeners();
  }

  void moveSelectedInnerDivision(
    double deltaX,
    double deltaY, {
    bool saveHistory = true,
  }) {
    if (selection.type != SelectionType.innerDivision ||
        selection.zoneId == null ||
        selection.innerDivisionIndex == null) {
      return;
    }

    if (saveHistory) _saveSnapshot();
    final zone = zones.firstWhere((z) => z.id == selection.zoneId);
    final isH = selection.isHorizontalInnerDivision ?? true;
    final isRight = selection.isRightSashInnerDivision ?? false;
    final index = selection.innerDivisionIndex!;

    double sashT =
        zone.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
    Rect sashR = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      final sep = 4.0;
      final midX = sashR.left + sashR.width * zone.doubleSashRatio;
      sashR = isRight
          ? Rect.fromLTRB(midX + sep / 2, sashR.top, sashR.right, sashR.bottom)
          : Rect.fromLTRB(sashR.left, sashR.top, midX - sep / 2, sashR.bottom);
    }
    Rect glassR = getSafeGlassRect(sashR, sashT);

    const double minDivSpacing = 30.0;
    double minRatioH = minDivSpacing / glassR.height;
    double minRatioV = minDivSpacing / glassR.width;

    double movedAbsolutePos = 0.0;

    if (isH) {
      double deltaRatio = deltaY / glassR.height;
      List<double> pos = List.from(
        isRight ? zone.rightInnerHPositions : zone.innerHPositions,
      );
      if (index < pos.length) {
        double newVal = pos[index] + deltaRatio;
        double minVal = index == 0 ? minRatioH : pos[index - 1] + minRatioH;
        double maxVal = index == pos.length - 1
            ? 1.0 - minRatioH
            : pos[index + 1] - minRatioH;
        if (minVal > maxVal) return;
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerHPositions = pos;
        } else {
          zone.innerHPositions = pos;
        }
        movedAbsolutePos = glassR.top + glassR.height * pos[index];
      }
    } else {
      double deltaRatio = deltaX / glassR.width;
      List<double> pos = List.from(
        isRight ? zone.rightInnerVPositions : zone.innerVPositions,
      );
      if (index < pos.length) {
        double newVal = pos[index] + deltaRatio;
        double minVal = index == 0 ? minRatioV : pos[index - 1] + minRatioV;
        double maxVal = index == pos.length - 1
            ? 1.0 - minRatioV
            : pos[index + 1] - minRatioV;
        if (minVal > maxVal) return;
        pos[index] = newVal.clamp(minVal, maxVal);
        if (isRight) {
          zone.rightInnerVPositions = pos;
        } else {
          zone.innerVPositions = pos;
        }
        movedAbsolutePos = glassR.left + glassR.width * pos[index];
      }
    }

    // ── الالتصاق المغناطيسي للضلفة المجاورة والإطارات المجاورة ضمن 100 ملم ──
    _snapNearbyInnerDivisions(
      sourceZoneId: zone.id,
      sourceIsRight: isRight,
      isHorizontal: isH,
      targetAbsolutePos: movedAbsolutePos,
    );

    _notifyModelListeners();
  }

  /// محاذاة تلقائية لأي تقسيم موازٍ في الضلفة المجاورة (داخل الضلفتين أو عبر المناطق)
  /// عندما يكون في مجال 10 سم (100 ملم)
  void _snapNearbyInnerDivisions({
    required String sourceZoneId,
    required bool sourceIsRight,
    required bool isHorizontal,
    required double targetAbsolutePos,
  }) {
    const double snapThresholdMm = 100.0; // 10 سم

    for (final z in zones) {
      final isDouble = z.content == ZoneContent.doubleSash;
      final sides = isDouble ? [false, true] : [false];

      for (final isRightSide in sides) {
        // تخطي نفس الضلفة التي يتم تحريكها حالياً
        if (z.id == sourceZoneId && isRightSide == sourceIsRight) continue;

        double sT =
            z.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
        Rect sR = z.boundary;
        if (isDouble) {
          final sep = 4.0;
          final midX = sR.left + sR.width * z.doubleSashRatio;
          sR = isRightSide
              ? Rect.fromLTRB(midX + sep / 2, sR.top, sR.right, sR.bottom)
              : Rect.fromLTRB(sR.left, sR.top, midX - sep / 2, sR.bottom);
        }
        final gR = getSafeGlassRect(sR, sT);

        if (isHorizontal) {
          List<double> positions = List.from(
            isRightSide ? z.rightInnerHPositions : z.innerHPositions,
          );
          bool changed = false;
          for (int i = 0; i < positions.length; i++) {
            double currentAbsY = gR.top + gR.height * positions[i];
            if ((currentAbsY - targetAbsolutePos).abs() <= snapThresholdMm) {
              double targetRatio = (targetAbsolutePos - gR.top) / gR.height;
              positions[i] = targetRatio.clamp(0.05, 0.95);
              changed = true;
            }
          }
          if (changed) {
            if (isRightSide) {
              z.rightInnerHPositions = positions;
            } else {
              z.innerHPositions = positions;
            }
          }
        } else {
          List<double> positions = List.from(
            isRightSide ? z.rightInnerVPositions : z.innerVPositions,
          );
          bool changed = false;
          for (int i = 0; i < positions.length; i++) {
            double currentAbsX = gR.left + gR.width * positions[i];
            if ((currentAbsX - targetAbsolutePos).abs() <= snapThresholdMm) {
              double targetRatio = (targetAbsolutePos - gR.left) / gR.width;
              positions[i] = targetRatio.clamp(0.05, 0.95);
              changed = true;
            }
          }
          if (changed) {
            if (isRightSide) {
              z.rightInnerVPositions = positions;
            } else {
              z.innerVPositions = positions;
            }
          }
        }
      }
    }
  }
}

/// The pieces of [dividers] (anchored on [source]) that cross [part], a
/// rectangle cut out of [source], anchored on the edges of [part]. A piece
/// shorter than 50 mm, or with both ends on the same edge, is dropped.
List<SlantedDivider> slantedDividersInPart(
  List<SlantedDivider> dividers,
  Rect source,
  Rect part,
) {
  final kept = <SlantedDivider>[];
  for (final divider in dividers) {
    final clipped = _clipSegmentToRect(
      divider.start.pointOn(source),
      divider.end.pointOn(source),
      part,
    );
    if (clipped == null || (clipped.$2 - clipped.$1).distance < 50) continue;
    final start = _anchorOnRectEdge(clipped.$1, part);
    final end = _anchorOnRectEdge(clipped.$2, part);
    if (start == null || end == null || start.edge == end.edge) continue;
    // A division confined to the cell it was drawn in follows that cell.
    final seed = divider.seedPoint(source);
    if (seed != null && !part.contains(seed)) continue;
    kept.add(
      SlantedDivider(
        id: divider.id,
        start: start,
        end: end,
        profileCode: divider.profileCode,
        seed: seed == null
            ? null
            : Offset(
                (seed.dx - part.left) / part.width,
                (seed.dy - part.top) / part.height,
              ),
      ),
    );
  }
  return kept;
}

/// Liang-Barsky clipping of the segment [a]-[b] to [rect].
(Offset, Offset)? _clipSegmentToRect(Offset a, Offset b, Rect rect) {
  final d = b - a;
  var t0 = 0.0;
  var t1 = 1.0;
  final checks = <(double, double)>[
    (-d.dx, a.dx - rect.left),
    (d.dx, rect.right - a.dx),
    (-d.dy, a.dy - rect.top),
    (d.dy, rect.bottom - a.dy),
  ];
  for (final (p, q) in checks) {
    if (p.abs() < 1e-9) {
      if (q < 0) return null;
      continue;
    }
    final r = q / p;
    if (p < 0) {
      if (r > t1) return null;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return null;
      if (r < t1) t1 = r;
    }
  }
  return (a + d * t0, a + d * t1);
}

/// The anchor of [point], lying on the outline of [rect], on its nearest
/// edge; null when the point is not on the outline.
SlantedDividerAnchor? _anchorOnRectEdge(Offset point, Rect rect) {
  final distances = <ZoneEdge, double>{
    ZoneEdge.top: (point.dy - rect.top).abs(),
    ZoneEdge.bottom: (point.dy - rect.bottom).abs(),
    ZoneEdge.left: (point.dx - rect.left).abs(),
    ZoneEdge.right: (point.dx - rect.right).abs(),
  };
  final nearest = distances.entries.reduce((a, b) => a.value <= b.value ? a : b);
  if (nearest.value > 1.0) return null;
  final horizontalEdge =
      nearest.key == ZoneEdge.top || nearest.key == ZoneEdge.bottom;
  final ratio = horizontalEdge
      ? (point.dx - rect.left) / rect.width
      : (point.dy - rect.top) / rect.height;
  return SlantedDividerAnchor(nearest.key, ratio.clamp(0.0, 1.0));
}
