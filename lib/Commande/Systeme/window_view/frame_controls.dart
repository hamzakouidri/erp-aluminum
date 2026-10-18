part of '../show_system_francais.dart';

/// Frames, mullions, side covers, profiles and series of the drawing page.
extension _WindowViewFrame on _WindowViewState {
  Future<void> _open3DPreview() async {
    if (widget.model.width <= 0 || widget.model.height <= 0) {
      _showShortcutFeedback(
        Localization.translate(
          'ارسم النافذة أولاً لعرضها بثلاثة أبعاد',
          Provider.of<AppSettingsProvider>(context, listen: false).language,
        ),
        icon: Icons.view_in_ar_rounded,
        color: Colors.orange,
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Window3DPreview(model: widget.model),
      ),
    );
  }

  Future<void> _loadInitialCatalog() async {
    try {
      await widget.model.loadCatalogData(widget.systemMode);
    } finally {
      if (mounted) {
        _setViewState(() => _initialCatalogReady = true);
      }
    }
  }

  Future<void> _setShowAllFrameProfiles(bool value) async {
    if (_showAllFrameProfiles == value) return;
    _setViewState(() => _showAllFrameProfiles = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_WindowViewState._showAllFramesPreferenceKey, value);
  }

  Future<void> _setHidePresetCard(bool value) async {
    if (_hidePresetCard == value) return;
    _setViewState(() => _hidePresetCard = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_WindowViewState._hidePresetCardPreferenceKey, value);
  }

  bool _seriesMatchesScope(
    AluminumSeries series,
    AluminumProfileSystem system,
    String scope,
  ) {
    return widget.model.seriesSupportsDrawingScopeInSystem(
      series,
      scope,
      profile: system,
    );
  }

  List<AluminumSeries> _seriesForScope(
    AluminumProfileSystem system,
    String scope,
  ) {
    final normalizedScope = scope.trim().toLowerCase();
    final oppositeScope = normalizedScope == 'sliding' ? 'opening' : 'sliding';
    final matching = system.series
        .where((series) => _seriesMatchesScope(series, system, normalizedScope))
        .toList();

    if (matching.isNotEmpty) {
      // A system can contain several opening/sliding series. Older catalogues
      // often configured the drawing roles for only one series, so returning
      // `matching` alone hides the other active series from the selector.
      // Broaden the result within this exact system, while still excluding a
      // series that is explicitly classified for the opposite drawing.
      final broadened = system.series.where((series) {
        if (_seriesMatchesScope(series, system, normalizedScope)) return true;
        // Check the opposite scope only on the series itself. Using the
        // system-wide fallback here would classify an unlabelled series as
        // both families and then remove it from this list again.
        if (widget.model.seriesSupportsDrawingScope(
          series,
          oppositeScope,
          profile: system,
        )) {
          return false;
        }
        return normalizedScope == 'sliding'
            ? !isOpeningSeriesForDrawing(series, system)
            : !isSlidingSeriesForDrawing(series);
      }).toList();
      if (broadened.isNotEmpty) return broadened;
    }

    // Some imported catalogues contain a valid multi-series system but do
    // not label the series with an opening/sliding keyword or scope. Keep
    // those active series selectable instead of hiding the whole system,
    // while never putting an explicitly sliding series in the opening list.
    final directlySliding = system.series
        .where(
          (series) => widget.model.seriesSupportsDrawingScope(
            series,
            'sliding',
            profile: system,
          ),
        )
        .toList();
    final directlyOpening = system.series
        .where(
          (series) => widget.model.seriesSupportsDrawingScope(
            series,
            'opening',
            profile: system,
          ),
        )
        .toList();

    if (normalizedScope == 'opening') {
      final unclassified = system.series
          .where((series) => !directlySliding.any((s) => s.id == series.id))
          .toList();
      if (unclassified.isNotEmpty) return unclassified;
      return directlyOpening;
    }
    if (directlyOpening.isNotEmpty) {
      return const <AluminumSeries>[];
    }
    return List<AluminumSeries>.from(system.series);
  }

  AluminumSeries? get activeSeriesForSystem {
    if (widget.systemMode == 'sliding') {
      return widget.model.activeSlidingSeries;
    }
    if (widget.systemMode == 'mixed') {
      final zone = widget.model.selectedZone;
      if (zone != null && zone.content == ZoneContent.slidingSash) {
        return widget.model.activeSlidingSeries;
      }
    }
    return widget.model.activeSeries;
  }

