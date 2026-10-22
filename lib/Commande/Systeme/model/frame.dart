part of '../model.dart';

/// Outer frames, covers, bottom frame, plinthe and profile angles of [WindowModel].
extension WindowModelFrame on WindowModel {
  List<AluminumSection> _sideCoversForSeries(AluminumSeries series) {
    final configuredIds = _seriesDesignRoleSectionIds[series.id]?['side_cover'];
    if (!_hasLoadedRoleMetadata(series) ||
        configuredIds == null ||
        configuredIds.isEmpty) {
      // The drawing can be edited before the role metadata query finishes.
      // In that short window, keep an explicitly typed cover from the same
      // series available instead of cancelling the user's cover selection.
      return series.sections
          .where((section) {
            final type = section.type.trim().toLowerCase();
            return type == 'side_cover' ||
                type == 'couvre_joint' ||
                type == 'couvre-joint';
          })
          .toList(growable: false);
    }
    return series.sections
        .where((section) => configuredIds.contains(section.id))
        .toList(growable: false);
  }

  void _synchronizeSharedSideCover() {
    // The outer frame owns its couvre-joint.  Never scan sibling series in a
    // profile system: a similarly named PVC/aluminium cover from another
    // family must not be injected into the current drawing.
    final owner = activeFrameSeries;
    final covers = owner == null
        ? const <AluminumSection>[]
        : _sideCoversForSeries(owner);

    AluminumSection? selected;
    final selectedId =
        selectedSideCover?.id ??
        (sideCoverOverride?['id'] is num
            ? (sideCoverOverride!['id'] as num).toInt()
            : int.tryParse('${sideCoverOverride?['id'] ?? ''}'));
    final selectedCode =
        (selectedSideCover?.code ??
                sideCoverOverride?['code']?.toString() ??
                '')
            .trim()
            .toLowerCase();
    for (final cover in covers) {
      if ((selectedId != null && cover.id == selectedId) ||
          (selectedCode.isNotEmpty &&
              cover.code.trim().toLowerCase() == selectedCode)) {
        selected = cover;
        break;
      }
    }

    if (selected == null && covers.isNotEmpty) {
      selected = covers.first;
    }
    if (selected == null) {
      selectedSideCover = null;
      sideCoverOverride = null;
      // An integrated couvre-joint belongs to the selected frame and does
      // not require a separate catalogue row. Do not turn off the global
      // cover switch merely because the shared standalone catalogue is empty.
      // This also preserves an explicit user choice when switching series.
      return;
    }

    selectedSideCover = selected;
    final oldOverride = sideCoverOverride;
    sideCoverOverride = selected.toMap();
    if (oldOverride?['calculated_price'] != null) {
      sideCoverOverride!['calculated_price'] = oldOverride!['calculated_price'];
    }
  }

  bool _sectionHasIntegratedSideCover(AluminumSection section) {
    if (section.designIntegratedSideCover != null) {
      return section.designIntegratedSideCover!;
    }
    final name = section.name.toLowerCase();
    final type = section.type.toLowerCase();
    return section.couvreJointWidth > 0 ||
        name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc') ||
        name.contains('sunset') ||
        name.contains('sontara') ||
        name.contains('suntara') ||
        type.contains('monobloc') ||
        type.contains('sunset') ||
        type.contains('sontara') ||
        type.contains('suntara');
  }

  bool _sectionIsSideCover(AluminumSection section) {
    final label = '${section.type} ${section.name}'.toLowerCase().replaceAll(
      '-',
      '_',
    );
    return label.contains('couvre') ||
        label.contains('couvre_joint') ||
        label.contains('couvrejoint') ||
        label.contains('side_cover') ||
        label.contains('sidecover') ||
        label.contains('cover') ||
        label.contains('غطاء') ||
        label.contains('كوفر') ||
        label.contains('كوفرجوا') ||
        label.contains('كوفرجوان') ||
        label.contains('كوفر جوان') ||
        label.contains('كفر') ||
        label.contains('كفرجون') ||
        label.contains('جانبي') ||
        label.contains('جوانب');
  }

  bool _sectionAllowsStandaloneSideCover(AluminumSection section) {
    return !_sectionHasIntegratedSideCover(section) && section.allowsSideCover;
  }

  bool _overrideAllowsStandaloneSideCover(Map<String, dynamic>? override) {
    if (override == null) return true;
    if (_overrideHasIntegratedSideCover(override)) return false;
    final rawAllowed =
        override['design_allows_side_cover'] ?? override['allows_side_cover'];
    if (rawAllowed is bool) return rawAllowed;
    if (rawAllowed is num) return rawAllowed != 0;
    if (rawAllowed is String) {
      final normalized = rawAllowed.trim().toLowerCase();
      return normalized != '0' && normalized != 'false' && normalized != 'no';
    }
    return true;
  }

  bool _frameMapWasManuallySelected(Map<String, dynamic>? override) {
    if (override == null) return false;
    return override['manual_selection'] == true ||
        override['is_manual_selection'] == true ||
        override['user_selected'] == true;
  }

  List<AluminumSection> _compatibleFrameCandidatesForSeries(
    AluminumSeries series,
    List<AluminumSection> frames,
  ) {
    final isMultiFrame = getFrameRects().length > 1;
    if (isMultiFrame) {
      var plain = frames
          .where((frame) => !_sectionHasIntegratedSideCover(frame))
          .toList();
      // With a separate side cover switched on, a frame that can never
      // carry one (40 102 "scj") is not a default choice.
      if (hasSideCovers) {
        final coverable = plain
            .where(_sectionAllowsStandaloneSideCover)
            .toList();
        if (coverable.isNotEmpty) plain = coverable;
      }
      if (plain.isNotEmpty && _frameJoinPartners.isNotEmpty) {
        final otherFrame = _otherJoinedActiveFrame(series);
        if (otherFrame != null) {
          final joinFiltered = plain
              .where((f) => framesCanJoin(f, otherFrame))
              .toList();
          if (joinFiltered.isNotEmpty) return joinFiltered;
        }
      }
      if (plain.isNotEmpty) return plain;
    }

    // With a side cover switched on, a frame that can never carry one is
    // not a default choice.
    if (hasSideCovers) {
      final coverFrames = frames
          .where(
            (frame) =>
                _sectionAllowsStandaloneSideCover(frame) ||
                _sectionHasIntegratedSideCover(frame),
          )
          .toList();
      if (coverFrames.isNotEmpty) frames = coverFrames;
    }

    if (!hasShutter || isCaissonTunnel || _isPvcSeries(series)) return frames;

    // Plain frames must never disappear from the replacement picker merely
    // because a separate side cover is currently enabled.
    return frames
        .where((frame) => !_sectionHasIntegratedSideCover(frame))
        .toList();
  }

  AluminumSection? _otherJoinedActiveFrame(AluminumSeries thisSeries) {
    final isThisSliding = thisSeries == effectiveSlidingSeries;
    final otherOverride = isThisSliding
        ? (frameOverride ?? getSectionByType('frame')?.toMap())
        : (slidingFrameOverride ?? getSlidingSectionByType('frame')?.toMap());
    if (otherOverride == null) return null;
    final otherId = (otherOverride['id'] as num?)?.toInt();
    if (otherId == null) return null;
    final otherSeries = isThisSliding ? activeSeries : effectiveSlidingSeries;
    if (otherSeries == null) return null;
    try {
      return otherSeries.sections.firstWhere((s) => s.id == otherId);
    } catch (_) {
      return null;
    }
  }

  AluminumSection _preferredFrameForSeries(
    List<AluminumSection> frames,
    AluminumSeries series,
  ) {
    if (frames.length <= 1) return frames.first;
    // The frame marked as the default in the series components comes first.
    for (final frame in frames) {
      final row = _seriesDesignRoleOptions[series.id]?['frame']?[frame.id];
      final raw = row?['is_default'];
      if (raw == 1 || raw == true || raw?.toString() == '1') return frame;
    }
    final seriesLabel = '${series.name} ${series.type}'.toLowerCase();
    String? family;
    if (seriesLabel.contains('67000') || seriesLabel.contains('67')) {
      family = '67';
    } else if (seriesLabel.contains('40000') || seriesLabel.contains('40')) {
      family = '40';
    }
    if (family == null) return frames.first;

    return frames.firstWhere(
      (frame) => '${frame.name} ${frame.code}'.toLowerCase().contains(family!),
      orElse: () => frames.first,
    );
  }

  bool _isFrameSection(AluminumSection section) {
    final type = section.type.toLowerCase();
    return section.isFrame ||
        type == 'frame' ||
        type.contains('cadre') ||
        type.contains('إطار') ||
        type.contains('فريم');
  }

  /// Multi-frame drawings keep the side-cover option enabled by default.
  void _enforceMultiFramePlainFrameRule() {
    final previousThickness = profileThickness;
    final previousMullionThickness = mullionThickness;
    var changedFrame = false;
    final isMultiFrame = getFrameRects().length > 1;
    if (!isMultiFrame) {
      if (!hasSideCovers) {
        _multiFrameSideCoverManuallyEnabled = false;
      }
      // A single-frame drawing keeps the user's side-cover state. It must not
      // be reset by notifyListeners or by an unrelated drawing edit.
      return;
    }
    // If the single frame carried an integrated couvre-joint, joining a
    // second frame must preserve the visible cover as a separate profile.
    // The integrated frame itself is not valid in a multi-frame assembly.
    var migrateIntegratedCoverToStandalone = false;

    // Joining frames changes their profile construction, not the user's
    // cover switch or individually hidden sides. Never reset these on notify.

    for (final sliding in [false, true]) {
      final series = sliding ? effectiveSlidingSeries : activeSeries;
      if (series == null) continue;
      final currentFrame = sliding
          ? slidingFrameOverride ?? getSlidingSectionByType('frame')?.toMap()
          : frameOverride ?? getSectionByType('frame')?.toMap();
      final hasIntegrated = _overrideHasIntegratedSideCover(currentFrame);
      migrateIntegratedCoverToStandalone |= hasIntegrated && hasSideCovers;
      // Integrated-cover frames are never valid in a multi-frame assembly.
      // A plain frame, however, always accepts the separately selected cover.
      if (!hasIntegrated) continue;
      final configured = getConfiguredSectionsForRole(
        'frame',
        useSlidingSeries: sliding,
      );
      // Role metadata can contain only the currently selected integrated
      // frame. Always merge it with the real frame sections from the series,
      // otherwise the mandatory multi-frame conversion cannot find the plain
      // counterpart even though it exists in the catalogue.
      final candidateById = <int, AluminumSection>{
        for (final section in configured) section.id: section,
        for (final section in series.sections)
          if (section.isFrame ||
              section.type.toLowerCase() == 'frame' ||
              section.type.toLowerCase().contains('cadre'))
            section.id: section,
      };
      final candidateSections = candidateById.values.toList();
      var plainFrames = candidateSections
          .where(
            (section) =>
                !_sectionHasIntegratedSideCover(section) &&
                (!hasSideCovers || _sectionAllowsStandaloneSideCover(section)),
          )
          .toList();
      if (plainFrames.isEmpty) {
        plainFrames = candidateSections
            .where((section) => !_sectionHasIntegratedSideCover(section))
            .toList();
      }
      if (plainFrames.isEmpty) continue;

      final selected = sliding
          ? _preferredSlidingFrameForTrackCount(
              plainFrames,
              series,
              _requestedSlidingTrackCount(),
            )
          : _preferredFrameForSeries(plainFrames, series);
      final plainFrame = sliding
          ? _slidingFrameMapWithRoleOptions(selected, series)
          : selected.toMap();
      changedFrame = true;
      if (sliding) {
        slidingFrameOverride = plainFrame;
      } else {
        frameOverride = plainFrame;
        selectedFrameCode = plainFrame['code']?.toString();
      }

      if (hasIntegrated) {
        hasSideCovers = true;
        _multiFrameSideCoverManuallyEnabled = true;
      }
    }

    if (changedFrame) {
      updateProfileThickness();
      _synchronizeDivisionGapsForSeries(
        previousThickness,
        previousMullionThickness,
      );
    }

    // These are already the side_cover role of the owning series. A cover's
    // own width/name must not classify it as an integrated FRAME.
    final separateCovers = availableSideCovers;
    if (separateCovers.isNotEmpty) {
      if (!separateCovers.any((cover) => cover.id == selectedSideCover?.id)) {
        selectedSideCover = separateCovers.first;
      }
      if (changedFrame || sideCoverOverride == null) {
        sideCoverOverride = selectedSideCover!.toMap();
      }
      if (migrateIntegratedCoverToStandalone) {
        hasSideCovers = true;
        _multiFrameSideCoverManuallyEnabled = true;
      }
    } else if (migrateIntegratedCoverToStandalone) {
      // Never keep drawing an integrated-frame cover in a multi-frame
      // layout. If the catalogue has no separate cover, keep the plain frame
      // and leave the cover disabled instead of silently using the invalid
      // integrated profile.
      hasSideCovers = false;
      _multiFrameSideCoverManuallyEnabled = false;
    }
  }

  bool _overrideHasIntegratedSideCover(Map<String, dynamic>? override) {
    if (override == null) return false;
    // إذا كان عرض الغطاء المدمج > 0 فهو مدمج بالتأكيد بغض النظر عن design_integrated
    final rawWidth = override['couvre_joint_width'];
    final width = rawWidth is num
        ? rawWidth.toDouble()
        : double.tryParse('${rawWidth ?? ''}') ?? 0.0;
    if (width > 0) return true;

    final name = (override['name'] ?? '').toString().toLowerCase();
    final type = (override['type'] ?? '').toString().toLowerCase();
    final rawIntegrated = override['design_integrated_side_cover'];
    if (rawIntegrated is bool) return rawIntegrated;
    if (rawIntegrated is num) return rawIntegrated != 0;
    if (rawIntegrated is String) {
      final normalized = rawIntegrated.trim().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
      if (normalized == '0' || normalized == 'false' || normalized == 'no') {
        return false;
      }
    }
    return name.contains('مدمج') ||
        name.contains('intégré') ||
        name.contains('integre') ||
        name.contains('monobloc');
  }

  /// Series and override used for the visible outer frame. In a mixed system
  /// the opening series owns the outer frame, while a sliding-only system uses
  /// the sliding series.
  AluminumSeries? get activeFrameSeries =>
      usesSlidingPrimaryProfiles ? activeSlidingSeries : activeSeries;

