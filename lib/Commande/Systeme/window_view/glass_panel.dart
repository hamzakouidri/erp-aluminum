part of '../show_system_francais.dart';

/// Glass, panel and glazing-bead controls of the drawing page.
extension _WindowViewGlass on _WindowViewState {
  Widget _slidingGlassFitInfo(GlassSpecification spec) {
    final series = widget.model.effectiveSlidingSeries;
    final capacity = widget.model.glazingCapacityForStructure(
      spec.structure,
      sliding: true,
    );
    if (series == null || capacity == null) return const SizedBox.shrink();
    final glass = spec.totalThickness(widget.model.allGlassCache);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: CatalogCandidateResolver(database: SqlDatabase()).resolve(
        CatalogCandidateQuery(
          category: 'joint',
          selectorType: 'joint_bourrage',
          roleKeys: const ['joint_bourrage'],
          seriesId: series.id,
          materialType: widget.model.isSlidingPVC ? 'pvc' : 'aluminium',
          drawingMode: AccessoryDrawingMode.sliding,
          requireDialog: false,
          requireQuantity: true,
          hasSimpleGlassForReducer:
              spec.structure == GlassStructure.simple ||
              spec.structure == GlassStructure.closed,
          hasDoubleGlassForRules: spec.structure == GlassStructure.double,
        ),
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final fit = findGlassJointFit(
          candidates: snapshot.data!,
          glassThickness: glass,
          capacity: capacity,
          sides: spec.jointTwoSides ? 2 : 1,
        );
        final lang = context.read<AppSettingsProvider>().language;
        final unit = lang == AppLanguage.arabic ? 'مم' : 'mm';
        final message = fit == null
            ? (lang == AppLanguage.french
                ? 'Attention : Aucune combinaison de joints active ne correspond au vitrage ($glass $unit) et à la capacité ($capacity $unit). Le manque est interdit, tolérance max +1 $unit.'
                : lang == AppLanguage.english
                ? 'Warning: No active gasket combination matches glass ($glass $unit) and capacity ($capacity $unit). Deficit not allowed, max excess +1 $unit.'
                : 'تنبيه: لا توجد تركيبة جوانات مفعّلة تطابق الزجاج ($glass $unit) والسعة ($capacity $unit). النقص ممنوع والزيادة القصوى 1 $unit.')
            : (lang == AppLanguage.french
                ? 'Combinaison de joints suggérée : ${fit.map((row) => '${row['name']} (${row['thickness']} $unit)').join(' + ')}. Vitrage : $glass $unit, Capacité : $capacity $unit, tolérance max +1 $unit sans manque.'
                : lang == AppLanguage.english
                ? 'Suggested gasket combination: ${fit.map((row) => '${row['name']} (${row['thickness']} $unit)').join(' + ')}. Glass: $glass $unit, Capacity: $capacity $unit, max excess +1 $unit without deficit.'
                : 'تركيبة جوانات متوافقة مقترحة: ${fit.map((row) => '${row['name']} (${row['thickness']} $unit)').join(' + ')}. الزجاج: $glass $unit، السعة: $capacity $unit، الزيادة القصوى 1 $unit دون نقص.');
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            message,
            style: TextStyle(
              fontSize: 11,
              color: fit == null ? Colors.red : Colors.green,
            ),
          ),
        );
      },
    );
  }

  void _startPaintbrushMode({
    GlassFinish? finish,
    GlassStructure? structure,
    ZoneContent? zoneContent,
    int? slidingSashesCount,
    bool cellSash = false,
    bool cellPanel = false,
    GlassSpecification? glassSpec,
  }) {
    _paintbrushTimer?.cancel();
    _setViewState(() {
      _activePaintFinish = finish;
      _activePaintStructure = structure;
      _activePaintZoneContent = zoneContent;
      _activePaintSlidingSashesCount = slidingSashesCount;
      _activePaintCellSash = cellSash;
      _activePaintCellPanel = cellPanel;
      _activePaintGlassSpec = glassSpec;
      _paintbrushSecondsLeft = 10;
    });

    _paintbrushTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _setViewState(() {
        if (_paintbrushSecondsLeft > 1) {
          _paintbrushSecondsLeft--;
        } else {
          _paintbrushSecondsLeft = 0;
          _activePaintFinish = null;
          _activePaintStructure = null;
          _activePaintZoneContent = null;
          _activePaintSlidingSashesCount = null;
          _activePaintCellSash = false;
          _activePaintCellPanel = false;
          _activePaintGlassSpec = null;
          timer.cancel();
        }
      });
    });
  }

  void _cancelPaintbrushMode() {
    _paintbrushTimer?.cancel();
    _setViewState(() {
      _paintbrushSecondsLeft = 0;
      _activePaintFinish = null;
      _activePaintStructure = null;
      _activePaintZoneContent = null;
      _activePaintGlassSpec = null;
      _activePaintSlidingSashesCount = null;
      _activePaintCellSash = false;
      _activePaintCellPanel = false;
    });
  }

  Future<bool?> _askSlidingRebateCut(WindowZone zone) async {
    if (!widget.model.shouldAskSlidingRebateCut(zone)) return null;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('ركوب الزجاج للمنزلق', lang)),
        content: Text(
          Localization.translate(
            'هذا المنزلق داخل إطار واحد مقسم. هل سيتم قطع وحساب ركوب الزجاج حول منطقة المنزلق؟',
            lang,
          ),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(Localization.translate('لا', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(Localization.translate('نعم', lang)),
          ),
        ],
      ),
    );
  }

  bool _isDecorPanelSpec(GlassSpecification spec) {
    return spec.structure == GlassStructure.closed &&
        (isDecorPanelSubtype(spec.panneauSubtype) ||
            spec.finishOuter == GlassFinish.paneauSandwitchDecore);
  }

  Size _decorPanelFullSpace(WindowZone zone, String? cellId) {
    Rect target = zone.boundary;
    final isDouble = zone.content == ZoneContent.doubleSash;
    final isSash =
        isDouble ||
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.slidingSash;

    if (isDouble) {
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      const separator = 4.0;
      target = (cellId ?? '').startsWith('right')
          ? Rect.fromLTRB(
              splitX + separator / 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              splitX - separator / 2,
              zone.boundary.bottom,
            );
    } else if (zone.content == ZoneContent.slidingSash) {
      final count = math.max(1, zone.slidingSashesCount);
      target = Rect.fromLTWH(
        zone.boundary.left,
        zone.boundary.top,
        zone.boundary.width / count,
        zone.boundary.height,
      );
    }

    if (isSash) {
      final sashThickness =
          zone.sashThickness ??
          widget.model.getSectionThickness('sash', fallback: 45.0);
      final width = math.max(0.0, target.width - 2 * sashThickness);
      final height = math.max(0.0, target.height - 2 * sashThickness);
      return Size(width, height);
    }
    return Size(math.max(0.0, target.width), math.max(0.0, target.height));
  }

  bool _decorPanelSideHasDivisions(WindowZone zone, String? cellId) {
    final key = cellId ?? '';
    final hasLeftOrMain =
        zone.innerH > 0 ||
        zone.innerV > 0 ||
        zone.innerHPositions.isNotEmpty ||
        zone.innerVPositions.isNotEmpty;
    final hasRight =
        zone.rightInnerH > 0 ||
        zone.rightInnerV > 0 ||
        zone.rightInnerHPositions.isNotEmpty ||
        zone.rightInnerVPositions.isNotEmpty;
    if (key.startsWith('right')) return hasRight;
    if (key.startsWith('left') || key.startsWith('main')) {
      return hasLeftOrMain;
    }
    return hasLeftOrMain || hasRight;
  }

  Future<_DecorPlacementResult> _prepareDecorPanelPlacement({
    required WindowZone zone,
    required String? cellId,
    required GlassSpecification spec,
  }) async {
    if (!_isDecorPanelSpec(spec)) {
      return _DecorPlacementResult(true, cellId);
    }

    final product = widget.model.getPanneauProductForSpec(spec);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final decorWidth = product == null
        ? 0.0
        : _catalogNumber(product, 'visible_width');
    final decorHeight = product == null
        ? 0.0
        : _catalogNumber(product, 'height');
    final panelWidth = product == null
        ? 0.0
        : _catalogNumber(product, 'panel_width');
    final panelHeight = product == null
        ? 0.0
        : _catalogNumber(product, 'panel_height');
    if (product == null || decorWidth <= 0 || decorHeight <= 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Localization.translate('أبعاد البانو ديكور غير محددة', lang),
          ),
          content: Text(
            Localization.translate(
              'يجب تحديد عرض الديكور وطوله في منتج الزجاج أولاً.',
              lang,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('حسناً', lang)),
            ),
          ],
        ),
      );
      return _DecorPlacementResult(false, cellId);
    }

    final available = _decorPanelFullSpace(zone, cellId);
    if (panelWidth > 0 &&
        panelHeight > 0 &&
        !decorPanelSheetCoversSpace(
          spaceWidth: available.width,
          spaceHeight: available.height,
          panelWidth: panelWidth,
          panelHeight: panelHeight,
        )) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Localization.translate('لا يمكن وضع هذا البانو هنا', lang),
          ),
          content: Text(
            '${Localization.translate('مقاس البانو الكامل', lang)} '
            '${panelWidth.toStringAsFixed(0)} × ${panelHeight.toStringAsFixed(0)} '
            '${Localization.translate('مم', lang)} '
            '${Localization.translate('أصغر من المساحة المطلوبة', lang)} '
            '${available.width.toStringAsFixed(0)} × '
            '${available.height.toStringAsFixed(0)} '
            '${Localization.translate('مم', lang)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('حسناً', lang)),
            ),
          ],
        ),
      );
      return _DecorPlacementResult(false, cellId);
    }
    if (!decorPanelFitsSpace(
      spaceWidth: available.width,
      spaceHeight: available.height,
      decorWidth: decorWidth,
      decorHeight: decorHeight,
    )) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            Localization.translate('لا يمكن وضع هذا البانو هنا', lang),
          ),
          content: Text(
            '${Localization.translate('حجم الديكور', lang)} ${decorWidth.toStringAsFixed(0)} × ${decorHeight.toStringAsFixed(0)} ${Localization.translate('مم', lang)} '
            '${Localization.translate('يجب أن يكون أصغر من المساحة المتاحة بـ 30 مم في العرض والطول', lang)} ${available.width.toStringAsFixed(0)} × ${available.height.toStringAsFixed(0)} ${Localization.translate('مم', lang)}. '
            '${Localization.translate('ينبغي اختيار بانو آخر.', lang)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('حسناً', lang)),
            ),
          ],
        ),
      );
      return _DecorPlacementResult(false, cellId);
    }

    if (!_decorPanelSideHasDivisions(zone, cellId)) {
      return _DecorPlacementResult(true, cellId);
    }

    final removeDivisions = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('إلغاء التقسيم؟', lang)),
        content: Text(
          '${Localization.translate('البانو ديكور لا يقبل أي تقسيمات.', lang)} '
          '${Localization.translate('يجب إلغاء التقسيم الحالي لتفعيله. هل توافق؟', lang)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(Localization.translate('لا', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(Localization.translate('نعم', lang)),
          ),
        ],
      ),
    );
    if (removeDivisions != true) {
      return _DecorPlacementResult(false, cellId);
    }

    final normalizedCell = widget.model.removeSashDivisions(
      zoneOverride: zone,
      targetCellKey: cellId,
    );
    return _DecorPlacementResult(true, normalizedCell);
  }

  /// Synchronise the left glass drawer with the drawing being edited. A
  /// drawing with different glass specifications deliberately keeps the
  /// controls neutral, instead of borrowing an arbitrary selected cell.
  void _syncDrawerGlassFromDrawing() {
    _tempGlassSpec =
        widget.model.getUniformGlassSpecification() ??
        const GlassSpecification();
  }

  bool _checkAndStartGlassDecorDrag(
    String zoneId,
    Rect glassR,
    GlassSpecification spec,
    Offset touchScreen,
  ) {
    if (spec.structure != GlassStructure.double) return false;
    if (spec.decorH == 0 && spec.decorV == 0) return false;

    final double hitRadius = 50.0;

    List<double> hPositions = List.from(spec.decorHPositions);
    if (hPositions.isEmpty && spec.decorH > 0) {
      double stepY = 1.0 / (spec.decorH + 1);
      for (int i = 1; i <= spec.decorH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(spec.decorVPositions);
    if (vPositions.isEmpty && spec.decorV > 0) {
      double stepX = 1.0 / (spec.decorV + 1);
      for (int i = 1; i <= spec.decorV; i++) {
        vPositions.add(stepX * i);
      }
    }

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      final lineStart = _modelToScreen(Offset(glassR.left, yVal));
      final lineEnd = _modelToScreen(Offset(glassR.right, yVal));
      final screenY = lineStart.dy;
      final screenLeft = lineStart.dx;
      final screenRight = lineEnd.dx;

      if ((touchScreen.dy - screenY).abs() < hitRadius &&
          touchScreen.dx >= screenLeft - hitRadius &&
          touchScreen.dx <= screenRight + hitRadius) {
        _setViewState(() {
          _isDraggingDecor = true;
          _draggedDecorZoneId = zoneId;
          _draggedDecorIsHorizontal = true;
          _draggedDecorIndex = i;
        });
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      final lineStart = _modelToScreen(Offset(xVal, glassR.top));
      final lineEnd = _modelToScreen(Offset(xVal, glassR.bottom));
      final screenX = lineStart.dx;
      final screenTop = lineStart.dy;
      final screenBottom = lineEnd.dy;

      if ((touchScreen.dx - screenX).abs() < hitRadius &&
          touchScreen.dy >= screenTop - hitRadius &&
          touchScreen.dy <= screenBottom + hitRadius) {
        _setViewState(() {
          _isDraggingDecor = true;
          _draggedDecorZoneId = zoneId;
          _draggedDecorIsHorizontal = false;
          _draggedDecorIndex = i;
        });
        widget.model.showZoneMenu = false;
        widget.model.activeSubZone = null;
        widget.model.refreshUI();
        return true;
      }
    }

    return false;
  }

  String _getStructureName(GlassStructure s) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    switch (s) {
      case GlassStructure.simple:
        return Localization.translate('عادي', lang);
      case GlassStructure.double:
        return Localization.translate('مزدوج', lang);
      case GlassStructure.closed:
        return Localization.translate('بانو', lang);
    }
  }

  String _getFinishName(GlassFinish f) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String name = '';
    switch (f) {
      case GlassFinish.clair:
        name = 'شفاف';
        break;
      case GlassFinish.stopSol:
        name = 'ستوبسول';
        break;
      case GlassFinish.sable:
        name = 'صابلي';
        break;
      case GlassFinish.delta:
        name = 'دلتا';
        break;
      case GlassFinish.tuC:
        name = 'تيسي';
        break;
      case GlassFinish.nevada:
        name = 'نيفادا';
        break;
      case GlassFinish.cuisine:
        name = 'مطبخ';
        break;
      case GlassFinish.aFleur:
        name = 'مورد';
        break;
      case GlassFinish.paneauSandwitch:
        name = 'بانو';
        break;
      case GlassFinish.resine:
        name = 'ارزين';
        break;
      case GlassFinish.plexyGlass:
        name = 'بليكسي';
        break;
      case GlassFinish.paneauSandwitchDecore:
        name = 'بانو ديكور';
        break;
      case GlassFinish.bardage:
        name = 'بارداش';
        break;
      case GlassFinish.moussa:
        name = 'موسى';
        break;
      case GlassFinish.harari:
        name = 'حراري';
        break;
      case GlassFinish.vitrageArme:
        name = 'زجاج مسلح';
        break;
    }
    return Localization.translate(name, lang);
  }

  String _getClosedColoreName(ClosedGlassColor d) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String name = '';
    switch (d) {
      case ClosedGlassColor.transparent:
        name = 'شفاف';
        break;
      case ClosedGlassColor.white:
        name = 'ابيض';
        break;
      case ClosedGlassColor.grisClair:
        name = 'رمادي فاتح';
        break;
      case ClosedGlassColor.fbmfonce:
        name = 'خشبي داكن';
        break;
      case ClosedGlassColor.grissoris:
        name = 'رمادي داكن';
        break;
      case ClosedGlassColor.black:
        name = 'اسود';
        break;
      case ClosedGlassColor.beige:
        name = 'باج';
        break;
      case ClosedGlassColor.fbmClair:
        name = 'خشبي فاتح';
        break;
      case ClosedGlassColor.opaque:
        name = 'عاتم';
        break;
      case ClosedGlassColor.marberier:
        name = 'رخامي';
        break;
    }
    return Localization.translate(name, lang);
  }

  void _showParcloseSelectorDialog(BuildContext context) async {
    final dbInstance = SqlDatabase();
    final d = await dbInstance.db;
    if (d == null || activeSeriesForSystem == null) return;

    final List<Map<String, dynamic>> res = await d.query(
      'Sections',
      where:
          'series_id = ? AND (type = ? OR type LIKE ? OR name LIKE ? OR TRIM(code) = ?)',
      whereArgs: [
        activeSeriesForSystem!.id,
        'parclose',
        '%parclose%',
        '%باكيت%',
        '514',
      ],
      orderBy: "CASE WHEN TRIM(code) = '514' THEN 0 ELSE 1 END, id",
    );

    // A double glazing pack must only be paired with a parclose that leaves
    // room for a real Intercall. Filter invalid single/small parcloses from
    // this selector so they cannot be chosen after the automatic selection.
    var requiredDoubleThickness = 0.0;
    void considerGlass(GlassSpecification glass) {
      if (glass.structure != GlassStructure.double) return;
      final total = glass.totalThickness(widget.model.allGlassCache);
      if (total > requiredDoubleThickness) requiredDoubleThickness = total;
    }

    for (final zone in widget.model.zones) {
      considerGlass(zone.glass);
      for (final glass in zone.cellGlassSpec.values) {
        considerGlass(glass);
      }
    }
    final simple514 = res
        .where((item) => item['code']?.toString().trim() == '514')
        .toList();
    final availableParcloses = requiredDoubleThickness > 0
        ? res.where((item) {
            final raw = item['max_glass_thickness'];
            final capacity = raw is num
                ? raw.toDouble()
                : double.tryParse(raw?.toString() ?? '');
            return (capacity ?? 0) >=
                (requiredDoubleThickness > 10.0
                    ? requiredDoubleThickness
                    : 10.0);
          }).toList()
        : (simple514.isNotEmpty ? simple514 : res);

    if (!context.mounted) return;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(Localization.translate('Choisir la parclose', lang)),
          content: availableParcloses.isEmpty
              ? Text(
                  Localization.translate(
                    'لا توجد عناصر باكيت زجاج مسجلة لهذه السلسلة في قاعدة البيانات',
                    lang,
                  ),
                )
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableParcloses.length,
                    itemBuilder: (context, index) {
                      final item = availableParcloses[index];
                      final double maxThickness =
                          (item['max_glass_thickness'] as num?)?.toDouble() ??
                          0.0;
                      return ListTile(
                        title: Text('${item['code']} - ${item['name']}'),
                        subtitle: Text(
                          '${Localization.translate('السمك الأقصى للزجاج', lang)}: $maxThickness ${Localization.translate('مم', lang)}',
                        ),
                        trailing: Icon(
                          widget.model.componentOverrides['باكيت الزجاج (Parclose)']?['id'] ==
                                  item['id']
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: Colors.green,
                        ),
                        onTap: () async {
                          final mutableItem = Map<String, dynamic>.from(item);
                          final colorId = widget.model.selectedDbColor?['id'];
                          final double price = await dbInstance.getSectionPrice(
                            item['id'] as int,
                            colorId,
                          );
                          mutableItem['calculated_price'] = price;

                          _setViewState(() {
                            widget
                                    .model
                                    .componentOverrides['باكيت الزجاج (Parclose)'] =
                                mutableItem;
                          });
                          widget.model
                              .fitDoubleGlassIntercallsToSelectedParclose();
                          await widget.model.updateGlassGasket();
                          widget.model.refreshUI();
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
          ],
        );
      },
    );
  }
}
