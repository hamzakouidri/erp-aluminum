part of '../model.dart';

/// Sliding leaves, tracks, montants and chicanes of [WindowModel].
extension WindowModelSliding on WindowModel {
  /// In mixed drawings, the opening series owns the frame only when the
  /// drawing actually contains an opening sash. A sliding-only drawing may
  /// still contain fixed-glass or empty zones; those zones must not make the
  /// resolver borrow an opening frame or sash.
  bool get usesSlidingPrimaryProfiles {
    final hasSlidingZone = zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasEmptyOrFixed = zones.any(
      (zone) =>
          zone.content == ZoneContent.empty ||
          zone.content == ZoneContent.fixedGlass,
    );
    final hasOpeningSash = zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    if (systemMode == 'sliding') {
      if (hasSlidingZone && hasEmptyOrFixed && activeSeries != null) {
        return false;
      }
      return true;
    }
    if (systemMode != 'mixed') {
      return activeSlidingSeries != null && activeSeries == null;
    }

    if (hasSlidingZone && (hasOpeningSash || hasEmptyOrFixed)) return false;
    if (hasSlidingZone && !hasOpeningSash && !hasEmptyOrFixed) return true;
    if (hasOpeningSash && !hasSlidingZone) return false;
    return activeSlidingSeries != null && activeSeries == null;
  }

  /// Keeps the rail metadata entered in the series-role editor on the actual
  /// selected frame map. [AluminumSection] intentionally contains only the
  /// physical section fields, so converting it with `toMap()` used to discard
  /// `track_count` / `track_mode`; every frame then looked like the default
  /// two-rail base to the calculator.
  Map<String, dynamic> _slidingFrameMapWithRoleOptions(
    AluminumSection section,
    AluminumSeries series,
  ) {
    final result = section.toMap();
    final options = _seriesDesignRoleOptions[series.id]?['frame']?[section.id];
    if (options == null) return result;
    const optionKeys = <String>[
      'track_count',
      'track_mode',
      'supported_track_counts',
      'design_track_count',
      'design_track_mode',
      'design_supported_track_counts',
    ];
    for (final key in optionKeys) {
      final value = options[key];
      if (value == null) continue;
      final designKey = key.startsWith('design_') ? key : 'design_$key';
      result[designKey] = value;
    }
    return result;
  }

  int _requestedSlidingTrackCount() {
    var result = 2;
    for (final zone in zones) {
      if (zone.content != ZoneContent.slidingSash) continue;
      result = math.max(result, zone.slidingTrackCount.clamp(2, 7).toInt());
    }
    return result;
  }