  Map<String, dynamic>? get activeFrameOverride {
    if (usesSlidingPrimaryProfiles) {
      // getSlidingBaseFrameSection already validates the saved override
      // against the active sliding series and its configured frame role.
      return getSlidingBaseFrameSection()?.toMap();
    }

    final override = frameOverride;
    final series = activeSeries;
    if (override == null || !_hasLoadedRoleMetadata(series)) return override;
    final rawId = override['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    final configuredIds =
        _seriesDesignRoleSectionIds[series!.id]?['frame'] ?? const <int>{};
    return id != null &&
            configuredIds.contains(id) &&
            _configuredSectionMatchesScope(series, 'frame', id, sliding: false)
        ? override
        : null;
  }

  /// Maximum length of one frame profile piece, in millimetres.
  ///
  /// The catalogue stores [AluminumSection.barLength] in metres.  A legacy
  /// row may already contain millimetres, so values above 100 are accepted as
  /// millimetres.  A standalone cover is included when it is actually part
  /// of the drawing; an integrated cover is already part of the frame row.
  double get maximumFrameBarLengthMm {
    double asMillimetres(double value) {
      if (value <= 0) return 0.0;
      return value > 100.0 ? value : value * 1000.0;
    }

    final lengths = <double>[];
    final frameLength = asMillimetres(
      getSectionByType('frame')?.barLength ?? 0,
    );
    if (frameLength > 0) lengths.add(frameLength);

    if (hasSideCovers && !isIntegratedFrame) {
      final overrideLength = sideCoverOverride?['bar_length'];
      final coverLength = asMillimetres(
        selectedSideCover?.barLength ??
            (overrideLength is num
                ? overrideLength.toDouble()
                : double.tryParse(overrideLength?.toString() ?? '') ?? 0.0),
      );
      if (coverLength > 0) lengths.add(coverLength);
    }

    return lengths.isEmpty ? 6000.0 : lengths.reduce(math.min);
  }

  double _limitFrameDimension(double value) =>
      value.clamp(200.0, maximumFrameBarLengthMm).toDouble();

  /// Smallest side of one outer frame: 380 mm, or 250 mm when the other
  /// side is at least one metre (a long, narrow frame is still buildable).
  double minimumFrameSideFor(double otherSide) =>
      otherSide >= 1000.0 ? 250.0 : 380.0;

  /// Applies [_limitFrameDimension] and the 380/250 mm frame rule together.
  Size _limitFrameSize(double w, double h) {
    w = _limitFrameDimension(w);
    h = _limitFrameDimension(h);
    w = math.max(w, minimumFrameSideFor(h));
    h = math.max(h, minimumFrameSideFor(w));
    return Size(w, h);
  }

  /// Legal outer size of the physical frame holding [zoneId]. A legacy frame
  /// already below the rule stays editable at its current size.
  ({double min, double max}) frameOuterLimits(
    String zoneId, {
    required bool isWidth,
  }) {
    final rect = frameRectForZone(zoneId) ?? Rect.fromLTWH(0, 0, width, height);
    final current = isWidth ? rect.width : rect.height;
    final other = isWidth ? rect.height : rect.width;
    var min = minimumFrameSideFor(other);
    if (current > 0 && current < min) min = current;
    return (min: min, max: maximumFrameBarLengthMm);
  }

  /// Smallest clear opening a zone may keep along one axis. A fixed glass
  /// only needs its glazing strip; an opening sash must also fit both of its
  /// sash bars (minus the rebate overlap it shares with the frame). No zone
  /// is ever narrower than [WindowModel.minimumZoneMm].
  double minimumZoneSpanMm(WindowZone zone, {required bool isWidth}) =>
      math.max(
        WindowModel.minimumZoneMm,
        _contentMinimumSpanMm(zone, isWidth: isWidth),
      );

  /// Top end of a vertical mullion centred at [x], [barWidth] wide, that
  /// reaches a slanted or arched head: y of its long point (the higher
  /// corner on the head's inner face) and its cut angle with the head in
  /// degrees, 90 being a square cut. Null under a flat head.
  ({double longPointY, double cutAngleDeg})? verticalMullionHeadCut(
    double x,
    double barWidth,
  ) {
    if (!hasArchOrSlant || barWidth <= 0) return null;
    final inset = profileThickness;
    final yLeft = headEdgeY(x - barWidth / 2, inset);
    final yRight = headEdgeY(x + barWidth / 2, inset);
    final slopeDeg =
        math.atan2((yRight - yLeft).abs(), barWidth) * 180 / math.pi;
    if (slopeDeg < 0.05) return null;
    return (longPointY: math.min(yLeft, yRight), cutAngleDeg: 90 - slopeDeg);
  }

  /// Whether every zone in [parts] keeps [minimumZoneSpanMm] along the axis
  /// a division just cut ([isWidth] for a vertical mullion).
  bool zonesKeepMinimumSpan(
    Iterable<WindowZone> parts, {
    required bool isWidth,
  }) => parts.every((zone) {
    final span = isWidth ? zone.boundary.width : zone.boundary.height;
    return span + 0.01 >= minimumZoneSpanMm(zone, isWidth: isWidth);
  });

  double _contentMinimumSpanMm(WindowZone zone, {required bool isWidth}) {
    final sashT =
        zone.sashThickness ?? getSectionThickness('sash', fallback: 45.0);
    final overlap = openingSashOverlap.clamp(0.0, sashT).toDouble();
    final leaf = 2 * sashT + WindowModel.minimumGlazingSpanMm;
    switch (zone.content) {
      case ZoneContent.singleSash:
        return math.max(WindowModel.minimumGlazingSpanMm, leaf - 2 * overlap);
      case ZoneContent.doubleSash:
        if (!isWidth) {
          return math.max(WindowModel.minimumGlazingSpanMm, leaf - 2 * overlap);
        }
        // The narrower leaf must still fit its own bars at the current ratio.
        final narrowest = math
            .min(zone.doubleSashRatio, 1.0 - zone.doubleSashRatio)
            .clamp(0.15, 0.5)
            .toDouble();
        return math.max(WindowModel.minimumGlazingSpanMm, leaf / narrowest - 2 * overlap);
      case ZoneContent.slidingSash:
        if (!isWidth) return leaf;
        final count = math.max(1, zone.slidingSashesCount);
        return count * (sashT + WindowModel.minimumGlazingSpanMm);
      case ZoneContent.empty:
      case ZoneContent.fixedGlass:
        return WindowModel.minimumGlazingSpanMm;
    }
  }

  /// Smallest outer width/height the current layout can be resized to while
  /// every zone keeps [minimumZoneSpanMm]. [_rescaleZonesInternal] scales all
  /// glazed spans by one factor and keeps mullions and frame bars fixed, so
  /// the limit is reached when the most constrained zone hits its minimum.
  double minimumOuterDimensionForLayout({required bool isWidth}) {
    const absoluteMinimum = 200.0;
    if (zones.isEmpty || isShutterOnly) return absoluteMinimum;
    double startOf(WindowZone z) => isWidth ? z.boundary.left : z.boundary.top;
    double endOf(WindowZone z) =>
        isWidth ? z.boundary.right : z.boundary.bottom;

    final total = isWidth ? width : height;
    final innerStart = zones.map(startOf).reduce(math.min);
    final innerEnd = zones.map(endOf).reduce(math.max);
    final coords = [...zones.map(startOf), ...zones.map(endOf)]..sort();
    final edges = <double>[];
    for (final c in coords) {
      if (edges.isEmpty || c - edges.last > 2.0) edges.add(c);
    }

    double zoneSpanTotal = 0.0;
    double fixedSpanTotal = 0.0;
    for (var i = 0; i < edges.length - 1; i++) {
      final span = edges[i + 1] - edges[i];
      final mid = (edges[i] + edges[i + 1]) / 2;
      final covered = zones.any((z) => startOf(z) <= mid && mid <= endOf(z));
      if (covered) {
        zoneSpanTotal += span;
      } else {
        fixedSpanTotal += span;
      }
    }

    double requiredScale = 0.0;
    for (final z in zones) {
      final span = endOf(z) - startOf(z);
      if (span <= 0) continue;
      requiredScale = math.max(
        requiredScale,
        minimumZoneSpanMm(z, isWidth: isWidth) / span,
      );
    }

    final margins = innerStart + (total - innerEnd);
    return math.max(
      absoluteMinimum,
      margins + fixedSpanTotal + zoneSpanTotal * requiredScale,
    );
  }

  /// Legal outer size range for the whole drawing along one axis. A legacy
  /// drawing that already breaks the minimum stays editable at its current
  /// size instead of being forced to grow.
  ({double min, double max}) outerDimensionLimits({
    required bool isWidth,
    double? otherSide,
  }) {
    if (isShutterOnly) {
      return isWidth
          ? (min: 200.0, max: maximumShutterBarLengthMm)
          : (min: 100.0, max: 10000.0);
    }
    final max = maximumFrameBarLengthMm;
    final current = isWidth ? width : height;
    final layoutMin = minimumOuterDimensionForLayout(isWidth: isWidth);
    var min = math.max(
      layoutMin,
      // [otherSide] is the requested size of the other axis, when both
      // change together (the 250 mm exception depends on it).
      minimumFrameSideFor(otherSide ?? (isWidth ? height : width)),
    );
    // Only a drawing that already breaks the rule at its current sizes keeps
    // its current size as the floor; a valid one must stay valid.
    final minNow = math.max(
      layoutMin,
      minimumFrameSideFor(isWidth ? height : width),
    );
    if (current > 0 && current < minNow) min = math.max(200.0, current);
    return (min: math.min(min, max), max: max);
  }

  /// Legal clear size range for one zone between its neighbours. The size
  /// taken from (or given to) the neighbour keeps the total width/height
  /// unchanged, so the parts always add up to the frame.
  ({double min, double max})? innerSizeLimits(String zoneId, bool isWidth) {
    final index = zones.indexWhere((z) => z.id == zoneId);
    if (index == -1 || !_hasNeighbourAcrossEdge(zones[index], isWidth)) {
      return null;
    }
    final min = minimumZoneSpanMm(zones[index], isWidth: isWidth);
    final max = getMaxAllowedInnerSize(zoneId, isWidth);
    if (max < min) return null;
    return (min: min, max: max);
  }

  /// Whether the edge [resizeZoneInner] would move is shared with another
  /// zone. Without a neighbour the edge is the frame itself and moving it
  /// would detach the zone from its frame bar.
  bool _hasNeighbourAcrossEdge(WindowZone zone, bool isWidth) {
    final r = zone.boundary;
    final gap = divisionThickness + 4;
    bool overlapsAcross(Rect n) => isWidth
        ? math.max(r.top, n.top) < math.min(r.bottom, n.bottom) - 2
        : math.max(r.left, n.left) < math.min(r.right, n.right) - 2;
    final isLast = isWidth
        ? !zones.any((z) => z.boundary.left > r.right - 2)
        : !zones.any((z) => z.boundary.top > r.bottom - 2);
    return zones.any((other) {
      if (identical(other, zone)) return false;
      final n = other.boundary;
      if (!overlapsAcross(n)) return false;
      final distance = isWidth
          ? (isLast ? r.left - n.right : n.left - r.right)
          : (isLast ? r.top - n.bottom : n.top - r.bottom);
      return distance >= -1 && distance <= gap;
    });
  }

  bool get isFramePVC => _isPvcSeries(activeFrameSeries);

  void applyFrameOverride(
    Map<String, dynamic> frame, {
    required bool sliding,
    bool manualSelection = false,
  }) {
    final keepStandaloneSideCover = hasSideCovers;
    final previousThickness = profileThickness;
    final previousMullionThickness = mullionThickness;
    var mutable = Map<String, dynamic>.from(frame);
    if (manualSelection) {
      _sideCoverSelectionRevision++;
      mutable['manual_selection'] = true;
    }

    // An integrated-cover frame is a complete frame selection. Keep it as
    // selected, including for shutter systems; replacing it with a plain
    // frame here made the painter fall back to the unrelated standalone
    // side-cover profile. Multi-frame layouts are handled separately by the
    // perimeter painter and must not change the selected frame either.

    // Selecting a frame from the lower drawing toolbar also selects the
    // cover mode represented by that frame. An integrated-cover frame enables
    // its own cover. A plain frame remains selectable while the cover switch
    // is active and then uses a separate side-cover profile.
    if (manualSelection) {
      final frameHasIntegratedCover = _overrideHasIntegratedSideCover(mutable);
      hasSideCovers = frameHasIntegratedCover || keepStandaloneSideCover;
      _multiFrameSideCoverManuallyEnabled = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      if (!frameHasIntegratedCover && hasSideCovers) {
        final covers = availableSideCovers;
        if (covers.isNotEmpty &&
            !covers.any((cover) => cover.id == selectedSideCover?.id)) {
          selectedSideCover = covers.first;
          sideCoverOverride = covers.first.toMap();
        } else if (selectedSideCover != null && sideCoverOverride == null) {
          sideCoverOverride = selectedSideCover!.toMap();
        }
      }
    }

    final frameHasIntegratedCover = _overrideHasIntegratedSideCover(mutable);
    if (frameHasIntegratedCover) {
      // The couvre-joint belongs to the selected frame itself. It must not
      // remain hidden because a previous plain frame disabled the optional
      // standalone-cover switch.
      hasSideCovers = true;
    }

    if (sliding) {
      slidingFrameOverride = mutable;
      _synchronizeSlidingSashesWithFrameTracks(mutable);
    } else {
      frameOverride = mutable;
      selectedFrameCode = mutable['code']?.toString();
    }
    updateProfileThickness();
    // updateProfileThickness only moves the edges on the outer perimeter.
    // Where two coupled frames meet, the zones kept the old two-jamb gap, so
    // a narrower frame left an empty strip between each sash and the jamb
    // (and the sashes were cut too small).
    _synchronizeDivisionGapsForSeries(
      previousThickness,
      previousMullionThickness,
    );
  }

  List<WindowZone> zonesInFrameOf(WindowZone targetZone) {
    final groups = _frameZoneGroups();
    for (final group in groups) {
      if (group.any((z) => z.id == targetZone.id)) {
        return group;
      }
    }
    return [targetZone];
  }

  /// Replaces the frame reinforcement with the one linked to the currently
  /// selected outer frame and resolves its price for the selected colour.
  /// Keeping this in the model prevents the drawing page and the quantity
  /// table from retaining a reinforcement (or a zero price) from a frame that
  /// the user has already replaced.
  Future<void> syncFrameReinforcement({bool notify = true}) async {
    const reinforcementKey = 'حديد الإطار (Renfort Frame)';

    int? readId(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    if (!isFramePVC) {
      final removed = componentOverrides.remove(reinforcementKey) != null;
      if (notify && removed) _notifyModelListeners();
      return;
    }

    final frame = activeFrameOverride;
    final frameId = readId(frame?['id']);
    final database = await db.db;
    if (frame == null || frameId == null || database == null) return;

    // Always read the current catalogue row. Older saved drawings may have a
    // frame override without the link column even though the catalogue has it.
    final frameRows = await database.query(
      'Sections',
      where: 'id = ?',
      whereArgs: [frameId],
      limit: 1,
    );
    final frameSource = frameRows.isEmpty ? frame : frameRows.first;
    Map<String, dynamic>? reinforcement;
    // The Renfort role is the authoritative association configured for the
    // selected series. This also supports a shared section whose owner is a
    // different series or even a different material system.
    final configuredReinforcement = getConfiguredSectionForRole(
      'renfort',
      useSlidingSeries: false,
    );
    if (configuredReinforcement != null) {
      reinforcement = configuredReinforcement.toMap();
    }

    final linkedReinforcementId = readId(
      frameSource['linked_renfort_id'] ?? frame['linked_renfort_id'],
    );
    if (reinforcement == null && linkedReinforcementId != null) {
      final rows = await database.query(
        'Sections',
        where: 'id = ?',
        whereArgs: [linkedReinforcementId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        reinforcement = Map<String, dynamic>.from(rows.first);
      }
    }

    // Some older catalogues did not store linked_renfort_id. Use the frame
    // reinforcement from the same series rather than making its row/pricing
    // disappear when such a frame is selected.
    if (reinforcement == null) {
      final seriesId = activeFrameSeries?.id;
      if (seriesId != null) {
        final candidates = await database.query(
          'Sections',
          where:
              "series_id = ? AND (LOWER(type) LIKE ? OR LOWER(name) LIKE ? OR name LIKE ?)",
          // "renfor" also matches the catalogue spelling "Renfore".
          whereArgs: [seriesId, '%renfor%', '%renfor%', '%حديد%'],
        );
        if (candidates.isNotEmpty) {
          final preferred = candidates.firstWhere((candidate) {
            final label =
                '${candidate['name'] ?? ''} ${candidate['type'] ?? ''}'
                    .toLowerCase();
            return label.contains('frame') ||
                label.contains('dormant') ||
                label.contains('cadre') ||
                label.contains('إطار');
          }, orElse: () => candidates.first);
          reinforcement = Map<String, dynamic>.from(preferred);
        }
      }
    }

    if (reinforcement == null) {
      final removed = componentOverrides.remove(reinforcementKey) != null;
      if (notify && removed) _notifyModelListeners();
      return;
    }

    final reinforcementId = readId(reinforcement['id']);
    final colorId = readId(selectedDbColor?['id']);
    var price = reinforcementId == null
        ? 0.0
        : await db.getSectionPrice(reinforcementId, colorId);
    if (price <= 0) {
      final rawPrice = reinforcement['price_dzd'] ?? reinforcement['price'];
      price = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
    }

    reinforcement['calculated_price'] = price;
    reinforcement['_linked_frame_id'] = frameId;
    componentOverrides[reinforcementKey] = reinforcement;
    if (notify) _notifyModelListeners();
  }

  bool _zoneEdgeTouchesAnotherZone(
    WindowZone zone, {
    required bool verticalEdge,
    required bool negativeSide,
  }) {
    const tolerance = 3.0;
    final boundary = zone.boundary;
    for (final other in zones) {
      if (other.id == zone.id) continue;
      final otherBoundary = other.boundary;
      if (verticalEdge) {
        final edge = negativeSide ? boundary.left : boundary.right;
        final otherEdge = negativeSide
            ? otherBoundary.right
            : otherBoundary.left;
        final overlap =
            math.min(boundary.bottom, otherBoundary.bottom) -
            math.max(boundary.top, otherBoundary.top);
        if ((edge - otherEdge).abs() <= divisionThickness + tolerance &&
            overlap > 5.0) {
          return true;
        }
      } else {
        final edge = negativeSide ? boundary.top : boundary.bottom;
        final otherEdge = negativeSide
            ? otherBoundary.bottom
            : otherBoundary.top;
        final overlap =
            math.min(boundary.right, otherBoundary.right) -
            math.max(boundary.left, otherBoundary.left);
        if ((edge - otherEdge).abs() <= divisionThickness + tolerance &&
            overlap > 5.0) {
          return true;
        }
      }
    }
    return false;
  }

  bool get hasFrameJoinRules => _frameJoinPartners.isNotEmpty;

  void loadFrameJoinPartners(Map<int, Set<int>> partners) {
    _frameJoinPartners = partners;
  }

  /// Returns true when sections are declared join-compatible.
  /// Sections from DIFFERENT series MUST have an explicit entry in [FrameJoinRules].
  /// Sections from the SAME series must have matching profile thickness and matching sliding/ouvrant category.
  bool framesCanJoin(AluminumSection a, AluminumSection b) {
    if (a.id == b.id) return true;

    // Check sliding vs ouvrant mismatch:
    final aIsSliding =
        a.type.toLowerCase().contains('sliding') ||
        a.type.toLowerCase().contains('couliss') ||
        a.name.toLowerCase().contains('rail') ||
        a.name.toLowerCase().contains('couliss');
    final bIsSliding =
        b.type.toLowerCase().contains('sliding') ||
        b.type.toLowerCase().contains('couliss') ||
        b.name.toLowerCase().contains('rail') ||
        b.name.toLowerCase().contains('couliss');
    if (aIsSliding != bIsSliding) return false;

    // Different series: MUST have an explicit link in _frameJoinPartners!
    if (a.seriesId != 0 && b.seriesId != 0 && a.seriesId != b.seriesId) {
      final partnersOfA = _frameJoinPartners[a.id];
      if (partnersOfA == null) return false;
      return partnersOfA.contains(b.id);
    }

    // Same series: require matching thickness/depth if both specify it
    if (a.thickness > 0 &&
        b.thickness > 0 &&
        (a.thickness - b.thickness).abs() > 2.0) {
      return false;
    }

    return true;
  }

  bool frameMapsCanJoin(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    try {
      final idA = (first['id'] as num?)?.toInt();
      final idB = (second['id'] as num?)?.toInt();
      if (idA != null && idB != null && idA == idB) return true;

      // Sliding vs ouvrant mismatch check:
      bool isSliding(Map<String, dynamic> m) {
        final role = (m['role_key'] ?? m['role'] ?? m['design_role'] ?? '')
            .toString()
            .toLowerCase();
        if (role == 'sliding_frame' || role == 'frame_sliding') return true;
        final uScope =
            (m['usage_scope'] ??
                    m['design_usage_scope'] ??
                    m['sharing_usage_scope'] ??
                    '')
                .toString()
                .toLowerCase();
        if (uScope == 'sliding') return true;
        if (uScope == 'opening' || uScope == 'ouvrant') return false;
        final text =
            '${m['label'] ?? ''} ${m['name'] ?? ''} ${m['type'] ?? ''} ${m['code'] ?? ''}'
                .toLowerCase();
        return RegExp(
          r'\b\d+\s*rail|raill|monorail|couliss|glissi|galandage|سحاب|منزلق|جرار',
        ).hasMatch(text);
      }

      if (isSliding(first) != isSliding(second)) return false;

      // Thickness / depth check:
      final tA = (first['thickness'] as num?)?.toDouble() ?? 0.0;
      final tB = (second['thickness'] as num?)?.toDouble() ?? 0.0;
      if (tA > 0 && tB > 0 && (tA - tB).abs() > 2.0) return false;

      final seriesA =
          (first['series_id'] as num?)?.toInt() ??
          (first['source_series_id'] as num?)?.toInt();
      final seriesB =
          (second['series_id'] as num?)?.toInt() ??
          (second['source_series_id'] as num?)?.toInt();

      if (seriesA != null && seriesB != null && seriesA != seriesB) {
        if (idA == null || idB == null) return false;
        final partnersOfA = _frameJoinPartners[idA];
        if (partnersOfA == null) return false;
        return partnersOfA.contains(idB);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Set<String> profileAngleSidesForFrame(Rect frame) {
    if (!usesProfileAngle) return const {};
    final result = <String>{};
    final junctions = getAdjacentFrameJunctions();
    for (final junction in junctions) {
      if (!activeProfileAngleJunctions.contains(junction.index)) continue;
      if (junction.firstFrame == frame) result.add('right');
      if (junction.secondFrame == frame) result.add('left');
    }
    final frameRects = getFrameRects();
    if (junctions.isEmpty && frameRects.isNotEmpty) {
      if ((profileAngleMode == 2 || profileAngleMode == 3) &&
          frameRects.first == frame) {
        result.add('left');
      }
      if ((profileAngleMode == 1 || profileAngleMode == 3) &&
          frameRects.last == frame) {
        result.add('right');
      }
    }
    return result;
  }

  String? _frameSideStoragePrefix(Rect frame) {
    final owners =
        zones
            .where((zone) => frame.contains(zone.boundary.center))
            .map((zone) => zone.id)
            .toList()
          ..sort();
    if (owners.isEmpty) return null;
    return 'frame-side:${owners.first}';
  }

  Map<String, dynamic>? frameSideOverrideForRect(Rect frame, String side) {
    final prefix = _frameSideStoragePrefix(frame);
    if (prefix != null) {
      final raw = componentOverrides['$prefix:${side.toLowerCase()}'];
      if (raw is Map && raw['pairing_role'] == 'no_cover') {
        // Follows the frame of this side's pairing, even after the frame
        // itself was changed.
        final base = frameSectionForRect(frame);
        final partnerId = base == null ? null : noCoverFrameIdFor(base.id);
        final partner = partnerId == null
            ? null
            : catalogSectionById(partnerId);
        if (partner == null) return null;
        return partner.toMap()
          ..['manual_selection'] = true
          ..['frame_side'] = side.toLowerCase()
          ..['pairing_role'] = 'no_cover';
      }
      if (raw is Map) return Map<String, dynamic>.from(raw);
    }
    // If no manual override on this side, check if it touches a profile angle
    if (usesProfileAngle &&
        profileAngleSidesForFrame(frame).contains(side.toLowerCase())) {
      final currentFrame = frameSectionForRect(frame);
      if (currentFrame != null) {
        final sliding = frameUsesSlidingSeries(frame);
        final compatible = findCompatibleNoCoverFrame(
          currentFrame: currentFrame,
          sliding: sliding,
        );
        if (compatible != null) {
          return compatible.toMap();
        }
      }
    }
    return null;
  }

  bool frameHasSideOverrides(Rect frame) => const [
    'top',
    'right',
    'bottom',
    'left',
  ].any((side) => frameSideOverrideForRect(frame, side) != null);

  /// Whether [side] of [frame] takes the frame its corner profile needs
  /// rather than one chosen by hand.
  bool frameSideIsAutomatic(Rect frame, String side) {
    final prefix = _frameSideStoragePrefix(frame);
    if (prefix != null &&
        componentOverrides['$prefix:${side.toLowerCase()}'] is Map) {
      return false;
    }
    return frameSideOverrideForRect(frame, side) != null;
  }

  /// The face width a frame shows, its thickness when the catalogue gives
  /// none.
  double frameSectionFaceWidth(AluminumSection section) =>
      section.visibleWidth > 0 ? section.visibleWidth : section.thickness;

  /// Whether [candidate] may be cut for one side of a frame made of [base].
  /// A frame in a compatibility group (frame join rules) takes only the
  /// frames of its group. Without a group, only a frame of the same series
  /// (one depth) showing exactly the same visible width.
  /// Only the frames set for [base] in the frame pairing page (its frame
  /// without cover, its corner frame, the frames it joins) may be cut on
  /// one of its sides. Nothing is guessed from widths.
  bool frameFitsSideOf(AluminumSection base, AluminumSection candidate) {
    if (candidate.id == base.id) return true;
    final group = _frameJoinPartners[base.id];
    return group != null && group.contains(candidate.id);
  }

  @visibleForTesting
  void setFrameJoinGroupsForTest(Map<int, Set<int>> partners) =>
      _frameJoinPartners = partners;

  @visibleForTesting
  void setFramePairingsForTest(Map<int, Map<String, dynamic>> pairings) {
    _framePairings = pairings;
    _frameJoinPartners = _partnersFromPairings(pairings);
  }

  int? _pairingId(int sectionId, String column) {
    final raw = _framePairings[sectionId]?[column];
    return raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  }

  /// The frame set to be cut on the sides of [sectionId] without a cover.
  int? noCoverFrameIdFor(int sectionId) =>
      _pairingId(sectionId, 'no_cover_frame_id');

  /// The frame set to be cut against a corner profile for [sectionId].
  int? cornerFrameIdFor(int sectionId) =>
      _pairingId(sectionId, 'corner_frame_id');

  /// A catalogue section by id, from every loaded series.
  AluminumSection? catalogSectionById(int id) {
    for (final system in availableSystems) {
      for (final series in system.series) {
        for (final section in series.sections) {
          if (section.id == id) return section;
        }
      }
    }
    for (final series in [activeSeries, activeSlidingSeries]) {
      for (final section in series?.sections ?? const <AluminumSection>[]) {
        if (section.id == id) return section;
      }
    }
    return null;
  }

  static Map<int, Set<int>> _partnersFromPairings(
    Map<int, Map<String, dynamic>> pairings,
  ) {
    int? read(Object? raw) =>
        raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
    final partners = <int, Set<int>>{};
    pairings.forEach((sectionId, row) {
      final own = partners.putIfAbsent(sectionId, () => <int>{});
      for (final id in [
        read(row['no_cover_frame_id']),
        read(row['corner_frame_id']),
      ].whereType<int>()) {
        if (id != sectionId) own.add(id);
      }
      for (final part in (row['join_ids']?.toString() ?? '').split(',')) {
        final id = int.tryParse(part.trim());
        if (id == null || id == sectionId) continue;
        own.add(id);
        // Joining goes both ways.
        partners.putIfAbsent(id, () => <int>{}).add(sectionId);
      }
    });
    partners.removeWhere((_, value) => value.isEmpty);
    return partners;
  }

  double frameSideVisibleWidth(
    Rect frame,
    String side, {
    required double fallback,
  }) {
    final override = frameSideOverrideForRect(frame, side);
    if (override == null) return fallback;
    final raw = override['visible_width'] ?? override['thickness'];
    final width = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    return width != null && width > 0 ? width : fallback;
  }

  bool frameSideHasIntegratedCover(Rect frame, String side) {
    final override = frameSideOverrideForRect(frame, side);
    final effective = override ?? frameSectionForRect(frame)?.toMap();
    return _overrideHasIntegratedSideCover(effective);
  }

  bool frameSideAllowsSideCover(Rect frame, String side) {
    final override = frameSideOverrideForRect(frame, side);
    final effective = override ?? frameSectionForRect(frame)?.toMap();
    if (effective == null) return true;
    return _overrideAllowsStandaloneSideCover(effective);
  }

  /// Whether [side] of [frame] carries the cover: a bottom needs its frame,
  /// and the side's own frame must take the cover. The drawing and the
  /// quantities both use it, so one frame never takes away its neighbour's
  /// cover.
  bool frameSideTakesSideCover(Rect frame, String side) {
    final normalized = side.toLowerCase();
    if (normalized == 'bottom' && !hasBottomFrameForRect(frame)) return false;
    return isIntegratedFrame
        ? frameSideHasIntegratedCover(frame, normalized)
        : frameSideAllowsSideCover(frame, normalized);
  }

  /// The frames whose [side] lies on the outside of the drawing.
  List<Rect> framesOnOuterSide(String side) {
    final frames = getFrameRects();
    if (frames.isEmpty) return const [];
    const tolerance = 2.0;
    final edge = switch (side) {
      'left' => frames.map((r) => r.left).reduce(math.min),
      'right' => frames.map((r) => r.right).reduce(math.max),
      'top' => frames.map((r) => r.top).reduce(math.min),
      _ => frames.map((r) => r.bottom).reduce(math.max),
    };
    return frames.where((rect) {
      final value = switch (side) {
        'left' => rect.left,
        'right' => rect.right,
        'top' => rect.top,
        _ => rect.bottom,
      };
      return (value - edge).abs() <= tolerance;
    }).toList();
  }

  /// The frames on [side] whose own section has an integrated cover and a
  /// frame "without cover" set in the frame pairing page.
  List<Rect> framesWithNoCoverPartnerOnSide(String side) => [
    for (final frame in framesOnOuterSide(side))
      if (frameSectionForRect(frame) case final base?)
        // Any frame given a "without cover" frame by hand (a traverse has a
        // cover on one side although no cover width is recorded).
        if (noCoverFrameIdFor(base.id) != null &&
            catalogSectionById(noCoverFrameIdFor(base.id)!) != null)
          frame,
  ];

  /// Whether [side] uses the frame "without cover" of its pairing.
  bool sideUsesNoCoverFrame(String side) {
    for (final frame in framesOnOuterSide(side)) {
      final prefix = _frameSideStoragePrefix(frame);
      if (prefix == null) continue;
      final raw = componentOverrides['$prefix:$side'];
      if (raw is Map && raw['pairing_role'] == 'no_cover') return true;
    }
    return false;
  }

  /// Cuts [side] from the frame "without cover" set for its frame (instead
  /// of cutting the integrated cover off): the side then has no cover.
  void useNoCoverFrameOnSide(String side) {
    for (final frame in framesWithNoCoverPartnerOnSide(side)) {
      final base = frameSectionForRect(frame)!;
      final partner = catalogSectionById(noCoverFrameIdFor(base.id)!)!;
      setFrameSideOverrides(frame, [side], {
        ...partner.toMap(),
        'pairing_role': 'no_cover',
      });
    }
  }

  /// Gives [side] back the frame with its integrated cover.
  void restoreCoveredFrameOnSide(String side) {
    for (final frame in framesOnOuterSide(side)) {
      final prefix = _frameSideStoragePrefix(frame);
      if (prefix == null) continue;
      final raw = componentOverrides['$prefix:$side'];
      if (raw is Map && raw['pairing_role'] == 'no_cover') {
        setFrameSideOverrides(frame, [side], null);
      }
    }
    if (!isSideCoverSegmentEnabled(side)) toggleSideCoverSegment(side);
  }

  /// Whether [item] (a frame section) can be used in the current drawing:
  /// shutter, side cover and corner profile all accept it. The drawing's
  /// frame picker and the quantity table's "change" both use this rule.
  /// With [ignoreSideCover] the side cover does not restrict the choice: the
  /// required-goods page then adds or removes the cover with the new frame
  /// (see [setSideCoversAfterFrameSwap]).
  bool frameFitsCurrentDrawing(
    Map<String, dynamic> item, {
    required bool sliding,
    bool ignoreSideCover = false,
  }) {
    bool readBool(Object? value, {required bool fallback}) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value?.toString().trim().toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
      if (normalized == '0' || normalized == 'false' || normalized == 'no') {
        return false;
      }
      return fallback;
    }

    final integratedCover = readBool(
      item['design_integrated_side_cover'] ?? item['integrated_side_cover'],
      fallback: profileHasIntegratedSideCover(item),
    );
    final allowedWithShutter = readBool(
      item['design_allowed_with_shutter'] ?? item['allowed_with_shutter'],
      fallback: true,
    );
    if (hasShutter && !allowedWithShutter) return false;

    if (!ignoreSideCover &&
        hasSideCovers &&
        integratedFrameSideCoverWidth <= 0) {
      // A separate cover: the frame must take one.
      if (integratedCover) return false;
      final allowsStandaloneCover = readBool(
        item['design_allows_side_cover'] ?? item['allows_side_cover'],
        fallback: true,
      );
      if (!allowsStandaloneCover) return false;
    }

    if (usesProfileAngle) {
      try {
        if (!frameUsableWithProfileAngle(
          AluminumSection.fromMap(item),
          sliding: sliding,
        )) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    // A side already cut from the frame "without cover" needs the new frame
    // to have one set too.
    final itemId = item['id'] is num
        ? (item['id'] as num).toInt()
        : int.tryParse(item['id']?.toString() ?? '');
    if (const ['top', 'right', 'bottom', 'left'].any(sideUsesNoCoverFrame) &&
        (itemId == null || noCoverFrameIdFor(itemId) == null)) {
      return false;
    }
    return true;
  }

  void setFrameSideOverrides(
    Rect frame,
    Iterable<String> sides,
    Map<String, dynamic>? section,
  ) {
    final prefix = _frameSideStoragePrefix(frame);
    if (prefix == null) return;
    _saveSnapshot();
    for (final rawSide in sides) {
      final side = rawSide.toLowerCase();
      if (!const {'top', 'right', 'bottom', 'left'}.contains(side)) continue;
      final key = '$prefix:$side';
      if (section == null) {
        componentOverrides.remove(key);
      } else {
        componentOverrides[key] = Map<String, dynamic>.from(section)
          ..['manual_selection'] = true
          ..['frame_side'] = side;
      }

      // If the replaced frame profile for this side cannot carry a couvre-joint,
      // cancel/disable the couvre-joint on this specific side only, keeping all
      // other sides (e.g. top, left, right) intact and active.
      final effective = section ?? frameSectionForRect(frame)?.toMap();
      final allowsCover = isIntegratedFrame
          ? _overrideHasIntegratedSideCover(effective)
          : _overrideAllowsStandaloneSideCover(effective);

      if (getFrameRects().length > 1) {
        // With several frames the cover is kept or dropped per frame side
        // (frameSideTakesSideCover): a neighbouring frame on the same
        // side keeps its own cover.
        if (allowsCover && hasSideCovers) {
          removedShutterSides.remove(side);
          hiddenSideCoverSegments.remove(side);
        }
      } else if (!allowsCover) {
        _materializeLegacySideCoverSegments();
        sideCoverSegments = sideCoverSegments
            .where((s) => s.side != side)
            .toList();
        hiddenSideCoverSegments.add(side);
        removedShutterSides.add(side);
      } else if (hasSideCovers) {
        removedShutterSides.remove(side);
        hiddenSideCoverSegments.remove(side);
      }
    }
    _notifyModelListeners();
  }

  /// Loads the frame pairings set by hand (FramePairingRules).
  Future<void> reloadFrameJoinRules() async {
    final pairings = await db.readFramePairings();
    _framePairings = pairings;
    _frameJoinPartners = _partnersFromPairings(pairings);
  }

  AluminumSection? _frameForMullion(MullionProfileType profileType) {
    final series = activeFrameSeries;
    if (series == null) return null;

    final frames = series.sections
        .where(
          (section) => section.isFrame || section.type.toLowerCase() == 'frame',
        )
        .toList();
    if (frames.isEmpty) return null;

    if (profileType == MullionProfileType.grooved) {
      for (final frame in frames) {
        final code = frame.code.toLowerCase();
        final name = frame.name.toLowerCase();
        if (code.contains('140') || name.contains('140')) return frame;
      }
    }

    if (selectedFrameCode != null && selectedFrameCode!.isNotEmpty) {
      for (final frame in frames) {
        if (frame.code == selectedFrameCode) return frame;
      }
    }

    return frames.first;
  }

  /// A flat mullion is represented by two frame profiles. An explicit flag on
  /// a per-mullion override takes precedence, allowing imported orders to
  /// retain their original construction.
  bool isDoubleFrameMullionAt(bool isHorizontal, double position) {
    final key = _mullionKey(isHorizontal, position);
    final override = mullionSectionOverrides[key];
    if (override != null) {
      for (final flag in const [
        'is_double_frame',
        'isDoubleFrame',
        'double_frame',
        'doubleFrame',
      ]) {
        if (override.containsKey(flag)) return _isEnabledFlag(override[flag]);
      }
      return mullionProfiles[key] == MullionProfileType.flat;
    }

    if (mullionProfiles[key] == MullionProfileType.flat) return true;
    for (final entry in mullionProfiles.entries) {
      if (entry.value == MullionProfileType.flat) {
        if (entry.key.startsWith(isHorizontal ? 'H_' : 'V_')) {
          final p = double.tryParse(entry.key.substring(2));
          if (p != null && (p - position).abs() < 5.0) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool isGroovedFrameMullionAt(bool isHorizontal, double position) =>
      mullionProfiles[_mullionKey(isHorizontal, position)] ==
      MullionProfileType.grooved;

  /// Reads the width the same way as the painter: catalogue rows may carry
  /// it as text ("70"). Ignoring that fell back to [profileThickness], so a
  /// Cadre double was drawn 140 mm wide while frame grouping expected 90 mm
  /// and split the window into two frames.
  double frameProfileWidthAt(bool isHorizontal, double position) =>
      _doubleFrameSectionWidth(
        effectiveMullionSectionAt(isHorizontal, position),
      );

  double _doubleFrameSectionWidth(Map<String, dynamic>? section) {
    for (final field in const ['visible_width', 'thickness']) {
      final value = section?[field];
      final width = value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '');
      if (width != null && width > 0) return width;
    }
    return profileThickness;
  }

  double get plintheHeight {
    if (componentOverrides.containsKey('بلانت (Plinthe)')) {
      final rawWidth =
          componentOverrides['بلانت (Plinthe)']['visible_width'] ??
          componentOverrides['بلانت (Plinthe)']['thickness'];
      final width = rawWidth is num
          ? rawWidth.toDouble()
          : double.tryParse(rawWidth?.toString() ?? '') ?? 0.0;
      if (width > 0) return width;
    }
    final s = getSectionByType('plinthe');
    if (s != null) return s.visibleWidth;
    return 0.0;
  }

  bool get frameSwitchedForProfileAngle => _frameSwitchedForProfileAngle;

  String? get profileAngleFrameSwitchNotice => _profileAngleFrameSwitchNotice;

  bool get multiFrameSideCoverManuallyEnabled =>
      _multiFrameSideCoverManuallyEnabled;

  set multiFrameSideCoverManuallyEnabled(bool value) {
    _multiFrameSideCoverManuallyEnabled = value;
  }

  Rect get expectedOuterFrameClearBoundary {
    final topBox = hasShutter && !hasArchOrSlant && !isCaissonTunnel
        ? shutterBoxHeight
        : 0.0;
    final bottomFrame = hasBottomFrame ? profileThickness : 0.0;
    return Rect.fromLTRB(
      profileThickness,
      topBox + profileThickness,
      math.max(profileThickness, width - profileThickness),
      math.max(topBox + profileThickness, height - bottomFrame),
    );
  }

  /// A drawing with one zone always fills the exact clear opening of the
  /// selected outer frame. Rebuilding this boundary prevents a former frame
  /// width or caisson height from leaking into sash/glass cutting dimensions.
  void _synchronizeSingleZoneWithOuterFrame() {
    if (zones.length != 1 || width <= 0 || height <= 0) return;
    zones.first.boundary = expectedOuterFrameClearBoundary;
  }

  List<AluminumSection> get availableSideCovers {
    final owner = activeFrameSeries;
    return owner == null
        ? const <AluminumSection>[]
        : _sideCoversForSeries(owner);
  }

  /// Whether the selected plain frame accepts a separate side-cover profile.
  ///
  /// This is intentionally separate from [isIntegratedFrame]. A frame with
  /// an integrated cover does not need a second cover row, while a plain
  /// frame may explicitly reject a standalone cover in the catalogue.
  bool get canUseStandaloneSideCover {
    final canSwitchIntegratedFrame =
        _canSwitchIntegratedFrameToStandaloneSideCover;
    if (hasShutter && !isCaissonTunnel && !isFramePVC) {
      final currentFrame = activeFrameOverride;
      if (currentFrame != null) {
        return _overrideAllowsStandaloneSideCover(currentFrame) ||
            canSwitchIntegratedFrame;
      }
      final frame = getSectionByType('frame');
      if (frame != null) {
        return _sectionAllowsStandaloneSideCover(frame) ||
            canSwitchIntegratedFrame;
      }
    }
    if (isIntegratedFrame && !canSwitchIntegratedFrame) return false;
    final frame = getSectionByType('frame');
    final rawAllowed = activeFrameOverride?['allows_side_cover'];
    if (rawAllowed is bool && !rawAllowed) return canSwitchIntegratedFrame;
    if (rawAllowed is num && rawAllowed == 0) return canSwitchIntegratedFrame;
    if (rawAllowed is String &&
        (rawAllowed.trim() == '0' || rawAllowed.toLowerCase() == 'false')) {
      return canSwitchIntegratedFrame;
    }
    if (frame != null && !frame.allowsSideCover) {
      return canSwitchIntegratedFrame;
    }
    return availableSideCovers.isNotEmpty || standaloneSideCoverWidth > 0;
  }

  bool get _currentFrameHasIntegratedSideCover {
    final currentFrame = activeFrameOverride;
    if (currentFrame != null) {
      return _overrideHasIntegratedSideCover(currentFrame);
    }
    final frame = getSectionByType('frame');
    return frame != null && _sectionHasIntegratedSideCover(frame);
  }

  bool get _canSwitchIntegratedFrameToStandaloneSideCover {
    return !isFramePVC &&
        (availableSideCovers.isNotEmpty || standaloneSideCoverWidth > 0) &&
        (_currentFrameHasIntegratedSideCover ||
            !_overrideAllowsStandaloneSideCover(activeFrameOverride)) &&
        _hasFrameThatAllowsStandaloneSideCover;
  }

  bool get _hasFrameThatAllowsStandaloneSideCover {
    final series = activeFrameSeries;
    if (series == null) return false;
    final configuredFrames = getConfiguredSectionsForRole(
      'frame',
      useSlidingSeries: usesSlidingPrimaryProfiles,
    );
    final frames = configuredFrames.isNotEmpty
        ? configuredFrames
        : series.sections;
    return frames.any((section) {
      final type = section.type.toLowerCase();
      return (section.isFrame || type == 'frame' || type.contains('cadre')) &&
          _sectionAllowsStandaloneSideCover(section);
    });
  }

  bool get isSideCoverAllowed {
    // The selected frame owns this cover. Check it before the shutter rule
    // for standalone covers, otherwise an integrated frame can be rejected
    // before the drawing has a chance to render its own side cover.
    if (isIntegratedFrame) return integratedFrameSideCoverWidth > 0;

    if (hasShutter && !isCaissonTunnel && !isFramePVC) {
      final currentFrame = activeFrameOverride;
      if (currentFrame != null) {
        return _overrideAllowsStandaloneSideCover(currentFrame) ||
            _canSwitchIntegratedFrameToStandaloneSideCover;
      }
      final frame = getSectionByType('frame');
      if (frame != null) {
        return _sectionAllowsStandaloneSideCover(frame) ||
            _canSwitchIntegratedFrameToStandaloneSideCover;
      }
    }

    if (!canUseStandaloneSideCover) return false;
    return true;
  }

  bool get isIntegratedFrame {
    // Integration is a property of the selected profile, not the number of
    // frames. The painter separately follows their exposed perimeter.
    // Prefer the exact user-selected override.  The validated accessor can
    // temporarily return null while role metadata is refreshing; falling
    // through in that window incorrectly makes the painter use the separate
    // side-cover profile.
    final selectedOverride = usesSlidingPrimaryProfiles
        ? slidingFrameOverride
        : frameOverride;
    if (selectedOverride != null) {
      return _overrideHasIntegratedSideCover(selectedOverride);
    }
    if (activeFrameOverride != null) {
      return _overrideHasIntegratedSideCover(activeFrameOverride);
    }
    final frame = getSectionByType('frame');
    if (frame == null) return false;
    return _sectionHasIntegratedSideCover(frame);
  }

  /// Width of the selected standalone side-cover face.
  ///
  /// Older catalogues are not perfectly consistent: some TPR rows keep the
  /// drawable face in `visible_width_2` or in a textual measurement instead
  /// of `couvre_joint_width`. This getter deliberately never reads the frame,
  /// so an integrated-frame width cannot leak into a standalone cover
  /// calculation.
  double get standaloneSideCoverWidth {
    double readTextDimension(Object? value) {
      final text = value?.toString().replaceAll(',', '.') ?? '';
      if (text.trim().isEmpty) return 0.0;
      final matches = RegExp(r'\d+(?:\.\d+)?')
          .allMatches(text)
          .map((match) => double.tryParse(match.group(0)!))
          .whereType<double>()
          .where((number) => number > 1.0)
          .toList();
      if (matches.isEmpty) return 0.0;
      return matches.reduce(math.max);
    }

    double firstWidth = selectedSideCover?.couvreJointWidth ?? 0.0;
    double secondWidth = selectedSideCover?.visibleWidth ?? 0.0;
    double thirdWidth = selectedSideCover?.visibleWidth2 ?? 0.0;

    if (selectedSideCover == null && sideCoverOverride != null) {
      double read(String key) {
        final value = sideCoverOverride![key];
        return value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '') ?? 0.0;
      }

      firstWidth = read('couvre_joint_width');
      secondWidth = read('visible_width');
      thirdWidth = read('visible_width_2');
      if (firstWidth <= 0) {
        firstWidth = read('cover_width');
      }
      if (secondWidth <= 0) {
        secondWidth = read('width');
      }
      if (thirdWidth <= 0) {
        thirdWidth = read('largeur');
      }
      if (firstWidth <= 0 && secondWidth <= 0 && thirdWidth <= 0) {
        thirdWidth = math.max(
          readTextDimension(sideCoverOverride!['measurement']),
          readTextDimension(sideCoverOverride!['dimension']),
        );
      }
    }

    final selectedWidth = sideCoverUseSecondWidth ? secondWidth : firstWidth;
    final otherWidth = sideCoverUseSecondWidth ? firstWidth : secondWidth;
    if (selectedWidth > 0) return selectedWidth;
    if (otherWidth > 0) return otherWidth;
    if (thirdWidth > 0) return thirdWidth;
    return 0.0;
  }

  /// Thickness of the selected standalone cover only. It is used to shorten
  /// the frame once for every side on which that cover is actually installed.
  double get standaloneSideCoverThickness {
    if (selectedSideCover != null) {
      return selectedSideCover!.couvreJointThickness;
    }
    final value = sideCoverOverride?['couvre_joint_thickness'];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Integrated-cover width from the selected frame only.
  double get integratedFrameSideCoverWidth {
    final selectedOverride = usesSlidingPrimaryProfiles
        ? slidingFrameOverride
        : frameOverride;
    final source = selectedOverride ?? activeFrameOverride;
    if (source != null) {
      final value = source['couvre_joint_width'];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }
    return getSectionByType('frame')?.couvreJointWidth ?? 0.0;
  }

  double get sideCoverWidth {
    if (isIntegratedFrame) {
      // Missing frame measurements must never borrow another profile's face.
      return integratedFrameSideCoverWidth;
    }
    return standaloneSideCoverWidth;
  }

  bool get hasCustomSideCoverLayout =>
      useCustomSideCoverLayout && sideCoverSegments.isNotEmpty;

  double sideCoverSideLength(String side) {
    switch (side.toLowerCase()) {
      case 'left':
      case 'right':
        return height;
      case 'top':
      case 'bottom':
        return width;
      default:
        return 0.0;
    }
  }

  /// Workshop instruction printed in the side-cover cut row: for every cover
  /// piece that does not span its whole side (or has a special width) state
  /// where it starts and stops, measured from the nearest outer edge(s), e.g.
  /// "from the very top to 70 cm" or "from the top: 10 → 70 cm (from the
  /// bottom: 150 → 210 cm)". Returns null when every piece is standard.
  String? sideCoverWarningText({
    required bool integrated,
    required double fallbackWidth,
    AppLanguage lang = AppLanguage.arabic,
  }) {
    if (!hasSideCovers || fallbackWidth <= 0) return null;
    String t(String ar, String fr, String en) => switch (lang) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      _ => ar,
    };
    String sideLabel(String side) => switch (side) {
      'left' => t('يسار', 'Gauche', 'Left'),
      'right' => t('يمين', 'Droite', 'Right'),
      'top' => t('أعلى', 'Haut', 'Top'),
      'bottom' => t('أسفل', 'Bas', 'Bottom'),
      _ => side,
    };
    String cm(double millimetres) {
      final value = millimetres / 10.0;
      return value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
    }

    final unit = t('سم', 'cm', 'cm');
    final details = <String>[];
    for (final segment in effectiveSideCoverSegments) {
      if (segment.endOffset <= segment.startOffset) continue;
      final width = segment.visibleWidth > 0
          ? segment.visibleWidth
          : fallbackWidth;
      final sideLength = sideCoverSideLength(segment.side);
      final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
      final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
      final reachesStart = start <= 0.1;
      final reachesEnd = sideLength > 0 && (sideLength - end).abs() <= 0.1;
      final hasSpecialSpan = !(reachesStart && reachesEnd);
      final hasSpecialWidth =
          segment.visibleWidth > 0 &&
          (segment.visibleWidth - fallbackWidth).abs() > 0.1;
      if (!hasSpecialSpan && !hasSpecialWidth) continue;

      final vertical = segment.side == 'left' || segment.side == 'right';
      final fromStart = vertical
          ? t('من الأعلى', 'depuis le haut', 'from the top')
          : t('من اليسار', 'depuis la gauche', 'from the left');
      final fromEnd = vertical
          ? t('من الأسفل', 'depuis le bas', 'from the bottom')
          : t('من اليمين', 'depuis la droite', 'from the right');
      final startEdge = vertical
          ? t('أقصى الأعلى', 'tout en haut', 'the very top')
          : t('أقصى اليسار', 'tout à gauche', 'the far left');
      final endEdge = vertical
          ? t('أقصى الأسفل', 'tout en bas', 'the very bottom')
          : t('أقصى اليمين', 'tout à droite', 'the far right');

      var spanText = '';
      if (hasSpecialSpan) {
        final length = cm(end - start);
        final lengthText = t(
          'بطول $length $unit',
          'longueur $length $unit',
          'length $length $unit',
        );
        if (reachesStart) {
          spanText = t(
            'يبدأ من $startEdge (0) إلى ${cm(end)} $unit، $lengthText',
            'part de $startEdge (0) jusqu’à ${cm(end)} $unit, $lengthText',
            'starts at $startEdge (0) up to ${cm(end)} $unit, $lengthText',
          );
        } else if (reachesEnd) {
          spanText = t(
            'يبدأ من $endEdge (0) إلى ${cm(sideLength - start)} $unit، $lengthText',
            'part de $endEdge (0) jusqu’à ${cm(sideLength - start)} $unit, $lengthText',
            'starts at $endEdge (0) up to ${cm(sideLength - start)} $unit, $lengthText',
          );
        } else {
          spanText = t(
            '$fromStart: من ${cm(start)} إلى ${cm(end)} $unit '
                '($fromEnd: من ${cm(sideLength - end)} إلى ${cm(sideLength - start)} $unit)، $lengthText',
            '$fromStart : de ${cm(start)} à ${cm(end)} $unit '
                '($fromEnd : de ${cm(sideLength - end)} à ${cm(sideLength - start)} $unit), $lengthText',
            '$fromStart: ${cm(start)} to ${cm(end)} $unit '
                '($fromEnd: ${cm(sideLength - end)} to ${cm(sideLength - start)} $unit), $lengthText',
          );
        }
        spanText = '$spanText${t('، ', ', ', ', ')}';
      }
      details.add(
        '${sideLabel(segment.side)}: $spanText'
        '${t('عرضه الظاهر', 'largeur visible', 'visible width')} ${cm(width)} $unit',
      );
    }
    if (details.isEmpty) return null;
    final kind = integrated
        ? t('المدمج', 'intégré', 'integrated')
        : t('المنفصل', 'séparé', 'separate');
    return '${t('تنبيه الغطاء الجانبي', 'Attention couvre-joint', 'Warning side cover')} '
        '$kind: ${details.join(t('؛ ', ' ; ', '; '))}';
  }

  SideCoverSegment? sideCoverSegmentForSide(String side) {
    final normalized = side.toLowerCase();
    for (final segment in sideCoverSegments) {
      if (segment.side == normalized) return segment;
    }
    return null;
  }

  /// Keeps custom cover pieces attached to the frame edges when the overall
  /// window size changes. A piece ending at an outer edge extends with that
  /// edge; a piece wholly inside the frame keeps its explicitly chosen size.
  void _resizeSideCoverSegments(
    double oldWidth,
    double oldHeight,
    double newWidth,
    double newHeight,
  ) {
    if (!useCustomSideCoverLayout || sideCoverSegments.isEmpty) return;

    double lengthFor(String side, double windowWidth, double windowHeight) {
      switch (side.toLowerCase()) {
        case 'left':
        case 'right':
          return windowHeight;
        case 'top':
        case 'bottom':
          return windowWidth;
        default:
          return 0.0;
      }
    }

    // Saved drawings can round a full-length cover by one or two millimetres.
    // Treat that as attached to the outer edge so a couvre-joint still grows
    // with the drawing instead of leaving a thin uncovered gap after resize.
    bool isAtEdge(double value, double edge) => (value - edge).abs() <= 2.0;

    sideCoverSegments = sideCoverSegments.map((segment) {
      final oldLength = lengthFor(segment.side, oldWidth, oldHeight);
      final newLength = lengthFor(segment.side, newWidth, newHeight);
      if (oldLength <= 0 || newLength <= 0) return segment;

      final spansWholeSide =
          segment.startOffset.abs() <= 5.0 &&
          (isAtEdge(segment.endOffset, oldLength) ||
              segment.endOffset >= oldLength - 10.0);
      if (spansWholeSide) {
        return segment.copyWith(startOffset: 0.0, endOffset: newLength);
      }

      // Offset 0 is already fixed to the leading edge. Only values that were
      // anchored at the trailing edge should follow the resized frame.
      final start = isAtEdge(segment.startOffset, oldLength)
          ? newLength
          : segment.startOffset.clamp(0.0, newLength).toDouble();
      final end = isAtEdge(segment.endOffset, oldLength)
          ? newLength
          : segment.endOffset.clamp(0.0, newLength).toDouble();

      if (end <= start) {
        // If a shortened frame would otherwise cut the piece off completely,
        // retain its existing span at the new trailing edge instead of
        // silently turning a customised piece into a full-length cover.
        final preservedLength = math.min(segment.length, newLength);
        return segment.copyWith(
          startOffset: newLength - preservedLength,
          endOffset: newLength,
        );
      }
      return segment.copyWith(startOffset: start, endOffset: end);
    }).toList();
  }

  /// Returns the cover pieces that must be drawn or costed. Older saved
  /// drawings may contain one edited side only; their other sides are the
  /// legacy full surround unless the user has explicitly switched one off.
  List<SideCoverSegment> get effectiveSideCoverSegments {
    // A persisted/custom bottom cover is invalid as soon as the bottom frame
    // or the bottom wall is removed. Filter it here as a final drawing/BOM
    // safeguard as well as removing it at the state transition below.
    final storedSegments = sideCoverSegments
        .where(
          (segment) =>
              segment.side != 'bottom' || (hasBottomFrame && showBottomWall),
        )
        .toList();
    if (!useCustomSideCoverLayout) {
      return storedSegments;
    }

    final segments = storedSegments;
    const sides = ['top', 'left', 'right', 'bottom'];
    for (final side in sides) {
      if (side == 'bottom' && !canUseBottomSideCover) continue;
      if (hiddenSideCoverSegments.contains(side) ||
          removedShutterSides.contains(side) ||
          segments.any((segment) => segment.side == side)) {
        continue;
      }
      final length = sideCoverSideLength(side);
      if (length <= 0) continue;
      segments.add(
        SideCoverSegment(
          side: side,
          startOffset: 0.0,
          endOffset: length,
          visibleWidth: sideCoverWidth,
        ),
      );
    }
    return segments;
  }

  bool canSideUseSideCover(String side) {
    final normalized = side.toLowerCase();
    final frames = getFrameRects();
    if (frames.isEmpty) return true;
    final minLeft = frames.map((f) => f.left).reduce(math.min);
    final maxRight = frames.map((f) => f.right).reduce(math.max);
    final minTop = frames.map((f) => f.top).reduce(math.min);
    final maxBottom = frames.map((f) => f.bottom).reduce(math.max);
    // With several frames, one frame on the side taking a cover is enough:
    // the frames without one are dropped edge by edge.
    final multiFrame = frames.length > 1;
    var anyAllows = false;

    for (final frame in frames) {
      bool touchesSide = false;
      if (normalized == 'left' && (frame.left - minLeft).abs() <= 5.0)
        touchesSide = true;
      if (normalized == 'right' && (frame.right - maxRight).abs() <= 5.0)
        touchesSide = true;
      if (normalized == 'top' && (frame.top - minTop).abs() <= 5.0)
        touchesSide = true;
      if (normalized == 'bottom' && (frame.bottom - maxBottom).abs() <= 5.0)
        touchesSide = true;
      if (!touchesSide) continue;

      if (frameSideTakesSideCover(frame, normalized)) {
        anyAllows = true;
      } else if (!multiFrame) {
        return false;
      }
    }
    return !multiFrame || anyAllows;
  }

  bool isSideCoverSegmentEnabled(String side) {
    final normalized = side.toLowerCase();
    if (!canSideUseSideCover(normalized)) {
      return false;
    }
    if (!useCustomSideCoverLayout) {
      return !removedShutterSides.contains(normalized);
    }
    return effectiveSideCoverSegments.any(
      (segment) => segment.side == normalized,
    );
  }

  /// The old layout is a complete surround. When one side is customised for
  /// the first time, turn that surround into four explicit full-length pieces
  /// before replacing only the edited side. This keeps the other covers on
  /// screen instead of making them disappear.
  void _materializeLegacySideCoverSegments() {
    if (useCustomSideCoverLayout) return;

    const sides = ['top', 'left', 'right', 'bottom'];
    final segments = <SideCoverSegment>[];
    for (final side in sides) {
      if (!canSideUseSideCover(side)) continue;
      if (removedShutterSides.contains(side)) continue;
      final length = sideCoverSideLength(side);
      if (length <= 0) continue;
      segments.add(
        SideCoverSegment(
          side: side,
          startOffset: 0.0,
          endOffset: length,
          visibleWidth: sideCoverWidth,
        ),
      );
    }
    sideCoverSegments = segments;
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.clear();
  }

  /// A short press on a cover-side button only turns that side on or off.
  /// A long press opens the segment editor and does not change this state.
  void toggleSideCoverSegment(String side) {
    const allowedSides = {'left', 'right', 'top', 'bottom'};
    final normalized = side.toLowerCase();
    if (!allowedSides.contains(normalized)) return;
    if (!canSideUseSideCover(normalized)) {
      return;
    }

    _saveSnapshot();
    _materializeLegacySideCoverSegments();
    if (!isSideCoverSegmentEnabled(normalized)) {
      final length = sideCoverSideLength(normalized);
      if (length > 0) {
        hiddenSideCoverSegments.remove(normalized);
        sideCoverSegments = [
          ...sideCoverSegments,
          SideCoverSegment(
            side: normalized,
            startOffset: 0.0,
            endOffset: length,
            visibleWidth: sideCoverWidth,
          ),
        ];
        hasSideCovers = true;
      }
    } else {
      sideCoverSegments = sideCoverSegments
          .where((segment) => segment.side != normalized)
          .toList();
      hiddenSideCoverSegments.add(normalized);
    }
    _notifyModelListeners();
  }

  void saveSideCoverSegment(SideCoverSegment segment) {
    const allowedSides = {'left', 'right', 'top', 'bottom'};
    final side = segment.side.toLowerCase();
    if (!allowedSides.contains(side)) return;
    if (side == 'bottom' && !canUseBottomSideCover) return;

    final sideLength = sideCoverSideLength(side);
    if (sideLength <= 0) return;
    final start = segment.startOffset.clamp(0.0, sideLength).toDouble();
    final end = segment.endOffset.clamp(0.0, sideLength).toDouble();
    if (end <= start) return;

    _saveSnapshot();
    _materializeLegacySideCoverSegments();
    final normalized = segment.copyWith(
      side: side,
      startOffset: start,
      endOffset: end,
      // A side-specific cover may be narrower than the selected profile, but
      // it must never project farther than that profile's visible width.
      visibleWidth: segment.visibleWidth.clamp(0.0, sideCoverWidth).toDouble(),
    );
    sideCoverSegments = [
      ...sideCoverSegments.where((item) => item.side != side),
      normalized,
    ];
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.remove(side);
    hasSideCovers = true;
    _notifyModelListeners();
  }

  void removeSideCoverSegment(String side) {
    final normalized = side.toLowerCase();
    if (!sideCoverSegments.any((item) => item.side == normalized)) return;
    _saveSnapshot();
    sideCoverSegments = sideCoverSegments
        .where((item) => item.side != normalized)
        .toList();
    useCustomSideCoverLayout = true;
    hiddenSideCoverSegments.add(normalized);
    _notifyModelListeners();
  }

  FrameColor get frameColor => _frameColor;

  set frameColor(FrameColor color) {
    _frameColor = color;
    for (var z in zones) {
      z.sashColor = color;
    }
    _notifyModelListeners();
  }

  Map<String, dynamic>? _defaultFrameColor() {
    for (final color in availableColors) {
      if (_isWhiteProfileColor(color)) {
        return color;
      }
    }
    // A missing white price configuration must never make a new drawing look
    // grey merely because grey happens to be the first database row.  The
    // enum default stays white until the workshop configures a white color.
    return null;
  }

  void toggleCopyPreviousFrameSize() {
    copyPreviousFrameSize = !copyPreviousFrameSize;
    _notifyModelListeners();
  }

  String _frameSelectionKey(int index) => 'frame:$index';

  int? _frameIndexFromSelectionKey(String? key) {
    if (key == null || !key.startsWith('frame:')) return null;
    final index = int.tryParse(key.substring('frame:'.length));
    final frameCount = getFrameRects().length;
    if (index == null || index < 0 || index >= frameCount) return null;
    return index;
  }

  int? _frameIndexForSelection(String? key) {
    if (key == null) return null;
    final index = _frameIndexFromSelectionKey(key);
    if (index != null) return index;
    return _frameIndexContainingZone(key);
  }

  /// Whether the head is slanted or arched, or the bottom slanted.
  bool get hasShapedOutline =>
      archHeight != 0 ||
      topSlantLeftY != 0 ||
      topSlantRightY != 0 ||
      bottomSlantLeftY != 0 ||
      bottomSlantRightY != 0;

  /// The real outline of the window, [inset] mm inside its outer edge:
  /// slanted or arched head and slanted bottom, in drawing coordinates (an
  /// arch can rise above y = 0).
  Path windowOutlinePath({double inset = 0}) {
    final right = width - inset;
    if (hasCornerNotches && !hasShapedOutline) {
      return cornerNotches.outlinePath(width, height, inset: inset);
    }
    if (!hasShapedOutline) {
      return Path()..addRect(Rect.fromLTRB(inset, inset, right, height - inset));
    }
    final path = Path()..moveTo(inset, headEdgeY(inset, inset));
    final arc = headArc();
    final headRight = Offset(right, headEdgeY(right, inset));
    if (arc == null) {
      path.lineTo(headRight.dx, headRight.dy);
    } else {
      path.arcToPoint(
        headRight,
        radius: Radius.circular(math.max(1.0, arc.radius - inset)),
      );
    }
    return path
      ..lineTo(right, height - bottomSlantRightY - inset)
      ..lineTo(inset, height - bottomSlantLeftY - inset)
      ..close();
  }

  /// [rect] cut to the window [outline]. A rect touching the top (or the
  /// bottom) of [edges] is first stretched to the outline, so the part of a
  /// slanted or arched head above it is included, not only its rectangle.
  Path _shapedSelectionPath(Rect rect, Path outline, Rect edges) {
    final bounds = outline.getBounds();
    final stretched = Rect.fromLTRB(
      rect.left,
      rect.top <= edges.top + 0.5 ? math.min(rect.top, bounds.top) : rect.top,
      rect.right,
      rect.bottom >= edges.bottom - 0.5
          ? math.max(rect.bottom, bounds.bottom)
          : rect.bottom,
    );
    return Path.combine(
      PathOperation.intersect,
      outline,
      Path()..addRect(stretched),
    );
  }

  /// Outline of the selected frame [rect] (see [frameRectForSelection]),
  /// following a slanted or arched head and a slanted bottom.
  Path frameSelectionPath(Rect rect) {
    if (hasCornerNotches && !hasShapedOutline) {
      return Path.combine(
        PathOperation.intersect,
        windowOutlinePath(),
        Path()..addRect(rect),
      );
    }
    if (!hasShapedOutline) return Path()..addRect(rect);
    final frames = getFrameRects();
    final edges = frames.isEmpty
        ? Rect.fromLTWH(0, 0, width, height)
        : frames.reduce((a, b) => a.expandToInclude(b));
    return _shapedSelectionPath(rect, windowOutlinePath(), edges);
  }

  /// Highlight of a selected sash or glass [rect], following the inner edge
  /// of a slanted or arched head and of a slanted bottom.
  Path zoneSelectionPath(Rect rect) {
    if (!hasShapedOutline || zones.isEmpty) return Path()..addRect(rect);
    final edges = zones
        .map((zone) => zone.boundary)
        .reduce((a, b) => a.expandToInclude(b));
    return _shapedSelectionPath(
      rect,
      windowOutlinePath(inset: profileThickness),
      edges,
    );
  }

  Rect? frameRectForSelection(String? key) {
    final index =
        _frameIndexForSelection(key) ??
        (getFrameRects().length == 1 ? 0 : null);
    if (index == null) return null;
    final rects = getFrameRects();
    return index < rects.length ? rects[index] : null;
  }

  int? _frameIndexContainingZone(String zoneId) {
    final groups = _frameZoneGroups();
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].any((zone) => zone.id == zoneId)) {
        return index;
      }
    }
    return null;
  }

  Rect? frameRectForZone(String zoneId) {
    final index = _frameIndexContainingZone(zoneId);
    if (index == null) return null;
    final rects = getFrameRects();
    return index < rects.length ? rects[index] : null;
  }

  void resizeFrameOuterDimensionForZone(
    String zoneId, {
    required bool isWidth,
    required double outerSize,
  }) {
    final index = _frameIndexContainingZone(zoneId);
    if (index == null) return;
    final rects = getFrameRects();
    if (index >= rects.length) return;
    final current = rects[index];
    final limits = frameOuterLimits(zoneId, isWidth: isWidth);
    final clampedSize = outerSize.clamp(limits.min, limits.max);
    final delta = clampedSize - (isWidth ? current.width : current.height);
    if (delta.abs() < 0.001) return;
    final before = List<Rect>.of(rects);
    resizeFrameFromHandles(
      _frameSelectionKey(index),
      moveLeft: false,
      moveRight: isWidth,
      moveTop: false,
      moveBottom: !isWidth,
      deltaX: isWidth ? delta : 0.0,
      deltaY: isWidth ? 0.0 : delta,
    );
    _keepStackedFramesAligned(before, isWidth: isWidth);
  }

  /// After a typed frame dimension: frames beside the resized one have
  /// already moved (never shrunk). A frame stacked against a frame that
  /// moved or changed, whose outer edge was aligned with the edge that
  /// moved, follows that edge when it slides or grows, so the assembly
  /// keeps its outline. It never shrinks: making one frame smaller changes
  /// no other frame's size.
  void _keepStackedFramesAligned(List<Rect> before, {required bool isWidth}) {
    const tolerance = 3.0;
    double lo(Rect r) => isWidth ? r.left : r.top;
    double hi(Rect r) => isWidth ? r.right : r.bottom;
    bool stacked(Rect a, Rect b) {
      // Touching across the other axis and overlapping along this one.
      final touch = isWidth
          ? (a.bottom - b.top).abs() <= tolerance ||
                (b.bottom - a.top).abs() <= tolerance
          : (a.right - b.left).abs() <= tolerance ||
                (b.right - a.left).abs() <= tolerance;
      final overlap = isWidth
          ? math.min(a.right, b.right) - math.max(a.left, b.left)
          : math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
      return touch && overlap > 2.0;
    }

    final handled = <int>{};
    for (var pass = 0; pass < before.length; pass++) {
      final after = getFrameRects();
      if (after.length != before.length) return;
      final moves = <({double from, double to})>[];
      final moved = <int>{};
      for (var i = 0; i < before.length; i++) {
        final dLo = lo(after[i]) - lo(before[i]);
        final dHi = hi(after[i]) - hi(before[i]);
        if (dLo.abs() > 0.5) moves.add((from: lo(before[i]), to: lo(after[i])));
        if (dHi.abs() > 0.5) moves.add((from: hi(before[i]), to: hi(after[i])));
        if (dLo.abs() > 0.5 || dHi.abs() > 0.5) moved.add(i);
      }
      double follow(double edge) {
        for (final m in moves) {
          if ((m.from - edge).abs() <= tolerance) return m.to;
        }
        return edge;
      }

      var changed = false;
      for (var i = 0; i < before.length; i++) {
        if (moved.contains(i) || handled.contains(i)) continue;
        final rect = before[i];
        if (!moved.any((j) => stacked(before[j], rect))) continue;
        final dLo = follow(lo(rect)) - lo(rect);
        final dHi = follow(hi(rect)) - hi(rect);
        if (dLo.abs() <= 0.5 && dHi.abs() <= 0.5) continue;
        // The user's rule: another frame may slide or grow with its
        // neighbours, but is never made smaller, even if the outline then
        // stops being a rectangle.
        if (dHi - dLo < -0.5) continue;
        handled.add(i);
        changed = true;
        if ((dLo - dHi).abs() <= 0.5) {
          // Both edges follow: the frame slides with its neighbours.
          for (final zone in _frameZoneGroups()[i]) {
            zone.boundary = zone.boundary.shift(
              isWidth ? Offset(dLo, 0) : Offset(0, dLo),
            );
          }
          continue;
        }
        if (dHi.abs() > 0.5) {
          _resizePhysicalFrameFromHandles(
            i,
            moveLeft: false,
            moveRight: isWidth,
            moveTop: false,
            moveBottom: !isWidth,
            deltaX: isWidth ? dHi : 0.0,
            deltaY: isWidth ? 0.0 : dHi,
            saveHistory: false,
          );
        }
        if (dLo.abs() > 0.5) {
          _resizePhysicalFrameFromHandles(
            i,
            moveLeft: isWidth,
            moveRight: false,
            moveTop: !isWidth,
            moveBottom: false,
            deltaX: isWidth ? dLo : 0.0,
            deltaY: isWidth ? 0.0 : dLo,
            saveHistory: false,
          );
        }
      }
      if (!changed) break;
    }
    _updateOuterSizeFromFrames();
    _notifyModelListeners();
  }

  /// Which frames of a coupled drawing carry their own dimension, per side:
  /// the frames along the top/bottom outline (widths) and the left/right
  /// outline (heights). A side is left empty when it would only repeat the
  /// overall dimension or the opposite side. Frames on neither side of an
  /// axis (a middle row or column) are listed in innerWidths/innerHeights.
  ({
    List<PhysicalFrameInfo> top,
    List<PhysicalFrameInfo> bottom,
    List<PhysicalFrameInfo> left,
    List<PhysicalFrameInfo> right,
    List<PhysicalFrameInfo> innerWidths,
    List<PhysicalFrameInfo> innerHeights,
  })
  frameDimensionChains() {
    const tolerance = 3.0;
    final frames = getPhysicalFrameInfos();
    if (frames.length < 2) {
      return (
        top: const [],
        bottom: const [],
        left: const [],
        right: const [],
        innerWidths: const [],
        innerHeights: const [],
      );
    }
    final minL = frames.map((f) => f.rect.left).reduce(math.min);
    final maxR = frames.map((f) => f.rect.right).reduce(math.max);
    final minT = frames.map((f) => f.rect.top).reduce(math.min);
    final maxB = frames.map((f) => f.rect.bottom).reduce(math.max);
    bool near(double a, double b) => (a - b).abs() <= tolerance;
    bool fullWidth(PhysicalFrameInfo f) =>
        near(f.rect.left, minL) && near(f.rect.right, maxR);
    bool fullHeight(PhysicalFrameInfo f) =>
        near(f.rect.top, minT) && near(f.rect.bottom, maxB);

    List<PhysicalFrameInfo> along(
      bool Function(PhysicalFrameInfo) onSide,
      double Function(PhysicalFrameInfo) order,
    ) => frames.where(onSide).toList()
      ..sort((a, b) => order(a).compareTo(order(b)));

    var top = along((f) => near(f.rect.top, minT), (f) => f.rect.left);
    var bottom = along((f) => near(f.rect.bottom, maxB), (f) => f.rect.left);
    var left = along((f) => near(f.rect.left, minL), (f) => f.rect.top);
    var right = along((f) => near(f.rect.right, maxR), (f) => f.rect.top);
    final topIds = top.map((f) => f.index).toSet();
    final bottomIds = bottom.map((f) => f.index).toSet();
    final leftIds = left.map((f) => f.index).toSet();
    final rightIds = right.map((f) => f.index).toSet();

    // A lone frame spanning the whole side is the overall dimension; a
    // frame already measured on the opposite side is not repeated.
    if (top.length == 1 && fullWidth(top.first)) top = [];
    if (bottom.length == 1 && fullWidth(bottom.first)) bottom = [];
    final shownTop = top.map((f) => f.index).toSet();
    bottom = [
      for (final f in bottom)
        if (!shownTop.contains(f.index)) f,
    ];
    if (left.length == 1 && fullHeight(left.first)) left = [];
    if (right.length == 1 && fullHeight(right.first)) right = [];
    final shownLeft = left.map((f) => f.index).toSet();
    right = [
      for (final f in right)
        if (!shownLeft.contains(f.index)) f,
    ];

    return (
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      innerWidths: [
        for (final f in frames)
          if (!topIds.contains(f.index) &&
              !bottomIds.contains(f.index) &&
              !fullWidth(f))
            f,
      ],
      innerHeights: [
        for (final f in frames)
          if (!leftIds.contains(f.index) &&
              !rightIds.contains(f.index) &&
              !fullHeight(f))
            f,
      ],
    );
  }

  void _updateOuterSizeFromFrames() {
    final rects = getFrameRects();
    if (rects.isEmpty) return;
    width = rects.map((r) => r.right).reduce(math.max);
    height = rects.map((r) => r.bottom).reduce(math.max);
  }

  /// Selects one physical outer frame in a coupled drawing. A divided single
  /// frame remains one selectable frame; its inner zones do not expose resize
  /// handles independently.
  void selectFrameByIndex(int index) {
    final frameCount = getFrameRects().length;
    if (index < 0 || index >= frameCount) return;
    selection = SelectionInfo(
      type: SelectionType.frame,
      zoneId: _frameSelectionKey(index),
    );
    // A newly selected frame shows its resize squares first.
    frameShapeMode = false;
    showZoneMenu = false;
    activeSubZone = null;
    _notifySelectionChanged();
  }

  void selectFrame(String zoneId) {
    if (zoneId.startsWith('frame:')) {
      final index = _frameIndexFromSelectionKey(zoneId);
      if (index == null) return;
      selectFrameByIndex(index);
      return;
    }

    final groups = _frameZoneGroups();
    for (var index = 0; index < groups.length; index++) {
      if (groups[index].any((zone) => zone.id == zoneId)) {
        selectFrameByIndex(index);
        return;
      }
    }
  }

  /// Fixed, empty and sliding content all require a real lower frame. Older
  /// drawings can arrive here after the lower frame was removed for a
  /// sash/plinthe, so changing only the zone content leaves the new content
  /// at the old open-bottom height. Restore the structural state as one
  /// atomic transition.
  ///
  /// In a multi-frame drawing this is kept local to the physical frame that
  /// owns [zone].  In a single-frame drawing the lower-frame/plinthe state is
  /// global by design and all opening plinth flags are cleared together.
  void _restoreBottomFrameForContent(WindowZone zone) {
    final frames = getFrameRects();
    Rect? owner;
    for (final frame in frames) {
      if (frame.contains(zone.boundary.center)) {
        owner = frame;
        break;
      }
    }

    if (frames.length > 1 && owner != null) {
      // The local override is attached to every zone in this physical frame
      // so a later resize or serialisation cannot partially restore it.
      for (final candidate in zones) {
        if (owner.contains(candidate.boundary.center)) {
          componentOverrides['frame-bottom:${candidate.id}'] = true;
          candidate.hasSashPlintheBottom = false;
        }
      }
    } else {
      hasBottomFrame = true;
      hasFramePlintheBottom = false;
      for (final candidate in zones) {
        candidate.hasSashPlintheBottom = false;
        componentOverrides.remove('frame-bottom:${candidate.id}');
      }
    }

    showBottomWall = true;
    // These two sets may contain stale entries created when the lower frame
    // was absent.  Returning to a fixed pane must behave like restoring the
    // original drawing, including its bottom cover and 45-degree corners.
    _restoreBottomSideCoverWhenFrameReturns();
    updateBottomZoneBoundaries();
  }

  /// Resizes the selected outer frame from the supplied handles. Physical
  /// neighbour frames that touch the moved side are translated with it so the
  /// drawing behaves like a snapped frame grid instead of leaving gaps.
  void resizeFrameFromHandles(
    String frameSelectionId, {
    required bool moveLeft,
    required bool moveRight,
    required bool moveTop,
    required bool moveBottom,
    required double deltaX,
    required double deltaY,
    bool saveHistory = true,
  }) {
    final frameIndex =
        _frameIndexForSelection(frameSelectionId) ??
        (getFrameRects().length == 1 ? 0 : null);
    if (frameIndex != null) {
      _resizePhysicalFrameFromHandles(
        frameIndex,
        moveLeft: moveLeft,
        moveRight: moveRight,
        moveTop: moveTop,
        moveBottom: moveBottom,
        deltaX: deltaX,
        deltaY: deltaY,
        saveHistory: saveHistory,
      );
      return;
    }

    final zoneIndex = zones.indexWhere((zone) => zone.id == frameSelectionId);
    if (zoneIndex == -1) return;
    if (saveHistory) _saveSnapshot();
    final oldWidth = width;
    final oldHeight = height;

    const minInnerSize = 50.0;

    final current = zones[zoneIndex].boundary;
    double left = current.left;
    double top = current.top;
    double right = current.right;
    double bottom = current.bottom;
    final minLeft = profileThickness;
    final minTop = profileThickness;
    double clampDouble(double value, double minimum, double maximum) {
      if (maximum < minimum) return minimum;
      return value.clamp(minimum, maximum).toDouble();
    }

    if (moveLeft) {
      left = clampDouble(
        left + deltaX,
        math.max(minLeft, right - maximumFrameBarLengthMm),
        right - minInnerSize,
      );
    }
    if (moveRight) {
      right = clampDouble(
        right + deltaX,
        left + minInnerSize,
        left + maximumFrameBarLengthMm,
      );
    }
    if (moveTop) {
      top = clampDouble(
        top + deltaY,
        math.max(minTop, bottom - maximumFrameBarLengthMm),
        bottom - minInnerSize,
      );
    }
    if (moveBottom) {
      bottom = clampDouble(
        bottom + deltaY,
        top + minInnerSize,
        top + maximumFrameBarLengthMm,
      );
    }

    final next = Rect.fromLTRB(left, top, right, bottom);
    if ((next.left - current.left).abs() < 0.001 &&
        (next.top - current.top).abs() < 0.001 &&
        (next.right - current.right).abs() < 0.001 &&
        (next.bottom - current.bottom).abs() < 0.001) {
      return;
    }

    zones[zoneIndex].boundary = next;
    if (moveLeft || moveRight) {
      double nextWidth = 200.0;
      for (final zone in zones) {
        nextWidth = math.max(nextWidth, zone.boundary.right + profileThickness);
      }
      width = math.min(maximumFrameBarLengthMm, nextWidth);
    }
    if (moveTop || moveBottom) {
      double nextHeight = 200.0;
      for (final zone in zones) {
        nextHeight = math.max(
          nextHeight,
          zone.boundary.bottom + (hasBottomFrame ? profileThickness : 0.0),
        );
      }
      height = math.min(maximumFrameBarLengthMm, nextHeight);
    }
    _resizeSideCoverSegments(oldWidth, oldHeight, width, height);
    synchronizeShutterAfterFrameResize(oldWidth, oldHeight);
    _notifyModelListeners();
  }

  /// Snaps a physical frame edge to the outside edge of the next touching
  /// frame when the dragged edge is within 20 mm. This lets an upper frame
  /// grow from one lower frame to two, three, or more frames smoothly without
  /// sudden large jumps.
  double _snapPhysicalFrameEdge({
    required int frameIndex,
    required Rect current,
    required List<Rect> rects,
    required String side,
    required double proposed,
  }) {
    const threshold = 20.0;

    // Snapping is for extension toward a neighbouring frame. It must not
    // pull an edge back when the user is deliberately reducing its size.
    if ((side == 'right' && proposed <= current.right) ||
        (side == 'left' && proposed >= current.left) ||
        (side == 'bottom' && proposed <= current.bottom) ||
        (side == 'top' && proposed >= current.top)) {
      return proposed;
    }

    bool overlap(
      double firstStart,
      double firstEnd,
      double secondStart,
      double secondEnd,
    ) {
      return math.min(firstEnd, secondEnd) - math.max(firstStart, secondStart) >
          2.0;
    }

    bool nearPerpendicularEdge(Rect candidate) {
      if (side == 'left' || side == 'right') {
        return overlap(
              current.top,
              current.bottom,
              candidate.top,
              candidate.bottom,
            ) ||
            (candidate.top - current.bottom).abs() <= threshold ||
            (candidate.bottom - current.top).abs() <= threshold;
      }
      return overlap(
            current.left,
            current.right,
            candidate.left,
            candidate.right,
          ) ||
          (candidate.left - current.right).abs() <= threshold ||
          (candidate.right - current.left).abs() <= threshold;
    }

    double? best;
    var bestDistance = threshold + 0.001;
    for (var index = 0; index < rects.length; index++) {
      if (index == frameIndex) continue;
      final candidate = rects[index];
      if (!nearPerpendicularEdge(candidate)) continue;

      double? target;
      switch (side) {
        case 'right':
          if (candidate.right <= current.right + 2.0 ||
              candidate.left > proposed + threshold) {
            continue;
          }
          target = candidate.right;
          break;
        case 'left':
          if (candidate.left >= current.left - 2.0 ||
              candidate.right < proposed - threshold) {
            continue;
          }
          target = candidate.left;
          break;
        case 'bottom':
          if (candidate.bottom <= current.bottom + 2.0 ||
              candidate.top > proposed + threshold) {
            continue;
          }
          target = candidate.bottom;
          break;
        case 'top':
          if (candidate.top >= current.top - 2.0 ||
              candidate.bottom < proposed - threshold) {
            continue;
          }
          target = candidate.top;
          break;
      }
      if (target == null) continue;
      final distance = (target - proposed).abs();
      if (distance <= threshold && distance < bestDistance) {
        best = target;
        bestDistance = distance;
      }
    }
    return best ?? proposed;
  }

  void _resizePhysicalFrameFromHandles(
    int frameIndex, {
    required bool moveLeft,
    required bool moveRight,
    required bool moveTop,
    required bool moveBottom,
    required double deltaX,
    required double deltaY,
    bool saveHistory = true,
  }) {
    final groups = _frameZoneGroups();
    final rects = getFrameRects();
    if (frameIndex < 0 ||
        frameIndex >= groups.length ||
        frameIndex >= rects.length) {
      return;
    }
    final group = groups[frameIndex];
    if (group.isEmpty) return;
    if (saveHistory) _saveSnapshot();

    final oldWidth = width;
    final oldHeight = height;
    const minInnerSize = 50.0;

    final currentOuter = rects[frameIndex];
    double left = currentOuter.left;
    double top = currentOuter.top;
    double right = currentOuter.right;
    double bottom = currentOuter.bottom;

    double clampDouble(double value, double minimum, double maximum) {
      if (maximum < minimum) return minimum;
      return value.clamp(minimum, maximum).toDouble();
    }

    // 380 mm per side (250 mm beside a side of one metre or more); a legacy
    // frame already smaller keeps its size instead of jumping.
    final minFrameW = math.max(
      minInnerSize + (2 * profileThickness),
      math.min(
        minimumFrameSideFor(currentOuter.height),
        currentOuter.width,
      ),
    );
    final minFrameH = math.max(
      minInnerSize + (2 * profileThickness),
      math.min(
        minimumFrameSideFor(currentOuter.width),
        currentOuter.height,
      ),
    );
    if (moveLeft) {
      left = clampDouble(
        left + deltaX,
        right - maximumFrameBarLengthMm,
        right - minFrameW,
      );
    }
    if (moveRight) {
      right = clampDouble(
        right + deltaX,
        left + minFrameW,
        left + maximumFrameBarLengthMm,
      );
    }
    if (moveTop) {
      top = clampDouble(
        top + deltaY,
        bottom - maximumFrameBarLengthMm,
        bottom - minFrameH,
      );
    }
    if (moveBottom) {
      bottom = clampDouble(
        bottom + deltaY,
        top + minFrameH,
        top + maximumFrameBarLengthMm,
      );
    }

    // Magnetic extension: when a frame edge approaches the next physical
    // frame, lock it to that frame's outside edge within 100 mm.
    if (moveRight) {
      right = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'right',
        proposed: right,
      );
    }
    if (moveLeft) {
      left = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'left',
        proposed: left,
      );
    }
    if (moveBottom) {
      bottom = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'bottom',
        proposed: bottom,
      );
    }
    if (moveTop) {
      top = _snapPhysicalFrameEdge(
        frameIndex: frameIndex,
        current: currentOuter,
        rects: rects,
        side: 'top',
        proposed: top,
      );
    }

    bool overlapsRange(
      double firstStart,
      double firstEnd,
      double secondStart,
      double secondEnd,
    ) {
      return math.max(firstStart, secondStart) <
          math.min(firstEnd, secondEnd) - 2.0;
    }

    final nextOuter = Rect.fromLTRB(left, top, right, bottom);
    if ((nextOuter.left - currentOuter.left).abs() < 0.001 &&
        (nextOuter.top - currentOuter.top).abs() < 0.001 &&
        (nextOuter.right - currentOuter.right).abs() < 0.001 &&
        (nextOuter.bottom - currentOuter.bottom).abs() < 0.001) {
      return;
    }

    final currentInner = currentOuter.deflate(profileThickness);
    final nextInner = nextOuter.deflate(profileThickness);

    if (group.length == 1) {
      group.first.boundary = nextInner;
    } else {
      // 1. Identify all vertical mullion intervals within group
      final rawMullionXIntervals = <List<double>>[];
      for (var i = 0; i < group.length; i++) {
        for (var j = 0; j < group.length; j++) {
          if (i == j) continue;
          final za = group[i].boundary;
          final zb = group[j].boundary;
          if (za.right <= zb.left + 0.1) {
            final gap = zb.left - za.right;
            final vOverlap =
                math.min(za.bottom, zb.bottom) - math.max(za.top, zb.top);
            if (gap >= 0.0 &&
                gap <= maximumMullionThickness + 12.0 &&
                vOverlap > 2.0) {
              rawMullionXIntervals.add([za.right, zb.left]);
            }
          }
        }
      }
      rawMullionXIntervals.sort((a, b) => a[0].compareTo(b[0]));
      final mergedMullionX = <List<double>>[];
      for (final interval in rawMullionXIntervals) {
        if (mergedMullionX.isEmpty) {
          mergedMullionX.add(List<double>.from(interval));
        } else {
          final last = mergedMullionX.last;
          if (interval[0] <= last[1] + 2.0) {
            last[1] = math.max(last[1], interval[1]);
          } else {
            mergedMullionX.add(List<double>.from(interval));
          }
        }
      }

      // 2. Identify all horizontal mullion intervals within group
      final rawMullionYIntervals = <List<double>>[];
      for (var i = 0; i < group.length; i++) {
        for (var j = 0; j < group.length; j++) {
          if (i == j) continue;
          final za = group[i].boundary;
          final zb = group[j].boundary;
          if (za.bottom <= zb.top + 0.1) {
            final gap = zb.top - za.bottom;
            final hOverlap =
                math.min(za.right, zb.right) - math.max(za.left, zb.left);
            if (gap >= 0.0 &&
                gap <= maximumMullionThickness + 12.0 &&
                hOverlap > 2.0) {
              rawMullionYIntervals.add([za.bottom, zb.top]);
            }
          }
        }
      }
      rawMullionYIntervals.sort((a, b) => a[0].compareTo(b[0]));
      final mergedMullionY = <List<double>>[];
      for (final interval in rawMullionYIntervals) {
        if (mergedMullionY.isEmpty) {
          mergedMullionY.add(List<double>.from(interval));
        } else {
          final last = mergedMullionY.last;
          if (interval[0] <= last[1] + 2.0) {
            last[1] = math.max(last[1], interval[1]);
          } else {
            mergedMullionY.add(List<double>.from(interval));
          }
        }
      }

      double totalMullionW = 0.0;
      for (final m in mergedMullionX) {
        totalMullionW += (m[1] - m[0]);
      }
      final totalGlassOldW = currentInner.width - totalMullionW;
      final totalGlassNewW = nextInner.width - totalMullionW;
      final glassScaleX = (totalGlassOldW > 1.0 && totalGlassNewW > 1.0)
          ? totalGlassNewW / totalGlassOldW
          : (currentInner.width > 1.0
                ? nextInner.width / currentInner.width
                : 1.0);

      double mapX(double x) {
        if (totalGlassOldW <= 1.0 || totalGlassNewW <= 1.0) {
          return nextInner.left +
              (x - currentInner.left) *
                  (nextInner.width / math.max(1.0, currentInner.width));
        }
        double mullionBeforeX = 0.0;
        for (final m in mergedMullionX) {
          if (x <= m[0]) {
            // before this mullion
          } else if (x >= m[1]) {
            mullionBeforeX += (m[1] - m[0]);
          } else {
            mullionBeforeX += (x - m[0]);
          }
        }
        final glassBeforeX = (x - currentInner.left) - mullionBeforeX;
        return nextInner.left + (glassBeforeX * glassScaleX) + mullionBeforeX;
      }

      double totalMullionH = 0.0;
      for (final m in mergedMullionY) {
        totalMullionH += (m[1] - m[0]);
      }
      final totalGlassOldH = currentInner.height - totalMullionH;
      final totalGlassNewH = nextInner.height - totalMullionH;
      final glassScaleY = (totalGlassOldH > 1.0 && totalGlassNewH > 1.0)
          ? totalGlassNewH / totalGlassOldH
          : (currentInner.height > 1.0
                ? nextInner.height / currentInner.height
                : 1.0);

      double mapY(double y) {
        if (totalGlassOldH <= 1.0 || totalGlassNewH <= 1.0) {
          return nextInner.top +
              (y - currentInner.top) *
                  (nextInner.height / math.max(1.0, currentInner.height));
        }
        double mullionBeforeY = 0.0;
        for (final m in mergedMullionY) {
          if (y <= m[0]) {
            // before this mullion
          } else if (y >= m[1]) {
            mullionBeforeY += (m[1] - m[0]);
          } else {
            mullionBeforeY += (y - m[0]);
          }
        }
        final glassBeforeY = (y - currentInner.top) - mullionBeforeY;
        return nextInner.top + (glassBeforeY * glassScaleY) + mullionBeforeY;
      }

      for (final m in mergedMullionX) {
        final oldMid = (m[0] + m[1]) / 2.0;
        final newMid = (mapX(m[0]) + mapX(m[1])) / 2.0;
        _moveMullionMetadata(
          _mullionKey(false, oldMid),
          _mullionKey(false, newMid),
        );
      }
      for (final m in mergedMullionY) {
        final oldMid = (m[0] + m[1]) / 2.0;
        final newMid = (mapY(m[0]) + mapY(m[1])) / 2.0;
        _moveMullionMetadata(
          _mullionKey(true, oldMid),
          _mullionKey(true, newMid),
        );
      }

      if (selection.type == SelectionType.mullion &&
          selection.mullionPosition != null) {
        if (selection.isHorizontalMullion == false) {
          selection = SelectionInfo(
            type: SelectionType.mullion,
            isHorizontalMullion: false,
            mullionPosition: mapX(selection.mullionPosition!),
            mullionStart: selection.mullionStart != null
                ? mapY(selection.mullionStart!)
                : null,
            mullionEnd: selection.mullionEnd != null
                ? mapY(selection.mullionEnd!)
                : null,
          );
        } else {
          selection = SelectionInfo(
            type: SelectionType.mullion,
            isHorizontalMullion: true,
            mullionPosition: mapY(selection.mullionPosition!),
            mullionStart: selection.mullionStart != null
                ? mapX(selection.mullionStart!)
                : null,
            mullionEnd: selection.mullionEnd != null
                ? mapX(selection.mullionEnd!)
                : null,
          );
        }
      }

      for (final zone in group) {
        final r = zone.boundary;
        zone.boundary = Rect.fromLTRB(
          mapX(r.left),
          mapY(r.top),
          mapX(r.right),
          mapY(r.bottom),
        );
      }
    }

    Set<int> affectedFrameChain({
      required String side,
      required Rect movedRect,
    }) {
      const touchTolerance = 3.0;
      final affected = <int>{};
      final queue = <int>[];

      bool touches(Rect source, Rect candidate) {
        switch (side) {
          case 'right':
            return (candidate.left - source.right).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.top,
                  movedRect.bottom,
                  candidate.top,
                  candidate.bottom,
                );
          case 'left':
            return (candidate.right - source.left).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.top,
                  movedRect.bottom,
                  candidate.top,
                  candidate.bottom,
                );
          case 'bottom':
            return (candidate.top - source.bottom).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.left,
                  movedRect.right,
                  candidate.left,
                  candidate.right,
                );
          case 'top':
            return (candidate.bottom - source.top).abs() <= touchTolerance &&
                overlapsRange(
                  movedRect.left,
                  movedRect.right,
                  candidate.left,
                  candidate.right,
                );
        }
        return false;
      }

      void enqueueTouching(Rect source) {
        for (var i = 0; i < rects.length; i++) {
          if (i == frameIndex || affected.contains(i)) continue;
          if (!touches(source, rects[i])) continue;
          affected.add(i);
          queue.add(i);
        }
      }

      enqueueTouching(currentOuter);
      while (queue.isNotEmpty) {
        final currentIndex = queue.removeAt(0);
        enqueueTouching(rects[currentIndex]);
      }
      return affected;
    }

    void translateFrameGroups(Set<int> frameIndices, double dx, double dy) {
      if (frameIndices.isEmpty || (dx == 0 && dy == 0)) return;
      for (final index in frameIndices) {
        if (index < 0 || index >= groups.length) continue;
        for (final zone in groups[index]) {
          zone.boundary = zone.boundary.shift(Offset(dx, dy));
        }
      }
    }

    final deltaLeft = nextOuter.left - currentOuter.left;
    final deltaRight = nextOuter.right - currentOuter.right;
    final deltaTop = nextOuter.top - currentOuter.top;
    final deltaBottom = nextOuter.bottom - currentOuter.bottom;

    if (moveLeft && deltaLeft.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'left', movedRect: currentOuter),
        deltaLeft,
        0.0,
      );
    }
    if (moveRight && deltaRight.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'right', movedRect: currentOuter),
        deltaRight,
        0.0,
      );
    }
    if (moveTop && deltaTop.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'top', movedRect: currentOuter),
        0.0,
        deltaTop,
      );
    }
    if (moveBottom && deltaBottom.abs() > 0.001) {
      translateFrameGroups(
        affectedFrameChain(side: 'bottom', movedRect: currentOuter),
        0.0,
        deltaBottom,
      );
    }

    // The model coordinate system starts at the outside top-left corner of
    // the complete drawing. Resizing from the left/top used to leave the
    // drawing at a negative coordinate (when growing) or leave an empty
    // offset (when shrinking). Width/height are derived from right/bottom,
    // so that asymmetry distorted the drawing. Re-anchor the whole assembly
    // and move coordinate-based mullion metadata by the same offset.
    final resizedRects = getFrameRects();
    if (resizedRects.isNotEmpty) {
      final minLeft = resizedRects.map((rect) => rect.left).reduce(math.min);
      final minTop = resizedRects.map((rect) => rect.top).reduce(math.min);
      final shiftX = (moveLeft || moveRight) && minLeft.abs() > 0.001
          ? -minLeft
          : 0.0;
      final shiftY = (moveTop || moveBottom) && minTop.abs() > 0.001
          ? -minTop
          : 0.0;
      lastResizeAnchorShift = Offset(shiftX, shiftY);
      if (shiftX != 0.0 || shiftY != 0.0) {
        for (final zone in zones) {
          zone.boundary = zone.boundary.shift(Offset(shiftX, shiftY));
        }
        _shiftMullionMetadata(shiftX, shiftY);
      }
    }

    if (moveLeft || moveRight) {
      double nextWidth = 200.0;
      for (final zone in zones) {
        nextWidth = math.max(nextWidth, zone.boundary.right + profileThickness);
      }
      width = math.min(maximumFrameBarLengthMm, nextWidth);
    }
    if (moveTop || moveBottom) {
      double nextHeight = 200.0;
      for (final zone in zones) {
        nextHeight = math.max(
          nextHeight,
          zone.boundary.bottom + (hasBottomFrame ? profileThickness : 0.0),
        );
      }
      height = math.min(maximumFrameBarLengthMm, nextHeight);
    }
    _resizeSideCoverSegments(oldWidth, oldHeight, width, height);
    synchronizeShutterAfterFrameResize(oldWidth, oldHeight);
    _notifyModelListeners();
  }

  bool get canDisableBottomFrame {
    if (systemMode == 'sliding') return false;
    if (usesSeuil) return true;
    if (hasFramePlintheBottom || zones.any((z) => z.hasSashPlintheBottom)) {
      return true;
    }
    return true;
  }

  bool usesFrameRole(String role, {required bool sliding}) {
    if (getConfiguredSectionForRole(role, useSlidingSeries: sliding) == null)
      return false;
    if (role == 'cache_rail') return sliding && useOptionalCacheRail;
    if (isConfiguredRoleRequired(role, useSlidingSeries: sliding)) return true;
    return role == 'seuil'
        ? useOptionalSeuil
        : role == 'cache_dormant'
        ? useOptionalCacheDormant
        // Cache-rainure is never a drawing option: assigning it to a series
        // means it is always installed at a compatible frame-to-frame joint.
        : role == 'cache_rainure'
        ? true
        : role == 'profile_angle'
        ? usesProfileAngle
        : false;
  }

  bool hasFrameRole(String role) =>
      getConfiguredSectionForRole(role, useSlidingSeries: false) != null ||
      getConfiguredSectionForRole(role, useSlidingSeries: true) != null;

  bool supportsCaniveauForScope(bool sliding) =>
      getConfiguredSectionForRole('caniveau', useSlidingSeries: sliding) !=
          null &&
      getConfiguredSectionForRole(
            'cache_caniveau',
            useSlidingSeries: sliding,
          ) !=
          null;

  bool get hasCaniveauSupport =>
      supportsCaniveauForScope(false) || supportsCaniveauForScope(true);

  bool get hasBavetteSupport => hasFrameRole('bavette');

  /// Whether the currently selected opening series actually provides a
  /// plinthe profile. Drawing controls must not offer a plinthe merely because
  /// the window has an opening sash; the profile also has to belong to the
  /// selected series configuration.
  bool get hasPlintheSupport {
    final series = activeSeries;
    if (series == null || isPVC) return false;
    if (getConfiguredSectionForRole('plant', useSlidingSeries: false) != null) {
      return true;
    }
    if (_hasLoadedRoleMetadata(series)) return false;
    return series.sections.any((section) {
      final type = section.type.trim().toLowerCase();
      final name = section.name.trim().toLowerCase();
      return type.contains('plinthe') ||
          type.contains('plinth') ||
          type.contains('plant') ||
          type.contains('بلانت') ||
          name.contains('plinthe') ||
          name.contains('plinth') ||
          name.contains('plant') ||
          name.contains('بلانت');
    });
  }

  bool get usesBavette => optionalBavetteMode > 0 && hasBavetteSupport;

  void setOptionalBavetteMode(int mode) {
    final next = mode.clamp(0, 2).toInt();
    if (next > 0 && !hasBavetteSupport) return;
    _saveSnapshot();
    optionalBavetteMode = next;
    _notifyModelListeners();
  }

  bool get hasProfileAngleSupport {
    final sliding = systemMode == 'sliding';
    return getConfiguredSectionForRole(
              'profile_angle',
              useSlidingSeries: sliding,
            ) !=
            null ||
        getConfiguredSectionForRole(
              'profile_angle',
              useSlidingSeries: !sliding,
            ) !=
            null ||
        getSectionByType('profile_angle') != null ||
        getSlidingSectionByType('profile_angle') != null ||
        getSectionByType('tube_carre') != null ||
        getSlidingSectionByType('tube_carre') != null;
  }

  double get profileAngleTubeWidth {
    final sliding = systemMode == 'sliding';
    final angleSection =
        getConfiguredSectionForRole(
          'profile_angle',
          useSlidingSeries: sliding,
        ) ??
        getConfiguredSectionForRole(
          'profile_angle',
          useSlidingSeries: !sliding,
        ) ??
        getSectionByType('profile_angle') ??
        getSlidingSectionByType('profile_angle') ??
        getSectionByType('tube_carre') ??
        getSlidingSectionByType('tube_carre');
    return (angleSection != null && angleSection.visibleWidth > 0)
        ? angleSection.visibleWidth.clamp(30.0, 100.0)
        : 50.0;
  }

  bool isProfileAngleJunctionActive(int index) {
    if (profileAngleJunctionsDisabled) return false;
    if (profileAngleJunctions.isNotEmpty) {
      return profileAngleJunctions.contains(index);
    }
    return frameRoleRequiredInAllScopes('profile_angle');
  }

  /// Finds all touching/adjacent vertical seams between independent frames.
  /// Frames are ordered horizontally from left to right.
  List<FrameAngleJunction> getAdjacentFrameJunctions() {
    final frames = getFrameRects();
    if (frames.length < 2) return [];

    final sortedFrames = List<Rect>.from(frames)
      ..sort((a, b) {
        final cmp = a.left.compareTo(b.left);
        return cmp != 0 ? cmp : a.top.compareTo(b.top);
      });
    final junctions = <FrameAngleJunction>[];
    final maxGap = math.max(80.0, profileThickness * 2 + 10.0);

    for (int i = 0; i < sortedFrames.length; i++) {
      for (int j = i + 1; j < sortedFrames.length; j++) {
        final first = sortedFrames[i];
        final second = sortedFrames[j];

        final start = math.max(first.top, second.top);
        final end = math.min(first.bottom, second.bottom);
        if (end <= start + 10.0) continue;

        if ((second.left - first.right).abs() <= maxGap) {
          final hasIntermediate = sortedFrames.asMap().entries.any((entry) {
            final idx = entry.key;
            if (idx == i || idx == j) return false;
            final r = entry.value;
            return r.left >= first.right - 5.0 &&
                r.right <= second.left + 5.0 &&
                math.min(r.bottom, end) > math.max(r.top, start) + 10.0;
          });
          if (hasIntermediate) continue;

          junctions.add(
            FrameAngleJunction(
              index: junctions.length,
              firstFrameIndex: i,
              secondFrameIndex: j,
              firstFrame: first,
              secondFrame: second,
              x: (first.right + second.left) / 2.0,
              top: start,
              bottom: end,
            ),
          );
        }
      }
    }
    return junctions;
  }

  /// Returns the set of active junction indices.
  /// If [profileAngleJunctions] is non-empty, user explicit selection is used.
  /// If the series rules make 'profile_angle' required, all junctions default to active.
  Set<int> get activeProfileAngleJunctions {
    if (profileAngleJunctionsDisabled) return const <int>{};
    final junctions = getAdjacentFrameJunctions();
    if (junctions.isEmpty) return const <int>{};
    if (profileAngleJunctions.isNotEmpty) {
      return profileAngleJunctions
          .where((idx) => idx >= 0 && idx < junctions.length)
          .toSet();
    }
    if (frameRoleRequiredInAllScopes('profile_angle')) {
      return List.generate(junctions.length, (i) => i).toSet();
    }
    return const <int>{};
  }

  /// The corner profile goes only between two touching frames: the old
  /// outer-edge mode (profileAngleMode) is no longer used.
  bool get usesProfileAngle => activeProfileAngleJunctions.isNotEmpty;

  String get profileAngleModeName {
    final junctions = getAdjacentFrameJunctions();
    final activeJunctions = activeProfileAngleJunctions;
    if (activeJunctions.isNotEmpty && junctions.isNotEmpty) {
      if (activeJunctions.length == junctions.length) {
        return junctions.length == 1
            ? '${junctions.first.label} (90°)'
            : 'جميع الفواصل (${activeJunctions.length}) (90°)';
      } else if (activeJunctions.length == 1) {
        final j = junctions.firstWhere(
          (j) => activeJunctions.contains(j.index),
          orElse: () => junctions.first,
        );
        return '${j.label} (90°)';
      } else {
        return '${activeJunctions.length} فواصل (90°)';
      }
    }
    switch (profileAngleMode) {
      case 1:
        return 'يمين (90°)';
      case 2:
        return 'يسار (90°)';
      case 3:
        return 'الجهتين (90°)';
      default:
        return 'إيقاف';
    }
  }

  String localizedProfileAngleModeName(AppLanguage lang) {
    final junctions = getAdjacentFrameJunctions();
    final activeJunctions = activeProfileAngleJunctions;
    if (activeJunctions.isNotEmpty && junctions.isNotEmpty) {
      if (activeJunctions.length == junctions.length) {
        if (junctions.length == 1) {
          final j = junctions.first;
          return '${j.localizedLabel(lang)} (90°)';
        }
        final count = activeJunctions.length;
        if (lang == AppLanguage.french) {
          return 'Toutes les jonctions ($count) (90°)';
        }
        if (lang.fallback == AppLanguage.english) {
          return 'All junctions ($count) (90°)';
        }
        return 'جميع الفواصل ($count) (90°)';
      } else if (activeJunctions.length == 1) {
        final j = junctions.firstWhere(
          (j) => activeJunctions.contains(j.index),
          orElse: () => junctions.first,
        );
        return '${j.localizedLabel(lang)} (90°)';
      } else {
        final count = activeJunctions.length;
        if (lang == AppLanguage.french) return '$count jonctions (90°)';
        if (lang.fallback == AppLanguage.english) return '$count junctions (90°)';
        return '$count فواصل (90°)';
      }
    }
    switch (profileAngleMode) {
      case 1:
        if (lang == AppLanguage.french) return 'Droite (90°)';
        if (lang.fallback == AppLanguage.english) return 'Right (90°)';
        return 'يمين (90°)';
      case 2:
        if (lang == AppLanguage.french) return 'Gauche (90°)';
        if (lang.fallback == AppLanguage.english) return 'Left (90°)';
        return 'يسار (90°)';
      case 3:
        if (lang == AppLanguage.french) return 'Deux côtés (90°)';
        if (lang.fallback == AppLanguage.english) return 'Both sides (90°)';
        return 'الجهتين (90°)';
      default:
        if (lang == AppLanguage.french) return 'Désactivé';
        if (lang.fallback == AppLanguage.english) return 'Disabled';
        return 'إيقاف';
    }
  }

  /// The frames of [junctionIndexes] (every junction when null) that have
  /// no frame set against a corner profile in the frame pairing page.
  List<String> cornerPairingProblems([Iterable<int>? junctionIndexes]) {
    final wanted = junctionIndexes?.toSet();
    final names = <String>{};
    for (final junction in getAdjacentFrameJunctions()) {
      if (wanted != null && !wanted.contains(junction.index)) continue;
      for (final frame in [junction.firstFrame, junction.secondFrame]) {
        final section = frameSectionForRect(frame);
        if (section == null) continue;
        if (!frameUsableWithProfileAngle(
          section,
          sliding: frameUsesSlidingSeries(frame),
        )) {
          names.add(
            section.code.trim().isEmpty
                ? section.name
                : '${section.code} - ${section.name}',
          );
        }
      }
    }
    return names.toList();
  }

  void toggleProfileAngleJunction(int junctionIndex, [bool? enabled]) {
    final turningOn =
        enabled ?? !activeProfileAngleJunctions.contains(junctionIndex);
    if (turningOn) {
      final problems = cornerPairingProblems([junctionIndex]);
      lastCornerPairingRefusal = problems;
      if (problems.isNotEmpty) {
        _notifyModelListeners();
        return;
      }
    }
    _saveSnapshot();
    profileAngleJunctionsDisabled = false;
    final junctions = getAdjacentFrameJunctions();
    if (profileAngleJunctions.isEmpty &&
        frameRoleRequiredInAllScopes('profile_angle')) {
      profileAngleJunctions = List.generate(junctions.length, (i) => i).toSet();
    }
    final shouldEnable =
        enabled ?? !profileAngleJunctions.contains(junctionIndex);
    if (shouldEnable) {
      profileAngleJunctions.add(junctionIndex);
      viewAs90DegreeCorner = true;
    } else {
      profileAngleJunctions.remove(junctionIndex);
      if (profileAngleJunctions.isEmpty) {
        profileAngleJunctionsDisabled = true;
      }
    }
    adaptFramesForProfileAngle();
    _notifyModelListeners();
  }

  void setAllProfileAngleJunctions(bool enabled) {
    if (enabled) {
      final problems = cornerPairingProblems();
      lastCornerPairingRefusal = problems;
      if (problems.isNotEmpty) {
        _notifyModelListeners();
        return;
      }
    }
    _saveSnapshot();
    if (enabled) {
      profileAngleJunctionsDisabled = false;
      final junctions = getAdjacentFrameJunctions();
      profileAngleJunctions = List.generate(junctions.length, (i) => i).toSet();
      if (profileAngleJunctions.isNotEmpty) viewAs90DegreeCorner = true;
    } else {
      profileAngleJunctionsDisabled = true;
      profileAngleJunctions.clear();
    }
    adaptFramesForProfileAngle();
    _notifyModelListeners();
  }

  void clearProfileAngle() {
    _saveSnapshot();
    profileAngleMode = 0;
    profileAngleJunctionsDisabled = true;
    profileAngleJunctions.clear();
    adaptFramesForProfileAngle();
    _notifyModelListeners();
  }

  /// Only "off" remains: the corner profile is never put on a frame's
  /// outer edge, only between two touching frames.
  void setProfileAngleMode(int mode) {
    _saveSnapshot();
    profileAngleMode = 0;
    adaptFramesForProfileAngle();
    _notifyModelListeners();
  }

  void cycleProfileAngleMode() {
    final junctions = getAdjacentFrameJunctions();
    if (junctions.isNotEmpty) {
      if (activeProfileAngleJunctions.isEmpty) {
        setAllProfileAngleJunctions(true);
      } else {
        clearProfileAngle();
      }
    }
  }

  /// Toggles between the 3D 90° corner perspective view and the flat developed 2D view.
  void toggle90DegreeCornerView() {
    viewAs90DegreeCorner = !viewAs90DegreeCorner;
    _notifyModelListeners();
  }

  /// Whether [section] may stand next to a corner profile (profil d'angle).
  /// A frame with an integrated cover never may. In aluminium, a frame that
  /// accepts a separate cover may not either: only a frame that can never
  /// carry a cover sits against the corner tube. In PVC every frame without
  /// an integrated cover may.
  bool frameFitsProfileAngle(AluminumSection section, {bool sliding = false}) {
    if (_sectionHasIntegratedSideCover(section) ||
        section.couvreJointWidth > 0) {
      return false;
    }
    final series = sliding ? activeSlidingSeries : activeFrameSeries;
    if (series != null && _isPvcSeries(series)) return true;
    return !section.allowsSideCover;
  }

  /// Whether [section] can be used in a drawing with a corner profile:
  /// it fits the corner itself, or the series has a frame that does for the
  /// jamb touching the corner.
  bool frameUsableWithProfileAngle(
    AluminumSection section, {
    bool sliding = false,
  }) {
    final cornerId = cornerFrameIdFor(section.id);
    if (cornerId == null) return false;
    return cornerId == section.id || catalogSectionById(cornerId) != null;
  }

  /// The frame set in the frame pairing page to stand against a corner
  /// profile for [currentFrame]; null when the frame itself stands there or
  /// nothing is set (then the corner profile cannot be switched on).
  AluminumSection? findCompatibleNoCoverFrame({
    required AluminumSection currentFrame,
    bool sliding = false,
  }) {
    final cornerId = cornerFrameIdFor(currentFrame.id);
    if (cornerId == null || cornerId == currentFrame.id) return null;
    return catalogSectionById(cornerId);
  }

  /// Returns the compatible frames chosen for 90° corner junctions/edges
  /// (without integrated cover) that appear in the BOM (Quantity & Cost table).
  Map<String, ({AluminumSection section, bool sliding})>
  getProfileAngleJunctionFrames() {
    final result = <String, ({AluminumSection section, bool sliding})>{};
    if (!usesProfileAngle) return result;

    void addJunctionSide(Rect frame) {
      final currentFrame = frameSectionForRect(frame);
      if (currentFrame == null) return;
      final sliding = frameUsesSlidingSeries(frame);
      final compatible = findCompatibleNoCoverFrame(
        currentFrame: currentFrame,
        sliding: sliding,
      );
      if (compatible == null) return;
      final itemKey = '${sliding ? 'sliding' : 'opening'}:${compatible.id}';
      result[itemKey] = (section: compatible, sliding: sliding);
    }

    final junctions = getAdjacentFrameJunctions();
    for (final junction in junctions) {
      if (!activeProfileAngleJunctions.contains(junction.index)) {
        continue;
      }
      addJunctionSide(junction.firstFrame);
      addJunctionSide(junction.secondFrame);
    }

    final frameRects = getFrameRects();
    if (junctions.isEmpty && frameRects.isNotEmpty) {
      if (profileAngleMode == 2 || profileAngleMode == 3) {
        addJunctionSide(frameRects.first);
      }
      if (profileAngleMode == 1 || profileAngleMode == 3) {
        addJunctionSide(frameRects.last);
      }
    }
    return result;
  }

  /// Frames touching an active corner profile that neither fit the corner
  /// nor have a frame in their series that does (see
  /// [frameFitsProfileAngle]). The drawing is then not buildable as drawn.
  List<String> get profileAngleFrameProblems {
    if (!usesProfileAngle) return const [];
    final names = <String>{};
    void check(Rect frame) {
      final section = frameSectionForRect(frame);
      if (section == null) return;
      final sliding = frameUsesSlidingSeries(frame);
      if (!frameUsableWithProfileAngle(section, sliding: sliding)) {
        names.add(section.name);
      }
    }

    final junctions = getAdjacentFrameJunctions();
    for (final junction in junctions) {
      if (!activeProfileAngleJunctions.contains(junction.index)) continue;
      check(junction.firstFrame);
      check(junction.secondFrame);
    }
    final frameRects = getFrameRects();
    if (junctions.isEmpty && frameRects.isNotEmpty) {
      if (profileAngleMode == 2 || profileAngleMode == 3) {
        check(frameRects.first);
      }
      if (profileAngleMode == 1 || profileAngleMode == 3) {
        check(frameRects.last);
      }
    }
    return names.toList();
  }

  void _restoreFramesBeforeProfileAngleFullSwitch() {
    if (!_frameSwitchedForProfileAngle) return;
    if (_preProfileAngleFrameOverride != null) {
      applyFrameOverride(_preProfileAngleFrameOverride!, sliding: false);
      _preProfileAngleFrameOverride = null;
    }
    if (_preProfileAngleSlidingOverride != null) {
      applyFrameOverride(_preProfileAngleSlidingOverride!, sliding: true);
      _preProfileAngleSlidingOverride = null;
    }
    _frameSwitchedForProfileAngle = false;
    _profileAngleFrameSwitchNotice = null;
  }

  /// Automatically adapts frames touching corner profile by switching them
  /// to a compatible frame without integrated cover and with matching visible width.
  void adaptFramesForProfileAngle() {
    if (usesProfileAngle) {
      // If the drawing has separate side covers and is not an integrated frame,
      // we do not need to switch the entire frame. Only the junction-side vertical
      // jamb will be cut with the compatible frame in the BOM!
      if (hasSideCovers && !isIntegratedFrame) {
        // The drawing may previously have had no side covers, which causes a
        // complete compatible-frame switch. Restore its original frame now;
        // BOM generation will retain only the touching jamb on the compatible
        // profile (three original pieces + one junction piece per frame).
        _restoreFramesBeforeProfileAngleFullSwitch();
        hasSideCovers = true;
        return;
      }

      // Opening series frame check
      final currentOpening =
          activeFrameOverride ?? getSectionByType('frame')?.toMap();
      final bool openingHasCover =
          _overrideHasIntegratedSideCover(currentOpening) ||
          (currentOpening != null &&
              ((currentOpening['couvre_joint_width'] as num?)?.toDouble() ??
                      0) >
                  0);

      if (currentOpening != null && activeFrameSeries != null) {
        final currentSec = AluminumSection.fromMap(currentOpening);
        final compatible = findCompatibleNoCoverFrame(
          currentFrame: currentSec,
          sliding: false,
        );
        // With separate side covers, only the two jambs touching the tube
        // carré are substituted in the BOM. When the whole drawing has no
        // side cover, the compatible frame may replace the complete frame.
        if (compatible != null && (!hasSideCovers || openingHasCover)) {
          if (!_frameSwitchedForProfileAngle) {
            _preProfileAngleFrameOverride = currentOpening;
          }
          final override = compatible.toMap();
          override['manual_selection'] = true;
          applyFrameOverride(override, sliding: false);
          _frameSwitchedForProfileAngle = true;
          _profileAngleFrameSwitchNotice = compatible.name;
        }
      }

      // Sliding series frame check
      final currentSliding =
          slidingFrameOverride ?? getSlidingBaseFrameSection()?.toMap();
      final bool slidingHasCover =
          _overrideHasIntegratedSideCover(currentSliding) ||
          (currentSliding != null &&
              ((currentSliding['couvre_joint_width'] as num?)?.toDouble() ??
                      0) >
                  0);

      if (currentSliding != null && activeSlidingSeries != null) {
        final currentSec = AluminumSection.fromMap(currentSliding);
        final compatible = findCompatibleNoCoverFrame(
          currentFrame: currentSec,
          sliding: true,
        );
        if (compatible != null && (!hasSideCovers || slidingHasCover)) {
          if (!_frameSwitchedForProfileAngle) {
            _preProfileAngleSlidingOverride = currentSliding;
          }
          final override = compatible.toMap();
          override['manual_selection'] = true;
          applyFrameOverride(override, sliding: true);
          _frameSwitchedForProfileAngle = true;
          _profileAngleFrameSwitchNotice = compatible.name;
        }
      }
    } else {
      _restoreFramesBeforeProfileAngleFullSwitch();
    }
  }

  bool frameRoleRequiredInAllScopes(String role) {
    final scopes = [false, true].where(
      (sliding) =>
          getConfiguredSectionForRole(role, useSlidingSeries: sliding) != null,
    );
    return scopes.isNotEmpty &&
        scopes.every(
          (sliding) =>
              isConfiguredRoleRequired(role, useSlidingSeries: sliding),
        );
  }

  bool frameRoleEnabledInAnyScope(String role) =>
      [false, true].any((sliding) => usesFrameRole(role, sliding: sliding));

  (int, int) cacheRailCountsForRect(Rect frame) {
    if (!usesFrameRole('cache_rail', sliding: true)) return (0, 0);
    // A frame that can never carry a side cover cannot carry a cache-rail
    // either.
    final section = frameSectionForRect(frame);
    if (section != null &&
        !section.allowsSideCover &&
        !_sectionHasIntegratedSideCover(section)) {
      return (0, 0);
    }
    final tracks = zones
        .where((zone) => frame.contains(zone.boundary.center))
        .fold<int>(1, (count, zone) => math.max(count, zone.slidingTrackCount));
    final maximum = math.max(0, tracks - 1);
    return (maximum, maximum);
  }

  /// Visible workshop width of the exact frame selected for this rectangle.
  /// The painter must not reuse the generic profile thickness after a role
  /// rule has selected a different PVC frame.
  double frameVisibleWidthForRect(Rect frame, {double? fallback}) {
    final section = frameSectionForRect(frame);
    if (section != null) {
      final row = section.toMap();
      for (final key in const ['visible_width', 'thickness']) {
        final raw = row[key];
        final value = raw is num
            ? raw.toDouble()
            : double.tryParse(raw?.toString() ?? '');
        if (value != null && value > 0) return value;
      }
    }
    return fallback ?? profileThickness;
  }

  bool frameHasIntegratedSideCoverForRect(Rect frame) {
    final section = frameSectionForRect(frame);
    return section != null && _sectionHasIntegratedSideCover(section);
  }

  bool get selectedOuterFrameHasIntegratedSideCover {
    final frames = getFrameRects();
    final frame = frames.isEmpty
        ? Rect.fromLTWH(0, 0, width, height)
        : frames.first;
    return frameHasIntegratedSideCoverForRect(frame);
  }

  bool frameCanUseCacheRainure(Rect frame) {
    final section = frameSectionForRect(frame);
    if (section == null) return false;
    return !_sectionHasIntegratedSideCover(section);
  }

  /// Finds seams shared by two independent frames. A seam is eligible only
  /// when both frames accept a separate couvre-joint and either they belong
  /// to one series with Cache-rainure, or each touching series defines it.
  /// Each eligible seam receives one profile on the inside and one outside.
  List<FrameCacheRainureContact> getCacheRainureContacts() {
    const tolerance = 5.0;
    final frames = getFrameRects();
    final contacts = <FrameCacheRainureContact>[];

    for (var firstIndex = 0; firstIndex < frames.length; firstIndex++) {
      for (
        var secondIndex = firstIndex + 1;
        secondIndex < frames.length;
        secondIndex++
      ) {
        final first = frames[firstIndex];
        final second = frames[secondIndex];
        if (!frameCanUseCacheRainure(first) ||
            !frameCanUseCacheRainure(second)) {
          continue;
        }

        final firstSliding = frameUsesSlidingSeries(first);
        final secondSliding = frameUsesSlidingSeries(second);
        final firstSection = frameSectionForRect(first);
        final secondSection = frameSectionForRect(second);
        final sameSeries =
            firstSection != null &&
            secondSection != null &&
            firstSection.seriesId == secondSection.seriesId;
        final firstHasRole =
            getConfiguredSectionForRole(
                  'cache_rainure',
                  useSlidingSeries: firstSliding,
                ) !=
                null ||
            (firstSliding
                    ? getSlidingSectionByType('cache_rainure')
                    : getSectionByType('cache_rainure')) !=
                null;
        final secondHasRole =
            getConfiguredSectionForRole(
                  'cache_rainure',
                  useSlidingSeries: secondSliding,
                ) !=
                null ||
            (secondSliding
                    ? getSlidingSectionByType('cache_rainure')
                    : getSectionByType('cache_rainure')) !=
                null;
        // A role on only one of two different series is insufficient: it
        // would leave one face without a compatible Cache-rainure profile.
        if (!(sameSeries
            ? (firstHasRole || secondHasRole)
            : (firstHasRole && secondHasRole))) {
          continue;
        }
        // If an active profile angle or tube carre junction joins these two frames,
        // no cache-rainure can be placed at this junction seam.
        final activeAngles = activeProfileAngleJunctions;
        if (activeAngles.isNotEmpty) {
          final allJunctions = getAdjacentFrameJunctions();
          final hasAngleJunction = allJunctions.any(
            (j) =>
                activeAngles.contains(j.index) &&
                ((j.firstFrame == first && j.secondFrame == second) ||
                    (j.firstFrame == second && j.secondFrame == first)),
          );
          if (hasAngleJunction) continue;
        }

        final insideRoleSeries = firstHasRole ? firstSliding : secondSliding;
        final outsideRoleSeries = sameSeries ? insideRoleSeries : secondSliding;

        final vertical =
            (first.right - second.left).abs() <= tolerance ||
            (second.right - first.left).abs() <= tolerance;
        if (vertical) {
          final start = math.max(first.top, second.top);
          final end = math.min(first.bottom, second.bottom);
          if (end <= start + tolerance) continue;
          final coordinate = (first.right - second.left).abs() <= tolerance
              ? (first.right + second.left) / 2.0
              : (second.right + first.left) / 2.0;
          contacts.add(
            FrameCacheRainureContact(
              firstFrame: first,
              secondFrame: second,
              isVertical: true,
              coordinate: coordinate,
              start: start,
              end: end,
              insideUsesSlidingSeries: insideRoleSeries,
              outsideUsesSlidingSeries: outsideRoleSeries,
            ),
          );
          continue;
        }

        final horizontal =
            (first.bottom - second.top).abs() <= tolerance ||
            (second.bottom - first.top).abs() <= tolerance;
        if (!horizontal) continue;
        final start = math.max(first.left, second.left);
        final end = math.min(first.right, second.right);
        if (end <= start + tolerance) continue;
        final coordinate = (first.bottom - second.top).abs() <= tolerance
            ? (first.bottom + second.top) / 2.0
            : (second.bottom + first.top) / 2.0;
        contacts.add(
          FrameCacheRainureContact(
            firstFrame: first,
            secondFrame: second,
            isVertical: false,
            coordinate: coordinate,
            start: start,
            end: end,
            insideUsesSlidingSeries: insideRoleSeries,
            outsideUsesSlidingSeries: outsideRoleSeries,
          ),
        );
      }
    }
    return contacts;
  }

  bool get usesSeuil =>
      usesFrameRole('seuil', sliding: usesSlidingPrimaryProfiles);

  bool get usesCacheDormant =>
      useOptionalCacheDormant || isConfiguredRoleRequired('cache_dormant');

  bool get usesCacheRail =>
      useOptionalCacheRail &&
      getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) != null;

  void toggleSeuil(bool value) {
    if (value && !hasFrameRole('seuil')) return;
    _saveSnapshot();
    useOptionalSeuil = value;
    if (value) {
      useOptionalCaniveau = false;
    } else {
      // C/Seuil physically replaces the lower frame member. Switching it
      // off must therefore restore that member, even when an older drawing
      // had its bottom frame disabled before C was selected.
      final wasBottomFrame = hasBottomFrame;
      hasBottomFrame = true;
      showBottomWall = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      updateBottomZoneBoundaries();
    }
    _notifyModelListeners();
  }

  void toggleCacheDormant(bool value) {
    if (value && !hasFrameRole('cache_dormant')) return;
    _saveSnapshot();
    useOptionalCacheDormant = value;
    _notifyModelListeners();
  }

  void setCacheRailCounts(int left, int right) {
    _saveSnapshot();
    cacheRailLeftCount = math.max(0, left);
    cacheRailRightCount = math.max(0, right);
    useOptionalCacheRail = cacheRailLeftCount > 0 || cacheRailRightCount > 0;
    _notifyModelListeners();
  }

  void toggleCacheRail(bool value) {
    if (value &&
        getConfiguredSectionForRole('cache_rail', useSlidingSeries: true) ==
            null) {
      return;
    }
    _saveSnapshot();
    useOptionalCacheRail = value;
    _notifyModelListeners();
  }

  bool get effectiveHasBottomFrame {
    if (systemMode == 'sliding') {
      if (usesSeuil) return false;
      return hasBottomFrame;
    }
    if (hasFramePlintheBottom || zones.any((z) => z.hasSashPlintheBottom)) {
      return false;
    }
    if (usesSeuil) return false;
    if (!hasBottomFrame) return false;
    return (hasBottomFrame && !usesSeuil) || !canDisableBottomFrame;
  }

  /// Plinthe belongs to its opening frame, not neighbouring sliding frames.
  bool hasBottomFrameForRect(Rect frameRect) {
    final sliding = frameUsesSlidingSeries(frameRect);
    if (usesFrameRole('seuil', sliding: sliding)) return false;
    final frameZones = zones
        .where((z) => frameRect.contains(z.boundary.center))
        .toList();
    // A plinthe replaces the lower frame of opening/fixed sashes only. A
    // neighbouring frame made of sliding sashes keeps its real lower frame.
    final plintheSparesFrame =
        hasFramePlintheBottom &&
        frameZones.isNotEmpty &&
        frameZones.every((z) => z.content == ZoneContent.slidingSash);
    if (sliding) return hasBottomFrame || plintheSparesFrame;
    if (hasFramePlintheBottom) return plintheSparesFrame;
    if (frameZones.any((z) => z.hasSashPlintheBottom)) return false;
    if (frameZones.isNotEmpty &&
        frameZones.every(
          (z) =>
              z.content == ZoneContent.fixedGlass ||
              z.content == ZoneContent.empty,
        )) {
      return true;
    }
    for (final zone in frameZones) {
      final local = componentOverrides['frame-bottom:${zone.id}'];
      if (local is bool) return local;
    }
    if (!hasBottomFrame) return false;
    return hasBottomFrame;
  }

  Rect? get selectedPhysicalFrameRect {
    final zone = selectedZone;
    if (zone == null) return null;
    for (final rect in getFrameRects()) {
      if (rect.contains(zone.boundary.center)) return rect;
    }
    return null;
  }

  bool get selectedFrameHasBottom {
    final rect = selectedPhysicalFrameRect;
    return rect == null ? effectiveHasBottomFrame : hasBottomFrameForRect(rect);
  }

  // With the bottom wall hidden there is nothing below the frame for a
  // cover to close; this condition was lost when the rule became per side.
  bool get canUseBottomSideCover =>
      showBottomWall && canSideUseSideCover('bottom');

  bool get canEditSelectedBottomFrame {
    if (!canDisableBottomFrame) return false;
    final frames = getFrameRects();
    final selected =
        selectedPhysicalFrameRect ??
        (frames.length == 1 ? frames.single : null);
    // With one physical frame there is no ambiguity, so Cadre du bas can
    // toggle it even when the user has not selected the drawing first. A
    // multi-frame drawing still requires an explicit frame selection.
    if (selected == null || frameUsesSlidingSeries(selected)) return false;
    final frameZones = zones.where((z) => selected.contains(z.boundary.center));
    if (frameZones.isNotEmpty &&
        frameZones.every(
          (z) =>
              z.content == ZoneContent.fixedGlass ||
              z.content == ZoneContent.empty,
        )) {
      return false;
    }
    return true;
  }

  bool usesCaniveauForRect(Rect frameRect) {
    if (!useOptionalCaniveau) return false;
    final sliding = frameUsesSlidingSeries(frameRect);
    // A caniveau always sits outside an existing lower frame. Seuil/C removes
    // that frame, so the two profiles can never be used together.
    return supportsCaniveauForScope(sliding) &&
        hasBottomFrameForRect(frameRect) &&
        !usesFrameRole('seuil', sliding: sliding);
  }

  bool get canEnableCaniveau =>
      getFrameRects().any(usesCaniveauForRect) ||
      (hasCaniveauSupport &&
          !frameRoleEnabledInAnyScope('seuil') &&
          (hasBottomFrame || systemMode == 'sliding'));

  void toggleCaniveau(bool value) {
    if (value && (!hasCaniveauSupport || frameRoleEnabledInAnyScope('seuil'))) {
      return;
    }
    _saveSnapshot();
    useOptionalCaniveau = value;
    _notifyModelListeners();
  }

  void toggleOptionalTriangle(bool value) {
    _saveSnapshot();
    useOptionalTriangle = value;
    _notifyModelListeners();
  }

  bool get hasOptionalTriangleLink => componentOverrides.values.any(
    (value) =>
        value is Map &&
        '${value['triangle_link_mode'] ?? ''}'.trim().toLowerCase() ==
            'optional',
  );

  bool _normalizeBottomFrameForCurrentContent() {
    if (hasFramePlintheBottom || zones.any((z) => z.hasSashPlintheBottom)) {
      return false;
    }
    if (canDisableBottomFrame && systemMode != 'sliding') return false;

    var changed = false;
    if (!hasBottomFrame) {
      hasBottomFrame = true;
      changed = true;
    }
    if (hasFramePlintheBottom) {
      hasFramePlintheBottom = false;
      changed = true;
    }
    for (final zone in zones) {
      if (zone.hasSashPlintheBottom) {
        zone.hasSashPlintheBottom = false;
        changed = true;
      }
    }
    if (!showBottomWall) {
      showBottomWall = true;
      changed = true;
    }
    return changed;
  }

  void enforceBottomFrameForCurrentContent({bool notify = false}) {
    final changed = _normalizeBottomFrameForCurrentContent();
    if (!changed) return;
    updateBottomZoneBoundaries();
    if (notify) _notifyModelListeners();
  }

  void toggleBottomFrame(bool value) {
    final frames = getFrameRects();
    if (frames.length > 1) {
      final selected = selectedPhysicalFrameRect;
      if (selected == null ||
          frameUsesSlidingSeries(selected) ||
          !canDisableBottomFrame)
        return;
      _saveSnapshot();
      // Zone IDs survive resizing, serialization and undo. Keep this setting
      // on all members of the physical frame, without moving its boundaries
      // or changing the neighbouring frame's wall/cover state.
      for (final zone in zones) {
        if (selected.contains(zone.boundary.center)) {
          componentOverrides['frame-bottom:${zone.id}'] = value;
        }
      }
      _notifyModelListeners();
      return;
    }
    componentOverrides.removeWhere(
      (key, value) => key.startsWith('frame-bottom:'),
    );
    if (!value && !canEditSelectedBottomFrame) return;
    if ((systemMode == 'sliding' &&
            !hasFramePlintheBottom &&
            !zones.any((z) => z.hasSashPlintheBottom)) ||
        (!value && !canDisableBottomFrame)) {
      final wasBottomFrame = hasBottomFrame;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      hasFramePlintheBottom = false;
      for (var z in zones) {
        z.hasSashPlintheBottom = false;
      }
      showBottomWall = true;
      updateBottomZoneBoundaries();
      _notifyModelListeners();
      return;
    }
    _saveSnapshot();
    final wasBottomFrame = hasBottomFrame;
    hasBottomFrame = value;
    if (hasBottomFrame && !wasBottomFrame) {
      _restoreBottomSideCoverWhenFrameReturns();
    }
    _hideBottomCoverWhenBottomFrameIsMissing();
    if (hasBottomFrame) {
      hasFramePlintheBottom = false;
      for (var z in zones) {
        z.hasSashPlintheBottom = false;
      }
    }
    if (!hasBottomFrame) {
      showBottomWall = false;
    } else {
      showBottomWall = true;
    }
    updateBottomZoneBoundaries();
    _notifyModelListeners();
  }

  void toggleFramePlintheBottom(bool value) {
    bool isPlintheEligible(WindowZone zone) {
      return zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash ||
          zone.content == ZoneContent.fixedGlass;
    }

    final canUsePlinthe =
        hasOpeningSashZones ||
        zones.any((z) => z.content == ZoneContent.fixedGlass);
    if (value && !canUsePlinthe) {
      final wasBottomFrame = hasBottomFrame;
      hasFramePlintheBottom = false;
      for (final zone in zones) {
        zone.hasSashPlintheBottom = false;
      }
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      updateBottomZoneBoundaries();
      _notifyModelListeners();
      return;
    }
    final flagsMatch = zones.every(
      (zone) => zone.hasSashPlintheBottom == (value && isPlintheEligible(zone)),
    );
    final frameStateMatches = value ? !hasBottomFrame : hasBottomFrame;
    if (hasFramePlintheBottom == value && frameStateMatches && flagsMatch) {
      return;
    }
    _saveSnapshot();
    final wasBottomFrame = hasBottomFrame;

    if (value) {
      hasFramePlintheBottom = true;
      hasBottomFrame = false;
      showBottomWall = false;
      for (final z in zones) {
        z.hasSashPlintheBottom = isPlintheEligible(z);
      }
    } else {
      hasFramePlintheBottom = false;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      for (final z in zones) {
        z.hasSashPlintheBottom = false;
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();
    _notifyModelListeners();
  }

  void toggleSelectedZoneSashPlintheBottom() {
    final zone = selectedZone;
    if (zone == null) return;
    if (zone.content != ZoneContent.singleSash &&
        zone.content != ZoneContent.doubleSash) {
      return;
    }
    _saveSnapshot();

    zone.hasSashPlintheBottom = !zone.hasSashPlintheBottom;

    final anySashPlinthe = zones.any(
      (z) =>
          (z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash) &&
          z.hasSashPlintheBottom,
    );
    if (anySashPlinthe) {
      hasFramePlintheBottom = true;
      hasBottomFrame = false;
      showBottomWall = false;
    } else {
      final wasBottomFrame = hasBottomFrame;
      hasFramePlintheBottom = false;
      hasBottomFrame = true;
      if (!wasBottomFrame) _restoreBottomSideCoverWhenFrameReturns();
      showBottomWall = true;
      // Fixed-zone flags can only come from the global frame-plinthe mode.
      // Clear them when the last sash plinthe is disabled.
      for (final z in zones) {
        if (z.content != ZoneContent.singleSash &&
            z.content != ZoneContent.doubleSash) {
          z.hasSashPlintheBottom = false;
        }
      }
    }

    _hideBottomCoverWhenBottomFrameIsMissing();
    updateBottomZoneBoundaries();
    _notifyModelListeners();
  }

  void updateBottomZoneBoundaries() {
    _normalizeBottomFrameForCurrentContent();

    for (var z in zones) {
      if (z.content == ZoneContent.slidingSash) {
        z.hasSashPlintheBottom = false;
        continue;
      }
      final hasPlintheBottom = !hasBottomFrame && z.hasSashPlintheBottom;
      final isOpeningSash =
          z.content == ZoneContent.singleSash ||
          z.content == ZoneContent.doubleSash;
      final targetBottom =
          (!hasBottomFrame && (hasPlintheBottom || isOpeningSash))
          ? height
          : height - profileThickness;
      if ((z.boundary.bottom - height).abs() < 5.0 ||
          (z.boundary.bottom - (height - profileThickness)).abs() < 5.0 ||
          (z.boundary.bottom - (height - plintheHeight)).abs() < 5.0) {
        z.boundary = Rect.fromLTRB(
          z.boundary.left,
          z.boundary.top,
          z.boundary.right,
          targetBottom,
        );
      }
    }

    if (!hasBottomFrame) {
      for (var z in zones) {
        if (z.content == ZoneContent.slidingSash) continue;
        if (z.openDirection == OpenDirection.top ||
            z.openDirection == OpenDirection.bottom) {
          z.openDirection = OpenDirection.left;
        }
      }
    }
  }

  void toggleBottomWall() {
    _saveSnapshot();
    showBottomWall = !showBottomWall;
    enforceBottomSideCoverConstraint();
    _notifyModelListeners();
  }

  /// Whether a side cover is a separate profile here: coupled frames, or a
  /// regular (non-tunnel) shutter box on an aluminium frame. Otherwise the
  /// cover is part of an integrated-cover frame.
  bool get _usesStandaloneSideCover =>
      getFrameRects().length > 1 ||
      (hasShutter && !isCaissonTunnel && !isFramePVC);

  /// Turns the separate side cover on or off after the frame was replaced
  /// from the required-goods page. Unlike [toggleSideCovers] it never
  /// reselects the frame: the frame the user just chose stays.
  void setSideCoversAfterFrameSwap(bool enabled) {
    hasSideCovers = enabled;
    _multiFrameSideCoverManuallyEnabled =
        enabled && getFrameRects().length > 1;
    if (!enabled) return;
    final covers = availableSideCovers;
    if (covers.isNotEmpty &&
        !covers.any((cover) => cover.id == selectedSideCover?.id)) {
      selectedSideCover = covers.first;
      sideCoverOverride = covers.first.toMap();
    } else if (selectedSideCover != null && sideCoverOverride == null) {
      sideCoverOverride = selectedSideCover!.toMap();
    }
  }

  Future<void> toggleSideCovers(bool value) async {
    // Side covers follow a rectangular frame only.
    if (value && hasCornerNotches) return;
    final revision = ++_sideCoverSelectionRevision;
    final isMultiFrame = getFrameRects().length > 1;
    _saveSnapshot();
    _multiFrameSideCoverManuallyEnabled = isMultiFrame && value;
    hasSideCovers = value;
    if (value && usesProfileAngle && _frameSwitchedForProfileAngle) {
      _restoreFramesBeforeProfileAngleFullSwitch();
      // Applying the saved frame can update cover state as part of normal
      // manual frame selection. The user's current toggle remains authoritative.
      hasSideCovers = true;
    }
    if (value) {
      final covers = availableSideCovers;
      if (covers.isNotEmpty &&
          !covers.any((cover) => cover.id == selectedSideCover?.id)) {
        selectedSideCover = covers.first;
        sideCoverOverride = covers.first.toMap();
      } else if (selectedSideCover != null && sideCoverOverride == null) {
        sideCoverOverride = selectedSideCover!.toMap();
      }
    }
    // Draw the change immediately. Profile/price lookup stays asynchronous,
    // so a slow catalogue read cannot make the drawing page appear frozen.
    _notifyModelListeners();

    await _selectFrameForSideCoverToggle(value, revision: revision);
  }

  Future<void> _selectFrameForSideCoverToggle(
    bool enabled, {
    required int revision,
  }) async {
    final series = activeFrameSeries;
    if (series == null) return;
    final sliding = usesSlidingPrimaryProfiles;
    final hadShutter = hasShutter;
    final hadTunnel = isCaissonTunnel;
    final multiFrame = getFrameRects().length > 1;
    final needsStandalone = _usesStandaloneSideCover;
    final current = activeFrameOverride ?? getSectionByType('frame')?.toMap();
    final integrated = _overrideHasIntegratedSideCover(current);
    if (!enabled && !integrated) return;
    if (enabled && !needsStandalone && integrated && sideCoverWidth > 0) return;
    if (enabled &&
        needsStandalone &&
        current != null &&
        _overrideAllowsStandaloneSideCover(current)) {
      return;
    }

    bool stillCurrent() =>
        revision == _sideCoverSelectionRevision &&
        enabled == hasSideCovers &&
        series == activeFrameSeries &&
        sliding == usesSlidingPrimaryProfiles &&
        hadShutter == hasShutter &&
        hadTunnel == isCaissonTunnel &&
        multiFrame == (getFrameRects().length > 1);

    // A cover-button click may change the frame, but never invent a role or
    // select a profile that is hidden from the replacement dialog.
    final List<Map<String, dynamic>> rows;
    try {
      rows = await db.getDesignSectionsForScopedDialogRoles(
        series.id,
        const ['frame'],
        usageScope: sliding ? 'sliding' : 'opening',
        requireDialog: true,
        requireQuantity: true,
      );
    } catch (_) {
      return;
    }
    if (!stillCurrent()) return;
    final frames = rows.where((row) {
      final glassRule = '${row['design_show_when_glass'] ?? 'any'}'
          .trim()
          .toLowerCase();
      if ((glassRule == 'single' || glassRule == 'simple') &&
          !hasSimpleGlassForReducer) {
        return false;
      }
      if (glassRule == 'double' && !hasDoubleGlassForRules) return false;
      return true;
    }).toList();
    final plain = frames.where((row) => !_overrideHasIntegratedSideCover(row));
    // A plain frame always remains usable with a separate cover profile.
    final standalone = plain.toList();
    final integratedFrames = frames.where((row) {
      final width = _readPositiveDouble(row['couvre_joint_width']);
      return _overrideHasIntegratedSideCover(row) && width > 0;
    }).toList();
    final candidates = !enabled
        ? plain.toList()
        : needsStandalone
        ? standalone
        : integratedFrames.isNotEmpty
        ? integratedFrames
        : standalone;
    if (candidates.isEmpty) return;

    // Switching couvre-joint may require a compatible frame, but it must not
    // silently collapse a 4/5/6-rail sliding drawing back to the first
    // (usually two-rail) catalogue frame. Prefer an exact complete frame for
    // the rails already present; when none exists, keep the candidate base
    // and let Complément dormant supply the additional rails.
    final requestedTracks = sliding ? _requestedSlidingTrackCount() : 2;
    Map<String, dynamic>? completeMatchingTracks;
    for (final candidate in candidates) {
      final mode =
          (candidate['design_track_mode'] ?? candidate['track_mode'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
      final rawCount =
          candidate['design_track_count'] ?? candidate['track_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      if (mode == 'complete' && count == requestedTracks) {
        completeMatchingTracks = candidate;
        break;
      }
    }
    final target = Map<String, dynamic>.from(
      completeMatchingTracks ?? candidates.first,
    );
    target['manual_selection'] = true;
    // Preserve the requested switch state: applyFrameOverride's manual mode
    // is for clicking a profile, which intentionally disables plain covers.
    applyFrameOverride(target, sliding: sliding);
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments.clear();
    _notifyModelListeners();

    final colorId = selectedDbColor?['id'];
    if (colorId == null) return;
    try {
      final price = await db.getSectionPrice(target['id'], colorId);
      if (!stillCurrent() || selectedDbColor?['id'] != colorId) return;
      final selected = sliding ? slidingFrameOverride : frameOverride;
      if (selected?['id'] == target['id']) {
        selected!['calculated_price'] = price;
        _notifyModelListeners();
      }
    } catch (_) {
      // Geometry is already updated; a temporarily unavailable price must
      // not undo the user's frame/cover choice.
    }
  }

  void toggleSideCoverOrientation() {
    _saveSnapshot();
    sideCoverUseSecondWidth = !sideCoverUseSecondWidth;
    _notifyModelListeners();
  }

  void toggleFrameType() {
    _saveSnapshot();
    isFrame140 = !isFrame140;
    updateProfileThickness();
    _notifyModelListeners();
  }

  /// A bottom side cover cannot exist without its bottom frame and wall.
  void _hideBottomCoverWhenBottomFrameIsMissing() {
    enforceBottomSideCoverConstraint();
  }

  /// Re-enable a bottom cover after the drawing returns from a plinthe/open
  /// bottom to a real bottom frame. The missing-frame constraint intentionally
  /// stores the old state as hidden; clear only that stale state on this
  /// transition, without changing a user's deliberate hide action while the
  /// frame is already present.
  void _restoreBottomSideCoverWhenFrameReturns() {
    if (!hasBottomFrame) return;
    removedShutterSides.remove('bottom');
    hiddenSideCoverSegments.remove('bottom');
  }

  /// Normalises the bottom cover after a drawing is restored or altered.
  /// A bottom cover requires both a bottom frame and a visible bottom wall.
  void enforceBottomSideCoverConstraint() {
    if (!canUseBottomSideCover) {
      removedShutterSides.add('bottom');
      hiddenSideCoverSegments.add('bottom');
      sideCoverSegments = sideCoverSegments
          .where((segment) => segment.side != 'bottom')
          .toList();
    }
  }

  Rect? _blankFrameCellForDrawnFrame(Rect drawnRect, Offset start) {
    final windowRect = Rect.fromLTWH(0, 0, width, height);
    if (!windowRect.contains(start) || !windowRect.contains(drawnRect.center)) {
      return null;
    }

    final frameRects = getFrameRects();
    final xs = <double>[0.0, width];
    final ys = <double>[0.0, height];
    for (final frame in frameRects) {
      xs.add(frame.left.clamp(0.0, width).toDouble());
      xs.add(frame.right.clamp(0.0, width).toDouble());
      ys.add(frame.top.clamp(0.0, height).toDouble());
      ys.add(frame.bottom.clamp(0.0, height).toDouble());
    }

    List<double> sortedUnique(List<double> values) {
      values.sort();
      final result = <double>[];
      for (final value in values) {
        if (result.isEmpty || (value - result.last).abs() > 2.0) {
          result.add(value);
        }
      }
      return result;
    }

    final uniqueX = sortedUnique(xs);
    final uniqueY = sortedUnique(ys);
    Rect? best;
    double bestOverlap = 0.0;

    for (var xi = 0; xi < uniqueX.length - 1; xi++) {
      for (var yi = 0; yi < uniqueY.length - 1; yi++) {
        final cell = Rect.fromLTRB(
          uniqueX[xi],
          uniqueY[yi],
          uniqueX[xi + 1],
          uniqueY[yi + 1],
        );
        if (cell.width <= 50 + 2 * profileThickness ||
            cell.height <= 50 + 2 * profileThickness ||
            !cell.contains(start) ||
            !cell.contains(drawnRect.center)) {
          continue;
        }

        final occupied = frameRects.any(
          (frame) => frame.deflate(1.0).overlaps(cell.deflate(1.0)),
        );
        if (occupied) continue;

        final overlap = _rectOverlapArea(cell, drawnRect);
        if (overlap > bestOverlap) {
          best = cell;
          bestOverlap = overlap;
        }
      }
    }

    return best;
  }

  void setMullionFrameSection(
    MullionProfileType type,
    Map<String, dynamic> section,
  ) {
    if (selection.type != SelectionType.mullion ||
        selection.mullionPosition == null) {
      return;
    }
    if (type == MullionProfileType.standard) {
      setMullionProfile(type);
      return;
    }

    _saveSnapshot();
    final isHorizontal = selection.isHorizontalMullion!;
    final position = selection.mullionPosition!;

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

    final selected = Map<String, dynamic>.from(section);
    selected['mullion_profile_type'] = type.name;
    selected['is_double_frame'] = type == MullionProfileType.flat;

    final previousGap = maximumMullionThickness;
    final wasDoubleFrame = {
      for (final pos in collinearPositions)
        pos: isDoubleFrameMullionAt(isHorizontal, pos),
    };
    for (final pos in collinearPositions) {
      final key = _mullionKey(isHorizontal, pos);
      mullionProfiles[key] = type;
      mullionSectionOverrides[key] = Map<String, dynamic>.from(selected);
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

  /// حذف الإطار المحدد حالياً وسد الفراغ تلقائياً مع تحديث أبعاد النافذة
  void deleteSelectedFrame() {
    final groups = _frameZoneGroups();
    final rects = getFrameRects();
    if (groups.isEmpty || rects.isEmpty) return;

    int? targetIndex;
    if (selection.type == SelectionType.frame && selection.zoneId != null) {
      targetIndex = _frameIndexFromSelectionKey(selection.zoneId!);
    }
    if (targetIndex == null && selectedZone != null) {
      for (int i = 0; i < groups.length; i++) {
        if (groups[i].any((z) => z.id == selectedZone!.id)) {
          targetIndex = i;
          break;
        }
      }
    }

    if (targetIndex == null ||
        targetIndex < 0 ||
        targetIndex >= groups.length) {
      return;
    }

    _saveSnapshot();

    // إذا كان الإطار الوحيد، يتم تصفير كل شيء
    if (groups.length == 1) {
      clearAll();
      _notifyModelListeners();
      return;
    }

    final deletedFrameRect = rects[targetIndex];
    final deletedZones = groups[targetIndex];
    final deletedZoneIds = deletedZones.map((z) => z.id).toSet();

    // حذف مناطق الإطار المحدد
    zones.removeWhere((z) => deletedZoneIds.contains(z.id));

    // حساب إزاحة الإطارات المتبقية على اليمين لسد الفراغ
    final double shiftX = deletedFrameRect.width;

    // الإطارات الواقعة على يمين الإطار المحذوف تُزاح لليسار
    for (int i = 0; i < groups.length; i++) {
      if (i == targetIndex) continue;
      final otherRect = rects[i];
      if (otherRect.left >= deletedFrameRect.right - 2.0) {
        for (final z in groups[i]) {
          z.boundary = z.boundary.shift(Offset(-shiftX, 0));
        }
      }
    }

    // إذا كان الإطار المحذوف هو الأول وكان باقي الإطارات مزاحة، نعيد محاذاة البداية
    double minLeft = double.infinity;
    for (final z in zones) {
      if (z.boundary.left < minLeft) minLeft = z.boundary.left;
    }
    if (minLeft != double.infinity && minLeft > profileThickness + 1.0) {
      final double correction = minLeft - profileThickness;
      for (final z in zones) {
        z.boundary = z.boundary.shift(Offset(-correction, 0));
      }
    }

    // تحديث العرض والارتفاع الكلي
    double maxRight = 200.0;
    double maxBottom = 200.0;
    for (final z in zones) {
      if (z.boundary.right + profileThickness > maxRight) {
        maxRight = z.boundary.right + profileThickness;
      }
      if (z.boundary.bottom + profileThickness > maxBottom) {
        maxBottom = z.boundary.bottom + profileThickness;
      }
    }
    width = maxRight;
    height = maxBottom;
    synchronizeShutterAfterFrameResize(0, 0);

    selection = SelectionInfo.none;
    showZoneMenu = false;
    _notifyModelListeners();
  }

  double _intraFrameGapForZones(
    WindowZone first,
    WindowZone second, {
    required bool horizontal,
  }) {
    late final double firstEdge;
    late final double secondEdge;
    if (horizontal) {
      final forward = (first.boundary.bottom - second.boundary.top).abs();
      final reverse = (second.boundary.bottom - first.boundary.top).abs();
      firstEdge = forward <= reverse
          ? first.boundary.bottom
          : first.boundary.top;
      secondEdge = forward <= reverse
          ? second.boundary.top
          : second.boundary.bottom;
    } else {
      final forward = (first.boundary.right - second.boundary.left).abs();
      final reverse = (second.boundary.right - first.boundary.left).abs();
      firstEdge = forward <= reverse
          ? first.boundary.right
          : first.boundary.left;
      secondEdge = forward <= reverse
          ? second.boundary.left
          : second.boundary.right;
    }
    final position = (firstEdge + secondEdge) / 2.0;
    final prefix = horizontal ? 'H_' : 'V_';
    bool hasRecordedMullion(Iterable<String> keys) {
      for (final key in keys) {
        if (!key.startsWith(prefix)) continue;
        final stored = double.tryParse(key.substring(2));
        if (stored != null && (stored - position).abs() <= 6.0) return true;
      }
      return false;
    }

    final recorded =
        hasRecordedMullion(mullionCreationOrder.keys) ||
        hasRecordedMullion(mullionProfiles.keys) ||
        hasRecordedMullion(mullionSectionOverrides.keys);
    if (!recorded) return mullionThickness + 4.0;
    final width = isDoubleFrameMullionAt(horizontal, position)
        ? frameProfileWidthAt(horizontal, position) * 2.0
        : math.max(
            mullionThickness,
            _sectionVisibleWidth(
              effectiveMullionSectionAt(horizontal, position),
            ),
          );
    return width + 4.0;
  }

  /// Whether a frame without a sliding sash has at least one division. A
  /// sliding series has no mullions, so such a frame is an opening frame
  /// even while its panes are still fixed glass.
  bool get hasDividedOpeningFrame => _frameZoneGroups().any(
    (group) =>
        group.length > 1 &&
        !group.any((zone) => zone.content == ZoneContent.slidingSash),
  );

  List<List<WindowZone>> _frameZoneGroups() {
    final List<List<WindowZone>> groups = [];
    // Threshold for two zones belonging to the same physical frame:
    // An internal mullion gap ≈ mullionThickness (one profile, ~45 mm).
    // Two *separate* frames have a gap ≈ profileThickness × 2 (~90 mm).
    // Using mullionThickness + a small tolerance keeps them distinct even
    // after floating-point rounding during save/reload.
    bool zonesAreAdjacent(WindowZone first, WindowZone second) {
      final verticalGap = math.min(
        (first.boundary.right - second.boundary.left).abs(),
        (second.boundary.right - first.boundary.left).abs(),
      );
      final verticalTouch =
          verticalGap <=
          _intraFrameGapForZones(first, second, horizontal: false);
      if (verticalTouch) {
        final overlapTop = math.max(first.boundary.top, second.boundary.top);
        final overlapBottom = math.min(
          first.boundary.bottom,
          second.boundary.bottom,
        );
        if (overlapTop < overlapBottom - 5.0) return true;
      }

      final horizontalGap = math.min(
        (first.boundary.bottom - second.boundary.top).abs(),
        (second.boundary.bottom - first.boundary.top).abs(),
      );
      final horizontalTouch =
          horizontalGap <=
          _intraFrameGapForZones(first, second, horizontal: true);
      if (horizontalTouch) {
        final overlapLeft = math.max(first.boundary.left, second.boundary.left);
        final overlapRight = math.min(
          first.boundary.right,
          second.boundary.right,
        );
        if (overlapLeft < overlapRight - 5.0) return true;
      }
      return false;
    }

    for (final zone in zones) {
      final List<int> connectedGroupIndices = [];
      for (int i = 0; i < groups.length; i++) {
        bool isConnected = false;
        for (final other in groups[i]) {
          if (zonesAreAdjacent(zone, other)) {
            isConnected = true;
            break;
          }
        }
        // A partially visited grid is often L-shaped. Rejecting it before
        // visiting the remaining panes splits one real frame into several.
        // Connectivity uses the physical double-frame gap above, so coupled
        // frames remain separate without an area test on partial groups.
        if (isConnected) {
          connectedGroupIndices.add(i);
        }
      }

      if (connectedGroupIndices.isEmpty) {
        groups.add([zone]);
      } else {
        final List<WindowZone> mergedGroup = [zone];
        connectedGroupIndices.sort((a, b) => b.compareTo(a));
        for (final idx in connectedGroupIndices) {
          mergedGroup.addAll(groups[idx]);
          groups.removeAt(idx);
        }
        groups.add(mergedGroup);
      }
    }

    return groups;
  }

  List<Rect> getFrameRects() {
    final groups = _frameZoneGroups();

    final List<Rect> rects = [];
    final double t = profileThickness;
    for (final group in groups) {
      double minL = group[0].boundary.left;
      double maxR = group[0].boundary.right;
      double minT = group[0].boundary.top;
      double maxB = group[0].boundary.bottom;

      for (final z in group) {
        if (z.boundary.left < minL) minL = z.boundary.left;
        if (z.boundary.right > maxR) maxR = z.boundary.right;
        if (z.boundary.top < minT) minT = z.boundary.top;
        if (z.boundary.bottom > maxB) maxB = z.boundary.bottom;
      }

      rects.add(Rect.fromLTRB(minL - t, minT - t, maxR + t, maxB + t));
    }

    if (coupleFrames && rects.length > 1) {
      // إزالة أي فراغ بين الكوادر المقترنة بجعلها ملتصقة تماماً
      // أو ترك فاصل يعادل عرض بروفيل الزاوية (تيبيكاري) إن كانت هناك وصلة زاوية مفعّلة
      rects.sort((a, b) {
        final cmp = a.left.compareTo(b.left);
        return cmp != 0 ? cmp : a.top.compareTo(b.top);
      });
      for (int i = 0; i < rects.length; i++) {
        for (int j = i + 1; j < rects.length; j++) {
          final r1 = rects[i];
          final r2 = rects[j];
          final vOverlap =
              math.min(r1.bottom, r2.bottom) - math.max(r1.top, r2.top);
          final maxGap = math.max(80.0, profileThickness * 2 + 10.0);
          if (vOverlap > 10.0) {
            final hasIntermediate = rects.asMap().entries.any((entry) {
              final idx = entry.key;
              if (idx == i || idx == j) return false;
              final r = entry.value;
              final minRight = math.min(r1.right, r2.right);
              final maxLeft = math.max(r1.left, r2.left);
              return r.left >= minRight - 5.0 &&
                  r.right <= maxLeft + 5.0 &&
                  math.min(r.bottom, math.min(r1.bottom, r2.bottom)) >
                      math.max(r.top, math.max(r1.top, r2.top)) + 10.0;
            });
            if (!hasIntermediate && (r2.left - r1.right).abs() <= maxGap) {
              // Profile-angle tube sits BEHIND the corner (90° perpendicular).
              // It does NOT occupy space between the frames in the same plane —
              // frames touch at the same X coordinate without any gap.
              final commonX = (r1.right + r2.left) / 2.0;
              rects[i] = Rect.fromLTRB(r1.left, r1.top, commonX, r1.bottom);
              rects[j] = Rect.fromLTRB(commonX, r2.top, r2.right, r2.bottom);
            }
          }
          final hOverlap =
              math.min(r1.right, r2.right) - math.max(r1.left, r2.left);
          if (hOverlap > 10.0) {
            if ((r2.top - r1.bottom).abs() <= maxGap) {
              final commonY = (r1.bottom + r2.top) / 2.0;
              rects[i] = Rect.fromLTRB(r1.left, r1.top, r1.right, commonY);
              rects[j] = Rect.fromLTRB(r2.left, commonY, r2.right, r2.bottom);
            } else if ((r1.top - r2.bottom).abs() <= maxGap) {
              final commonY = (r2.bottom + r1.top) / 2.0;
              rects[j] = Rect.fromLTRB(r2.left, r2.top, r2.right, commonY);
              rects[i] = Rect.fromLTRB(r1.left, commonY, r1.right, r1.bottom);
            }
          }
        }
      }
    }

    return rects;
  }

  /// Returns structured information about each physical outer frame,
  /// including its bounding Rect, its constituent WindowZones, and its primary zone ID.
  List<PhysicalFrameInfo> getPhysicalFrameInfos() {
    final groups = _frameZoneGroups();
    final rects = getFrameRects();
    final count = math.min(groups.length, rects.length);
    if (count == 0 && width > 0 && height > 0) {
      return [
        PhysicalFrameInfo(
          index: 0,
          rect: Rect.fromLTWH(0, 0, width, height),
          zones: const [],
        ),
      ];
    }
    return List.generate(count, (i) {
      return PhysicalFrameInfo(index: i, rect: rects[i], zones: groups[i]);
    });
  }

  /// Returns only the outside perimeter of the physical frames.
  ///
  /// A single global rectangle is incorrect when one frame is above only
  /// part of another row: it creates a cover across the empty area. Shared
  /// edges are therefore removed and touching collinear edges are joined.
  /// The outer edges of a multi-frame drawing. [includeSide] drops the
  /// sides of some frames (those without a cover, for example) before
  /// neighbouring edges are joined, so a cover never runs on past its frame.
  List<FrameEdgeSegment> getExposedFrameEdgeSegments({
    bool Function(Rect frame, String side)? includeSide,
  }) {
    final rects = getFrameRects();
    if (rects.length <= 1) return const <FrameEdgeSegment>[];

    // Adjacent frames can differ by a few logical pixels after proportional
    // layout/rounding. Treat that seam as shared so no cover or visual gap is
    // produced between the frames.
    const tolerance = 5.0;
    final maxJunctionGap = math.max(100.0, profileAngleTubeWidth + 20.0);
    final raw = <FrameEdgeSegment>[];

    void addVisiblePieces({
      required String side,
      required double start,
      required double end,
      required double coordinate,
      required List<List<double>> blockers,
      Rect? frameRect,
    }) {
      if (includeSide != null &&
          frameRect != null &&
          !includeSide(frameRect, side)) {
        return;
      }
      var pieces = <List<double>>[
        [start, end],
      ];
      for (final blocker in blockers) {
        final next = <List<double>>[];
        for (final piece in pieces) {
          final overlapStart = math.max(piece[0], blocker[0]);
          final overlapEnd = math.min(piece[1], blocker[1]);
          if (overlapEnd <= overlapStart + tolerance) {
            next.add(piece);
            continue;
          }
          if (piece[0] < overlapStart - tolerance) {
            next.add([piece[0], overlapStart]);
          }
          if (overlapEnd < piece[1] - tolerance) {
            next.add([overlapEnd, piece[1]]);
          }
        }
        pieces = next;
        if (pieces.isEmpty) break;
      }
      for (final piece in pieces) {
        if (piece[1] > piece[0] + tolerance) {
          raw.add(
            FrameEdgeSegment(
              side: side,
              start: piece[0],
              end: piece[1],
              coordinate: coordinate,
              frameRect: frameRect,
            ),
          );
        }
      }
    }

    for (var index = 0; index < rects.length; index++) {
      final rect = rects[index];
      final others = [
        for (var otherIndex = 0; otherIndex < rects.length; otherIndex++)
          if (otherIndex != index) rects[otherIndex],
      ];

      addVisiblePieces(
        side: 'top',
        start: rect.left,
        end: rect.right,
        coordinate: rect.top,
        frameRect: rect,
        blockers: [
          for (final other in others)
            if (rect.top - other.bottom >= -tolerance &&
                rect.top - other.bottom <= maxJunctionGap &&
                math.min(rect.right, other.right) >
                    math.max(rect.left, other.left) + tolerance)
              [
                math.max(rect.left, other.left),
                math.min(rect.right, other.right),
              ],
        ],
      );
      addVisiblePieces(
        side: 'bottom',
        start: rect.left,
        end: rect.right,
        coordinate: rect.bottom,
        frameRect: rect,
        blockers: [
          for (final other in others)
            if (other.top - rect.bottom >= -tolerance &&
                other.top - rect.bottom <= maxJunctionGap &&
                math.min(rect.right, other.right) >
                    math.max(rect.left, other.left) + tolerance)
              [
                math.max(rect.left, other.left),
                math.min(rect.right, other.right),
              ],
        ],
      );
      addVisiblePieces(
        side: 'left',
        start: rect.top,
        end: rect.bottom,
        coordinate: rect.left,
        frameRect: rect,
        blockers: [
          for (final other in others)
            if (rect.left - other.right >= -tolerance &&
                rect.left - other.right <= maxJunctionGap &&
                math.min(rect.bottom, other.bottom) >
                    math.max(rect.top, other.top) + tolerance)
              [
                math.max(rect.top, other.top),
                math.min(rect.bottom, other.bottom),
              ],
        ],
      );
      addVisiblePieces(
        side: 'right',
        start: rect.top,
        end: rect.bottom,
        coordinate: rect.right,
        frameRect: rect,
        blockers: [
          for (final other in others)
            if (other.left - rect.right >= -tolerance &&
                other.left - rect.right <= maxJunctionGap &&
                math.min(rect.bottom, other.bottom) >
                    math.max(rect.top, other.top) + tolerance)
              [
                math.max(rect.top, other.top),
                math.min(rect.bottom, other.bottom),
              ],
        ],
      );
    }

    raw.sort((a, b) {
      final sideCompare = a.side.compareTo(b.side);
      if (sideCompare != 0) return sideCompare;
      final coordinateCompare = a.coordinate.compareTo(b.coordinate);
      if (coordinateCompare != 0) return coordinateCompare;
      return a.start.compareTo(b.start);
    });

    final merged = <FrameEdgeSegment>[];
    for (final segment in raw) {
      if (merged.isNotEmpty) {
        final previous = merged.last;
        if (previous.side == segment.side &&
            (previous.coordinate - segment.coordinate).abs() <= tolerance &&
            segment.start <= previous.end + tolerance) {
          merged[merged.length - 1] = FrameEdgeSegment(
            side: previous.side,
            start: previous.start,
            end: math.max(previous.end, segment.end),
            coordinate: previous.coordinate,
            frameRect: previous.frameRect ?? segment.frameRect,
          );
          continue;
        }
      }
      merged.add(segment);
    }
    return merged;
  }
}