  Future<void> _loadAvailableProfiles() async {
    final requestGeneration = ++_profileLoadGeneration;
    final seriesId = activeSeriesForSystem?.id;
    if (seriesId == null) {
      if (mounted) {
        _setViewState(() {
          _frameProfiles = [];
          _openingFrameProfiles = [];
          _slidingFrameProfiles = [];
          _sashProfiles = [];
          _openingSashProfiles = [];
          _slidingSashProfiles = [];
          _slidingLateralProfileIds = {};
          _slidingCentralProfileIds = {};
          _loadedSeriesId = null;
          _loadedOpeningFrameSeriesId = null;
          _loadedSlidingFrameSeriesId = null;
        });
      }
      return;
    }
    final openingSeriesId = widget.model.activeSeries?.id;
    final slidingSeriesId = widget.model.activeSlidingSeries?.id;
    final needsOpeningFrames =
        widget.systemMode == 'mixed' && openingSeriesId != null;
    final needsSlidingFrames =
        (widget.systemMode == 'mixed' || widget.systemMode == 'sliding') &&
        slidingSeriesId != null;
    if (_loadedSeriesId == seriesId &&
        (!needsOpeningFrames ||
            _loadedOpeningFrameSeriesId == openingSeriesId) &&
        (!needsSlidingFrames ||
            _loadedSlidingFrameSeriesId == slidingSeriesId)) {
      return;
    }
    final cacheKey =
        '${CloudSyncService().catalogRevision}|$seriesId|$openingSeriesId|'
        '$slidingSeriesId|${widget.systemMode}';
    if (_WindowViewState._profilesMemoryCache.containsKey(cacheKey)) {
      final cached = _WindowViewState._profilesMemoryCache[cacheKey]!;
      _setViewState(() {
        _frameProfiles = cached.frames;
        _openingFrameProfiles = cached.openingFrames;
        _slidingFrameProfiles = cached.slidingFrames;
        _sashProfiles = cached.sashes;
        _openingSashProfiles = cached.openingSashes;
        _slidingSashProfiles = cached.slidingSashes;
        _slidingLateralProfileIds = cached.lateralIds;
        _slidingCentralProfileIds = cached.centralIds;
        _loadedSeriesId = seriesId;
        _loadedOpeningFrameSeriesId = needsOpeningFrames
            ? openingSeriesId
            : null;
        _loadedSlidingFrameSeriesId = needsSlidingFrames
            ? slidingSeriesId
            : null;
      });
      return;
    }
    if (_loadingAvailableProfiles) return;
    _loadingAvailableProfiles = true;
    try {
      final db = SqlDatabase();
      final myDb = await db.db;
      if (myDb == null) return;

      final primaryUsesSlidingFrames =
          widget.systemMode == 'sliding' ||
          (widget.systemMode == 'mixed' &&
              seriesId == slidingSeriesId &&
              seriesId != openingSeriesId);
      final frames = await _loadFrameProfilesForSeries(
        db,
        seriesId,
        sliding: primaryUsesSlidingFrames,
      );
      final sashes = await _loadSashProfilesForSeries(
        db,
        seriesId,
        sliding: primaryUsesSlidingFrames,
      );
      final openingFrames = needsOpeningFrames
          ? await _loadFrameProfilesForSeries(
              db,
              openingSeriesId,
              sliding: false,
            )
          : <Map<String, dynamic>>[];
      final slidingFrames = needsSlidingFrames
          ? await _loadFrameProfilesForSeries(
              db,
              slidingSeriesId,
              sliding: true,
            )
          : <Map<String, dynamic>>[];
      final openingSashes = needsOpeningFrames
          ? await _loadSashProfilesForSeries(
              db,
              openingSeriesId,
              sliding: false,
            )
          : <Map<String, dynamic>>[];
      final slidingSashes = needsSlidingFrames
          ? await _loadSashProfilesForSeries(db, slidingSeriesId, sliding: true)
          : <Map<String, dynamic>>[];
      final montantRoleSeriesId = slidingSeriesId ?? seriesId;
      final lateralRoleProfiles = await db.getDesignSectionsForDrawingRoles(
        montantRoleSeriesId,
        const ['sash_lateral', 'lateral'],
        usageScope: 'sliding',
      );
      final centralRoleProfiles = await db
          .getDesignSectionsForDrawingRoles(montantRoleSeriesId, const [
            'sash_central',
            'central',
            'chicane',
            'chicane_renforcee',
            'sash_central_reinforced',
          ], usageScope: 'sliding');

      // Ignore an old result when either series changed. Publishing only one
      // complete generation prevents opening and sliding rows from being
      // mixed while the two selectors are changing quickly.
      if (!mounted ||
          requestGeneration != _profileLoadGeneration ||
          activeSeriesForSystem?.id != seriesId ||
          widget.model.activeSeries?.id != openingSeriesId ||
          widget.model.activeSlidingSeries?.id != slidingSeriesId) {
        return;
      }
      Set<int> idsFrom(List<Map<String, dynamic>> rows) => rows
          .map((row) {
            final rawId = row['id'];
            return rawId is num
                ? rawId.toInt()
                : int.tryParse('${rawId ?? ''}');
          })
          .whereType<int>()
          .toSet();
      final latIds = idsFrom(lateralRoleProfiles);
      final centIds = idsFrom(centralRoleProfiles);
      _WindowViewState._profilesMemoryCache[cacheKey] = _CachedProfiles(
        frames: frames,
        openingFrames: openingFrames,
        slidingFrames: slidingFrames,
        sashes: sashes,
        openingSashes: openingSashes,
        slidingSashes: slidingSashes,
        lateralIds: latIds,
        centralIds: centIds,
      );
      _setViewState(() {
        _frameProfiles = frames;
        _openingFrameProfiles = openingFrames;
        _slidingFrameProfiles = slidingFrames;
        _sashProfiles = sashes;
        _openingSashProfiles = openingSashes;
        _slidingSashProfiles = slidingSashes;
        _slidingLateralProfileIds = latIds;
        _slidingCentralProfileIds = centIds;
        _loadedSeriesId = seriesId;
        _loadedOpeningFrameSeriesId = needsOpeningFrames
            ? openingSeriesId
            : null;
        _loadedSlidingFrameSeriesId = needsSlidingFrames
            ? slidingSeriesId
            : null;
      });
    } finally {
      _loadingAvailableProfiles = false;
      // Only queue another load when the user changed the series while this
      // request was in flight. Retrying the same failed request in a tight
      // loop would make the drawing page appear to crash temporarily.
      if (mounted && activeSeriesForSystem?.id != null) {
        final currentOpeningSeriesId = widget.model.activeSeries?.id;
        final currentSlidingSeriesId = widget.model.activeSlidingSeries?.id;
        final currentNeedsOpeningFrames =
            widget.systemMode == 'mixed' && currentOpeningSeriesId != null;
        final currentNeedsSlidingFrames =
            (widget.systemMode == 'mixed' || widget.systemMode == 'sliding') &&
            currentSlidingSeriesId != null;
        final profilesChangedWhileLoading =
            requestGeneration != _profileLoadGeneration ||
            activeSeriesForSystem?.id != seriesId ||
            widget.model.activeSeries?.id != openingSeriesId ||
            widget.model.activeSlidingSeries?.id != slidingSeriesId ||
            (currentNeedsOpeningFrames &&
                currentOpeningSeriesId != openingSeriesId) ||
            (currentNeedsSlidingFrames &&
                currentSlidingSeriesId != slidingSeriesId);
        if (profilesChangedWhileLoading) {
          unawaited(_loadAvailableProfiles());
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadFrameProfilesForSeries(
    SqlDatabase db,
    int seriesId, {
    required bool sliding,
  }) async {
    final configured = await db.getDesignSectionsForDrawingRoles(
      seriesId,
      const ['frame'],
      usageScope: sliding ? 'sliding' : 'opening',
    );

    // A series may contain several usable dormant/cadre sections while only
    // its default one is assigned to the `frame` role. The role still owns
    // the default and its drawing options, but the frame picker must also
    // expose the other active frame sections of that same series (including
    // explicitly shared sections).
    final available = await db.readAvailableSectionsBySeries(
      seriesId,
      usageScope: sliding ? 'sliding' : 'opening',
    );

    bool isFrameCandidate(Map<String, dynamic> row) {
      final flag = row['is_frame'];
      final isFrame =
          flag == true ||
          (flag is num && flag != 0) ||
          flag?.toString().trim() == '1';
      final type = (row['type'] ?? '').toString().trim().toLowerCase();
      final name = (row['name'] ?? '').toString().trim().toLowerCase();
      final code = (row['code'] ?? '').toString().trim().toLowerCase();
      final designRole = (row['design_role_key'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final sharedRole = (row['sharing_role_key'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final normalizedType = type.replaceAll(RegExp(r'[\s-]+'), '_');
      final normalizedName = name.replaceAll(RegExp(r'[\s-]+'), '_');
      final normalizedCode = code.replaceAll(RegExp(r'[\s-]+'), '_');
      final label = '$normalizedType $normalizedName $normalizedCode';
      final role = designRole.isNotEmpty ? designRole : sharedRole;

      // 1. Accessory / non-frame check:
      // Tringle, Port de joint, Parclose, etc. are NOT frames
      final isNonFrame =
          label.contains('tringle') ||
          label.contains('port_de_joint') ||
          label.contains('porte_de_joint') ||
          label.contains('port_joint') ||
          label.contains('porte_joint') ||
          label.contains('portejoint') ||
          label.contains('حامل_الجوان') ||
          label.contains('parclose') ||
          label.contains('rejet') ||
          label.contains('bavette') ||
          label.contains('cremone') ||
          label.contains('crémone') ||
          label.contains('charniere') ||
          label.contains('charnière') ||
          label.contains('roulette') ||
          label.contains('vitrage') ||
          label.contains('glace');
      if (isNonFrame) {
        return false;
      }

      final isFrameRole = role == 'frame' || role == 'sliding_frame';
      final isNonFrameRole =
          role == 'side_cover' ||
          role == 'porte_joint' ||
          role == 'tringle' ||
          role == 'parclose';
      final isSideCoverType =
          normalizedType == 'side_cover' ||
          normalizedType == 'sidecover' ||
          normalizedType == 'couvre_joint' ||
          normalizedType == 'couvrejoint';
      final isPorteJointType =
          normalizedType == 'porte_joint' || normalizedType == 'portejoint';
      final hasSideCoverLabel =
          label.contains('couvre_joint') ||
          label.contains('couvrejoint') ||
          label.contains('side_cover') ||
          label.contains('sidecover') ||
          label.contains('كوفرجوا') ||
          label.contains('كوفر_جوا') ||
          label.contains('غطاء_جانبي');
      final typeClearlyNamesFrame =
          isFrameRole ||
          normalizedType == 'frame' ||
          normalizedType.contains('cadre') ||
          normalizedType.contains('dormant') ||
          normalizedName.contains('cadre') ||
          normalizedName.contains('dormant') ||
          normalizedName.contains('حلق') ||
          normalizedName.contains('إطار');

      if (isNonFrameRole ||
          isSideCoverType ||
          isPorteJointType ||
          (!isFrameRole && !typeClearlyNamesFrame && hasSideCoverLabel)) {
        return false;
      }
      if (sharedRole == 'frame_extension' || type == 'frame_extension') {
        return false;
      }

      final isBasicFrame = isFrame || isFrameRole || typeClearlyNamesFrame;
      if (!isBasicFrame) return false;

      // 2. Sliding vs Opening check:
      bool isSlidingProfile() {
        if (role == 'sliding_frame' || role == 'frame_sliding') return true;
        final uScope =
            (row['usage_scope'] ??
                    row['design_usage_scope'] ??
                    row['sharing_usage_scope'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();
        if (uScope == 'sliding') return true;
        final text = '$label $name $type $code'.toLowerCase();
        if (RegExp(
          r'\b\d+\s*rail|raill|monorail|couliss|glissi|galandage|سحاب|منزلق|جرار',
        ).hasMatch(text)) {
          return true;
        }
        return false;
      }

      final isSliding = isSlidingProfile();
      if (sliding) {
        // Looking for sliding frames: reject if strictly marked as opening
        if (!isSliding &&
            (role == 'frame' ||
                label.contains('ouvrant') ||
                label.contains('battant') ||
                label.contains('frappe'))) {
          return false;
        }
      } else {
        // Looking for opening frames: REJECT any profile that is sliding!
        if (isSliding) {
          return false;
        }
      }

      return true;
    }

    final merged = <Map<String, dynamic>>[];
    final seen = <int>{};
    void append(Map<String, dynamic> row, {required bool configuredFrame}) {
      final rawId = row['id'];
      final id = rawId is num
          ? rawId.toInt()
          : int.tryParse(rawId?.toString() ?? '');
      if (id == null || seen.add(id)) {
        merged.add({
          ...row,
          'frame_picker_configured': configuredFrame ? 1 : 0,
        });
      }
    }

    // Keep configured rows first so the catalogue default remains first and
    // role-specific properties such as integrated_side_cover are preserved.
    for (final row in configured.where(isFrameCandidate)) {
      append(row, configuredFrame: true);
    }
    for (final row in available.where(isFrameCandidate)) {
      append(row, configuredFrame: false);
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _loadSashProfilesForSeries(
    SqlDatabase db,
    int seriesId, {
    required bool sliding,
  }) async {
    return db.getDesignSectionsForDrawingRoles(
      seriesId,
      sliding
          ? const [
              'sash',
              'sash_extension',
              'sash_lateral',
              'sash_lateral_reinforced',
              'sash_central',
              'sash_central_reinforced',
              'sash_traverse',
              'chicane',
              'chicane_renforcee',
            ]
          : const ['sash', 'sash_extension'],
      usageScope: sliding ? 'sliding' : 'opening',
    );
  }

  bool _seriesIsPvc(AluminumSeries? series) {
    if (series == null) return widget.model.isPVC;
    for (final system in widget.model.availableSystems) {
      if (system.id == series.profileId ||
          system.series.any((candidate) => candidate.id == series.id)) {
        return system.type.toLowerCase().trim() == 'pvc';
      }
    }
    return false;
  }

  DecorationImage? _getWoodTextureImage(Map<String, dynamic> dbColor) {
    final name = dbColor['name'].toString().toLowerCase();
    final cleanName = name
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');

    final isWood =
        cleanName.contains('خشب') ||
        cleanName.contains('wood') ||
        cleanName.contains('bois') ||
        cleanName.contains('╪«╪┤╪¿') ||
        cleanName.contains('desert') ||
        cleanName.contains('ديزر') ||
        cleanName.contains('ديزير') ||
        cleanName.contains('oak') ||
        cleanName.contains('اوك') ||
        cleanName.contains('chene') ||
        cleanName.contains('chêne') ||
        cleanName.contains('noyer') ||
        cleanName.contains('acajou') ||
        cleanName.contains('شين') ||
        cleanName.contains('نويا') ||
        cleanName.contains('اكاجو') ||
        cleanName.contains('بوا') ||
        cleanName.contains('faux') ||
        cleanName.contains('فو') ||
        cleanName.contains('antique') ||
        cleanName.contains('انتيك') ||
        cleanName.contains('onteak') ||
        cleanName.contains('╪º┘å╪¬┘è┘â') ||
        cleanName.contains('╪»┘è╪▓╪▒') ||
        cleanName.contains('d0') ||
        cleanName.contains('دي زيرو') ||
        cleanName.contains('بلوط') ||
        cleanName.contains('di zero');

    if (!isWood) return null;

    String assetPath = 'assets/images/wood_texture.png';
    if (cleanName.contains('marron clair') ||
        cleanName.contains('light brown') ||
        cleanName.contains('بني فاتح')) {
      assetPath = 'assets/images/wood_texture_light_brown.png';
    } else if (cleanName.contains('d0') ||
        cleanName.contains('oak') ||
        cleanName.contains('اوك') ||
        cleanName.contains('شين') ||
        cleanName.contains('chene') ||
        cleanName.contains('chêne') ||
        cleanName.contains('بلوط') ||
        cleanName.contains('دي زيرو') ||
        cleanName.contains('di zero') ||
        cleanName.contains('desert') ||
        cleanName.contains('ديزر') ||
        cleanName.contains('ديزير') ||
        cleanName.contains('╪»┘è╪▓╪▒')) {
      assetPath = 'assets/images/wood_texture_d0.png';
    } else if (cleanName.contains('antique') ||
        cleanName.contains('انتيك') ||
        cleanName.contains('onteak') ||
        cleanName.contains('faux bois marron') ||
        cleanName.contains('marron faux bois') ||
        (cleanName.contains('marron') && cleanName.contains('bois')) ||
        (cleanName.contains('بني') && cleanName.contains('خشب')) ||
        cleanName.contains('╪º┘å╪¬┘è┘â')) {
      assetPath = 'assets/images/wood_texture_antique.png';
    } else if (cleanName.contains('grey') ||
        cleanName.contains('gray') ||
        cleanName.contains('gris') ||
        cleanName.contains('رمادي')) {
      assetPath = 'assets/images/wood_texture_grey.png';
    } else if (cleanName.contains('dark') ||
        cleanName.contains('daكن') ||
        cleanName.contains('fonce') ||
        cleanName.contains('foncé')) {
      assetPath = 'assets/images/wood_texture_dark.png';
    }

    return DecorationImage(image: AssetImage(assetPath), fit: BoxFit.cover);
  }

  double _catalogNumber(Map<String, dynamic> row, String key) {
    final value = row[key];
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  int? _frameAtBorder(Offset modelPosition) {
    final thickness = widget.model.profileThickness;
    final frameRects = widget.model.getFrameRects();
    for (var index = frameRects.length - 1; index >= 0; index--) {
      final outer = frameRects[index];
      final inner = outer.deflate(thickness * 0.72);
      if (outer.inflate(12.0).contains(modelPosition) &&
          !inner.deflate(8.0).contains(modelPosition)) {
        return index;
      }
    }
    return null;
  }

  _FrameResizeHandle? _frameResizeHandleAt(Offset screenPosition) {
    final frameKey =
        (widget.model.selection.type == SelectionType.frame ||
            widget.model.selection.type == SelectionType.zone)
        ? widget.model.selection.zoneId
        : null;
    final outer = widget.model.frameRectForSelection(frameKey);
    if (outer == null) return null;
    final handles = <_FrameResizeHandle, Offset>{
      _FrameResizeHandle.topLeft: outer.topLeft,
      _FrameResizeHandle.top: Offset(outer.center.dx, outer.top),
      _FrameResizeHandle.topRight: outer.topRight,
      _FrameResizeHandle.right: Offset(outer.right, outer.center.dy),
      _FrameResizeHandle.bottomRight: outer.bottomRight,
      _FrameResizeHandle.bottom: Offset(outer.center.dx, outer.bottom),
      _FrameResizeHandle.bottomLeft: outer.bottomLeft,
      _FrameResizeHandle.left: Offset(outer.left, outer.center.dy),
    };

    _FrameResizeHandle? closest;
    double closestDistance = 30.0;
    for (final entry in handles.entries) {
      final distance = (_modelToScreen(entry.value) - screenPosition).distance;
      if (distance <= closestDistance) {
        closest = entry.key;
        closestDistance = distance;
      }
    }
    return closest;
  }

  List<Map<String, dynamic>> _availableMullionFrameSections() {
    final frames = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    double readDimension(Map<String, dynamic> raw, String key) {
      final value = raw[key];
      return value is num
          ? value.toDouble()
          : double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    void addFrame(Map<String, dynamic> raw) {
      final code = (raw['code'] ?? '').toString().trim();
      final name = (raw['name'] ?? '').toString().trim();
      final type = (raw['type'] ?? '').toString().toLowerCase();
      final isFrameFlag =
          raw['is_frame'] == 1 ||
          raw['isFrame'] == true ||
          raw['is_frame']?.toString() == '1';
      final isFrame =
          isFrameFlag ||
          type == 'frame' ||
          type == 'cadre' ||
          type == 'dormant' ||
          type == 'إطار';
      if (!isFrame) return;
      final coverWidth = readDimension(raw, 'couvre_joint_width');
      final hasIntegratedCover =
          coverWidth > 0.5 ||
          name.toLowerCase().contains('مدمج') ||
          name.toLowerCase().contains('intégré') ||
          name.toLowerCase().contains('integre') ||
          name.toLowerCase().contains('monobloc') ||
          type.contains('monobloc');
      if (hasIntegratedCover) return;
      final idKey = (raw['id'] ?? '$code:$name').toString();
      if (!seenIds.add(idKey)) return;
      frames.add(Map<String, dynamic>.from(raw));
    }

    for (final frame in _frameProfiles) {
      addFrame(frame);
    }
    for (final frame in _openingFrameProfiles) {
      addFrame(frame);
    }
    for (final frame in _slidingFrameProfiles) {
      addFrame(frame);
    }

    frames.sort((a, b) {
      final aCode = (a['code'] ?? '').toString();
      final bCode = (b['code'] ?? '').toString();
      return aCode.compareTo(bCode);
    });
    return frames;
  }

  bool _selectedMullionFrameMatches(
    Map<String, dynamic> frame,
    MullionProfileType type,
  ) {
    final selection = widget.model.selection;
    if (selection.type != SelectionType.mullion ||
        selection.isHorizontalMullion == null ||
        selection.mullionPosition == null) {
      return false;
    }
    final key =
        '${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}';
    final currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    final current = widget.model.mullionSectionOverrides[key];
    if (currentType != type || current == null) return false;
    return current['id']?.toString() == frame['id']?.toString();
  }

  Future<void> _applyMullionFrameSection(
    MullionProfileType type,
    Map<String, dynamic> frame,
  ) async {
    final mutable = Map<String, dynamic>.from(frame);
    mutable['calculated_price'] = await _sectionPriceForSelectedColor(mutable);
    if (!mounted) return;
    _setViewState(() {
      widget.model.setMullionFrameSection(type, mutable);
    });
  }

  Widget buildSideCoverSegmentsControl(
    BuildContext context,
    WindowModel model,
    AppLanguage lang,
  ) {
    if (!model.hasSideCovers) return const SizedBox.shrink();

    String labelFor(String side) {
      switch (side) {
        case 'top':
          return Localization.translate('علوية', lang);
        case 'left':
          return Localization.translate('يسرى', lang);
        case 'right':
          return Localization.translate('يمنى', lang);
        case 'bottom':
          return Localization.translate('سفلية', lang);
        default:
          return side;
      }
    }

    Widget sideButton(String side) {
      final allowed = model.canSideUseSideCover(side);
      final enabled = model.isSideCoverSegmentEnabled(side);
      return Tooltip(
        message: !allowed
            ? Localization.translate(
                'بروفيل هذه الجهة لا يقبل غطاء جانبي',
                lang,
              )
            : Localization.translate(
                'ضغطة للتفعيل أو التعطيل، واضغط مطولا لتخصيص الغطاء',
                lang,
              ),
        child: Stack(
          children: [
            FilterChip(
              labelStyle: TextStyle(
                fontSize: 10,
                color: !allowed ? Colors.grey : null,
              ),
              label: Text(labelFor(side)),
              selected: enabled,
              onSelected: (_) {},
            ),
            // This transparent layer is deliberately above the chip so one
            // recognizer owns both gestures. It makes a short tap reliable
            // on touch screens and desktop while preserving long press and
            // right-click for the segment editor.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (!allowed) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'بروفيل الإطار الحالي في الجهة (${labelFor(side)}) لا يسمح بتركيب غطاء جانبي.',
                        ),
                        backgroundColor: Colors.orange.shade800,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  model.toggleSideCoverSegment(side);
                },
                onLongPress: allowed
                    ? () => _showSideCoverSegmentDialog(context, side)
                    : null,
                onSecondaryTap: allowed
                    ? () => _showSideCoverSegmentDialog(context, side)
                    : null,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Localization.translate(
            'ضغطة للتفعيل أو التعطيل، واضغط مطولا على الجهة لتخصيصها',
            lang,
          ),
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            sideButton('top'),
            sideButton('left'),
            sideButton('right'),
            sideButton('bottom'),
          ],
        ),
      ],
    );
  }

  int? _selectedProfileColorId() {
    final rawId = widget.model.selectedDbColor?['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  int? _catalogRowId(Map<String, dynamic> item) {
    final rawId = item['id'];
    return rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
  }

  Future<double> _sectionPriceForSelectedColor(
    Map<String, dynamic> item,
  ) async {
    final sectionId = _catalogRowId(item);
    final colorId = _selectedProfileColorId();
    if (sectionId == null || colorId == null) return 0.0;
    try {
      return await SqlDatabase().getSectionPrice(sectionId, colorId);
    } catch (error) {
      debugPrint('Failed to resolve section price for drawing button: $error');
      return 0.0;
    }
  }

  Future<void> _openMaterialConsumptionScreen(BuildContext context) async {
    // حماية: إذا كان تحميل السلسلة والكتالوج جارياً، ننتظر حتى ينتهي تماماً
    // حتى لا تأخذ شاشة الكميات السلسلة الافتراضية بالخطأ
    if (widget.model.colorsLoading) {
      await widget.model.loadCatalogData(widget.systemMode);
    }
    if (widget.model.zones.any(
      (zone) =>
          zone.glass.glazingFitValid == false ||
          zone.cellGlassSpec.values.any(
            (spec) => spec.glazingFitValid == false,
          ),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تركيب الزجاج غير متوافق. راجع السماكات والجوانات في القائمة اليسرى قبل اعتماد الكمية والتكلفة.',
          ),
        ),
      );
      return;
    }
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final hasWindowContent = widget.model.zones.any(
      (z) => z.content != ZoneContent.empty,
    );
    final hasReadyShutterOnly =
        widget.model.isShutterOnly &&
        widget.model.width > 0 &&
        widget.model.height > 0;

    if (!hasReadyShutterOnly && !hasWindowContent) {
      final message = widget.model.drawNextShapeAsShutterOnly
          ? 'ارسم مستطيل الستار على اللوحة أولاً قبل حساب الكمية والتكلفة.'
          : 'الرجاء رسم أو إضافة جزء في النافذة أولاً قبل حساب التكلفة!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate(message, lang)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    widget.model.clearSelection();

    if (!widget.model.isShutterOnly) {
      // The frame picked in the drawing is the source of truth. Refresh its
      // colour price in the background so database startup never blocks the
      // transition to the material table.
      unawaited(() async {
        try {
          final activeFrame = widget.model.activeFrameOverride;
          final cId = _selectedProfileColorId();
          if (activeFrame == null || cId == null) return;
          final rawFrameId = activeFrame['id'];
          final sId = rawFrameId is num
              ? rawFrameId.toInt()
              : int.tryParse(rawFrameId?.toString() ?? '');
          if (sId == null) return;

          final updatedPrice = await SqlDatabase().getSectionPrice(sId, cId);
          final pricedFrame = Map<String, dynamic>.from(activeFrame);
          pricedFrame['calculated_price'] = updatedPrice;
          if (widget.model.usesSlidingPrimaryProfiles) {
            widget.model.slidingFrameOverride = pricedFrame;
          } else {
            widget.model.frameOverride = pricedFrame;
            widget.model.selectedFrameCode = pricedFrame['code']?.toString();
          }
          widget.model.updateProfileThickness();
        } catch (error) {
          debugPrint('Failed to refresh frame price in background: $error');
        }
      }());
    }

    if (!context.mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MaterialConsumptionScreen(model: widget.model),
      ),
    );
    if (result == true && context.mounted) {
      Navigator.pop(context, widget.model);
    }
  }

  Future<void> _addDrawingAndCalculate(BuildContext context) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final hasInvalidGlazing = widget.model.zones.any(
      (zone) =>
          zone.glass.glazingFitValid == false ||
          zone.cellGlassSpec.values.any(
            (spec) => spec.glazingFitValid == false,
          ),
    );
    if (hasInvalidGlazing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'تركيب الزجاج غير متوافق. راجع السماكات والجوانات قبل الإضافة.',
              lang,
            ),
          ),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      return;
    }

    final hasWindowContent = widget.model.zones.any(
      (z) => z.content != ZoneContent.empty,
    );
    final hasReadyShutterOnly =
        widget.model.isShutterOnly &&
        widget.model.width > 0 &&
        widget.model.height > 0;
    if (!hasReadyShutterOnly && !hasWindowContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'الرجاء رسم أو إضافة جزء في النافذة أولاً قبل حساب التكلفة!',
              lang,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Use the exact same initialization, catalogue stabilization, BOM and
    // selling-price pipeline as the quantity/cost table.  Maintaining a
    // second shortened calculator here caused different totals for profiles,
    // panels and shutters depending on which button the user pressed.
    widget.model.clearSelection();
    final calculated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => MaterialConsumptionScreen(
          model: widget.model,
          autoCalculateAndSave: true,
        ),
      ),
    );
    if (!context.mounted) return;
    if (calculated == true) {
      Navigator.pop(context, widget.model);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate(
              'تعذر احتساب السعر. راجع أسعار المكونات في جدول الكمية والتكلفة.',
              lang,
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
    return;

    // إظهار مؤشر تحميل احتساب السعر
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dbInstance = SqlDatabase();
      final engine = BomEngineV2(database: dbInstance);
      var bom = ComponentCalculator.generateBom(widget.model, {});
      await engine.stabilizeSelections(window: widget.model, items: bom);
      bom = ComponentCalculator.generateBom(widget.model, {});
      await engine.stabilizeSelections(window: widget.model, items: bom);
      bom = await engine.filterItemsByAvailableCandidates(
        window: widget.model,
        items: bom,
      );

      final prefs = await SharedPreferences.getInstance();
      // Purchase prices are already the weighted average cost stored in the
      // price tables the BOM reads, so no extra override is needed here.
      var method =
          CostMethod.values[prefs.getInt('app_cost_method') ??
              CostMethod.percentage.index];
      if (widget.model.isShutterOnly && method == CostMethod.linearMeter) {
        method = CostMethod.percentage;
      }

      final pricingRules = await dbInstance.getProfileCalculationRules();
      final database = await dbInstance.db;

      Future<double> installationFee(String type) async {
        final rows =
            await database?.query(
              'ShutterSqmPrices',
              columns: ['price_per_sqm'],
              where: 'blade_type = ? AND color_id = ?',
              whereArgs: [type, 0],
              limit: 1,
            ) ??
            [];
        return rows.isEmpty
            ? 0.0
            : (rows.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
      }

      // Linear meter price from series/color or DB
      double linearMeterPrice = 0.0;
      final seriesId =
          widget.model.activeFrameSeries?.id ??
          widget.model.effectiveSlidingSeries?.id ??
          widget.model.activeSeries?.id;
      final rawColorId = widget.model.selectedDbColor?['id'];
      final colorId = rawColorId is num
          ? rawColorId.toInt()
          : int.tryParse('${rawColorId ?? ''}');

      if (seriesId != null) {
        if (colorId != null) {
          linearMeterPrice = await dbInstance.getSeriesColorPrice(
            seriesId,
            colorId,
          );
        }
        if (linearMeterPrice <= 0.0) {
          final seriesRows =
              await database?.query(
                'Series',
                columns: ['price_per_meter'],
                where: 'id = ?',
                whereArgs: [seriesId],
                limit: 1,
              ) ??
              [];
          if (seriesRows.isNotEmpty) {
            linearMeterPrice =
                (seriesRows.first['price_per_meter'] as num?)?.toDouble() ??
                0.0;
          }
        }
      }
      if (linearMeterPrice <= 0.0) {
        linearMeterPrice = prefs.getDouble('app_price_linear_meter') ?? 0.0;
      }

      // Shutter sqm price from DB
      double shutterSqmPrice = 0.0;
      String actualBladeName = '';
      String bladeSubtype = 'normal';
      final lamesOverride = widget.model.componentOverrides['الشرائح (Lames)'];
      if (lamesOverride != null) {
        actualBladeName = (lamesOverride['name'] ?? '').toString();
        bladeSubtype = (lamesOverride['shutter_subtype'] ?? 'normal')
            .toString();
      } else if (widget.model.shutterLame.isNotEmpty) {
        actualBladeName = widget.model.shutterLame;
      }
      if (actualBladeName.isNotEmpty || bladeSubtype.isNotEmpty) {
        final allSqmPrices = await database?.query('ShutterSqmPrices') ?? [];
        shutterSqmPrice = WindowModel.resolveShutterSqmPrice(
          bladeName: actualBladeName,
          bladeSubtype: bladeSubtype,
          colorId: colorId,
          prices: allSqmPrices,
        );
      }
      if (shutterSqmPrice <= 0.0) {
        shutterSqmPrice = prefs.getDouble('app_shutter_price_per_sqm') ?? 0.0;
      }

      final totals = calculateSellingTotals(
        model: widget.model,
        items: bom,
        costMethod: method,
        profitMargin: prefs.getDouble('app_profit_margin') ?? 0,
        pricePerSqm: prefs.getDouble('app_price_per_sqm') ?? 0,
        linearMeterPrice: linearMeterPrice,
        shutterSqmPrice: shutterSqmPrice,
        moustiquaireSqmPrice: await dbInstance.getShutterSqmPrice(
          'Moustiquaire_Sqm',
          0,
        ),
        profileRules: {
          for (final rule in pricingRules)
            if (rule['section_id'] is num)
              (rule['section_id'] as num).toInt(): rule,
        },
        obInstallFee: await installationFee('OB_Install'),
        demiObInstallFee: await installationFee('DemiOB_Install'),
        verrouInstallFee: await installationFee('Verrou_Install'),
        moteurInstallFee: await installationFee('Moteur_Install'),
      );

      final qty = widget.model.quantity <= 0 ? 1 : widget.model.quantity;
      final unitPrice = (totals['total']?['selling'] ?? 0.0) / qty;
      if (unitPrice.isFinite && unitPrice > 0) {
        widget.model.totalCost = unitPrice;
        widget.model.manualPriceOverride = unitPrice;
      }
    } catch (e) {
      debugPrint('Error calculating price in _addDrawingAndCalculate: $e');
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // إغلاق مؤشر التحميل
      }
    }

    widget.model.clearSelection();
    if (context.mounted) {
      Navigator.pop(context, widget.model);
    }
  }
}