  /// Prefer a complete frame explicitly configured for the requested rails.
  /// If the series has no such frame, retain the normal base-frame choice so
  /// the configured Complément dormant can add the missing rails.
  AluminumSection _preferredSlidingFrameForTrackCount(
    List<AluminumSection> frames,
    AluminumSeries series,
    int trackCount,
  ) {
    if (frames.length <= 1) return frames.first;
    final target = trackCount.clamp(2, 7).toInt();
    final exactComplete = frames.where((section) {
      final options =
          _seriesDesignRoleOptions[series.id]?['frame']?[section.id];
      final mode = options?['track_mode']?.toString().toLowerCase() ?? '';
      final rawCount = options?['track_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      return mode == 'complete' && count == target;
    }).toList();
    if (exactComplete.isNotEmpty) {
      return _preferredFrameForSeries(exactComplete, series);
    }
    return _preferredFrameForSeries(frames, series);
  }

  String? slidingSeriesFamily({AluminumSeries? series}) {
    final source =
        series ??
        (systemMode == 'sliding' || usesSlidingPrimaryProfiles
            ? activeSlidingSeries
            : activeSeries);
    if (source == null) return null;
    final label = '${source.name} ${source.type}'.toLowerCase();
    if (label.contains('67000') ||
        label.contains('67 mil') ||
        label.contains('67m') ||
        label.contains('67 m') ||
        RegExp(r'(^|[^0-9])67([^0-9]|$)').hasMatch(label)) {
      return '67';
    }
    if (label.contains('40000') ||
        label.contains('40 mil') ||
        label.contains('40m') ||
        label.contains('40 m') ||
        RegExp(r'(^|[^0-9])40([^0-9]|$)').hasMatch(label)) {
      return '40';
    }
    if (label.contains('h36') ||
        label.contains('h 36') ||
        label.contains('hps') ||
        RegExp(r'(^|[^0-9])36([^0-9]|$)').hasMatch(label)) {
      return 'h36';
    }
    // TPR is a named sliding family in the catalogue (not a numeric
    // millimetre series). Keep it in the same family resolver so all
    // quantity/cost component rules can select it consistently.
    if (label.contains('tpr') || label.contains('tpi')) return 'tpr';
    return null;
  }

  bool get isSliding67Family => slidingSeriesFamily() == '67';

  bool get isSliding40Family => slidingSeriesFamily() == '40';

  bool get isSlidingH36Family => slidingSeriesFamily() == 'h36';

  int? _slidingTrackCountFromFrame(Map<String, dynamic> frame) {
    final configured = frame['design_track_count'] ?? frame['track_count'];
    final configuredCount = configured is num
        ? configured.toInt()
        : int.tryParse(configured?.toString() ?? '');
    if (configuredCount != null && configuredCount >= 2) {
      return configuredCount.clamp(2, 7).toInt();
    }
    final label =
        '${frame['name'] ?? ''} ${frame['type'] ?? ''} '
                '${frame['code'] ?? ''}'
            .toLowerCase()
            .replaceAll(RegExp(r'[_-]+'), ' ');

    bool mentions(int count) {
      return RegExp(
        '(^|[^0-9])$count\\s*(?:rail+l?s?|rails?|voies?|tracks?|سكك|سكة)',
        caseSensitive: false,
      ).hasMatch(label);
    }

    if (mentions(5)) return 5;
    if (mentions(4)) return 4;
    if (mentions(3)) return 3;
    if (mentions(2)) return 2;
    return null;
  }

  void _synchronizeSlidingSashesWithFrameTracks(Map<String, dynamic> frame) {
    final trackCount = _slidingTrackCountFromFrame(frame);
    if (trackCount == null) return;

    var updated = false;
    final isCompleteFrame =
        frame['design_track_mode']?.toString().toLowerCase() == 'complete';
    for (final zone in zones) {
      if (zone.content == ZoneContent.slidingSash) {
        zone.slidingTrackCount = trackCount;
        if (isCompleteFrame || zone.slidingSashesCount < trackCount) {
          zone.slidingSashesCount = trackCount.clamp(2, 7).toInt();
        }
        updated = true;
      }
    }

    // Selecting a complete multi-rail frame is also an explicit drawing
    // choice. If the current drawing has not yet been made sliding, promote
    // the selected zone (or the sole zone) immediately to the matching sash
    // count so a 3-rail frame visibly becomes a 3-sash drawing.
    if (!updated) {
      final target = selectedZone ?? (zones.length == 1 ? zones.first : null);
      if (target != null) {
        target.content = ZoneContent.slidingSash;
        target.slidingTrackCount = trackCount;
        // A complete N-rail frame starts with an intuitive N-leaf drawing,
        // but the user can then change leaves and rails independently.
        target.slidingSashesCount = trackCount.clamp(2, 7).toInt();
        target.innerH = 0;
        target.innerV = 0;
        target.rightInnerH = 0;
        target.rightInnerV = 0;
        target.openDirection = OpenDirection.right;
      }
    }
  }

  bool isSlidingMontantReinforced(
    Map<String, dynamic> profile, {
    required bool central,
  }) {
    final code = (profile['code'] ?? '').toString().trim().toLowerCase();
    final name = (profile['name'] ?? '').toString().toLowerCase();
    final type = (profile['type'] ?? '').toString().toLowerCase();
    final description = '$name $type';
    if (description.contains('غير معزز') ||
        description.contains('غير معزّز') ||
        RegExp(r'(non|sans)[\s-]*renfor').hasMatch(description) ||
        description.contains('not reinforced') ||
        description.contains('unreinforced')) {
      return false;
    }
    if (code.endsWith(central ? '107' : '108') ||
        code.replaceAll(' ', '').endsWith(central ? '107' : '108') ||
        name.contains('معزز') ||
        name.contains('renforc') ||
        type.contains('renforc')) {
      return true;
    }
    final role = (profile['design_role_key'] ?? '').toString();
    if (role == 'sash_central_reinforced' ||
        role == 'sash_lateral_reinforced' ||
        role == 'chicane_renforcee') {
      return true;
    }
    if (role == 'sash_central' || role == 'sash_lateral') return false;
    // In series where the chicane itself acts as the central montant reinforcement
    if (central &&
        (role == 'chicane' ||
            name.contains('chicane') ||
            type.contains('chicane') ||
            name.contains('شيكان') ||
            type.contains('شيكان'))) {
      return true;
    }
    return false;
  }

  void applySlidingMontantOverride(
    Map<String, dynamic> profile, {
    required bool central,
    bool? reinforced,
    bool manualSelection = false,
    bool updateAllMembers = true,
  }) {
    final mutable = Map<String, dynamic>.from(profile);
    if (manualSelection) {
      mutable['manual_selection'] = true;
      mutable['user_selected'] = true;
    }

    // PVC never uses a reinforced sliding montant, including when a drawing
    // loaded from an older version still contains the old reinforcement flag.
    final isReinforced =
        !isSlidingPVC &&
        (reinforced ?? isSlidingMontantReinforced(mutable, central: central));

    for (final zone in zones) {
      if (!updateAllMembers) break;
      if (zone.content != ZoneContent.slidingSash) continue;
      zone.slidingMontantReinforced = Map<String, bool>.from(
        zone.slidingMontantReinforced,
      );
      final sashes = zone.slidingSashesCount > 0 ? zone.slidingSashesCount : 2;
      final bool hasMeetingInCenter =
          zone.slidingFaceToFace &&
          isSlidingFaceToFaceLayout(
            trackCount: zone.slidingTrackCount,
            sashCount: sashes,
          );
      if (central) {
        final centralCount = hasMeetingInCenter
            ? (sashes == 4 ? 4 : 8)
            : math.max(0, (sashes * 2) - 2);
        for (var index = 0; index < centralCount; index++) {
          zone.slidingMontantReinforced['central_$index'] = isReinforced;
        }
      } else {
        final lateralCount = hasMeetingInCenter ? 4 : 2;
        for (var index = 0; index < lateralCount; index++) {
          zone.slidingMontantReinforced['lateral_$index'] = isReinforced;
        }
      }
    }

    if (central) {
      if (updateAllMembers) {
        componentOverrides.remove('قائم وسطي (Sash Central)');
        componentOverrides.remove('قائم وسطي معزز (Sash Central Renforcé)');
      }
      componentOverrides.remove('قائم وسطي (Central)');
      componentOverrides[isReinforced
              ? 'قائم وسطي معزز (Sash Central Renforcé)'
              : 'قائم وسطي (Sash Central)'] =
          mutable;
    } else {
      if (updateAllMembers) {
        componentOverrides.remove('قائم جانبي (Sash Lateral)');
        componentOverrides.remove('قائم جانبي معزز (Sash Lateral Renforcé)');
      }
      componentOverrides.remove('قائم جانبي (Lateral)');
      componentOverrides[isReinforced
              ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
              : 'قائم جانبي (Sash Lateral)'] =
          mutable;
    }
    _notifyModelListeners();
  }

  bool isSlidingMontantCandidate(
    Map<String, dynamic> item, {
    required bool central,
  }) {
    if (isSlidingMontantSlimCandidate(item)) {
      return false;
    }
    final role = (item['design_role_key'] ?? '').toString();
    final name = (item['name'] ?? '').toString().toLowerCase();
    final type = (item['type'] ?? '').toString().toLowerCase();
    if (role == 'face_to_face' ||
        type == 'face_to_face' ||
        name.contains('face to face') ||
        name.contains('face-to-face')) {
      return false;
    }
    if (role.isNotEmpty) {
      return central
          ? const [
              'sash_central',
              'sash_central_reinforced',
              'central',
              'chicane',
              'chicane_renforcee',
            ].contains(role)
          : const [
              'sash_lateral',
              'sash_lateral_reinforced',
              'lateral',
            ].contains(role);
    }
    final isOpeningSash =
        type.contains('ouvrant') ||
        type.contains('opening') ||
        name.contains('ouvrant') ||
        name.contains('opening');
    if (isOpeningSash &&
        !type.contains('sliding') &&
        !name.contains('coulissant') &&
        !name.contains('منزلق')) {
      return false;
    }

    final series = effectiveSlidingSeries;
    if (series != null) {
      final rawId = item['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id != null) {
        final centralRoles = [
          'sash_central',
          'sash_central_reinforced',
          'central',
          'chicane',
          'chicane_renforcee',
        ];
        final lateralRoles = [
          'sash_lateral',
          'sash_lateral_reinforced',
          'lateral',
        ];
        final inCentralRole = centralRoles.any(
          (r) => (_seriesDesignRoleSectionIds[series.id]?[r] ?? const <int>{})
              .contains(id),
        );
        final inLateralRole = lateralRoles.any(
          (r) => (_seriesDesignRoleSectionIds[series.id]?[r] ?? const <int>{})
              .contains(id),
        );
        if (central && inCentralRole) return true;
        if (!central && inLateralRole) return true;
        if (central && inLateralRole) return false;
        if (!central && inCentralRole) return false;
      }
    }

    final code = (item['code'] ?? '').toString().trim().toLowerCase();
    if (central) {
      return type.contains('central') ||
          type.contains('وسطي') ||
          name.contains('central') ||
          name.contains('وسطي') ||
          type.contains('chicane') ||
          name.contains('chicane') ||
          name.contains('شيكان') ||
          type.contains('شيكان') ||
          code.endsWith('105') ||
          code.endsWith('107');
    }
    return type.contains('lateral') ||
        type.contains('جانبي') ||
        name.contains('lateral') ||
        name.contains('جانبي') ||
        code.endsWith('104') ||
        code.endsWith('108');
  }

  bool isSlidingMontantSlimCandidate(Map<String, dynamic> profile) {
    final role =
        (profile['design_role_key'] ??
                profile['roleKey'] ??
                profile['role_key'] ??
                '')
            .toString()
            .toLowerCase();
    if (role == 'montant_central_slim' ||
        role == 'sash_central_slim' ||
        role == 'montant_slim') {
      return true;
    }
    final code = (profile['code'] ?? '').toString().trim().toLowerCase();
    final name = (profile['name'] ?? '').toString().toLowerCase();
    final type = (profile['type'] ?? '').toString().toLowerCase();
    final description = '$name $type $code';
    return description.contains('slim') || description.contains('سليم');
  }

  List<Map<String, dynamic>> getSlidingSlimCandidates() {
    // The role assignment is authoritative. A Slim profile is often stored
    // with the ordinary central-montant type/name, so name matching alone
    // makes it disappear from the drawing and the BOM.
    final configured = getConfiguredSectionsForRole(
      'montant_central_slim',
      useSlidingSeries: true,
    );
    if (configured.isNotEmpty) {
      return configured.map((section) => section.toMap()).toList();
    }
    final sections = (activeSlidingSeries ?? activeSeries)?.sections ?? [];
    return sections
        .map((s) => s.toMap())
        .where((m) => isSlidingMontantSlimCandidate(m))
        .toList();
  }

  Map<String, dynamic>? get selectedSlimMontantProfile {
    if (!hasActiveSlidingMontantSlim) return null;
    final override = componentOverrides['قائم وسطي سليم (Montant Slim)'];
    if (override is Map<String, dynamic>) return override;
    if (override is Map) return Map<String, dynamic>.from(override);
    final candidates = getSlidingSlimCandidates();
    return candidates.isNotEmpty ? candidates.first : null;
  }

  bool get hasActiveSlidingMontantSlim => zones.any((zone) {
    if (zone.content != ZoneContent.slidingSash) return false;
    return slidingCentralEdgeKeys(
      zone: zone,
      sashesCount: zone.slidingSashesCount,
    ).any((key) => zone.slidingMontantSlim[key] == true);
  });

  void clearSlidingMontantSlimOverrideIfInactive() {
    // Old drawings and leaf-count changes may leave obsolete central keys in
    // the map. They are invisible on canvas but used to keep Slim alive in
    // the BOM after the user had unchecked every visible edge.
    for (final zone in zones) {
      final activeKeys = zone.content == ZoneContent.slidingSash
          ? slidingCentralEdgeKeys(
              zone: zone,
              sashesCount: zone.slidingSashesCount,
            ).toSet()
          : const <String>{};
      zone.slidingMontantSlim.removeWhere(
        (key, _) => !activeKeys.contains(key),
      );
    }
    if (hasActiveSlidingMontantSlim) return;
    componentOverrides.remove('قائم وسطي سليم (Montant Slim)');
    componentOverrides.remove('قائم وسطي سليم (Sash Central Slim)');
    _notifyModelListeners();
  }

  void applySlidingMontantSlimOverride(
    Map<String, dynamic> profile, {
    bool manualSelection = false,
  }) {
    final mutable = Map<String, dynamic>.from(profile);
    if (manualSelection) {
      mutable['manual_selection'] = true;
      mutable['user_selected'] = true;
    }
    componentOverrides['قائم وسطي سليم (Montant Slim)'] = mutable;
    _notifyModelListeners();
  }

  /// Material of a sliding zone.  This must stay independent from [isPVC]
  /// because a mixed drawing has two independently selected series.
  bool get isSlidingPVC => _isPvcSeries(
    systemMode == 'sliding' || usesSlidingPrimaryProfiles
        ? activeSlidingSeries
        : activeSeries,
  );

  bool isSlidingZoneNestedInSingleFrame(WindowZone zone) {
    if (systemMode == 'sliding') return false;
    if (zones.length <= 1) return false;
    if (!zones.any((candidate) => candidate.id == zone.id)) return false;
    return getFrameRects().length == 1;
  }

  bool shouldAskSlidingRebateCut(WindowZone zone) {
    return isSlidingZoneNestedInSingleFrame(zone);
  }

  int slidingRebateSideCount(WindowZone zone, {required bool horizontal}) {
    if (!zone.cutSlidingGlassRebate) return 0;
    if (!isSlidingZoneNestedInSingleFrame(zone)) return 0;
    if (openingSashOverlap <= 0) return 0;

    const tolerance = 3.0;
    final outerClear = _outerClearRectForRebate();
    final boundary = zone.boundary;
    var count = 0;

    if (horizontal) {
      final hasLeft =
          (boundary.left - outerClear.left).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: true,
            negativeSide: true,
          );
      final hasRight =
          (boundary.right - outerClear.right).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: true,
            negativeSide: false,
          );
      if (hasLeft) count++;
      if (hasRight) count++;
    } else {
      final hasTop =
          (boundary.top - outerClear.top).abs() <= tolerance ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: false,
            negativeSide: true,
          );
      final hasBottom =
          ((hasBottomFrame || hasFramePlintheBottom) &&
              (boundary.bottom - outerClear.bottom).abs() <= tolerance) ||
          _zoneEdgeTouchesAnotherZone(
            zone,
            verticalEdge: false,
            negativeSide: false,
          );
      if (hasTop) count++;
      if (hasBottom) count++;
    }
    return count;
  }

  double slidingRebateDeduction(WindowZone zone, {required bool horizontal}) {
    return openingSashOverlap *
        slidingRebateSideCount(zone, horizontal: horizontal);
  }

  List<AluminumSection> get availableInternalSlidingSideCovers {
    final series = activeSlidingSeries;
    if (series == null) return const <AluminumSection>[];
    return series.sections.where(_sectionIsSideCover).toList();
  }

  Map<String, dynamic>? get effectiveInternalSlidingSideCoverMap {
    if (selectedInternalSlidingSideCover != null) {
      return selectedInternalSlidingSideCover!.toMap();
    }
    return internalSlidingSideCoverOverride;
  }

  double get internalSlidingSideCoverWidth {
    final selected = selectedInternalSlidingSideCover;
    if (selected != null) {
      if (selected.couvreJointWidth > 0) return selected.couvreJointWidth;
      if (selected.visibleWidth > 0) return selected.visibleWidth;
    }

    final override = internalSlidingSideCoverOverride;
    if (override == null) return 0.0;
    for (final key in const ['couvre_joint_width', 'visible_width']) {
      final value = override[key];
      if (value is num && value > 0) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0.0;
  }

  void _selectDefaultInternalSlidingSideCover() {
    final covers = availableInternalSlidingSideCovers;
    if (covers.isEmpty) return;
    final currentId = internalSlidingSideCoverOverride?['id']?.toString();
    final selected = currentId == null
        ? covers.first
        : covers.firstWhere(
            (cover) => cover.id.toString() == currentId,
            orElse: () => covers.first,
          );
    selectedInternalSlidingSideCover = selected;
    internalSlidingSideCoverOverride = selected.toMap();
  }

  AluminumSeries? get effectiveSlidingSeries =>
      activeSlidingSeries ??
      (systemMode == 'sliding' || usesSlidingPrimaryProfiles
          ? activeSeries
          : null);

  /// Series-specific total deduction used to calculate the cut width of
  /// sliding leaves.  A value may be entered independently for 2, 3, or 4
  /// leaves; zero keeps the catalogue's legacy formula.
  double slidingSashWidthDeduction(int sashCount) {
    final config = slidingSeriesTableConfig ?? seriesTableConfig;
    final key = switch (sashCount) {
      2 => 'sash_w_deduction_2',
      3 => 'sash_w_deduction_3',
      4 => 'sash_w_deduction_4',
      _ => null,
    };
    if (key == null) return 0.0;
    final value = config?[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Vertical deduction configured for the sliding sash. The database keeps
  /// the legacy column name `sash_overlap_val`, but the series form defines
  /// it as a value deducted from the usable height.
  double slidingSashHeightDeduction() {
    final config = slidingSeriesTableConfig ?? seriesTableConfig;
    final value = config?['sash_overlap_val'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// Looks up a profile exclusively in the selected sliding series.  Do not
  /// use [getSectionByType] for a sliding zone in a mixed drawing: that method
  /// intentionally returns the primary (opening) series when both coexist.
  AluminumSection? getSlidingSectionByType(String type) {
    final series = effectiveSlidingSeries;
    if (series == null) return null;
    final normalizedType = type.toLowerCase();

    if (normalizedType == 'sash') {
      final rawId = slidingSashOverride?['id'];
      final overrideId = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['sash'] ?? const <int>{};
      final overrideIsAllowed =
          overrideId != null &&
          (!_hasLoadedRoleMetadata(series) ||
              (configuredIds.contains(overrideId) &&
                  _configuredSectionMatchesScope(
                    series,
                    'sash',
                    overrideId,
                    sliding: true,
                  )));
      if (overrideIsAllowed) {
        return AluminumSection.fromMap(slidingSashOverride!);
      }
      if (_hasLoadedRoleMetadata(series)) {
        for (final section in series.sections) {
          if (configuredIds.contains(section.id) &&
              _configuredSectionMatchesScope(
                series,
                'sash',
                section.id,
                sliding: true,
              )) {
            return section;
          }
        }
        return null;
      }
    }
    if (normalizedType == 'frame') {
      final base = getSlidingBaseFrameSection();
      if (base != null) return base;
      // A configured sliding series with no frame role must stay empty. Do
      // not select an opening frame merely because its type is also "frame".
      if (_hasLoadedRoleMetadata(series)) return null;
    }

    if (normalizedType == 'sash_lateral_reinforced') {
      final override =
          componentOverrides['قائم جانبي معزز (Sash Lateral Renforcé)'];
      if (override is Map) {
        return AluminumSection.fromMap(Map<String, dynamic>.from(override));
      }
      final configured = getConfiguredSectionForRole(
        'sash_lateral_reinforced',
        useSlidingSeries: true,
      );
      if (configured != null) return configured;
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: false) &&
            isSlidingMontantReinforced(map, central: false)) {
          return section;
        }
      }
      return null;
    }

    if (normalizedType == 'sash_central_reinforced' ||
        normalizedType == 'chicane_renforcee') {
      final override =
          componentOverrides['قائم وسطي معزز (Sash Central Renforcé)'] ??
          componentOverrides['شيكان معزز (Chicane Renforcée)'];
      if (override is Map) {
        return AluminumSection.fromMap(Map<String, dynamic>.from(override));
      }
      final configured =
          getConfiguredSectionForRole(
            'sash_central_reinforced',
            useSlidingSeries: true,
          ) ??
          getConfiguredSectionForRole(
            'chicane_renforcee',
            useSlidingSeries: true,
          );
      if (configured != null) return configured;
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: true) &&
            isSlidingMontantReinforced(map, central: true)) {
          return section;
        }
      }
      return null;
    }

    if (normalizedType == 'sash_lateral' || normalizedType == 'lateral') {
      final override =
          componentOverrides['قائم جانبي (Sash Lateral)'] ??
          componentOverrides['قائم جانبي (Lateral)'];
      if (override is Map) {
        return AluminumSection.fromMap(Map<String, dynamic>.from(override));
      }
      final configured =
          getConfiguredSectionForRole('sash_lateral', useSlidingSeries: true) ??
          getConfiguredSectionForRole('lateral', useSlidingSeries: true);
      if (configured != null &&
          !isSlidingMontantReinforced(configured.toMap(), central: false)) {
        return configured;
      }
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: false) &&
            !isSlidingMontantReinforced(map, central: false)) {
          return section;
        }
      }
      if (configured != null) return configured;
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: false)) {
          return section;
        }
      }
      return null;
    }

    if (normalizedType == 'sash_central' ||
        normalizedType == 'central' ||
        normalizedType == 'chicane') {
      final override =
          componentOverrides['قائم وسطي (Sash Central)'] ??
          componentOverrides['قائم وسطي (Central)'] ??
          componentOverrides['الشيكان (Chicane)'];
      if (override is Map) {
        return AluminumSection.fromMap(Map<String, dynamic>.from(override));
      }
      final configured =
          getConfiguredSectionForRole(normalizedType, useSlidingSeries: true) ??
          getConfiguredSectionForRole('sash_central', useSlidingSeries: true) ??
          getConfiguredSectionForRole('chicane', useSlidingSeries: true);
      if (configured != null &&
          !isSlidingMontantReinforced(configured.toMap(), central: true)) {
        return configured;
      }
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: true) &&
            !isSlidingMontantReinforced(map, central: true)) {
          return section;
        }
      }
      if (configured != null) return configured;
      for (final section in series.sections) {
        final map = section.toMap();
        if (isSlidingMontantCandidate(map, central: true)) {
          return section;
        }
      }
      return null;
    }

    if (normalizedType == 'face_to_face') {
      final configured = getConfiguredSectionForRole(
        'face_to_face',
        useSlidingSeries: true,
      );
      if (configured != null) return configured;
    }

    for (final section in series.sections) {
      final sectionType = section.type.toLowerCase();
      final sectionName = section.name.toLowerCase();
      final isCremoneTringle =
          normalizedType == 'triangle' &&
          (sectionType == 'tringle' ||
              sectionType.contains('tringle') ||
              sectionName.contains('tringle') ||
              sectionName.contains('ترينجل') ||
              sectionName.contains('تراينغل') ||
              sectionName.contains('تريانغل'));
      if (sectionType == normalizedType ||
          isCremoneTringle ||
          (normalizedType == 'frame' && section.isFrame)) {
        return section;
      }
    }
    return null;
  }

  /// Returns true when a catalogue row is the one-track extension assigned
  /// to a sliding series. This is used by the selector to keep the mandatory
  /// two-track base frame separate from its automatic additions.
  bool isSlidingFrameExtension(Map<String, dynamic> section) {
    final series = effectiveSlidingSeries;
    final rawId = section['id'];
    final id = rawId is num
        ? rawId.toInt()
        : int.tryParse(rawId?.toString() ?? '');
    final configuredIds = series == null
        ? const <int>{}
        : (_seriesDesignRoleSectionIds[series.id]?['frame_extension'] ??
              const <int>{});
    return id != null && configuredIds.contains(id);
  }

  /// Resolves the physical two-track base frame even when an old drawing or
  /// an overly broad catalogue role contains a one-track profile.
  AluminumSection? getSlidingBaseFrameSection() {
    final series = effectiveSlidingSeries;
    if (series == null) return null;

    bool isCurrentSlidingFrame(Map<String, dynamic> value) {
      final rawId = value['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null || isSlidingFrameExtension(value)) return false;

      AluminumSection? section;
      for (final candidate in series.sections) {
        if (candidate.id == id) {
          section = candidate;
          break;
        }
      }
      if (section == null) return false;
      if (!_hasLoadedRoleMetadata(series)) return true;

      final configuredIds =
          _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
      return configuredIds.contains(id) &&
          _configuredSectionMatchesScope(series, 'frame', id, sliding: true);
    }

    if (slidingFrameOverride != null &&
        isCurrentSlidingFrame(slidingFrameOverride!)) {
      return AluminumSection.fromMap(slidingFrameOverride!);
    }

    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?['frame'] ?? const <int>{};
    for (final section in series.sections) {
      if (configuredIds.contains(section.id) &&
          _configuredSectionMatchesScope(
            series,
            'frame',
            section.id,
            sliding: true,
          ) &&
          !isSlidingFrameExtension(section.toMap())) {
        return section;
      }
    }

    // Older catalogues do not have SeriesDesignRoles yet. Keep the legacy
    // fallback only for those catalogues; once role metadata exists, an
    // unassigned frame must remain missing instead of borrowing an opening
    // profile.
    if (!_hasLoadedRoleMetadata(series)) {
      for (final section in series.sections) {
        if (_isFrameSection(section) &&
            !isSlidingFrameExtension(section.toMap())) {
          return section;
        }
      }
    }

    return null;
  }

  /// The sliding frame is always the two-track base frame.  Additional
  /// tracks are represented by the section assigned to `frame_extension` in
  /// the series rules, rather than by selecting a fictitious three/four-track
  /// frame from the catalogue.
  AluminumSection? getSlidingFrameExtensionSection() {
    final series = effectiveSlidingSeries;
    if (series == null) return null;

    final configuredIds =
        _seriesDesignRoleSectionIds[series.id]?['frame_extension'] ??
        const <int>{};
    if (configuredIds.isNotEmpty) {
      for (final section in series.sections) {
        if (configuredIds.contains(section.id) &&
            _configuredSectionMatchesScope(
              series,
              'frame_extension',
              section.id,
              sliding: true,
            )) {
          return section;
        }
      }
    }

    return null;
  }

  /// Number of C-profile pieces needed after the configured base frame.
  /// One physical C profile may add one, two or three rails as selected in
  /// the series rules.
  int slidingSingleTrackAdditionCount(int trackCount) {
    final safeCount = trackCount.clamp(2, 7).toInt();
    final frameMode =
        slidingFrameOverride?['design_track_mode']?.toString().toLowerCase() ??
        '';
    if (frameMode == 'complete') return 0;
    final baseRaw = slidingFrameOverride?['design_track_count'];
    final baseCount = baseRaw is num
        ? baseRaw.toInt()
        : int.tryParse(baseRaw?.toString() ?? '') ?? 2;
    final missingTracks = math.max(0, safeCount - baseCount);
    final extension = getSlidingFrameExtensionSection();
    final seriesId = effectiveSlidingSeries?.id;
    final addsRaw = seriesId == null || extension == null
        ? null
        : _seriesDesignRoleOptions[seriesId]?['frame_extension']?[extension
              .id]?['track_adds'];
    final configuredTracksPerPiece = addsRaw is num
        ? addsRaw.toInt()
        : int.tryParse(addsRaw?.toString() ?? '') ?? 1;
    final tracksPerPiece = configuredTracksPerPiece.clamp(1, 3);
    return (missingTracks / tracksPerPiece).ceil();
  }

  dynamic _selectedSlidingRoleOption(String roleKey, String optionKey) {
    final seriesId = activeSlidingSeries?.id ?? activeSeries?.id;
    if (seriesId == null) return null;
    final selectedRail = componentOverrides['الري (Rail)'];
    final selectedId = roleKey == 'rail' && selectedRail is Map
        ? selectedRail['id']
        : null;
    final parsedSelectedId = selectedId is num
        ? selectedId.toInt()
        : int.tryParse('${selectedId ?? ''}');
    final roleOptions = _seriesDesignRoleOptions[seriesId]?[roleKey];
    if (roleOptions == null || roleOptions.isEmpty) return null;
    if (parsedSelectedId != null && roleOptions.containsKey(parsedSelectedId)) {
      return roleOptions[parsedSelectedId]?[optionKey];
    }
    return roleOptions.values.first[optionKey];
  }

  /// Number of physical lower-rail pieces required for the drawing. The
  /// catalogue rule defines whether one piece represents 1, 2 or 3 rails.
  int slidingRailPieceCount(int trackCount) {
    final raw = _selectedSlidingRoleOption('rail', 'track_adds');
    final configured = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 1;
    final railsPerPiece = configured.clamp(1, 3);
    return (trackCount.clamp(0, 7) / railsPerPiece).ceil();
  }

  int slidingTrackCountForRect(Rect frame) => zones
      .where((zone) => frame.contains(zone.boundary.center))
      .fold<int>(1, (count, zone) => math.max(count, zone.slidingTrackCount));

  /// Number of physical Seuil/C pieces required below a sliding frame.
  /// The catalogue rule defines whether one profile covers 1, 2 or 3 rails.
  int slidingSeuilPieceCount(int trackCount) {
    final raw = _selectedSlidingRoleOption('seuil', 'track_adds');
    final configured = raw is num
        ? raw.toInt()
        : int.tryParse('${raw ?? ''}') ?? 1;
    final tracksPerPiece = configured.clamp(1, 3);
    return (trackCount.clamp(0, 7) / tracksPerPiece).ceil();
  }

  /// Final catalogue-rule correction applied after calculating the clear
  /// internal rail width. A saved rule has priority over inferred defaults.
  double get slidingRailWidthAdjustmentMm {
    final raw = _selectedSlidingRoleOption('rail', 'width_adjust_mm');
    return raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}'.replaceAll(',', '.')) ?? 0.0;
  }

  bool get selectedSlidingFrameIsComplete =>
      slidingFrameOverride?['design_track_mode']?.toString().toLowerCase() ==
      'complete';

  Set<int> get supportedSlidingTrackCounts {
    final seriesId = effectiveSlidingSeries?.id;
    final result = <int>{};

    bool allowedForCurrentDrawing(
      Map<String, dynamic> options, {
      bool isFrameExtension = false,
    }) {
      return slidingFrameRoleAllowedForDrawing(
        options,
        hasShutter: hasShutter,
        isCaissonTunnel: isCaissonTunnel,
        isPvc: isSlidingPVC,
        isFrameExtension: isFrameExtension,
      );
    }

    void addCounts(Map<String, dynamic> options) {
      final count = options['design_track_count'] ?? options['track_count'];
      final parsedCount = count is num
          ? count.toInt()
          : int.tryParse(count?.toString() ?? '');
      if (parsedCount != null && parsedCount >= 2 && parsedCount <= 7) {
        result.add(parsedCount);
      }
      for (final token
          in (options['design_supported_track_counts'] ??
                  options['supported_track_counts'] ??
                  '')
              .toString()
              .split(',')) {
        final value = int.tryParse(token.trim());
        if (value != null && value >= 2 && value <= 7) result.add(value);
      }
    }

    if (seriesId == null) {
      if (slidingFrameOverride != null &&
          allowedForCurrentDrawing(slidingFrameOverride!)) {
        addCounts(slidingFrameOverride!);
      }
      return result.isEmpty ? const {2} : result;
    }
    final roles = _seriesDesignRoleOptions[seriesId];
    if (roles == null || roles.isEmpty) {
      // Compatibility for old catalogues that predate explicit frame rules.
      return const {2, 3, 4};
    }
    final frameOptions = roles['frame'];
    var hasEligibleBaseFrame = false;
    if (frameOptions != null) {
      for (final options in frameOptions.values) {
        if (!allowedForCurrentDrawing(options)) continue;
        final mode = options['track_mode']?.toString().toLowerCase() ?? 'base';
        if (mode == 'complete') {
          final count = options['track_count'];
          final parsed = count is num
              ? count.toInt()
              : int.tryParse(count?.toString() ?? '');
          if (parsed != null && parsed >= 2 && parsed <= 7) result.add(parsed);
        } else {
          hasEligibleBaseFrame = true;
          final count = options['track_count'];
          final parsed = count is num
              ? count.toInt()
              : int.tryParse(count?.toString() ?? '');
          result.add(parsed != null && parsed >= 2 && parsed <= 7 ? parsed : 2);
        }
      }
    }
    final extensionOptions = roles['frame_extension'];
    if (hasEligibleBaseFrame && extensionOptions != null) {
      for (final options in extensionOptions.values) {
        if (!allowedForCurrentDrawing(options, isFrameExtension: true)) {
          continue;
        }
        addCounts(options);
      }
    }
    return result.isEmpty ? const {2} : result;
  }

  /// Leaf choices are independent of rail count. Even on a 2-track series (السكتين),
  /// a workshop can build 2, 3, 4, or 6 sashes unless restricted by max_sliding_sashes.
  Set<int> get supportedSlidingSashCounts {
    final minimum = selectedZone?.content == ZoneContent.slidingSash
        ? selectedZone!.slidingTrackCount.clamp(2, 7).toInt()
        : 2;
    final maxAllowedRaw =
        (slidingSeriesTableConfig ?? seriesTableConfig)?['max_sliding_sashes'];
    final maxAllowed = (maxAllowedRaw is num)
        ? maxAllowedRaw.toInt()
        : int.tryParse('$maxAllowedRaw') ?? 0;
    final effectiveMax = (maxAllowed >= 2) ? math.max(minimum, maxAllowed) : 6;

    final counts = <int>{};
    for (final s in const [2, 3, 4, 5, 6]) {
      if (s >= minimum && s <= effectiveMax) {
        counts.add(s);
      }
    }
    return counts.isEmpty ? {minimum} : counts;
  }

  /// Returns a manually selected sliding profile only when it belongs to the
  /// active sliding series.  Old orders can otherwise carry an override from
  /// a previously selected series into the quantity and cost table.
  Map<String, dynamic>? getSlidingComponentOverride(String key) {
    final candidate = componentOverrides[key];
    if (candidate is! Map) return null;
    final result = Map<String, dynamic>.from(candidate);
    final activeSeriesId = effectiveSlidingSeries?.id;
    final sourceSeriesId = result['series_id'];
    if (activeSeriesId != null &&
        sourceSeriesId != null &&
        sourceSeriesId.toString() != activeSeriesId.toString()) {
      return null;
    }
    return result;
  }

  Future<void> setActiveSlidingSeries(AluminumSeries series) {
    final next = _seriesUpdateChain.then(
      (_) => _setActiveSlidingSeries(series),
    );
    _seriesUpdateChain = next.catchError((Object error, StackTrace stack) {});
    return next;
  }

  Future<void> _setActiveSlidingSeries(AluminumSeries series) async {
    _saveSnapshot();
    final double previousFrameThickness = profileThickness;
    final double previousMullionThickness = mullionThickness;
    final bool affectsVisibleDivisions = usesSlidingPrimaryProfiles;
    final bool seriesChanged =
        (activeSlidingSeries != null && activeSlidingSeries!.id != series.id) ||
        (activeSlidingSeries == null && loadedSlidingSeriesId == null) ||
        (activeSlidingSeries == null &&
            loadedSlidingSeriesId != null &&
            loadedSlidingSeriesId != series.id);
    activeSlidingSeries = series;
    loadedSlidingSeriesId = series.id;
    loadedSlidingSeriesName = series.name;
    seriesDesignConfig = await db.getSeriesDesignConfig(series.id);
    slidingSeriesTableConfig = await db.getSeriesTableConfig(series.id);
    final configuredRoleRows = await db.getSeriesDesignRoles(series.id);
    _rememberSeriesRoleKeys(series, configuredRoleRows);
    final strictProfileRoles = configuredRoleRows.isNotEmpty;
    bool configuredRoleRowAllowed(Map<String, dynamic> row) {
      if (row['is_visible'] == 0 || row['show_in_quantity'] == 0) {
        return false;
      }
      if (!_roleScopeMatches(row['usage_scope']?.toString(), sliding: true)) {
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

    final hasFaceToFaceRule =
        configuredSectionsFor(const ['face_to_face']).isNotEmpty ||
        series.sections.any((s) => s.type.toLowerCase() == 'face_to_face') ||
        series.hasFaceToFace;
    if (hasFaceToFaceRule && seriesChanged) {
      for (final zone in zones) {
        if (zone.content == ZoneContent.slidingSash &&
            isSlidingFaceToFaceLayout(
              trackCount: zone.slidingTrackCount,
              sashCount: zone.slidingSashesCount,
            ) &&
            zone.slidingFaceToFace) {
          // فقط إذا كانت الخاصية مفعلة بالفعل، لا نجبرها بالقوة إذا ألغاها المستخدم
          zone.slidingCentralHandle = true;
        }
      }
    }
    if (seriesChanged) {
      slidingFrameOverride = null;
      slidingSashOverride = null;
      hasInternalSlidingSideCover = false;
      selectedInternalSlidingSideCover = null;
      internalSlidingSideCoverOverride = null;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      _clearSlidingProfileOverrides();
      _clearAccessoryOverrides();
      componentOverrides.remove('البارداج (Bardage)');
      componentOverrides.remove('البانو (Panneau)');
      removeOverridesFromForeignSeries();

      if (affectsVisibleDivisions) {
        mullionProfiles.clear();
        groovedMullionCavityOnPositiveSide.clear();
        mullionSectionOverrides.clear();
      }

      // Auto-matching opening series for System Mixed
      if (systemMode == 'mixed' || activeSeries != null) {
        final currentSystem = profileSystemForSeries(availableSystems, series);
        final openingSystem = profileSystemForSeries(
          availableSystems,
          activeSeries,
        );
        final canAutoMatchOpening =
            currentSystem != null &&
            (systemMode == 'mixed' ||
                activeSeries == null ||
                openingSystem == null ||
                profileSystemsShareMaterial(currentSystem, openingSystem));
        if (canAutoMatchOpening) {
          final openingMissingOrForeign =
              activeSeries == null ||
              (!zones.any(
                    (zone) =>
                        zone.content == ZoneContent.singleSash ||
                        zone.content == ZoneContent.doubleSash,
                  ) &&
                  (openingSystem == null ||
                      !profileSystemsShareMaterial(
                        currentSystem,
                        openingSystem,
                      )));
          if (openingMissingOrForeign) {
            AluminumSeries? newOpening;
            for (var s in currentSystem.series) {
              if (seriesSupportsDrawingScope(
                s,
                'opening',
                profile: currentSystem,
              )) {
                newOpening = s;
                break;
              }
            }
            if (newOpening == null) {
              for (final candidateSystem in availableSystems) {
                if (!profileSystemsShareMaterial(
                  currentSystem,
                  candidateSystem,
                )) {
                  continue;
                }
                for (final candidate in candidateSystem.series) {
                  if (seriesSupportsDrawingScopeInSystem(
                    candidate,
                    'opening',
                    profile: candidateSystem,
                  )) {
                    newOpening = candidate;
                    break;
                  }
                }
                if (newOpening != null) break;
              }
            }
            if (newOpening != null) {
              activeSeries = newOpening;
              frameOverride = null;
              sashOverride = null;
              final frames = getConfiguredSectionsForRole(
                'frame',
                useSlidingSeries: false,
              );
              if (frames.isNotEmpty) {
                final candidates = _compatibleFrameCandidatesForSeries(
                  newOpening,
                  frames,
                );
                if (candidates.isNotEmpty) {
                  frameOverride = _preferredFrameForSeries(
                    candidates,
                    newOpening,
                  ).toMap();
                }
              }
              final sashes = getConfiguredSectionsForRole(
                'sash',
                useSlidingSeries: false,
              );
              if (sashes.isNotEmpty) {
                sashOverride = sashes.first.toMap();
              }
              updateProfileThickness();
              updateAllSashThicknesses();
            } else if (systemMode == 'mixed') {
              activeSeries = null;
              frameOverride = null;
              sashOverride = null;
            }
          }
        }
      }
    }

    if (slidingFrameOverride == null) {
      // `frame` is the mandatory two-track base.  `frame_extension` is a
      // separate one-track profile and must never replace the base frame.
      final frames = configuredSectionsFor(const ['frame']);

      if (frames.isNotEmpty) {
        // Aluminium sliding frames should start without an integrated cover;
        // the cover is controlled as a separate profile when it is needed.
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

    var rails = configuredSectionsFor(const ['rail']);
    if (rails.isEmpty && !strictProfileRoles) {
      rails = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        return t == 'rail' ||
            t.contains('rail') ||
            t == 'الري' ||
            t.contains('الري') ||
            t == 'راي' ||
            t.contains('راي');
      }).toList();
    }
    if (rails.isNotEmpty && !componentOverrides.containsKey('الري (Rail)')) {
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

    var chicanes = configuredSectionsFor(const ['chicane']);
    if (chicanes.isEmpty && !strictProfileRoles) {
      chicanes = series.sections.where((s) {
        final t = s.type.toLowerCase().trim();
        final n = s.name.toLowerCase().trim();
        return t.contains('chicane') ||
            n.contains('chicane') ||
            t.contains('شيكان') ||
            n.contains('شيكان');
      }).toList();
    }
    if (chicanes.isNotEmpty &&
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

    // Only affects a drawing made entirely of sliding zones in mixed mode.
    // A mixed drawing that still has opening zones keeps its opening frame.
    updateProfileThickness();
    if (seriesChanged && affectsVisibleDivisions) {
      _synchronizeDivisionGapsForSeries(
        previousFrameThickness,
        previousMullionThickness,
      );
    }

    _synchronizeSharedSideCover();
    await _loadColorsForProfile(series.profileId);
    await _ensureParcloseForCurrentGlass();
    await refreshSectionPricesForSelectedColor(notify: false);
    await refreshBardageColorPrices(notify: false);
    final d = await db.db;
    if (d != null) {
      await _loadAccessoryDefaults(d, series.id);
    }

    _notifyModelListeners();
  }

  void _disableSlidingMontantReinforcementForPvc() {
    if (!isSlidingPVC) return;

    for (final zone in zones) {
      for (final key in zone.slidingMontantReinforced.keys.toList()) {
        if (zone.slidingMontantReinforced[key] == true) {
          zone.slidingMontantReinforced[key] = false;
        }
      }
    }

    const reinforcedKeys = [
      'قائم جانبي معزز (Sash Lateral Renforcé)',
      'قائم وسطي معزز (Sash Central Renforcé)',
    ];
    for (final key in reinforcedKeys) {
      componentOverrides.remove(key);
    }

    // A legacy save may have put a reinforced profile under the normal key.
    // Remove it so the regular series profile is resolved again.
    const normalOverrides = [
      ('قائم جانبي (Sash Lateral)', false),
      ('قائم جانبي (Lateral)', false),
      ('قائم وسطي (Sash Central)', true),
      ('قائم وسطي (Central)', true),
    ];
    for (final (key, central) in normalOverrides) {
      final value = componentOverrides[key];
      if (value is Map &&
          isSlidingMontantReinforced(
            Map<String, dynamic>.from(value),
            central: central,
          )) {
        componentOverrides.remove(key);
      }
    }
  }

  bool frameUsesSlidingSeries(Rect frame) {
    final members = zones
        .where((zone) => frame.contains(zone.boundary.center))
        .toList();
    if (members.isEmpty)
      return usesSlidingPrimaryProfiles || systemMode == 'sliding';

    final hasSlidingSash = members.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpeningSash = members.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    if (hasSlidingSash && !hasOpeningSash) return true;
    if (hasOpeningSash && !hasSlidingSash) return false;

    final hasSlidingElsewhere = zones.any(
      (z) => z.content == ZoneContent.slidingSash && !members.contains(z),
    );
    if (hasSlidingElsewhere) {
      return false;
    }

    // Fixed-glass and empty cells: follow the series of this window/frame.
    return usesSlidingPrimaryProfiles || systemMode == 'sliding';
  }

  void toggleInternalSlidingSideCover(bool value) {
    final zone = selectedZone;
    if (zone == null || !isSlidingZoneNestedInSingleFrame(zone)) return;
    _saveSnapshot();
    hasInternalSlidingSideCover = value;
    if (value) {
      _selectDefaultInternalSlidingSideCover();
    }
    _notifyModelListeners();
  }

  void setSlidingSashesCount(int count) {
    if (selectedZone == null) return;
    _saveSnapshot();
    final zone = selectedZone!;
    final oldSashesCount = zone.slidingSashesCount;
    zone.slidingSashesCount = count.clamp(2, 7).toInt();
    _resizeSlidingMontantSlimSelection(zone, oldSashesCount: oldSashesCount);
    if (!isSlidingFaceToFaceLayout(
      trackCount: zone.slidingTrackCount,
      sashCount: zone.slidingSashesCount,
    )) {
      zone.slidingFaceToFace = false;
      zone.slidingCentralHandle = false;
      zone.slidingSecondCentralHandle = false;
    }
    _notifyModelListeners();
  }

  void setSelectedZoneSlidingTracks(int count) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    _saveSnapshot();
    if (!supportedSlidingTrackCounts.contains(count)) return;
    zone.slidingTrackCount = count.clamp(2, 7).toInt();
    if (zone.slidingSashesCount < zone.slidingTrackCount) {
      final oldSashesCount = zone.slidingSashesCount;
      zone.slidingSashesCount = zone.slidingTrackCount;
      _resizeSlidingMontantSlimSelection(zone, oldSashesCount: oldSashesCount);
    }
    if (!isSlidingFaceToFaceLayout(
      trackCount: zone.slidingTrackCount,
      sashCount: zone.slidingSashesCount,
    )) {
      zone.slidingFaceToFace = false;
      zone.slidingCentralHandle = false;
      zone.slidingSecondCentralHandle = false;
    }
    // A series may provide a ready-made 4/5/6-rail frame in addition to the
    // composable two-rail base. Select that exact complete frame as soon as
    // the user chooses its rail count. If it does not exist, keep the base
    // frame so the C-profile/Complément dormant calculation remains active.
    final series = effectiveSlidingSeries;
    if (series != null) {
      final frames = getConfiguredSectionsForRole(
        'frame',
        useSlidingSeries: true,
      );
      if (frames.isNotEmpty) {
        final selected = _preferredSlidingFrameForTrackCount(
          frames,
          series,
          zone.slidingTrackCount,
        );
        final selectedMap = _slidingFrameMapWithRoleOptions(selected, series);
        if (_catalogueId(slidingFrameOverride) != selected.id) {
          slidingFrameOverride = selectedMap;
        } else {
          // Keep role metadata fresh even when the physical section did not
          // change (old saved drawings lack these design fields).
          slidingFrameOverride = {
            ...slidingFrameOverride ?? const <String, dynamic>{},
            ...selectedMap,
          };
        }
      }
    }
    _notifyModelListeners();
  }

  void setSelectedZoneSlidingSashes(int count, {bool? cutSlidingGlassRebate}) {
    if (hasArchOrSlant) return;
    final zone = selectedZone;
    if (zone == null) return;
    _saveSnapshot();
    zone.content = ZoneContent.slidingSash;
    if (!supportedSlidingSashCounts.contains(count) ||
        count < zone.slidingTrackCount) {
      return;
    }
    final oldSashesCount = zone.slidingSashesCount;
    zone.slidingSashesCount = count.clamp(2, 7).toInt();
    _resizeSlidingMontantSlimSelection(zone, oldSashesCount: oldSashesCount);
    if (!isSlidingFaceToFaceLayout(
      trackCount: zone.slidingTrackCount,
      sashCount: zone.slidingSashesCount,
    )) {
      zone.slidingFaceToFace = false;
      zone.slidingCentralHandle = false;
      zone.slidingSecondCentralHandle = false;
    }
    zone.cutSlidingGlassRebate =
        cutSlidingGlassRebate ?? zone.cutSlidingGlassRebate;
    zone.sashThickness = _calculateSashThickness(zone.isSash105);
    zone.openDirection = OpenDirection.right;
    zone.innerH = 0;
    zone.innerV = 0;
    zone.rightInnerH = 0;
    zone.rightInnerV = 0;
    zone.primaryDivisionAxis = null;
    zone.rightPrimaryDivisionAxis = null;
    zone.innerHPositions = const [];
    zone.innerVPositions = const [];
    zone.rightInnerHPositions = const [];
    zone.rightInnerVPositions = const [];
    zone.cellIsPanel = {};
    activeSubZone = null;
    showZoneMenu = false;
    // A frame is drawn before the user chooses its contents, so only the
    // first explicit sliding choice can resolve the opening/sliding
    // ambiguity. Promote the selected profiles immediately so the canvas and
    // the BOM use the same sliding frame.
    _activateSlidingProfilesForDrawing();
    updateProfileThickness();
    _notifyModelListeners();
  }

  /// Keeps the Montant Slim drawing state coherent when the leaf count is
  /// changed. If every old central edge was Slim (the drawer's "select all"
  /// state), newly appended leaves must also receive square 90-degree ends.
  /// Individual selections remain attached to their existing physical edges.
  void _resizeSlidingMontantSlimSelection(
    WindowZone zone, {
    required int oldSashesCount,
  }) {
    final oldCentralKeys = slidingCentralEdgeKeys(
      zone: zone,
      sashesCount: oldSashesCount,
    );
    final newCentralKeys = slidingCentralEdgeKeys(
      zone: zone,
      sashesCount: zone.slidingSashesCount,
    );
    final allOldCentralEdgesWereSlim =
        oldCentralKeys.isNotEmpty &&
        oldCentralKeys.every((key) => zone.slidingMontantSlim[key] == true);

    final resized = <String, bool>{};
    for (final key in newCentralKeys) {
      resized[key] =
          zone.slidingMontantSlim[key] ??
          (allOldCentralEdgesWereSlim && !oldCentralKeys.contains(key));
    }
    zone.slidingMontantSlim = resized;
  }

  void _activateSlidingProfilesForDrawing() {
    AluminumSeries? series = activeSlidingSeries;
    if (series == null && systemMode == 'sliding') {
      series = activeSeries;
    }
    if (series == null) {
      final currentSys =
          system ??
          (activeSeries != null
              ? profileSystemForSeries(availableSystems, activeSeries!)
              : null);
      if (currentSys != null) {
        for (final candidate in currentSys.series) {
          if (isSlidingSeriesForDrawing(candidate)) {
            series = candidate;
            break;
          }
        }
      }
      if (series == null) {
        for (final profileSystem in availableSystems) {
          for (final candidate in profileSystem.series) {
            if (isSlidingSeriesForDrawing(candidate)) {
              series = candidate;
              break;
            }
          }
          if (series != null) break;
        }
      }
    }
    if (series == null) return;
    activeSlidingSeries ??= series;

    final frames = getConfiguredSectionsForRole(
      'frame',
      useSlidingSeries: true,
    );
    final frame = frames.isNotEmpty
        ? _preferredSlidingFrameForTrackCount(
            frames,
            series,
            _requestedSlidingTrackCount(),
          )
        : getSlidingBaseFrameSection();
    if (frame != null &&
        (slidingFrameOverride == null ||
            getSlidingBaseFrameSection()?.id !=
                _catalogueId(slidingFrameOverride))) {
      slidingFrameOverride = _slidingFrameMapWithRoleOptions(frame, series);
    }

    if (slidingSashOverride == null) {
      final configured = getConfiguredSectionForRole(
        'sash',
        useSlidingSeries: true,
      );
      if (configured != null) {
        slidingSashOverride = configured.toMap();
      } else if (!_hasLoadedRoleMetadata(series)) {
        for (final section in series.sections) {
          final type = section.type.toLowerCase();
          if (section.isSash || type == 'sash' || type.contains('ouvrant')) {
            slidingSashOverride = section.toMap();
            break;
          }
        }
      }
    }
    updateAllSashThicknesses();
  }

  /// Whether the active sliding series supports Entrematique.
  /// PVC sliding never supports Entrematique.
  /// For aluminium sliding, it requires having an Entrematique override or candidate rule.
  bool get supportsSlidingEntrematique {
    if (isPVC || isSlidingPVC) return false;
    final series = effectiveSlidingSeries;
    if (series == null) return false;
    if (_isPvcSeries(series)) return false;
    if (componentOverrides.containsKey('أونتروماتيك (Entrematique)') ||
        componentOverrides.containsKey('entrematique')) {
      return true;
    }
    final rawRoles = _seriesDesignRoleSectionIds[series.id];
    if (rawRoles != null &&
        (rawRoles.containsKey('entrematique') ||
            rawRoles.containsKey('أونتروماتيك'))) {
      return true;
    }
    return false;
  }

  /// Whether the active sliding series has explicitly assigned the
  /// Face-to-Face profile role.  A missing rule means the option does not
  /// exist; the painter and BOM must not guess a profile by its name.
  bool get supportsSlidingFaceToFace {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return false;
    return isSlidingFaceToFaceLayout(
      trackCount: zone.slidingTrackCount,
      sashCount: zone.slidingSashesCount,
    );
  }

  void setSelectedZoneSlidingFaceToFace(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    if (value &&
        !isSlidingFaceToFaceLayout(
          trackCount: zone.slidingTrackCount,
          sashCount: zone.slidingSashesCount,
        )) {
      return;
    }
    if (zone.slidingFaceToFace == value) return;
    _saveSnapshot();
    zone.slidingFaceToFace = value;
    if (value) {
      zone.slidingCentralHandle = true;
      zone.slidingSecondCentralHandle = true;
    } else {
      zone.slidingCentralHandle = false;
      zone.slidingSecondCentralHandle = false;
    }
    _notifyModelListeners();
  }

  void toggleSelectedZoneSlidingFaceToFace() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingFaceToFace(!zone.slidingFaceToFace);
  }

  void setSelectedZoneSlidingCentralHandle(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    if (value &&
        !isSlidingFaceToFaceLayout(
          trackCount: zone.slidingTrackCount,
          sashCount: zone.slidingSashesCount,
        )) {
      return;
    }
    if (value && !zone.slidingFaceToFace) return;
    if (zone.slidingCentralHandle == value) return;
    _saveSnapshot();
    zone.slidingCentralHandle = value;
    _notifyModelListeners();
  }

  void toggleSelectedZoneSlidingCentralHandle() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingCentralHandle(!zone.slidingCentralHandle);
  }

  /// Enables the second middle handle as a drawing/BOM handle only.  It is
  /// intentionally dependent on the first central handle: without the
  /// functional middle handle there is no valid pair to mirror.
  void setSelectedZoneSlidingSecondCentralHandle(bool value) {
    final zone = selectedZone;
    if (zone == null || zone.content != ZoneContent.slidingSash) return;
    if (value &&
        (!isSlidingFaceToFaceLayout(
              trackCount: zone.slidingTrackCount,
              sashCount: zone.slidingSashesCount,
            ) ||
            !zone.slidingFaceToFace)) {
      return;
    }
    if (zone.slidingSecondCentralHandle == value &&
        (!value || zone.slidingCentralHandle)) {
      return;
    }
    _saveSnapshot();
    if (value) {
      // The decorative handle mirrors the functional middle handle. Repair
      // old drawings that saved Face-to-Face with the functional handle off.
      zone.slidingCentralHandle = true;
    }
    zone.slidingSecondCentralHandle = value;
    _notifyModelListeners();
  }

  void toggleSelectedZoneSlidingSecondCentralHandle() {
    final zone = selectedZone;
    if (zone == null) return;
    setSelectedZoneSlidingSecondCentralHandle(!zone.slidingSecondCentralHandle);
  }

  /// These profiles are specific to a sliding series.  Keeping them after a
  /// series change makes the BOM show sections and prices from the old series.
  void _clearSlidingProfileOverrides() {
    const keys = [
      'الظلفة المنزلقة (Sliding Sash)',
      'سكة الظلفة (Sash Traverse)',
      'عرضي (Traverse)',
      'قائم جانبي (Sash Lateral)',
      'قائم جانبي معزز (Sash Lateral Renforcé)',
      'قائم جانبي (Lateral)',
      'قائم وسطي (Sash Central)',
      'قائم وسطي معزز (Sash Central Renforcé)',
      'قائم وسطي (Central)',
      'الشيكان (Chicane)',
      'الري (Rail)',
    ];
    for (final key in keys) {
      componentOverrides.remove(key);
    }
  }

  void _ensureActiveSlidingSeries() {
    _activateSlidingProfilesForDrawing();
    if (activeSlidingSeries != null && systemMode == 'sliding') {
      activeSeries = activeSlidingSeries;
    }
  }
}
