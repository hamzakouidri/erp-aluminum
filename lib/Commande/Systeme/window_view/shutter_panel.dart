part of '../show_system_francais.dart';

/// Roller shutter controls of the drawing page.
extension _WindowViewShutter on _WindowViewState {
  void _toggleShutterFeature() {
    final newVal = !widget.model.hasShutter;
    widget.model.toggleShutter(newVal);
    if (newVal &&
        (widget.model.shutterDriveSide == null ||
            widget.model.shutterDriveSide!.isEmpty)) {
      widget.model.setAllShutterDriveSide('right');
    }
    widget.model.notifyListeners();
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _showShortcutFeedback(
      Localization.translate(
        newVal ? 'تم تفعيل الستار' : 'تم إلغاء الستار',
        lang,
      ),
      icon: newVal ? Icons.layers_rounded : Icons.layers_clear_rounded,
      color: newVal ? Colors.green.shade700 : Colors.red.shade700,
    );
    _setViewState(() {});
  }

  void _toggleMoustiquaireAddon() {
    final enabled = !widget.model.hasMoustiquaireAddon;
    widget.model.hasMoustiquaireAddon = enabled;
    widget.model.notifyListeners();
    _showShortcutFeedback(
      enabled
          ? 'تمت إضافة الموستيكير إلى حساب النافذة'
          : 'تم حذف الموستيكير من حساب النافذة',
      icon: Icons.grid_on_rounded,
      color: enabled ? Colors.green.shade700 : Colors.red.shade700,
    );
    _setViewState(() {});
  }

  void _toggleCaissonTunnelFeature() {
    final newVal = !widget.model.isCaissonTunnel;
    widget.model.toggleCaissonTunnel(newVal);
    widget.model.refreshUI();
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _showShortcutFeedback(
      Localization.translate(
        newVal ? 'تم تفعيل صندوق النفق' : 'تم إلغاء صندوق النفق',
        lang,
      ),
      icon: Icons.horizontal_rule_rounded,
      color: newVal ? Colors.deepPurple.shade700 : Colors.red.shade700,
    );
    _setViewState(() {});
  }

  void _setShutterMechanismFeature(String requestedMechanism) {
    if (!widget.model.hasShutter) {
      widget.model.toggleShutter(true);
    }
    final mechanism = switch (requestedMechanism) {
      'مانيفال' || 'مانيفر' => 'منايفال',
      'محرك' => 'محرك',
      _ => 'حزام',
    };
    widget.model.setAllShutterMechanism(mechanism);
    if (mechanism == 'حزام') {
      widget.model.shutterDriveSide = 'left';
      widget.model.setAllShutterDriveSide('left');
    }
    widget.model.refreshUI();
    unawaited(widget.model.updateShutterDefaultsIfNeeded());
    if (mounted) _setViewState(() {});
  }

  void _cycleShutterMechanismFeature() {
    final current = widget.model.shutterMechanism;
    String next;
    if (current == 'محرك') {
      next = 'منايفال';
    } else if (current == 'منايفال' ||
        current == 'مانيفال' ||
        current == 'مانيفر') {
      next = 'حزام';
    } else {
      next = 'محرك';
    }
    _setShutterMechanismFeature(next);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String labelKey;
    IconData icon;
    switch (next) {
      case 'محرك':
        labelKey = 'آلية الستار: محرك';
        icon = Icons.electrical_services_rounded;
        break;
      case 'منايفال':
        labelKey = 'آلية الستار: منايفال';
        icon = Icons.rotate_right_rounded;
        break;
      default:
        labelKey = 'آلية الستار: حزام';
        icon = Icons.line_weight_rounded;
        break;
    }
    _showShortcutFeedback(
      Localization.translate(labelKey, lang),
      icon: icon,
      color: Colors.indigo.shade700,
    );
  }

  void _toggleShutterDriveSideFeature([String? targetSide]) {
    if (!widget.model.hasShutter) {
      widget.model.toggleShutter(true);
    }
    final newSide =
        targetSide ??
        (widget.model.shutterDriveSide == 'right' ? 'left' : 'right');
    widget.model.shutterDriveSide = newSide;
    widget.model.setAllShutterDriveSide(newSide);
    widget.model.notifyListeners();
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _showShortcutFeedback(
      Localization.translate(
        newSide == 'right'
            ? 'جهة تحكم الستار: اليمين'
            : 'جهة تحكم الستار: اليسار',
        lang,
      ),
      icon: newSide == 'right'
          ? Icons.keyboard_double_arrow_right_rounded
          : Icons.keyboard_double_arrow_left_rounded,
      color: Colors.blue.shade700,
    );
    _setViewState(() {});
  }

  bool _isCaissonTunnelOption(Map<String, dynamic> option) {
    final name = (option['name'] ?? '').toString().toLowerCase();
    final type = (option['component_type'] ?? '').toString().toLowerCase();
    return name.contains('tunnel') ||
        name.contains('نفق') ||
        type.contains('tunnel') ||
        type.contains('نفق');
  }

  double? _caissonSizeMm(Map<String, dynamic> option) {
    final raw = getComponentSize(option);
    if (raw == null || raw.trim().isEmpty) return null;
    var size = double.tryParse(raw.replaceAll(',', '.'));
    if (size == null || size <= 0) return null;
    if (size < 100) size *= 10;
    return size;
  }

  // ── تحميل خيارات الستار من قاعدة البيانات ──
  Future<void> _loadShutterOptions() async {
    if (_loadingShutterOptions) return;
    _setViewState(() => _loadingShutterOptions = true);
    try {
      final db = SqlDatabase();
      final dbInstance = await db.db;
      if (dbInstance == null) return;

      // الشفرات (Lames)
      final lames = await dbInstance.query(
        'ShutterComponents',
        where:
            "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      // السكك (Coulisses)
      final coulisses = await dbInstance.query(
        'ShutterComponents',
        where:
            "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      // الصناديق (Caisson)
      final caissonRes = await dbInstance.query(
        'ShutterComponents',
        where:
            "(LOWER(name) LIKE '%caisson%' OR name LIKE '%صندوق%' OR LOWER(component_type) LIKE '%caisson%' OR LOWER(component_type) LIKE '%box%') AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'name ASC',
      );

      final seriesId = activeSeriesForSystem?.id;
      final shutterRules = seriesId == null
          ? <Map<String, dynamic>>[]
          : await db.getSeriesShutterRules(seriesId);

      // The shutter is independent from the drawing series.  Do not apply
      // any series-specific profile rules to its catalogue choices.
      final configuredLames = lames
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final configuredCoulisses = coulisses
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final configuredCaissons = caissonRes
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      // A box is selectable only when the limit configured for the current
      // blade on the price-management page accepts this window height.  The
      // same rule is used by the material calculation, so the visual choice
      // can never disagree with the required-goods table.
      final unavailableCaissonReasons = <int, String>{};
      Map<String, dynamic>? selectedBlade;
      final rawBlade = widget.model.componentOverrides['الشرائح (Lames)'];
      if (rawBlade is Map) {
        selectedBlade = Map<String, dynamic>.from(rawBlade);
      }
      if (selectedBlade == null) {
        for (final blade in configuredLames) {
          if (blade['name']?.toString() == widget.model.shutterLame) {
            selectedBlade = blade;
            break;
          }
        }
      }
      final bladeId = (selectedBlade?['id'] as num?)?.toInt();
      if (widget.model.hasShutter && bladeId != null) {
        final limits = await dbInstance.query(
          'ShutterBoxLimits',
          where: 'blade_id = ?',
          whereArgs: [bladeId],
        );
        final fallbackMinimumSize = widget.model.height > 2400
            ? 205.0
            : (widget.model.height > 1600 ? 185.0 : 155.0);
        if (limits.isNotEmpty) {
          for (final caisson in configuredCaissons) {
            if (_isCaissonTunnelOption(caisson)) continue;
            final id = (caisson['id'] as num?)?.toInt();
            final size = _caissonSizeMm(caisson);
            if (id == null || size == null) continue;
            final matchingLimits = limits.where((limit) {
              final limitSize = (limit['box_size'] as num?)?.toDouble() ?? 0;
              return (limitSize - size).abs() < 5;
            });
            final maxHeight = matchingLimits
                .map((limit) => (limit['max_height'] as num?)?.toDouble() ?? 0)
                .fold<double>(0, (max, value) => value > max ? value : max);
            if (maxHeight <= 0) {
              unavailableCaissonReasons[id] =
                  'هذا الصندوق غير مضبوط لهذه الشفرة في حدود الستار.';
            } else if (widget.model.height > maxHeight) {
              unavailableCaissonReasons[id] =
                  'الحد الأقصى لهذا الصندوق ${maxHeight.toStringAsFixed(0)} مم.';
            }
          }
        } else {
          for (final caisson in configuredCaissons) {
            if (_isCaissonTunnelOption(caisson)) continue;
            final id = (caisson['id'] as num?)?.toInt();
            final size = _caissonSizeMm(caisson);
            if (id == null || size == null) continue;
            if (size + 0.5 < fallbackMinimumSize) {
              unavailableCaissonReasons[id] =
                  'هذا الصندوق أصغر من الحد المطلوب ${fallbackMinimumSize.toStringAsFixed(0)} مم.';
            }
          }
        }
      }

      if (mounted) {
        _setViewState(() {
          _shutterLamesOptions = configuredLames;
          _shutterCoulisseOptions = configuredCoulisses;
          _shutterCaissonOptions = configuredCaissons;
          _unavailableCaissonReasons = unavailableCaissonReasons;
          _loadingShutterOptions = false;
        });
      }
      if (widget.model.hasShutter) {
        unawaited(widget.model.updateShutterDefaultsIfNeeded());
      }
    } catch (e) {
      if (mounted) _setViewState(() => _loadingShutterOptions = false);
    }
  }

  void _activateShutterFromDesign() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final hasMeasuredDrawing =
        widget.model.width > 0 && widget.model.height > 0;
    final convertingExistingDrawing =
        hasMeasuredDrawing && !widget.model.isShutterOnly;
    _setViewState(() {
      if (convertingExistingDrawing) {
        widget.model.convertCurrentDrawingToShutter();
      } else if (!widget.model.isShutterOnly) {
        widget.model.prepareShutterOnlyDrawing();
      }
      _isShutterSelected = true;
      _isBottomPanelExpanded = true;
      _isDrawerOpen = false;
      _isLeftDrawerOpen = false;
      _activeShutterTab = 0;
    });

    if (_shutterLamesOptions.isEmpty && _shutterCoulisseOptions.isEmpty) {
      _loadShutterOptions();
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          Localization.translate(
            convertingExistingDrawing
                ? 'تم تحويل القياس الحالي إلى ستار'
                : 'ارسم مستطيل الستار على اللوحة',
            lang,
          ),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showSplitShutterDialog(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final frames = List<Rect>.from(widget.model.getFrameRects())
      ..sort((a, b) => a.left.compareTo(b.left));
    final hasMultipleFrames = frames.length > 1;

    int selectedTab = widget.model.isShutterSplit
        ? (widget.model.shutterSplitMode == 'custom_divisions' ||
                  widget.model.shutterSplitMode == 'custom'
              ? 1
              : 0)
        : (hasMultipleFrames ? 0 : 1);

    int divisionCount = widget.model.shutterSplits.length >= 2
        ? widget.model.shutterSplits.length
        : 2;

    List<TextEditingController> divisionControllers = [];
    final Map<int, String> divisionMechanisms = {};
    final Map<int, String> divisionDriveSides = {};
    void initDivisionControllers(int count) {
      for (final c in divisionControllers) {
        c.dispose();
      }
      divisionControllers = [];
      if (widget.model.isShutterSplit &&
          (widget.model.shutterSplitMode == 'custom_divisions' ||
              widget.model.shutterSplitMode == 'custom') &&
          widget.model.shutterSplits.length == count) {
        for (int i = 0; i < widget.model.shutterSplits.length; i++) {
          final expectedLabel = 'صندوق ${i + 1}';
          final matching = widget.model.shutterSplits.where(
            (split) => split.label == expectedLabel,
          );
          final s = matching.isNotEmpty
              ? matching.first
              : widget.model.shutterSplits[i];
          divisionControllers.add(
            TextEditingController(text: s.width.toStringAsFixed(1)),
          );
          divisionMechanisms[i] = s.mechanism ?? widget.model.shutterMechanism;
          divisionDriveSides[i] = s.driveSide ?? widget.model.shutterDriveSide;
        }
      } else {
        final equalW = (widget.model.width / count).toStringAsFixed(1);
        for (int i = 0; i < count; i++) {
          divisionControllers.add(TextEditingController(text: equalW));
          divisionMechanisms.putIfAbsent(
            i,
            () => widget.model.shutterMechanism,
          );
          divisionDriveSides.putIfAbsent(
            i,
            () => widget.model.shutterDriveSide,
          );
        }
      }
    }

    initDivisionControllers(divisionCount);

    final defaultDrawingHeight = widget.model.height.toDouble();
    final Map<int, TextEditingController> frameHeightControllers = {};
    final Map<int, String> frameMechanisms = {};
    final Map<int, String> frameDriveSides = {};
    for (int i = 0; i < frames.length; i++) {
      double? existingH;
      ShutterSplitSection? existingSplit;
      if (widget.model.isShutterSplit) {
        final match = widget.model.shutterSplits.where(
          (s) => s.frameIndex == i,
        );
        if (match.isNotEmpty) {
          existingSplit = match.first;
          existingH = existingSplit.customHeight;
        }
      }
      frameMechanisms[i] =
          existingSplit?.mechanism ?? widget.model.shutterMechanism;
      frameDriveSides[i] =
          existingSplit?.driveSide ?? widget.model.shutterDriveSide;
      final frameTotalH =
          (widget.model.hasShutter && !widget.model.isCaissonTunnel)
          ? (frames[i].height + widget.model.shutterBoxHeight)
          : frames[i].height;
      final effectiveDefaultH = (frameTotalH - defaultDrawingHeight).abs() < 1.0
          ? defaultDrawingHeight
          : frameTotalH;
      frameHeightControllers[i] = TextEditingController(
        text: (existingH ?? effectiveDefaultH).toStringAsFixed(1),
      );
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.view_column_rounded,
                    color: Colors.teal.shade400,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate(
                            'فصل وتقسيم صناديق الستار',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          widget.model.isShutterSplit
                              ? '${Localization.translate('الحالة: مفصول إلى', lang)} (${widget.model.effectiveShutterSplits.length}) ${Localization.translate('صناديق مستقلة', lang)}'
                              : Localization.translate(
                                  'الحالة: صندوق واحد موحد',
                                  lang,
                                ),
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.model.isShutterSplit
                                ? Colors.teal
                                : Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () =>
                                    setDialogState(() => selectedTab = 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selectedTab == 0
                                        ? (isDark
                                              ? Colors.teal.shade800
                                              : Colors.teal.shade100)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      Localization.translate(
                                        'صندوق لكل إطار',
                                        lang,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selectedTab == 0
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selectedTab == 0
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.teal.shade900)
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () =>
                                    setDialogState(() => selectedTab = 1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selectedTab == 1
                                        ? (isDark
                                              ? Colors.teal.shade800
                                              : Colors.teal.shade100)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      Localization.translate(
                                        'تقسيم إطار واحد',
                                        lang,
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: selectedTab == 1
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: selectedTab == 1
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.teal.shade900)
                                            : (isDark
                                                  ? Colors.white70
                                                  : Colors.black87),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (selectedTab == 0) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localization.translate(
                                    'التقسيم التلقائي يخصص صندوقاً مستقلاً ومحركاً ومجاري لكل إطار (بما في ذلك زاوية 90° دون إنقاص قياس الستار). يمكنك تعديل ارتفاع الستار للإطار الأقصر.',
                                    lang,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${Localization.translate('الإطارات المكتشفة', lang)} (${frames.length}):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...frames.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final frame = entry.value;
                          final hCtrl = frameHeightControllers[idx]!;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF28283E)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.teal.withOpacity(
                                        0.2,
                                      ),
                                      child: Text(
                                        '${idx + 1}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${Localization.translate('إطار', lang)} ${idx + 1}',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          Text(
                                            '${Localization.translate('العرض', lang)}: ${frame.width.toStringAsFixed(0)} mm',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: hCtrl,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'ارتفاع الستار',
                                            lang,
                                          ),
                                          labelStyle: const TextStyle(
                                            fontSize: 10,
                                          ),
                                          suffixText: 'mm',
                                          suffixStyle: const TextStyle(
                                            fontSize: 10,
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: frameMechanisms[idx],
                                        isDense: true,
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'نوع الستار',
                                            lang,
                                          ),
                                          border: const OutlineInputBorder(),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'حزام',
                                            child: Text(
                                              Localization.translate(
                                                'حزام',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'منايفال',
                                            child: Text(
                                              Localization.translate(
                                                'مانيفيل',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'محرك',
                                            child: Text(
                                              Localization.translate(
                                                'محرك',
                                                lang,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setDialogState(() {
                                            frameMechanisms[idx] = value;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: frameDriveSides[idx],
                                        isDense: true,
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'جهة الستار',
                                            lang,
                                          ),
                                          border: const OutlineInputBorder(),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'left',
                                            child: Text(
                                              Localization.translate(
                                                'يسار',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'right',
                                            child: Text(
                                              Localization.translate(
                                                'يمين',
                                                lang,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setDialogState(() {
                                            frameDriveSides[idx] = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  Localization.translate(
                                    'تقسيم الصندوق في إطار واحد إلى عدة أقسام مستقلة. الترتيب يبدأ من اليمين إلى اليسار.',
                                    lang,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  Localization.translate('عدد الأقسام:', lang),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SegmentedButton<int>(
                                  showSelectedIcon: false,
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  segments: const [
                                    ButtonSegment(value: 2, label: Text('2')),
                                    ButtonSegment(value: 3, label: Text('3')),
                                    ButtonSegment(value: 4, label: Text('4')),
                                  ],
                                  selected: {divisionCount},
                                  onSelectionChanged: (Set<int> newSelection) {
                                    setDialogState(() {
                                      divisionCount = newSelection.first;
                                      initDivisionControllers(divisionCount);
                                    });
                                  },
                                ),
                              ],
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(Icons.balance, size: 16),
                              label: Text(
                                Localization.translate('توزيع بالتساوي', lang),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  final equalW =
                                      (widget.model.width / divisionCount)
                                          .toStringAsFixed(1);
                                  for (final c in divisionControllers) {
                                    c.text = equalW;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(divisionCount, (i) {
                          final label = i == 0
                              ? Localization.translate(
                                  'الصندوق 1 (اليمين)',
                                  lang,
                                )
                              : (i == divisionCount - 1
                                    ? '${Localization.translate('الصندوق', lang)} ${i + 1} (${Localization.translate('اليسار', lang)})'
                                    : '${Localization.translate('الصندوق', lang)} ${i + 1} (${Localization.translate('الوسط', lang)})');
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF28283E)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.teal.withOpacity(
                                        0.2,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        controller: divisionControllers[i],
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        onChanged: (val) {
                                          final entered = double.tryParse(
                                            val.replaceAll(',', '.').trim(),
                                          );
                                          if (entered != null && entered > 0) {
                                            final remaining =
                                                widget.model.width - entered;
                                            final otherIndices = List.generate(
                                              divisionCount,
                                              (idx) => idx,
                                            )..remove(i);
                                            if (otherIndices.isNotEmpty &&
                                                remaining > 0) {
                                              final share =
                                                  (remaining /
                                                          otherIndices.length)
                                                      .toStringAsFixed(1);
                                              for (final otherIdx
                                                  in otherIndices) {
                                                divisionControllers[otherIdx]
                                                        .text =
                                                    share;
                                              }
                                            }
                                          }
                                        },
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'العرض',
                                            lang,
                                          ),
                                          labelStyle: const TextStyle(
                                            fontSize: 10,
                                          ),
                                          suffixText: 'mm',
                                          suffixStyle: const TextStyle(
                                            fontSize: 10,
                                          ),
                                          isDense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: divisionMechanisms[i],
                                        isDense: true,
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'نوع الستار',
                                            lang,
                                          ),
                                          border: const OutlineInputBorder(),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'حزام',
                                            child: Text(
                                              Localization.translate(
                                                'حزام',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'منايفال',
                                            child: Text(
                                              Localization.translate(
                                                'مانيفيل',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'محرك',
                                            child: Text(
                                              Localization.translate(
                                                'محرك',
                                                lang,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setDialogState(() {
                                            divisionMechanisms[i] = value;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: divisionDriveSides[i],
                                        isDense: true,
                                        decoration: InputDecoration(
                                          labelText: Localization.translate(
                                            'جهة الستار',
                                            lang,
                                          ),
                                          border: const OutlineInputBorder(),
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: 'left',
                                            child: Text(
                                              Localization.translate(
                                                'يسار',
                                                lang,
                                              ),
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: 'right',
                                            child: Text(
                                              Localization.translate(
                                                'يمين',
                                                lang,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setDialogState(() {
                                            divisionDriveSides[i] = value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                        Container(
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${Localization.translate('العرض الكلي للإطار:', lang)} ${widget.model.width.toStringAsFixed(1)} mm',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                if (widget.model.isShutterSplit)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                    ),
                    icon: const Icon(Icons.merge_type, size: 16),
                    label: Text(
                      Localization.translate(
                        'دمج الصناديق (إلغاء الفصل)',
                        lang,
                      ),
                    ),
                    onPressed: () {
                      _setViewState(() {
                        widget.model.resetShutterSplit();
                      });
                      widget.model.refreshUI();
                      Navigator.pop(dialogCtx);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(Localization.translate('تطبيق الفصل', lang)),
                  onPressed: () {
                    _setViewState(() {
                      if (selectedTab == 0) {
                        widget.model.autoSplitShutterPerFrame();
                        for (int i = 0; i < frames.length; i++) {
                          final hVal = double.tryParse(
                            frameHeightControllers[i]!.text.replaceAll(
                              ',',
                              '.',
                            ),
                          );
                          if (hVal != null && hVal > 0) {
                            widget.model.setShutterSplitHeight(i, hVal);
                          }
                          widget.model.setShutterSplitDrive(
                            i,
                            mechanism:
                                frameMechanisms[i] ??
                                widget.model.shutterMechanism,
                            driveSide:
                                frameDriveSides[i] ??
                                widget.model.shutterDriveSide,
                          );
                        }
                      } else {
                        final widths = divisionControllers
                            .map(
                              (c) =>
                                  double.tryParse(
                                    c.text.replaceAll(',', '.'),
                                  ) ??
                                  (widget.model.width / divisionCount),
                            )
                            .toList();
                        widget.model.splitShutterCustomDivisions(
                          widths,
                          startFromRight: true,
                          mechanisms: List.generate(
                            divisionCount,
                            (i) =>
                                divisionMechanisms[i] ??
                                widget.model.shutterMechanism,
                          ),
                          driveSides: List.generate(
                            divisionCount,
                            (i) =>
                                divisionDriveSides[i] ??
                                widget.model.shutterDriveSide,
                          ),
                        );
                      }
                    });
                    widget.model.refreshUI();
                    Navigator.pop(dialogCtx);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ignore: unused_element
  Widget buildShutterSidesControl(
    BuildContext context,
    WindowModel model,
    AppLanguage lang,
  ) {
    if (!model.hasSideCovers && !model.hasShutter) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6.0,
          runSpacing: 4.0,
          children: [
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('علوية', lang)),
              selected: !model.removedShutterSides.contains('top'),
              onSelected: (_) => model.toggleShutterSide('top'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('يسرى', lang)),
              selected: !model.removedShutterSides.contains('left'),
              onSelected: (_) => model.toggleShutterSide('left'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('يمنى', lang)),
              selected: !model.removedShutterSides.contains('right'),
              onSelected: (_) => model.toggleShutterSide('right'),
            ),
            FilterChip(
              labelStyle: const TextStyle(fontSize: 10),
              label: Text(Localization.translate('سفلية', lang)),
              selected:
                  model.hasBottomFrame &&
                  !model.removedShutterSides.contains('bottom'),
              onSelected: model.hasBottomFrame
                  ? (_) => model.toggleShutterSide('bottom')
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShutterBottomPanel(BuildContext context) {
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 1,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _setViewState(() {
                _isBottomPanelExpanded = false;
                _isShutterSelected = false;
              }),
              child: Container(
                width: double.infinity,
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Center(
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.blue.shade700,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (!widget.model.isShutterOnly) ...[
              // ── Main Tab Bar showing "الستار (Volet)" selected ──
              _buildTier1TabBar(isMullionSelected),
              const Divider(height: 1, thickness: 0.5),
            ],
            // ── تبويبات الستار (Tier 1 of Shutter) ──
            _buildShutterTier1TabBar(),
            const Divider(height: 1, thickness: 0.5),
            // ── محتوى التبويب (Tier 2) ──
            SizedBox(
              height: 110,
              child: _loadingShutterOptions
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _HorizontalWheelScrollArea(
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          // Caissons, blades and tracks can have long labels.
                          // Keep every shutter option on one horizontally
                          // scrollable row instead of forcing two tall rows
                          // into the fixed bottom-panel height.
                          children: _buildShutterTier2Options(context),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShutterTier1TabBar() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final tabs = [
      {'id': 0, 'label': 'شائع', 'icon': Icons.tune_rounded},
      {'id': 1, 'label': 'الصندوق', 'icon': Icons.inbox_rounded},
      {'id': 2, 'label': 'الشفرات', 'icon': Icons.view_week_rounded},
      {'id': 3, 'label': 'السكك', 'icon': Icons.linear_scale_rounded},
      {'id': 4, 'label': 'نوع الستار', 'icon': Icons.settings_rounded},
    ];

    return SizedBox(
      height: 44,
      child: _HorizontalWheelScrollArea(
        builder: (context, controller) => ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final id = tab['id'] as int;
            final isSelected = _activeShutterTab == id;
            return InkWell(
              onTap: () => _setViewState(() => _activeShutterTab = id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? Colors.orange.shade700
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      size: 15,
                      color: isSelected
                          ? Colors.orange.shade700
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      Localization.translate(tab['label'] as String, lang),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Colors.orange.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildShutterTier2Options(BuildContext context) {
    switch (_activeShutterTab) {
      case 0: // شائع
        return _buildShutterCommonOptions(context);
      case 1: // الصندوق
        return _buildShutterCaissonOptions(context);
      case 2: // الشفرات
        return _buildShutterLamesOptions2(context);
      case 3: // السكك
        return _buildShutterCoulisseOptions(context);
      case 4: // نوع الستار
        return _buildShutterMechanismOptions(context);
      default:
        return [];
    }
  }

  // تبويب شائع: تفعيل/إلغاء الستار + Caisson Tunnel
  List<Widget> _buildShutterCommonOptions(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final items = <Widget>[];

    if (!widget.model.isShutterOnly) {
      // تفعيل/إلغاء الستار
      items.add(
        _ShutterChip(
          label: Localization.translate('الستار', lang),
          icon: Icons.layers_rounded,
          selected: widget.model.hasShutter,
          color: Colors.orange,
          onTap: () {
            final enable = !widget.model.hasShutter;
            _setViewState(() {
              widget.model.toggleShutter(enable);
              if (!enable) _isShutterSelected = false;
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.hasShutter && widget.model.shutterWidthWarning != null) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      final rec = widget.model.recommendedShutterBlade;
      items.add(
        Container(
          width: 360,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.straighten,
                    color: Colors.orange.shade800,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.model.localizedShutterWidthWarning(lang) ??
                          widget.model.shutterWidthWarning!,
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (rec != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 14),
                    label: Text(
                      lang == AppLanguage.french
                          ? 'Appliquer la recommandation'
                          : (lang == AppLanguage.english
                                ? 'Apply recommendation'
                                : 'تطبيق المقترح'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      widget.model.applyRecommendedShutterBlade();
                      await widget.model.updateShutterDefaultsIfNeeded();
                      if (mounted) _setViewState(() {});
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.shutterHeightWarning != null) {
      items.add(
        _ShutterChip(
          label: widget.model.shutterHeightWarning!,
          icon: Icons.warning_amber_rounded,
          selected: true,
          color: Colors.red,
          onTap: () {},
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    // صندوق النفق
    items.add(
      _ShutterChip(
        label: Localization.translate('صندوق النفق (Caisson tunnel)', lang),
        icon: Icons.horizontal_rule_rounded,
        selected: widget.model.isCaissonTunnel,
        color: Colors.deepPurple,
        onTap: () {
          _setViewState(() {
            widget.model.toggleCaissonTunnel(!widget.model.isCaissonTunnel);
            widget.model.refreshUI();
          });
        },
      ),
    );
    items.add(const SizedBox(width: 8));

    // غطاء جانبي
    items.add(
      _ShutterChip(
        label: 'غطاء جانبي',
        icon: Icons.border_left_rounded,
        selected: widget.model.hasSideCovers,
        color: Colors.teal,
        onTap: () async {
          await widget.model.toggleSideCovers(!widget.model.hasSideCovers);
          if (mounted) _setViewState(() {});
        },
      ),
    );

    return items;
  }

  // تبويب الصندوق
  List<Widget> _buildShutterCaissonOptions(BuildContext context) {
    if (_shutterCaissonOptions.isEmpty) {
      return [
        Center(
          child: Text(
            _tr('لا توجد صناديق في قاعدة البيانات'),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['الصندوق (Caisson)'];
    final currentId = current?['id'];
    return _shutterCaissonOptions.map((opt) {
      final optionId = (opt['id'] as num?)?.toInt();
      final isTunnelOption = _isCaissonTunnelOption(opt);
      final unavailableReason = optionId == null
          ? null
          : _unavailableCaissonReasons[optionId];
      final isAvailable = unavailableReason == null;
      final isSelected = isTunnelOption
          ? widget.model.isCaissonTunnel
          : (!widget.model.isCaissonTunnel &&
                currentId != null &&
                opt['id'] == currentId);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: isAvailable ? Icons.inbox_rounded : Icons.block_outlined,
            selected: isSelected,
            color: Colors.indigo,
            enabled: isAvailable,
            disabledHint: unavailableReason,
            onTap: () async {
              if (isTunnelOption) {
                widget.model.toggleCaissonTunnel(true);
                if (mounted) _setViewState(() {});
                return;
              }
              final mutable = Map<String, dynamic>.from(opt);
              final rawPrice = opt['price_dzd'] ?? opt['price'] ?? 0.0;
              mutable['calculated_price'] = rawPrice is num
                  ? rawPrice.toDouble()
                  : double.tryParse(rawPrice.toString()) ?? 0.0;
              mutable['manual_selection'] = true;
              // A normal caisson must always leave tunnel mode first; otherwise
              // `shutterBoxHeight` is locked to the tunnel height and the
              // drawing keeps showing the old large box.
              if (widget.model.isCaissonTunnel) {
                widget.model.toggleCaissonTunnel(false);
              }
              widget.model.componentOverrides['الصندوق (Caisson)'] = mutable;
              await widget.model.updateShutterDefaultsIfNeeded();
              if (mounted) _setViewState(() {});
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();
  }

  // تبويب الشفرات
  List<Widget> _buildShutterLamesOptions2(BuildContext context) {
    if (_shutterLamesOptions.isEmpty) {
      return [
        Center(
          child: Text(
            _tr('لا توجد شفرات في قاعدة البيانات'),
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final current = widget.model.componentOverrides['الشرائح (Lames)'];
    final currentId = current?['id'];
    final list = _shutterLamesOptions.map<Widget>((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.view_week_rounded,
            selected: isSelected,
            color: Colors.brown,
            onTap: () async {
              final mutable = Map<String, dynamic>.from(opt);
              // Selecting a blade from the drawer is an explicit user choice.
              // Keep it even when its configured width is below the window;
              // the model will show a warning instead of silently replacing it.
              mutable['manual_selection'] = true;
              mutable['user_selected'] = true;
              mutable['automatic_selection'] = false;
              mutable['calculated_price'] =
                  (opt['price_dzd'] ?? opt['price'] ?? 0.0).toDouble();
              _setViewState(() {
                widget.model.componentOverrides['الشرائح (Lames)'] = mutable;
                widget.model.shutterLame =
                    mutable['name']?.toString() ?? widget.model.shutterLame;
                widget.model.refreshUI();
              });
              // X3D / Extrudé chooses its compatible axis and motor as soon
              // as the blade changes, not only after reopening the table.
              await widget.model.updateShutterDefaultsIfNeeded();
              if (!mounted) return;
              final selected =
                  widget.model.componentOverrides['الشرائح (Lames)'];
              if (selected?['id'] != opt['id']) return;
              final warning =
                  widget.model.localizedShutterWidthWarning(lang) ??
                  widget.model.shutterWidthWarning;
              if (warning != null) {
                final rec = widget.model.recommendedShutterBlade;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(warning),
                      backgroundColor: Colors.orange.shade900,
                      duration: const Duration(seconds: 8),
                      action: rec != null
                          ? SnackBarAction(
                              label: lang == AppLanguage.french
                                  ? 'Appliquer'
                                  : (lang == AppLanguage.english
                                        ? 'Apply'
                                        : 'تطبيق المقترح'),
                              textColor: Colors.yellowAccent,
                              onPressed: () async {
                                widget.model.applyRecommendedShutterBlade();
                                await widget.model
                                    .updateShutterDefaultsIfNeeded();
                                if (mounted) _setViewState(() {});
                              },
                            )
                          : null,
                    ),
                  );
              }
              _setViewState(() {});
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();

    if (widget.model.shutterWidthWarning != null) {
      final warning =
          widget.model.localizedShutterWidthWarning(lang) ??
          widget.model.shutterWidthWarning!;
      final rec = widget.model.recommendedShutterBlade;
      list.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.orange.shade900,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    warning,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (rec != null) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade900,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.check_circle, size: 14),
                    label: Text(
                      lang == AppLanguage.french
                          ? 'Appliquer'
                          : (lang == AppLanguage.english ? 'Apply' : 'تطبيق'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      widget.model.applyRecommendedShutterBlade();
                      await widget.model.updateShutterDefaultsIfNeeded();
                      if (mounted) _setViewState(() {});
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return list;
  }

  // تبويب السكك
  List<Widget> _buildShutterCoulisseOptions(BuildContext context) {
    final selectedBlade = widget.model.componentOverrides['الشرائح (Lames)'];
    final requiredTrackMeasurement = selectedBlade == null
        ? null
        : WindowModel.shutterMeasurementKey(
            Map<String, dynamic>.from(selectedBlade),
            preferTrackMeasurement: true,
          );
    final compatibleOptions = selectedBlade == null
        ? _shutterCoulisseOptions
        : WindowModel.compatibleShutterTracks(
            Map<String, dynamic>.from(selectedBlade),
            _shutterCoulisseOptions,
          );
    final options = requiredTrackMeasurement == null
        ? _shutterCoulisseOptions
        : compatibleOptions;
    if (options.isEmpty) {
      return [
        Center(
          child: Text(
            requiredTrackMeasurement == null
                ? 'لا توجد سكك في قاعدة البيانات'
                : 'لا توجد سكة مرتبطة بقياس $requiredTrackMeasurement مم لهذه الشفرة',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ];
    }
    final current = widget.model.componentOverrides['السكك (Coulisses)'];
    final currentId = current?['id'];
    return options.map((opt) {
      final isSelected = currentId != null && opt['id'] == currentId;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShutterChip(
            label: opt['name']?.toString() ?? '',
            icon: Icons.linear_scale_rounded,
            selected: isSelected,
            color: Colors.cyan.shade800,
            onTap: () {
              final mutable = Map<String, dynamic>.from(opt);
              final rawPrice = opt['price_dzd'] ?? opt['price'] ?? 0.0;
              mutable['calculated_price'] = rawPrice is num
                  ? rawPrice.toDouble()
                  : double.tryParse(rawPrice.toString()) ?? 0.0;
              _setViewState(() {
                widget.model.componentOverrides['السكك (Coulisses)'] = mutable;
                widget.model.refreshUI();
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      );
    }).toList();
  }

  // تبويب نوع الستار (الآلية)
  List<Widget> _buildShutterMechanismOptions(BuildContext context) {
    final items = <Widget>[];
    final mechanisms = [
      {'value': 'حزام', 'label': 'حزام', 'icon': Icons.radio_button_unchecked},
      {
        'value': 'منايفال',
        'label': 'مانيفال',
        'icon': Icons.settings_backup_restore_rounded,
      },
      {'value': 'محرك', 'label': 'محرك', 'icon': Icons.electric_bolt_rounded},
    ];
    for (final mech in mechanisms) {
      final val = mech['value'] as String;
      final isSelected =
          widget.model.shutterMechanism == val ||
          (val == 'منايفال' &&
              (widget.model.shutterMechanism == 'مانيفال' ||
                  widget.model.shutterMechanism == 'مانيفر'));
      items.add(
        _ShutterChip(
          label: mech['label'] as String,
          icon: mech['icon'] as IconData,
          selected: isSelected,
          color: Colors.deepOrange,
          onTap: () => _setShutterMechanismFeature(val),
        ),
      );
      items.add(const SizedBox(width: 8));
    }

    if (widget.model.shutterMechanism == 'محرك') {
      items.add(
        const VerticalDivider(width: 16, thickness: 1, indent: 8, endIndent: 8),
      );
      items.add(const SizedBox(width: 8));

      // قاطعة (Interrupteur)
      items.add(
        _ShutterChip(
          label: 'قاطعة (Interrupteur)',
          icon: Icons.power,
          selected: widget.model.motorHasInterrupteur,
          color: Colors.blue,
          onTap: () {
            _setViewState(() {
              widget.model.motorHasInterrupteur =
                  !widget.model.motorHasInterrupteur;
              widget.model.refreshUI();
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));

      // جهاز تحكم (Télécommande)
      items.add(
        _ShutterChip(
          label: 'جهاز تحكم (Télécommande)',
          icon: Icons.settings_remote,
          selected: widget.model.motorHasTelecommande,
          color: Colors.blue,
          onTap: () {
            _setViewState(() {
              widget.model.motorHasTelecommande =
                  !widget.model.motorHasTelecommande;
              widget.model.refreshUI();
            });
          },
        ),
      );
      items.add(const SizedBox(width: 8));
    }
    return items;
  }
}
